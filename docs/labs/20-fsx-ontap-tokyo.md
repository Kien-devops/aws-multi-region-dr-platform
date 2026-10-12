# LAB 20 - FSx for NetApp ONTAP Tokyo

## 1. Mục tiêu

Tạo Tokyo destination foundation và chuẩn bị volume DP cho SnapMirror.

## 2. Thành phần sẽ xây dựng

`dr-tokyo-fsx-ontap`, `dr-tokyo-svm`, destination volume `dr-data-dr`, junction `/dr-data` sau promotion.

## 3. Bối cảnh kiến trúc

```text
Singapore dr-data (RW) -> SnapMirror -> Tokyo dr-data-dr (DP/read-only)
```

## 4. Điều kiện tiên quyết

- LAB 19; Tokyo deployment type/capacity đủ chứa source.
- Peering/routes/intercluster SG flow của LAB 04 hoàn tất.
- Không có application writer tại Tokyo.

## 5. Quy ước đặt tên tài nguyên

| File system | SVM | Volume |
|---|---|---|
| `dr-tokyo-fsx-ontap` | `dr-tokyo-svm` | `dr-data-dr` |

### 6.1 Tạo Security Group cho FSx for ONTAP tại Tokyo

1. Mở AWS Management Console, chuyển Region sang **Asia Pacific (Tokyo) `ap-northeast-1`**.
2. Vào dịch vụ **VPC** -> chọn **Security groups** -> nhấp **Create security group**.
3. **Security group name**: Nhập `dr-tokyo-fsx-sg`.
4. **Description**: Nhập `Security group for FSx ONTAP Tokyo NFS and SnapMirror destination`.
5. **VPC**: Chọn `dr-tokyo-vpc`.
6. **Inbound rules**:
   - *Rule 1 (NFS từ EC2 Tokyo):* Type: **NFS** (TCP port `2049`), Source: Chọn `dr-tokyo-storage-ec2-sg` (hoặc CIDR `10.20.11.0/24`).
   - *Rule 2 (RPC Portmapper):* Type: **Custom TCP**, Port: `111`, Source: `dr-tokyo-storage-ec2-sg`.
   - *Rule 3 (RPC Mountd):* Type: **Custom TCP**, Port: `635`, Source: `dr-tokyo-storage-ec2-sg`.
   - *Rule 4 (SnapMirror Intercluster replication từ Singapore):* Type: **Custom TCP**, Port range: `11104-11105`, Source: Nhập CIDR Singapore `10.10.0.0/16`.
   - *Rule 5 (ONTAP REST API / Mgmt từ Singapore):* Type: **HTTPS** (Port `443`), Source: Nhập CIDR Singapore `10.10.0.0/16`.
   - *Rule 6 (ICMP Ping):* Type: **All ICMP - IPv4**, Source: Nhập `10.10.0.0/16`.
7. Nhấp nút **Create security group**.

### 6.2 Khởi tạo Amazon FSx for NetApp ONTAP File System tại Tokyo

1. Trên thanh tìm kiếm AWS Console, gõ `FSx` và chọn dịch vụ **Amazon FSx**.
2. Nhấp vào nút **Create file system** màu cam ở góc trên bên phải.
3. Chọn **Amazon FSx for NetApp ONTAP** -> nhấp nút **Next**.
4. **Bước 1: File system details**:
   - **Creation method**: Chọn **Standard create**.
   - **File system name**: Nhập `dr-tokyo-fsx-ontap`.
   - **Deployment type**: Chọn **Single-AZ**.
   - **SSD storage capacity**: Nhập `1024` GiB.
   - **Provisioned SSD IOPS**: Chọn **Automatic (3 IOPS per GiB)**.
   - **Throughput capacity**: Chọn `128` MB/s.
5. **Bước 2: Network & security**:
   - **Virtual Private Cloud (VPC)**: Chọn `dr-tokyo-vpc`.
   - **VPC Security Groups**: Xóa nhóm mặc định, chọn `dr-tokyo-fsx-sg` đã tạo ở bước 6.1.
   - **Subnet**: Chọn private subnet `dr-tokyo-private-a`.
