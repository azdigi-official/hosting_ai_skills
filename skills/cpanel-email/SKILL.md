---
name: cpanel-email
description: Quản lý email trên gói hosting cPanel — tạo/xóa tài khoản email, đổi mật khẩu, đặt quota, và quản lý email forwarder. Dùng khi người dùng cần tạo địa chỉ email, mailbox, hộp thư, chuyển tiếp email (forwarder), đổi mật khẩu email, hoặc đặt dung lượng cho email trên cPanel.
---

# cPanel — Quản lý Email

Tạo và quản lý tài khoản email + forwarder qua `bin/cpanel` (UAPI module `Email`).
Địa chỉ email luôn ở dạng đầy đủ `user@domain`.

## Tài khoản email (mailbox)

```bash
# Liệt kê
cpanel email:list

# Tạo (quota tính bằng MB, bỏ trống hoặc 0 = không giới hạn)
cpanel email:create sales@example.com 'M@tKhauManh2026!' 500

# Đổi mật khẩu
cpanel email:passwd sales@example.com 'M@tKhauMoi2026!'

# Đổi quota (MB)
cpanel email:quota sales@example.com 1024

# Xóa (HỎI XÁC NHẬN trước — mất toàn bộ thư trong hộp)
cpanel email:delete sales@example.com
```

## Forwarder (chuyển tiếp)

```bash
cpanel email:fwd-list
# Chuyển info@example.com → một địa chỉ đích (nội bộ hoặc ngoài)
cpanel email:fwd-add info@example.com sales@example.com
cpanel email:fwd-delete info@example.com sales@example.com
```

## Lưu ý

- Tham số CLI nhận **địa chỉ đầy đủ** `user@domain`; CLI tự tách local-part và domain.
- Đặt mật khẩu trong nháy đơn để shell không diễn giải ký tự đặc biệt; mật khẩu yếu
  có thể bị cPanel từ chối.
- `email:delete`/`email:fwd-delete` là thao tác phá hủy — engine chặn nếu thiếu xác nhận;
  sau khi người dùng đồng ý, chạy lại kèm `--yes` (vd `cpanel email:delete a@b.com --yes`).
- Domain phải đã tồn tại trên tài khoản (xem `cpanel-domain`) thì mới tạo được email.
- Để email gửi/nhận ngoài internet, domain cần bản ghi MX trỏ đúng (xem DNS qua
  escape hatch `uapi DNS ...`). SSL cho mail server: xem `cpanel-ssl`.
- Các chức năng khác (autoresponder, mailing list, default address) gọi qua escape
  hatch: `cpanel uapi Email <function> ...` — tra tại https://api.docs.cpanel.net/.
  (Autoresponder phụ thuộc feature `autoresponders` của gói; có gói tắt sẵn.)

## Deliverability (chống email vào spam) & dung lượng hộp thư

```bash
cpanel email:deliverability example.com          # Trạng thái SPF/DKIM (đọc từ DNS, không ghi)
cpanel email:dkim example.com --yes              # Bật DKIM: tự tạo khóa + ghi bản ghi DNS
cpanel email:spf example.com 'v=spf1 +mx +a ~all' --yes   # Cài/sửa SPF (ghi DNS)
cpanel email:usage                               # Dung lượng đĩa theo từng hộp thư
```

- `email:spf`/`email:dkim` **ghi bản ghi vào DNS** → engine chặn nếu thiếu `--yes`; hỏi
  người dùng trước, rồi chạy lại kèm `--yes`. Xem trước: `--dry-run`.
- **SPF không tự đoán:** phải truyền chuỗi SPF đầy đủ (bắt đầu `v=spf1`). Ưu tiên giá trị
  nhà cung cấp hosting khuyến nghị (thường có `include:` mail gateway của họ) thay vì mặc định.
- `email:deliverability` chỉ có ý nghĩa với domain có zone riêng (main/addon), không phải subdomain.
