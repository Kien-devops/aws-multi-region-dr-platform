# LAB 03 - Xây Dựng Hạ Tầng Mạng VPC Tokyo (Networking Tokyo)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Tạo mạng ảo Virtual Private Cloud (VPC) cho vùng dự phòng Tokyo (`ap-northeast-1`) với dải địa chỉ IP không trùng lặp `10.20.0.0/16`.
2. Phân chia 4 subnets trên 2 Availability Zones (AZs) của Tokyo (`ap-northeast-1a` và `ap-northeast-1c`):
   - 2 Public Subnets (cho Tokyo ALB và NAT Gateway).
   - 2 Private Subnets (cho EKS Worker Nodes Tokyo và Aurora Secondary Cluster).
3. Thiết lập Internet Gateway, NAT Gateway và Route Tables cho vùng Tokyo.
4. Gắn các tag đặc thù cho cụm `dr-tokyo-eks`.

---

## Architecture impact

Hạ tầng mạng Tokyo là nền tảng Warm Standby sẵn sàng tiếp quản toàn bộ lưu lượng khi có sự cố:

```text
                                [ INTERNET ]
                                     |
                                     v
                       [ Internet Gateway: dr-tokyo-igw ]
                                     |
            +------------------------+------------------------+
            | (Public Route Table: 0.0.0.0/0 -> dr-tokyo-igw) |
            v                                                 v
  [ Public Subnet AZ-a ]                            [ Public Subnet AZ-c ]
    CIDR: 10.20.0.0/24                                CIDR: 10.20.1.0/24
    - NAT Gateway (dr-tokyo-nat-a)                    - Standby Public Subnet
    - Tokyo Public ALB (AZ-a)                         - Tokyo Public ALB (AZ-c)
            |
            | (Outbound traffic qua NAT Gateway)
            v
  ===================================================================================
            [ Private Route Table: 0.0.0.0/0 -> dr-tokyo-nat-a ]
  ===================================================================================
            |                                                 |
            v                                                 v
  [ Private Subnet AZ-a ]                           [ Private Subnet AZ-c ]
    CIDR: 10.20.10.0/24                               CIDR: 10.20.11.0/24
    - Tokyo EKS Workers (AZ-a)                        - Tokyo EKS Workers (AZ-c)
    - Aurora Secondary DB (AZ-a)                      - Aurora Secondary DB (AZ-c)
```

---

## Resource naming

- Region: `ap-northeast-1` (Tokyo)
- VPC Name: `dr-tokyo-vpc` (`10.20.0.0/16`)
- Internet Gateway: `dr-tokyo-igw`
- Elastic IP: `dr-tokyo-nat-eip`
- NAT Gateway: `dr-tokyo-nat-a`
- Subnets:
  - Public Subnet AZ-A: `dr-tokyo-pub-sub-a` (`10.20.0.0/24`) in `ap-northeast-1a`
  - Public Subnet AZ-C: `dr-tokyo-pub-sub-c` (`10.20.1.0/24`) in `ap-northeast-1c`
  - Private Subnet AZ-A: `dr-tokyo-priv-sub-a` (`10.20.10.0/24`) in `ap-northeast-1a`
  - Private Subnet AZ-C: `dr-tokyo-priv-sub-c` (`10.20.11.0/24`) in `ap-northeast-1c`
- Route Tables:
  - Public Route Table: `dr-tokyo-pub-rt`
  - Private Route Table: `dr-tokyo-priv-rt`

---

## AWS Console Steps

### Bước 1: Chuyển Vùng Sang Tokyo
1. Mở AWS Management Console.
2. Tại thanh điều hướng góc trên bên phải, nhấn chọn Region **Asia Pacific (Tokyo) ap-northeast-1**.

### Bước 2: Tạo VPC Tokyo
1. Tìm kiếm và chọn dịch vụ **VPC**.
2. Ở menu bên trái, chọn **Your VPCs** -> Nhấn nút màu cam **Create VPC**.
3. Chọn tùy chọn **VPC only**.
4. Điền các trường cấu hình:
   - **Name tag:** `dr-tokyo-vpc`
   - **IPv4 CIDR block:** Nhập `10.20.0.0/16` (Lưu ý: Không dùng `10.10.0.0/16` để tránh xung đột dải mạng khi kết nối Peering).
   - **Tenancy:** Chọn *Default*
5. Nhấn nút **Create VPC**.
6. Bật tính năng DNS Hostnames:
   - Trong màn hình chi tiết của `dr-tokyo-vpc`, nhấn menu **Actions** -> Chọn **Edit VPC settings**.
   - Tích chọn cả hai ô:
     - [x] **Enable DNS hostnames**
     - [x] **Enable DNS resolution**
   - Nhấn **Save changes**.

