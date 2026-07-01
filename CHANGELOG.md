# Changelog

Mọi thay đổi đáng chú ý của dự án được ghi ở đây.
Định dạng theo [Keep a Changelog](https://keepachangelog.com/vi/1.1.0/),
và dự án tuân theo [Semantic Versioning](https://semver.org/lang/vi/).

## [Unreleased]

### Added
- Cổng xác nhận trong engine cho thao tác phá hủy (`confirm_destructive`): các lệnh
  xóa dừng lại khi chạy non-interactive nếu thiếu `--yes`/`CPANEL_ASSUME_YES`.
- Cờ toàn cục `--yes`/`-y` (bỏ qua xác nhận sau khi người dùng đồng ý) và `--dry-run`
  (in thao tác API sẽ gọi mà không thực thi).
- Lệnh `cpanel version`.
- Dọn thư mục tạm tập trung (`mk_tmpdir` + một `trap EXIT INT TERM`) — an toàn khi Ctrl+C.

### Fixed
- **Bảo mật:** vá JSON-injection ở `git:clone` (dựng `source_repository` bằng `jq -n --arg`).
- **Bảo mật:** vá command-injection ở `wp:*` — validate slug plugin/theme và chặn ký tự
  đặc biệt của shell ở `wp:cli`.
- Sửa tài liệu trỏ sai `.claude/skills/` → `skills/` trong `AGENTS.md`.

## [0.1.0] - 2026-07-01

### Added
- Bản phát hành đầu: plugin marketplace Claude Code với 12 skill thao tác hosting cPanel
  qua API token (database, domain, deploy, debug, email, SSL, DNS, metrics, FTP, backup,
  WordPress) và engine CLI `bin/cpanel` (UAPI/API2 + escape hatch).
