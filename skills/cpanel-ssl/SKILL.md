---
name: cpanel-ssl
description: Quản lý chứng chỉ SSL/TLS trên gói hosting cPanel — xem cert đã cài, kích hoạt AutoSSL (Let's Encrypt) để cấp/gia hạn cert miễn phí, kiểm tra trạng thái, và cài cert thủ công do người dùng cung cấp. Dùng khi người dùng cần bật HTTPS, cấp chứng chỉ SSL, gia hạn cert, cài SSL cho domain, hoặc khắc phục lỗi chứng chỉ trên cPanel.
---

# cPanel — Quản lý SSL/TLS

Quản lý chứng chỉ qua `bin/cpanel` (UAPI module `SSL`).

## Xem chứng chỉ đang cài

```bash
cpanel ssl:list      # cert theo từng host (domain, danh sách domain phủ, hạn)
cpanel ssl:certs     # cert trong kho của tài khoản
```

`ssl:list` trả `certificate.domains` (các domain được phủ), `not_after` (hạn dùng,
Unix timestamp) và `issuer` (đơn vị cấp — nếu là chính domain tức cert self-signed).

## AutoSSL — cấp/gia hạn Let's Encrypt MIỄN PHÍ (cách khuyến nghị)

```bash
cpanel ssl:autossl   # kích hoạt một lượt AutoSSL cho mọi domain đủ điều kiện
cpanel ssl:status    # AutoSSL có đang chạy không
```

> **QUAN TRỌNG:** AutoSSL xác thực quyền sở hữu domain qua HTTP — domain **phải đã trỏ
> DNS** về đúng server thì mới cấp được cert. Nếu domain chưa trỏ DNS, lệnh chạy thành
> công ở tầng API nhưng cert sẽ không được cấp (validation thất bại). Sau khi DNS đã
> trỏ, chạy `ssl:autossl` rồi đợi vài phút và kiểm tra lại bằng `ssl:list`.

## Cài chứng chỉ thủ công (cert do người dùng/CA khác cung cấp)

```bash
cpanel ssl:install <domain> <cert_file> <key_file> [cabundle_file]
# Ví dụ:
cpanel ssl:install shop.example.com fullchain.crt private.key ca-bundle.crt
```
CLI đọc nội dung file cert/key/cabundle local và gửi qua API. Dùng khi có cert trả phí
hoặc wildcard từ nhà cung cấp khác. Domain phải là vhost đã tồn tại trên tài khoản.

## Lưu ý

- Ưu tiên **AutoSSL** cho nhu cầu HTTPS thông thường (miễn phí, tự gia hạn).
- `ssl:install` ghi đè cert hiện tại của domain — với cert tốt đang chạy thì cân nhắc.
- Sau khi cấp/cài SSL, kiểm tra HTTPS thực tế. Nếu domain chưa trỏ DNS, không verify
  được qua trình duyệt (xem ghi chú DNS ở `cpanel-deploy`).
- Thu hồi/xóa cert hoặc thao tác nâng cao: escape hatch `cpanel uapi SSL <function>`
  (vd `delete_ssl`, `get_cn_name`) — tra tại https://api.docs.cpanel.net/.
