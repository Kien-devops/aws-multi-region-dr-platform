# LAB 02 - Xây Dựng Hạ Tầng Mạng VPC Singapore (Networking Singapore)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Tạo mạng ảo độc lập Virtual Private Cloud (VPC) cho vùng chính Singapore (`ap-southeast-1`) với dải địa chỉ IP `10.10.0.0/16`.
2. Phân chia 4 subnets trên 2 Availability Zones (AZs) độc lập:
   - 2 Public Subnets (dành cho Application Load Balancer và NAT Gateway).
   - 2 Private Subnets (dành cho EKS Worker Nodes và Amazon Aurora Database).
3. Thiết lập Internet Gateway (IGW), Elastic IP (EIP), và NAT Gateway.
4. Cấu hình bảng định tuyến (Route Tables) và gắn tag chuẩn cho AWS Load Balancer Controller và Kubernetes.

---

## Architecture impact

Hạ tầng mạng vùng Singapore là nền tảng chịu tải chính cho toàn bộ hệ thống:

```text
                                [ INTERNET ]
                                     |
                                     v
                        [ Internet Gateway: dr-sg-igw ]
                                     |
            +------------------------+------------------------+
            | (Public Route Table: 0.0.0.0/0 -> dr-sg-igw)     |
            v                                                 v
  [ Public Subnet AZ-a ]                            [ Public Subnet AZ-b ]
    CIDR: 10.10.0.0/24                                CIDR: 10.10.1.0/24
    - NAT Gateway (dr-sg-nat-a)                       - Spare Public Subnet
    - Internet-facing ALB (AZ-a)                      - Internet-facing ALB (AZ-b)
            |
            | (Outbound traffic qua NAT Gateway)
            v
  ===================================================================================
            [ Private Route Table: 0.0.0.0/0 -> dr-sg-nat-a ]
  ===================================================================================
            |                                                 |
            v                                                 v
  [ Private Subnet AZ-a ]                           [ Private Subnet AZ-b ]
    CIDR: 10.10.10.0/24                               CIDR: 10.10.11.0/24
    - EKS Worker Nodes (AZ-a)                         - EKS Worker Nodes (AZ-b)
    - Aurora DB Instance (AZ-a)                       - Aurora DB Instance (AZ-b)
```

---

## Resource naming

- VPC Name: `dr-sg-vpc` (`10.10.0.0/16`)
- Internet Gateway: `dr-sg-igw`
- Elastic IP: `dr-sg-nat-eip`
- NAT Gateway: `dr-sg-nat-a`
- Subnets:
  - Public Subnet AZ-A: `dr-sg-pub-sub-a` (`10.10.0.0/24`) in `ap-southeast-1a`
  - Public Subnet AZ-B: `dr-sg-pub-sub-b` (`10.10.1.0/24`) in `ap-southeast-1b`
  - Private Subnet AZ-A: `dr-sg-priv-sub-a` (`10.10.10.0/24`) in `ap-southeast-1a`
  - Private Subnet AZ-B: `dr-sg-priv-sub-b` (`10.10.11.0/24`) in `ap-southeast-1b`
- Route Tables:
  - Public Route Table: `dr-sg-pub-rt`
  - Private Route Table: `dr-sg-priv-rt`

---

## AWS Console Steps

### Bước 1: Tạo VPC Singapore
1. Mở AWS Management Console.
2. Tại góc trên bên phải, xác nhận đang chọn Region **Asia Pacific (Singapore) ap-southeast-1**.
3. Tìm kiếm và chọn dịch vụ **VPC**.
4. Ở menu bên trái, chọn **Your VPCs**.
5. Nhấn nút màu cam **Create VPC**.
6. Tại mục **Resources to create**, chọn tùy chọn **VPC only** (Khuyến nghị tạo thủ công từng thành phần để hiểu sâu bản chất).
7. Điền các trường cấu hình:
   - **Name tag:** `dr-sg-vpc`
   - **IPv4 CIDR block:** Chọn *IPv4 CIDR manual input*, nhập: `10.10.0.0/16`
   - **IPv6 CIDR block:** Chọn *No IPv6 CIDR block*
   - **Tenancy:** Chọn *Default*
