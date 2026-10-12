# LAB 19 - FSx for NetApp ONTAP Singapore

## 1. Mục tiêu

Tạo source volume RW tại Singapore và mount NFS 4.1 vào `/mnt/dr-data`.

## 2. Thành phần sẽ xây dựng

`dr-sg-fsx-ontap`, SVM `dr-sg-svm`, volume `dr-data`, junction `/dr-data`, export policy và private NFS endpoint.

## 3. Bối cảnh kiến trúc

```text
dr-sg-storage-ec2 -> NFS 4.1 -> dr-sg-svm:/dr-data (RW)
```

## 4. Điều kiện tiên quyết

- LAB 18; quota/capacity/throughput/deployment type được kiểm tra trong Console.
- Chọn **Single-AZ** cho lab chi phí thấp và peering-accessible client endpoints. Production phải đánh giá Multi-AZ và Transit Gateway vì floating client endpoints không đi qua VPC peering.
- KMS key, backup retention và ONTAP credential handling được phê duyệt.

## 5. Quy ước đặt tên tài nguyên

| File system | SVM | Volume | Junction |
|---|---|---|---|
| `dr-sg-fsx-ontap` | `dr-sg-svm` | `dr-data` | `/dr-data` |

### 6.1 Tạo Security Group cho FSx for ONTAP tại Singapore

1. Mở AWS Management Console, chuyển Region sang **Asia Pacific (Singapore) `ap-southeast-1`**.
2. Vào dịch vụ **VPC** -> chọn **Security groups** -> nhấp **Create security group**.
3. **Security group name**: Nhập `dr-sg-fsx-sg`.
4. **Description**: Nhập `Security group for FSx ONTAP Singapore NFS and SnapMirror`.
5. **VPC**: Chọn `dr-sg-vpc`.
6. **Inbound rules**:
   - *Rule 1 (NFS Traffic):* Type: **NFS** (TCP port `2049`), Source: Chọn `dr-sg-storage-ec2-sg` (hoặc CIDR subnet `10.10.11.0/24`).
   - *Rule 2 (RPC Portmapper):* Type: **Custom TCP**, Port: `111`, Source: `dr-sg-storage-ec2-sg`.
   - *Rule 3 (RPC Mountd):* Type: **Custom TCP**, Port: `635`, Source: `dr-sg-storage-ec2-sg`.
   - *Rule 4 (SnapMirror Intercluster replication từ Tokyo):* Type: **Custom TCP**, Port range: `11104-11105`, Source: Nhập CIDR Tokyo `10.20.0.0/16`.
   - *Rule 5 (ONTAP REST API / Mgmt từ Tokyo):* Type: **HTTPS** (Port `443`), Source: Nhập CIDR Tokyo `10.20.0.0/16`.
   - *Rule 6 (ICMP Ping kiểm tra kết nối):* Type: **All ICMP - IPv4**, Source: Nhập `10.20.0.0/16`.
7. Nhấp nút **Create security group**.

### 6.2 Khởi tạo Amazon FSx for NetApp ONTAP File System trên Console

1. Trên thanh tìm kiếm AWS Console, gõ `FSx` và chọn dịch vụ **Amazon FSx**.
2. Nhấp vào nút **Create file system** màu cam ở góc trên bên phải.
3. Tại trang chọn loại hệ thống tệp:
   - Chọn **Amazon FSx for NetApp ONTAP** -> nhấp nút **Next**.
4. **Bước 1: File system details**:
   - **Creation method**: Chọn **Standard create**.
   - **File system name**: Nhập `dr-sg-fsx-ontap`.
   - **Deployment type**: Chọn **Single-AZ** (Lựa chọn tối ưu chi phí lab và cho phép định tuyến NFS / SnapMirror qua VPC Peering trực tiếp không cần Transit Gateway phức tạp).
   - **SSD storage capacity**: Nhập `1024` GiB (Mức dung lượng SSD tối thiểu bắt buộc của FSx ONTAP).
   - **Provisioned SSD IOPS**: Chọn **Automatic (3 IOPS per GiB)**.
   - **Throughput capacity**: Chọn `128` MB/s (hoặc mức thấp nhất được hỗ trợ).
5. **Bước 2: Network & security**:
   - **Virtual Private Cloud (VPC)**: Chọn `dr-sg-vpc`.
   - **VPC Security Groups**: Xóa nhóm mặc định, chọn `dr-sg-fsx-sg` đã tạo ở bước 6.1.
   - **Subnet**: Chọn private subnet `dr-sg-private-a`.
6. **Bước 3: Security & encryption**:
   - **Encryption key**: Chọn `(default) aws/fsx`.
   - **File system administrative password**: Nhập mật khẩu quản trị cho tài khoản `fsxadmin` (Lưu lại an toàn trong password manager).
7. **Bước 4: Default Storage Virtual Machine (SVM) configuration**:
   - **Storage virtual machine name**: Nhập `dr-sg-svm`.
   - **SVM administrative password**: Tích chọn *Specify a password* và nhập mật khẩu hoặc dùng chung với file system.
