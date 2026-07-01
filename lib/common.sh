# shellcheck shell=bash
# common.sh — Tiện ích dùng chung cho toolkit cPanel/DirectAdmin.
# Nạp file này bằng: source "$(dirname "$0")/../lib/common.sh"
#
# Trách nhiệm:
#   - Tìm gốc dự án (REPO_ROOT)
#   - Nạp cấu hình từ .env
#   - Kiểm tra phụ thuộc (curl, jq)
#   - Hàm log, lỗi, và in JSON đẹp

set -o pipefail

# ---------------------------------------------------------------------------
# Xác định gốc dự án (thư mục chứa bin/ và lib/)
# ---------------------------------------------------------------------------
if [ -z "${REPO_ROOT:-}" ]; then
  _this_file="${BASH_SOURCE[0]:-$0}"
  REPO_ROOT="$(cd "$(dirname "$_this_file")/.." && pwd)"
fi
export REPO_ROOT

# ---------------------------------------------------------------------------
# Màu sắc / logging (ghi ra stderr để không lẫn vào output JSON ở stdout)
# ---------------------------------------------------------------------------
if [ -t 2 ]; then
  _C_RED=$'\033[0;31m'; _C_GRN=$'\033[0;32m'; _C_YLW=$'\033[0;33m'
  _C_BLU=$'\033[0;34m'; _C_DIM=$'\033[2m'; _C_RST=$'\033[0m'
else
  _C_RED=''; _C_GRN=''; _C_YLW=''; _C_BLU=''; _C_DIM=''; _C_RST=''
fi

log_info()  { printf '%s[info]%s %s\n'  "$_C_BLU" "$_C_RST" "$*" >&2; }
log_ok()    { printf '%s[ ok ]%s %s\n'  "$_C_GRN" "$_C_RST" "$*" >&2; }
log_warn()  { printf '%s[warn]%s %s\n'  "$_C_YLW" "$_C_RST" "$*" >&2; }
log_err()   { printf '%s[fail]%s %s\n'  "$_C_RED" "$_C_RST" "$*" >&2; }
log_debug() { [ -n "${CPANEL_DEBUG:-}" ] && printf '%s[dbg ] %s%s\n' "$_C_DIM" "$*" "$_C_RST" >&2; return 0; }

die() { log_err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Quản lý thư mục tạm: đăng ký tập trung + MỘT trap dọn dẹp duy nhất.
# Tránh bẫy trap RETURN lồng nhau (deploy_laravel gọi deploy_static). Mọi hàm
# tạo thư mục tạm nên dùng mk_tmpdir để được tự dọn kể cả khi lỗi/Ctrl+C.
# ---------------------------------------------------------------------------
_TMP_DIRS=()
mk_tmpdir() {
  local d
  d="$(mktemp -d)" || die "Không tạo được thư mục tạm."
  _TMP_DIRS+=("$d")
  printf '%s' "$d"
}
_cleanup_tmps() {
  local d
  for d in ${_TMP_DIRS[@]+"${_TMP_DIRS[@]}"}; do
    [ -n "$d" ] && rm -rf "$d"
  done
}
trap _cleanup_tmps EXIT INT TERM

# ---------------------------------------------------------------------------
# confirm_destructive <mô tả> — cổng xác nhận cho thao tác PHÁ HỦY (không hoàn tác).
#   - CPANEL_DRY_RUN=1               → bỏ qua (chỉ mô phỏng, không thực thi thật).
#   - CPANEL_ASSUME_YES=1 / --yes    → chạy luôn (dùng sau khi người dùng đã đồng ý).
#   - stdin là TTY                   → hỏi trực tiếp, yêu cầu gõ đúng "yes".
#   - non-interactive & không có yes → DỪNG với hướng dẫn (an toàn mặc định cho AI).
# ---------------------------------------------------------------------------
confirm_destructive() {
  local what="$1"
  [ -n "${CPANEL_DRY_RUN:-}" ] && return 0
  if [ -n "${CPANEL_ASSUME_YES:-}" ]; then
    log_warn "Xác nhận tự động (--yes): $what"
    return 0
  fi
  if [ -t 0 ]; then
    printf '%s[warn]%s %s\n' "$_C_YLW" "$_C_RST" "$what" >&2
    printf '  Gõ "yes" để xác nhận (KHÔNG hoàn tác): ' >&2
    local ans; IFS= read -r ans || ans=""
    [ "$ans" = "yes" ] && return 0
    die "Đã hủy (không nhận được 'yes')."
  fi
  die "Thao tác phá hủy cần xác nhận: $what — thêm cờ --yes (sau khi người dùng đồng ý) hoặc đặt CPANEL_ASSUME_YES=1."
}

# ---------------------------------------------------------------------------
# Kiểm tra phụ thuộc
# ---------------------------------------------------------------------------
require_cmd() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Thiếu lệnh '$cmd'. Vui lòng cài đặt trước khi tiếp tục."
  done
}

# jq là tùy chọn nhưng được khuyến nghị mạnh để parse JSON.
HAS_JQ=0
if command -v jq >/dev/null 2>&1; then HAS_JQ=1; fi

# In JSON đẹp nếu có jq, ngược lại in thô.
pretty_json() {
  if [ "$HAS_JQ" -eq 1 ]; then jq . 2>/dev/null || cat; else cat; fi
}

# ---------------------------------------------------------------------------
# Nạp cấu hình từ .env
# Thứ tự ưu tiên (dùng file ĐẦU TIÊN tồn tại rồi dừng):
#   1. biến môi trường sẵn có (không bị ghi đè)
#   2. $CPANEL_ENV_FILE        — chỉ định tường minh
#   3. $PWD/.env               — .env RIÊNG của website/dự án đang làm việc
#   4. $REPO_ROOT/.env         — khi chạy trực tiếp trong repo (dev)
#   5. $HOME/.cpanel-ai.env    — fallback dùng chung mọi project
# ---------------------------------------------------------------------------
load_env() {
  local env_file
  for env_file in "${CPANEL_ENV_FILE:-}" "$PWD/.env" "$REPO_ROOT/.env" "$HOME/.cpanel-ai.env"; do
    [ -z "$env_file" ] && continue
    if [ -f "$env_file" ]; then
      log_debug "Nạp cấu hình từ $env_file"
      set -a
      # shellcheck disable=SC1090
      . "$env_file"
      set +a
      return 0
    fi
  done
  log_debug "Không tìm thấy file .env, dùng biến môi trường hiện có."
}

# Bảo đảm các biến cPanel bắt buộc đã có. Gọi sau load_env.
require_cpanel_config() {
  load_env
  : "${CPANEL_HOST:?Chưa cấu hình CPANEL_HOST (xem .env.example)}"
  : "${CPANEL_USER:?Chưa cấu hình CPANEL_USER (xem .env.example)}"
  : "${CPANEL_API_TOKEN:?Chưa cấu hình CPANEL_API_TOKEN (xem .env.example)}"
  : "${CPANEL_PORT:=2083}"
  : "${CPANEL_SCHEME:=https}"
  export CPANEL_HOST CPANEL_USER CPANEL_API_TOKEN CPANEL_PORT CPANEL_SCHEME
}
