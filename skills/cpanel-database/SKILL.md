---
name: cpanel-database
description: Tạo và quản lý MySQL database, MySQL user và phân quyền trên gói hosting cPanel. Dùng khi người dùng cần tạo database, tạo user MySQL, cấp quyền, kết nối website (WordPress, Laravel...) tới database, hoặc xóa database trên cPanel.
---

# cPanel — Quản lý MySQL Database

Tạo database, user và cấp quyền qua `bin/cpanel`.

> **Tiền tố bắt buộc:** cPanel yêu cầu mọi database/user mang tiền tố `<cpaneluser>_`.
> UAPI **không tự thêm** (chỉ giao diện web mới tự thêm). CLI này **tự ghép tiền tố**
> cho bạn — lấy động qua `Mysql::get_restrictions`. Bạn truyền tên ngắn (`blog`) hay
> tên đầy đủ (`user_blog`) đều được; CLI in ra tên đầy đủ đã dùng.

## Quy trình chuẩn tạo database cho một ứng dụng

```bash
# 1. Tạo database  (CLI tự thành  <user>_blog)
cpanel db:create blog

# 2. Tạo MySQL user (CLI tự thành  <user>_bloguser)
cpanel db:user-create bloguser 'M@tKhauManh123!'

# 3. Cấp toàn quyền — truyền tên ngắn cũng được, CLI tự ghép tiền tố cho cả hai
cpanel db:grant bloguser blog
```

Sau đó dùng thông tin này trong cấu hình ứng dụng:
- Host: `localhost`
- Database: `user_blog`
- User: `user_bloguser`
- Password: mật khẩu đã đặt

## Các lệnh

| Lệnh | Mô tả |
|------|-------|
| `db:list` | Liệt kê database hiện có |
| `db:create <name>` | Tạo database |
| `db:user-create <user> <pass>` | Tạo MySQL user |
| `db:user-passwd <user> <pass>` | Đổi mật khẩu MySQL user |
| `db:user-delete <user>` | Xóa MySQL user |
| `db:grant <user> <db> [priv]` | Cấp quyền (mặc định `ALL PRIVILEGES`) |
| `db:delete <name>` | **Xóa database — phải xác nhận trước** |

## Lưu ý

- Trước khi tạo, chạy `db:list` để tránh trùng tên.
- Mật khẩu nên ≥ 12 ký tự, có hoa/thường/số/ký tự đặc biệt (cPanel có thể từ chối
  mật khẩu yếu). Đặt mật khẩu trong dấu nháy đơn để shell không diễn giải ký tự đặc biệt.
- **Không bao giờ** chạy `db:delete`/`db:user-delete` mà chưa xác nhận rõ ràng với người
  dùng. Engine sẽ chặn nếu thiếu xác nhận; sau khi người dùng đồng ý, chạy lại kèm `--yes`
  (vd `cpanel db:delete blog --yes`). Xem trước: thêm `--dry-run`.
- Để chỉ cấp quyền hạn chế: `db:grant <user> <db> "SELECT, INSERT, UPDATE, DELETE"`.
- Trong file cấu hình ứng dụng, **luôn dùng tên đầy đủ có tiền tố** (ví dụ
  `<user>_blog`) — đây là tên thật trong MySQL. Chạy `db:list` để lấy tên chính xác.
