# AGENTS.md — Hướng dẫn cho AI agent (Codex & tương thích)

Repo này cung cấp một bộ công cụ để AI thao tác lên **gói hosting cPanel** của người
dùng qua API token: tạo database, thêm domain, deploy, debug, cron, email...

Claude Code dùng các skill trong `skills/`. Codex và các agent khác dùng tài
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

- **Thao tác phá hủy có cổng xác nhận trong engine.** Các lệnh xóa (`db:delete`,
  `db:user-delete`, `subdomain:delete`, `file:delete`, `email:delete`,
  `email:fwd-delete`, `ftp:delete`, `redirect:delete`, `dns:remove`, `cron:delete`)
  sẽ **DỪNG** khi chạy non-interactive nếu không có xác nhận. Quy trình đúng:
  1. Hỏi người dùng và nêu rõ đối tượng sẽ bị xóa (KHÔNG hoàn tác).
  2. Sau khi người dùng đồng ý, chạy lại lệnh kèm cờ `--yes`.
  - Muốn xem trước mà không thực thi: thêm `--dry-run` (in ra thao tác API sẽ gọi).
  - **Lưu ý:** escape hatch `cpanel uapi/api2` gọi API thô, **KHÔNG** qua cổng xác nhận —
    tự chịu trách nhiệm khi dùng để xóa.
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
