# Runbook: Phục Hồi Cơ Sở Dữ Liệu Aurora Global Database (Database Recovery)

> **Mục đích:** Cung cấp hướng dẫn chuyên sâu cho Database Administrator (DBA) và SRE về các phương án xử lý sự cố, khôi phục dữ liệu, xử lý lỗi đứt gãy replication, chiến lược kết nối endpoints và thăng cấp cụm Amazon Aurora PostgreSQL Global Database.

---

## 1. Kiến Trúc Kết Nối Endpoints và Phương Án Dự Phòng (Endpoints Architecture)

Amazon Aurora cung cấp các loại endpoints sau:
1. **Cluster Writer Endpoint:** Luôn trỏ tới DB instance đang nắm quyền ghi trong cụm khu vực. Khi failover trong nội bộ region, endpoint này tự động chuyển IP sang node replica được thăng cấp.
2. **Cluster Reader Endpoint:** Tự động cân bằng tải (load balancing) cho các truy vấn đọc (Read-only queries) giữa các Read Replicas trong cùng một cụm.
3. **Instance Endpoint:** Điểm kết nối trực tiếp tới một máy chủ DB cụ thể, chủ yếu dùng cho mục đích chẩn đoán hoặc giám sát sâu.
4. **Aurora Global Database Writer Endpoint (Nếu Engine/Version/Account hỗ trợ):** Điểm kết nối toàn cục đại diện cho Primary Cluster hiện tại của Global Database.

### Thiết Kế Dự Phòng Kết Nối (Alternative Connection Design):
> [!IMPORTANT]
> **Không để toàn bộ thiết kế DR phụ thuộc vào một tính năng tùy chọn.** Nếu Global Writer Endpoint không khả dụng trong cấu hình môi trường hoặc phiên bản engine PostgreSQL lựa chọn, hệ thống áp dụng một trong hai giải pháp kiến trúc thay thế chuẩn sau:
> - **Phương án 1 (Secrets Manager DB_HOST Update):** Mỗi vùng duy trì cấu hình `DB_HOST` riêng trong AWS Secrets Manager tại vùng đó. Khi failover sang Tokyo, External Secrets Operator đồng bộ secret trỏ tới Tokyo Cluster Writer Endpoint (`app2-tokyo-db.cluster-xxxx.ap-northeast-1.rds.amazonaws.com`).
> - **Phương án 2 (Route 53 Private Hosted Zone CNAME):** Sử dụng một tên miền nội bộ thống nhất (ví dụ: `db.app2.internal`). Khi sự cố xảy ra, runbook cập nhật bản ghi CNAME trỏ từ Singapore Writer Endpoint sang Tokyo Writer Endpoint.

---

## 2. Các Phương Án Khôi Phục (Recovery Scenarios)

### Kịch bản 1: Planned Switchover (Chuyển đổi theo kế hoạch)
- **Khi nào áp dụng:** Khi cả 2 vùng Singapore và Tokyo đều khỏe mạnh. Dùng cho bảo trì vùng hoặc diễn tập định kỳ.
- **RPO:** **0 (Zero data loss)**. Quá trình switchover đồng bộ sạch sẽ toàn bộ transaction buffer trước khi đổi vai trò.
- **RTO:** Thường hoàn tất trong vòng 1-2 phút.
- **Cách thực hiện trên Console:**
  1. Vào RDS Console -> Databases.
  2. Chọn cụm Global Database `app2-global-db`.
  3. Chọn menu **Actions** -> Chọn **Switch over global database**.
  4. Chọn vùng mục tiêu Tokyo (`ap-northeast-1`) -> Nhấn **Switch over**.

### Kịch bản 2: Unplanned Failover / Detach and Promote (Cứu hộ thảm họa)
- **Khi nào áp dụng:** Khi vùng Singapore sập hoàn toàn (Regional Outage) hoặc mất kết nối mạng kéo dài không thể phục hồi.
- **RPO:** Có thể mất một lượng nhỏ dữ liệu tương ứng với Replication Lag vật lý trước khi thảm họa xảy ra (mục tiêu thiết kế: $< 30\text{s}$, thực tế thường $< 1-2\text{s}$).
- **RTO:** Thường từ 1-3 phút.
- **Cách thực hiện trên Console:**
  1. Vào RDS Console tại region Tokyo (`ap-northeast-1`).
  2. Chọn cụm Regional cluster `app2-tokyo-db`.
  3. Chọn menu **Actions** -> Chọn **Failover global database** (hoặc Remove from global database).
  4. AWS sẽ tách cụm Tokyo khỏi cụm Global và chuyển thành một standalone Aurora Cluster độc lập có toàn quyền Read/Write.

