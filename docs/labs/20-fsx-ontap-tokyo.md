# LAB 20 - FSx for NetApp ONTAP Tokyo

## 1. Mục tiêu

Khởi tạo và cấu hình hệ thống tệp lưu trữ phân tán **Amazon FSx for NetApp ONTAP** tại Tokyo (`ap-northeast-1`), đóng vai trò là **Destination / Standby Volume (Data Protection - DP)** sẵn sàng tiếp nhận luồng đồng bộ SnapMirror định kỳ từ Singapore, đáp ứng kiến trúc DR Warm-Standby.

## 2. Thành phần xây dựng

- **File System:** `dr-tokyo-fsx-ontap` (ID: `fs-0104cc857c91c78e2`), Deployment Type: `Single-AZ (SINGLE_AZ_1)`.
- **Storage Virtual Machine (SVM):** `dr-tokyo-svm` (ID: `svm-0c6499bac116da7a2`).
- **Destination Volume:** `dr_data_dr` (Type: `DP` - Data Protection, Dung lượng: 10 GiB) *(Lưu ý: Tên volume không dùng dấu gạch ngang, đặt là `dr_data_dr`)*.
- **Junction Path:** `/dr-data` (Mount read-only cho client và pod kiểm tra dữ liệu).
- **Security Group:** `dr-tokyo-fsx-sg` (`sg-0333ec462c106afaf`) mở cổng NFS, SSH, HTTPS, SnapMirror 11104-11105 và ICMP.
- **Client Mount:** Mount NFS v4.1 chế độ Read-Only (`ro`) tại `/mnt/dr-data` trên Tokyo EKS Worker Nodes / EC2 Storage Instance.

## 3. Bối cảnh kiến trúc

```text
[ Singapore drdata (RW) ]
            │
            ▼ (SnapMirror Replication qua VPC Peering)
[ Tokyo dr-tokyo-svm (Volume: dr_data_dr - DP) ]
   (Management IP: 10.20.11.183)
   (Intercluster IPs: 10.20.11.215, 10.20.11.142)
   (NFS Endpoint: 10.20.11.230)
            │
            ▼ (NFS v4.1 Read-Only: -o ro)
[ Tokyo EKS Worker Nodes / App2 File Service ]
```

## 4. Điều kiện tiên quyết

- LAB 19 hoàn tất; Volume nguồn `drdata` tại Singapore đã hoạt động.
- VPC Peering `pcx-0cbc2b7685a2cfe78` và route liên vùng `10.10.0.0/16` $\leftrightarrow$ `10.20.0.0/16` thông suốt.
- Mật khẩu quản trị thống nhất: `App2SecureAdmin_2026!`.

## 5. Quy ước đặt tên tài nguyên

| Tài nguyên | Tên quy ước | ID / Thông số thực tế | Ghi chú |
|---|---|---|---|
| **File System** | `dr-tokyo-fsx-ontap` | `fs-0104cc857c91c78e2` | Single-AZ, 1024 GiB SSD, 128 MB/s |
| **SVM** | `dr-tokyo-svm` | `svm-0c6499bac116da7a2` | Root Volume: `dr_tokyo_svm_root` |
| **Volume (DP)** | `dr_data_dr` | `vol-065e1db0b3886fc8f` | Type: `DP`, Size: 10 GiB, Junction: `/dr-data` |
| **Security Group** | `dr-tokyo-fsx-sg` | `sg-0333ec462c106afaf` | Gắn vào ENIs của FSx |
| **Subnet** | `dr-tokyo-private-a` | `subnet-07b960b76e10f19c9` | CIDR `10.20.11.0/24` |
| **Management IP** | - | `10.20.11.183` | `management.fs-0104cc857c91c78e2.fsx.ap-northeast-1.amazonaws.com` |
| **NFS Endpoint** | - | `10.20.11.230` | `svm-0c6499bac116da7a2.fs-0104cc857c91c78e2.fsx.ap-northeast-1.amazonaws.com` |
| **Intercluster IPs** | - | `10.20.11.215`, `10.20.11.142` | Cổng replication SnapMirror 11104-11105 |

---

## 6. Các bước triển khai chi tiết

### 6.1 Tạo Security Group cho FSx for ONTAP tại Tokyo (`dr-tokyo-fsx-sg`)

1. Mở **AWS Management Console**, chuyển Region sang **Asia Pacific (Tokyo) `ap-northeast-1`**.
2. Vào **VPC** -> **Security groups** -> nhấp **Create security group**.
3. **Security group name**: Nhập `dr-tokyo-fsx-sg`.
4. **VPC**: Chọn `dr-tokyo-vpc` (`vpc-014bd2b27411c1b8a`).
5. **Inbound rules**:
   - *Rule 1 (NFS Traffic):* Type: **NFS** (Port `2049`), Source: CIDR `10.20.0.0/16` (toàn bộ VPC Tokyo).
   - *Rule 2 (RPC Portmapper):* Type: **Custom TCP**, Port: `111`, Source: `10.20.0.0/16`.
   - *Rule 3 (RPC Mountd):* Type: **Custom TCP**, Port: `635`, Source: `10.20.0.0/16`.
   - *Rule 4 (SSH - Quản trị ONTAP CLI):* Type: **SSH** (Port `22`), Source: `10.20.0.0/16`.
   - *Rule 5 (HTTPS - REST API & Mgmt):* Type: **HTTPS** (Port `443`), Source: `10.20.0.0/16` và `10.10.0.0/16`.
   - *Rule 6 (SnapMirror Replication):* Type: **Custom TCP**, Port range: `11104-11105`, Source: CIDR Singapore `10.10.0.0/16`.
   - *Rule 7 (ICMP Ping):* Type: **All ICMP - IPv4**, Source: CIDR Singapore `10.10.0.0/16`.
