# LAB 19 - FSx for NetApp ONTAP Singapore

## 1. Mục tiêu

Khởi tạo và cấu hình hệ thống tệp lưu trữ phân tán **Amazon FSx for NetApp ONTAP** tại Singapore (`ap-southeast-1`), đóng vai trò là **Source Volume (Read-Write)** phục vụ cho dịch vụ `app2-file-service` và làm nguồn dữ liệu nhân bản SnapMirror sang Tokyo.

## 2. Thành phần xây dựng

- **File System:** `dr-sg-fsx-ontap` (ID: `fs-0955146589825df51`), Deployment Type: `Single-AZ (SINGLE_AZ_1)`.
- **Storage Virtual Machine (SVM):** `dr-sg-svm` (ID: `svm-0d7a5a310c9ded152`).
- **Volume:** `drdata` (Type: `RW`, Dung lượng: 10 GiB) *(Lưu ý: NetApp ONTAP không hỗ trợ ký tự gạch ngang `-` trong tên volume, nên đặt là `drdata`)*.
- **Junction Path:** `/dr-data`.
- **Security Group:** `dr-sg-fsx-sg` (`sg-0776992793aac17e6`) mở đầy đủ cổng NFS, SSH (ONTAP CLI), HTTPS (REST API), SnapMirror replication và ICMP.
- **Client Mount:** Mount NFS v4.1 tại `/mnt/dr-data` trên EKS Worker Nodes / EC2 Storage Instance.

## 3. Bối cảnh kiến trúc

```text
[ EKS Worker Nodes / App2 File Service ]
              │ (NFS v4.1 - RW)
              ▼
[ dr-sg-svm:/dr-data (Volume: drdata) ]
   (Management IP: 10.10.12.163)
   (Intercluster IPs: 10.10.12.218, 10.10.12.145)
              │
              ▼ (SnapMirror Replication - Port 11104-11105 qua VPC Peering)
[ Tokyo Standby FSx ONTAP ]
```

## 4. Điều kiện tiên quyết

- Mạng VPC Singapore (`dr-sg-vpc` - CIDR `10.10.0.0/16`) đã hoàn tất ở LAB 02.
- VPC Peering `pcx-0cbc2b7685a2cfe78` kết nối với Tokyo (`10.20.0.0/16`) đã hoạt động.
- Mật khẩu quản trị hệ thống thống nhất cho cả 2 Region: `App2SecureAdmin_2026!`.

## 5. Quy ước đặt tên tài nguyên

| Tài nguyên | Tên quy ước | ID / Thông số thực tế | Ghi chú |
|---|---|---|---|
| **File System** | `dr-sg-fsx-ontap` | `fs-0955146589825df51` | Single-AZ, 1024 GiB SSD, 128 MB/s |
| **SVM** | `dr-sg-svm` | `svm-0d7a5a310c9ded152` | Root Volume: `dr_sg_svm_root` |
| **Volume** | `drdata` | `vol-05658e474542d13b4` | Type: `RW`, Size: 10 GiB, Junction: `/dr-data` |
| **Security Group** | `dr-sg-fsx-sg` | `sg-0776992793aac17e6` | Gắn vào ENIs của FSx |
| **Subnet** | `dr-sg-private-a` | `subnet-0be5b8a0bfb5c77e6` | CIDR `10.10.12.0/24` |
| **Management IP** | - | `10.10.12.163` | `management.fs-0955146589825df51.fsx.ap-southeast-1.amazonaws.com` |
| **NFS Endpoint** | - | `10.10.12.163` | `svm-0d7a5a310c9ded152.fs-0955146589825df51.fsx.ap-southeast-1.amazonaws.com` |
| **Intercluster IPs** | - | `10.10.12.218`, `10.10.12.145` | Cổng replication SnapMirror 11104-11105 |

---

## 6. Các bước triển khai chi tiết

### 6.1 Tạo Security Group cho FSx for ONTAP tại Singapore (`dr-sg-fsx-sg`)

1. Mở **AWS Management Console**, chuyển Region sang **Asia Pacific (Singapore) `ap-southeast-1`**.
2. Vào **VPC** -> **Security groups** -> nhấp **Create security group**.
3. **Security group name**: Nhập `dr-sg-fsx-sg`.
4. **VPC**: Chọn `dr-sg-vpc` (`vpc-035e691629f36584e`).
5. **Inbound rules** (Cấu hình chuẩn bảo mật và kết nối):
   - *Rule 1 (NFS Traffic):* Type: **NFS** (Port `2049`), Source: CIDR `10.10.0.0/16` (toàn bộ VPC Singapore gồm EKS nodes và EC2).
   - *Rule 2 (RPC Portmapper):* Type: **Custom TCP**, Port: `111`, Source: `10.10.0.0/16`.
   - *Rule 3 (RPC Mountd):* Type: **Custom TCP**, Port: `635`, Source: `10.10.0.0/16`.
   - *Rule 4 (SSH - Quản trị ONTAP CLI):* Type: **SSH** (Port `22`), Source: `10.10.0.0/16` (phục vụ đăng nhập từ Session Manager EC2).
   - *Rule 5 (HTTPS - REST API & Web Mgmt):* Type: **HTTPS** (Port `443`), Source: `10.10.0.0/16` và `10.20.0.0/16`.
   - *Rule 6 (SnapMirror Replication):* Type: **Custom TCP**, Port range: `11104-11105`, Source: CIDR Tokyo `10.20.0.0/16`.
   - *Rule 7 (ICMP Ping kiểm tra đường truyền):* Type: **All ICMP - IPv4**, Source: CIDR Tokyo `10.20.0.0/16`.
