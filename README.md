# CI/CD Python Demo – Group 11, Topic 37

Project thực hành quy trình CI/CD cho ứng dụng Python Flask, dùng GitHub Actions, Docker, GHCR và triển khai ba môi trường Development, Staging, Production trên Windows 11.

> **Trạng thái trung thực:** mã nguồn và cấu hình được chuẩn bị trong repository này. Việc triển khai thực tế vẫn cần cấu hình GitHub, GHCR, Windows 11 và kết nối SSH. Chỉ kết luận hệ thống chạy thành công sau khi có log CI/CD và kết quả Health Check trên máy Windows thật.

## 1. Kiến trúc tổng thể

```text
Developer
   |
   | push / pull request
   v
GitHub Repository
   |
   v
CI Pipeline
   +--> Ruff Lint + Format
   +--> Unit Test + Integration Test
   |       (hai job chạy độc lập)
   |
   +--> nếu cả Quality và Test PASS
           |
           v
       Docker Build
           |
           v
       Push GHCR
       - sha-<commit> (tag bất biến dùng để deploy)
       - development-latest / staging-latest / latest
           |
           v
       workflow_run: CI Pipeline completed successfully
           |
           +--> feature/* --> Development (port 8002)
           +--> develop   --> Staging     (port 8001)
           +--> main      --> Production  (port 8000)
                                  |
                                  v
                           Pull image GHCR
                                  |
                                  v
                           Docker Compose up
                                  |
                                  v
                              /health
                              /     \
                            PASS    FAIL
                             |       |
                         Save SHA  Restore previous
                         as stable image + Health Check
```

**Nguyên tắc quan trọng:** CD không build lại source. CD lấy đúng image `sha-<commit>` do CI của commit đó build và push sau khi kiểm thử thành công. Nhờ vậy, image được triển khai là image gắn với commit đã qua CI.

## 2. Thành phần chính

| Thành phần | File / thư mục | Vai trò |
|---|---|---|
| Flask app | `app.py` | Trang demo, API greeting, endpoint `/health` |
| Unit Test | `tests/test_unit.py` | Kiểm tra hàm `make_greeting()` |
| Integration Test | `tests/test_integration.py` | Kiểm tra HTTP route và nội dung JSON |
| Ruff | `.github/workflows/ruff.yml`, `pyproject.toml` | Lint và format Python |
| CI | `.github/workflows/ci.yml` | Quality, Test, Build và Push GHCR |
| CD | `.github/workflows/cd.yml` | Chọn môi trường theo branch và triển khai qua SSH |
| Docker | `Dockerfile` | Multi-stage build, pip BuildKit cache, non-root user, HEALTHCHECK |
| Compose | `docker-compose*.yml` | Cấu hình local và ba môi trường server |
| Windows deploy | `scripts/deploy.ps1` | Pull image, triển khai, Health Check và Rollback |
| Windows bootstrap | `scripts/bootstrap_server.ps1` | Chuẩn bị OpenSSH và thư mục trên Windows 11 |
| Linux helper | `scripts/healthcheck_rollback.sh` | Deploy/check/rollback khi chạy Compose trên Linux |
| OIDC note | `docs/OIDC_VS_STATIC_KEYS.md` | So sánh OIDC, Static Key và cơ chế thực tế project dùng |

`Dockerfile` là file được CI sử dụng. `Dockerfile.single` chỉ là mẫu single-stage để đối chiếu trong phần thực hành, không được workflow CI sử dụng.

## 3. Chạy thử tại máy phát triển

Yêu cầu: Python 3.12 trở lên và Docker Desktop nếu muốn chạy bằng container.

### 3.1. Tạo môi trường Python và cài dependency

Windows PowerShell:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
```

Linux/macOS:

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-dev.txt
```

### 3.2. Chạy kiểm tra chất lượng và test

```bash
ruff check .
ruff format --check .
python -m pytest tests/ -v
```

### 3.3. Chạy bằng Docker Compose local

