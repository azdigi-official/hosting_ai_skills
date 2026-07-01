# shellcheck shell=bash
# security.sh — Trạng thái bảo mật tài khoản: 2FA và ModSecurity (WAF) theo domain.
# Yêu cầu: đã source common.sh + cpanel-api.sh và require_cpanel_config. Cần jq.
#
# LƯU Ý: đây là các hàm CHỈ ĐỌC. Bật 2FA cần quy trình tương tác (quét QR), và bật/tắt
# ModSecurity theo domain KHÔNG có trong UAPI người dùng trên nhiều server — nên skill
# chỉ báo cáo trạng thái, không đổi.

# security_2fa_status — 2FA của tài khoản cPanel đã bật chưa.
security_2fa_status() {
  cpanel_uapi TwoFactorAuth get_user_configuration \
    | jq '{two_factor_auth_enabled: (((.data.is_enabled // 0) | tonumber?) == 1)}'
}

# security_modsec_status — trạng thái ModSecurity (WAF) theo từng domain.
security_modsec_status() {
  cpanel_uapi ModSecurity list_domains \
    | jq '{domains: [ .data[]? | {
        domain,
        type,
        modsecurity_enabled: (((.enabled // 0) | tonumber?) == 1)
      } ] }'
}