6. **Bước 3: Security & encryption**:
   - **Encryption key**: Chọn `(default) aws/fsx`.
   - **File system administrative password**: Nhập mật khẩu quản trị `fsxadmin`.
7. **Bước 4: Default Storage Virtual Machine (SVM)**:
   - **Storage virtual machine name**: Nhập `dr-tokyo-svm`.
   - **SVM administrative password**: Nhập mật khẩu quản trị SVM.
8. **Bước 5: Default Volume configuration**:
   - Để trống hoặc tạo volume tạm thời (chúng ta sẽ tạo volume chuyên biệt Data Protection `dr-data-dr` ở bước 6.3).
9. Nhấp nút **Next** -> rà soát thiết lập -> Nhấp **Create file system**. Chờ 15-25 phút cho trạng thái chuyển sang **Available**.

### 6.3 Tạo Destination Volume Data Protection (`dr-data-dr`)

Volume đích của SnapMirror bắt buộc phải có kiểu là **Data Protection (DP)**, đóng vai trò là bản sao chỉ đọc (Read-only) và không thể ghi trực tiếp từ phía client:

- **Cách 1: Tạo trực tiếp trên FSx Console:**
  1. Trong FSx Console tại Tokyo, chọn menu **Volumes** ở bên trái.
  2. Nhấp nút **Create volume** màu cam.
  3. **Volume name**: Nhập `dr-data-dr`.
  4. **Storage virtual machine**: Chọn `dr-tokyo-svm`.
  5. **Volume type**: Chọn **Secondary (DP) - for replication**.
  6. **Capacity**: Nhập `10` GiB (phải bằng hoặc lớn hơn dung lượng volume nguồn `dr-data` ở Singapore).
  7. Nhấp nút **Create volume**.
- **Cách 2: Hoặc tạo qua ONTAP CLI từ EC2 Tokyo:**
  ```text
  FSx-Dest::> vol create -vserver dr-tokyo-svm -volume dr-data-dr \
    -aggregate <TOKYO_AGGREGATE> -size 10g -type DP -tiering-policy all
  ```

### 6.4 Lấy thông tin Endpoints của Tokyo SVM

1. Trong menu bên trái của FSx Console, nhấp chọn **Storage virtual machines** -> chọn `dr-tokyo-svm`.
2. Chuyển sang tab **Endpoints**:
   - Ghi lại **NFS DNS name** (dùng cho việc mount sau khi failover/promote).
   - Ghi lại **Management IP / DNS name** và **Intercluster IP addresses** (chuẩn bị thiết lập Peering ở LAB 21).

## 7. Xác minh

```text
FSx-Dest::> volume show -vserver dr-tokyo-svm -volume dr-data-dr -fields type,state,size
```

Kỳ vọng type `DP`, state online, capacity không nhỏ hơn source. Ghi lại export-policy name/rules và junction hiện tại; không tạo file trực tiếp tại destination.

## 8. Kết quả mong đợi

Tokyo foundation sẵn sàng nhận baseline; chưa writable và chưa phục vụ traffic.

## 9. Xử lý sự cố

- Không tạo được DP: kiểm tra aggregate/capacity/volume name.
- Client mount không thấy data: relationship chưa initialize hoặc junction/export chưa sẵn sàng.
- Ghi thành công trước promotion: dừng lại; kiểm tra nhầm volume/relationship vì đây là split-brain risk.

## 10. Lưu ý bảo mật

Tách ONTAP admin khỏi application runtime. Chỉ operator role được phép peer/create/break/resync.

## 11. Lưu ý chi phí

Tokyo FSx tính phí liên tục kể cả destination read-only; tiering không loại bỏ capacity/throughput/backup costs.

## 12. Dọn dẹp / Quay lui

Không xóa DP volume khi relationship còn tồn tại. Xóa/release relationship theo LAB 27 trước.

## 13. Bằng chứng cần thu thập

File system/SVM/volume IDs, type DP, size, KMS, subnets, SG/export policy, no-write evidence.

## 14. Lab tiếp theo

[LAB 21 - SnapMirror Replication](21-snapmirror-replication.md).