```bash
docker compose up -d --build
docker compose ps
docker compose logs -f web
```

Mở trình duyệt:

- `http://localhost:8000/`
- `http://localhost:8000/health`
- `http://localhost:8000/api/greeting?name=An`

Dừng ứng dụng:

```bash
docker compose down
```

## 4. Luồng branch và môi trường

| Branch | CI | Image channel tag | Môi trường CD |
|---|---|---|---|
| `feature/*` | Ruff + Test + Build/Push | `development-latest` | Development, port 8002 |
| `develop` | Ruff + Test + Build/Push | `staging-latest` | Staging, port 8001 |
| `main` | Ruff + Test + Build/Push | `latest` | Production, port 8000 |
| Pull Request vào `main`/`develop` | Ruff + Test | Không push image | Không deploy |

Development được dùng chung cho các nhánh `feature/*`. Vì vậy, nhánh feature nào deploy sau cùng sẽ là phiên bản hiển thị tại Development.

CD lắng nghe sự kiện `workflow_run` của workflow có tên **CI Pipeline**. CD chỉ chạy khi workflow nguồn là sự kiện `push` và có kết luận `success`. Pull Request không kích hoạt deploy.

## 5. Chuẩn bị GHCR

Image repository được cấu hình cố định trong source:

```text
ghcr.io/233404050190-dotcom/cicd-python-demo
```

Nếu repository GitHub của nhóm thuộc owner khác, cần thay namespace đồng nhất tại:

- `.github/workflows/ci.yml`
- `scripts/deploy.ps1`
- `scripts/healthcheck_rollback.sh`

CI sử dụng `GITHUB_TOKEN` với quyền `packages: write` để push image lên GHCR. Máy Windows pull image không kèm credential, do đó package phải ở chế độ **Public**.

### Thiết lập package lần đầu

1. Push source lên GitHub và để CI chạy lần đầu nhằm tạo GHCR package.
2. Mở tab Packages của owner `233404050190-dotcom`, vào package `cicd-python-demo` → **Package settings**.
3. Đổi package visibility thành **Public**. Chỉ public package demo không chứa dữ liệu nhạy cảm; tuyệt đối không đưa secret hoặc file `.env` chứa mật khẩu vào Docker image.
4. Nếu CD của lần push đầu chạy trước khi package được public và thất bại khi pull image, sau khi đổi visibility hãy push một commit mới hoặc rerun CI để tạo một sự kiện hoàn tất CI mới.
5. Kiểm tra từ Windows server:

```powershell
docker pull ghcr.io/233404050190-dotcom/cicd-python-demo:latest
```

Repository Public không tự động đồng nghĩa package Public. Phải kiểm tra riêng visibility của GHCR package.

## 6. Chuẩn bị Windows 11 Demo Server

Máy Windows đóng vai trò server triển khai. Những bước dưới đây cần làm một lần bằng tài khoản Windows sẽ được dùng để SSH và chạy Docker.

### 6.1. Cài Docker Desktop

1. Cài Docker Desktop và bật WSL 2/Linux containers.
2. Mở Docker Desktop, chờ Docker Engine ở trạng thái running.
3. Trong PowerShell của đúng tài khoản deploy, chạy:

```powershell
docker version
docker compose version
docker run --rm hello-world
```

Docker Desktop cần tiếp tục chạy trong phiên người dùng deploy khi workflow thực hiện triển khai.

### 6.2. Bootstrap OpenSSH và thư mục deploy

Mở PowerShell bằng **Run as Administrator**. Nên chạy script bằng chính tài khoản Windows sẽ dùng làm `SSH_USER` để ACL được cấp cho đúng tài khoản:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\bootstrap_server.ps1
```

Script cài/bật OpenSSH Server, tạo firewall rule SSH và tạo thư mục:

```text
C:\cicd-python-demo\
  scripts\
  envs\
  state\