8. Nhấn nút **Create VPC**.
9. Kích hoạt tính năng phân giải DNS nội bộ:
   - Trong màn hình chi tiết của `dr-sg-vpc`, nhấn menu **Actions** -> Chọn **Edit VPC settings**.
   - Tại mục **DNS settings**, tích chọn cả 2 ô:
     - [x] **Enable DNS hostnames**
     - [x] **Enable DNS resolution**
   - Nhấn **Save changes**.

### Bước 2: Tạo 4 Subnets
Ở menu bên trái, chọn **Subnets** -> Nhấn nút **Create subnet**:

1. **Subnet 1: Public Subnet AZ-A**
   - VPC ID: Chọn `dr-sg-vpc`
   - Subnet name: `dr-sg-pub-sub-a`
   - Availability Zone: Chọn `ap-southeast-1a`
   - IPv4 subnet CIDR block: `10.10.0.0/24`
   - Nhấn **Add new subnet** ở dưới.

2. **Subnet 2: Public Subnet AZ-B**
   - Subnet name: `dr-sg-pub-sub-b`
   - Availability Zone: Chọn `ap-southeast-1b`
   - IPv4 subnet CIDR block: `10.10.1.0/24`
   - Nhấn **Add new subnet** ở dưới.

3. **Subnet 3: Private Subnet AZ-A**
   - Subnet name: `dr-sg-priv-sub-a`
   - Availability Zone: Chọn `ap-southeast-1a`
   - IPv4 subnet CIDR block: `10.10.10.0/24`
   - Nhấn **Add new subnet** ở dưới.

4. **Subnet 4: Private Subnet AZ-B**
   - Subnet name: `dr-sg-priv-sub-b`
   - Availability Zone: Chọn `ap-southeast-1b`
   - IPv4 subnet CIDR block: `10.10.11.0/24`

5. Nhấn nút **Create subnet**.
6. **Bật Auto-assign Public IP cho 2 Public Subnets:**
   - Chọn `dr-sg-pub-sub-a` -> **Actions** -> **Edit subnet settings** -> Tích chọn [x] *Enable auto-assign public IPv4 address* -> **Save**.
   - Lặp lại tương tự cho `dr-sg-pub-sub-b`.

### Bước 3: Tạo Internet Gateway (IGW)
1. Ở menu bên trái, chọn **Internet gateways** -> Nhấn **Create internet gateway**.
2. Name tag: Nhập `dr-sg-igw`.
3. Nhấn **Create internet gateway**.
4. Tại màn hình thông báo vừa tạo thành công, nhấn menu **Actions** -> Chọn **Attach to VPC**.
5. Tại ô **Available VPCs**, chọn `dr-sg-vpc` -> Nhấn nút **Attach internet gateway**.

### Bước 4: Tạo NAT Gateway và Elastic IP
1. Ở menu bên trái, chọn **NAT gateways** -> Nhấn **Create NAT gateway**.
2. Điền thông tin:
   - **Name:** `dr-sg-nat-a`
   - **Subnet:** Chọn public subnet `dr-sg-pub-sub-a` (Bắt buộc phải đặt trong Public Subnet).
   - **Connectivity type:** Chọn **Public**.
   - **Elastic IP allocation ID:** Nhấn nút **Allocate Elastic IP** ngay bên dưới để AWS cấp phát một IP tĩnh công cộng mới.
3. Nhấn nút **Create NAT gateway**.
4. Trạng thái NAT Gateway sẽ là `Pending` trong khoảng 1-2 phút trước khi chuyển sang `Available`.

