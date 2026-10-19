# Kế Hoạch Dọn Dẹp Toàn Diện Tài Nguyên AWS (Cleanup Plan)

**Dự án:** AWS Multi-Region Disaster Recovery Platform  
**AWS Account ID:** `620306387033` (`arn:aws:iam::620306387033:user/kien-lvn`)  
**Vùng:** Singapore (`ap-southeast-1`) & Tokyo (`ap-northeast-1`)  
**Trạng thái kế hoạch:** **CHỜ PHÊ DUYỆT (PENDING OPERATOR APPROVAL)**

---

## 1. Nguyên Tắc & Ranh Giới An Toàn (Safety Boundaries)

1. **Tuyệt đối không chạm vào tài nguyên của dự án NT548 và các workload khác trong tài khoản:**
   - Database RDS: `nt548-mysql` (BẢO LƯU 100%).
   - Load Balancer: `nt548-shared-alb` và VPC `vpc-0ae0bf586b6f77479` (BẢO LƯU 100%).
   - ECR Repositories: toàn bộ `nt548-*` (`nt548-prod-*`, `nt548-dev-*`) (BẢO LƯU 100%).
   - Secrets Manager: `nt548/app-secrets`, `skycert-advisor/router-api` (BẢO LƯU 100%).
   - S3 Buckets: `nt548-*`, `serverless-portfolio-*`, `skycert-*`, `aws-sam-*`, `aws-quicksetup-*` (BẢO LƯU 100%).
   - EIPs không thuộc project: 3 EIPs tại Singapore và 2 EIPs tại Tokyo (BẢO LƯU 100%).
   - Lambda & DynamoDB: toàn bộ hàm và bảng của `nt548-*`, `skycert-*`, `serverless-portfolio-*` (BẢO LƯU 100%).
2. **Bảo toàn dữ liệu thực nghiệm & Dữ liệu thực tế:**
   - **Đã sao lưu toàn bộ nội dung nhị phân (Binary content) thực tế của 53 tệp tin** trên FSx ONTAP (bao gồm chứng chỉ PDF, router backups, ảnh JPG, các marker thực nghiệm) về thư mục cục bộ [docs/cleanup/backups/fsx/](backups/fsx/).
   - **Đã sao lưu toàn bộ 50 đơn hàng** trong cơ sở dữ liệu Aurora PostgreSQL về file cục bộ [docs/cleanup/backups/rds/orders_full.json](backups/rds/orders_full.json).
   - 100% bằng chứng khoa học, mốc RTO/RPO và log đối soát đã được lưu trữ an toàn trong Git.
   - Do đó, việc xóa tài nguyên trên AWS hoàn toàn không gây mất mát dữ liệu.
3. **Chi phí ngừng phát sinh:**
   - EKS Clusters ($0.10/h mỗi cụm) + 6 EC2 worker nodes (`m5.large`).
   - Aurora Global Database ($0.12/h mỗi instance db.t4g.medium + storage I/O).
   - FSx for NetApp ONTAP (2 file systems SSD dung lượng lớn + throughput capacity).
   - 2 NAT Gateways ($0.059/h mỗi NAT) + 2 Elastic IPs.
   - AWS Global Accelerator ($0.025/h).
   - Tổng chi phí ước tính tiết kiệm: **~$25 – $35 / ngày (~$750 – $1,050 / tháng)**.

---

## 2. Bảng Phân Loại Tài Nguyên (Resource Classification)

