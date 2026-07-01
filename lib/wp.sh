# shellcheck shell=bash
# wp.sh — Quản lý WordPress trên hosting cPanel KHÔNG cần SSH.
# Yêu cầu: đã source common.sh + cpanel-api.sh và require_cpanel_config.
#
# Bối cảnh: toolkit chỉ có API token (không SSH). WP-CLI thường KHÔNG cài sẵn.
# Giải pháp đã kiểm chứng:
#   1. Tải wp-cli.phar về $HOME của server (một lần).
#   2. Chạy lệnh wp-cli bằng ĐÚNG PHP-CLI của domain (không phải php mặc định 7.4)
#      thông qua một CRON một-lần (cách thực thi shell duy nhất khi không có SSH).
#   3. Ghi output ra file log, poll đọc qua Fileman, rồi xóa cron.
#
# BẪY QUAN TRỌNG: trong crontab ký tự '%' là đặc biệt (bị hiểu là xuống dòng) →
# lệnh chứa '%' sẽ ÂM THẦM không chạy. Mọi runid/timestamp được sinh LOCAL (ở các
# hàm dưới đây) rồi nhúng thành chuỗi, nên chuỗi cron gửi lên server KHÔNG có '%'.

WP_CLI_PHAR_URL="${WP_CLI_PHAR_URL:-https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar}"
WP_WAIT_SECS="${WP_WAIT_SECS:-480}"      # tổng thời gian chờ cron chạy + xong (giây)
WP_POLL_INTERVAL="${WP_POLL_INTERVAL:-8}"

# ---------------------------------------------------------------------------
# _wp_need_jq — wp.sh phụ thuộc jq để parse log/JSON.
# ---------------------------------------------------------------------------
_wp_need_jq() { [ "$HAS_JQ" -eq 1 ] || die "Cần 'jq' cho các lệnh wp:* (parse JSON)."; }

# ---------------------------------------------------------------------------
# _wp_home_abs — in đường dẫn tuyệt đối thư mục home trên server (vd /home/user).
# ---------------------------------------------------------------------------
_wp_home_abs() {
  local abs
  abs="$(_remote_dir_abspath public_html 2>/dev/null)"
  abs="${abs%/public_html}"
  [ -n "$abs" ] || die "Không xác định được thư mục home trên server."
  printf '%s' "$abs"
}

# ---------------------------------------------------------------------------
# _wp_php_binary — chọn đường dẫn PHP-CLI khớp version domain.
#   Ưu tiên: WP_PHP (full path) > WP_PHP_VERSION (vd ea-php82) > version của main domain.
#   Cron mặc định dùng PHP 7.4 — KHÔNG khớp site, nên phải chỉ đúng binary.
# ---------------------------------------------------------------------------
_wp_php_binary() {
  if [ -n "${WP_PHP:-}" ]; then printf '%s' "$WP_PHP"; return; fi
  local ver="${WP_PHP_VERSION:-}"
  if [ -z "$ver" ]; then
    local main
    main="$(cpanel_uapi DomainInfo list_domains 2>/dev/null | jq -r '.data.main_domain // empty' 2>/dev/null)"
    ver="$(cpanel_uapi LangPHP php_get_vhost_versions 2>/dev/null \
            | jq -r --arg d "$main" '.data[]? | select(.vhost==$d) | .version' 2>/dev/null | head -1)"
  fi
  case "$ver" in
    ea-php*)  printf '/opt/cpanel/%s/root/usr/bin/php' "$ver" ;;
    alt-php*) printf '/opt/alt/php%s/usr/bin/php' "${ver#alt-php}" ;;
    *)        printf 'php' ;;  # fallback: PATH (thường là 7.4)
  esac
}

# ---------------------------------------------------------------------------
# _wp_runid — sinh mã chạy duy nhất (LOCAL, không chứa '%').
# ---------------------------------------------------------------------------
_wp_runid() { printf '%s-%s' "$(date +%Y%m%d-%H%M%S)" "$$"; }