### Bước 3: Tạo 4 Subnets tại Tokyo
Ở menu bên trái, chọn **Subnets** -> Nhấn nút **Create subnet**:

1. **Subnet 1: Public Subnet AZ-A**
   - VPC ID: Chọn `dr-tokyo-vpc`
   - Subnet name: `dr-tokyo-pub-sub-a`
   - Availability Zone: Chọn `ap-northeast-1a`
   - IPv4 subnet CIDR block: `10.20.0.0/24`
   - Nhấn **Add new subnet** ở dưới.

2. **Subnet 2: Public Subnet AZ-C**
   - Subnet name: `dr-tokyo-pub-sub-c`
   - Availability Zone: Chọn `ap-northeast-1c` (Tại Tokyo, AZ 1a và 1c là 2 AZ phổ biến nhất).
   - IPv4 subnet CIDR block: `10.20.1.0/24`
   - Nhấn **Add new subnet** ở dưới.

3. **Subnet 3: Private Subnet AZ-A**
   - Subnet name: `dr-tokyo-priv-sub-a`
   - Availability Zone: Chọn `ap-northeast-1a`
   - IPv4 subnet CIDR block: `10.20.10.0/24`
   - Nhấn **Add new subnet** ở dưới.

4. **Subnet 4: Private Subnet AZ-C**
   - Subnet name: `dr-tokyo-priv-sub-c`
   - Availability Zone: Chọn `ap-northeast-1c`
   - IPv4 subnet CIDR block: `10.20.11.0/24`

5. Nhấn nút **Create subnet**.
6. **Bật Auto-assign Public IP cho 2 Public Subnets:**
   - Chọn `dr-tokyo-pub-sub-a` -> **Actions** -> **Edit subnet settings** -> Tích chọn [x] *Enable auto-assign public IPv4 address* -> **Save**.
   - Lặp lại cho `dr-tokyo-pub-sub-c`.

### Bước 4: Tạo Internet Gateway (IGW)
1. Ở menu bên trái, chọn **Internet gateways** -> Nhấn **Create internet gateway**.
2. Name tag: Nhập `dr-tokyo-igw`.
3. Nhấn **Create internet gateway**.
4. Nhấn menu **Actions** -> Chọn **Attach to VPC**.
5. Chọn `dr-tokyo-vpc` -> Nhấn **Attach internet gateway**.

### Bước 5: Tạo NAT Gateway và Elastic IP
1. Ở menu bên trái, chọn **NAT gateways** -> Nhấn **Create NAT gateway**.
2. Điền thông tin:
   - **Name:** `dr-tokyo-nat-a`
   - **Subnet:** Chọn public subnet `dr-tokyo-pub-sub-a`.
   - **Connectivity type:** Chọn **Public**.
   - Nhấn nút **Allocate Elastic IP** để cấp phát IP tĩnh.
3. Nhấn nút **Create NAT gateway**.
4. Chờ 1-2 phút cho trạng thái chuyển sang `Available`.

### Bước 6: Cấu hình Bảng Định Tuyến (Route Tables)
1. **Public Route Table:**
   - Chọn **Route tables** -> Nhấn **Create route table**.
   - Name: `dr-tokyo-pub-rt`.
   - VPC: Chọn `dr-tokyo-vpc`.
   - Nhấn **Create route table**.
   - Tab **Routes** -> **Edit routes** -> **Add route**:
     - Destination: `0.0.0.0/0` -> Target: **Internet Gateway** (`dr-tokyo-igw`).
     - Nhấn **Save changes**.
   - Tab **Subnet associations** -> **Edit subnet associations**:
     - Tích chọn `dr-tokyo-pub-sub-a` và `dr-tokyo-pub-sub-c` -> Nhấn **Save associations**.

2. **Private Route Table:**
   - Chọn **Route tables** -> Nhấn **Create route table**.
   - Name: `dr-tokyo-priv-rt`.
   - VPC: Chọn `dr-tokyo-vpc`.
   - Nhấn **Create route table**.
   - Tab **Routes** -> **Edit routes** -> **Add route**:
     - Destination: `0.0.0.0/0` -> Target: **NAT Gateway** (`dr-tokyo-nat-a`).
     - Nhấn **Save changes**.
   - Tab **Subnet associations** -> **Edit subnet associations**:
     - Tích chọn `dr-tokyo-priv-sub-a` và `dr-tokyo-priv-sub-c` -> Nhấn **Save associations**.

### Bước 7: Gắn Tags Chuẩn cho EKS Tokyo
1. Vào mục **Subnets**:
2. Chọn `dr-tokyo-pub-sub-a` và `dr-tokyo-pub-sub-c`: Chọn tab **Tags** -> **Manage tags** -> Thêm:
   - `kubernetes.io/role/elb` = `1`
   - `kubernetes.io/cluster/dr-tokyo-eks` = `shared`
