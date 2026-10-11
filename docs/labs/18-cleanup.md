# LAB 18 - Dọn Dẹp Tài Nguyên Tránh Phát Sinh Chi Phí (Resource Cleanup)

## 1. Overview & Objective

Khi hoàn thành toàn bộ chuỗi 18 bài thực hành và diễn tập thành công trên AWS Console, việc dọn dẹp tài nguyên là bắt buộc để tránh phát sinh chi phí không mong muốn. Một lỗi phổ biến là cố gắng xóa VPC trước khi xóa các tài nguyên phụ thuộc (ENI, ALB, NAT Gateway), dẫn tới lỗi **Dependency Locking** và khiến người học bối rối.

Mục tiêu chính:
1. Nắm vững thứ tự hủy tài nguyên chuẩn xác theo chiều ngược lại của quá trình khởi tạo (Strict Reverse Dependency Teardown Order).
2. Xóa sạch sẽ toàn bộ tài nguyên đã tạo trên cả hai vùng Singapore (`ap-southeast-1`) và Tokyo (`ap-northeast-1`).
3. Đưa chi phí duy trì tài khoản AWS về **$0.00/tháng**.
4. Sử dụng script kiểm tra cuối cùng để đảm bảo không còn bất kỳ tài nguyên ẩn nào (đặc biệt là Unattached Elastic IPs và NAT Gateways) âm thầm phát sinh chi phí.

---

## 2. Architecture Diagram & Teardown Flow

```text
THỨ TỰ HỦY TÀI NGUYÊN BẮT BUỘC (REVERSE DEPENDENCY ORDER):

[ 1. Ingress & Argo CD Workloads ]  (Xóa Pods, Services, Ingress để giải phóng ALBs)
                 |
                 v
[ 2. AWS Load Balancers ]           (Đảm bảo ALBs và Target Groups đã bị xóa hoàn toàn)
                 |
                 v
[ 3. AWS Global Accelerator ]       (Disable -> Xóa Accelerator)
                 |
                 v
[ 4. EKS Managed Node Groups ]      (Hủy EC2 Worker Nodes và giải phóng ENIs)
                 |
                 v
[ 5. EKS Clusters ]                 (Hủy Control Plane)
                 |
                 v
[ 6. Aurora Global Database ]       (Tách/Xóa Tokyo Secondary -> Xóa Global DB -> Xóa SG Primary)
                 |
                 v
[ 7. Secrets Manager Secrets ]      (Xóa vĩnh viễn không chờ window)
                 |
                 v
[ 8. Inter-Region VPC Peering ]     (Xóa peering connection)
                 |
                 v
[ 9. NAT Gateways & Elastic IPs ]   (Xóa NAT Gateways và BẮT BUỘC Release Elastic IPs)
                 |
                 v
[ 10. Subnets, IGWs & VPCs ]        (Detach IGWs -> Xóa Subnets -> Xóa VPCs)
                 |
                 v
[ 11. ECR & IAM Roles ]             (Xóa kho chứa image và roles nếu không tái sử dụng)
```

---

## 3. Prerequisites & Pre-flight Checklist

- [ ] Toàn bộ bài đo đạc benchmark (Lab 17) đã hoàn tất và kết quả đã được ghi chép vào báo cáo.
- [ ] Đã sao lưu các manifests hoặc configs quan trọng nếu muốn lưu trữ offline.
- [ ] AWS CLI đã được cấu hình với quyền Admin trên máy trạm.
- [ ] Không có quy trình CI/CD nào đang chạy tự động push image hoặc update manifest.

---

## 4. Step-by-Step Implementation (Console-first + CLI)

### Bước 1: Xóa Ingress và Workloads Ứng Dụng
1. Mở terminal trên máy trạm, xóa Ingress trên cả hai cụm để AWS Load Balancer Controller tự động giải phóng Application Load Balancers:
   ```bash
   kubectl --context singapore -n app2 delete ingress app2-ingress
   kubectl --context tokyo -n app2 delete ingress app2-ingress
   ```
2. Xóa toàn bộ namespace `app2` trên cả 2 cụm:
   ```bash
   kubectl --context singapore delete namespace app2
   kubectl --context tokyo delete namespace app2
   ```
3. Đợi 2 - 3 phút. Mở EC2 Console -> **Load Balancers** tại cả Singapore và Tokyo: Đảm bảo danh sách trống.

### Bước 2: Vô Hiệu Hóa và Xóa AWS Global Accelerator
1. Mở Console **AWS Global Accelerator**.
2. Chọn accelerator `app2-global`.
3. Nhấn **Disable** (Tắt) -> Đợi trạng thái chuyển sang `Disabled`.
4. Nhấn **Delete** -> Nhập `delete` để xác nhận xóa vĩnh viễn.

