# LAB 18 - EC2 Storage Workload

## 1. Mục tiêu

Tạo hai EC2 Linux private cho `file-service`, quản trị bằng SSM Session Manager, không dùng public IP/SSH.

## 2. Thành phần sẽ xây dựng

- `dr-sg-storage-ec2`, `dr-tokyo-storage-ec2`.
- IAM role/profile có `AmazonSSMManagedInstanceCore` và quyền pull đúng ECR repository.
- Security group chỉ nhận HTTP từ storage ALB SG và NFS tới FSx theo flow đã phê duyệt.

## 3. Bối cảnh kiến trúc

```text
Internet -> ALB -> private EC2 -> /mnt/dr-data -> FSx ONTAP
                    ^
                    SSM, không SSH
```

## 4. Điều kiện tiên quyết

- LAB 00-04 hoàn tất; private subnet có NAT hoặc VPC endpoints cho SSM/ECR/CloudWatch.
- AMI, instance type và ngân sách được phê duyệt.
- ECR có `app2-file-service`; không dùng tag `latest`.

## 5. Quy ước đặt tên tài nguyên

| Thành phần | Singapore | Tokyo |
|---|---|---|
| Instance | `dr-sg-storage-ec2` | `dr-tokyo-storage-ec2` |
| Role | `dr-sg-storage-role` | `dr-tokyo-storage-role` |
| SG | `dr-sg-storage-ec2-sg` | `dr-tokyo-storage-ec2-sg` |

### 6.1 Tạo IAM Role cho EC2 Storage Instances

Cần tạo IAM Role cho phép EC2 giao tiếp với AWS Systems Manager (quản trị không cần mở SSH) và pull container image từ ECR:

1. Mở AWS Management Console, truy cập dịch vụ **IAM**.
2. Trong menu bên trái, chọn **Roles** -> nhấp nút **Create role** màu cam.
3. **Select trusted entity**:
   - **Trusted entity type**: Chọn **AWS service**.
   - **Use case**: Chọn **EC2** -> nhấp nút **Next**.
4. **Add permissions**:
   - Tìm kiếm và tích chọn 2 policy sau:
     1. `AmazonSSMManagedInstanceCore` (cho phép kết nối qua Session Manager).
     2. `AmazonEC2ContainerRegistryReadOnly` (cho phép pull image `app2-file-service` từ ECR).
   - Nhấp nút **Next**.
5. **Name, review, and create**:
   - **Role name**: Nhập `dr-sg-storage-role` (tại Singapore).
   - Nhấp nút **Create role** màu cam.
6. Lặp lại thao tác trên để tạo role cho Tokyo với tên `dr-tokyo-storage-role`.

### 6.2 Tạo Security Group cho EC2 Storage Instance

#### Bước 1: Tạo tại Singapore
1. Chuyển Region sang **Asia Pacific (Singapore) `ap-southeast-1`** -> vào dịch vụ **EC2** hoặc **VPC** -> chọn **Security groups**.
2. Nhấp nút **Create security group**.
3. **Security group name**: Nhập `dr-sg-storage-ec2-sg`.
4. **Description**: Nhập `Security group for private storage EC2 in Singapore`.
5. **VPC**: Chọn `dr-sg-vpc`.
6. **Inbound rules**:
   - Tạm thời để trống (ở LAB 22 sẽ thêm rule cho phép HTTP từ Storage ALB).
   - *Tuyệt đối không thêm rule SSH (port 22).*
7. **Outbound rules**: Giữ mặc định *All traffic* (để instance gọi ra NAT Gateway kết nối SSM và ECR).
8. Nhấp nút **Create security group**.

#### Bước 2: Tạo tại Tokyo
1. Chuyển Region sang **Asia Pacific (Tokyo) `ap-northeast-1`** -> tạo Security Group `dr-tokyo-storage-ec2-sg` trong VPC `dr-tokyo-vpc` với cấu hình tương tự.

### 6.3 Khởi chạy Private EC2 Instance tại Singapore (`dr-sg-storage-ec2`)

