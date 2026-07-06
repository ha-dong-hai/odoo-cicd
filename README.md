# CI/CD tự host cho Odoo — mô phỏng mô hình Odoo.sh

Bộ pipeline này tái tạo lại cơ chế vận hành của Odoo.sh (3 nhánh development/staging/production, container mới mỗi lần build, backup trước khi update, tự rollback khi build lỗi) bằng GitHub Actions + Docker Compose + Traefik, chạy trên **1 server tự host duy nhất** thông qua GitHub Actions **self-hosted runner** — không cần VPS, không cần mở port SSH ra internet.

Xem giải thích nguyên lý đầy đủ tại [trang tổng hợp tài liệu Odoo.sh](https://claude.ai/code/artifact/2a9cb2f3-b894-4862-b778-06c8265acd9d) đã tổng hợp trước đó. README này chỉ tập trung vào **cách vận hành bộ pipeline cụ thể trong repo này**.

## Vì sao dùng self-hosted runner thay vì SSH?

Vì server của bạn không phải VPS thuê ngoài (không có IP public cố định, thường sau NAT/router gia đình), GitHub Actions (chạy trên cloud của GitHub) không thể tự kết nối *vào* server bạn. Giải pháp: cài 1 agent nhỏ (**runner**) chạy sẵn trên server, agent này **tự kết nối ra ngoài** tới GitHub để nhận việc — không cần mở bất kỳ port nào, không cần SSH key nào cả.

Hệ quả: image Odoo được build **ngay trên server đó** (không cần push/pull qua registry như GHCR), và các script deploy chạy trực tiếp, không qua SSH.

## 1. Mô hình nhánh Git

| Nhánh | Vai trò | Trigger |
|---|---|---|
| `feature/*` | Nơi phát triển từng tính năng | PR vào `develop` |
| `develop` | Tương đương "development" của Odoo.sh | `ci-develop.yml` — chạy trên GitHub-hosted runner (không đụng tới server bạn), build + test suite, không deploy |
| `staging` | Tương đương "staging" | `deploy-staging.yml` — chạy trên self-hosted runner, deploy vào bản sao trung hoà của production |
| `main` | Tương đương "production" | `deploy-production.yml` — chạy trên self-hosted runner, backup, update, cutover có kiểm tra sức khoẻ |

**Lưu ý:** `ci-develop.yml` cố tình vẫn chạy trên runner miễn phí của GitHub (`ubuntu-latest`), không phải server của bạn — để việc chạy test suite (có thể tốn CPU/RAM) không tranh tài nguyên với staging/production đang chạy live trên cùng 1 máy.

## 2. Chuẩn bị server (làm 1 lần, thủ công)

Việc này Claude Code không thể tự làm thay bạn (không có quyền truy cập máy thật của bạn).

### 2.1. Cài Docker
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER   # để user hiện tại chạy docker không cần sudo
```

### 2.2. Cài GitHub Actions self-hosted runner
Vào repo trên GitHub → **Settings → Actions → Runners → New self-hosted runner**, chọn Linux, làm theo các lệnh GitHub hiển thị (dạng):
```bash
mkdir actions-runner && cd actions-runner
curl -o actions-runner.tar.gz -L https://github.com/actions/runner/releases/download/<version>/actions-runner-linux-x64-<version>.tar.gz
tar xzf actions-runner.tar.gz
./config.sh --url https://github.com/<org>/<repo> --token <token-github-cung-cap>
sudo ./svc.sh install
sudo ./svc.sh start
```
Cài làm **service** (`svc.sh install`) để runner tự khởi động lại cùng server. Đảm bảo user chạy service này nằm trong group `docker` (bước 2.1).

### 2.3. Tạo thư mục dữ liệu bền vững `/opt/odoo-cicd-data`

Đây là nơi giữ **mọi thứ không được phép mất khi checkout git đổi** (secrets, backup, trạng thái blue/green đang active, file routing Traefik) — tách biệt hoàn toàn khỏi thư mục mà Actions checkout code vào mỗi lần chạy (checkout sẽ dọn sạch file chưa commit).

```bash
sudo mkdir -p /opt/odoo-cicd-data/{backups/production,production,traefik/dynamic,traefik/letsencrypt}
sudo chown -R $USER:$USER /opt/odoo-cicd-data
```

Copy các file mẫu từ repo (sau khi `git clone` repo này ra một bản riêng để lấy template — thư mục này không cần giữ lại sau bước copy):
```bash
cp .env.staging.example    /opt/odoo-cicd-data/.env.staging
cp .env.production.example /opt/odoo-cicd-data/.env.production
cp traefik/.env.example    /opt/odoo-cicd-data/traefik/.env
cp traefik/docker-compose.traefik.yml /opt/odoo-cicd-data/traefik/
```
Mở và điền giá trị thật vào 3 file `.env*` (domain, mật khẩu).

### 2.4. Network & Traefik
```bash
docker network create proxy
cd /opt/odoo-cicd-data/traefik
docker compose -f docker-compose.traefik.yml up -d
```

### 2.5. Render file routing production lần đầu
```bash
export DOMAIN_PROD=app.yourdomain.com   # domain thật của bạn
envsubst '${DOMAIN_PROD}' \
  < traefik/dynamic/production.yml.template \
  > /opt/odoo-cicd-data/traefik/dynamic/production.yml
```
Từ đây, `scripts/deploy.sh` tự cập nhật riêng dòng URL trong file này ở mỗi lần deploy — không cần đụng tay lại.

### 2.6. Khởi động lần đầu (dùng image "bootstrap" tạm để tạo database rỗng)
```bash
docker compose -f docker-compose.staging.yml --env-file /opt/odoo-cicd-data/.env.staging up -d
docker compose -f docker-compose.prod.yml --env-file /opt/odoo-cicd-data/.env.production up -d odoo-blue
echo blue > /opt/odoo-cicd-data/production/.active_color
```

## 3. Cấu hình GitHub

1. **Settings → Environments**, tạo 2 environment: `staging` và `production`.
   - Với `production`, bật **Required reviewers** — bước duyệt thủ công trước khi lên production, giống việc Odoo.sh yêu cầu bạn tự tay kéo-thả merge staging→production.
2. Thêm **secret** `PRODUCTION_DB_PASSWORD` vào environment `production` (phải trùng giá trị `DB_PASSWORD` trong `/opt/odoo-cicd-data/.env.production`) — đây là secret **duy nhất** cần thiết, vì không còn SSH key nào phải quản lý nữa.
3. Runner đã đăng ký ở bước 2.2 sẽ tự nhận job có `runs-on: self-hosted`.

## 4. Quy trình làm việc hằng ngày

```
feature/xyz → PR → develop → PR → staging → PR (cần duyệt) → main
```

- Push/PR vào `develop`: CI tự build image, cài module với demo data, chạy toàn bộ test suite (`ci-develop.yml`, chạy trên cloud GitHub). Không có gì được deploy hay lưu lại — giống "development build" của Odoo.sh.
- Merge vào `staging`: `deploy-staging.yml` build image ngay trên server, làm mới database staging từ bản backup production mới nhất, vô hiệu hoá mail/cron/payment thật (`neutralize.sh`), rồi deploy và tự rollback nếu health check fail.
- Merge vào `main` (sau khi review): `deploy-production.yml` backup trước, chỉ chạy `-u <module>` nếu phát hiện version trong `__manifest__.py` thay đổi, dựng container màu chưa hoạt động (blue hoặc green), kiểm tra sức khoẻ, rồi mới chuyển traffic sang. Nếu fail, container cũ không hề bị đụng tới.

**Tăng version khi cần auto-update**: giống Odoo.sh, nếu bạn sửa view/logic mà cần Odoo tự chạy update module khi lên production, hãy tăng số `version` trong `__manifest__.py` của module đó. Không tăng version → không update, không backup tự động (commit được coi là an toàn).

## 5. Rollback thủ công

**Staging**: chạy lại deploy với image tag cũ (image vẫn còn trong Docker local nếu chưa bị dọn):
```bash
IMAGE=odoo-cicd:staging-<sha-cu> DATA_ROOT=/opt/odoo-cicd-data bash scripts/deploy.sh staging
```

**Production**: đơn giản nhất là vào tab Actions trên GitHub, chọn lần chạy `deploy-production.yml` ứng với commit cũ → **Re-run job** (image cũ vẫn có trong Docker local trên server nếu chưa bị `docker image prune`).

## 6. Xem log / debug

```bash
docker compose -f docker-compose.prod.yml --env-file /opt/odoo-cicd-data/.env.production logs -f odoo-blue    # hoặc odoo-green
docker compose -f docker-compose.staging.yml --env-file /opt/odoo-cicd-data/.env.staging logs -f odoo
cat /opt/odoo-cicd-data/production/.active_color                                                                # màu đang phục vụ traffic
```

## 7. Backup thủ công / lịch backup

Thêm vào crontab của server (`crontab -e`) — chạy từ một bản checkout cố định của repo (ví dụ giữ lại 1 bản tại `/opt/odoo-cicd-repo` chỉ để cron dùng, cập nhật bằng `git pull` định kỳ):
```cron
0 2 * * *   cd /opt/odoo-cicd-repo && DATA_ROOT=/opt/odoo-cicd-data bash scripts/backup.sh daily
0 3 * * 0   cd /opt/odoo-cicd-repo && DATA_ROOT=/opt/odoo-cicd-data bash scripts/backup.sh weekly
0 4 1 * *   cd /opt/odoo-cicd-repo && DATA_ROOT=/opt/odoo-cicd-data bash scripts/backup.sh monthly
```
Backup trước khi deploy (`pre-deploy`) đã được `deploy-production.yml` tự gọi trong workspace của runner, không cần thêm vào cron.

## 8. Lưu ý bảo mật khi dùng self-hosted runner

Self-hosted runner có toàn quyền trên server (chạy Docker, đọc/ghi file) — bất kỳ ai push được code vào các nhánh có trigger workflow (`develop`/`staging`/`main`) đều gián tiếp chạy được lệnh trên server bạn. Với 1 người dùng/1 team nhỏ tự quản lý repo, đây là đánh đổi chấp nhận được; nếu sau này mở repo cho cộng tác viên bên ngoài hoặc nhận PR từ fork lạ, cần giới hạn thêm (ví dụ: yêu cầu duyệt thủ công trước khi chạy workflow từ fork — GitHub có cơ chế này sẵn cho self-hosted runner).

## 9. Giới hạn đã biết của bản scaffold này

- **1 server duy nhất = không có dự phòng.** Nếu server này down, cả staging lẫn production đều down cùng lúc — không giống Odoo.sh thật (chạy trên hạ tầng nhiều máy). Đây là đánh đổi hợp lý khi mới bắt đầu; có thể tách production ra 1 máy riêng sau này mà không cần đổi lại kiến trúc (chỉ cần cài thêm 1 self-hosted runner gắn nhãn riêng, ví dụ `production-only`, và sửa `runs-on` trong `deploy-production.yml`).
- `neutralize.sh` dùng tên bảng/cột của Odoo 19.0 Community tiêu chuẩn (`ir_mail_server`, `ir_cron`, `payment_provider`, `delivery_carrier`). Nếu bạn tuỳ biến các model này hoặc dùng edition/version khác, hãy kiểm tra lại trước khi tin tưởng hoàn toàn.
- `detect_module_updates.sh` chỉ so sánh trường `version` trong `__manifest__.py` bằng `ast.literal_eval` — không phát hiện thay đổi dữ liệu/migration script nằm ngoài quy ước đó.
- Backup/restore dùng `docker exec` trực tiếp — phù hợp quy mô 1 server/team nhỏ; nếu database lớn, cân nhắc `pg_dump` dạng directory + nén song song để giảm thời gian backup.
