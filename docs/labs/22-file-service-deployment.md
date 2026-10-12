# LAB 22 - File-service Deployment trên EC2

## 1. Mục tiêu

Chạy immutable `file-service` container trên hai private EC2, expose bằng hai ALB và một storage Global Accelerator riêng.

## 2. Thành phần sẽ xây dựng

- ECR image `app2-file-service:<COMMIT_SHA>`.
- Container bind mount `/mnt/dr-data:/mnt/dr-data`.
- `dr-sg-storage-alb`, `dr-tokyo-storage-alb`, `dr-file-global-accelerator`.
- Public DNS `files.example.com` trỏ tới storage accelerator; ACM certificate phù hợp với TLS design.
- Frontend GitOps configuration `FILE_SERVICE_BASE_URL`; base and regional defaults are empty until DNS/TLS is ready.
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
- Chốt runtime UID/GID `1000:1000`, NFS UNIX permissions và upload limit. Lab default `MAX_UPLOAD_BYTES=10485760` (10 MiB).

## 5. Quy ước đặt tên tài nguyên

ALB `dr-sg-storage-alb`, `dr-tokyo-storage-alb`; accelerator `dr-file-global-accelerator`; target group `dr-*-file-service-tg`.

### 6.1 Khởi chạy Container File-Service trên EC2 qua Session Manager

Thực hiện trên `dr-sg-storage-ec2` tại Singapore:

1. Đăng nhập Session Manager vào `dr-sg-storage-ec2`.
2. Tạo các thư mục cấu trúc cho `file-service` và gán quyền cho non-root user `1000:1000`:

```bash
sudo install -d -m 0770 -o 1000 -g 1000 \
  /mnt/dr-data/uploads /mnt/dr-data/metadata /mnt/dr-data/events
stat -c 'owner=%u group=%g mode=%a path=%n' \
  /mnt/dr-data /mnt/dr-data/uploads /mnt/dr-data/metadata /mnt/dr-data/events
```

3. Đăng nhập ECR bằng instance IAM profile và khởi chạy container:

```bash
# Lấy mật khẩu đăng nhập ECR
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com

# Khởi chạy container file-service (Singapore đóng vai trò Writeable)
docker run -d --name file-service --restart unless-stopped \
  --user 1000:1000 \
  -p 8080:8080 \
  -e PORT=8080 \
  -e AWS_REGION=ap-southeast-1 \
  -e STORAGE_PATH=/mnt/dr-data \
  -e MAX_UPLOAD_BYTES=10485760 \
  -e CORS_ALLOWED_ORIGINS=https://app.example.com \
  -v /mnt/dr-data:/mnt/dr-data \
  <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/app2-file-service:<COMMIT_SHA>

# Kiểm tra log container
docker logs -f file-service
```

4. Lặp lại thao tác trên cho `dr-tokyo-storage-ec2` tại Tokyo (sử dụng image từ ECR replica Tokyo và đặt biến `AWS_REGION=ap-northeast-1`). Tại Tokyo, container khởi động nhưng endpoint `/ready` sẽ báo `writable: false` do volume FSx Tokyo đang là Data Protection (DP/Read-only).

### 6.2 Tạo Security Group cho Storage ALB tại Singapore và Tokyo

#### Bước 1: Tạo SG cho ALB tại Singapore (`dr-sg-storage-alb-sg`)
1. Vào **VPC** -> **Security groups** tại Singapore -> nhấp **Create security group**.
2. **Name**: `dr-sg-storage-alb-sg`, **VPC**: `dr-sg-vpc`.
3. **Inbound rules**: Thêm rule HTTP (port `80`) và HTTPS (port `443`) từ `0.0.0.0/0`.
4. Nhấp **Create security group**.
5. Cập nhật Security Group của EC2 (`dr-sg-storage-ec2-sg`):
   - Chọn `dr-sg-storage-ec2-sg` -> **Edit inbound rules** -> thêm rule Custom TCP port `8080`, Source chọn `dr-sg-storage-alb-sg` -> nhấp **Save rules**.

#### Bước 2: Tạo SG cho ALB tại Tokyo (`dr-tokyo-storage-alb-sg`)
1. Lặp lại thao tác trên tại Tokyo trong VPC `dr-tokyo-vpc`, mở cổng `80`/`443` cho ALB và cập nhật `dr-tokyo-storage-ec2-sg` cho phép port `8080` từ ALB SG.

