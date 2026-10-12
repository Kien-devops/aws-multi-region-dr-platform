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

### 6.1 Tạo VPC

```text
VPC Console Singapore -> Your VPCs -> Create VPC
Resources to create: VPC only
Name: dr-sg-vpc
IPv4 CIDR: 10.10.0.0/16
IPv6: No IPv6 CIDR block
Tenancy: Default
-> Create VPC
```

Chọn VPC -> Actions -> Edit VPC settings -> bật DNS resolution và DNS hostnames.

### 6.2 Tạo subnet

```text
VPC -> Subnets -> Create subnet -> VPC dr-sg-vpc
dr-sg-public-a  / <SG_AZ_A> / 10.10.1.0/24
dr-sg-public-b  / <SG_AZ_B> / 10.10.2.0/24
dr-sg-private-a / <SG_AZ_A> / 10.10.11.0/24
dr-sg-private-b / <SG_AZ_B> / 10.10.12.0/24
-> Create subnet
```

Chỉ bật auto-assign public IPv4 trên hai public subnet. Giữ tùy chọn này tắt trên private subnet.

### 6.3 Tạo và gắn IGW

```text
VPC -> Internet gateways -> Create internet gateway
Name: dr-sg-igw -> Create
Actions -> Attach to a VPC -> dr-sg-vpc
```

### 6.4 Tạo public route table

```text
VPC -> Route tables -> Create route table
Name: dr-sg-public-rt; VPC: dr-sg-vpc
Routes -> Add 0.0.0.0/0 -> dr-sg-igw
Subnet associations -> dr-sg-public-a, dr-sg-public-b
```

### 6.5 Tạo NAT Gateway

```text
VPC -> NAT gateways -> Create NAT gateway
Name: dr-sg-nat
Subnet: dr-sg-public-a
Connectivity: Public
Allocate Elastic IP
-> Create; wait for Available
```

**Chế độ production HA:** tạo một NAT cho mỗi AZ và một private route table riêng cho mỗi AZ. Một NAT duy nhất trong lab tạo phụ thuộc vào một AZ và đường truyền dữ liệu liên AZ cho `private-b`.

### 6.6 Tạo private route table

```text
Create route table: dr-sg-private-rt in dr-sg-vpc
Route: 0.0.0.0/0 -> dr-sg-nat
Associate: dr-sg-private-a, dr-sg-private-b
```

### 6.7 Gắn tag cho subnet

Public subnet:

```text
kubernetes.io/role/elb = 1
```

Private subnet:

```text
kubernetes.io/role/internal-elb = 1
```

Tag cũ `kubernetes.io/cluster/dr-sg-eks=shared` không bắt buộc với các phiên bản AWS Load Balancer Controller hiện hành khi subnet discovery thông thường. Chỉ thêm nếu yêu cầu đã được xác minh của controller/phiên bản cụ thể cần tag này.

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
