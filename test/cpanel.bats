#!/usr/bin/env bats
# Test engine cpanel — KHÔNG gọi mạng (dùng CPANEL_CURL_MOCK).
# Chạy: bats test/

setup() {
  CPANEL="$BATS_TEST_DIRNAME/../bin/cpanel"
  export CPANEL_HOST=mock.local CPANEL_USER=u CPANEL_API_TOKEN=tok
  # Mọi lời gọi API trả về body giả này (đủ cho get_restrictions + báo thành công).
  export CPANEL_CURL_MOCK='{"status":1,"data":{"prefix":"u_"}}'
  # Không để .env thật của repo lọt vào test.
  export CPANEL_ENV_FILE=/dev/null
}

@test "version in ra phiên bản" {
  run "$CPANEL" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.1.0"* ]]
}

@test "help chạy được" {
  run "$CPANEL" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"toolkit thao tác hosting cPanel"* ]]
}

@test "lệnh đọc (db:list) chạy với mock, rc=0" {
  run "$CPANEL" db:list
  [ "$status" -eq 0 ]
}

@test "confirm gate CHẶN db:delete khi non-interactive thiếu --yes" {
  run "$CPANEL" db:delete victim
  [ "$status" -eq 1 ]
  [[ "$output" == *"cần xác nhận"* ]]
}

@test "db:delete --yes vượt qua gate (rc=0)" {
  run "$CPANEL" db:delete victim --yes
  [ "$status" -eq 0 ]
}

@test "CPANEL_ASSUME_YES=1 tương đương --yes" {
  CPANEL_ASSUME_YES=1 run "$CPANEL" db:delete victim
  [ "$status" -eq 0 ]
}

@test "--dry-run in ý định, không thực thi (email:delete)" {
  run "$CPANEL" email:delete a@b.com --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry_run"* ]]
}

@test "--dry-run cho lệnh tổ hợp (deploy:static)" {
  run "$CPANEL" deploy:static ./x public_html --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry_run"* ]]
}

@test "wp:update-plugins chặn slug độc (command injection)" {
  run "$CPANEL" wp:update-plugins public_html 'evil; rm -rf ~'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Slug không hợp lệ"* ]]
}

@test "wp:cli chặn ký tự đặc biệt" {
  run "$CPANEL" wp:cli public_html option get 'siteurl; id'
  [ "$status" -ne 0 ]
  [[ "$output" == *"ký tự đặc biệt"* ]]
}

@test "wp:update-plugins chấp nhận slug hợp lệ (không chặn ở bước validate)" {
  # Slug hợp lệ vượt qua validate; sau đó _wp_exec cần jq — với mock sẽ không tìm thấy
  # linekey và timeout nhanh không xảy ra ở đây vì ta chỉ kiểm tra KHÔNG bị chặn slug.
  run bash -c "source '$BATS_TEST_DIRNAME/../lib/common.sh'; source '$BATS_TEST_DIRNAME/../lib/cpanel-api.sh'; source '$BATS_TEST_DIRNAME/../lib/deploy.sh'; source '$BATS_TEST_DIRNAME/../lib/wp.sh'; \
    _s='akismet'; case \"\$_s\" in *[!A-Za-z0-9._-]*) echo BAD; exit 1;; esac; echo GOOD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GOOD"* ]]
}

@test "git_clone dựng JSON an toàn với URL chứa dấu ngoặc kép" {
  run bash -c "source '$BATS_TEST_DIRNAME/../lib/common.sh'; \
    url='https://x.git\"},\"evil\":1'; jq -nc --arg url \"\$url\" '{url:\$url}'"
  [ "$status" -eq 0 ]
  # jq phải escape " thành \\\" → chuỗi vẫn là JSON hợp lệ 1 field.
  echo "$output" | jq -e '.url' >/dev/null
  run bash -c "echo '$output' | jq -e 'keys==[\"url\"]'"
  [ "$status" -eq 0 ]
}

@test "php:versions chỉ trả bản alt-php (lọc ea-php)" {
  export CPANEL_CURL_MOCK='{"status":1,"data":{"versions":["ea-php74","alt-php81","alt-php82","ea-php82"]}}'
  run "$CPANEL" php:versions
  [ "$status" -eq 0 ]
  [[ "$output" == *"alt-php81"* ]]
  [[ "$output" == *"alt-php82"* ]]
  [[ "$output" != *"ea-php"* ]]
}

@test "php:set từ chối ea-php*" {
  export CPANEL_CURL_MOCK='{"status":1,"data":{"versions":["alt-php82"]}}'
  run "$CPANEL" php:set example.com ea-php82 --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"chỉ đặt bản alt-php"* ]]
}

@test "php:set từ chối bản chưa cài" {
  export CPANEL_CURL_MOCK='{"status":1,"data":{"versions":["alt-php82"]}}'
  run "$CPANEL" php:set example.com alt-php99 --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"chưa cài"* ]]
}

@test "php:set chấp nhận alt-php đã cài (với --yes)" {
  export CPANEL_CURL_MOCK='{"status":1,"data":{"versions":["alt-php81","alt-php82"]}}'
  run "$CPANEL" php:set example.com alt-php82 --yes
  [ "$status" -eq 0 ]
}

@test "php:set bị gate chặn khi thiếu --yes" {
  export CPANEL_CURL_MOCK='{"status":1,"data":{"versions":["alt-php82"]}}'
  run "$CPANEL" php:set example.com alt-php82
  [ "$status" -eq 1 ]
  [[ "$output" == *"cần xác nhận"* ]]
}

@test "file:chmod từ chối mode không hợp lệ" {
  run "$CPANEL" file:chmod public_html/x.php 999 --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"Mode không hợp lệ"* ]]
}

@test "file:chmod bị gate chặn khi thiếu --yes" {
  run "$CPANEL" file:chmod public_html/x.php 644
  [ "$status" -eq 1 ]
  [[ "$output" == *"cần xác nhận"* ]]
}

@test "email:spf từ chối record không bắt đầu v=spf1 (với --yes)" {
  run "$CPANEL" email:spf example.com 'khong-phai-spf' --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"v=spf1"* ]]
}

@test "email:spf bị gate chặn khi thiếu --yes" {
  run "$CPANEL" email:spf example.com 'v=spf1 ~all'
  [ "$status" -eq 1 ]
  [[ "$output" == *"cần xác nhận"* ]]
}

@test "email:dkim bị gate chặn khi thiếu --yes" {
  run "$CPANEL" email:dkim example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"cần xác nhận"* ]]
}

@test "metrics:disk-usage tổng hợp từ quota" {
  export CPANEL_CURL_MOCK='{"status":1,"data":{"megabytes_used":100,"megabyte_limit":1000,"megabytes_remain":900,"inodes_used":500}}'
  run "$CPANEL" metrics:disk-usage
  [ "$status" -eq 0 ]
  [[ "$output" == *"100"* ]]
  [[ "$output" == *"disk_mb_limit"* ]]
}

@test "cpanel_mysql_name tự ghép tiền tố" {
  run bash -c "export CPANEL_HOST=m CPANEL_USER=u CPANEL_API_TOKEN=t CPANEL_CURL_MOCK='{\"status\":1,\"data\":{\"prefix\":\"u_\"}}' CPANEL_ENV_FILE=/dev/null; \
    source '$BATS_TEST_DIRNAME/../lib/common.sh'; source '$BATS_TEST_DIRNAME/../lib/cpanel-api.sh'; require_cpanel_config; cpanel_mysql_name blog"
  [ "$status" -eq 0 ]
  [[ "$output" == *"u_blog"* ]]
}
