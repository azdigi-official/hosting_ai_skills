# hosting_ai_skills

Hệ thống **skill cho AI** (Claude Code, Codex) để thao tác lên gói hosting của người
dùng qua API của control panel: tạo database, thêm domain, deploy, debug, sửa lỗi, cron...

Hiện hỗ trợ **cPanel** (UAPI + API2, xác thực bằng API token).

## Kiến trúc

Repo này là một **Claude Code plugin** (đồng thời là marketplace) — `bin/` tự vào
PATH khi plugin bật, nên engine `cpanel` gọi được ở mọi nơi.

```
.claude-plugin/
  ├── plugin.json       manifest plugin "cpanel"
  └── marketplace.json  catalog "hosting-ai-skills" (để /plugin marketplace add)
bin/cpanel          CLI điều phối — điểm vào duy nhất (vào PATH khi plugin bật)
lib/common.sh       nạp cấu hình .env, logging, kiểm tra phụ thuộc
lib/cpanel-api.sh   wrapper curl cho cPanel UAPI & API2
skills/             skill cho Claude Code (tự khám phá theo description)
  ├── cpanel-toolkit/   skill gốc: auth, an toàn, escape hatch gọi mọi hàm
  ├── cpanel-database/  MySQL database & user
  ├── cpanel-domain/    addon domain, subdomain, DNS
  ├── cpanel-debug/     đọc log, chẩn đoán lỗi
  ├── cpanel-deploy/    upload/giải nén source, deploy WordPress/Laravel/static/Node/Git
  ├── cpanel-email/     tài khoản email, forwarder, quota
  ├── cpanel-ssl/       chứng chỉ SSL, AutoSSL (Let's Encrypt), cài cert thủ công
  ├── cpanel-dns/       bản ghi DNS (A/CNAME/MX/TXT) — xem/thêm/xóa
  ├── cpanel-metrics/   sức khỏe tài khoản: disk, bandwidth, MySQL, LVE, quota
  ├── cpanel-ftp/       tài khoản FTP + URL redirect
  ├── cpanel-backup/    full backup về home/FTP (+ ghi chú JetBackup cần WHM token)
  └── cpanel-wordpress/ WordPress không cần SSH: core/plugin/theme, wp-cli
lib/deploy.sh       orchestration deploy (tải source, tạo DB, sinh wp-config)
lib/email-ssl.sh    helper email + cài SSL thủ công
lib/dns.sh          bản ghi DNS (giải mã base64, mass_edit_zone)
lib/metrics.sh      giám sát sức khỏe tài khoản
lib/backup.sh       full backup (home/FTP) qua cPanel Backup gốc
AGENTS.md           hướng dẫn cho Codex (dùng chung engine cpanel)
.env.example        mẫu cấu hình (sao chép thành .env)
```

**Engine dùng chung**: `bin/cpanel` là core để giao tiếp với API của cPanel.
Skill (`skills/`) và `AGENTS.md` chỉ là lớp hướng dẫn thực thi trỏ vào core này.

## Cài đặt

### Credential — mỗi website một `.env` riêng (khuyến nghị)

Mỗi website/dự án nên có **file `.env` riêng** đặt trong thư mục của website đó, chứa
credential cPanel của hosting tương ứng. Khi AI làm việc trong thư mục website nào,
engine tự nạp `.env` ở chính thư mục đó — không lẫn giữa các website/khách hàng khác nhau.

```bash
cd ~/sites/website-A          # thư mục dự án của website A
printf 'CPANEL_HOST=hostA.example.com\nCPANEL_USER=userA\nCPANEL_API_TOKEN=xxxx\n' > .env
chmod 600 .env
# website B làm tương tự trong thư mục riêng của nó, với host/user/token của B
```

Token tạo tại cPanel **> Security > Manage API Tokens**. **Không commit `.env`** (đã có
trong `.gitignore` của repo; với thư mục website hãy tự thêm vào `.gitignore`).

Engine tìm credential theo thứ tự (dùng cái **đầu tiên** có):
`$CPANEL_ENV_FILE` → `./.env` (thư mục hiện tại) → `~/.cpanel-ai.env` (fallback dùng chung).
Nếu chỉ quản lý **một** tài khoản cPanel cho mọi việc, có thể đặt một file chung
`~/.cpanel-ai.env` thay vì `.env` mỗi thư mục.

### Claude Code (chuẩn — plugin marketplace)

Trong Claude Code, chạy:

```
/plugin marketplace add azdigi-official/hosting_ai_skills
/plugin install cpanel@hosting-ai-skills
```

Xong — `bin/` tự vào PATH, gọi được `cpanel ...` ở mọi project; skill tự kích hoạt
theo ngữ cảnh. Cập nhật: `/plugin marketplace update hosting-ai-skills`.

### Codex (qua AGENTS.md)

Codex chưa có hệ plugin; dùng `AGENTS.md`. Clone repo rồi trỏ Codex tới nó:

```bash
git clone https://github.com/azdigi-official/hosting_ai_skills.git ~/.config/hosting_ai_skills
ln -sf ~/.config/hosting_ai_skills/AGENTS.md ~/.codex/AGENTS.md   # hoặc copy nội dung
export PATH="$HOME/.config/hosting_ai_skills/bin:$PATH"           # thêm vào ~/.zshrc để có lệnh cpanel
```

### Dùng tại chỗ / phát triển

Mở Claude Code/Codex ngay trong thư mục repo: skill ở `skills/` được nạp tự động,
hoặc test plugin bằng `claude --plugin-dir .`. Gọi engine bằng `./bin/cpanel <lệnh>`
(tương đương `cpanel <lệnh>` khi đã cài). Kiểm tra: `./bin/cpanel doctor`.

## Yêu cầu

- `bash`, `curl` (bắt buộc)
- `jq` (khuyến nghị — để parse/format JSON; thiếu vẫn chạy, in JSON thô)
- `git` (để clone & cập nhật khi cài global)

## Gọi bất kỳ hàm cPanel nào

Toolkit không bao quanh mọi hàm. Khi cần, gọi trực tiếp:

```bash
cpanel uapi <Module> <function> key=value     # UAPI hiện đại
cpanel api2 <Module> <function> key=value     # API2 (chức năng cũ)
```

Tra cứu module/hàm: https://api.docs.cpanel.net/

## An toàn

- `.env` chứa token và đã được `.gitignore` — **không commit**.
- AI được hướng dẫn **xác nhận trước thao tác phá hủy** (xóa DB/domain/file).
- Token mang quyền của chính tài khoản hosting, không phải root/WHM.