# ---------------------------------------------------------------------------
# _wp_exec <docroot> <inner_script>
#   Chạy <inner_script> trên server qua cron một-lần. Bên trong script có sẵn:
#     $WP   → "<php> $HOME/wp-cli.phar"  (đã trỏ docroot, đã có wp-cli.phar)
#   Trả nội dung log (stdout của script) ra stdout. Tự dọn cron + sentinel + log.
# ---------------------------------------------------------------------------
_wp_exec() {
  local docroot="$1" inner="$2"
  [ -n "$docroot" ] && [ -n "$inner" ] || die "_wp_exec cần <docroot> <inner_script>"
  _wp_need_jq

  local phpbin runid home_abs logfile sentinel marker
  phpbin="$(_wp_php_binary)"
  runid="$(_wp_runid)"
  home_abs="$(_wp_home_abs)"
  logfile=".wpcli-${runid}.log"
  sentinel=".wpcli-${runid}.done"
  marker="=== WPCLI_DONE ${runid} ==="

  log_info "PHP-CLI: ${phpbin}"
  log_info "docroot: ${docroot}  | runid: ${runid}"

  # Chuỗi cron: KHÔNG được chứa '%'. Tất cả đường dẫn dùng $HOME (giãn trên server).
  # Guard chạy-một-lần bằng sentinel. wp-cli.phar tải nếu thiếu.
  local cmd
  cmd="if [ -f \$HOME/${sentinel} ]; then exit 0; fi; touch \$HOME/${sentinel}; "
  cmd+="PHP='${phpbin}'; [ -x \"\$PHP\" ] || PHP=php; "
  cmd+="if [ ! -s \$HOME/wp-cli.phar ]; then curl -fsSL -o \$HOME/wp-cli.phar '${WP_CLI_PHAR_URL}' || echo 'WPCLI_PHAR_DOWNLOAD_FAILED'; fi; "
  cmd+="WP=\"\$PHP \$HOME/wp-cli.phar\"; "
  cmd+="cd \$HOME/${docroot} 2>/dev/null || cd \$HOME; "
  cmd+="{ ${inner} echo '${marker}'; } > \$HOME/${logfile} 2>&1"

  case "$cmd" in
    *%*) die "Lỗi nội bộ: chuỗi cron chứa ký tự '%' (sẽ không chạy). Hủy." ;;
  esac

  # Cài cron chạy mỗi phút (sẽ tự thoát sau lần đầu nhờ sentinel).
  local add_out linekey
  add_out="$(cpanel_api2 Cron add_line minute='*' hour='*' day='*' month='*' weekday='*' command="$cmd")" \
    || die "Không thêm được cron để chạy wp-cli."
  linekey="$(printf '%s' "$add_out" | jq -r '.cpanelresult.data[0].linekey // empty' 2>/dev/null || true)"
  log_info "Đã cài cron (linekey=${linekey:-?}). Chờ server chạy (host có thể trễ vài phút)..."

  # Poll log đến khi thấy marker hoặc hết thời gian.
  # LƯU Ý set -e: file log chưa tồn tại ở các vòng đầu → cpanel_uapi trả non-zero.
  # Phải '|| true' để phép gán không làm thoát script.
  local waited=0 content found=0
  while [ "$waited" -lt "$WP_WAIT_SECS" ]; do
    content="$(cpanel_uapi Fileman get_file_content dir="$home_abs" file="$logfile" 2>/dev/null \
               | jq -r '.data.content // empty' 2>/dev/null || true)"
    if printf '%s' "$content" | grep -qF "$marker"; then found=1; break; fi
    sleep "$WP_POLL_INTERVAL"; waited=$((waited + WP_POLL_INTERVAL))
  done

  # Dọn dẹp: xóa cron + sentinel + log (giữ wp-cli.phar để dùng lại).
  [ -n "$linekey" ] && cpanel_api2 Cron remove_line linekey="$linekey" >/dev/null 2>&1 || true
  cpanel_api2 Fileman fileop op=unlink sourcefiles="$home_abs/$sentinel" destfiles="" >/dev/null 2>&1 || true

  if [ "$found" -ne 1 ]; then
    log_err "Hết thời gian chờ (${WP_WAIT_SECS}s) mà cron chưa hoàn tất. Output tạm:"
    printf '%s\n' "${content:-<rỗng>}" >&2
    cpanel_api2 Fileman fileop op=unlink sourcefiles="$home_abs/$logfile" destfiles="" >/dev/null 2>&1 || true
    return 1
  fi

  # In output (bỏ dòng marker) ra stdout.
  printf '%s\n' "$content" | grep -vF "$marker"
  cpanel_api2 Fileman fileop op=unlink sourcefiles="$home_abs/$logfile" destfiles="" >/dev/null 2>&1 || true
  log_ok "Hoàn tất."
}

# ---------------------------------------------------------------------------
# wp_status <docroot> — version core, bản cập nhật core/plugin/theme đang chờ.
# ---------------------------------------------------------------------------
wp_status() {
  local docroot="${1:-public_html}"
  local inner
  inner="echo '=== CORE VERSION ==='; \$WP core version --skip-plugins --skip-themes; "
  inner+="echo '=== CORE UPDATE ==='; \$WP core check-update --skip-plugins --skip-themes; "
  inner+="echo '=== PLUGINS (có bản mới) ==='; \$WP plugin list --update=available --fields=name,status,version,update_version --skip-plugins --skip-themes; "
  inner+="echo '=== THEMES (có bản mới) ==='; \$WP theme list --update=available --fields=name,status,version,update_version --skip-plugins --skip-themes; "
  _wp_exec "$docroot" "$inner"
}