---

## 3. Quy Trình Khắc Phục Lỗi Đồng Bộ Bị Gián Đoạn (Fixing Broken Replication)

Nếu sau sự cố, cụm Singapore quay trở lại nhưng trạng thái replication bị lỗi (`Incompatible-parameters`, `Error`, hoặc `Storage-full`):

### Bước 1: Đánh giá trạng thái trên Console
1. Truy cập RDS Console -> Databases.
2. Kiểm tra cột **Role** và **Status** của cụm Singapore và Tokyo.
3. Nếu cụm Singapore bị detached hoặc không còn đồng bộ được từ Tokyo:
   - Cụm Tokyo hiện tại đang là Primary Writer chứa dữ liệu mới nhất.
   - Cụm Singapore cũ chứa dữ liệu cũ có nguy cơ xung đột.

### Bước 2: Tái tạo lại Secondary Cluster tại Singapore
1. Tạo final snapshot lưu trữ cụm cũ tại Singapore:
   - Snapshot name: `app2-sg-db-legacy-backup`.
2. Xóa cụm DB instance và cluster cũ tại Singapore (`app2-sg-db`).
3. Đứng từ RDS Console vùng Tokyo:
   - Chọn cụm đang là writer: `app2-tokyo-db`.
   - Nếu cụm Tokyo chưa phải là Global Database, chọn **Actions** -> **Add AWS Region** để tạo Global Database mới với Tokyo là Primary.
   - Thêm region đích: `ap-southeast-1 (Singapore)`.
   - Chọn VPC `dr-sg-vpc`, Subnet Group của Singapore, Security Group `app2-sg-db-sg`.
   - Đặt identifier: `app2-sg-db`.
   - Nhấn **Add Region**.
4. AWS Aurora Storage Engine sẽ tự động sao chép toàn bộ storage snapshot từ Tokyo sang Singapore ở tầng lưu trữ vật lý mà không cần dump/restore thủ công.

---

## 4. Xử Lý Tranh Chấp Dữ Liệu Khi Xảy Ra Split-Brain

Nếu vô tình cả hai vùng cùng nhận lệnh ghi trong thời gian xảy ra sự cố mạng phân mảnh (Network Partition):

1. **Ngay lập tức cô lập cụm Singapore cũ:**
   - Sửa Security Group của Aurora Singapore: Xóa toàn bộ inbound rule port 5432 để ngăn chặn mọi backend pod ghi thêm dữ liệu.
2. **So sánh LSN (Log Sequence Number) và dữ liệu chênh lệch:**
   - Kết nối vào cả 2 database qua psql.
   - Truy vấn transaction ID và bản ghi theo thời gian:
     ```sql
     SELECT txid_current_snapshot(), now();
     SELECT * FROM orders WHERE created_at >= '<THỜI_ĐIỂM_SỰ_CỐ>' ORDER BY created_at DESC;
     ```
3. **Thực hiện Reconciliation (Hòa giải dữ liệu):**
   - Xuất dữ liệu các đơn hàng chỉ tồn tại ở Singapore cũ ra file CSV/SQL dump.
   - Import các bản ghi này vào cơ sở dữ liệu Tokyo.
   - Sau khi hòa giải dữ liệu xong, tiến hành tái đồng bộ hóa cụm Singapore theo Bước 3 ở trên.

---

## 5. Cấu Hình Secret và Khởi Động Lại Backend Phụ Thuộc (Least Privilege)

1. Theo nguyên tắc Least Privilege (Đặc quyền tối thiểu):
   - **Chỉ duy nhất `app2-backend-3` kết nối trực tiếp vào PostgreSQL** (để quản lý orders).
   - `app2-backend-1` và `app2-backend-2` **hoàn toàn không kết nối cơ sở dữ liệu** và không được cấp Secret database.
2. Secret `app2/database` trên AWS Secrets Manager cung cấp 5 biến môi trường cho Backend-3:
   - `DB_HOST`: Writer Endpoint của cụm cơ sở dữ liệu
   - `DB_PORT`: `5432`
   - `DB_USER`: `postgres` (hoặc master user được quản lý)
   - `DB_PASSWORD`: Managed credentials từ AWS Secrets Manager
   - `DB_NAME`: `orders_db`
3. Nếu ứng dụng không tự refresh DNS hoặc connection pool sau khi DB chuyển đổi writer, chỉ cần khởi động lại duy nhất deployment Backend-3:
   ```bash
   kubectl rollout restart deployment -n app2 app2-backend-3
   ```
