# shellcheck shell=bash
# metrics.sh — Giám sát sức khỏe tài khoản cPanel.
# Yêu cầu: đã source common.sh + cpanel-api.sh và require_cpanel_config. Cần jq.

# metrics_health — tổng quan disk/bandwidth/MySQL/inode... (StatsBar::get_stats).
metrics_health() {
  local display="${1:-diskusage|bandwidthusage|mysqldiskusage|filesusage|emailaccounts|mysqldatabases|addondomains|subdomains}"
  cpanel_uapi StatsBar get_stats display="$display" \
    | jq '{stats: [ .data[]? | {
        item: .id,
        name: .name,
        used: (.count // .value),
        max: (.max // "∞"),
        units: (.units // ""),
        percent: (.percent // null)
      } ] }'
}

# metrics_resource — CPU/RAM/IO (CloudLinux LVE) qua ResourceUsage::get_usages.
metrics_resource() {
  cpanel_uapi ResourceUsage get_usages \
    | jq '{resources: [ .data[]? | {
        id, description,
        usage: (._count // .usage // null),
        max: (.maximum // null),
        percent: (.percent_used // null)
      } ] }'
}

# metrics_quota — dung lượng đĩa (Quota::get_quota_info).
metrics_quota() {
  cpanel_uapi Quota get_quota_info | pretty_json
}

# metrics_disk_usage — tổng quan dung lượng đĩa: đã dùng/giới hạn/inode + phần email.
metrics_disk_usage() {
  local q email_disk
  q="$(cpanel_uapi Quota get_quota_info)" || die "Không lấy được thông tin quota."
  email_disk="$(cpanel_uapi Email get_main_account_disk_usage 2>/dev/null | jq -r '.data // "?"' 2>/dev/null)"
  printf '%s' "$q" | jq --arg em "${email_disk:-?}" '{
    disk_mb_used:   (.data.megabytes_used),
    disk_mb_limit:  (.data.megabyte_limit),
    disk_mb_remain: (.data.megabytes_remain),
    inodes_used:    (.data.inodes_used),
    email_disk:     $em
  }'
}