### 6.3 Tạo Target Group và Storage ALB tại Singapore

#### Bước 1: Tạo Target Group
1. Vào dịch vụ **EC2** tại Singapore -> menu bên trái chọn **Target Groups**.
2. Nhấp nút **Create target group** màu cam.
3. **Target type**: Chọn **Instances**.
4. **Target group name**: Nhập `dr-sg-file-service-tg`.
5. **Protocol**: `HTTP`, **Port**: `8080`.
6. **IP address type**: `IPv4`, **VPC**: `dr-sg-vpc`.
7. **Health checks**:
   - **Health check protocol**: `HTTP`.
   - **Health check path**: Nhập `/ready` (đảm bảo chỉ coi endpoint là Healthy khi storage có quyền ghi).
8. Nhấp nút **Next**.
9. Tại bước **Register targets**: Tích chọn instance `dr-sg-storage-ec2` -> cổng nhập `8080` -> nhấp nút **Include as pending below**.
10. Nhấp nút **Create target group**.

#### Bước 2: Tạo Application Load Balancer
1. Trong menu bên trái, chọn **Load Balancers** -> nhấp **Create load balancer**.
2. Chọn loại **Application Load Balancer** -> nhấp **Create**.
3. **Basic configuration**:
   - **Load balancer name**: Nhập `dr-sg-storage-alb`.
   - **Scheme**: Chọn **Internet-facing**.
   - **IP address type**: Chọn **IPv4**.
4. **Network mapping**:
   - **VPC**: Chọn `dr-sg-vpc`.
   - **Mappings**: Chọn 2 public subnets: `dr-sg-public-a` và `dr-sg-public-b`.
5. **Security groups**: Xóa nhóm mặc định, chọn `dr-sg-storage-alb-sg`.
6. **Listeners and routing**:
   - **Listener HTTP:80**: Forward to target group `dr-sg-file-service-tg`.
7. Nhấp nút **Create load balancer**. Chờ ALB chuyển sang trạng thái **Active**.

### 6.4 Tạo Target Group và Storage ALB tại Tokyo

Thực hiện tương tự tại Tokyo (`ap-northeast-1`):

1. Tạo Target Group mang tên `dr-tokyo-file-service-tg`, cổng `8080`, VPC `dr-tokyo-vpc`, Health check path `/ready`, đăng ký instance `dr-tokyo-storage-ec2`.
2. Tạo Application Load Balancer mang tên `dr-tokyo-storage-alb`, Internet-facing, phân bổ vào 2 public subnets `dr-tokyo-public-a` và `dr-tokyo-public-b`, Security group `dr-tokyo-storage-alb-sg`, Listener HTTP:80 forward tới `dr-tokyo-file-service-tg`.

### 6.5 Khởi tạo Storage Global Accelerator (`dr-file-global-accelerator`)

Tạo một Global Accelerator chuyên biệt riêng cho dịch vụ File Service:

1. Mở dịch vụ **AWS Global Accelerator** Console.
2. Nhấp nút **Create accelerator** màu cam.
3. **Accelerator name**: Nhập `dr-file-global-accelerator`, type **Standard**, IP type **IPv4** -> nhấp **Next**.
4. **Listeners**: Thêm port `80`, protocol **TCP**, Client affinity **None** -> nhấp **Next**.
5. **Endpoint groups**:
   - *Nhóm 1 (Singapore):*
     - **Region**: `ap-southeast-1`.
     - **Traffic dial**: `100`.
     - **Endpoint type**: `Application Load Balancer` -> chọn `dr-sg-storage-alb`, Weight: `128`.
   - *Nhóm 2 (Tokyo):*
     - Nhấp **Add endpoint group** -> chọn Region `ap-northeast-1`.
     - **Traffic dial**: `0` (do Tokyo FSx đang là Read-only, chưa sẵn sàng phục vụ lưu lượng ghi).
     - **Endpoint type**: `Application Load Balancer` -> chọn `dr-tokyo-storage-alb`, Weight: `128`.
6. Nhấp nút **Next** -> rà soát thông tin -> Nhấp nút **Create accelerator**.
7. Lưu lại **DNS name** của `dr-file-global-accelerator`.

