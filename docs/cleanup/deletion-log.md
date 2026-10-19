# Nhật Ký Thực Hiện Xóa Tài Nguyên (Deletion Log)

**Dự án:** AWS Multi-Region Disaster Recovery Platform  
**AWS Account ID:** `620306387033`  
**Thời gian thực hiện:** 2026-10-19 07:05:00 - 07:55:00 (UTC+7)  
**Người thực hiện:** Senior AWS Cloud Engineer  
**Trạng thái:** HOÀN TẤT THÀNH CÔNG (100% tài nguyên tính phí đã được dỡ bỏ)  
**Tác động chi phí:** Giảm chi phí phát sinh về **$0.00 / giờ** ($0.00 / tháng)

---

## 1. Tóm Tắt Kết Quả

| Nhóm Tài Nguyên | Trước Dọn Dẹp (Inventory Before) | Sau Dọn Dẹp (Inventory After) | Trạng Thái |
|---|---|---|:---:|
| **Aurora Global Database** | 1 Global DB, 2 Clusters, 2 Instances | 0 DB Clusters, 0 Instances | ✅ ĐÃ XÓA |
| **FSx for NetApp ONTAP** | 2 File Systems, 4 Volumes, 2 SVMs, SnapMirror | 0 File Systems, 0 Volumes, 0 SVMs | ✅ ĐÃ XÓA |
| **EKS Clusters & Nodes** | 2 Clusters, 2 Nodegroups, 6 EC2 instances | 0 Clusters, 0 Nodegroups, 0 Instances | ✅ ĐÃ XÓA |
| **Ingress & Traffic** | 2 ALBs, 1 Global Accelerator | 0 ALBs, 0 Global Accelerator | ✅ ĐÃ XÓA |
| **Serverless Orchestration** | 1 Step Function, 14 Lambdas, 2 DynamoDB, 1 SNS | 0 State Machines, 0 Lambdas, 0 DynamoDB, 0 SNS | ✅ ĐÃ XÓA |
| **ECR & Secrets** | 10 ECR Repos, 2 Secrets Manager Secrets | 0 Project ECR Repos, 0 Secrets | ✅ ĐÃ XÓA |
| **Networking & NAT** | 2 NAT GWs, 2 Project EIPs, VPC Peering | 0 NAT GWs, 0 Project EIPs, 0 Peering | ✅ ĐÃ GIẢI PHÓNG |
| **IAM Security** | 14 Project IAM Roles, 2 Managed Policies | 0 Project IAM Roles, 0 Policies | ✅ ĐÃ XÓA |
| **CloudWatch Logs** | Tất cả Log Groups của EKS, ContainerInsights, Lambda | 0 Project Log Groups | ✅ ĐÃ XÓA |

---

## 2. Nhật Ký Chi Tiết Từng Giai Đoạn

### Giai đoạn 1: Sao lưu Dữ liệu & Bằng chứng
- **FSx ONTAP Backup:** Tải và lưu trữ toàn bộ 53 file nhị phân thực tế từ Tokyo FSx ONTAP về thư mục `docs/cleanup/backups/fsx/` (chứng chỉ bảo mật, router backups, file thực nghiệm).
- **Aurora PostgreSQL Backup:** Trích xuất toàn bộ 50 đơn hàng cơ sở dữ liệu về `docs/cleanup/backups/rds/orders_full.json`.
- **Kiểm kê:** Xuất toàn bộ cấu hình hạ tầng trước khi xóa ra `docs/cleanup/inventory-before.json` (32 KB).

### Giai đoạn 2: Ingress & Traffic Management
- Đã xóa Kubernetes Ingress `app2-ingress` tại Singapore và Tokyo EKS.
- AWS ALB Ingress `k8s-app2-app2ingr-4a5ceed8d3` (SG) và `k8s-app2-app2ingr-47439970ff` (Tokyo) tự động được gỡ bỏ cùng toàn bộ Target Groups liên kết.
- AWS Global Accelerator `dr-global-accelerator` (`arn:aws:globalaccelerator::620306387033:accelerator/944e590d-27ae-4886-9db4-a95f9c54bb86`): Vô hiệu hóa và xóa hoàn tất.

