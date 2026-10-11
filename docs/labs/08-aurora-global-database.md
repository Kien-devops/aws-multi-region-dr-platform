# LAB 08 - Khởi Tạo Amazon Aurora PostgreSQL Global Database (Aurora Global Database)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Tạo DB Subnet Groups và DB Security Groups độc lập tại cả Singapore và Tokyo trên các Private Subnets theo nguyên tắc Least Privilege (ưu tiên Security Group của EKS Node).
2. Khởi tạo cụm cơ sở dữ liệu Amazon Aurora PostgreSQL tại Singapore đóng vai trò **Primary Cluster (Writer)**.
3. Kích hoạt tính năng **Aurora Global Database** và thêm vùng Tokyo (`ap-northeast-1`) đóng vai trò **Secondary Cluster (Read-Only Replica)**.
4. Quản lý mật khẩu cơ sở dữ liệu an toàn bằng tùy chọn **Manage master credentials in AWS Secrets Manager** (hoặc tạo mật khẩu ngẫu nhiên an toàn, không dùng mật khẩu mẫu tĩnh).
5. Nắm vững cấu trúc kết nối với 4 loại endpoints, bao gồm phương án dự phòng thiết kế bền vững (Robust Alternative Design) khi Global Writer Endpoint không khả dụng:
   - Cluster Writer Endpoint
   - Cluster Reader Endpoint
   - Instance Endpoint
   - Global Writer Endpoint & Phương án thay thế (Route 53 CNAME / Secrets Manager DB_HOST update)
6. Hiểu rõ chỉ số RPO thực tế: Không giả định replication lag $< 1\text{s}$ như một cam kết bảo đảm, mà phải đo đạc định lượng bằng metric `AuroraGlobalDBReplicationLag`.

---

## Architecture impact

```text
===================================================================================
                       [ AURORA GLOBAL DATABASE: app2-global-db ]
===================================================================================
            |                                                         |
            v                                                         v
+------------------------------------+   Physical Storage     +------------------------------------+
| PRIMARY REGION: SINGAPORE          |     Replication        | DR REGION: TOKYO                   |
| Cluster: app2-sg-db                |     (Lag đo bằng       | Cluster: app2-tokyo-db             |
| Role: Primary Writer               |     CloudWatch Metric) | Role: Secondary Read-Only          |
|                                    | =====================> |                                    |
| [ DB Instance: app2-sg-db-instance]|                        | [ DB Instance: app2-tokyo-db-inst ]|
| (Private Subnets: 10.10.10/11.x)   |                        | (Private Subnets: 10.20.10/11.x)   |
+------------------------------------+                        +------------------------------------+
            ^                                                         ^
            |                                                         |
   EKS Singapore backend-3                                   EKS Tokyo Standby backend-3
   (Giao dịch Ghi & Đọc)                                     (Đọc dữ liệu / Sẵn sàng khi failover)
```

---

## Resource naming

- Global Database Identifier: `app2-global-db`
- Primary Cluster (Singapore): `app2-sg-db`
- Primary Instance (Singapore): `app2-sg-db-instance`
- Secondary Cluster (Tokyo): `app2-tokyo-db`
- Secondary Instance (Tokyo): `app2-tokyo-db-instance`
- Database Engine: **Aurora PostgreSQL (Compatible with PostgreSQL 15.x)**
- Master Username: `app2_admin`
- Database Name: `app2`
- DB Subnet Group Singapore: `app2-sg-db-subnets`
- DB Subnet Group Tokyo: `app2-tokyo-db-subnets`
- DB Security Group Singapore: `app2-sg-db-sg`
- DB Security Group Tokyo: `app2-tokyo-db-sg`

---

## AWS Console Steps

### Bước 1: Chuẩn Bị Network & Security Group tại Singapore
1. Chọn Region **Asia Pacific (Singapore) ap-southeast-1**.
2. **Tạo DB Security Group:**
   - Vào VPC -> **Security groups** -> Nhấn **Create security group**.
   - Name: `app2-sg-db-sg`, VPC: Chọn `dr-sg-vpc`.
   - **Inbound rules:** Nhấn **Add rule**:
     - Type: **PostgreSQL** (Port 5432).
     - Source: Chọn Security Group của EKS Node Group (`dr-sg-workers-sg`) làm nguồn (Production Best Practice). Nếu chưa có, chọn Custom CIDR `10.10.0.0/16` cho môi trường lab.
     - Thêm một rule thứ 2: Type: PostgreSQL, Source: CIDR VPC Tokyo `10.20.0.0/16` (cho phép kết nối qua Peering khi cần admin).
     - *Tuyệt đối không nhập `0.0.0.0/0`*.
   - Nhấn **Create security group**.
3. **Tạo DB Subnet Group:**
   - Vào **RDS** -> **Subnet groups** -> **Create DB subnet group**.
   - Name: `app2-sg-db-subnets`, VPC: Chọn `dr-sg-vpc`.
   - Availability Zones: Chọn `ap-southeast-1a` và `ap-southeast-1b`.
   - Subnets: Chọn 2 Private Subnets `dr-sg-priv-sub-a` (`10.10.10.0/24`) và `dr-sg-priv-sub-b` (`10.10.11.0/24`).
   - Nhấn **Create**.

