# shellcheck shell=bash
# email-ssl.sh — Helper cho thao tác Email và SSL trên cPanel.
# Yêu cầu: đã source common.sh + cpanel-api.sh và require_cpanel_config.

# ---------------------------------------------------------------------------
# _email_split <addr> — tách "user@domain" thành 2 biến EMAIL_LOCAL, EMAIL_DOMAIN.
# ---------------------------------------------------------------------------
_email_split() {
  local addr="$1"
  # EMAIL_LOCAL/EMAIL_DOMAIN được đọc ở bin/cpanel (cross-file) — không phải biến chết.
  # shellcheck disable=SC2034
  case "$addr" in
    *@*) EMAIL_LOCAL="${addr%@*}"; EMAIL_DOMAIN="${addr#*@}" ;;
    *)   die "Địa chỉ email phải dạng user@domain: $addr" ;;
  esac
}

# ---------------------------------------------------------------------------
# ssl_install <domain> <cert_file> <key_file> [cabundle_file]
#   Cài chứng chỉ SSL do người dùng cung cấp (đọc file local, gửi nội dung qua API).
#   Với Let's Encrypt miễn phí, dùng ssl:autossl thay vì lệnh này.
# ---------------------------------------------------------------------------
ssl_install() {
  local domain="$1" certf="$2" keyf="$3" caf="${4:-}"
  [ -n "$domain" ] && [ -n "$certf" ] && [ -n "$keyf" ] || die "ssl_install cần <domain> <cert_file> <key_file> [cabundle_file]"
  [ -f "$certf" ] || die "Không thấy cert file: $certf"
  [ -f "$keyf" ]  || die "Không thấy key file: $keyf"

  local args=(domain="$domain" "cert@${certf}" "key@${keyf}")
  if [ -n "$caf" ]; then
    [ -f "$caf" ] || die "Không thấy cabundle file: $caf"
    args+=("cabundle@${caf}")
  fi
  log_info "Cài SSL cho $domain"
  cpanel_uapi SSL install_ssl "${args[@]}"
}
