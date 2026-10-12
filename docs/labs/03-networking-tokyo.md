# LAB 03 - VPC Tokyo

## 1. Mục tiêu

Tạo VPC warm standby tại Tokyo không chồng lấn CIDR, theo cùng mô hình hai AZ như Singapore.

## 2. Thành phần sẽ xây dựng

VPC `10.20.0.0/16`, hai public subnet, hai private subnet, IGW, một NAT Gateway cho lab, public/private route table và tag subnet cho EKS.

## 3. Bối cảnh kiến trúc

```text
Internet -> dr-tokyo-igw -> public subnet -> ALB/NAT Tokyo
                                     NAT -> private subnet -> EKS/Aurora secondary
```

## 4. Điều kiện tiên quyết

- Hoàn thành LAB 02.
- Đã chọn Region `ap-northeast-1`.
- Hai AZ khả dụng cho tài khoản, được ghi lại thành `<TOKYO_AZ_A>` và `<TOKYO_AZ_B>`.
- Không giả định ký tự AZ ánh xạ tới cùng vị trí vật lý giữa các tài khoản AWS.

## 5. Quy ước đặt tên tài nguyên

| Tài nguyên | CIDR/Giá trị |
|---|---|
| `dr-tokyo-vpc` | `10.20.0.0/16` |
| `dr-tokyo-public-a` | `10.20.1.0/24` |
| `dr-tokyo-public-b` | `10.20.2.0/24` |
| `dr-tokyo-private-a` | `10.20.11.0/24` |
| `dr-tokyo-private-b` | `10.20.12.0/24` |
| `dr-tokyo-igw` | Internet Gateway |
| `dr-tokyo-nat` | NAT Gateway trong public-a |
| `dr-tokyo-public-rt` | Public route table |
| `dr-tokyo-private-rt` | Private route table |

## 6. Các bước triển khai

### 6.1 Tạo VPC Tokyo

1. Mở AWS Management Console, chuyển Region sang **Asia Pacific (Tokyo) `ap-northeast-1`** ở góc trên bên phải.
2. Tại thanh tìm kiếm, gõ `VPC` và nhấp chọn dịch vụ **VPC**.
3. Trong menu bên trái, nhấp chọn **Your VPCs**.
4. Nhấp vào nút **Create VPC** màu cam ở góc trên bên phải.
5. Tại giao diện tạo VPC:
   - **Resources to create**: Chọn **VPC only**.
   - **Name tag**: Nhập `dr-tokyo-vpc`.
   - **IPv4 CIDR manual input**: Tích chọn và nhập `10.20.0.0/16`.
   - **IPv6 CIDR block**: Chọn **No IPv6 CIDR block**.
   - **Tenancy**: Chọn **Default**.
6. Nhấp nút **Create VPC** màu cam ở cuối trang.
7. Bật DNS Hostnames và DNS Resolution cho VPC:
   - Trong trang chi tiết của `dr-tokyo-vpc` (hoặc tại danh sách **Your VPCs**, tích chọn `dr-tokyo-vpc`).
   - Nhấp menu **Actions** ở góc trên bên phải -> chọn **Edit VPC settings**.
   - Tại mục **DNS settings**:
     - Tích chọn **Enable DNS resolution**.
     - Tích chọn **Enable DNS hostnames**.
   - Nhấp nút **Save changes**.

### 6.2 Tạo 4 Subnets (2 Public, 2 Private trên 2 AZs tại Tokyo)

Xác định trước 2 Availability Zones sẽ dùng tại Tokyo (ví dụ: `ap-northeast-1a` và `ap-northeast-1c` hoặc `ap-northeast-1d` tùy tài khoản).

