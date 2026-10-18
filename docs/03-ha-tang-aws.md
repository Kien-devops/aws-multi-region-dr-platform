# Tài Liệu 03: Đặc Tả Hạ Tầng AWS & Cấu Hình Kỹ Thuật

Tài liệu này tổng hợp toàn bộ thông số kỹ thuật, cấu hình mạng, tài nguyên điện toán, lưu trữ và cơ chế triển khai của nền tảng AWS Multi-Region DR Platform.

---

## 1. Thông Tin Tài Khoản & Môi Trường

- **AWS Account ID**: `620306387033`
- **Primary Region**: `ap-southeast-1` (Singapore)
- **Secondary / DR Region**: `ap-northeast-1` (Tokyo)
- **Mã Nguồn Quản Lý Hạ Tầng (IaC)**: Terraform v1.5+ đặt tại [iac/terraform/](../iac/terraform)
- **Cơ Chế GitOps**: Argo CD v2.10+ đặt tại [gitops/app2/](../gitops/app2)

---

## 2. Phân Bổ Mạng & Kết Nối Liên Vùng (Networking)

| Vùng Địa Lý | Tên VPC | Dải Mạng CIDR | Subnets | Điểm Nổi Bật |
|---|---|---|---|---|
| **Singapore** | `dr-sg-vpc` | `10.10.0.0/16` | Public (2), Private App (2), Private DB/Storage (2) | NAT Gateways đa vùng sẵn sàng, Internet Gateway |
| **Tokyo** | `dr-tokyo-vpc` | `10.20.0.0/16` | Public (2), Private App (2), Private DB/Storage (2) | NAT Gateways đa vùng sẵn sàng, Internet Gateway |
| **Liên Vùng** | `pcx-sg-tokyo` | Inter-Region | Định tuyến chéo `10.10.0.0/16` $\leftrightarrow$ `10.20.0.0/16` | Phục vụ kết nối Inter-Cluster SVM SnapMirror và DB replication |

---

## 3. Cụm Điện Toán Amazon EKS & Quản Trị Cấu Hình GitOps

### 3.1. Thông Số Cụm EKS
- **Singapore Cluster**: `dr-sg-eks` (Kubernetes v1.29)
  - Node Group: Managed Node Group 2 nodes (`m5.large`).
  - Namespace ứng dụng: `app2`.
- **Tokyo Cluster**: `dr-tokyo-eks` (Kubernetes v1.29)
  - Node Group: Managed Node Group 2 nodes (`m5.large`).
  - Namespace ứng dụng: `app2`.

### 3.2. Cấu Trúc GitOps (Argo CD)
Toàn bộ tài nguyên Kubernetes được quản lý theo mô hình Kustomize:
- **`gitops/app2/base/`**: Định nghĩa cấu trúc chuẩn của 5 microservices, ingress, namespace.
- **`gitops/app2/overlays/singapore/`**: Thiết lập tài nguyên vùng chính: Replicas = 2, biến môi trường vùng Singapore, mount volume NFS Singapore.
- **`gitops/app2/overlays/tokyo/`**: Thiết lập tài nguyên vùng Warm Standby: Replicas = 1, mount volume NFS Tokyo qua địa chỉ IP `10.20.11.230` với thuộc tính `readOnly: false` để sẵn sàng ghi ngay khi volume chuyển sang trạng thái RW.

---

## 4. Cơ Sở Dữ Liệu: Amazon Aurora Global Database

- **Global Database Identifier**: `app2-global-db`
- **Engine Version**: PostgreSQL 15.4 (Aurora PostgreSQL)
- **Cụm Vùng Chính (Singapore)**:
  - Cluster Identifier: `app2-sg-db`
  - Writer Instance: `app2-sg-db-instance-1` (`db.r6g.large`)
  - Reader Instance: `app2-sg-db-instance-2` (`db.r6g.large`)
  - Trạng thái bình thường: `IsWriter: True`
- **Cụm Vùng Dự Phòng (Tokyo)**:
  - Cluster Identifier: `app2-tokyo-db`
  - Reader Instance: `app2-tokyo-db-instance-1` (`db.r6g.large`)
  - Reader Instance: `app2-tokyo-db-instance-2` (`db.r6g.large`)
  - Trạng thái bình thường: `IsWriter: False` (Read-only replica)

---

## 5. Lưu Trữ Tệp Tin: Amazon FSx for NetApp ONTAP

- **Hệ Thống Tệp Tin Singapore**:
  - File System ID: `fs-0955146589825df51`
  - SVM Name: `dr-sg-svm` (UUID: `23571f08-cb0e-11f1-b25b-d1d0614e9f77`)
  - Volume Name: `drdata` (Volume ID: `fsvol-00177e5706ea802e2`)
  - Giao thức: NFSv4.1
  - Dung lượng: 100 GiB (Loại volume: `RW`)
- **Hệ Thống Tệp Tin Tokyo**:
  - File System ID: `fs-0104cc857c91c78e2`
  - SVM Name: `dr-tokyo-svm` (UUID: `0edac83f-cb14-11f1-8f09-75ce6ba06232`)
  - Volume Name: `dr_data_dr` (Volume ID: `fsvol-0aa304f04e3efc058`)
  - Giao thức: NFSv4.1 (NFS IP: `10.20.11.230`, Export path: `/dr-data`)
  - Dung lượng: 100 GiB (Loại volume: `DP` trong điều kiện nhân bản; `RW` khi failover)
- **SnapMirror Relationship**:
  - UUID: `ce3ce815-cb1c-11f1-8f09-75ce6ba06232`
  - Source Path: `dr-sg-svm:drdata`
  - Destination Path: `dr-tokyo-svm:dr_data_dr`
  - Lịch sao chép: Đồng bộ gia tăng (Incremental transfer)

---

## 6. Phân Quyền & Bảo Mật (IAM & Security)

- **IAM Role Phục Vụ DR**:
  - `dr-fsx-orchestrator-role`: Cung cấp quyền gọi Lambda, truy cập SSM Parameter Store để lấy thông tin xác thực ONTAP API, quyền quản lý FSx volumes và đọc trạng thái RDS.
- **Quản Lý Bí Mật (Secrets Management)**:
  - Thông tin mật khẩu quản trị ONTAP được lưu trữ an toàn trong **AWS Secrets Manager** / **SSM Parameter Store**.
  - Ứng dụng EKS tích hợp **External Secrets Operator (ESO)** để đồng bộ thông tin kết nối cơ sở dữ liệu thành Kubernetes Secrets cục bộ mà không để lộ plain-text trong Git.
