# LAB 08 - Aurora PostgreSQL Global Database

## 1. Mục tiêu

Tạo Aurora PostgreSQL Global Database được mã hóa, với primary writer tại Singapore và secondary chỉ đọc tại Tokyo, sẵn sàng cho switchover/failover có quản lý.

## 2. Thành phần sẽ xây dựng

- DB subnet group và DB security group tại mỗi Region.
- Global cluster `app2-global-db`.
- Regional cluster `app2-sg-db` và `app2-tokyo-db`.
- Tối thiểu một DB instance mỗi Region cho lab; có hướng dẫn HA cho production.
- Ghi lại global writer endpoint và các regional endpoint.

## 3. Bối cảnh kiến trúc

```text
global writer endpoint của app2-global-db
          -> primary writer hiện tại

Singapore app2-sg-db          Tokyo app2-tokyo-db
primary writer                secondary chỉ đọc
private subnet                private subnet
```

AWS quản lý Aurora storage replication; cơ chế này không cần VPC peering.

Ý nghĩa endpoint:

- **Global writer endpoint:** tự đi theo primary writer hiện tại sau switchover/failover có quản lý; là lựa chọn ưu tiên cho `DB_HOST` tương lai khi được hỗ trợ.
- **Regional cluster/writer endpoint:** trỏ tới writer của regional cluster đó; không hoạt động với secondary global cluster.
- **Regional reader endpoint:** cân bằng truy vấn đọc giữa các reader instance trong regional cluster.
- **Instance endpoint:** gắn với một DB instance; chỉ dùng chẩn đoán, không dùng cho luồng ghi ứng dụng cần khả năng chịu lỗi.

## 4. Điều kiện tiên quyết

- Hoàn thành LAB 02-03 và 05-06.
- Có private subnet tại hai AZ trong mỗi Region.
- Đã ghi lại security group ID của EKS cluster cho truy cập DB tương lai.
- Dùng ma trận tính năng/Region chính thức của AWS để chọn phiên bản Aurora PostgreSQL hỗ trợ Global Database ở cả hai Region.
- Chọn chính xác cùng engine version/patch cho hai regional cluster.
- Phương án maintenance, backup, mã hóa, credential và deletion protection đã được phê duyệt.

## 5. Quy ước đặt tên tài nguyên

| Tài nguyên | Singapore | Tokyo |
|---|---|---|
| DB cluster | `app2-sg-db` | `app2-tokyo-db` |
| DB instance | `app2-sg-db-1` | `app2-tokyo-db-1` |
| Subnet group | `app2-sg-db-subnet-group` | `app2-tokyo-db-subnet-group` |
| Security group | `app2-sg-db-sg` | `app2-tokyo-db-sg` |
| Global cluster | `app2-global-db` | global |
| Cơ sở dữ liệu ban đầu | `app2` | được replicate |
| Master username | `app2_admin` | được replicate |

## 6. Các bước triển khai

### 6.1 Tạo DB Subnet Group tại Singapore và Tokyo

#### Bước 1: Tạo DB Subnet Group tại Singapore
1. Mở AWS Console, chuyển Region sang **Asia Pacific (Singapore) `ap-southeast-1`**.
2. Trên thanh tìm kiếm, gõ `RDS` và chọn dịch vụ **Relational Database Service**.
3. Trong menu bên trái, nhấp chọn **Subnet groups**.
4. Nhấp nút **Create DB subnet group** màu cam ở góc trên bên phải.
5. Tại giao diện cấu hình:
   - **Name**: Nhập `app2-sg-db-subnet-group`.
   - **Description**: Nhập `Subnet group for app2 Aurora PostgreSQL in Singapore`.
   - **VPC**: Chọn `dr-sg-vpc`.
   - Tại mục **Add subnets**:
     - **Availability Zones**: Chọn 2 AZ đã tạo private subnet (ví dụ: `ap-southeast-1a` và `ap-southeast-1b`).
     - **Subnets**: Tích chọn 2 private subnets: `dr-sg-private-a` (`10.10.11.0/24`) và `dr-sg-private-b` (`10.10.12.0/24`). *Không chọn các public subnets.*
