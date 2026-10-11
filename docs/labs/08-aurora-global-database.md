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

### 6.1 Tạo DB subnet group

Singapore:

```text
RDS -> Subnet groups -> Create DB subnet group
Name: app2-sg-db-subnet-group
VPC: dr-sg-vpc
AZs: <SG_AZ_A>, <SG_AZ_B>
Subnets: dr-sg-private-a, dr-sg-private-b
```

Lặp lại tại Tokyo với `app2-tokyo-db-subnet-group` và các private subnet Tokyo.

### 6.2 Tạo DB security group

Singapore VPC Console:

```text
Security Groups -> Create
Name: app2-sg-db-sg
VPC: dr-sg-vpc
Inbound: PostgreSQL TCP 5432 from the Singapore EKS cluster/node security group only
Outbound: default initially; tighten after required flows are known
```

Lặp lại tại Tokyo, chỉ dùng EKS security group của Tokyo làm nguồn. Không cho phép `0.0.0.0/0`; không public DB. Khi kiểm tra peering liên Region tùy chọn, chỉ thêm tạm CIDR private subnet của peer vì không hỗ trợ tham chiếu SG liên Region.

### 6.3 Tạo primary cluster tại Singapore

AWS Console tại Singapore:

```text
RDS -> Databases -> Create database
Creation method: Standard create
Engine: Amazon Aurora
Edition: Aurora PostgreSQL-Compatible
Engine version: <AURORA_PG_VERSION_SUPPORTED_IN_BOTH_REGIONS>
Template: Production or Dev/Test according to lab budget
DB cluster identifier: app2-sg-db
Master username: app2_admin
Credentials: Manage in AWS Secrets Manager preferred
Initial database name: app2
Instance class: smallest class shown as supported for selected Global Database engine; record it
Availability: one writer for lab; add a reader in another AZ for production HA
VPC: dr-sg-vpc
DB subnet group: app2-sg-db-subnet-group
Public access: No
Security group: app2-sg-db-sg
Storage encryption: Enabled
KMS: aws/rds for lab or approved customer-managed regional key
Backup retention: 7 days lab; production according to policy
Deletion protection: Enabled
Log exports: PostgreSQL and upgrade logs as required
Performance Insights/Database Insights: enable according to budget
-> Create database
```

Chờ cluster và instance chuyển sang `Available`.

### 6.4 Chuyển đổi/tạo Global Database

Chọn `app2-sg-db` trong RDS Console:

```text
Actions -> Add AWS Region / Create global database
Global database identifier: app2-global-db
Confirm engine/version and encryption
-> Create/continue
```

Nhãn trên Console có thể thay đổi theo thời gian; kết quả bắt buộc là global cluster chứa `app2-sg-db` với vai trò writer member.

### 6.5 Thêm secondary tại Tokyo

Từ trang chi tiết global database:

```text
Add Region
Region: ap-northeast-1
DB cluster identifier: app2-tokyo-db
Engine version: exact compatible version
Instance identifier: app2-tokyo-db-1
Instance class: supported lab class
VPC: dr-tokyo-vpc
DB subnet group: app2-tokyo-db-subnet-group
Public access: No
Security group: app2-tokyo-db-sg
Encryption: Enabled with Tokyo regional KMS key
Deletion protection: Enabled
-> Add Region
```

Chờ trạng thái replication là connected và cả hai cluster available.

### 6.6 Ghi lại endpoint và tham chiếu credential

Trong mục `Connectivity & security` của global cluster, ghi lại Global Database writer endpoint. Ghi riêng reader/writer endpoint của từng regional cluster. Không lưu mật khẩu trong Git hoặc ảnh chụp màn hình.

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

Xóa tài nguyên có mức ảnh hưởng cao. Giữ snapshot; gỡ secondary/instance đúng thứ tự, sau đó mới tới global/primary resource theo LAB 18. Không tắt deletion protection quá sớm.

## 13. Bằng chứng cần thu thập

Engine/version, topology Global Database, một writer, trạng thái đồng bộ, subnet group, truy cập private, mã hóa/KMS, backup/deletion protection, endpoint đã che một phần hostname và lag metric.

## 14. Lab tiếp theo

Tiếp tục với [LAB 09 - Secrets Manager đa Region](09-secrets-manager.md).
