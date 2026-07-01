# Changelog

Mọi thay đổi đáng chú ý của dự án được ghi ở đây.
Định dạng theo [Keep a Changelog](https://keepachangelog.com/vi/1.1.0/),
và dự án tuân theo [Semantic Versioning](https://semver.org/lang/vi/).

## [Unreleased]

### Added
- **Quản lý PHP theo domain** (`php:versions`, `php:list`, `php:set`) qua MultiPHP —
  skill `cpanel-php`. Chính sách CHỈ dùng bản `alt-php*` (CloudLinux PHP Selector),
  từ chối `ea-php*`. `php:set` là thao tác có ảnh hưởng nên qua cổng `--yes`.
- **`file:chmod <path> <mode>`** — đổi quyền file (sửa lỗi 403/500 sau restore/malware),
  qua cổng `--yes`.
- **Email deliverability:** `email:deliverability` (đọc trạng thái SPF/DKIM từ DNS),
  `email:spf <domain> <record>` và `email:dkim <domain>` (ghi DNS, qua cổng `--yes`).
- **`email:usage`** (dung lượng theo hộp thư) và **`metrics:disk-usage`** (tổng quan đĩa).
- Ghi chú: autoresponder phụ thuộc feature của gói (một số gói tắt sẵn) nên chưa thêm lệnh riêng.
- **Tier 2 — bảo mật:**
  - **DNSSEC:** `dns:dnssec-status/ds` (đọc) và `dns:dnssec-enable/disable` (ghi zone, qua `--yes`).
  - **Remote MySQL:** `db:remote-add/delete <host>` (ghi quyền, qua `--yes`).
  - **Security (đọc):** `security:2fa-status`, `security:modsec-status` — skill `cpanel-security`.
  - Bỏ khỏi pass: hotlink protection & SSL nâng cao (API UAPI không rõ ràng/rủi ro);
    bật-tắt ModSecurity theo domain (không có trong UAPI người dùng trên server này).
- Cổng xác nhận trong engine cho thao tác phá hủy (`confirm_destructive`): các lệnh
  xóa dừng lại khi chạy non-interactive nếu thiếu `--yes`/`CPANEL_ASSUME_YES`.
- Cờ toàn cục `--yes`/`-y` (bỏ qua xác nhận sau khi người dùng đồng ý) và `--dry-run`
  (in thao tác API sẽ gọi mà không thực thi).
- Lệnh `cpanel version`.
- Dọn thư mục tạm tập trung (`mk_tmpdir` + một `trap EXIT INT TERM`) — an toàn khi Ctrl+C.
- CI GitHub Actions: `bash -n` + ShellCheck + bats.
- Bộ test bats (`test/`) chạy không cần mạng qua hook `CPANEL_CURL_MOCK`.
- `require_cmd jq` — jq là bắt buộc (báo lỗi rõ thay vì chạy suy giảm âm thầm).

### Changed
- **Bảo mật:** token gửi qua file cấu hình của curl (`--config`, quyền 600) thay vì `-H`
  trên dòng lệnh → không lộ qua `ps aux` trên máy chủ dùng chung.
- `wp-cli.phar`: kiểm tra file non-empty và báo `WPCLI_PHAR_DOWNLOAD_FAILED` khi tải hỏng
  (thay vì `|| true` che lỗi).

### Fixed
- **Bảo mật:** vá JSON-injection ở `git:clone` (dựng `source_repository` bằng `jq -n --arg`).
- **Bảo mật:** vá command-injection ở `wp:*` — validate slug plugin/theme và chặn ký tự
  đặc biệt của shell ở `wp:cli`.
- Sửa tài liệu trỏ sai `.claude/skills/` → `skills/` trong `AGENTS.md`.
- Dọn biến chết (`result`, `cleanup_local`) để ShellCheck sạch.

## [0.1.0] - 2026-07-01

### Added
- Bản phát hành đầu: plugin marketplace Claude Code với 12 skill thao tác hosting cPanel
  qua API token (database, domain, deploy, debug, email, SSL, DNS, metrics, FTP, backup,
  WordPress) và engine CLI `bin/cpanel` (UAPI/API2 + escape hatch).