6. Nhấp nút **Create** màu cam.

#### Bước 2: Tạo DB Subnet Group tại Tokyo
1. Chuyển Region sang **Asia Pacific (Tokyo) `ap-northeast-1`**.
2. Trong menu bên trái của RDS Console, chọn **Subnet groups** -> nhấp **Create DB subnet group**.
3. Cấu hình:
   - **Name**: Nhập `app2-tokyo-db-subnet-group`.
   - **Description**: Nhập `Subnet group for app2 Aurora PostgreSQL in Tokyo`.
   - **VPC**: Chọn `dr-tokyo-vpc`.
   - **Availability Zones**: Chọn 2 AZ tương ứng tại Tokyo (ví dụ: `ap-northeast-1a` và `ap-northeast-1c`).
   - **Subnets**: Tích chọn 2 private subnets: `dr-tokyo-private-a` (`10.20.11.0/24`) và `dr-tokyo-private-b` (`10.20.12.0/24`).
4. Nhấp nút **Create** màu cam.

### 6.2 Tạo DB Security Group tại hai Region

#### Bước 1: Tạo Security Group tại Singapore
1. Chuyển Region về **Asia Pacific (Singapore) `ap-southeast-1`**.
2. Vào **VPC** Console -> chọn mục **Security groups** -> nhấp **Create security group**.
3. **Security group name**: Nhập `app2-sg-db-sg`.
4. **Description**: Nhập `Allow PostgreSQL inbound from EKS Singapore nodes`.
5. **VPC**: Chọn `dr-sg-vpc`.
6. Tại mục **Inbound rules**:
   - Nhấp **Add rule**:
     - **Type**: Chọn **PostgreSQL** (Port `5432`).
     - **Source**: Chọn **Custom** -> tìm và chọn Security Group của EKS Cluster hoặc Worker Nodes (`dr-sg-eks`).
7. Nhấp nút **Create security group**.

#### Bước 2: Tạo Security Group tại Tokyo
1. Chuyển Region sang **Asia Pacific (Tokyo) `ap-northeast-1`**.
2. Vào **VPC** -> **Security groups** -> nhấp **Create security group**.
3. **Security group name**: Nhập `app2-tokyo-db-sg`.
4. **VPC**: Chọn `dr-tokyo-vpc`.
5. **Inbound rules**:
   - Thêm rule PostgreSQL port `5432`, Source chọn Security Group của EKS Tokyo (`dr-tokyo-eks`).
6. Nhấp **Create security group**.

### 6.3 Tạo Primary Aurora PostgreSQL Cluster tại Singapore

1. Chuyển Region về **Asia Pacific (Singapore) `ap-southeast-1`**.
2. Truy cập dịch vụ **RDS** -> trong menu bên trái, chọn **Databases** -> nhấp nút **Create database** màu cam.
3. **Choose a database creation method**: Chọn **Standard create**.
4. **Engine options**:
   - **Engine type**: Chọn **Amazon Aurora**.
   - **Edition**: Chọn **Amazon Aurora PostgreSQL-Compatible Edition**.
   - **Engine version**: Chọn phiên bản hỗ trợ Global Database ở cả 2 Region (ví dụ: `Aurora PostgreSQL 16.3` hoặc phiên bản 15/16 mới nhất được hỗ trợ đồng đều).
5. **Templates**: Chọn **Production** hoặc **Dev/Test** (phù hợp với ngân sách lab).
6. **Settings**:
   - **DB cluster identifier**: Nhập `app2-sg-db`.
   - **Master username**: Nhập `app2_admin`.
   - **Master password**: Tích chọn **Manage master credentials in AWS Secrets Manager** (khuyến nghị để AWS tự quản lý khóa bí mật an toàn) hoặc nhập mật khẩu mạnh tự tạo.
7. **Cluster storage configuration**: Chọn **Aurora Standard**.
8. **Instance configuration**:
   - **DB instance class**: Chọn lớp instance nhỏ nhất có hỗ trợ Global Database (ví dụ: `db.r6g.large` hoặc `db.t4g.medium` nếu engine version được hỗ trợ).
