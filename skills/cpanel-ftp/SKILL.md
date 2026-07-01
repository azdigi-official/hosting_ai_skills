---
name: cpanel-ftp
description: Quản lý tài khoản FTP và URL redirect trên gói hosting cPanel. Dùng khi người dùng cần tạo/xóa tài khoản FTP để upload mã nguồn, đổi mật khẩu FTP, giới hạn FTP vào một thư mục, hoặc tạo chuyển hướng URL (redirect) cho domain.
---

# cPanel — FTP & Redirect

## Tài khoản FTP (UAPI module `Ftp`)

```bash
cpanel ftp:list

# Tạo FTP (quota MB, 0 = không giới hạn; homedir tương đối home, mặc định toàn home)
cpanel ftp:create deploy 'Ftp#MatKhauManh2026!' 0 public_html/site

# Đổi mật khẩu
cpanel ftp:passwd deploy 'Ftp#MatKhauMoi2026!'

# Xóa — dùng tên đầy đủ user@domain mà ftp:list hiển thị (cần --yes sau khi user đồng ý)
cpanel ftp:delete deploy@example.com --yes
```

- Tên đăng nhập FTP thực tế là `<user>@<maindomain>` (xem `ftp:list`). Khi xóa phải
  dùng tên đầy đủ này.
- Đặt `homedir` để khóa FTP vào đúng thư mục dự án (an toàn khi giao cho bên thứ ba).
- Mật khẩu phải mạnh (cPanel từ chối mật khẩu yếu). Đặt trong nháy đơn.

## URL Redirect (UAPI module `Mime`)

```bash
cpanel redirect:list

# Chuyển /khuyenmai → URL đích (301 permanent mặc định, hoặc temporary)
cpanel redirect:add example.com /khuyenmai https://example.com/sale permanent

cpanel redirect:delete /khuyenmai --yes
```

> **CẢNH BÁO (LiteSpeed):** `redirect:delete` gọi `Mime::delete_redirect` — trên một số
> server LiteSpeed lệnh **báo thành công nhưng không thực sự xóa**. Luôn kiểm tra lại
> bằng `redirect:list`. Nếu vẫn còn, xóa thủ công khối `RewriteCond/RewriteRule` tương
> ứng trong `public_html/.htaccess`:
> ```bash
> cpanel file:read public_html .htaccess     # tìm RewriteRule ^khuyenmai$
> # sửa file cục bộ rồi ghi lại:
> cpanel file:save public_html .htaccess ./htaccess_da_sua.txt
> ```
> `redirect:add` và `redirect:list` hoạt động ổn định.