### Bước 2: Chuẩn Bị Network & Security Group tại Tokyo
1. Chuyển sang Region **Asia Pacific (Tokyo) ap-northeast-1**.
2. **Tạo DB Security Group:**
   - Name: `app2-tokyo-db-sg`, VPC: Chọn `dr-tokyo-vpc`.
   - Inbound: Port 5432 từ Security Group của Tokyo EKS Node (hoặc CIDR `10.20.0.0/16`).
   - Nhấn **Create security group**.
3. **Tạo DB Subnet Group:**
   - Name: `app2-tokyo-db-subnets`, VPC: Chọn `dr-tokyo-vpc`.
   - Subnets: Chọn 2 Private Subnets của Tokyo (`dr-tokyo-priv-sub-a` và `dr-tokyo-priv-sub-c`).
   - Nhấn **Create**.

### Bước 3: Tạo Primary Aurora Cluster tại Singapore
1. Chuyển lại Region về **Asia Pacific (Singapore) ap-southeast-1**.
2. Vào RDS Console -> **Databases** -> **Create database**.
3. **Engine options:** Chọn **Amazon Aurora** -> **Amazon Aurora PostgreSQL-Compatible Edition** -> Version PostgreSQL 15.x.
4. **Templates:** Chọn **Production** (hoặc Dev/Test).
5. **Settings:**
   - DB cluster identifier: `app2-sg-db`.
   - Master username: `app2_admin`.
   - **Credential management:** Tích chọn **Manage master credentials in AWS Secrets Manager** (Khuyến nghị AWS để tự động tạo và lưu trữ mật khẩu mạnh trong Secrets Manager, tránh dùng mật khẩu hardcode).
   - *(Nếu chọn nhập mật khẩu thủ công, hãy sử dụng trình quản lý mật khẩu để tạo một chuỗi ngẫu nhiên mạnh có độ dài ít nhất 16 ký tự và lưu vào nơi an toàn)*.
6. **Instance configuration:** DB instance class: `db.t4g.medium` (hoặc `db.t3.medium`).
7. **Availability & durability:** Chọn *Create an Aurora Replica/Reader node in a different AZ* (Multi-AZ in region).
8. **Connectivity:**
   - VPC: `dr-sg-vpc`.
   - DB Subnet group: `app2-sg-db-subnets`.
   - Public access: **No** (Bắt buộc).
   - Security groups: Chọn `app2-sg-db-sg`.
9. **Additional configuration:**
   - Initial database name: `app2`.
   - Encryption: [x] Enable encryption (AWS KMS).
10. Nhấn **Create database**. Chờ 10-15 phút để cụm chuyển sang trạng thái `Available`.

### Bước 4: Thêm Vùng Tokyo Vào Aurora Global Database
1. Khi cụm `app2-sg-db` đã `Available`:
2. Chọn cụm `app2-sg-db` -> Menu **Actions** -> Chọn **Add AWS Region**.
3. Điền cấu hình:
   - **Global database identifier:** `app2-global-db`.
   - **Region:** `ap-northeast-1 (Tokyo)`.
   - **DB cluster identifier:** `app2-tokyo-db`.
   - **Instance class:** `db.t4g.medium` (hoặc `db.t3.medium`).
   - **Connectivity:** VPC: `dr-tokyo-vpc`, Subnet group: `app2-tokyo-db-subnets`, Security group: `app2-tokyo-db-sg`, Public access: **No**.
4. Nhấn **Add Region**.
5. Cụm Secondary tại Tokyo sẽ tự động được khởi tạo và đồng bộ dữ liệu.

---

## Kiến Trúc Endpoint và Phương Án Thay Thế Bền Vững

Trong hệ thống phân tán, cơ sở dữ liệu có 4 loại endpoints:

| Loại Endpoint | Vai trò kỹ thuật | Phạm vi hoạt động |
|---|---|---|
| **Cluster Writer Endpoint** | Luôn trỏ tới instance đang có quyền ghi trong cụm địa phương | Cục bộ trong từng Region |
| **Cluster Reader Endpoint** | Cân bằng tải cho các read replicas | Cục bộ trong từng Region |
| **Instance Endpoint** | Trỏ cố định vào 1 máy ảo DB instance đơn lẻ | Cục bộ trong từng Region |
| **Global Writer Endpoint** | Tự động phân giải tới Primary Cluster Writer của toàn cầu | Toàn cầu (nếu engine/version hỗ trợ) |

