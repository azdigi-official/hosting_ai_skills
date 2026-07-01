---
name: cpanel-dns
description: Quản lý bản ghi DNS của domain trên cPanel — xem, thêm, xóa record A, CNAME, MX, TXT, SPF... Dùng khi người dùng cần trỏ domain/subdomain về IP, cấu hình MX cho email, thêm bản ghi TXT (xác thực domain, SPF/DKIM), sửa DNS, hoặc chuẩn bị DNS để cấp SSL/AutoSSL.
---

# cPanel — Quản lý DNS

Xem và chỉnh bản ghi DNS qua `bin/cpanel` (UAPI module `DNS`).

## Xem bản ghi (kèm số dòng để xóa)

```bash
cpanel dns:list example.com
```

Trả JSON các record đã **giải mã** (cPanel lưu base64): `line` (dùng để xóa), `type`,
`name`, `ttl`, `data`. Lọc nhanh:

```bash
cpanel dns:list example.com | jq -r '.records[] | "\(.line)\t\(.type)\t\(.name)\t\(.data|join(","))"'
```

## Thêm bản ghi

```bash
# A record:  www → IP
cpanel dns:add example.com A www 14400 203.0.113.10

# CNAME:  blog → example.com.   (FQDN nên có dấu chấm cuối)
cpanel dns:add example.com CNAME blog 14400 example.com.

# MX:  data gồm 2 phần — priority và mail server
cpanel dns:add example.com MX @ 14400 10 mail.example.com.

# TXT / SPF:
cpanel dns:add example.com TXT @ 14400 "v=spf1 +mx ~all"
```

- `name` là phần host (vd `www`, `blog`). Cho bản ghi **gốc domain** dùng `@` (CLI tự
  chuyển thành FQDN) hoặc tên zone đầy đủ có dấu `.` cuối. Wildcard dùng `*`.
- `ttl` tính bằng giây (vd 14400). `data...` là một hoặc nhiều phần tử tùy loại record.

## Xóa bản ghi

```bash
cpanel dns:list example.com         # tìm 'line' của record cần xóa
cpanel dns:remove example.com 21 --yes   # xóa theo line_index (cần --yes sau khi user đồng ý)
```

> Cơ chế: CLI tự lấy `serial` (SOA) hiện tại rồi gọi `mass_edit_zone`. Mỗi lần ghi,
> serial tăng — nếu thao tác song song có thể lệch, cứ chạy lại `dns:list` để lấy line mới.

## Lưu ý

- Thay đổi DNS cần thời gian lan truyền (theo TTL). Kiểm tra bằng `dig`/`nslookup` từ ngoài.
- DNS là mắt xích cho: trỏ domain (A), email (MX + TXT/SPF/DKIM), và **AutoSSL** (domain
  phải trỏ đúng server thì mới cấp được cert — xem `cpanel-ssl`).
- Thao tác nâng cao (sửa hàng loạt): escape hatch `cpanel uapi DNS <function>`.

## DNSSEC (chống giả mạo DNS)

```bash
cpanel dns:dnssec-status example.com          # đã bật chưa
cpanel dns:dnssec-enable example.com --yes    # bật (ký zone) — cần --yes
cpanel dns:dnssec-ds example.com              # DS record để KHAI BÁO tại nhà đăng ký
cpanel dns:dnssec-disable example.com --yes   # tắt — cần --yes
```

- **Bắt buộc bước cuối:** sau khi `dnssec-enable`, phải lấy DS record (`dnssec-ds`) và
  **khai báo tại nhà đăng ký domain (registrar)** thì DNSSEC mới có hiệu lực. Nếu không
  khai báo DS, việc bật chỉ ký zone cục bộ, không ảnh hưởng phân giải.
- `dnssec-enable`/`disable` ghi vào zone → qua cổng `--yes` (hỏi người dùng trước).
