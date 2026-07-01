---
name: cpanel-metrics
description: Giám sát sức khỏe gói hosting cPanel — dung lượng đĩa, băng thông, số inode, MySQL disk, tài nguyên CPU/RAM/IO (CloudLinux LVE), quota. Dùng khi cần kiểm tra hosting còn bao nhiêu dung lượng, vì sao website chậm/lỗi, tài khoản có vượt giới hạn tài nguyên không, hoặc xem tổng quan tình trạng gói hosting.
---

# cPanel — Giám sát sức khỏe tài khoản

Kiểm tra nhanh tình trạng gói hosting qua `bin/cpanel`. Rất hữu ích khi **chẩn đoán**
("vì sao site lỗi/chậm?") — thường do hết dung lượng, hết inode, hoặc vượt giới hạn LVE.

## Tổng quan (disk, bandwidth, MySQL, inode, email, domain)

```bash
cpanel metrics:health
cpanel metrics:health | jq -r '.stats[] | "\(.name): \(.used)/\(.max) \(.units)"'
```

`StatsBar::get_stats` — ví dụ trả về: `diskusage: 95 MB/10 GB`, `mysqldatabases: 1/∞`,
`addondomains: 0/8`. Tùy biến mục hiển thị:

```bash
cpanel metrics:health 'diskusage|filesusage|bandwidthusage'
```

## Tài nguyên CPU/RAM/IO (CloudLinux LVE)

```bash
cpanel metrics:resource
```

`ResourceUsage::get_usages` — usage so với giới hạn LVE. Nếu một mục chạm trần (CPU,
EP/entry processes, IO) thì website bị throttling/lỗi 508 → đây là nguyên nhân thường gặp.

## Quota đĩa chi tiết (MB + inode)

```bash
cpanel metrics:quota
```

`Quota::get_quota_info` — `megabytes_used/megabytes_remain`, `inodes_used/inode_limit`.
**Hết inode** (quá nhiều file nhỏ) gây lỗi ghi file dù còn dung lượng MB — kiểm tra ở đây.

## Checklist chẩn đoán nhanh

0. `metrics:disk-usage` — tổng quan nhanh: đã dùng/giới hạn MB, inode, phần email chiếm bao nhiêu.
1. `metrics:quota` — hết MB hoặc hết inode? → site không ghi được file/session/cache.
2. `metrics:resource` — chạm trần CPU/IO/EP? → site chậm hoặc 508.
3. `metrics:health` — bandwidth gần giới hạn? database/email quá nhiều?
4. Kết hợp `cpanel-debug` (đọc error_log) để xác định lỗi ứng dụng.
