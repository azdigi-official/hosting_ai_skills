# AGENTS.md — Hướng dẫn cho AI agent (Codex & tương thích)

Repo này cung cấp một bộ công cụ để AI thao tác lên **gói hosting cPanel** của người
dùng qua API token: tạo database, thêm domain, deploy, debug, cron, email...

Claude Code dùng các skill trong `.claude/skills/`. Codex và các agent khác dùng tài
liệu này — nhưng **cả hai chạy chung một engine**: CLI `bin/cpanel`.

## Khởi động

```bash
# credential: mỗi website một .env RIÊNG trong thư mục dự án của nó
#   (CPANEL_HOST, CPANEL_USER, CPANEL_API_TOKEN). Engine nạp theo thứ tự:
#   $CPANEL_ENV_FILE -> ./.env (thư mục hiện tại) -> ~/.cpanel-ai.env (fallback chung)
cpanel doctor            # chạy trong thư mục website đó để xác minh kết nối
```

> Lệnh `cpanel` có sẵn khi `bin/` nằm trong PATH. Nếu chạy trực tiếp trong repo mà
> chưa thêm PATH, dùng `./bin/cpanel` (tương đương).

## Nguyên tắc

1. Mọi thao tác cPanel đi qua `cpanel`. Xem lệnh: `cpanel help`.
2. Output dữ liệu là JSON ở stdout; phân tích bằng `jq`.
3. Khi không có lệnh con phù hợp, dùng escape hatch:
   `cpanel uapi <Module> <func> key=value` (hoặc `api2`). Tra cứu hàm tại
   https://api.docs.cpanel.net/.

## Tác vụ thường gặp

| Tác vụ | Lệnh |
|--------|------|
| Kiểm tra kết nối | `cpanel doctor` |
| Tạo database + user + quyền | `db:create` → `db:user-create` → `db:grant` |
| Thêm subdomain | `cpanel subdomain:add <sub> <root>` |
| Thêm addon domain | `cpanel addon:add <domain>` |
| Debug lỗi web | `cpanel log:errors` |

## QUY TẮC AN TOÀN (bắt buộc)

- **Xác nhận với người dùng trước mọi thao tác phá hủy**: `db:delete`, xóa domain, ghi
  đè/xóa file.
- **Không in `CPANEL_API_TOKEN`** hay mật khẩu ra log/output.
- Chạy lệnh `:list` trước khi tạo mới để tránh trùng.
- Nếu `doctor` lỗi → dừng và báo người dùng kiểm tra `.env`, không đoán mò.
- File `.env` chứa bí mật và đã được `.gitignore` — không commit, không đọc token ra ngoài.

## Cấu trúc repo

```
.claude-plugin/     manifest plugin + marketplace (cho Claude Code)
bin/cpanel          CLI điều phối (điểm vào duy nhất)
lib/common.sh       nạp .env, logging, kiểm tra phụ thuộc
lib/cpanel-api.sh   wrapper curl cho UAPI & API2
skills/             skill cho Claude Code (cùng nội dung, định dạng skill)
```