### Giai đoạn 3: Workloads & Compute (EKS)
- Đã xóa namespace `app2` tại cả Singapore và Tokyo EKS.
- Xóa EKS Managed Nodegroups `dr-sg-ng` (Singapore) và `dr-tokyo-ng` (Tokyo).
- Toàn bộ 6 EC2 worker instances (`m5.large`) và các EBS volumes đính kèm đã được chấm dứt (terminated).
- Tắt tính năng Deletion Protection trên `dr-sg-eks` và thực hiện xóa thành công cả 2 cụm: `dr-sg-eks` và `dr-tokyo-eks`.

### Giai đoạn 4: Aurora Global Database
- Tách `app2-sg-db` và `app2-tokyo-db` ra khỏi Aurora Global Cluster.
- Xóa Aurora Global Database `app2-global-db`.
- Xóa DB instances `app2-sg-db-1` và `app2-tokyo-db-1` (`SkipFinalSnapshot=True`).
- Xóa cả 2 Aurora DB clusters `app2-sg-db` và `app2-tokyo-db`.

### Giai đoạn 5: FSx for NetApp ONTAP & SnapMirror
- Khởi chạy tác vụ quản trị ONTAP REST API / private CLI trong VPC để gỡ bỏ quan hệ SnapMirror `ce3ce815-cb1c-11f1-8f09-75ce6ba06232`.
- Gỡ bỏ quan hệ SVM Peering `dr-sg-svm` <-> `dr-tokyo-svm`.
- Xóa các FSx ONTAP Data Volumes: `fsvol-00177e5706ea802e2` (Singapore) và `fsvol-0aa304f04e3efc058` (Tokyo).
- Xóa các Storage Virtual Machines: `svm-0d7a5a310c9ded152` (Singapore) và `svm-0c6499bac116da7a2` (Tokyo).
- Xóa cả 2 FSx ONTAP File Systems: `fs-0955146589825df51` (Singapore) và `fs-0104cc857c91c78e2` (Tokyo).
- Xóa snapshot tự động `backup-00f071578dd4c2908`.

### Giai đoạn 6: Serverless & Orchestration
- Xóa AWS Step Functions State Machine `dr-fsx-failover-state-machine`.
- Xóa 14 hàm AWS Lambda `dr-fsx-failover-*`.
- Xóa 2 bảng DynamoDB: `dr-fsx-failover-approvals` và `dr-fsx-failover-lock`.
- Xóa SNS Topic: `dr-fsx-failover-notifications`.

### Giai đoạn 7: ECR, Secrets & CloudWatch Logs
- Xóa 10 ECR repositories `app2-*` trên cả 2 region.
- Xóa Secrets Manager secrets `/app2/database` và `/app2/ontap-credentials`.
- Xóa toàn bộ CloudWatch Log Groups của EKS cluster, Container Insights, và Lambda.

### Giai đoạn 8: Networking & IAM Security
- Xóa VPC Peering connection `pcx-0cbc2b7685a2cfe78`.
- Xóa cả 2 NAT Gateways: `nat-03898959bf2c6e284` (Singapore) và `nat-0136040978fdc339b` (Tokyo).
- Giải phóng 2 Elastic IPs của dự án: `eipalloc-0854805aad7065c68` và `eipalloc-0dd6a990f7f875305`.
- Xóa toàn bộ hạ tầng mạng Tokyo VPC (`vpc-014bd2b27411c1b8a`), bao gồm subnets, security groups, route tables, và IGW.
- Xóa toàn bộ hạ tầng mạng Singapore VPC (`vpc-035e691629f36584e`), bao gồm tất cả subnets, security groups, route tables, và IGW sau khi giải phóng ENI.
- Xóa 14 project IAM roles (`dr-sg-eks-*`, `dr-tokyo-eks-*`, `dr-fsx-failover-*`, `app2-github-actions-role`) và 2 IAM policies (`AWSLoadBalancerControllerIAMPolicy`, `App2DatabaseSecretReadPolicy`).

---

## 3. Xác Nhận An Toàn Hạ Tầng Chia Sẻ (Shared Resources Guardrails)
- **Tài nguyên NT548:** Các tài nguyên thuộc dự án NT548 (MySQL `nt548-mysql`, ALB `nt548-shared-alb`, VPC `vpc-0ae0bf586b6f77479`, các ECR repos `nt548-*`, secrets `nt548/app-secrets`, S3 buckets `nt548-*`) hoàn toàn **NGUYÊN VẸN 100%**, không bị ảnh hưởng.
- **S3 Terraform State:** Bucket `aws-multi-region-dr-platform-620306387033` được giữ nguyên để phục vụ tra cứu kiểm toán đồ án.
