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

# ---------------------------------------------------------------------------
# Email deliverability (SPF/DKIM) — chống email vào spam / bị giả mạo.
# LƯU Ý: email_spf/email_dkim GHI bản ghi vào DNS của domain → phải qua cổng xác nhận.
# ---------------------------------------------------------------------------

# email_spf <domain> <spf_record> — cài/sửa bản ghi SPF cho domain (ghi DNS).
#   spf_record: chuỗi SPF đầy đủ, vd 'v=spf1 +mx +a ~all' hoặc theo giá trị nhà cung cấp
#   khuyến nghị. KHÔNG tự đoán vì SPF phụ thuộc hạ tầng mail của từng host.
email_spf() {
  local domain="$1" record="$2"
  [ -n "$domain" ] && [ -n "$record" ] \
    || die "email_spf cần <domain> <spf_record>  (vd: 'v=spf1 +mx +a ~all')"
  case "$record" in
    v=spf1*) : ;;
    *) die "SPF record phải bắt đầu bằng 'v=spf1' (nhận: '${record:0:20}...')." ;;
  esac
  log_info "Cài/cập nhật SPF cho $domain: $record"
  cpanel_uapi EmailAuth install_spf_records domain="$domain" record="$record"
}

# email_dkim <domain> — bật DKIM (tạo khóa + ghi bản ghi DNS).
email_dkim() {
  local domain="$1"
  [ -n "$domain" ] || die "email_dkim cần <domain>"
  log_info "Bật DKIM cho $domain"
  cpanel_uapi EmailAuth enable_dkim domain="$domain"
}

# email_deliverability <domain> — báo cáo trạng thái SPF/DKIM đọc TỪ DNS (không ghi).
email_deliverability() {
  local domain="$1" recs
  [ -n "$domain" ] || die "email_deliverability cần <domain>"
  recs="$(cpanel_uapi DNS parse_zone zone="$domain")" \
    || die "Không đọc được zone '$domain' (domain có trên tài khoản?)."
  printf '%s' "$recs" | jq --arg d "$domain" '
    ( [ (.data // [])[] | select(.type=="record" and .record_type=="TXT")
        | { name: (.dname_b64|@base64d), data: ([ .data_b64[]? | @base64d ]|join("")) } ] ) as $txt
    | { domain: $d,
        spf:  ( ( [ $txt[] | select(.data|test("v=spf1")) ] ) as $s
                | { present: ($s|length>0), record: ($s[0].data // null) } ),
        dkim: ( ( [ $txt[] | select(.name|test("_domainkey")) | select(.data|test("v=DKIM1")) ] ) as $k
                | { present: ($k|length>0), selectors: [ $k[].name ] } )
      }'
}

# email_usage — dung lượng đĩa theo từng hộp thư (mailbox).
email_usage() {
  cpanel_uapi Email list_pops_with_disk | jq '{mailboxes: [ .data[]? | {
    email: (.email // "\(.user)@\(.domain)"),
    disk_used_mb: (._diskused // .diskused // null),
    quota_mb: (.diskquota // .quota // null),
    percent: (.diskusedpercent // null)
  } ] }'
}