### Bước 5: Cấu hình Bảng Định Tuyến (Route Tables)
1. **Tạo Public Route Table:**
   - Ở menu bên trái, chọn **Route tables** -> Nhấn **Create route table**.
   - Name: `dr-sg-pub-rt`.
   - VPC: Chọn `dr-sg-vpc`.
   - Nhấn **Create route table**.
   - Chọn tab **Routes** -> Nhấn **Edit routes** -> Nhấn **Add route**:
     - Destination: `0.0.0.0/0`
     - Target: Chọn **Internet Gateway** -> Chọn `dr-sg-igw`.
     - Nhấn **Save changes**.
   - Chọn tab **Subnet associations** -> Nhấn **Edit subnet associations**:
     - Tích chọn cả 2 public subnets: `dr-sg-pub-sub-a` và `dr-sg-pub-sub-b`.
     - Nhấn **Save associations**.

2. **Tạo Private Route Table:**
   - Nhấn **Create route table**.
   - Name: `dr-sg-priv-rt`.
   - VPC: Chọn `dr-sg-vpc`.
   - Nhấn **Create route table**.
   - Chọn tab **Routes** -> Nhấn **Edit routes** -> Nhấn **Add route**:
     - Destination: `0.0.0.0/0`
     - Target: Chọn **NAT Gateway** -> Chọn `dr-sg-nat-a`.
     - Nhấn **Save changes**.
   - Chọn tab **Subnet associations** -> Nhấn **Edit subnet associations**:
     - Tích chọn cả 2 private subnets: `dr-sg-priv-sub-a` và `dr-sg-priv-sub-b`.
     - Nhấn **Save associations**.

### Bước 6: Gắn Tags Cần Thiết cho EKS và AWS Load Balancer Controller
1. Vào mục **Subnets**:
2. Chọn `dr-sg-pub-sub-a` và `dr-sg-pub-sub-b`: Chọn tab **Tags** -> **Manage tags** -> Thêm các thẻ:
   - `kubernetes.io/role/elb` = `1`
   - `kubernetes.io/cluster/dr-sg-eks` = `shared`
3. Chọn `dr-sg-priv-sub-a` và `dr-sg-priv-sub-b`: Chọn tab **Tags** -> **Manage tags** -> Thêm các thẻ:
   - `kubernetes.io/role/internal-elb` = `1`
   - `kubernetes.io/cluster/dr-sg-eks` = `shared`

---

## Configuration

| Tên Subnet | Dải CIDR | Availability Zone | Loại Subnet | Route Table liên kết |
|---|---|---|---|---|
| `dr-sg-pub-sub-a` | `10.10.0.0/24` | `ap-southeast-1a` | Public | `dr-sg-pub-rt` (ra IGW) |
| `dr-sg-pub-sub-b` | `10.10.1.0/24` | `ap-southeast-1b` | Public | `dr-sg-pub-rt` (ra IGW) |
| `dr-sg-priv-sub-a`| `10.10.10.0/24`| `ap-southeast-1a` | Private| `dr-sg-priv-rt` (ra NAT GW) |
| `dr-sg-priv-sub-b`| `10.10.11.0/24`| `ap-southeast-1b` | Private| `dr-sg-priv-rt` (ra NAT GW) |

---

## Security considerations

- **Phân tách Public/Private nghiêm ngặt:** Toàn bộ compute (EKS Node) và database (Aurora) đặt trong Private Subnet không có Public IP.
- **NAT Gateway chiều ra duy nhất (One-way outbound):** Các container trong Private Subnet chỉ có thể gửi request đi ra ngoài (để kéo image, gọi external API, cập nhật OS), tuyệt đối không ai từ Internet có thể khởi tạo kết nối trực tiếp vào các container này.
- **Không bao giờ mở 0.0.0.0/0 cho cơ sở dữ liệu:** Các Security Group sau này cho Aurora và EKS chỉ mở cho CIDR nội bộ VPC.

---

## Expected result