| Service | Tài nguyên cụ thể | Phân loại | Hành động dự kiến | Quản lý bởi |
|---|---|:---:|:---:|:---:|
| **EKS** | `dr-sg-eks`, NodeGroup `dr-sg-ng` (3 nodes) | PROJECT_OWNED | XÓA | Terraform |
| **EKS** | `dr-tokyo-eks`, NodeGroup `dr-tokyo-ng` (3 nodes) | PROJECT_OWNED | XÓA | Terraform / Console |
| **RDS Aurora** | Global Cluster `app2-global-db` | PROJECT_OWNED | XÓA | Console |
| **RDS Aurora** | Cluster `app2-sg-db` & Instance `app2-sg-db-1` | PROJECT_OWNED | XÓA | Console |
| **RDS Aurora** | Cluster `app2-tokyo-db` & Instance `app2-tokyo-db-1` | PROJECT_OWNED | XÓA | Console |
| **RDS Instance** | `nt548-mysql` (ap-southeast-1) | **UNRELATED (NT548)** | **BẢO LƯU NGUYÊN VẸN** | NT548 |
| **FSx ONTAP** | FS `fs-0955146589825df51`, SVM `dr-sg-svm`, Vol `drdata` | PROJECT_OWNED | XÓA | Terraform |
| **FSx ONTAP** | FS `fs-0104cc857c91c78e2`, SVM `dr-tokyo-svm`, Vol `dr_data_dr` | PROJECT_OWNED | XÓA | Terraform |
| **FSx Backup** | `backup-00f071578dd4c2908` (Tokyo automatic root backup) | PROJECT_OWNED | XÓA | Auto-FSx |
| **ELB / ALB** | `k8s-app2-app2ingr-4a5ceed8d3` (Singapore) | PROJECT_OWNED | XÓA qua K8s Ingress | AWS LBC Controller |
| **ELB / ALB** | `k8s-app2-app2ingr-47439970ff` (Tokyo) | PROJECT_OWNED | XÓA qua K8s Ingress | AWS LBC Controller |
| **ELB / ALB** | `nt548-shared-alb` (VPC `vpc-0ae0bf586b6f77479`) | **UNRELATED (NT548)** | **BẢO LƯU NGUYÊN VẸN** | NT548 |
| **Global Accel**| `dr-global-accelerator` | PROJECT_OWNED | XÓA | Console |
| **VPC Peering** | `pcx-0cbc2b7685a2cfe78` (SG <-> Tokyo) | PROJECT_OWNED | XÓA | Terraform |
| **VPC & NAT** | Singapore VPC `vpc-035e691629f36584e`, NAT `nat-03898959bf2c6e284` | PROJECT_OWNED | XÓA | Terraform |
| **VPC & NAT** | Tokyo VPC `vpc-014bd2b27411c1b8a`, NAT `nat-0136040978fdc339b` | PROJECT_OWNED | XÓA | Terraform |
| **Elastic IP** | `eipalloc-0854805aad7065c68` (`dr-sg-nat-eip`) | PROJECT_OWNED | GIẢI PHÓNG (RELEASE) | Terraform |
| **Elastic IP** | `eipalloc-0dd6a990f7f875305` (`dr-tokyo-nat-eip`) | PROJECT_OWNED | GIẢI PHÓNG (RELEASE) | Terraform |
| **Elastic IP** | 3 EIPs tại SG (`18.143.*`, `3.1.*`, `52.76.*`) & 2 tại Tokyo | **UNRELATED** | **BẢO LƯU NGUYÊN VẸN** | NT548/Khác |
| **Serverless** | 14 Lambda functions (`dr-fsx-failover-*`) tại Tokyo | PROJECT_OWNED | XÓA | Terraform |
| **Step Functions**| `dr-fsx-failover-state-machine` (Tokyo) | PROJECT_OWNED | XÓA | Terraform |
| **DynamoDB** | `dr-fsx-failover-approvals`, `dr-fsx-failover-lock` | PROJECT_OWNED | XÓA | Terraform |
| **DynamoDB** | `prod-dr-automation-LockStack-*`, `serverless-portfolio-*`, `skycert-*` | **UNRELATED / SHARED** | **BẢO LƯU NGUYÊN VẸN** | Khác |
| **Secrets Mgr** | `/app2/database` (SG & Tokyo), `/app2/ontap-credentials` | PROJECT_OWNED | XÓA (Immediate) | Terraform/Console |
| **Secrets Mgr** | `nt548/app-secrets`, `skycert-advisor/*` | **UNRELATED** | **BẢO LƯU NGUYÊN VẸN** | NT548/Khác |
| **ECR** | 5 repos tại SG & 5 repos tại Tokyo (`app2-*`) | PROJECT_OWNED | XÓA | Terraform |
| **ECR** | Tất cả repos `nt548-*` (dev, prod, product, order, user,...) | **UNRELATED (NT548)** | **BẢO LƯU NGUYÊN VẸN** | NT548 |
| **CloudWatch** | Logs EKS cluster, containerinsights, lambda `dr-fsx-*` | PROJECT_OWNED | XÓA | Terraform/Auto |
| **IAM** | 14 IAM roles cho EKS, LBC, CloudWatch, ESO, DR failover | PROJECT_OWNED | XÓA | Terraform |
| **S3** | `aws-multi-region-dr-platform-620306387033` | PROJECT_OWNED | GIỮ LẠI (State audit) | Terraform Backend |

---

## 3. Thứ Tự Xóa Chi Tiết (8 Giai Đoạn Tuần Tự)

