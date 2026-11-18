# CI/CD Python Demo – Group 11, Topic 37

Dự án thực hành xây dựng quy trình CI/CD nâng cao cho ứng dụng Python Flask, sử dụng GitHub Actions, Docker, GitHub Container Registry (GHCR) và Self-hosted Runner trên Windows 11.

**Trạng thái triển khai:** Đã kiểm chứng CI/CD trên ba môi trường Development, Staging và Production. Cả ba môi trường đều vượt qua Health Check. Cơ chế rollback đã được kiểm thử thành công trên Development trong tình huống image mới không tồn tại trên GHCR.

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
   |       (các job kiểm thử độc lập)
   |
   +--> Quality và Test PASS
           |
           v
       Docker Build
           |
           v
       Push GHCR
       - sha-<commit>
       - development-latest
       - staging-latest
       - latest
           |
           v
       workflow_run: CI completed successfully
           |
           v
       Self-hosted Runner
       Windows 11 - TV1
           |
           +--> feature/* --> Development (8002)
           +--> develop   --> Staging     (8001)
           +--> main      --> Production  (8000)
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

**Nguyên tắc triển khai:** CI build và push image gắn với commit SHA. CD lấy đúng image SHA của commit đã vượt qua CI, không build lại source code.

## 2. Công nghệ và thành phần chính

| Thành phần | Công nghệ / File | Vai trò |
|---|---|---|
| Application | Python Flask, `app.py` | Ứng dụng demo và API |
| Lint và Format | Ruff | Kiểm tra chất lượng code |
| Automated Testing | Pytest | Unit Test và Integration Test |
| CI | `.github/workflows/ci.yml` | Kiểm thử, build và push image |
| CD | `.github/workflows/cd.yml` | Triển khai theo nhánh GitHub |
| Container | Dockerfile | Đóng gói ứng dụng |
| Registry | GHCR | Lưu trữ Docker image |
| Deployment | Docker Compose | Quản lý container theo môi trường |
| Self-hosted Runner | Windows 11 TV1 | Thực thi workflow triển khai |
| Health Check và Rollback | `scripts/deploy.ps1` | Kiểm tra ứng dụng và khôi phục image cũ |

## 3. Cấu trúc dự án

```text
.
├── .github/
│   └── workflows/
│       ├── ci.yml
│       ├── cd.yml
│       └── ruff.yml
├── docs/
│   ├── OIDC_VS_STATIC_KEYS.md
│   ├── VERIFICATION.md
│   └── deployment-test-results.md
├── envs/
│   ├── .env.dev
│   ├── .env.staging
│   └── .env.prod
├── scripts/
│   ├── deploy.ps1
│   ├── bootstrap_server.ps1
│   └── healthcheck_rollback.sh
├── tests/
│   ├── test_unit.py
│   └── test_integration.py
├── app.py
├── Dockerfile
├── docker-compose.yml
├── docker-compose.development.yml
├── docker-compose.staging.yml
├── docker-compose.prod.yml
├── requirements.txt
├── requirements-dev.txt
├── pyproject.toml
└── README.md
```

## 4. Luồng CI/CD theo nhánh

| Branch | CI | CD Environment | Port |
|---|---|---|---:|
| `feature/*` | Ruff, Test, Build và Push | Development | 8002 |
| `develop` | Ruff, Test, Build và Push | Staging | 8001 |
| `main` | Ruff, Test, Build và Push | Production | 8000 |
| Pull Request vào `main` hoặc `develop` | Ruff và Test | Không tự triển khai | — |

CI được kích hoạt khi có push lên các nhánh `main`, `develop`, `feature/**` hoặc pull request vào `main` và `develop`.

CD sử dụng sự kiện `workflow_run`, chỉ triển khai khi workflow `CI Pipeline` hoàn thành thành công và nguồn là sự kiện push.

Các nhánh feature dùng chung môi trường Development. Nhánh feature được triển khai sau cùng sẽ là phiên bản hiện tại ở cổng 8002.

## 5. Cấu hình GitHub Container Registry

Image repository:

```text
ghcr.io/233404050190-dotcom/cicd-python-demo
```

Các loại tag:

- `sha-<40 ký tự commit SHA>`: tag định danh phiên bản để triển khai.
- `development-latest`: phiên bản gần nhất của Development.
- `staging-latest`: phiên bản gần nhất của Staging.
- `latest`: phiên bản gần nhất của Production.

CI sử dụng `GITHUB_TOKEN` với quyền `packages: write` để push image.

CD sử dụng `GITHUB_TOKEN` với quyền `packages: read` và `docker/login-action@v3` để đăng nhập GHCR, sau đó pull image.

Repository GitHub cần được cấp quyền truy cập phù hợp vào GHCR package. Không cần lưu PAT dài hạn trong workflow.

## 6. Cấu hình Windows 11 và Self-hosted Runner

Máy TV1 đóng vai trò máy chủ triển khai.

Các thành phần cần có:

- Windows 11.
- Docker Desktop.
- Docker Engine chạy ở chế độ Linux containers.
- GitHub Actions Self-hosted Runner.
- Runner được đăng ký với các nhãn `self-hosted`, `Windows`, `X64`, `tv1`.

Trong GitHub repository, có thể kiểm tra runner tại:

**Settings → Actions → Runners**

Workflow CD sử dụng:

```yaml
runs-on: [self-hosted, Windows, X64, tv1]
```

Đảm bảo TV1 đang bật, Docker Desktop hoạt động và tiến trình Self-hosted Runner đang chạy để nhận deployment job.

Kiểm tra Docker trên TV1 bằng PowerShell:

```powershell
docker version
docker compose version
docker run --rm hello-world
```

Kiểm tra runner: cửa sổ runner phải hiển thị trạng thái `Listening for Jobs`.

**Lưu ý bảo mật:** Self-hosted Runner chỉ nên nhận các deployment job từ những nhánh và người dùng đáng tin cậy. Không cho phép mã nguồn pull request không tin cậy thực thi trên máy triển khai.

## 7. Quy trình CD trên Windows 11

Workflow CD thực hiện các bước:

1. Nhận kết quả hoàn thành thành công của CI.
2. Checkout đúng commit SHA đã vượt qua CI.
3. Kiểm tra Docker Engine.
4. Chuẩn bị thư mục triển khai `C:\cicd-python-demo`.
5. Sao chép Docker Compose, script deploy và các file môi trường.
6. Đăng nhập GHCR bằng `GITHUB_TOKEN`.
7. Xác định môi trường dựa trên nhánh nguồn.
8. Chạy `scripts/deploy.ps1` với môi trường và image SHA tương ứng.
9. Thực hiện Health Check.
10. Lưu phiên bản ổn định hoặc tự động rollback khi triển khai thất bại.

Các file trạng thái được lưu riêng theo môi trường trong:

```text
C:\cicd-python-demo\
├── scripts\
├── envs\
└── state\
    ├── development-image.txt
    ├── staging-image.txt
    └── production-image.txt
```

## 8. Kiểm tra ứng dụng

Trên máy TV1, truy cập:

| Môi trường | URL |
|---|---|
| Development | `http://localhost:8002/health` |
| Staging | `http://localhost:8001/health` |
| Production | `http://localhost:8000/health` |

Kết quả mong đợi là JSON có đúng tên môi trường và:

```json
{
  "status": "ok"
}
```

## 9. Health Check và Rollback

Script `scripts/deploy.ps1` chịu trách nhiệm triển khai và khôi phục phiên bản.

Quy trình:

1. Kiểm tra image tag và môi trường.
2. Pull image mới từ GHCR.
3. Đọc SHA của lần triển khai khỏe mạnh gần nhất từ state file.
4. Triển khai bằng Docker Compose.
5. Kiểm tra endpoint `/health` tối đa 12 lần.
6. Nếu Health Check thành công, cập nhật state file bằng image mới.
7. Nếu triển khai thất bại, khởi động lại image cũ và kiểm tra Health Check.
8. Nếu rollback thành công, ghi nhận `ROLLBACK SUCCESS`.

**Quy ước mã thoát:** Deployment mới thất bại vẫn trả exit code khác 0, kể cả khi rollback thành công. Điều này giúp GitHub Actions ghi nhận release thất bại thay vì đánh dấu deployment mới là thành công.

### Kết quả kiểm thử rollback

Nhóm đã thực hiện trên Development bằng cách sử dụng SHA không tồn tại trên GHCR:

```text
sha-0000000000000000000000000000000000000000
```

Kết quả:

- Pull image mới: FAILED, đúng kịch bản kiểm thử.
- Rollback: SUCCESS.
- Image cũ được khôi phục:

```text
sha-9467e81ed47253ce06f71759db20008b070b2b6c
```

- Health Check sau rollback: PASS.
- Ứng dụng Development tiếp tục trả về `status: ok`.

Chưa kiểm thử riêng trường hợp image mới tải thành công nhưng ứng dụng không vượt qua Health Check.

## 10. Kết quả kiểm thử thực tế

| Hạng mục | Kết quả |
|---|---|
| CI trên `main` | PASS |
| CD Production | PASS |
| CI trên `develop` | PASS |
| CD Staging | PASS |
| CI trên `feature/*` | PASS |
| CD Development | PASS |
| Health Check Production | PASS |
| Health Check Staging | PASS |
| Health Check Development | PASS |
| Rollback khi image mới không tồn tại | PASS |

Chi tiết và minh chứng được lưu tại:

[`docs/deployment-test-results.md`](docs/deployment-test-results.md)

## 11. Giới hạn và hướng phát triển

- Ba môi trường hiện dùng chung một máy Windows 11 TV1, được phân tách bằng Docker Compose project, container, cấu hình môi trường, state file và port. Đây là mô hình thực hành, chưa phải ba hạ tầng cô lập vật lý.
- Rollback mới được kiểm chứng trên Development trong tình huống pull image mới thất bại.
- Chưa kiểm thử riêng rollback do ứng dụng mới không vượt qua Health Check.
- OIDC được trình bày trong `docs/OIDC_VS_STATIC_KEYS.md` nhưng chưa triển khai federation với cloud IAM.
- Dự án dùng `GITHUB_TOKEN` cho quyền truy cập GHCR; không triển khai SSH trong luồng CD hiện tại.
- Chưa có TLS/HTTPS, reverse proxy, monitoring tập trung hoặc high availability.

## 12. Kết luận

Dự án đã xây dựng và kiểm chứng quy trình CI/CD tự động bằng GitHub Actions, Docker và GHCR trên ba môi trường Development, Staging và Production.

Self-hosted Runner trên Windows 11 TV1 thực thi quy trình triển khai tự động theo nhánh. Cả ba ứng dụng đều vượt qua Health Check. Cơ chế rollback đã được kiểm thử thành công trong tình huống image mới không tồn tại trên GHCR.

Đây là mô hình thực hành CI/CD nâng cao, có thể tiếp tục mở rộng với rollback do lỗi ứng dụng, HTTPS, monitoring và hạ tầng triển khai độc lập.