1. Chuyển Region về **Asia Pacific (Singapore) `ap-southeast-1`**.
2. Trong menu bên trái của EC2 Console, chọn **Instances** -> nhấp nút **Launch instances** màu cam ở góc trên bên phải.
3. Tại giao diện khởi chạy:
   - **Name**: Nhập `dr-sg-storage-ec2`.
   - **Application and OS Images (Amazon Machine Image)**:
     - Chọn **Amazon Linux**.
     - **AMI**: Chọn **Amazon Linux 2023 AMI** (Hỗ trợ sẵn SSM Agent và kiến trúc x86_64).
   - **Instance type**: Chọn `t3.micro` hoặc `t3.small` (tối ưu chi phí lab).
   - **Key pair (login)**:
     - Chọn **Proceed without a key pair (Not recommended)**.
     - *Lý do:* Chúng ta quản trị an toàn 100% qua AWS Systems Manager Session Manager, không mở cổng SSH ra ngoài Internet.
   - **Network settings** -> nhấp **Edit**:
     - **VPC**: Chọn `dr-sg-vpc`.
     - **Subnet**: Chọn private subnet `dr-sg-private-a`.
     - **Auto-assign public IP**: Chọn **Disable** (Bắt buộc không cấp public IP).
     - **Firewall (security groups)**: Chọn **Select existing security group** -> chọn `dr-sg-storage-ec2-sg`.
   - **Configure storage**:
     - `1x 20 GiB gp3` (Root volume).
     - Đảm bảo **Encrypted** hiển thị là *Encrypted*.
   - **Advanced details** (Cuộn xuống dưới cùng và mở rộng):
     - **IAM instance profile**: Chọn `dr-sg-storage-role`.
     - **Metadata version**: Chọn **V2 only (token required)** (Bắt buộc chuẩn an ninh IMDSv2).
4. Nhấp nút **Launch instance** màu cam. Chờ instance chuyển sang trạng thái **Running**.

### 6.4 Khởi chạy Private EC2 Instance tại Tokyo (`dr-tokyo-storage-ec2`)

1. Chuyển Region sang **Asia Pacific (Tokyo) `ap-northeast-1`**.
2. Nhấp **Launch instances**:
   - **Name**: Nhập `dr-tokyo-storage-ec2`.
   - **AMI**: Amazon Linux 2023.
   - **Instance type**: `t3.micro` hoặc `t3.small`.
   - **Key pair**: Proceed without a key pair.
   - **Network settings**: VPC `dr-tokyo-vpc`, Subnet `dr-tokyo-private-a`, Auto-assign public IP: **Disable**, Security group: `dr-tokyo-storage-ec2-sg`.
   - **Advanced details**: IAM instance profile chọn `dr-tokyo-storage-role`, Metadata version: **V2 only**.
3. Nhấp nút **Launch instance**.

### 6.5 Kết nối và chuẩn bị môi trường qua SSM Session Manager

1. Tại EC2 Console ở Singapore, chọn instance `dr-sg-storage-ec2`.
2. Nhấp vào nút **Connect** ở thanh công cụ phía trên.
3. Chuyển sang tab **Session Manager**:
   - Nhấp nút **Connect** màu cam. Một cửa sổ terminal shell an toàn trên trình duyệt sẽ được mở ra.
4. Cài đặt Docker và tạo thư mục mount:

```bash
sudo dnf update -y
sudo dnf install -y docker nfs-utils
sudo systemctl enable --now docker
sudo usermod -aG docker ssm-user
sudo mkdir -p /mnt/dr-data
sudo chmod 777 /mnt/dr-data
docker --version
```

5. Lặp lại thao tác kết nối qua Session Manager trên `dr-tokyo-storage-ec2` tại Tokyo và thực thi cùng các lệnh cài đặt trên.

## 7. Xác minh

```bash
aws ssm describe-instance-information --region ap-southeast-1 --filters Key=tag:Name,Values=dr-sg-storage-ec2
aws ssm describe-instance-information --region ap-northeast-1 --filters Key=tag:Name,Values=dr-tokyo-storage-ec2
```

Trong SSM session: `docker version`, `test -d /mnt/dr-data`, `curl` tới metadata phải bị chặn nếu không dùng IMDSv2 token.

## 8. Kết quả mong đợi

Hai instance private xuất hiện `Online` trong SSM, Docker chạy, không public IP, không inbound SSH.

## 9. Xử lý sự cố

- SSM offline: kiểm tra role, DNS, NAT/endpoints, time sync và SSM Agent.
- ECR pull lỗi: kiểm tra regional repository, token endpoint, IAM và route.
- ALB unhealthy sau LAB 22: kiểm tra app bind `0.0.0.0`, port, SG và `/health`.

## 10. Lưu ý bảo mật

IMDSv2 bắt buộc; EBS mã hóa; patch AMI; Session Manager logging; IAM không có push/delete ECR; không lưu ONTAP admin password trên instance.

## 11. Lưu ý chi phí

EC2, EBS, NAT/VPC endpoints, CloudWatch và public ALB ở lab sau đều tính phí.

## 12. Dọn dẹp / Quay lui

Stop instance khi tạm dừng ngắn; terminate chỉ sau khi unmount FSx và giữ log/evidence. Xóa role sau instance profile.

## 13. Bằng chứng cần thu thập

Instance ID/subnet/SG, no-public-IP, IAM policy, SSM Online, Docker version, EBS encryption.

## 14. Lab tiếp theo

[LAB 19 - FSx ONTAP Singapore](19-fsx-ontap-singapore.md).
