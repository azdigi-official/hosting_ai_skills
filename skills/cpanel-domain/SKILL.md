---
name: cpanel-domain
description: Thêm và quản lý domain trên gói hosting cPanel — addon domain, subdomain, document root. Dùng khi người dùng cần thêm tên miền mới vào hosting, tạo subdomain, trỏ domain tới thư mục, hoặc liệt kê các domain đang có.
---

# cPanel — Quản lý Domain

Quản lý domain, addon domain và subdomain qua `bin/cpanel`.

## Liệt kê domain hiện có

```bash
cpanel domain:list
```

Trả về domain chính (main), addon, subdomain (sub) và parked — luôn chạy trước khi
thêm mới để tránh trùng và để biết domain gốc dùng cho subdomain.

## Thêm subdomain

```bash
# blog.example.com  với document root mặc định
cpanel subdomain:add blog example.com

# chỉ định document root tùy ý
cpanel subdomain:add blog example.com public_html/blog
```

## Thêm addon domain (tên miền hoàn toàn mới)

```bash
# tự suy ra subdomain & docroot
cpanel addon:add newsite.com

# chỉ định rõ subdomain nội bộ và document root
cpanel addon:add newsite.com newsite public_html/newsite.com
```

> Addon domain trên cPanel hiện đại có thể được quản lý qua giao diện "Domains" mới.
> Lệnh `addon:add` dùng API2 `AddonDomain::addaddondomain` (tương thích rộng). Nếu
> server trả lỗi "feature disabled", kiểm tra gói hosting có cho phép addon domain không.

## DNS & thao tác nâng cao (escape hatch)

Các tác vụ DNS dùng trực tiếp UAPI — ví dụ:

```bash
# Liệt kê bản ghi DNS của một zone
cpanel uapi DNS parse_zone zone=example.com

# Thêm bản ghi (tham khảo tài liệu UAPI DNS::mass_edit_zone)
```

Tra cứu hàm tại https://api.docs.cpanel.net/ (module **DNS**, **DomainInfo**, **SubDomain**).

## An toàn

- Chạy `domain:list` trước khi thêm để tránh trùng.
- Xóa domain/subdomain là thao tác phá hủy (mất cấu hình vhost). Engine chặn nếu thiếu
  xác nhận; sau khi người dùng đồng ý, chạy lại kèm `--yes` (vd `cpanel subdomain:delete blog example.com --yes`).
- Sau khi thêm domain, nhắc người dùng trỏ DNS/nameserver nếu domain đăng ký ở nơi khác.