# ---------------------------------------------------------------------------
# wp_backup <docroot> — export DB + nén wp-content/plugins & themes vào
#   ~/backup_pre_update/. Trả về danh sách file backup.
# ---------------------------------------------------------------------------
wp_backup() {
  local docroot="${1:-public_html}" ts
  ts="$(_wp_runid)"
  local inner
  inner="B=\$HOME/backup_pre_update; mkdir -p \$B; "
  inner+="echo '=== DB EXPORT ==='; \$WP db export \$B/db-${ts}.sql --skip-plugins --skip-themes; "
  inner+="echo '=== ARCHIVE plugins+themes ==='; tar czf \$B/code-${ts}.tar.gz -C \$HOME/${docroot} wp-content/plugins wp-content/themes; "
  inner+="echo '=== BACKUP FILES ==='; ls -la \$B; "
  _wp_exec "$docroot" "$inner"
}

# ---------------------------------------------------------------------------
# wp_update <docroot> <scope> [slugs...]
#   scope: core | plugins | themes | all
#   slugs: (chỉ với plugins/themes) danh sách slug cụ thể; bỏ trống = tất cả.
#   Tự BACKUP trước (DB + plugins/themes) trừ khi WP_SKIP_BACKUP=1.
# ---------------------------------------------------------------------------
wp_update() {
  local docroot="$1" scope="$2"; shift 2 || true
  [ -n "$docroot" ] && [ -n "$scope" ] || die "wp_update cần <docroot> <scope> [slugs...]"
  # Chuỗi slug được nhúng vào lệnh chạy trên server → chỉ cho phép ký tự slug hợp lệ
  # (chống command injection qua cron). Slug WordPress: chữ, số, '.', '_', '-'.
  local _s
  for _s in "$@"; do
    case "$_s" in
      *[!A-Za-z0-9._-]*) die "Slug không hợp lệ: '$_s' (chỉ cho phép chữ, số, . _ -)" ;;
    esac
  done
  local slugs="$*" ts
  ts="$(_wp_runid)"

  local inner=""
  if [ -z "${WP_SKIP_BACKUP:-}" ]; then
    inner+="echo '=== BACKUP ==='; B=\$HOME/backup_pre_update; mkdir -p \$B; "
    inner+="\$WP db export \$B/db-${ts}.sql --skip-plugins --skip-themes; "
    inner+="tar czf \$B/code-${ts}.tar.gz -C \$HOME/${docroot} wp-content/plugins wp-content/themes; "
    inner+="echo 'backup: '; ls -la \$B; "
  fi

  case "$scope" in
    core)
      inner+="echo '=== UPDATE CORE ==='; \$WP core update; \$WP core update-db --skip-plugins --skip-themes; "
      ;;
    plugins)
      if [ -n "$slugs" ]; then
        inner+="echo '=== UPDATE PLUGINS (${slugs}) ==='; \$WP plugin update ${slugs}; "
      else
        inner+="echo '=== UPDATE PLUGINS (tất cả) ==='; \$WP plugin update --all; "
      fi
      ;;
    themes)
      if [ -n "$slugs" ]; then
        inner+="echo '=== UPDATE THEMES (${slugs}) ==='; \$WP theme update ${slugs}; "
      else
        inner+="echo '=== UPDATE THEMES (tất cả) ==='; \$WP theme update --all; "
      fi
      ;;
    all)
      inner+="echo '=== UPDATE CORE ==='; \$WP core update; \$WP core update-db --skip-plugins --skip-themes; "
      inner+="echo '=== UPDATE PLUGINS ==='; \$WP plugin update --all; "
      inner+="echo '=== UPDATE THEMES ==='; \$WP theme update --all; "
      ;;
    *) die "scope không hợp lệ: $scope (dùng core|plugins|themes|all)" ;;
  esac

  inner+="echo '=== POST STATE ==='; \$WP core version --skip-plugins --skip-themes; "
  inner+="\$WP plugin list --update=available --fields=name,version,update_version --skip-plugins --skip-themes; "
  inner+="\$WP theme list --update=available --fields=name,version,update_version --skip-plugins --skip-themes; "
  _wp_exec "$docroot" "$inner"
}

# ---------------------------------------------------------------------------
# wp_cli <docroot> <raw wp args...> — escape hatch: chạy bất kỳ lệnh wp-cli nào.
#   Ví dụ: wp_cli public_html plugin list
#          wp_cli public_html option get siteurl
# ---------------------------------------------------------------------------
wp_cli() {
  local docroot="$1"; shift || true
  [ -n "$docroot" ] && [ $# -ge 1 ] || die "wp_cli cần <docroot> <wp args...>"
  # Tham số được nhúng thẳng vào lệnh shell chạy qua cron. Chặn ký tự đặc biệt để
  # tránh command injection: '%' (bẫy cron) + metachar shell. Lệnh cần payload phức
  # tạp (quote/JSON/biến) KHÔNG chạy được qua đường cron này — đây là giới hạn có chủ đích.
  case "$*" in
    *%*)                 die "Tham số chứa '%' — không hỗ trợ qua cron. Dùng cách khác." ;;
    *[\;\|\&\$\`\<\>\(\)\'\"]*) die "Tham số chứa ký tự đặc biệt (; | & \$ \` < > ( ) ' \") — không hỗ trợ qua cron (chống injection)." ;;
  esac
  _wp_exec "$docroot" "echo '=== wp $* ==='; \$WP $*; "
}
