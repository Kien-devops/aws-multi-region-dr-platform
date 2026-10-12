# LAB 22 - File-service Deployment trên EC2

## 1. Mục tiêu

Chạy immutable `file-service` container trên hai private EC2, expose bằng hai ALB và một storage Global Accelerator riêng.

## 2. Thành phần sẽ xây dựng

- ECR image `app2-file-service:<COMMIT_SHA>`.
- Container bind mount `/mnt/dr-data:/mnt/dr-data`.
- `dr-sg-storage-alb`, `dr-tokyo-storage-alb`, `dr-file-global-accelerator`.
- Public DNS `files.example.com` trỏ tới storage accelerator; ACM certificate phù hợp với TLS design.
- Frontend GitOps configuration `FILE_SERVICE_BASE_URL=https://files.example.com`.
- File-service runtime configuration `CORS_ALLOWED_ORIGINS=https://app.example.com`.

## 3. Bối cảnh kiến trúc

```text
Users -> storage GA -> regional storage ALB -> private EC2 -> file-service -> NFS -> FSx
```

Không gắn storage ALB vào application accelerator listener: Global Accelerator không path-route, và EKS ALB do Kubernetes controller quản lý.

## 4. Điều kiện tiên quyết

- LAB 18-21; app2 CI đã publish immutable image tới Singapore và ECR replication tới Tokyo.
- Singapore mount RW; Tokyo destination DP/read-only.
- TLS certificate/DNS decision được ghi nhận. HTTP chỉ chấp nhận cho lab cô lập.
- `app.example.com` là frontend origin được phê duyệt; không dùng wildcard CORS trong production.

## 5. Quy ước đặt tên tài nguyên

ALB `dr-sg-storage-alb`, `dr-tokyo-storage-alb`; accelerator `dr-file-global-accelerator`; target group `dr-*-file-service-tg`.

## 6. Các bước triển khai

1. Qua SSM, login ECR bằng instance role và pull đúng digest/SHA. Không dùng static access key hoặc `latest`.
2. Singapore:

```bash
docker run -d --name file-service --restart unless-stopped \
  -p 8080:8080 \
  -e PORT=8080 \
  -e AWS_REGION=ap-southeast-1 \
  -e STORAGE_PATH=/mnt/dr-data \
  -e CORS_ALLOWED_ORIGINS=https://app.example.com \
  -v /mnt/dr-data:/mnt/dr-data \
  <SG_ECR_URI>:<COMMIT_SHA>
```

3. Tokyo chạy cùng digest/regional replica với `AWS_REGION=ap-northeast-1`. `/health` có thể OK; `/ready` phải false/read-only trước promotion.
4. Tạo internet-facing ALB trong hai public subnets mỗi Region; target type `instance`; register private EC2 port `8080`. Dùng `/ready` cho target eligibility để Tokyo read-only không được coi là endpoint phục vụ write.
5. ALB SG nhận listener từ Internet; EC2 SG chỉ nhận port `8080` từ ALB SG. TLS/ACM là production baseline.
6. Tạo standard accelerator riêng, listener theo TLS design, Singapore dial `100`, Tokyo `0`, endpoint weight dương. Nếu health check chỉ dùng `/health`, khi Singapore unhealthy Global Accelerator có thể đưa kết nối tới Tokyo dù storage còn read-only. Ưu tiên `/ready` eligibility kết hợp traffic dial/manual promotion gate; không dựa vào process liveness cho write routing.
7. Route 53 -> Create record `files.example.com` alias tới `dr-file-global-accelerator`. Gắn ACM certificate cho `files.example.com` tại ALB TLS listeners theo regional certificate requirements; HTTP redirect HTTPS.
8. Trong GitOps overlay frontend, đặt `FILE_SERVICE_BASE_URL=https://files.example.com`. Trong file-service runtime, đặt `CORS_ALLOWED_ORIGINS=https://app.example.com`; kiểm tra preflight và credential policy theo app contract.
9. Application CI chỉ build/test/scan/publish image và cập nhật Git desired state. Không chạy `kubectl apply`, không SSH/SSM vào EC2, không mutate ALB/GA trực tiếp.
10. Lưu runtime config bằng systemd unit hoặc container service file root-owned; không chứa secret. Logs chuyển CloudWatch hoặc retained Docker logs.

## 7. Xác minh

```bash
curl -fsS http://<SG_ALB_DNS>/health
curl -fsS http://<SG_ALB_DNS>/ready
curl -fsS http://<TOKYO_ALB_DNS>/health
curl -sS http://<TOKYO_ALB_DNS>/ready
```

Singapore ready/writable; Tokyo alive nhưng not-ready/read-only. Frontend `/files` gọi `https://files.example.com` và upload/list/download/delete/verify đi qua storage accelerator tới Singapore.

## 8. Kết quả mong đợi

Traffic storage bình thường chỉ tới Singapore; EC2 không public; Tokyo không nhận write trước promotion; frontend `/files` không phụ thuộc ALB/EKS hostname nội bộ.

## 9. Xử lý sự cố

- Target unhealthy: container logs, bind address/port, EC2 SG, health path.
- Tokyo bị GA xem healthy dù storage read-only: `/health` chỉ chứng minh process sống. Dùng `/ready` cho target eligibility và vẫn giữ traffic dial/manual promotion gate; không bật automatic write failover chỉ dựa trên health.
- Browser CORS lỗi: so sánh chính xác scheme/host/port của `app.example.com`, preflight response và `CORS_ALLOWED_ORIGINS`; không sửa bằng `*` khi dùng credentials.
- DNS/TLS lỗi: kiểm tra Route 53 alias, ACM certificate Region, listener certificate/SNI và security policy.
- Image mismatch: so sánh digest, không chỉ tag.

## 10. Lưu ý bảo mật

Upload size/path validation nằm trong app. ALB/WAF/auth là lớp riêng; checksum không thay authentication. EC2/FSx private; IAM pull-only.

## 11. Lưu ý chi phí

Hai ALB và accelerator thứ hai tính phí liên tục. Không tạo kiến trúc này nếu demo không cần public endpoint riêng.

## 12. Dọn dẹp / Quay lui

Đưa storage GA dial về Singapore, dừng Tokyo container, xóa ALB/accelerator theo thứ tự endpoint -> group -> listener -> accelerator.

## 13. Bằng chứng cần thu thập

Image digest, container config đã che secret, DNS/ACM, frontend `FILE_SERVICE_BASE_URL`, file-service CORS allowlist, ALB target health, GA endpoint state, `/health` và `/ready` hai Region.

## 14. Lab tiếp theo

[LAB 23 - ONTAP Planned Switchover](23-ontap-planned-switchover.md).