6. Nhấp nút **Create security group**.

---

### 6.2 Khởi tạo Amazon FSx for NetApp ONTAP File System tại Tokyo

1. Vào dịch vụ **Amazon FSx** tại Region Tokyo.
2. Nhấp nút **Create file system** -> chọn **Amazon FSx for NetApp ONTAP** -> nhấp **Next**.
3. **Cấu hình chi tiết:**
   - **File system name:** `dr-tokyo-fsx-ontap`.
   - **Deployment type:** Chọn **Single-AZ** (`SINGLE_AZ_1`).
   - **SSD storage capacity:** `1024` GiB.
   - **Provisioned SSD IOPS:** Chọn **Automatic (3 IOPS per GiB)**.
   - **Throughput capacity:** `128` MB/s.
4. **Network & security:**
   - **VPC:** Chọn `dr-tokyo-vpc`.
   - **VPC Security Groups:** Chọn `dr-tokyo-fsx-sg` đã tạo ở bước 6.1.
   - **Subnet:** Chọn private subnet `dr-tokyo-private-a` (`subnet-07b960b76e10f19c9`).
5. **Security & encryption:**
   - **File system administrative password:** Nhập `App2SecureAdmin_2026!`.
6. **Default Storage Virtual Machine (SVM):**
   - **Storage virtual machine name:** `dr-tokyo-svm`.
   - **SVM administrative password:** Nhập `App2SecureAdmin_2026!`.
7. **Default Volume configuration:**
   - Bỏ qua hoặc tạo volume mặc định nhỏ (chúng ta sẽ tạo volume đích chuyên biệt `dr_data_dr` loại DP ở bước 6.3).
8. Nhấp **Next** -> Nhấp **Create file system**. Chờ 15-25 phút cho đến khi trạng thái chuyển sang **Available**.

---

### 6.3 Tạo Destination Volume Data Protection (`dr_data_dr`)

Volume đích của SnapMirror bắt buộc phải có kiểu là **Data Protection (DP)**:

1. **Cách tạo trên FSx Console:**
   - Trong FSx Console Tokyo, chọn menu **Volumes** ở bên trái.
   - Nhấp nút **Create volume** màu cam.
   - **Volume name**: `dr_data_dr`.
   - **Storage virtual machine**: Chọn `dr-tokyo-svm`.
   - **Volume type**: Chọn **Secondary (DP) - for replication**.
   - **Capacity**: Nhập `10` GiB (bằng dung lượng volume nguồn `drdata` Singapore).
   - Nhấp **Create volume**.
2. **Cách tạo qua ONTAP CLI (tùy chọn):**
   ```text
   FsxId0104cc857c91c78e2::> volume create -vserver dr-tokyo-svm -volume dr_data_dr -aggregate aggr1 -size 10g -type DP
   ```

---

### 6.4 Gán Junction Path và Mount Read-Only trên Tokyo EKS Node / EC2

1. **Gán Junction Path trên ONTAP CLI:**
   Volume loại DP vẫn có thể được gán Junction Path để mount kiểm tra dữ liệu ở chế độ Read-Only:
   ```text
   FsxId0104cc857c91c78e2::> volume mount -vserver dr-tokyo-svm -volume dr_data_dr -junction-path /dr-data
   ```

2. **Mount NFS Read-Only trên EKS Worker Node / EC2 Tokyo:**
   ```bash
   # 1. Cài đặt tiện ích NFS
   sudo dnf install -y nfs-utils

   # 2. Tạo thư mục mount
   sudo mkdir -p /mnt/dr-data

   # 3. Mount NFS với cờ 'ro' (Read-Only)
   sudo mount -t nfs -o ro,nfsvers=4.1 10.20.11.230:/dr-data /mnt/dr-data

   # 4. Kiểm tra trạng thái mount
   df -h /mnt/dr-data
   mount | grep /mnt/dr-data

   # 5. Kiểm chứng tính toàn vẹn: Hệ thống PHẢI từ chối ghi
   touch /mnt/dr-data/test-write.txt
   # Kết quả mong đợi: touch: cannot touch '/mnt/dr-data/test-write.txt': Read-only file system
   ```

Để tự động mount lại khi khởi động lại node Tokyo:
```text
10.20.11.230:/dr-data /mnt/dr-data nfs ro,nfsvers=4.1,defaults,_netdev 0 0
```

---

## 7. Xác minh và Bằng chứng thu thập

- [x] File System `dr-tokyo-fsx-ontap` (`fs-0104cc857c91c78e2`) trạng thái `AVAILABLE`.
- [x] SVM `dr-tokyo-svm` (`svm-0c6499bac116da7a2`) trạng thái `running`.
- [x] Volume `dr_data_dr` có `Type = DP` (Data Protection) và trạng thái `online`.
- [x] Junction path `/dr-data` đã được gắn thành công.
- [x] Mount NFS `ro` thành công trên Worker Node Tokyo; thao tác ghi bị chặn an toàn.

---

## 8. Lab tiếp theo

Chuyển sang: 👉 [LAB 21 - SnapMirror Replication](21-snapmirror-replication.md) để thiết lập Cluster Peering, SVM Peering và kích hoạt lịch trình đồng bộ dữ liệu tự động giữa 2 miền.