3. Chọn `dr-tokyo-priv-sub-a` và `dr-tokyo-priv-sub-c`: Chọn tab **Tags** -> **Manage tags** -> Thêm:
   - `kubernetes.io/role/internal-elb` = `1`
   - `kubernetes.io/cluster/dr-tokyo-eks` = `shared`

---

## Configuration

| Tên Subnet | Dải CIDR | Availability Zone | Loại Subnet | Route Table liên kết |
|---|---|---|---|---|
| `dr-tokyo-pub-sub-a` | `10.20.0.0/24` | `ap-northeast-1a` | Public | `dr-tokyo-pub-rt` (ra IGW) |
| `dr-tokyo-pub-sub-c` | `10.20.1.0/24` | `ap-northeast-1c` | Public | `dr-tokyo-pub-rt` (ra IGW) |
| `dr-tokyo-priv-sub-a`| `10.20.10.0/24`| `ap-northeast-1a` | Private| `dr-tokyo-priv-rt` (ra NAT GW) |
| `dr-tokyo-priv-sub-c`| `10.20.11.0/24`| `ap-northeast-1c` | Private| `dr-tokyo-priv-rt` (ra NAT GW) |

---

## Security considerations

- **Bất đối xứng CIDR (Non-overlapping CIDR):** Singapore dùng `10.10.0.0/16`, Tokyo dùng `10.20.0.0/16`. Điều này là bắt buộc để thực hiện định tuyến cross-region mà không bị xung đột IP (IP Collision).
- **Phân tách ranh giới mạng:** Toàn bộ dữ liệu của Tokyo được cô lập hoàn toàn và tuân thủ nguyên tắc Least Privilege tương tự như vùng Singapore.

---

## Expected result

- VPC `dr-tokyo-vpc` trạng thái `available` với CIDR `10.20.0.0/16`.
- 4 subnets hiển thị đúng dải mạng và AZ.
- NAT Gateway `dr-tokyo-nat-a` chuyển trạng thái `Available`.
- Tags được gán đầy đủ với tiền tố `dr-tokyo-eks`.

---

## Verification

### Kiểm tra bằng Console
1. Kiểm tra VPC Console tại region Tokyo: Thấy `dr-tokyo-vpc`.
2. Kiểm tra Route Tables: `dr-tokyo-priv-rt` có route `0.0.0.0/0` trỏ tới `dr-tokyo-nat-a`.

### Kiểm tra bằng AWS CLI
```bash
aws ec2 describe-vpcs --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=dr-tokyo-vpc" \
  --query "Vpcs[*].[VpcId,CidrBlock,State]" --output table

aws ec2 describe-subnets --region ap-northeast-1 \
  --filters "Name=vpc-id,Values=$(aws ec2 describe-vpcs --region ap-northeast-1 --filters "Name=tag:Name,Values=dr-tokyo-vpc" --query "Vpcs[0].VpcId" --output text)" \
  --query "Subnets[*].[Tags[?Key=='Name'].Value | [0],CidrBlock,AvailabilityZone]" --output table
```

---

## Troubleshooting

1. **Lỗi: Nhầm Availability Zone tại Tokyo (ví dụ chọn `ap-northeast-1b`):**
   - *Nguyên nhân:* Tại vùng Tokyo, AZ `ap-northeast-1b` có một số dịch vụ hoặc instance types không hỗ trợ đầy đủ so với 1a và 1c.
   - *Cách sửa:* Luôn chọn cặp AZ `ap-northeast-1a` và `ap-northeast-1c` để đạt độ tương thích cao nhất cho EKS và RDS.
2. **Lỗi: Không tạo được EKS do subnet tag sai tên cluster:**
   - *Nguyên nhân:* Copy nhầm tag `dr-sg-eks` của Singapore sang Tokyo.
   - *Cách sửa:* Đảm bảo giá trị tag trên các subnet của Tokyo là `kubernetes.io/cluster/dr-tokyo-eks=shared`.
3. **Lỗi: Quên bật DNS Hostnames trên VPC:**
   - *Nguyên nhân:* Aurora PostgreSQL yêu cầu VPC phải bật cả DNS Hostnames và DNS Resolution để tạo endpoint nội bộ.
   - *Cách sửa:* Vào VPC Actions -> Edit VPC settings -> Kích hoạt cả hai mục DNS.

---

## Cost note

- Phát sinh chi phí cho 1 NAT Gateway tại Tokyo (~$0.045/giờ $\approx$ $32/tháng).
- Để tiết kiệm tối đa trong lab thử nghiệm, có thể tạm xóa NAT Gateway khi không thực hành và tái tạo lại sau.

---

## Next step

Tiếp tục chuyển sang [LAB 04 - Thiết Lập Kết Nối Mạng Đa Vùng VPC Peering](04-cross-region-networking.md).
