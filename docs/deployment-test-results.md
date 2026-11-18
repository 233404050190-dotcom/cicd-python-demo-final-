# Báo cáo kiểm thử triển khai CI/CD

**Repository:** `cicd-python-demo-final-`  
**Ngày kiểm thử:** 18/11/2026  
**Nền tảng:** GitHub Actions, Docker, GitHub Container Registry (GHCR), Windows 11

## 1. Mục tiêu kiểm thử

Kiểm tra quy trình CI/CD tự động theo từng nhánh GitHub, triển khai ứng dụng bằng Docker Compose trên ba môi trường Development, Staging và Production; đồng thời kiểm tra health check và cơ chế rollback khi deployment thất bại.

## 2. Kết quả kiểm thử CI/CD

| Môi trường | Nhánh GitHub | CI run | CD run | Kết quả |
|---|---|---:|---:|---|
| Production | `main` | #22 | #22 | PASS |
| Staging | `develop` | #24 | #24 | PASS |
| Development | `feature/development-deploy-test` | #26 | #26 | PASS |

Các workflow CI và CD tương ứng đều hiển thị trạng thái thành công trên GitHub Actions.

## 3. Kết quả Health Check

| Môi trường | Địa chỉ kiểm tra | Kết quả |
|---|---|---|
| Production | `http://localhost:8000/health` | PASS |
| Staging | `http://localhost:8001/health` | PASS |
| Development | `http://localhost:8002/health` | PASS |

Kết quả phản hồi của ứng dụng:

**Production**
```json
{"environment":"production","service":"cicd-python-demo","status":"ok"}
```

**Staging**
```json
{"environment":"staging","service":"cicd-python-demo","status":"ok"}
```

**Development**
```json
{"environment":"development","service":"cicd-python-demo","status":"ok"}
```

Cả ba môi trường đều trả về `status: ok`.

## 4. Kiểm thử cơ chế Rollback

**Phạm vi:** Chỉ thực hiện trên môi trường Development.

### 4.1. Điều kiện ban đầu

- Development đang hoạt động bình thường.
- Health check trả về `status: ok`.
- Image triển khai ổn định đã được lưu trong state file và có sẵn trên máy TV1.

Image ổn định:

`ghcr.io/233404050190-dotcom/cicd-python-demo:sha-9467e81ed47253ce06f71759db20008b070b2b6c`

### 4.2. Cách thực hiện

Cố tình sử dụng image SHA không tồn tại trên GHCR:

`sha-0000000000000000000000000000000000000000`

Mục tiêu là tạo lỗi tại bước tải image để kiểm tra khả năng tự động rollback.

### 4.3. Kết quả

- Docker pull image mới: FAILED (image không tồn tại).
- Deployment: FAILED (đúng với kịch bản kiểm thử).
- Script tự động kích hoạt rollback.
- Docker khôi phục image ổn định trước đó.
- Health Check lần đầu: PENDING.
- Health Check lần thứ hai: PASS.
- Script ghi nhận `ROLLBACK SUCCESS`.
- Health check sau rollback trả về `status: ok`.

**Deployment exit code:** `1`.

Mã 1 là kết quả dự kiến vì phiên bản mới triển khai thất bại, dù quá trình rollback đã thành công.

**Kết luận:** Cơ chế rollback khi không tải được image mới đã hoạt động thành công trên Development.

## 5. Những giới hạn của kiểm thử

- Chưa kiểm thử riêng trường hợp image mới tải thành công, container khởi chạy nhưng ứng dụng không vượt qua Health Check.
- Rollback mới được kiểm chứng trên Development, chưa thực hiện trên Staging và Production.
- Chưa thực hiện kiểm thử rollback bằng một phiên bản lỗi thực tế.

Không xem các trường hợp chưa kiểm thử là đã đạt PASS.

## 6. Kết luận

Kết quả kiểm thử xác nhận:

1. CI/CD đã chạy thành công trên ba nhánh tương ứng với ba môi trường.
2. Ứng dụng hoạt động và vượt qua health check trên cả Development, Staging và Production.
3. Cơ chế rollback đã được kiểm chứng thành công khi image mới không tồn tại trên GHCR.
4. Sau rollback, môi trường Development được khôi phục và tiếp tục hoạt động bình thường.

**Kết luận chung:** Quy trình CI/CD nâng cao đã hoàn thành kiểm thử triển khai đa môi trường và kiểm thử rollback trong kịch bản image mới không thể tải xuống.
