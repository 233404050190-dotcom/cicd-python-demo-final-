# OIDC, Static API Keys và Secrets trong project

## Cơ chế project đang triển khai

- GitHub Actions dùng `GITHUB_TOKEN` để xác thực với GitHub Container Registry (GHCR).
- Workflow giới hạn quyền bằng `permissions: contents: read` và `packages: write` ở job cần push image.
- SSH private key, SSH host và webhook token/chat ID được lưu trong GitHub Actions Secrets hoặc Environment Secrets; không ghi giá trị thật vào repository.
- Máy Windows 11 chỉ pull image từ GHCR. Với cấu hình mẫu này, package `cicd-python-demo` phải được đặt ở chế độ Public để server pull mà không cần lưu PAT trên server.

## So sánh

| Tiêu chí | Static API Key / PAT | OIDC |
|---|---|---|
| Cách xác thực | Dùng credential cố định cho đến khi hết hạn/thu hồi | Dùng token ngắn hạn được cấp dựa trên danh tính workload |
| Lưu trữ | Thường cần lưu trong Secrets hoặc secret manager | Không cần lưu access key dài hạn ở GitHub nếu nhà cung cấp hỗ trợ federation |
| Rủi ro | Có thể bị lộ hoặc quên xoay vòng | Giảm rủi ro credential dài hạn; vẫn phải cấu hình trust policy đúng |
| Phạm vi phù hợp | Dịch vụ không hỗ trợ OIDC hoặc cần credential truyền thống | Cloud provider/registry hỗ trợ workload identity federation |

## Vì sao project chưa bật OIDC?

Đích triển khai hiện tại là một máy Windows 11 truy cập qua SSH, không phải một cloud provider có OIDC federation được cấu hình. Vì vậy, workflow dùng SSH key lưu trong GitHub Environment Secrets để kết nối máy chủ. GHCR dùng `GITHUB_TOKEN` do GitHub cấp cho từng lần chạy; đây không phải một Personal Access Token dài hạn.

Muốn triển khai OIDC thực tế cần có nhà cung cấp đích hỗ trợ tin cậy token của GitHub Actions (ví dụ cloud IAM). Không nên thêm `id-token: write` vào workflow nếu không có bước trao đổi OIDC token và trust policy tương ứng.