8. **Bước 5: Default Volume configuration**:
   - **Volume name**: Nhập `dr-data`.
   - **Volume size**: Nhập `10` GiB.
   - **Junction path**: Nhập `/dr-data`.
   - **Storage efficiency**: Chọn **Enabled** (Tự động nén và chống trùng lặp dữ liệu của NetApp).
   - **Tiering policy**: Chọn **None** (cho lab) hoặc **Auto**.
9. Nhấp nút **Next** -> Rà soát lại toàn bộ thiết lập -> Nhấp nút **Create file system** màu cam.
10. *Thời gian khởi tạo:* AWS FSx for NetApp ONTAP sẽ mất từ **15 đến 25 phút** để khởi tạo hoàn chỉnh. Đợi cho đến khi trạng thái chuyển sang **Available**.

### 6.3 Lấy thông tin NFS DNS Name của SVM

1. Khi `dr-sg-fsx-ontap` đã **Available**, trong menu bên trái nhấp chọn **Storage virtual machines**.
2. Nhấp vào tên SVM `dr-sg-svm` để mở trang chi tiết.
3. Chuyển sang tab **Endpoints**:
   - Ghi lại trường **NFS DNS name** (dạng `svm-0xxxxxxxxxxxxxx.fs-0xxxxxxxxxxxxxx.fsx.ap-southeast-1.amazonaws.com`).
   - Ghi lại **Management IP / DNS name** và **Intercluster IP addresses** (phục vụ cho SnapMirror ở LAB 21).

### 6.4 Mount NFS 4.1 vào EC2 Storage Instance và Phân quyền

1. Mở AWS Console -> vào dịch vụ **EC2** -> chọn `dr-sg-storage-ec2` -> nhấp **Connect** -> chọn **Session Manager** -> nhấp **Connect**.
2. Thực thi các lệnh sau trong terminal Session Manager:

```bash
# Đảm bảo cài nfs-utils
sudo dnf install -y nfs-utils

# Tạo thư mục mount
sudo mkdir -p /mnt/dr-data

# Thay <SG_SVM_NFS_DNS> bằng NFS DNS name vừa lấy ở bước 6.3
sudo mount -t nfs -o nfsvers=4.1 <SG_SVM_NFS_DNS>:/dr-data /mnt/dr-data

# Kiểm tra mount thành công
mount | grep /mnt/dr-data

# Thiết lập quyền sở hữu cho non-root UID 1000 (app container user)
sudo chown 1000:1000 /mnt/dr-data
sudo chmod 0770 /mnt/dr-data
stat -c 'owner=%u group=%g mode=%a path=%n' /mnt/dr-data

# Kiểm tra ghi đọc bằng user 1000
sudo -u '#1000' -g '#1000' sh -c 'umask 0007; printf host-probe > /mnt/dr-data/.host-rw-probe; test "$(cat /mnt/dr-data/.host-rw-probe)" = host-probe; rm /mnt/dr-data/.host-rw-probe'
echo "Host NFS probe SUCCESS!"
```

3. Thêm cấu hình tự động mount vào `/etc/fstab`:

```bash
echo "<SG_SVM_NFS_DNS>:/dr-data /mnt/dr-data nfs nfsvers=4.1,defaults,_netdev 0 0" | sudo tee -a /etc/fstab
```

## 7. Xác minh

FSx `AVAILABLE`; SVM/volume online; export rule chỉ match client được duyệt; `/mnt/dr-data` là `1000:1000` mode `0770`; host và container non-root create/read/delete thành công; mount dùng `vers=4.1`; không có public endpoint.

## 8. Kết quả mong đợi

Singapore EC2 đọc/ghi `/mnt/dr-data`; dữ liệu nằm trên `dr-data`, không nằm trong container/EBS.

## 9. Xử lý sự cố

- Mount timeout: kiểm tra SVM DNS, route, NACL, SG, export policy.
- `access denied`: export policy/client match, root mapping bootstrap hoặc junction path sai.
- Container `Permission denied`: xác minh process thật sự chạy `1000:1000`, bind path là `/mnt/dr-data:/mnt/dr-data`, owner/mode không bị image entrypoint thay đổi; không chữa bằng `chmod 777` hoặc root container.
- Boot treo: dùng `_netdev`, kiểm tra DNS/network readiness; cân nhắc `nofail` chỉ khi failure semantics được chấp nhận.

## 10. Lưu ý bảo mật

FSx private, encryption at rest, least-privilege export; NFS không phải authentication boundary cho Internet-facing client.

## 11. Lưu ý chi phí

FSx tính phí capacity, throughput, backup, SSD/tiering và transfer. Xác minh giá Region hiện hành trước Create.

## 12. Dọn dẹp / Quay lui

Unmount client trước khi xóa volume/SVM/file system. Backup theo retention policy; không mặc định xóa dữ liệu.

## 13. Bằng chứng cần thu thập

Deployment type, subnets, KMS, capacity/throughput, export policy, SG, mount options, RW test.

## 14. Lab tiếp theo

[LAB 20 - FSx ONTAP Tokyo](20-fsx-ontap-tokyo.md).

Nguồn: [AWS Linux mount](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/attach-linux-client.html), [security-group ports](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/limit-access-security-groups.html#fsx-vpc-security-groups), [NetApp export-policy rules](https://docs.netapp.com/us-en/ontap/nfs-config/add-rule-export-policy-task.html).
