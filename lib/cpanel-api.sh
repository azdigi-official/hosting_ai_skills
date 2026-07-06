# shellcheck shell=bash
# cpanel-api.sh — Lớp wrapper curl cho cPanel UAPI và API2 (xác thực bằng API token).
# Yêu cầu: đã source common.sh và gọi require_cpanel_config trước đó.
#
# Tài liệu tham khảo:
#   UAPI : https://api.docs.cpanel.net/cpanel/introduction/
#   API2 : https://api.docs.cpanel.net/guides/quickstart-development-guide/
#
# Xác thực: header  Authorization: cpanel <user>:<token>
# Token tạo trong cPanel > Security > Manage API Tokens (quyền của chính tài khoản hosting).

# ---------------------------------------------------------------------------
# _curl_cpanel <url> [curl-args...]
# Gọi curl với header xác thực chuẩn.
# In ra stdout: <body> rồi một dòng cuối là mã HTTP. Hàm gọi tách dòng cuối ra.
# (Không dùng biến global vì hàm này luôn chạy trong command substitution —
#  biến gán trong subshell không truyền ngược về hàm cha được.)
# ---------------------------------------------------------------------------
_curl_cpanel() {
  local url="$1"; shift

  # Hook test: nếu CPANEL_CURL_MOCK được đặt, trả body giả + mã HTTP giả và KHÔNG gọi
  # mạng. Dùng cho bats (xem test/). CPANEL_CURL_MOCK_CODE mặc định 200.
  if [ -n "${CPANEL_CURL_MOCK:-}" ]; then
    printf '%s\n%s' "$CPANEL_CURL_MOCK" "${CPANEL_CURL_MOCK_CODE:-200}"
    return 0
  fi

  # Token đưa vào FILE cấu hình của curl (quyền 600) thay vì -H trên dòng lệnh, để token
  # KHÔNG lộ qua `ps aux` trên máy chủ dùng chung.
  local body http_code tmp cfg
  tmp="$(mktemp)"; cfg="$(mktemp)"
  chmod 600 "$cfg"
  printf 'header = "Authorization: cpanel %s:%s"\n' "$CPANEL_USER" "$CPANEL_API_TOKEN" > "$cfg"

  local curl_args=(-sS --max-time "${CPANEL_TIMEOUT:-60}" --config "$cfg")
  # Cho phép bỏ qua kiểm tra TLS khi host dùng self-signed cert (đặt CPANEL_INSECURE=1).
  [ -n "${CPANEL_INSECURE:-}" ] && curl_args+=(--insecure)

  http_code="$(curl \
    "${curl_args[@]}" \
    -w '%{http_code}' \
    -o "$tmp" \
    "$@" \
    "$url" 2>/dev/null)" || { rm -f "$tmp" "$cfg"; die "Lỗi kết nối tới $CPANEL_HOST (curl thất bại)."; }

  rm -f "$cfg"
  body="$(cat "$tmp")"; rm -f "$tmp"
  log_debug "HTTP $http_code  URL=$url"
  printf '%s\n%s' "$body" "$http_code"
}

# _split_http <output-of-_curl_cpanel>
# Tách chuỗi trả về thành biến RESP (body) và HTTP_CODE (dòng cuối).
_split_http() {
  local out="$1"
  HTTP_CODE="${out##*$'\n'}"
  RESP="${out%$'\n'*}"
}

# ---------------------------------------------------------------------------
# cpanel_uapi <Module> <function> [key=value ...]
# Gọi một hàm UAPI. In JSON kết quả ra stdout. Trả mã thoát !=0 nếu status=0.
# Ví dụ: cpanel_uapi Mysql create_database name=blog_db
# ---------------------------------------------------------------------------
cpanel_uapi() {
  local module="$1" func="$2"; shift 2
  [ -z "$module" ] || [ -z "$func" ] && die "cpanel_uapi cần <Module> <function>"

  if [ -n "${CPANEL_DRY_RUN:-}" ]; then
    log_warn "[dry-run] UAPI ${module}::${func} $*"
    printf '{"dry_run":true,"api":"uapi","module":"%s","func":"%s"}' "$module" "$func"
    return 0
  fi

  local url="${CPANEL_SCHEME}://${CPANEL_HOST}:${CPANEL_PORT}/execute/${module}/${func}"
  local data_args=(-X POST)
  local kv
  for kv in "$@"; do
    data_args+=(--data-urlencode "$kv")
  done

  local RESP HTTP_CODE resp
  _split_http "$(_curl_cpanel "$url" "${data_args[@]}")"
  resp="$RESP"

  if [ "${HTTP_CODE:0:1}" != "2" ]; then
    log_err "UAPI ${module}::${func} trả HTTP $HTTP_CODE"
    printf '%s\n' "$resp" >&2
    return 1
  fi

  # Kiểm tra trường status của UAPI nếu có jq.
  if [ "$HAS_JQ" -eq 1 ]; then
    local status errmsg
    status="$(printf '%s' "$resp" | jq -r '.status // empty' 2>/dev/null)"
    if [ "$status" = "0" ]; then
      errmsg="$(printf '%s' "$resp" | jq -r '(.errors // [])|join("; ")' 2>/dev/null)"
      log_err "UAPI ${module}::${func} thất bại: ${errmsg:-không rõ lỗi}"
      printf '%s' "$resp"
      return 1
    fi
  fi
  printf '%s' "$resp"
}

