# LAB 02 - VPC Singapore

## 1. Mục tiêu

Tạo VPC Singapore trên hai AZ, gồm public subnet cho ALB/NAT và private subnet cho EKS/Aurora.

## 2. Thành phần sẽ xây dựng

- VPC `10.10.0.0/16`, bật DNS.
- Hai public subnet và hai private subnet.
- IGW, route table và một NAT Gateway trong chế độ tiết kiệm chi phí.
- Tag subnet discovery cho EKS/ALB.

## 3. Bối cảnh kiến trúc

```text
Internet -> IGW -> public-a/public-b -> ALB internet-facing
                    |
                    `-> NAT Gateway -> private-a/private-b -> node EKS, Aurora
```

Public subnet có route tới IGW. Private subnet không có route trực tiếp tới IGW. NAT chỉ cung cấp kết nối IPv4 outbound, không cho phép lưu lượng inbound không được yêu cầu.

## 4. Điều kiện tiên quyết

- Hoàn thành LAB 00.
- Đã chọn Region `ap-southeast-1`.
- Đã chọn hai AZ khả dụng và ghi lại thành `<SG_AZ_A>` và `<SG_AZ_B>`.
- Đã chọn chế độ NAT: một NAT cho lab, hoặc một NAT mỗi AZ cho production HA.

## 5. Quy ước đặt tên tài nguyên

| Tài nguyên | CIDR/Giá trị |
|---|---|
| `dr-sg-vpc` | `10.10.0.0/16` |
| `dr-sg-public-a` | `10.10.1.0/24` |
| `dr-sg-public-b` | `10.10.2.0/24` |
| `dr-sg-private-a` | `10.10.11.0/24` |
| `dr-sg-private-b` | `10.10.12.0/24` |
| `dr-sg-igw` | Internet Gateway |
| `dr-sg-nat` | NAT Gateway trong `dr-sg-public-a` |
| `dr-sg-public-rt` | `0.0.0.0/0 -> IGW` |
| `dr-sg-private-rt` | `0.0.0.0/0 -> NAT` |

## 6. Các bước triển khai

### 6.1 Tạo VPC Singapore

1. Mở AWS Management Console, chọn Region **Asia Pacific (Singapore) `ap-southeast-1`** ở góc trên bên phải.
2. Tại thanh tìm kiếm, gõ `VPC` và nhấp chọn dịch vụ **VPC**.
3. Trong menu bên trái, nhấp chọn **Your VPCs**.
4. Nhấp vào nút **Create VPC** màu cam ở góc trên bên phải.
5. Tại giao diện tạo VPC:
   - **Resources to create**: Chọn **VPC only** (tự cấu hình từng thành phần để nắm vững kiến trúc mạng).
   - **Name tag**: Nhập `dr-sg-vpc`.
   - **IPv4 CIDR manual input**: Tích chọn và nhập `10.10.0.0/16`.
   - **IPv6 CIDR block**: Chọn **No IPv6 CIDR block**.
   - **Tenancy**: Chọn **Default**.
6. Nhấp nút **Create VPC** màu cam ở cuối trang.
7. Bật DNS Hostnames và DNS Resolution cho VPC:
   - Trong trang chi tiết của VPC vừa tạo (hoặc tại danh sách **Your VPCs**, tích chọn `dr-sg-vpc`).
   - Nhấp vào menu **Actions** ở góc trên bên phải -> chọn **Edit VPC settings**.
   - Tại mục **DNS settings**:
     - Tích chọn **Enable DNS resolution**.
     - Tích chọn **Enable DNS hostnames**.
   - Nhấp nút **Save changes**.

### 6.2 Tạo 4 Subnets (2 Public, 2 Private trên 2 AZs)

Xác định trước 2 Availability Zones sẽ dùng tại Singapore (ví dụ: `ap-southeast-1a` và `ap-southeast-1b`).

1. Trong thanh điều hướng bên trái của VPC Console, nhấp chọn **Subnets**.
2. Nhấp vào nút **Create subnet** màu cam.
3. **VPC ID**: Nhấp vào ô tìm kiếm và chọn `dr-sg-vpc`.
4. *Cấu hình Subnet 1 (Public A):*
   - **Subnet name**: `dr-sg-public-a`
   - **Availability Zone**: Chọn AZ đầu tiên (ví dụ: `ap-southeast-1a`)
   - **IPv4 CIDR block**: `10.10.1.0/24`
5. Nhấp nút **Add new subnet** ở phía dưới để thêm subnet tiếp theo:
   - *Cấu hình Subnet 2 (Public B):*
     - **Subnet name**: `dr-sg-public-b`
     - **Availability Zone**: Chọn AZ thứ hai (ví dụ: `ap-southeast-1b`)
     - **IPv4 CIDR block**: `10.10.2.0/24`
6. Nhấp nút **Add new subnet**:
   - *Cấu hình Subnet 3 (Private A):*
     - **Subnet name**: `dr-sg-private-a`
     - **Availability Zone**: Chọn AZ đầu tiên (trùng AZ với Public A, ví dụ: `ap-southeast-1a`)
     - **IPv4 CIDR block**: `10.10.11.0/24`
7. Nhấp nút **Add new subnet**:
   - *Cấu hình Subnet 4 (Private B):*
     - **Subnet name**: `dr-sg-private-b`
     - **Availability Zone**: Chọn AZ thứ hai (trùng AZ với Public B, ví dụ: `ap-southeast-1b`)
     - **IPv4 CIDR block**: `10.10.12.0/24`
8. Nhấp nút **Create subnet** màu cam ở cuối trang để tạo cùng lúc 4 subnet.
9. Bật tự động cấp phát Public IPv4 cho 2 Public subnets:
   - Tại danh sách Subnets, tích chọn `dr-sg-public-a`.
   - Nhấp **Actions** -> chọn **Edit subnet settings**.
   - Tại phần **Auto-assign IP settings**: Tích chọn **Enable auto-assign public IPv4 address** -> nhấp **Save**.
   - Lặp lại thao tác trên cho `dr-sg-public-b`.
   - *Lưu ý:* Tuyệt đối không bật tùy chọn này cho 2 private subnets (`dr-sg-private-a`, `dr-sg-private-b`).

### 6.3 Tạo và gắn Internet Gateway (IGW)

1. Trong thanh điều hướng bên trái, nhấp chọn **Internet gateways**.
2. Nhấp nút **Create internet gateway** màu cam.
3. **Name tag**: Nhập `dr-sg-igw`.
4. Nhấp nút **Create internet gateway**.
5. Sau khi tạo xong, trạng thái ban đầu sẽ là *Detached*:
   - Nhấp vào menu **Actions** ở góc trên bên phải -> chọn **Attach to VPC**.
   - Tại mục **Available VPCs**: Chọn `dr-sg-vpc`.
   - Nhấp nút **Attach internet gateway** màu cam. Trạng thái sẽ chuyển sang *Attached*.

### 6.4 Tạo Public Route Table và gán tuyến đường

1. Trong thanh điều hướng bên trái, nhấp chọn **Route tables**.
2. Nhấp nút **Create route table** màu cam.
3. **Name**: Nhập `dr-sg-public-rt`.
4. **VPC**: Chọn `dr-sg-vpc`.
5. Nhấp nút **Create route table**.
6. Thêm tuyến đường ra Internet qua IGW:
   - Trong trang chi tiết của `dr-sg-public-rt`, chuyển sang tab **Routes**.
   - Nhấp nút **Edit routes**.
   - Nhấp nút **Add route**:
     - **Destination**: Nhập `0.0.0.0/0`.
     - **Target**: Chọn **Internet Gateway** -> chọn `dr-sg-igw`.
   - Nhấp nút **Save changes**.
7. Liên kết Public subnets vào bảng định tuyến:
   - Chuyển sang tab **Subnet associations**.
   - Nhấp nút **Edit subnet associations**.
   - Tích chọn 2 subnet: `dr-sg-public-a` và `dr-sg-public-b`.
   - Nhấp nút **Save associations**.

### 6.5 Tạo NAT Gateway tại Public Subnet

1. Trong thanh điều hướng bên trái, nhấp chọn **NAT gateways**.
2. Nhấp nút **Create NAT gateway** màu cam.
3. Tại giao diện cấu hình:
   - **Name**: Nhập `dr-sg-nat`.
   - **Subnet**: Chọn subnet public `dr-sg-public-a`.
   - **Connectivity type**: Chọn **Public**.
   - **Elastic IP allocation ID**: Nhấp nút **Allocate Elastic IP** để hệ thống tự cấp phát một địa chỉ IP tĩnh công cộng mới.
4. Nhấp nút **Create NAT gateway**.
5. Chờ vài phút cho đến khi trạng thái (Status) của NAT gateway chuyển từ *Pending* sang **Available**.

> [!NOTE]
> **Chế độ Production HA:** Với môi trường Production chịu tải cao, khuyến nghị triển khai Multi-NAT Gateway (mỗi Availability Zone một NAT Gateway nằm trong Public Subnet tương ứng và Route Table Private riêng). Việc dùng một NAT Gateway duy nhất trong bài lab là phương án tối ưu hóa chi phí (khoảng ~$32/tháng/NAT), chấp nhận phụ thuộc tính khả dụng vào AZ chứa NAT.

### 6.6 Tạo Private Route Table và gán tuyến đường ra NAT

1. Trong thanh điều hướng bên trái, nhấp chọn **Route tables**.
2. Nhấp nút **Create route table** màu cam.
3. **Name**: Nhập `dr-sg-private-rt`.
4. **VPC**: Chọn `dr-sg-vpc`.
5. Nhấp nút **Create route table**.
6. Thêm tuyến đường ra Internet an toàn qua NAT Gateway:
   - Chuyển sang tab **Routes** -> nhấp **Edit routes**.
   - Nhấp nút **Add route**:
     - **Destination**: Nhập `0.0.0.0/0`.
     - **Target**: Chọn **NAT Gateway** -> chọn `dr-sg-nat`.
   - Nhấp nút **Save changes**.
7. Liên kết Private subnets vào bảng định tuyến:
   - Chuyển sang tab **Subnet associations** -> nhấp **Edit subnet associations**.
   - Tích chọn 2 subnet: `dr-sg-private-a` và `dr-sg-private-b`.
   - Nhấp nút **Save associations**.

### 6.7 Gắn thẻ (Tags) cho Subnets phục vụ AWS Load Balancer Controller

AWS Load Balancer Controller trong EKS sử dụng các thẻ tag đặc thù để tự động nhận diện đúng subnet khi cấp phát Internet-facing ALB hoặc Internal ALB:

1. Trong menu bên trái, nhấp chọn **Subnets**.
2. *Gắn tag cho 2 Public subnets (`dr-sg-public-a`, `dr-sg-public-b`):*
   - Tích chọn subnet `dr-sg-public-a` -> chuyển sang tab **Tags** ở nửa dưới màn hình -> nhấp **Manage tags**.
   - Nhấp **Add new tag**:
     - **Key**: `kubernetes.io/role/elb`
     - **Value**: `1`
   - Nhấp **Save**.
   - Lặp lại thao tác gắn tag này cho `dr-sg-public-b`.
3. *Gắn tag cho 2 Private subnets (`dr-sg-private-a`, `dr-sg-private-b`):*
   - Tích chọn subnet `dr-sg-private-a` -> chuyển sang tab **Tags** -> nhấp **Manage tags**.
   - Nhấp **Add new tag**:
     - **Key**: `kubernetes.io/role/internal-elb`
     - **Value**: `1`
   - Nhấp **Save**.
   - Lặp lại thao tác gắn tag này cho `dr-sg-private-b`.

## 7. Xác minh

```bash
aws ec2 describe-vpcs --region ap-southeast-1 --filters Name=tag:Name,Values=dr-sg-vpc
aws ec2 describe-subnets --region ap-southeast-1 --filters Name=tag:Name,Values='dr-sg-*' \
  --query 'Subnets[*].[Tags[?Key==`Name`].Value|[0],CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' --output table
