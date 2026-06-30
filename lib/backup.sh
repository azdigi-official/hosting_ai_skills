# shellcheck shell=bash
# backup.sh — Sao lưu tài khoản qua cPanel Backup gốc (module Backup).
# Yêu cầu: đã source common.sh + cpanel-api.sh và require_cpanel_config. Cần jq.
#
# LƯU Ý: đây là cPanel Backup tích hợp sẵn (chạy được với token cPanel user).
# JetBackup API KHÔNG dùng được bằng token cPanel user — cần WHM token (xem skill).

# backup_list — gộp backup cPanel-managed (list_backups) + file backup-*.tar.gz trong home.
backup_list() {
  local backups fileman
  backups="$(cpanel_uapi Backup list_backups 2>/dev/null)"
  fileman="$(cpanel_uapi Fileman list_files dir="" 2>/dev/null)"
  # Lưu ý: KHÔNG dùng ${var:-{}} — bash parse sai (default thành '{' + '}' thừa → JSON hỏng).
  [ -n "$backups" ] || backups='{}'
  [ -n "$fileman" ] || fileman='{}'
  jq -n --argjson b "$backups" --argjson f "$fileman" '{
    managed_backups: ($b.data // []),
    homedir_backups: [ ($f.data // [])[]
      | select(.file | test("^backup-.*\\.tar\\.gz$"))
      | { file, size_mb: (((.size|tonumber) / 1048576 * 100 | floor) / 100), mtime } ]
  }'
}

# backup_create [email] — tạo full backup vào thư mục home (chạy nền trên server).
backup_create() {
  local email="${1:-}"
  local args=()
  [ -n "$email" ] && args+=(email="$email")
  log_info "Yêu cầu full backup về home (chạy nền; file backup-*.tar.gz sẽ xuất hiện khi xong)"
  cpanel_uapi Backup fullbackup_to_homedir "${args[@]}"
}

# backup_create_ftp <host> <user> <pass> [port] [rdir] [email] — full backup lên FTP từ xa.
backup_create_ftp() {
  local host="$1" user="$2" pass="$3" port="${4:-21}" rdir="${5:-}" email="${6:-}"
  [ -n "$host" ] && [ -n "$user" ] && [ -n "$pass" ] \
    || die "backup_create_ftp cần <host> <user> <pass> [port] [rdir] [email]"
  local args=(host="$host" username="$user" password="$pass" port="$port")
  [ -n "$rdir" ]  && args+=(rdir="$rdir")
  [ -n "$email" ] && args+=(email="$email")
  log_info "Yêu cầu full backup lên FTP $host (chạy nền)"
  cpanel_uapi Backup fullbackup_to_ftp "${args[@]}"
}
