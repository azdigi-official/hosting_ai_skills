# Đóng góp cho hosting_ai_skills

Cảm ơn bạn đã quan tâm! Tài liệu này nêu quy ước để đóng góp an toàn và nhất quán.

## Kiến trúc

- **Điểm vào duy nhất:** `bin/cpanel` (điều phối). Logic đặt trong `lib/*.sh` và được
  `source` vào engine.
- **Skill:** mỗi thư mục `skills/<tên>/SKILL.md` mô tả cách dùng cho AI. Cùng chung engine
  `bin/cpanel` với Codex (xem `AGENTS.md`).
- Mọi thao tác cPanel đi qua UAPI/API2 (`lib/cpanel-api.sh`). Khi chưa có lệnh riêng,
  dùng escape hatch `cpanel uapi/api2`.

## Quy ước code (bash)

- Bắt đầu file thực thi bằng `set -euo pipefail`.
- **Dữ liệu ra stdout dạng JSON; log/diễn giải ra stderr** (dùng `log_info/ok/warn/err`).
- **Không in `CPANEL_API_TOKEN`** hay mật khẩu ra log/output.
- Dựng JSON bằng `jq -n --arg`, **không** nội suy chuỗi (tránh injection).
- Thao tác phá hủy phải gọi `confirm_destructive "<mô tả>"` trước khi thực thi.
- Tạo thư mục tạm bằng `mk_tmpdir` (được trap dọn tự động).
- Validate input đến từ người dùng trước khi nhúng vào lệnh chạy trên server.

## Trước khi mở Pull Request

```bash
# 1. Kiểm tra cú pháp
for f in bin/cpanel lib/*.sh; do bash -n "$f" || exit 1; done

# 2. Lint (khuyến nghị)
shellcheck bin/cpanel lib/*.sh

# 3. Thử với tài khoản cPanel thật của bạn (dùng .env riêng, KHÔNG commit)
./bin/cpanel doctor
```

- Cập nhật `CHANGELOG.md` (mục `Unreleased`).
- Nếu thêm/đổi lệnh: cập nhật `usage()` trong `bin/cpanel` và `SKILL.md` liên quan.
- **Không commit** `.env` hay bất kỳ token nào.

## Báo lỗi / đề xuất

Mở issue kèm: phiên bản (`cpanel version`), bản cPanel, lệnh đã chạy (che token), và
output lỗi (đặt `CPANEL_DEBUG=1` để có log chi tiết).
