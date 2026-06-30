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