- VPC `dr-sg-vpc` trạng thái `available` với DNS Hostnames và DNS Resolution đã bật.
- 4 subnets hiển thị đúng AZ và dải CIDR.
- NAT Gateway `dr-sg-nat-a` chuyển trạng thái sang `Available`.
- Public Route Table có route `0.0.0.0/0` trỏ về IGW.
- Private Route Table có route `0.0.0.0/0` trỏ về NAT Gateway.

---

## Verification

### Kiểm tra bằng Console
1. Mở VPC Console -> **Virtual private clouds** -> **Your VPCs**: Xác nhận `dr-sg-vpc` có CIDR `10.10.0.0/16`.
2. Kiểm tra **Subnets**: Xác nhận cả 4 subnet đã được gắn đúng Route Table và Tags.

### Kiểm tra bằng AWS CLI
```bash
# Kiểm tra VPC
aws ec2 describe-vpcs --region ap-southeast-1 \
  --filters "Name=tag:Name,Values=dr-sg-vpc" \
  --query "Vpcs[*].[VpcId,CidrBlock,State]" --output table

# Kiểm tra Subnets và CIDR
aws ec2 describe-subnets --region ap-southeast-1 \
  --filters "Name=vpc-id,Values=$(aws ec2 describe-vpcs --region ap-southeast-1 --filters "Name=tag:Name,Values=dr-sg-vpc" --query "Vpcs[0].VpcId" --output text)" \
  --query "Subnets[*].[Tags[?Key=='Name'].Value | [0],CidrBlock,AvailabilityZone]" --output table

# Kiểm tra NAT Gateway
aws ec2 describe-nat-gateways --region ap-southeast-1 \
  --filter "Name=tag:Name,Values=dr-sg-nat-a" \
  --query "NatGateways[*].[NatGatewayId,State,SubnetId]" --output table
```

---

## Troubleshooting

1. **Lỗi: EKS Nodes trong private subnet không kết nối được với EKS Control Plane:**
   - *Nguyên nhân:* Private Route Table thiếu route `0.0.0.0/0 -> nat-gateway`, hoặc NAT Gateway bị tạo nhầm trong Private Subnet.
   - *Cách sửa:* Kiểm tra bảng định tuyến của Private Subnet đảm bảo trỏ ra NAT Gateway, và kiểm tra NAT Gateway phải nằm trong `dr-sg-pub-sub-a`.
2. **Lỗi: AWS Load Balancer Controller không tự động tìm thấy Subnet để tạo ALB:**
   - *Nguyên nhân:* Thiếu các tag `kubernetes.io/role/elb=1` trên public subnets hoặc `kubernetes.io/cluster/dr-sg-eks=shared`.
   - *Cách sửa:* Vào Subnets Console, chọn các public subnets và thêm đúng các thẻ tag theo hướng dẫn ở Bước 6.
3. **Lỗi: `Cannot allocate Elastic IP: The maximum number of addresses has been reached`:**
   - *Nguyên nhân:* Tài khoản AWS chạm ngưỡng quota 5 Elastic IPs cho Region.
   - *Cách sửa:* Vào EC2 Console -> Elastic IPs, giải phóng (Release) các IP tĩnh chưa sử dụng, hoặc gửi yêu cầu nâng hạn mức Service Quotas.

---

## Cost note

- **VPC & Internet Gateway:** Hoàn toàn miễn phí.
- **NAT Gateway:** Phát sinh chi phí tính theo giờ (~$0.045/giờ $\approx$ $32/tháng) cộng với phí xử lý dung lượng ($0.045/GB).
- **Elastic IP:** Miễn phí khi được gắn vào NAT Gateway đang chạy.
- **Mẹo tiết kiệm chi phí trong Lab:** Chỉ sử dụng 1 NAT Gateway duy nhất cho cả 2 AZ trong môi trường thực hành. Khi tạm ngưng lab, hãy xóa NAT Gateway và giải phóng Elastic IP.

---

## Next step

Tiếp tục chuyển sang [LAB 03 - Xây Dựng Hạ Tầng Mạng VPC Tokyo](03-networking-tokyo.md).