9. **Availability & durability**:
   - Chọn **Create an Aurora Replica/Reader node in a different AZ** (hoặc chọn *Don't create an Aurora Replica* nếu muốn tiết kiệm chi phí tối đa cho lab).
10. **Connectivity**:
    - **Compute resource**: Chọn **Don't connect to an EC2 compute resource**.
    - **Network type**: Chọn **IPv4**.
    - **Virtual private cloud (VPC)**: Chọn `dr-sg-vpc`.
    - **DB subnet group**: Chọn `app2-sg-db-subnet-group`.
    - **Public access**: Chọn **No** (Bắt buộc riêng tư).
    - **Existing VPC security groups**: Xóa nhóm mặc định, chọn `app2-sg-db-sg`.
11. **Database authentication**: Chọn **Password authentication**.
12. **Additional configuration**:
    - **Initial database name**: Nhập `app2`.
    - **Backup**: Retention period đặt `7 days`.
    - **Encryption**: Bật **Enable encryption**, KMS key chọn `(default) aws/rds`.
    - **Deletion protection**: Tích chọn **Enable deletion protection**.
13. Nhấp nút **Create database** màu cam ở cuối trang.
14. Chờ từ 10-15 phút để cluster và instance chuyển hoàn toàn sang trạng thái **Available**.

### 6.4 Chuyển đổi Primary Cluster thành Global Database

1. Đảm bảo cluster `app2-sg-db` đã ở trạng thái **Available**.
2. Tại danh sách **Databases** trong RDS Console tại Singapore, tích chọn vào cluster `app2-sg-db` (dòng có role là *Regional cluster* hoặc *Writer*).
3. Nhấp vào menu **Actions** ở góc trên bên phải -> chọn **Add AWS Region** (hoặc **Create global database** tùy phiên bản giao diện).
4. Tại màn hình tạo Global Database:
   - **Global database identifier**: Nhập `app2-global-db`.
5. Tiếp tục thực hiện cấu hình Secondary Cluster tại Tokyo ngay trên màn hình này (xem chi tiết mục 6.5).

### 6.5 Thêm Secondary Cluster tại Tokyo

Trên cùng giao diện **Add AWS Region**:

1. **Secondary Region details**:
   - **AWS Region**: Chọn **Asia Pacific (Tokyo) ap-northeast-1**.
2. **Settings**:
   - **DB cluster identifier**: Nhập `app2-tokyo-db`.
3. **Instance configuration**:
   - **DB instance class**: Chọn lớp instance hoàn toàn tương đồng với Singapore (ví dụ: `db.r6g.large` hoặc `db.t4g.medium`).
   - **DB instance identifier**: Nhập `app2-tokyo-db-1`.
4. **Connectivity**:
   - **Virtual private cloud (VPC)**: Chọn `dr-tokyo-vpc`.
   - **DB subnet group**: Chọn `app2-tokyo-db-subnet-group`.
   - **Public access**: Chọn **No**.
   - **Existing VPC security groups**: Chọn `app2-tokyo-db-sg`.
5. **Encryption**:
   - Bật mã hóa và chọn KMS key tại Tokyo (`aws/rds` hoặc Customer Managed Key).
6. **Deletion protection**: Tích chọn **Enable deletion protection**.
7. Nhấp nút **Add Region** màu cam ở cuối trang.
8. Quá trình tạo Secondary Cluster tại Tokyo và thiết lập liên kết lưu trữ Global Storage Replication sẽ diễn ra trong khoảng 15-20 phút.
9. Kiểm tra danh sách: Bạn sẽ thấy cluster cấp cao nhất là `app2-global-db` (Global database), bên trong chứa:
   - `app2-sg-db` (Primary, Writer) tại Singapore.
   - `app2-tokyo-db` (Secondary, Read-only) tại Tokyo.

### 6.6 Ghi lại Endpoints và Tham chiếu Quản trị

1. Nhấp vào tên cluster `app2-global-db` (hoặc mở rộng cây thư mục cluster):
2. Trong tab **Connectivity & security**, ghi lại các endpoint quan trọng:
   - **Global writer endpoint** (nếu hiển thị): Điểm kết nối toàn cầu tự động trỏ tới Writer Region hiện tại.
   - **Regional Cluster Writer endpoint** của Singapore: `app2-sg-db.cluster-xxxxxx.ap-southeast-1.rds.amazonaws.com` (Cổng `5432`).
   - **Regional Reader endpoint** của Tokyo: `app2-tokyo-db.cluster-ro-xxxxxx.ap-northeast-1.rds.amazonaws.com` (Cổng `5432`).
3. Nếu ở bước 6.3 bạn đã chọn *Manage master credentials in AWS Secrets Manager*, hệ thống sẽ tạo một Secret tự động trong Secrets Manager. Lưu ý tên hoặc ARN của Secret này để dùng cho LAB 09. Không chụp màn hình hiển thị mật khẩu thô.

## 7. Xác minh

```bash
aws rds describe-global-clusters --region ap-southeast-1 --global-cluster-identifier app2-global-db \
  --query 'GlobalClusters[0].{Status:Status,Engine:Engine,Version:EngineVersion,GlobalWriterEndpoint:Endpoint,Members:GlobalClusterMembers[*].{Arn:DBClusterArn,Writer:IsWriter,Sync:SynchronizationStatus}}'

aws rds describe-db-clusters --region ap-southeast-1 --db-cluster-identifier app2-sg-db
aws rds describe-db-clusters --region ap-northeast-1 --db-cluster-identifier app2-tokyo-db
```

Trong CloudWatch Tokyo, kiểm tra datapoint thực tế của `AuroraGlobalDBReplicationLag`, `AuroraGlobalDBProgressLag` và `AuroraGlobalDBRPOLag` khi metric khả dụng.

## 8. Kết quả mong đợi

Có một global cluster; Singapore là writer duy nhất; Tokyo là secondary chỉ đọc đã kết nối; instance private được mã hóa; endpoint đã ghi nhận; metric đang phát dữ liệu.

## 9. Xử lý sự cố

- Không có Add Region: engine/version/Region/instance class không tương thích tính năng.
- Switchover bị từ chối dù cùng minor version: patch level hoặc pending maintenance có thể khác nhau.
- Không kết nối được: kiểm tra đường client, nguồn DB SG, route, DNS, credential và yêu cầu TLS.
- Replication lag tăng: kiểm tra tải writer, sức khỏe/dung lượng secondary instance, RDS event và điều kiện liên Region.

## 10. Lưu ý bảo mật

- DB chỉ private, kết nối TLS, storage/backup được mã hóa và credential được bảo vệ.
- Customer-managed KMS cần regional key/policy chính xác; KMS key là tài nguyên theo Region.
- Bật deletion protection và giới hạn quyền thực hiện RDS failover/switchover.
- Cân nhắc IAM DB authentication hoặc user ứng dụng riêng ở Giai đoạn 2; không dùng master user từ pod ứng dụng trong production.

## 11. Lưu ý chi phí

Aurora instance, storage, I/O, backup vượt mức miễn phí, I/O/truyền dữ liệu replication liên Region, insights và log tính phí liên tục. Một instance mỗi Region là thỏa hiệp cho lab, không phải production HA.

## 12. Dọn dẹp / Quay lui

Xóa tài nguyên có mức ảnh hưởng cao. Giữ snapshot; gỡ secondary/instance đúng thứ tự, sau đó mới tới global/primary resource theo LAB 27. Không tắt deletion protection quá sớm.

## 13. Bằng chứng cần thu thập

Engine/version, topology Global Database, một writer, trạng thái đồng bộ, subnet group, truy cập private, mã hóa/KMS, backup/deletion protection, endpoint đã che một phần hostname và lag metric.

## 14. Lab tiếp theo

Tiếp tục với [LAB 09 - Secrets Manager đa Region](09-secrets-manager.md).