### Giai đoạn 1: Xóa Kubernetes Ingress & AWS Global Accelerator
*Mục đích: Ngắt traffic, giải phóng ALB do AWS Load Balancer Controller quản lý trước khi xóa cụm EKS/VPC.*
1. `kubectl --context=singapore delete ingress app2-ingress -n app2`
2. `kubectl --context=tokyo delete ingress app2-ingress -n app2`
3. Theo dõi đến khi cả 2 ALB `k8s-app2-app2ingr-4a5ceed8d3` và `k8s-app2-app2ingr-47439970ff` hoàn tất xóa trong AWS.
4. Vô hiệu hóa và xóa Global Accelerator `dr-global-accelerator`:
   - Gỡ Endpoint groups Tokyo & Singapore.
   - Xóa Listener port 80.
   - Xóa Accelerator.

### Giai đoạn 2: Xóa Kubernetes Namespaces & Workloads
*Mục đích: Dỡ bỏ pods, service accounts và Pod Identity bindings.*
1. `kubectl --context=singapore delete namespace app2`
2. `kubectl --context=tokyo delete namespace app2`

### Giai đoạn 3: Tháo Gỡ và Xóa Aurora Global Database
*Mục đích: Tách rời cụm Global Cluster và xóa DB clusters mà không bị vướng phụ thuộc chéo.*
1. Gỡ cụm Reader Singapore `app2-sg-db` khỏi Global Cluster:
   `aws rds remove-from-global-cluster --global-cluster-identifier app2-global-db --db-cluster-identifier arn:aws:rds:ap-southeast-1:620306387033:cluster:app2-sg-db`
2. Gỡ cụm Writer Tokyo `app2-tokyo-db` khỏi Global Cluster:
   `aws rds remove-from-global-cluster --global-cluster-identifier app2-global-db --db-cluster-identifier arn:aws:rds:ap-northeast-1:620306387033:cluster:app2-tokyo-db`
3. Xóa Global Cluster rỗng `app2-global-db`:
   `aws rds delete-global-cluster --global-cluster-identifier app2-global-db`
4. Xóa DB Instance tại Singapore:
   `aws rds delete-db-instance --db-instance-identifier app2-sg-db-1 --skip-final-snapshot --region ap-southeast-1`
5. Xóa DB Instance tại Tokyo:
   `aws rds delete-db-instance --db-instance-identifier app2-tokyo-db-1 --skip-final-snapshot --region ap-northeast-1`
6. Xóa DB Cluster tại Singapore:
   `aws rds delete-db-cluster --db-cluster-identifier app2-sg-db --skip-final-snapshot --region ap-southeast-1`
7. Xóa DB Cluster tại Tokyo:
   `aws rds delete-db-cluster --db-cluster-identifier app2-tokyo-db --skip-final-snapshot --region ap-northeast-1`

### Giai đoạn 4: Dỡ Bỏ FSx for NetApp ONTAP & Backup
*Mục đích: Xóa volume dữ liệu, SVM và toàn bộ file system ONTAP 2 vùng.*
1. Xóa Volume dữ liệu `drdata` tại Singapore:
   `aws fsx delete-volume --volume-id fsvol-00177e5706ea802e2 --region ap-southeast-1`
2. Xóa Volume dữ liệu `dr_data_dr` tại Tokyo:
   `aws fsx delete-volume --volume-id fsvol-0aa304f04e3efc058 --region ap-northeast-1`
3. Xóa SVM `dr-sg-svm` (`svm-0d7a5a310c9ded152`) tại Singapore.
4. Xóa SVM `dr-tokyo-svm` (`svm-0c6499bac116da7a2`) tại Tokyo.
5. Xóa File System `fs-0955146589825df51` tại Singapore.
6. Xóa File System `fs-0104cc857c91c78e2` tại Tokyo.
7. Xóa automatic backup `backup-00f071578dd4c2908` tại Tokyo.

### Giai đoạn 5: Dọn Dẹp Serverless & State Machine (Tokyo)
1. Xóa Step Functions State Machine `dr-fsx-failover-state-machine`.
2. Xóa 14 Lambda functions `dr-fsx-failover-*`.
3. Xóa 2 DynamoDB tables `dr-fsx-failover-approvals` và `dr-fsx-failover-lock`.
4. Xóa SNS topic `dr-fsx-failover-notifications`.