### Bước 3: Xóa EKS Managed Node Groups và Clusters
Thực hiện lần lượt tại Singapore (`ap-southeast-1`) và Tokyo (`ap-northeast-1`):
1. Vào dịch vụ **EKS** -> Chọn cụm cluster (`dr-sg-eks` hoặc `dr-tokyo-eks`).
2. Chuyển sang tab **Compute**:
   - Chọn Node Group (`dr-sg-workers` hoặc `dr-tokyo-workers`) -> Nhấn **Delete node group**.
   - Xác nhận xóa và chờ khoảng 3-5 phút cho các máy ảo EC2 bị terminate.
3. Sau khi Node Group đã bị xóa hoàn toàn:
   - Nhấn nút **Delete cluster** ở góc trên bên phải.
   - Nhập tên cluster để xác nhận xóa.

### Bước 4: Xóa Amazon Aurora PostgreSQL Global Database
1. Mở dịch vụ **RDS** -> Databases.
2. **Xóa cụm Secondary tại Tokyo trước:**
   - Chuyển sang region Tokyo (`ap-northeast-1`).
   - Chọn DB instance `app2-tokyo-db-instance` -> **Actions** -> **Delete** (bỏ chọn snapshot cuối).
   - Chọn cụm `app2-tokyo-db` -> **Actions** -> **Delete** (hoặc *Remove from Global Database*).
3. **Xóa cụm Primary tại Singapore:**
   - Chuyển sang region Singapore (`ap-southeast-1`).
   - Chọn DB instance trong cụm `app2-sg-db` -> **Actions** -> **Delete**.
   - Khi không còn instance nào, chọn cụm `app2-sg-db` -> **Actions** -> **Delete** (Bỏ chọn *Create final snapshot*).
   - Xóa cụm Global Database `app2-global-db`.
4. **Xóa DB Subnet Groups:**
   - Vào RDS -> **Subnet groups** tại cả 2 vùng: Xóa `app2-sg-db-subnets` và `app2-tokyo-db-subnets`.

### Bước 5: Xóa AWS Secrets Manager Secrets
1. Vào **Secrets Manager** tại Singapore (`ap-southeast-1`).
2. Chọn secret `app2/database` -> **Actions** -> **Delete secret**.
3. Chọn tùy chọn **Delete immediately without recovery window** (Xóa ngay lập tức).
4. Kiểm tra tại Tokyo (`ap-northeast-1`) đảm bảo secret bản sao cũng đã bị xóa.

### Bước 6: Xóa VPC Peering Connection
1. Vào **VPC** Console -> **Peering connections**.
2. Chọn `dr-sg-to-tokyo-peering` -> **Actions** -> **Delete peering connection**.
3. Tích chọn xóa các route liên quan trên route tables của cả 2 đầu.

### Bước 7: Xóa NAT Gateways và Bắt Buộc Giải Phóng Elastic IPs
> [!WARNING]
> Xóa NAT Gateway không tự động giải phóng Elastic IP! Bạn phải chủ động Release Elastic IP, nếu không AWS sẽ tiếp tục tính phí IP nhàn rỗi.
1. **Tại Singapore:**
   - Vào VPC -> **NAT gateways** -> Chọn `dr-sg-nat-a` -> **Actions** -> **Delete NAT gateway**.
   - Đợi trạng thái chuyển sang `Deleted`.
   - Vào EC2 -> **Elastic IPs** -> Chọn IP vừa gắn với NAT Gateway -> **Actions** -> **Release Elastic IP addresses**.
2. **Tại Tokyo:**
   - Lặp lại tương tự cho `dr-tokyo-nat-a` và Elastic IP tại Tokyo.

### Bước 8: Xóa Internet Gateways, Subnets và VPCs
Thực hiện tại cả hai vùng:
1. Vào VPC -> **Internet gateways**:
   - Chọn IGW (`dr-sg-igw` hoặc `dr-tokyo-igw`) -> **Actions** -> **Detach from VPC**.
   - Sau đó chọn **Actions** -> **Delete internet gateway**.
2. Vào VPC -> **Subnets**:
   - Chọn toàn bộ subnets của VPC dự án -> **Actions** -> **Delete subnet**.
3. Vào VPC -> **Your VPCs**:
   - Chọn `dr-sg-vpc` (hoặc `dr-tokyo-vpc`) -> **Actions** -> **Delete VPC**.
   - AWS sẽ tự động xóa các Route Tables và Security Groups phụ thuộc đi kèm.

### Bước 9: Xóa ECR Repositories và IAM Roles (Tùy Chọn)
Nếu muốn dọn dẹp triệt để:
1. Vào **ECR** -> Repositories tại Singapore và Tokyo:
   - Xóa `app2-frontend`, `app2-backend-1`, `app2-backend-2`, `app2-backend-3`.
2. Vào **IAM** -> Roles:
   - Xóa `GitHubActions-App2-ECRPush` và các IAM Roles phục vụ IRSA / Load Balancer Controller.