6. Nhấp nút **Create security group**.

---

### 6.2 Khởi tạo Amazon FSx for NetApp ONTAP File System

1. Trên AWS Console, tìm kiếm và truy cập dịch vụ **Amazon FSx**.
2. Nhấp nút **Create file system** màu cam ở góc trên bên phải.
3. Chọn loại **Amazon FSx for NetApp ONTAP** -> nhấp **Next**.
4. **Cấu hình chi tiết (Standard create):**
   - **File system name:** `dr-sg-fsx-ontap`.
   - **Deployment type:** Chọn **Single-AZ** (`SINGLE_AZ_1`).
   - **SSD storage capacity:** `1024` GiB (Mức dung lượng tối thiểu).
   - **Provisioned SSD IOPS:** Chọn **Automatic (3 IOPS per GiB)** (3072 IOPS).
   - **Throughput capacity:** `128` MB/s.
5. **Network & security:**
   - **VPC:** Chọn `dr-sg-vpc`.
   - **VPC Security Groups:** Chọn `dr-sg-fsx-sg` đã tạo ở bước 6.1.
   - **Subnet:** Chọn private subnet `dr-sg-private-a` (`subnet-0be5b8a0bfb5c77e6`).
6. **Security & encryption:**
   - **File system administrative password:** Nhập mật khẩu quản trị cho user `fsxadmin`: `App2SecureAdmin_2026!`.
7. **Default Storage Virtual Machine (SVM):**
   - **Storage virtual machine name:** `dr-sg-svm`.
   - **SVM administrative password:** Dùng chung mật khẩu quản trị `App2SecureAdmin_2026!`.
8. **Default Volume configuration:**
   - **Volume name:** `drdata` *(chú ý không dùng dấu gạch ngang `-`)*.
   - **Volume size:** `10` GiB.
   - **Junction path:** `/dr-data`.
   - **Storage efficiency:** Enabled.
   - **Tiering policy:** None (hoặc Auto).
9. Nhấp **Next** -> Xem lại cấu hình -> Nhấp **Create file system**.
   *(Thời gian khởi tạo hoàn tất từ 15 đến 25 phút. Trạng thái chuyển sang **Available**)*.

---

### 6.3 Thu thập thông tin Endpoints của SVM Singapore

Sau khi File System chuyển sang `AVAILABLE`:
1. Vào menu **Storage virtual machines** -> chọn `dr-sg-svm`.
2. Ghi lại các thông tin tại tab **Endpoints**:
   - **NFS DNS name:** `svm-0d7a5a310c9ded152.fs-0955146589825df51.fsx.ap-southeast-1.amazonaws.com` (IP: `10.10.12.163`).
   - **Management DNS name:** `management.fs-0955146589825df51.fsx.ap-southeast-1.amazonaws.com` (IP: `10.10.12.163`).
   - **Intercluster IP addresses:** `10.10.12.218`, `10.10.12.145`.

---

### 6.4 Mount NFS v4.1 trên EKS Worker Node / EC2 Instance

Từ phiên Session Manager trên EKS Worker Node hoặc EC2 Storage Instance:

```bash
# 1. Cài đặt tiện ích NFS
sudo dnf install -y nfs-utils

# 2. Tạo thư mục mount
sudo mkdir -p /mnt/dr-data

# 3. Mount NFS v4.1 từ SVM Singapore
sudo mount -t nfs -o nfsvers=4.1 svm-0d7a5a310c9ded152.fs-0955146589825df51.fsx.ap-southeast-1.amazonaws.com:/dr-data /mnt/dr-data

# 4. Kiểm tra trạng thái mount và dung lượng
df -h /mnt/dr-data
mount | grep /mnt/dr-data

# 5. Phân quyền cho ứng dụng (User 1000 và ec2-user)
sudo chown -R 1000:1000 /mnt/dr-data
sudo chmod 0770 /mnt/dr-data

# 6. Kiểm tra quyền ghi/đọc (Read-Write test)
echo "sg-probe-$(date -u +%Y%m%d-%H%M%S)" | sudo tee /mnt/dr-data/.host-rw-probe
cat /mnt/dr-data/.host-rw-probe
sudo rm /mnt/dr-data/.host-rw-probe
echo "Mount and Read-Write test: SUCCESS!"
```

Để tự động mount lại khi khởi động lại node, thêm vào `/etc/fstab`:
```text
svm-0d7a5a310c9ded152.fs-0955146589825df51.fsx.ap-southeast-1.amazonaws.com:/dr-data /mnt/dr-data nfs nfsvers=4.1,defaults,_netdev 0 0
```

---

## 7. Xác minh và Bằng chứng thu thập

- [x] File System `dr-sg-fsx-ontap` trạng thái `AVAILABLE`.
- [x] SVM `dr-sg-svm` trạng thái `running`.
- [x] Volume `drdata` (Size: 10 GiB, Type: `RW`) mount tại `/dr-data`.
- [x] Thư mục `/mnt/dr-data` có quyền đọc ghi (`readable: true`, `writable: true`).
- [x] Mở đầy đủ cổng mạng trong Security Group `sg-0776992793aac17e6`.

---

## 8. Lab tiếp theo

Chuyển sang: 👉 [LAB 20 - FSx ONTAP Tokyo](20-fsx-ontap-tokyo.md) để khởi tạo File System đích và Volume Data Protection (`DP`) sẵn sàng cho SnapMirror.