### Phương án thay thế khi Global Writer Endpoint không khả dụng:
Không phải mọi phiên bản Aurora PostgreSQL đều hỗ trợ Global Writer Endpoint tự động cập nhật qua DNS. Để kiến trúc DR không bị phụ thuộc vào một tính năng đơn lẻ, hệ thống áp dụng **chiến lược chuyển đổi qua Secrets Manager & Route 53**:
1. **Chiến lược Secrets Manager (Mặc định trong dự án):**
   - Ứng dụng `backend-3` đọc biến `DB_HOST` từ Kubernetes Secret `app2-db-secret` (đồng bộ qua External Secrets Operator).
   - Tại Singapore, `DB_HOST` trỏ tới Writer Endpoint của cụm Singapore (`app2-sg-db.cluster-....rds.amazonaws.com`).
   - Khi thực hiện Failover sang Tokyo, sau khi thăng cấp cụm Tokyo, pipeline hoặc SRE cập nhật giá trị `DB_HOST` trong Secrets Manager Tokyo trỏ tới Writer Endpoint của cụm Tokyo (`app2-tokyo-db.cluster-....rds.amazonaws.com`). External Secrets Operator tự động reload secret trong cluster.
2. **Chiến lược Route 53 Private Hosted Zone (Tuỳ chọn nâng cao):**
   - Tạo Private DNS `db.app2.internal` trỏ CNAME tới Singapore Writer. Khi failover, cập nhật bản ghi CNAME trỏ sang Tokyo Writer với TTL ngắn (10s).

---

## Thực Tế Về Độ Trễ Sao Chép và Chỉ Số RPO

> [!WARNING]
> Không coi khẳng định "độ trễ replication < 1 giây" như một cam kết bảo đảm tuyệt đối (SLA).
> - Trong điều kiện tải bình thường, hạ tầng lưu trữ của Aurora Global Database thường đạt độ trễ sao chép vật lý dưới 1 giây.
> - Tuy nhiên, trong các đợt tải I/O cao hoặc tắc nghẽn mạng liên lục địa, độ trễ có thể dao động từ vài giây đến hàng chục giây.
> - **Chỉ số RPO thực tế phải được kiểm chứng liên tục qua:**
>   1. Metric CloudWatch: `AuroraGlobalDBReplicationLag` (đơn vị mili-giây).
>   2. Bài kiểm tra thực nghiệm tại [LAB 17](17-rto-rpo-test.md) bằng script `rpo-writer.sh`.
>   3. Mục tiêu thiết kế là **RPO < 30 giây**.

---

## Security considerations

- **SG-to-SG:** Chỉ cho phép cổng 5432 từ Security Group của Worker Node / Pods, không mở toàn bộ VPC nếu có thể.
- **Mã hóa toàn diện:** Mã hóa lưu trữ bằng KMS key và bắt buộc kết nối SSL/TLS giữa `backend-3` và database.
- **Manage in Secrets Manager:** Không chia sẻ mật khẩu dạng plain text trong code hoặc tài liệu.

---

## Expected result

- Cụm `app2-global-db` có Primary tại Singapore và Secondary tại Tokyo.
- Metric `AuroraGlobalDBReplicationLag` hiển thị dữ liệu bình thường.
- Cả hai cụm đều nằm hoàn toàn trong Private Subnets.

---

## Verification

```bash
aws rds describe-global-clusters --region ap-southeast-1 \
  --global-cluster-identifier app2-global-db \
  --query "GlobalClusters[*].[GlobalClusterIdentifier,Status,GlobalClusterMembers[*].[DbClusterArn,IsWriter]]" \
  --output json
```

---

## Troubleshooting

1. **Lỗi: Nhầm lẫn về quyền ghi tại Tokyo trước khi failover:**
   - *Nguyên nhân:* Cụm Tokyo đang là Read-Only Secondary, mọi lệnh INSERT/UPDATE sẽ bị PostgreSQL từ chối với lỗi `cannot execute INSERT in a read-only transaction`.
   - *Cách sửa:* Đây là hành vi đúng. Chỉ khi thực hiện Failover hoặc Switchover, cụm Tokyo mới được phép nhận lệnh ghi.
2. **Lỗi: Replication Lag tăng đột biến:**
   - *Nguyên nhân:* Đang có batch job ghi khối lượng lớn dữ liệu tại Singapore, hoặc instance thiếu CPU Credit.
   - *Cách sửa:* Kiểm tra `CPUUtilization` trên CloudWatch và kiểm tra metric `AuroraGlobalDBReplicationLag`.
3. **Lỗi: Không tìm thấy DB Subnet Group:**
   - *Nguyên nhân:* DB Subnet group chưa chọn đủ 2 private subnets trên 2 AZ khác nhau.
   - *Cách sửa:* Kiểm tra lại Bước 1 và 2.

---

## Cost note

- Chi phí ước tính (chỉ mang tính tham khảo, kiểm tra AWS Pricing Calculator):
  - 2 instances Singapore (Primary + Reader): ~$0.073/giờ x 2 $\approx$ $105/tháng.
  - 1 instance Tokyo (Secondary): ~$0.073/giờ $\approx$ $52/tháng.
  - Phí sao chép I/O: ~$0.20 / triệu requests.

---

## Next step

Tiếp tục chuyển sang [LAB 09 - Quản Lý Bí Mật Với AWS Secrets Manager Đa Vùng](09-secrets-manager.md).