# ---------------------------------------------------------------------------
# cpanel_api2 <Module> <function> [key=value ...]
# Gọi một hàm cPanel API2 (json-api). Dùng cho các chức năng chưa có trong UAPI
# (ví dụ AddonDomain::addaddondomain trên cPanel cũ).
# ---------------------------------------------------------------------------
cpanel_api2() {
  local module="$1" func="$2"; shift 2
  [ -z "$module" ] || [ -z "$func" ] && die "cpanel_api2 cần <Module> <function>"

  if [ -n "${CPANEL_DRY_RUN:-}" ]; then
    log_warn "[dry-run] API2 ${module}::${func} $*"
    printf '{"dry_run":true,"api":"api2","module":"%s","func":"%s"}' "$module" "$func"
    return 0
  fi

  local url="${CPANEL_SCHEME}://${CPANEL_HOST}:${CPANEL_PORT}/json-api/cpanel"
  local data_args=(
    -X POST
    --data-urlencode "cpanel_jsonapi_user=${CPANEL_USER}"
    --data-urlencode "cpanel_jsonapi_apiversion=2"
    --data-urlencode "cpanel_jsonapi_module=${module}"
    --data-urlencode "cpanel_jsonapi_func=${func}"
  )
  local kv
  for kv in "$@"; do
    data_args+=(--data-urlencode "$kv")
  done

  local RESP HTTP_CODE resp
  _split_http "$(_curl_cpanel "$url" "${data_args[@]}")"
  resp="$RESP"

  if [ "${HTTP_CODE:0:1}" != "2" ]; then
    log_err "API2 ${module}::${func} trả HTTP $HTTP_CODE"
    printf '%s\n' "$resp" >&2
    return 1
  fi

  if [ "$HAS_JQ" -eq 1 ]; then
    local errmsg
    errmsg="$(printf '%s' "$resp" | jq -r '.cpanelresult.error // empty' 2>/dev/null)"
    if [ -n "$errmsg" ] && [ "$errmsg" != "null" ]; then
      log_err "API2 ${module}::${func} thất bại: $errmsg"
      printf '%s' "$resp"
      return 1
    fi
  fi
  printf '%s' "$resp"
}

# ---------------------------------------------------------------------------
# Tiền tố MySQL: server cPanel BẮT BUỘC database/user mang tiền tố "<user>_".
# UAPI KHÔNG tự thêm (khác giao diện web), nên CLI phải tự ghép.
# Lấy prefix động qua Mysql::get_restrictions, cache trong _MYSQL_PREFIX.
# ---------------------------------------------------------------------------
cpanel_mysql_prefix() {
  if [ -z "${_MYSQL_PREFIX:-}" ]; then
    local out
    out="$(cpanel_uapi Mysql get_restrictions 2>/dev/null)" || true
    if [ "$HAS_JQ" -eq 1 ]; then
      _MYSQL_PREFIX="$(printf '%s' "$out" | jq -r '.data.prefix // empty' 2>/dev/null)"
    fi
    [ -z "${_MYSQL_PREFIX:-}" ] && _MYSQL_PREFIX="${CPANEL_USER}_"
    export _MYSQL_PREFIX
  fi
  printf '%s' "$_MYSQL_PREFIX"
}

# cpanel_mysql_name <name> — ghép tiền tố nếu chưa có. In tên đầy đủ ra stdout.
cpanel_mysql_name() {
  local name="$1" prefix
  prefix="$(cpanel_mysql_prefix)"
  case "$name" in
    "$prefix"*) printf '%s' "$name" ;;
    *)          printf '%s%s' "$prefix" "$name" ;;
  esac
}

# ---------------------------------------------------------------------------
# cpanel_upload <remote_dir> <local_file> [overwrite]
# Upload một file local lên server qua UAPI Fileman::upload_files (multipart).
# ---------------------------------------------------------------------------
cpanel_upload() {
  local dir="$1" localfile="$2" overwrite="${3:-1}"
  [ -f "$localfile" ] || die "Không tìm thấy file local: $localfile"

  if [ -n "${CPANEL_DRY_RUN:-}" ]; then
    log_warn "[dry-run] Upload ${localfile} → ${dir} (overwrite=${overwrite})"
    printf '{"dry_run":true,"api":"upload","dir":"%s"}' "$dir"
    return 0
  fi

  local url="${CPANEL_SCHEME}://${CPANEL_HOST}:${CPANEL_PORT}/execute/Fileman/upload_files"

  local RESP HTTP_CODE resp
  _split_http "$(_curl_cpanel "$url" -X POST \
    -F "dir=${dir}" \
    -F "overwrite=${overwrite}" \
    -F "file-1=@${localfile}")"
  resp="$RESP"

  if [ "${HTTP_CODE:0:1}" != "2" ]; then
    log_err "upload_files trả HTTP $HTTP_CODE"; printf '%s\n' "$resp" >&2; return 1
  fi
  if [ "$HAS_JQ" -eq 1 ]; then
    local status errmsg
    status="$(printf '%s' "$resp" | jq -r '.status // empty' 2>/dev/null)"
    if [ "$status" = "0" ]; then
      errmsg="$(printf '%s' "$resp" | jq -r '(.errors // [])|join("; ")' 2>/dev/null)"
      log_err "upload_files thất bại: ${errmsg:-không rõ}"; printf '%s' "$resp"; return 1
    fi
  fi
  printf '%s' "$resp"
}