---

## 5. Verification & Testing ($0 Cost Audit Script)

Chạy script kiểm tra audit tài nguyên sau trên máy trạm để chứng minh trạng thái sạch $0.00:

```bash
#!/bin/bash
echo "=== KIEM TRA TAI NGUYEN CON LAI TAI SINGAPORE (ap-southeast-1) ==="
aws ec2 describe-nat-gateways --region ap-southeast-1 --filter "Name=state,Values=available,pending" --query "NatGateways[*].NatGatewayId" --output text
aws ec2 describe-addresses --region ap-southeast-1 --query "Addresses[*].PublicIp" --output text
aws eks list-clusters --region ap-southeast-1 --output text
aws rds describe-db-clusters --region ap-southeast-1 --output text

echo "=== KIEM TRA TAI NGUYEN CON LAI TAI TOKYO (ap-northeast-1) ==="
aws ec2 describe-nat-gateways --region ap-northeast-1 --filter "Name=state,Values=available,pending" --query "NatGateways[*].NatGatewayId" --output text
aws ec2 describe-addresses --region ap-northeast-1 --query "Addresses[*].PublicIp" --output text
aws eks list-clusters --region ap-northeast-1 --output text
aws rds describe-db-clusters --region ap-northeast-1 --output text

echo "=== KIEM TRA GLOBAL ACCELERATOR ==="
aws globalaccelerator list-accelerators --query "Accelerators[*].Name" --output text
```

*Expected output:* Toàn bộ các câu lệnh trên đều không in ra bất kỳ tài nguyên nào (kết quả trống). Hệ thống đã đạt trạng thái sạch hoàn toàn **$0.00 Cost**.

---

## 6. Failure Modes & Troubleshooting

1. **Lỗi: Không thể xóa VPC do báo `Network interfaces still in use`:**
   - *Nguyên nhân:* Vẫn còn Application Load Balancer, EKS Node hoặc RDS Instance chưa xóa hoàn tất ENI trong VPC.
   - *Cách sửa:* Vào EC2 -> **Network Interfaces**, lọc theo VPC ID để tìm tài nguyên nào đang gắn với ENI đó và xóa tài nguyên gốc trước.
2. **Lỗi: Không thể xóa EKS Cluster do báo `Node group still active`:**
   - *Nguyên nhân:* Bắt buộc phải xóa Node Group và chờ EC2 instances terminated trước khi xóa Control Plane.
   - *Cách sửa:* Xóa Managed Node Group trước, đợi biến mất rồi xóa cluster.
3. **Lỗi: Vẫn bị tính tiền sau khi xóa hết labs:**
   - *Nguyên nhân:* Quên **Release Elastic IP** sau khi xóa NAT Gateway. Unattached Elastic IPs bị tính phí $0.005/giờ.
   - *Cách sửa:* Vào EC2 -> Elastic IPs -> Release tất cả IP tĩnh chưa gắn.

---

## 7. Production Hardening & Best Practices

- Luôn kiểm tra AWS Cost Explorer và AWS Budgets 24-48 giờ sau khi dọn dẹp để đảm bảo không có chi phí phát sinh ngoài ý muốn.
- Trong môi trường doanh nghiệp, sử dụng AWS CloudFormation hoặc Terraform để việc teardown diễn ra tự động và triệt để qua lệnh `terraform destroy`.

---

## 8. Security & IAM Guardrails

- Không lưu trữ các thông tin credentials (access keys, passwords) trên máy trạm sau khi lab hoàn thành.
- Thu hồi các quyền OIDC hoặc IAM Role đã tạo tạm thời.

---

## 9. Cost Estimation & Optimization (Review)

> [!NOTE]
> Mọi con số chi phí nêu ra trong tài liệu đều chỉ mang tính chất ước lượng tham khảo tại thời điểm viết bài (approximate only). Đơn giá dịch vụ AWS có thể thay đổi tùy thuộc vào cấu hình tài nguyên thực tế và chính sách giá của AWS. Luôn tra cứu AWS Pricing Calculator chính thức trước khi khởi tạo hạ tầng.

---

## 10. Rollback & Disaster Recovery Runbook

- Nếu việc xóa tài nguyên bị gián đoạn giữa chừng do lỗi mạng, chạy lại các bước tuần tự từ Bước 1 đến Bước 9 để hoàn tất dọn dẹp.

---

## 11. Next Steps & Handoff

Chúc mừng bạn đã hoàn thành trọn vẹn toàn bộ chuỗi 19 bài Labs thực hành nền tảng Multi-Region Disaster Recovery Platform trên AWS Console! 

Bước tiếp theo của dự án:
- Tổng hợp toàn bộ kinh nghiệm và kiến trúc đã kiểm chứng để chuyển đổi sang mô hình **Infrastructure as Code (IaC) với Terraform / OpenTofu**.
