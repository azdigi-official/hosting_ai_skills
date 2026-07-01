# shellcheck shell=bash
# dns.sh — Quản lý bản ghi DNS qua cPanel UAPI module DNS.
# Yêu cầu: đã source common.sh + cpanel-api.sh và require_cpanel_config. Cần jq.
#
# Ghi chú API (đã kiểm chứng):
#   - DNS::parse_zone trả record với field base64: dname_b64, data_b64[], line_index.
#   - Serial nằm ở SOA record: data_b64[2] (giải base64).
#   - DNS::mass_edit_zone cần zone + serial; 'add' là MỘT object JSON / record;
#     'remove' là line_index. Trả new_serial.

# Lấy serial hiện tại của zone (cho mass_edit_zone).
dns_serial() {
  local zone="$1"
  cpanel_uapi DNS parse_zone zone="$zone" 2>/dev/null \
    | jq -r '.data[] | select(.record_type=="SOA") | .data_b64[2] | @base64d' 2>/dev/null
}

# dns_list <zone> — in JSON các record đã giải mã (line, type, name, ttl, data).
dns_list() {
  local zone="$1" resp
  [ -n "$zone" ] || die "dns_list cần <zone>"
  resp="$(cpanel_uapi DNS parse_zone zone="$zone")" || die "Không đọc được zone '$zone' (zone có tồn tại trên tài khoản?)."
  printf '%s' "$resp" | jq '{zone:"'"$zone"'", records: [ (.data // [])[]
        | select(.type=="record")
        | { line: .line_index,
            type: .record_type,
            name: (.dname_b64 | @base64d),
            ttl,
            data: [ .data_b64[]? | @base64d ] } ] }'
}

# dns_add <zone> <type> <name> <ttl> <data...> — thêm 1 record.
#   data... : một hoặc nhiều phần tử (vd MX cần "10" "mail.example.com.").
dns_add() {
  local zone="$1" rtype="$2" name="$3" ttl="$4"; shift 4
  [ -n "$zone" ] && [ -n "$rtype" ] && [ -n "$name" ] && [ "$#" -ge 1 ] \
    || die "dns_add cần <zone> <type> <name> <ttl> <data...>"
  # Quy ước: '@' = gốc zone. cPanel cần FQDN có dấu chấm cuối, không nhận '@'.
  [ "$name" = "@" ] && name="${zone}."

  local serial
  serial="$(dns_serial "$zone")"
  [ -n "$serial" ] || die "Không lấy được serial của zone $zone."

  local data_json add_json
  data_json="$(printf '%s\n' "$@" | jq -R . | jq -sc .)"
  add_json="$(jq -nc --arg dn "$name" --arg rt "$rtype" --argjson ttl "$ttl" \
    --argjson data "$data_json" '{dname:$dn, record_type:$rt, ttl:$ttl, data:$data}')"

  log_info "Thêm $rtype $name (ttl=$ttl) vào $zone"
  cpanel_uapi DNS mass_edit_zone zone="$zone" serial="$serial" add="$add_json"
}

# dns_remove <zone> <line_index> — xóa record theo line (lấy từ dns_list).
dns_remove() {
  local zone="$1" line="$2"
  [ -n "$zone" ] && [ -n "$line" ] || die "dns_remove cần <zone> <line_index>"
  local serial
  serial="$(dns_serial "$zone")"
  [ -n "$serial" ] || die "Không lấy được serial của zone $zone."
  log_info "Xóa record line=$line khỏi $zone"
  cpanel_uapi DNS mass_edit_zone zone="$zone" serial="$serial" remove="$line"
}

# ---------------------------------------------------------------------------
# DNSSEC — ký số zone để chống giả mạo DNS. Sau khi bật, phải khai báo DS record
# tại NHÀ ĐĂNG KÝ domain (registrar) thì mới có hiệu lực. enable/disable GHI zone.
# ---------------------------------------------------------------------------

# dnssec_status <domain> — DNSSEC đã bật chưa + DS record (đọc).
dnssec_status() {
  local domain="$1"
  [ -n "$domain" ] || die "dnssec_status cần <domain>"
  cpanel_uapi DNSSEC fetch_ds_records domain="$domain" \
    | jq --arg d "$domain" '{
        domain: $d,
        enabled: (((.data[$d] // {}) | length) > 0),
        ds_records: (.data[$d] // {})
      }'
}

# dnssec_ds <domain> — in DS record để khai báo tại nhà đăng ký domain.
dnssec_ds() {
  local domain="$1"
  [ -n "$domain" ] || die "dnssec_ds cần <domain>"
  cpanel_uapi DNSSEC fetch_ds_records domain="$domain" | jq '.data'
}

# dnssec_enable <domain> — bật DNSSEC (tạo khóa + ký zone).
dnssec_enable() {
  local domain="$1"
  [ -n "$domain" ] || die "dnssec_enable cần <domain>"
  log_info "Bật DNSSEC cho $domain (nhớ thêm DS record tại nhà đăng ký domain sau đó)"
  cpanel_uapi DNSSEC enable_dnssec domain="$domain"
}

# dnssec_disable <domain> — tắt DNSSEC (xóa khóa).
dnssec_disable() {
  local domain="$1"
  [ -n "$domain" ] || die "dnssec_disable cần <domain>"
  log_info "Tắt DNSSEC cho $domain"
  cpanel_uapi DNSSEC disable_dnssec domain="$domain"
}
