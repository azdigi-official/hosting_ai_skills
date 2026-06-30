# shellcheck shell=bash
# deploy.sh — Orchestration deploy ứng dụng lên hosting cPanel qua API.
# Yêu cầu: đã source common.sh + cpanel-api.sh và require_cpanel_config.

WP_DOWNLOAD_URL="${WP_DOWNLOAD_URL:-https://wordpress.org/latest.zip}"
WP_SALT_URL="${WP_SALT_URL:-https://api.wordpress.org/secret-key/1.1/salt/}"

# ---------------------------------------------------------------------------
# _fileop <op> <sourcefiles> <destfiles> [extra k=v ...]
# Gọi API2 Fileman::fileop (move/extract/...). Paths tính tương đối thư mục home.
# ---------------------------------------------------------------------------
_fileop() {
  local op="$1" src="$2" dest="$3"; shift 3
  cpanel_api2 Fileman fileop op="$op" sourcefiles="$src" destfiles="$dest" "$@"
}

# ---------------------------------------------------------------------------
# deploy_wordpress <docroot> <dbname> <dbuser> <dbpass> [table_prefix]
#   docroot      : thư mục đích tương đối home, ví dụ  public_html  hoặc  public_html/blog
#   dbname/dbuser: tên ngắn (tự ghép tiền tố) hoặc đầy đủ
#   dbpass       : mật khẩu MySQL user
#   table_prefix : tiền tố bảng WP (mặc định wp_)
# ---------------------------------------------------------------------------
deploy_wordpress() {
  local docroot="$1" dbname_in="$2" dbuser_in="$3" dbpass="$4" tprefix="${5:-wp_}"
  [ -n "$docroot" ] && [ -n "$dbname_in" ] && [ -n "$dbuser_in" ] && [ -n "$dbpass" ] \
    || die "deploy_wordpress cần <docroot> <dbname> <dbuser> <dbpass> [table_prefix]"

  require_cmd curl
  local dbname dbuser
  dbname="$(cpanel_mysql_name "$dbname_in")"
  dbuser="$(cpanel_mysql_name "$dbuser_in")"

  local work zip
  work="$(mktemp -d)"; zip="$work/latest.zip"

  # --- 1. Tải WordPress về máy local --------------------------------------
  log_info "Tải WordPress: $WP_DOWNLOAD_URL"
  curl -fsSL "$WP_DOWNLOAD_URL" -o "$zip" || { rm -rf "$work"; die "Tải WordPress thất bại."; }
  log_ok "Đã tải $(du -h "$zip" | cut -f1) → $zip"

  # --- 2. Upload zip lên server -------------------------------------------
  log_info "Upload latest.zip vào $docroot"
  cpanel_upload "$docroot" "$zip" 1 >/dev/null || { rm -rf "$work"; die "Upload thất bại."; }
  log_ok "Đã upload."

  # --- 3. Giải nén trên server --------------------------------------------
  # LƯU Ý: destfiles của fileop tính TƯƠNG ĐỐI thư mục chứa archive. Archive nằm
  # trong $docroot nên destfiles="." để giải nén ngay tại $docroot (tạo wordpress/).
  log_info "Giải nén $docroot/latest.zip"
  [ "$HAS_JQ" -eq 1 ] || { rm -rf "$work"; die "Cần jq cho bước deploy."; }
  _fileop extract "$docroot/latest.zip" "." doubledecode=1 overwrite=1 >/dev/null \
    || { rm -rf "$work"; die "Giải nén thất bại."; }
  log_ok "Đã giải nén (tạo $docroot/wordpress)."

  # --- 4. Di chuyển nội dung wordpress/* lên docroot ----------------------
  # Dùng đường dẫn TUYỆT ĐỐI (fullpath) để fileop move không bị nhập nhằng path.
  log_info "Di chuyển file từ $docroot/wordpress → $docroot"
  local listing src_dir_abs docroot_abs srcpath
  listing="$(cpanel_uapi Fileman list_files dir="$docroot/wordpress")" \
    || { rm -rf "$work"; die "Không liệt kê được $docroot/wordpress (giải nén sai?)."; }
  src_dir_abs="$(printf '%s' "$listing" | jq -r '.data[0].path // empty')"
  [ -n "$src_dir_abs" ] || { rm -rf "$work"; die "Thư mục wordpress rỗng sau giải nén."; }
  docroot_abs="$(dirname "$src_dir_abs")"
  while IFS= read -r srcpath; do
    [ -z "$srcpath" ] && continue
    _fileop move "$srcpath" "$docroot_abs" >/dev/null \
      || log_warn "Không di chuyển được: $srcpath"
  done < <(printf '%s' "$listing" | jq -r '.data[].fullpath')
  log_ok "Đã di chuyển source WordPress."

  # --- 5. Dọn zip + thư mục wordpress rỗng --------------------------------
  cpanel_api2 Fileman fileop op=unlink sourcefiles="$docroot_abs/latest.zip" destfiles="" >/dev/null 2>&1 || true
  cpanel_api2 Fileman fileop op=unlink sourcefiles="$docroot_abs/wordpress" destfiles="" >/dev/null 2>&1 || true

  # --- 5b. Đổi tên index.html mặc định (Apache/LiteSpeed ưu tiên hơn index.php) ---
  local root_listing
  root_listing="$(cpanel_uapi Fileman list_files dir="$docroot" 2>/dev/null)" || true
  if printf '%s' "$root_listing" | jq -e '.data[]?|select(.file=="index.html")' >/dev/null 2>&1; then
    log_info "Đổi tên index.html mặc định để WordPress (index.php) được nạp"
    cpanel_api2 Fileman fileop op=rename \
      sourcefiles="$docroot_abs/index.html" \
      destfiles="$docroot_abs/index.html.default-bak" >/dev/null 2>&1 || log_warn "Không đổi được index.html."
  fi

  # --- 6. Tạo database + user + quyền -------------------------------------
  log_info "Tạo database $dbname + user $dbuser"
  cpanel_uapi Mysql create_database name="$dbname" >/dev/null || log_warn "Database có thể đã tồn tại."
  cpanel_uapi Mysql create_user name="$dbuser" password="$dbpass" >/dev/null || log_warn "User có thể đã tồn tại."
  cpanel_uapi Mysql set_privileges_on_database user="$dbuser" database="$dbname" privileges="ALL PRIVILEGES" >/dev/null \
    || log_warn "Cấp quyền có thể đã có sẵn."
  log_ok "Database sẵn sàng."

  # --- 7. Sinh wp-config.php ----------------------------------------------
  log_info "Lấy salt keys từ WordPress.org"
  local salts wpconfig
  salts="$(curl -fsSL "$WP_SALT_URL" 2>/dev/null)" || salts="// (không lấy được salt — hãy thay thủ công)"
  wpconfig="$work/wp-config.php"
  cat > "$wpconfig" <<PHP
<?php
/** Sinh tự động bởi hosting_ai_skills deploy:wp */
define( 'DB_NAME', '${dbname}' );
define( 'DB_USER', '${dbuser}' );
define( 'DB_PASSWORD', '${dbpass}' );
define( 'DB_HOST', 'localhost' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

${salts}

\$table_prefix = '${tprefix}';

define( 'WP_DEBUG', false );

if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
PHP

  log_info "Ghi wp-config.php vào $docroot"
  cpanel_uapi Fileman save_file_content \
    dir="$docroot" file="wp-config.php" "content@${wpconfig}" >/dev/null \
    || { rm -rf "$work"; die "Ghi wp-config.php thất bại."; }
  log_ok "Đã ghi wp-config.php."

  rm -rf "$work"
  log_ok "DEPLOY HOÀN TẤT. Truy cập website để chạy bước cài đặt WordPress (chọn ngôn ngữ, tạo admin)."
  printf '{"status":1,"docroot":"%s","database":"%s","db_user":"%s"}\n' "$docroot" "$dbname" "$dbuser"
}

# ---------------------------------------------------------------------------
# _remote_dir_abspath <relpath> — in đường dẫn tuyệt đối của một thư mục server.
# (Lấy từ trường .data[0].path của list_files; thư mục phải tồn tại & không rỗng,
#  hoặc suy từ .path của chính nó.)
# ---------------------------------------------------------------------------
_remote_dir_abspath() {
  local rel="$1" listing abs
  listing="$(cpanel_uapi Fileman list_files dir="$rel" 2>/dev/null)" || return 1
  abs="$(printf '%s' "$listing" | jq -r '.data[0].path // empty' 2>/dev/null)"
  printf '%s' "$abs"
}

# ---------------------------------------------------------------------------
# deploy_static <local_path> <docroot>
#   local_path : thư mục (sẽ zip NỘI DUNG) hoặc 1 file .zip có sẵn
#   docroot    : thư mục đích tương đối home (vd public_html/static)
# Vì zip nội dung trực tiếp nên extract destfiles="." là đủ — không cần bước move.
# ---------------------------------------------------------------------------
deploy_static() {
  local src="$1" docroot="$2"
  [ -n "$src" ] && [ -n "$docroot" ] || die "deploy_static cần <local_path> <docroot>"
  require_cmd curl
  [ "$HAS_JQ" -eq 1 ] || die "Cần jq cho deploy_static."

  local work zip cleanup_local=0
  work="$(mktemp -d)"
  if [ -f "$src" ] && [[ "$src" == *.zip ]]; then
    zip="$src"
  elif [ -d "$src" ]; then
    require_cmd zip
    zip="$work/payload.zip"
    log_info "Nén nội dung $src"
    # Loại .git, .DS_Store và .env (không upload secret local; .env ghi riêng trên server).
    ( cd "$src" && zip -rq "$zip" . -x '.git/*' -x '.DS_Store' -x '.env' ) || { rm -rf "$work"; die "Nén thất bại."; }
    cleanup_local=1
  else
    rm -rf "$work"; die "local_path phải là thư mục hoặc file .zip: $src"
  fi
  log_ok "Payload: $(du -h "$zip" | cut -f1)"

  log_info "Upload payload vào $docroot"
  cpanel_upload "$docroot" "$zip" 1 >/dev/null || { rm -rf "$work"; die "Upload thất bại."; }

  local zipbase docroot_abs
  zipbase="$(basename "$zip")"
  log_info "Giải nén tại $docroot"
  _fileop extract "$docroot/$zipbase" "." doubledecode=1 overwrite=1 >/dev/null \
    || { rm -rf "$work"; die "Giải nén thất bại."; }

  docroot_abs="$(_remote_dir_abspath "$docroot")"
  if [ -n "$docroot_abs" ]; then
    cpanel_api2 Fileman fileop op=unlink sourcefiles="$docroot_abs/$zipbase" destfiles="" >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
  log_ok "DEPLOY STATIC HOÀN TẤT → $docroot"
  printf '{"status":1,"docroot":"%s"}\n' "$docroot"
}

# ---------------------------------------------------------------------------
# git_clone <repo_url> <deploy_path> — clone repo qua cPanel VersionControl.
#   deploy_path: thư mục đích tương đối home (phải CHƯA tồn tại hoặc rỗng)
# ---------------------------------------------------------------------------
git_clone() {
  local url="$1" path="$2" name="${3:-}"
  [ -n "$url" ] && [ -n "$path" ] || die "git_clone cần <repo_url> <deploy_path> [name]"
  [ "$HAS_JQ" -eq 1 ] || die "Cần jq cho git_clone."

  # repository_root PHẢI là đường dẫn tuyệt đối. Nếu là tương đối, ghép với home.
  local abspath="$path"
  case "$path" in
    /*) : ;;
    *)
      local home_abs
      home_abs="$(_remote_dir_abspath public_html)"; home_abs="${home_abs%/public_html}"
      [ -n "$home_abs" ] || die "Không xác định được thư mục home."
      abspath="$home_abs/$path"
      ;;
  esac
  [ -z "$name" ] && name="$(basename "$path")"

  log_info "Clone $url → $abspath (name=$name)"
  # source_repository là JSON object {"url":"..."}; repository_root tuyệt đối.
  cpanel_uapi VersionControl create type=git name="$name" \
    repository_root="$abspath" \
    source_repository="{\"url\":\"${url}\"}"
}

# ---------------------------------------------------------------------------
# node_create <app_root> <domain> <app_url> [startup_file] [node_env]
#   Đăng ký một Node.js app qua PassengerApps.
# ---------------------------------------------------------------------------
node_create() {
  local approot="$1" domain="$2" name="$3" startup="${4:-app.js}" envname="${5:-production}"
  [ -n "$approot" ] && [ -n "$domain" ] && [ -n "$name" ] || die "node_create cần <app_root> <domain> <app_name> [startup_file] [node_env]"
  log_info "Tạo Node.js app: name=$name root=$approot domain=$domain startup=$startup"
  # Hàm đúng là register_application; tham số 'domain' (số ít), không phải 'domains'.
  cpanel_uapi PassengerApps register_application \
    name="$name" path="$approot" domain="$domain" deployment_mode=production \
    envvars.NODE_ENV="$envname" startup_file="$startup"
}

# ---------------------------------------------------------------------------
# deploy_laravel <local_app_dir> <app_root_docroot> [app_url]
#   local_app_dir    : thư mục Laravel ĐÃ build local (phải có vendor/)
#   app_root_docroot : thư mục app trên server (tương đối home); web docroot là
#                      <app_root_docroot>/public
#   app_url          : URL công khai (ghi vào APP_URL của .env)
#
# Công thức không-SSH (đã kiểm chứng):
#   - vendor/ build sẵn local (composer install --no-dev), bundle vào zip
#   - APP_KEY sinh local, ghi vào .env trên server (không upload .env local)
#   - DB mặc định SQLite (database/database.sqlite) — pre-migrate LOCAL trước khi deploy
# ---------------------------------------------------------------------------
deploy_laravel() {
  local appdir="$1" docroot="$2" appurl="${3:-}"
  [ -n "$appdir" ] && [ -n "$docroot" ] || die "deploy_laravel cần <local_app_dir> <app_root_docroot> [app_url]"
  [ -d "$appdir" ] || die "Không thấy thư mục app: $appdir"
  [ -d "$appdir/vendor" ] || die "Thiếu vendor/ trong $appdir. Chạy 'composer install --no-dev --optimize-autoloader' trước."
  [ -f "$appdir/artisan" ] || die "$appdir không phải app Laravel (thiếu artisan)."
  [ "$HAS_JQ" -eq 1 ] || die "Cần jq cho deploy_laravel."

  # Cảnh báo nếu chưa pre-migrate SQLite (DB mặc định).
  if [ ! -s "$appdir/database/database.sqlite" ]; then
    log_warn "database/database.sqlite trống/thiếu — nhớ 'touch' + 'php artisan migrate' LOCAL trước nếu dùng SQLite."
  fi

  # APP_KEY: ưu tiên artisan local, fallback openssl.
  local appkey=""
  if command -v php >/dev/null 2>&1; then
    appkey="$(cd "$appdir" && php artisan key:generate --show 2>/dev/null | tr -d '\r')"
  fi
  if [ -z "$appkey" ]; then
    require_cmd openssl
    appkey="base64:$(openssl rand -base64 32)"
  fi
  log_info "APP_KEY đã sinh."

  # 1. Upload + giải nén app (deploy_static loại .env khỏi zip).
  deploy_static "$appdir" "$docroot" >/dev/null || die "Upload app Laravel thất bại."

  # 2. Ghi .env trên server.
  local work envfile
  work="$(mktemp -d)"; envfile="$work/.env"
  cat > "$envfile" <<ENV
APP_NAME=Laravel
APP_ENV=production
APP_KEY=${appkey}
APP_DEBUG=false
APP_URL=${appurl}

LOG_CHANNEL=stack
DB_CONNECTION=sqlite

SESSION_DRIVER=file
CACHE_STORE=file
QUEUE_CONNECTION=sync
ENV
  log_info "Ghi .env vào $docroot"
  cpanel_uapi Fileman save_file_content dir="$docroot" file=".env" "content@${envfile}" >/dev/null \
    || { rm -rf "$work"; die "Ghi .env thất bại."; }
  rm -rf "$work"

  log_ok "DEPLOY LARAVEL HOÀN TẤT → app root: $docroot"
  log_warn "BƯỚC TIẾP THEO (thủ công nếu chưa làm):"
  log_warn "  1. Trỏ document root của domain/subdomain vào: ${docroot}/public"
  log_warn "     vd: ./bin/cpanel subdomain:add app <domain> ${docroot}/public"
  log_warn "  2. Đặt PHP cho vhost >= phiên bản Laravel yêu cầu (vd alt-php83):"
  log_warn "     ./bin/cpanel uapi LangPHP php_set_vhost_versions vhost=<domain> version=alt-php83"
  log_warn "  3. APP_DEBUG đang =false. Bật true tạm khi cần xem lỗi."
  printf '{"status":1,"app_root":"%s","web_docroot":"%s/public"}\n' "$docroot" "$docroot"
}