### Giai đoạn 6: Dỡ Bỏ EKS Nodegroups & EKS Clusters
1. Xóa Node Group `dr-tokyo-ng` (Tokyo) và `dr-sg-ng` (Singapore), chờ EC2 instances tắt hẳn.
2. Xóa EKS Cluster `dr-tokyo-eks` (Tokyo) và `dr-sg-eks` (Singapore).
3. Xóa EKS Addons & Pod Identity Associations.

### Giai đoạn 7: Dọn Dẹp Network, NAT Gateways & VPCs
1. Xóa VPC Peering `pcx-0cbc2b7685a2cfe78`.
2. Xóa NAT Gateway `nat-03898959bf2c6e284` (Singapore) & `nat-0136040978fdc339b` (Tokyo).
3. Chờ NAT Gateway deleted, sau đó giải phóng chính xác 2 Elastic IPs của project:
   - `eipalloc-0854805aad7065c68` (Singapore)
   - `eipalloc-0dd6a990f7f875305` (Tokyo)
4. Xóa Subnets, Route Tables, Internet Gateways và Security Groups của `dr-sg-vpc` và `dr-tokyo-vpc`.
5. Xóa 2 VPCs: `vpc-035e691629f36584e` và `vpc-014bd2b27411c1b8a`.

### Giai đoạn 8: Dọn Dẹp ECR, Secrets Manager, CloudWatch Logs & IAM Roles
1. Xóa 5 ECR repos Singapore và 5 ECR repos Tokyo (`app2-*`) với `--force`.
2. Xóa Secrets Manager secrets `/app2/database` (2 vùng) và `/app2/ontap-credentials` (`--force-delete-without-recovery`).
3. Xóa CloudWatch Log Groups của EKS clusters và Lambda functions thuộc project.
4. Xóa 14 IAM roles và policy `App2DatabaseSecretReadPolicy`, `AWSLoadBalancerControllerIAMPolicy`.

---

## 4. Bảng Kế Hoạch Xác Nhận Tại Cổng Phê Duyệt (Approval Gate)

| STT | Dịch Vụ AWS | Vùng (Region) | Resource ID / Tên Cụ Thể | Quản Lý | Nguy Cơ Mất Dữ Liệu | Đã Có Backup Độc Lập Chưa? | Chi Phí Phát Sinh Nếu Giữ |
|:---:|---|:---:|---|:---:|:---:|:---:|---:|
| 1 | **Kubernetes Ingress / ALB** | SG & Tokyo | `k8s-app2-app2ingr-4a5ceed8d3`, `k8s-app2-app2ingr-47439970ff` | AWS LBC | Không (Stateless) | Có (Manifests GitOps trong Git) | ~$36/tháng |
| 2 | **Global Accelerator** | Global / US | `dr-global-accelerator` | Console | Không (Routing) | Có (Mã trong repo) | ~$18/tháng |
| 3 | **Aurora Global Database** | SG & Tokyo | `app2-global-db`, `app2-sg-db`, `app2-tokyo-db` | Console | Dữ liệu DB lab | Có (Đã lưu kết quả & CSVs trong Git) | ~$180/tháng |
| 4 | **FSx for NetApp ONTAP** | SG & Tokyo | `fs-0955146589825df51`, `fs-0104cc857c91c78e2` | Terraform | File metadata lab | Có (Đã lưu mã SHA-256 & file list) | ~$450/tháng |
| 5 | **EKS Clusters & Nodes** | SG & Tokyo | `dr-sg-eks`, `dr-tokyo-eks` (6 EC2 `m5.large`) | TF / Console | Không (Stateless) | Có (GitOps & Docker images) | ~$280/tháng |
| 6 | **NAT Gateways & EIPs** | SG & Tokyo | 2 NAT Gateways + 2 EIPs | Terraform | Không | Có (Terraform IaC) | ~$75/tháng |
| 7 | **Serverless DR Stack** | Tokyo | 14 Lambdas, 1 State Machine, 2 DDBs | Terraform | State điều phối | Có (Toàn bộ source code trong repo) | ~$0 - $5/tháng |
| 8 | **ECR & Secrets Manager** | SG & Tokyo | 10 ECR repos (`app2-*`), 3 Secrets | TF / Console | Image cache | Có (Mã nguồn app trong app2 repo) | ~$5/tháng |
| 9 | **VPCs & Peering** | SG & Tokyo | `dr-sg-vpc`, `dr-tokyo-vpc`, `pcx-0cbc2b7685a2cfe78` | Terraform | Không | Có (Terraform IaC) | Miễn phí |

**TỔNG TIẾT KIỆM DỰ KIẾN:** **~$1,044 / tháng (khoảng ~26.000.000 VNĐ / tháng)**.