aws ec2 describe-route-tables --region ap-southeast-1 --filters Name=vpc-id,Values=<SG_VPC_ID>
aws ec2 describe-nat-gateways --region ap-southeast-1 --filter Name=tag:Name,Values=dr-sg-nat
```

## 8. Kết quả mong đợi

CIDR chính xác, hai AZ, public route qua IGW, private route qua NAT và tag vai trò subnet đầy đủ. Chưa có node EKS hoặc cơ sở dữ liệu.

## 9. Xử lý sự cố

- NAT ở trạng thái `Failed`: kiểm tra EIP, subnet, IGW và thông báo trạng thái.
- Private egress lỗi ở lab sau: xác nhận NAT là `Available`, public route tới IGW, private route tới NAT và DNS đã bật.
- ALB subnet discovery lỗi: kiểm tra chính xác role tag và ít nhất hai subnet phù hợp ở hai AZ khác nhau.
- CIDR chồng lấn: tạo lại trước khi cấu hình peering/cơ sở dữ liệu; không tiếp tục với mạng bị chồng lấn.

## 10. Lưu ý bảo mật

- Không đặt cơ sở dữ liệu hoặc worker node trong public subnet.
- Giữ Network ACL mặc định cho lab; kiểm soát truy cập bằng security group ở các lab sau.
- Nên bật Flow Logs cho production và điều tra bảo mật.
- Cân nhắc VPC endpoint cho ECR API/DKR, S3, STS, EKS, EC2 và Logs để giảm phụ thuộc NAT và chi phí.

## 11. Lưu ý chi phí

NAT Gateway, lưu lượng xử lý, EIP/public IPv4, Flow Logs và endpoint có thể phát sinh phí. Một NAT rẻ hơn nhưng không chịu lỗi ở cấp AZ.

## 12. Dọn dẹp / Quay lui

Xóa theo thứ tự: workload/endpoint phụ thuộc, NAT, giải phóng EIP, route table, tháo và xóa IGW, subnet, VPC. Quy trình đầy đủ nằm ở LAB 27.

## 13. Bằng chứng cần thu thập

- VPC resource map.
- Bảng CIDR/AZ của subnet.
- Route table và subnet association.
- Trạng thái NAT/EIP allocation.
- Tag của subnet.

## 14. Lab tiếp theo

Tiếp tục với [LAB 03 - VPC Tokyo](03-networking-tokyo.md).