1. Trong thanh điều hướng bên trái của VPC Console, nhấp chọn **Subnets**.
2. Nhấp vào nút **Create subnet** màu cam.
3. **VPC ID**: Nhấp vào ô tìm kiếm và chọn `dr-tokyo-vpc`.
4. *Cấu hình Subnet 1 (Public A):*
   - **Subnet name**: `dr-tokyo-public-a`
   - **Availability Zone**: Chọn AZ thứ nhất (ví dụ: `ap-northeast-1a`)
   - **IPv4 CIDR block**: `10.20.1.0/24`
5. Nhấp nút **Add new subnet**:
   - *Cấu hình Subnet 2 (Public B):*
     - **Subnet name**: `dr-tokyo-public-b`
     - **Availability Zone**: Chọn AZ thứ hai (ví dụ: `ap-northeast-1c`)
     - **IPv4 CIDR block**: `10.20.2.0/24`
6. Nhấp nút **Add new subnet**:
   - *Cấu hình Subnet 3 (Private A):*
     - **Subnet name**: `dr-tokyo-private-a`
     - **Availability Zone**: Chọn AZ thứ nhất (trùng AZ với Public A, ví dụ: `ap-northeast-1a`)
     - **IPv4 CIDR block**: `10.20.11.0/24`
7. Nhấp nút **Add new subnet**:
   - *Cấu hình Subnet 4 (Private B):*
     - **Subnet name**: `dr-tokyo-private-b`
     - **Availability Zone**: Chọn AZ thứ hai (trùng AZ với Public B, ví dụ: `ap-northeast-1c`)
     - **IPv4 CIDR block**: `10.20.12.0/24`
8. Nhấp nút **Create subnet** màu cam ở cuối trang.
9. Bật tự động cấp phát Public IPv4 cho 2 Public subnets:
   - Tích chọn subnet `dr-tokyo-public-a` -> **Actions** -> **Edit subnet settings**.
   - Tích chọn **Enable auto-assign public IPv4 address** -> nhấp **Save**.
   - Lặp lại thao tác trên cho `dr-tokyo-public-b`. Giữ nguyên tắt cho 2 private subnets.

### 6.3 Tạo và gắn Internet Gateway (IGW)

1. Trong thanh điều hướng bên trái, nhấp chọn **Internet gateways**.
2. Nhấp nút **Create internet gateway** màu cam.
3. **Name tag**: Nhập `dr-tokyo-igw` -> nhấp **Create internet gateway**.
4. Tại màn hình thông báo tạo thành công, nhấp **Actions** -> chọn **Attach to VPC**.
5. **Available VPCs**: Chọn `dr-tokyo-vpc` -> nhấp nút **Attach internet gateway** màu cam.

### 6.4 Tạo Public Route Table và gán tuyến đường

1. Trong menu bên trái, nhấp chọn **Route tables** -> nhấp nút **Create route table**.
2. **Name**: Nhập `dr-tokyo-public-rt`, **VPC**: Chọn `dr-tokyo-vpc` -> nhấp **Create route table**.
3. Thêm tuyến đường ra Internet qua IGW:
   - Chuyển sang tab **Routes** -> nhấp **Edit routes**.
   - Nhấp **Add route**: Destination: `0.0.0.0/0`, Target: chọn **Internet Gateway** -> chọn `dr-tokyo-igw`.
   - Nhấp **Save changes**.
4. Liên kết Public subnets:
   - Chuyển sang tab **Subnet associations** -> nhấp **Edit subnet associations**.
   - Tích chọn `dr-tokyo-public-a` và `dr-tokyo-public-b`.
   - Nhấp **Save associations**.

### 6.5 Tạo NAT Gateway tại Public Subnet

1. Trong menu bên trái, nhấp chọn **NAT gateways** -> nhấp nút **Create NAT gateway**.
2. **Name**: Nhập `dr-tokyo-nat`.
3. **Subnet**: Chọn subnet public `dr-tokyo-public-a`.
4. **Connectivity type**: Chọn **Public**.
5. **Elastic IP allocation ID**: Nhấp nút **Allocate Elastic IP**.
6. Nhấp **Create NAT gateway**. Chờ trạng thái chuyển sang **Available**.

