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

### 6.1 Tạo VPC

```text
VPC Console Tokyo -> Your VPCs -> Create VPC
Resources: VPC only
Name: dr-tokyo-vpc
IPv4 CIDR: 10.20.0.0/16
IPv6: None
Tenancy: Default
-> Create VPC
```

Chọn VPC -> Actions -> Edit VPC settings -> bật DNS resolution và DNS hostnames.

### 6.2 Tạo bốn subnet

```text
VPC -> Subnets -> Create subnet -> VPC dr-tokyo-vpc
dr-tokyo-public-a  / <TOKYO_AZ_A> / 10.20.1.0/24
dr-tokyo-public-b  / <TOKYO_AZ_B> / 10.20.2.0/24
dr-tokyo-private-a / <TOKYO_AZ_A> / 10.20.11.0/24
dr-tokyo-private-b / <TOKYO_AZ_B> / 10.20.12.0/24
-> Create subnet
```

Với từng public subnet: Actions -> Edit subnet settings -> bật auto-assign public IPv4. Giữ tùy chọn này tắt trên private subnet.

### 6.3 Tạo IGW và public route table

```text
VPC -> Internet gateways -> Create -> dr-tokyo-igw
Actions -> Attach to VPC -> dr-tokyo-vpc

VPC -> Route tables -> Create -> dr-tokyo-public-rt
VPC: dr-tokyo-vpc
Route: 0.0.0.0/0 -> dr-tokyo-igw
Associate: dr-tokyo-public-a, dr-tokyo-public-b
```

### 6.4 Tạo NAT Gateway

```text
VPC -> NAT gateways -> Create NAT gateway
Name: dr-tokyo-nat
Subnet: dr-tokyo-public-a
Connectivity: Public
Allocate Elastic IP
-> Create; wait for Available
```

### 6.5 Tạo private route table

```text
VPC -> Route tables -> Create -> dr-tokyo-private-rt
VPC: dr-tokyo-vpc
Route: 0.0.0.0/0 -> dr-tokyo-nat
Associate: dr-tokyo-private-a, dr-tokyo-private-b
```

### 6.6 Thêm tag cho subnet

Public: `kubernetes.io/role/elb=1`. Private: `kubernetes.io/role/internal-elb=1`.

Chế độ production HA cần một NAT và một private route table cho mỗi AZ.

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
