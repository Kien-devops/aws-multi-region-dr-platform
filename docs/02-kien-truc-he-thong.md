# Tài Liệu 02: Kiến Trúc Hệ Thống & Luồng Dữ Liệu

---

## 1. Mô Hình Tổng Thể

Hệ thống được thiết kế theo mô hình **Warm Standby (Active-Passive)** phân tán qua hai vùng địa lý:
- **Singapore (`ap-southeast-1`)**: Đóng vai trò là **Primary Region (Active)**. Xử lý toàn bộ lưu lượng ghi của cơ sở dữ liệu và lưu lượng ghi của hệ thống tệp tin trong điều kiện vận hành bình thường.
- **Tokyo (`ap-northeast-1`)**: Đóng vai trò là **Disaster Recovery Region (Standby)**. Hạ tầng mạng, cụm EKS và các phân hệ ứng dụng luôn được duy trì sẵn sàng ở quy mô tối thiểu (Warm Standby). Cơ sở dữ liệu Aurora ở chế độ Read-Only và FSx Volume ở chế độ Data Protection (DP).

Chi tiết sơ đồ kiến trúc tham khảo tại: [docs/diagrams/01-multi-region-architecture.md](diagrams/01-multi-region-architecture.md).

---

## 2. Các Phân Hệ Cốt Lõi

### 2.1. Phân Hệ Định Tuyến Toàn Cầu (Global Ingress Tier)
- **AWS Global Accelerator**:
  - Cung cấp hai địa chỉ Static Anycast IP tĩnh toàn cầu: `75.2.109.112` và `99.83.197.80`.
  - Kết nối tới hai endpoint groups: Singapore ALB (Port 80) và Tokyo ALB (Port 80).
  - Điều khiển lưu lượng thông qua thuộc tính **Traffic Dial** (Mặc định: Singapore 100%, Tokyo 0%; khi chuyển vùng: Singapore 0%, Tokyo 100%).

### 2.2. Phân Hệ Ứng Dụng Microservices (EKS Workloads)
Ứng dụng mẫu `app2` gồm 5 dịch vụ thành phần:
1. **`app2-frontend` (Port 80/3000)**: Giao diện web người dùng, cung cấp các thao tác tạo đơn hàng và tải lên tài liệu.
2. **`app2-backend-1` (Port 8081)**: Dịch vụ tiếp nhận đơn hàng (Order Intake).
3. **`app2-backend-2` (Port 8082)**: Dịch vụ kiểm tra kho hàng (Inventory Validation).
4. **`app2-backend-3` (Port 8083)**: Dịch vụ kết nối PostgreSQL, thực thi các truy vấn ghi nhận đơn hàng và đảm bảo tính nhất quán ACID.
5. **`app2-file-service` (Port 8080)**: Dịch vụ quản lý tệp tin, tiếp nhận upload qua giao thức HTTP multipart, tính toán mã băm SHA-256 tức thời và lưu trữ trực tiếp lên phân vùng NFS dùng chung.

### 2.3. Phân Hệ Cơ Sở Dữ Liệu Phân Tán (Amazon Aurora Global Database)
- **Kiến trúc Storage Engine Replication**:
  - Không sử dụng Logical Replication truyền thống hay binlog, Aurora Global Database nhân bản ở tầng khối dữ liệu lưu trữ vật lý (Storage block-level replication).
  - Khi Singapore commit một giao dịch, các storage nodes của Aurora tự động sao chép các trang dữ liệu thay đổi sang cụm Tokyo với độ trễ truyền dẫn liên vùng trung bình dưới 1 giây.
- **Cấu hình cụm**:
  - Singapore: `app2-sg-db` (Cụm Primary Writer - 2 instances).
  - Tokyo: `app2-tokyo-db` (Cụm Cross-Region Read Replica - 2 instances).

### 2.4. Phân Hệ Lưu Trữ Tệp Tin Doanh Nghiệp (FSx for NetApp ONTAP)
- **Công nghệ SnapMirror**:
  - Thiết lập Inter-Cluster SVM Peering giữa `dr-sg-svm` (Singapore) và `dr-tokyo-svm` (Tokyo) thông qua Inter-Region VPC Peering.
  - Phân vùng nguồn: `drdata` (Singapore, kiểu RW).
  - Phân vùng đích: `dr_data_dr` (Tokyo, kiểu DP - Data Protection).
  - SnapMirror truyền tải các khối snapshot gia tăng (Incremental block updates), tối ưu hóa băng thông WAN và đảm bảo toàn vẹn dữ liệu hệ thống tệp.

---

## 3. Luồng Xử Lý Dữ Liệu Nghiệp Vụ

### 3.1. Luồng Ghi Đơn Hàng (Order Transaction Flow)
```text
Client
  ──> AWS Global Accelerator (Anycast IP)
  ──> Singapore ALB
  ──> app2-frontend
  ──> app2-backend-1 (Order API)
  ──> app2-backend-2 (Inventory Check)
  ──> app2-backend-3 (Database Operations)
  ──> Aurora Singapore Primary Writer (Commit ACID)
  ──= (Async Storage Replication < 1s) =──> Aurora Tokyo Reader Storage
```

### 3.2. Luồng Ghi Tệp Tin (File Upload Flow)
```text
Client
  ──> AWS Global Accelerator
  ──> Singapore ALB
  ──> app2-file-service (/api/v1/files)
  ──> Tính toán SHA-256 trên Stream & Ghi Metadata JSON
  ──> Lưu tệp tin vào /mnt/dr-data/ (NFS Mount tới FSx Singapore)
  ──= (SnapMirror Incremental Replication) =──> FSx Tokyo Volume (DP)
```
