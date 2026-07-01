# shellcheck shell=bash
# php.sh — Quản lý phiên bản PHP theo domain (MultiPHP Manager / CloudLinux PHP Selector).
# Yêu cầu: đã source common.sh + cpanel-api.sh và require_cpanel_config. Cần jq.
#
# CHÍNH SÁCH: skill này CHỈ thao tác với các bản alt-php* (CloudLinux PHP Selector),
# KHÔNG đặt ea-php* (EasyApache) để đồng nhất môi trường CloudLinux. Lệnh đọc (php_list)
# vẫn báo cáo đúng thực tế kể cả khi một domain đang chạy ea-php.

# _php_installed_alt — in ra (mỗi dòng 1 bản) các bản alt-php* đã cài trên server.
_php_installed_alt() {
  cpanel_uapi LangPHP php_get_installed_versions 2>/dev/null \
    | jq -r '.data.versions[]? | select(startswith("alt-php"))' 2>/dev/null
}

# php_versions — liệt kê các bản alt-php* đã cài (đã lọc bỏ ea-php*).
php_versions() {
  cpanel_uapi LangPHP php_get_installed_versions \
    | jq '{alt_php_versions: [ .data.versions[]? | select(startswith("alt-php")) ]}'
}

# php_list — PHP hiện tại của từng domain; đánh dấu domain KHÔNG chạy alt-php.
php_list() {
  cpanel_uapi LangPHP php_get_vhost_versions \
    | jq '{domains: [ .data[]? | {
        domain: .vhost,
        version: .version,
        is_alt_php: (.version | startswith("alt-php")),
        note: (if (.version|startswith("alt-php")) then "" else "KHÔNG phải alt-php (skill không đặt loại này)" end)
      } ]}'
}

# php_set <domain> <alt-phpXX> — đặt PHP cho 1 domain. CHỈ chấp nhận alt-php* đã cài.
php_set() {
  local domain="$1" version="$2"
  [ -n "$domain" ] && [ -n "$version" ] || die "php_set cần <domain> <alt-phpXX>"

  # Chỉ cho phép alt-php* (chính sách CloudLinux). Từ chối ea-php* và định dạng lạ.
  case "$version" in
    alt-php[0-9]*) : ;;
    ea-php*) die "Skill chỉ đặt bản alt-php* (CloudLinux). '$version' là ea-php — bị từ chối." ;;
    *)       die "Phiên bản không hợp lệ: '$version' (định dạng alt-phpXX, vd alt-php82). Xem 'cpanel php:versions'." ;;
  esac

  # Bản phải thực sự đã cài trên server.
  if ! _php_installed_alt | grep -qx "$version"; then
    die "Bản '$version' chưa cài trên server. Xem 'cpanel php:versions'."
  fi

  log_info "Đặt PHP cho $domain → $version"
  cpanel_uapi LangPHP php_set_vhost_versions version="$version" vhost="$domain"
}