### 6.6 Cấu hình DNS Alias và Frontend GitOps (Production Readiness)

1. **Route 53 (Tùy chọn):** Tạo bản ghi CNAME hoặc Alias A Record cho `files.example.com` trỏ tới DNS Name của `dr-file-global-accelerator`.
2. **Cập nhật GitOps cho app2 Frontend:**
   - Trong `gitops/app2/overlays/singapore/kustomization.yaml` và `tokyo/kustomization.yaml`, cập nhật giá trị biến `FILE_SERVICE_BASE_URL` trỏ tới URL của Storage Accelerator hoặc domain `https://files.example.com`. Cả hai Region đều trỏ về cùng một URL thống nhất, việc phân bổ vào SG hay Tokyo do trạng thái của Global Accelerator quyết định.

## 7. Xác minh

```bash
curl -fsS http://<SG_ALB_DNS>/health
curl -fsS http://<SG_ALB_DNS>/ready
curl -fsS http://<TOKYO_ALB_DNS>/health
curl -sS http://<TOKYO_ALB_DNS>/ready
```

Singapore ready/writable; Tokyo alive nhưng not-ready/read-only. Frontend `/files` gọi `https://files.example.com` và upload/list/download/delete/verify đi qua storage accelerator tới Singapore.

Upload/integrity tests must use files `<= MAX_UPLOAD_BYTES`. Default lab test sizes are 1 MiB and optional 10 MiB; a 100 MiB test requires an explicitly raised limit plus ALB/application timeout review.

## 8. Kết quả mong đợi

Traffic storage bình thường chỉ tới Singapore; EC2 không public; Tokyo không nhận write trước promotion. Rendered frontend manifest starts with an empty URL, then resolves to the same reviewed `https://files.example.com` in both overlays after operator configuration.

## 9. Xử lý sự cố

- Target unhealthy: container logs, bind address/port, EC2 SG, health path.
- Tokyo bị GA xem healthy dù storage read-only: `/health` chỉ chứng minh process sống. Dùng `/ready` cho target eligibility và vẫn giữ traffic dial/manual promotion gate; không bật automatic write failover chỉ dựa trên health.
- Browser CORS lỗi: so sánh chính xác scheme/host/port của `app.example.com`, preflight response và `CORS_ALLOWED_ORIGINS`; không sửa bằng `*` khi dùng credentials.
- DNS/TLS lỗi: kiểm tra Route 53 alias, ACM certificate Region, listener certificate/SNI và security policy.
- Image mismatch: so sánh digest, không chỉ tag.
- `EACCES`/readiness false: compare host and container UID/GID, NFS security style/export mapping, directory ownership and actual non-root write probes.
- Upload returns `413`: keep test size below `MAX_UPLOAD_BYTES` or approve a coordinated limit/timeout change.

## 10. Lưu ý bảo mật

Public upload/delete endpoints are acceptable only for a bounded lab with synthetic data and restricted source access. Production requires authentication/authorization per operation, WAF/rate limiting, filename/path and content-type validation, size enforcement, audit logs, quarantine/malware scanning before trusted consumption, and retention/deletion policy. CORS is browser policy, **not authentication or authorization**. Checksum detects corruption; it does not prove uploader identity or content safety. EC2/FSx remain private; IAM is pull-only.

## 11. Lưu ý chi phí

Hai ALB và accelerator thứ hai tính phí liên tục. Không tạo kiến trúc này nếu demo không cần public endpoint riêng.

## 12. Dọn dẹp / Quay lui

Đưa storage GA dial về Singapore, dừng Tokyo container, xóa ALB/accelerator theo thứ tự endpoint -> group -> listener -> accelerator.

## 13. Bằng chứng cần thu thập

Image digest, `stat /mnt/dr-data`, UID/GID and host/container write probes, `MAX_UPLOAD_BYTES`, container config đã che secret, DNS/ACM, rendered frontend `FILE_SERVICE_BASE_URL`, file-service CORS allowlist, ALB target health, GA endpoint state, `/health` và `/ready` hai Region.

## 14. Lab tiếp theo

[LAB 23 - ONTAP Planned Switchover](23-ontap-planned-switchover.md).