```

Mặc định firewall rule cho phép TCP/22 từ mọi địa chỉ. **Không nên để nguyên cấu hình này khi expose server lên Internet.** Hãy giới hạn `AllowedSshRemoteAddress` theo mạng được phép hoặc dùng giải pháp VPN/self-hosted runner phù hợp với hạ tầng của nhóm. GitHub-hosted runner không thể truy cập địa chỉ LAN riêng như `192.168.x.x` nếu không có kết nối mạng được thiết lập.

### 6.3. Tạo SSH key

Trên máy quản trị an toàn, tạo cặp khóa Ed25519 không có passphrase (để runner dùng non-interactive):

```powershell
ssh-keygen -t ed25519 -C "github-actions-cicd" -N "" -f "$env:USERPROFILE\.ssh\cicd_deploy"
```

- `cicd_deploy` là **private key**. Lưu nội dung vào GitHub Environment Secret `SSH_PRIVATE_KEY`. Không commit hoặc gửi file này vào báo cáo.
- `cicd_deploy.pub` là **public key**. Thêm một dòng của file này vào `authorized_keys` của tài khoản Windows deploy.

Tạo file:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.ssh"
notepad "$env:USERPROFILE\.ssh\authorized_keys"
```

Nếu tài khoản nằm trong nhóm Administrators, Windows OpenSSH có thể dùng `C:\ProgramData\ssh\administrators_authorized_keys` thay cho file trong profile. Cần thiết lập ACL đúng theo cấu hình OpenSSH của máy. Ví dụ, với tài khoản thường, sau khi tạo `authorized_keys`, có thể giới hạn quyền file cho chính tài khoản và SYSTEM:

```powershell
$AuthorizedKeys = "$env:USERPROFILE\.ssh\authorized_keys"
$Account = whoami
icacls $AuthorizedKeys /inheritance:r
icacls $AuthorizedKeys /grant "${Account}:(R)" /grant "SYSTEM:(F)"
```

Với tài khoản thuộc Administrators, kiểm tra file `C:\ProgramData\ssh\administrators_authorized_keys` và ACL theo yêu cầu OpenSSH của Windows (thường chỉ Administrators và SYSTEM được truy cập). Không áp dụng lệnh ACL của tài khoản thường cho file administrators.

Kiểm tra kết nối SSH từ một máy khác trước khi cấu hình GitHub Actions:

```powershell
ssh -i "$env:USERPROFILE\.ssh\cicd_deploy" -p 22 <WINDOWS_USER>@<PUBLIC_IP_OR_DNS>
```

Chỉ sau khi xác minh đăng nhập bằng key thành công mới cân nhắc tắt Password Authentication trong `sshd_config`. Không thay đổi phương thức xác thực khi chưa có cách đăng nhập dự phòng để tránh tự khóa quyền truy cập máy chủ.

### 6.4. Kết nối từ GitHub-hosted runner

GitHub-hosted runner chạy ngoài mạng LAN. `SSH_HOST` phải là host mà runner truy cập được. Có thể cần public IP/DDNS và cấu hình NAT/port forwarding, nhưng không nên mở SSH công khai mà không giới hạn nguồn truy cập và không có biện pháp bảo vệ.

Nếu nhà mạng dùng CGNAT hoặc không thể mở cổng an toàn, phương án SSH từ GitHub-hosted runner sẽ không hoạt động trực tiếp. Khi đó cần chuyển sang VPN/overlay network đã cấu hình cho runner hoặc dùng self-hosted runner trên máy Windows. ZIP hiện tại triển khai theo phương án GitHub-hosted runner → SSH; chưa cấu hình VPN hay self-hosted runner.

Tạo `SSH_KNOWN_HOSTS` sau khi đã đối chiếu fingerprint host key trên server bằng kênh tin cậy. Trên Windows server:

```powershell
ssh-keygen -lf C:\ProgramData\ssh\ssh_host_ed25519_key.pub
```

Trên máy quản trị:

```bash
ssh-keyscan -p <SSH_PORT> <SSH_HOST>
```

So sánh fingerprint trước khi lưu dòng host key vào secret `SSH_KNOWN_HOSTS`. Không chấp nhận kết quả `ssh-keyscan` một cách mù quáng.

## 7. Cấu hình GitHub Environments và Secrets

Trong GitHub repository, vào **Settings → Environments**, tạo đúng ba Environment:

- `development`
- `staging`
- `production`

Trong mỗi Environment, khai báo các Secrets sau. Có thể dùng cùng một Windows server demo nhưng phải khai báo secret cho cả ba Environment vì từng job chỉ đọc secrets của environment mà nó sử dụng.

| Secret | Nội dung |
|---|---|
| `SSH_HOST` | Public IP hoặc DNS/DDNS có thể truy cập từ runner |
| `SSH_PORT` | Cổng SSH, ví dụ `22` |
| `SSH_USER` | Tài khoản Windows deploy |
| `SSH_PRIVATE_KEY` | Nội dung private key Ed25519, nhiều dòng |
| `SSH_KNOWN_HOSTS` | Host key đã xác minh, theo đúng host/port |

Trong **Settings → Secrets and variables → Actions → Repository secrets**, tạo một hoặc cả hai nhóm secret để gửi thông báo CI:

**Telegram:**

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID`

**Discord:**

- `DISCORD_WEBHOOK_URL`

Thiếu các secret thông báo thì workflow bỏ qua bước gửi tin; điều đó không làm thay đổi kết quả Quality/Test/Build. Lỗi gửi webhook cũng không làm CI chuyển thành Failed.

Nên bật **Required reviewers** cho Environment `production` nếu nhóm muốn giảng viên thấy bước phê duyệt trước deploy Production.

## 8. Triển khai theo trình tự

1. Đảm bảo toàn bộ workflow, Compose và script deploy đã được merge vào nhánh mặc định `main`. `workflow_run` dùng file CD ở nhánh mặc định.
2. Tạo nhánh `develop` từ `main` và push lên GitHub.
3. Tạo nhánh `feature/<ten-nhanh>` từ `develop`; push code để CI chạy. Khi CI thành công, CD deploy Development.
4. Kiểm tra Development: `http://<SERVER_HOST>:8002/` và `http://<SERVER_HOST>:8002/health`.
5. Push thay đổi lên `develop`; CI thành công thì CD deploy Staging.
6. Kiểm tra Staging: `http://<SERVER_HOST>:8001/` và `http://<SERVER_HOST>:8001/health`.
7. Tạo Pull Request `develop` → `main`, review rồi merge. CI chạy lại trên `main`; nếu thành công thì CD deploy Production.
8. Kiểm tra Production: `http://<SERVER_HOST>:8000/` và `http://<SERVER_HOST>:8000/health`.

Nếu cần truy cập các cổng web từ máy khác trong cùng LAN, có thể tạo rule giới hạn ở LocalSubnet:

```powershell
New-NetFirewallRule -DisplayName 'CI CD Demo Web Ports (LAN)' -Direction Inbound -Protocol TCP -LocalPort 8000,8001,8002 -RemoteAddress LocalSubnet -Action Allow
```

Nếu chỉ demo trên chính máy Windows bằng `localhost`, không cần mở các cổng này cho mạng ngoài. Các cổng ứng dụng là HTTP demo, chưa có TLS/HTTPS hoặc reverse proxy; không dùng như cấu hình Production thực tế ngoài Internet.

## 9. Cơ chế Health Check và Rollback

### 9.1. Windows 11 tự động qua `scripts/deploy.ps1`

Mỗi môi trường có một state file riêng:

```text
C:\cicd-python-demo\state\development-image.txt
C:\cicd-python-demo\state\staging-image.txt
C:\cicd-python-demo\state\production-image.txt
```

Quy trình:

1. Kiểm tra tag image `sha-<40 ký tự hex>` và chọn Compose file đúng môi trường.
2. Pull image SHA từ GHCR.
3. Đọc image SHA của lần triển khai khỏe mạnh gần nhất từ state file.
4. Deploy image mới bằng Docker Compose.
5. Gọi `/health` tối đa 12 lần, cách nhau 5 giây; chỉ xem là thành công khi JSON có `status: ok`.
6. Nếu đạt, ghi image mới vào state file.
7. Nếu thất bại, chạy lại image cũ và kiểm tra Health Check của image cũ. GitHub Actions vẫn ghi nhận deploy mới là Failed dù rollback thành công.
8. Nếu chưa có lần deploy thành công trước đó, script không thể rollback về một image chưa tồn tại; nó dừng deployment lỗi và báo rõ trường hợp first deployment.

### 9.2. Linux/local helper

`scripts/healthcheck_rollback.sh` là helper Bash cho môi trường Linux/local. Helper nhận environment, Compose file, image tag và health URL; lưu state riêng, deploy image mới, kiểm tra HTTP 200 và khôi phục image trước nếu lần deploy mới thất bại.

Ví dụ (cần thay SHA bằng tag thật đã push lên GHCR):

```bash
scripts/healthcheck_rollback.sh \
  staging \
  docker-compose.staging.yml \
  sha-0123456789abcdef0123456789abcdef01234567 \
  http://127.0.0.1:8001/health
```

CD Windows tự động dùng `scripts/deploy.ps1`, không gọi Bash helper.

## 10. Kiểm tra và minh chứng cần chụp cho báo cáo

Không ghi “đã triển khai thành công” chỉ dựa vào việc có file YAML. Nhóm cần chụp các minh chứng thật:

1. GitHub Actions: Ruff PASS.
2. GitHub Actions: Unit Test và Integration Test PASS.
3. GitHub Actions: Docker Build/Push GHCR thành công, có tag SHA.
4. GHCR package: image SHA tồn tại.
5. CD Staging: job SSH thành công, log `docker pull`, Compose deploy và Health Check PASS.
6. Trình duyệt/curl truy cập `/health` trên Staging.
7. CD Production: deploy thành công trên `main`.
8. Thử nghiệm lỗi có kiểm soát trên môi trường Development để chứng minh rollback. Chỉ làm sau khi Development đã có ít nhất một image thành công và state file đã được tạo. Có thể dùng một SHA hợp lệ về định dạng nhưng chắc chắn không được push, để `docker pull` thất bại và kích hoạt rollback:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\cicd-python-demo\scripts\deploy-development.ps1 -Environment development -ImageTag sha-0000000000000000000000000000000000000000
```

Lệnh dự kiến trả exit code khác 0 (lần release mới không tồn tại), nhưng log phải thể hiện `ROLLBACK SUCCESS` và ứng dụng cũ vẫn trả `/health` HTTP 200. Không chạy thử nghiệm này trên Production.
9. Telegram/Discord nhận thông báo CI PASS và FAIL.

## 11. Giới hạn hiện tại

- OIDC được giải thích trong `docs/OIDC_VS_STATIC_KEYS.md` nhưng chưa cấu hình federation với cloud IAM. GHCR sử dụng `GITHUB_TOKEN`; SSH private key và webhook token được lưu trong GitHub Secrets.
- Ba môi trường dùng chung một Windows 11 demo server và chỉ khác Compose project, container name, environment config, state file và host port. Đây là mô hình học tập, không phải ba hạ tầng cô lập vật lý.
- GHCR package được giả định là Public để server pull không cần credential registry dài hạn.
- SSH connectivity, Windows Docker Desktop, GitHub Environment/Secrets, quyền GHCR và Webhook phải được nhóm cấu hình/kiểm tra bên ngoài source code.
- HTTP chưa có TLS/HTTPS, chưa có Nginx reverse proxy, monitoring tập trung hoặc hạ tầng HA.
- CI/CD permission validation
- Staging deployment test
- Development deployment test