### 6.6 Tạo Private Route Table và gán tuyến đường ra NAT

1. Trong menu bên trái, nhấp chọn **Route tables** -> nhấp nút **Create route table**.
2. **Name**: Nhập `dr-tokyo-private-rt`, **VPC**: Chọn `dr-tokyo-vpc` -> nhấp **Create route table**.
3. Thêm tuyến đường qua NAT Gateway:
   - Chuyển sang tab **Routes** -> nhấp **Edit routes**.
   - Nhấp **Add route**: Destination: `0.0.0.0/0`, Target: chọn **NAT Gateway** -> chọn `dr-tokyo-nat`.
   - Nhấp **Save changes**.
4. Liên kết Private subnets:
   - Chuyển sang tab **Subnet associations** -> nhấp **Edit subnet associations**.
   - Tích chọn `dr-tokyo-private-a` và `dr-tokyo-private-b`.
   - Nhấp **Save associations**.

### 6.7 Gắn thẻ (Tags) cho Subnets phục vụ AWS Load Balancer Controller

1. Trong menu bên trái, nhấp chọn **Subnets**.
2. *Gắn tag cho 2 Public subnets (`dr-tokyo-public-a`, `dr-tokyo-public-b`):*
   - Chọn subnet `dr-tokyo-public-a` -> tab **Tags** -> nhấp **Manage tags**.
   - Thêm tag: Key `kubernetes.io/role/elb`, Value `1` -> nhấp **Save**.
   - Lặp lại cho `dr-tokyo-public-b`.
3. *Gắn tag cho 2 Private subnets (`dr-tokyo-private-a`, `dr-tokyo-private-b`):*
   - Chọn subnet `dr-tokyo-private-a` -> tab **Tags** -> nhấp **Manage tags**.
   - Thêm tag: Key `kubernetes.io/role/internal-elb`, Value `1` -> nhấp **Save**.
   - Lặp lại cho `dr-tokyo-private-b`.

## 7. Xác minh

```bash
aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=dr-tokyo-vpc
aws ec2 describe-subnets --region ap-northeast-1 --filters Name=tag:Name,Values='dr-tokyo-*' \
  --query 'Subnets[*].[Tags[?Key==`Name`].Value|[0],CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' --output table
aws ec2 describe-route-tables --region ap-northeast-1 --filters Name=vpc-id,Values=<TOKYO_VPC_ID>
aws ec2 describe-nat-gateways --region ap-northeast-1 --filter Name=tag:Name,Values=dr-tokyo-nat
```

## 8. Kết quả mong đợi

Tokyo có mạng cô lập, không chồng lấn, sẵn sàng cho EKS, Aurora secondary, ALB và peering tùy chọn.

## 9. Xử lý sự cố

Áp dụng hướng dẫn xử lý sự cố của LAB 02. Đồng thời xác nhận các AZ Tokyo đã chọn hỗ trợ instance class dự kiến tại thời điểm triển khai; không dựa vào giả định AZ được hardcode.

## 10. Lưu ý bảo mật

Đặt node/cơ sở dữ liệu trong private subnet, không public DB, áp dụng security group đặc quyền tối thiểu ở lab sau; khuyến nghị Flow Logs và VPC endpoint cho production.

## 11. Lưu ý chi phí

NAT và public IPv4 tại Tokyo bắt đầu tính phí theo giờ ngay khi tạo. Xóa nếu tạm dừng trước khi tạo EKS.

## 12. Dọn dẹp / Quay lui

Tuân theo cùng thứ tự phụ thuộc như Singapore; quy trình teardown đầy đủ nằm ở LAB 27.

## 13. Bằng chứng cần thu thập

VPC resource map, subnet/AZ, route, NAT/EIP, cấu hình DNS và tag subnet.

## 14. Lab tiếp theo

Tiếp tục với [LAB 04 - Kết nối mạng liên Region tùy chọn](04-cross-region-networking.md).
