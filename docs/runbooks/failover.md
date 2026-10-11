# Runbook: Quy Trình Failover Sang Tokyo (DR Failover to Tokyo)

> **Mục đích:** Hướng dẫn đội ngũ SRE / DevOps thực hiện chuyển giao toàn bộ hoạt động của hệ thống từ Singapore (`ap-southeast-1`) sang Tokyo (`ap-northeast-1`) khi xảy ra sự cố nghiêm trọng hoặc trong các đợt diễn tập định kỳ.

---

## 1. Tiêu Chí Kích Hoạt (Activation Criteria & Preconditions)

Chỉ kích hoạt Failover khi thỏa mãn một trong các điều kiện sau:
1. **Sự cố thực tế:**
   - Cụm Singapore gặp mất điện / gián đoạn kết nối AWS diện rộng trên nhiều AZ kéo dài quá 3 phút.
   - Toàn bộ Endpoint Group Singapore trên AWS Global Accelerator chuyển trạng thái `UNHEALTHY`.
   - Có sự phê duyệt chính thức từ Incident Commander (Trưởng ban xử lý sự cố).
2. **Diễn tập có kế hoạch (Planned DR Drill):**
   - Đã thông báo cho các bên liên quan và đang trong cửa sổ bảo trì (maintenance window).
   - Kiểm tra replication lag của Aurora Global Database hiện tại dưới 1 giây (`AuroraGlobalDBReplicationLag < 1000 ms`).

---

## 2. Nguyên Tắc Ngăn Chặn Xung Đột Split-Brain (Prevent Split-Brain)

> [!CAUTION]
> **Rủi ro lớn nhất trong DR là Split-Brain:** Tình trạng cả hai cụm cơ sở dữ liệu cùng nhận lệnh ghi (Dual-Primary Writer) do mạng bị phân mảnh. Dẫn đến phân rã dữ liệu và không thể đồng bộ lại được mà không có sự can thiệp thủ công phức tạp.

Để ngăn chặn tuyệt đối Split-Brain:
1. **Trong diễn tập kiểm thử có kiểm soát (Controlled Test):**
   - Trước khi thăng cấp Tokyo thành Writer, **bắt buộc phải cô lập hoàn toàn cụm Singapore Writer** (scale workloads Singapore về 0 hoặc chặn port 5432 trên Security Group của Aurora Singapore).
   - Đảm bảo không còn bất kỳ transaction nào từ Singapore đang ghi vào storage.
2. **Trong sự cố mất điện/mạng thực tế (Unplanned Outage):**
   - Khi cụm Singapore đột ngột khôi phục kết nối mạng, **cụm Singapore cũ tuyệt đối không được phép nhận lệnh ghi**.
   - Không được cấu hình DNS tự động trỏ về Singapore.
   - Cụm Singapore cũ phải được giữ ở trạng thái cô lập cho tới khi được tái cấu trúc thành Secondary Cluster đồng bộ từ Tokyo theo [database-recovery.md](database-recovery.md).
3. **Không bao giờ tự động failback:** Mọi quyết định quay trở lại Singapore phải được thực hiện có kế hoạch (Planned Failback) sau khi Singapore đã chạy ổn định tối thiểu 30 phút.

---

## 3. Nhật Ký Sự Cố (Incident Time Tracker)

Trước khi bắt đầu thao tác, người thực hiện phải mở bảng nhật ký và ghi nhận chính xác từng mốc thời gian:

| Mốc | Sự kiện | Thời gian thực tế (UTC / GMT+7) | Người thực hiện | Ghi chú |
|---|---|---|---|---|
| **$T_0$** | Sự cố phát sinh / Lệnh diễn tập kích hoạt | | | Điểm gốc tính toán |
| **$T_1$** | Báo động giám sát xác nhận sự cố | | | Health check `/health` báo lỗi |
| **$T_2$** | Traffic chuyển hướng thành công sang Tokyo ALB | | | Global Accelerator chuyển routing |
| **$T_3$** | Aurora Tokyo hoàn tất thăng cấp thành Primary Writer | | | Cụm Tokyo chuyển thành `Regional primary` |
| **$T_4$** | Request đọc dữ liệu đầu tiên thành công tại Tokyo | | | `GET /api/v1/catalog` trả về HTTP 200 |
| **$T_5$** | Transaction ghi dữ liệu đầu tiên thành công tại Tokyo | | | `POST /api/v1/orders` commit thành công |
| **RTO** | **$T_5 - T_0$** | **... phút ... giây** | | **Mục tiêu: < 5 phút** |

> [!NOTE]
> Lưu ý về chuỗi phụ thuộc: Khi lưu lượng chuyển sang Tokyo ($T_2$), các request đọc (`GET /health`, `GET /api/v1/catalog`) sẽ thành công ($T_4$), nhưng các giao dịch ghi (`POST /api/v1/orders`) sẽ thất bại cho đến khi Aurora Tokyo hoàn tất thăng cấp thành Writer ($T_3$). Do đó, mốc $T_5$ (Ghi thành công) mới là mốc hoàn tất RTO thực tế.

---

## 4. Quy Trình Thao Tác Chi Tiết (Operational Step-by-Step)

### Bước 1: Xác nhận tình trạng Cụm Standby Tokyo
Trước khi chuyển giao, đảm bảo vùng Tokyo đang hoạt động ổn định:
1. Mở AWS Console tại region **Asia Pacific (Tokyo) ap-northeast-1**.
2. Kiểm tra EKS cluster `dr-tokyo-eks`: Trạng thái `ACTIVE`.
3. Kiểm tra pod trạng thái ứng dụng:
   ```bash
   kubectl --context tokyo get pods -n app2
   ```
   Tất cả pods (`frontend`, `backend-1`, `backend-2`, `backend-3`) phải ở trạng thái `Running (1/1)` (Warm Standby 1 replica mỗi service).
4. Kiểm tra ALB Tokyo trên EC2 Console -> Load Balancers -> `app2-tokyo-alb`: Trạng thái `Active`, Target Groups kiểm tra `/health` đều `Healthy`.

### Bước 2: Chuyển hướng Traffic bằng Global Accelerator
Nếu dùng Option A (Deterministic Traffic Dial Control):
1. Mở AWS Console -> **AWS Global Accelerator** -> Chọn `app2-global`.
2. Chuyển sang tab **Listeners** -> Chọn listener port 80.
3. Tại danh sách Endpoint groups:
   - Chọn Endpoint group **ap-southeast-1 (Singapore)** -> Chọn **Edit**.
   - Đặt **Traffic dial** = `0%` -> Chọn **Save changes**.
   - Chọn Endpoint group **ap-northeast-1 (Tokyo)** -> Chọn **Edit**.
   - Đặt **Traffic dial** = `100%` -> Chọn **Save changes**.
4. Ghi nhận mốc **$T_2$** khi lệnh test truy cập trả về server Tokyo:
   ```bash
   curl -s http://<GLOBAL_ACCELERATOR_IP>/health | jq .
   ```
   *Body trả về `"region": "ap-northeast-1"`.*

### Bước 3: Thăng cấp Cơ sở dữ liệu Tokyo (Aurora Promotion)
#### Tùy chọn A: Planned Switchover (Diễn tập / Không mất dữ liệu)
1. Mở AWS Console -> Dịch vụ **RDS** -> Chọn cụm Global database `app2-global-db`.
2. Chọn menu **Actions** -> Chọn **Switch over global database**.
3. Chọn vùng mục tiêu mới: `app2-tokyo-db (ap-northeast-1)`.
4. Xác nhận lệnh switchover.
5. Chờ 60 - 90 giây cho cụm Tokyo chuyển thành Primary Writer. Ghi nhận mốc **$T_3$**.

#### Tùy chọn B: Unplanned Failover (Sự cố khẩn cấp vùng Singapore)
1. Mở AWS Console -> Chuyển sang region **ap-northeast-1 (Tokyo)**.
2. Vào dịch vụ **RDS** -> Chọn cụm `app2-tokyo-db`.
3. Chọn menu **Actions** -> Chọn **Failover global database** (hoặc Remove from global database).
4. Xác nhận chấp nhận thăng cấp ngay lập tức để cứu hộ dịch vụ.
5. Ghi nhận mốc **$T_3$** khi cụm Tokyo chuyển trạng thái sang `Available` với vai trò `Regional primary`.

### Bước 4: Scale Workload tại Tokyo lên Full Production
1. Tăng số lượng Pods để sẵn sàng chịu 100% tải người dùng:
   ```bash
   kubectl --context tokyo scale deployment -n app2 --replicas=2 --all
   ```
2. Kiểm tra các Pod mới khởi tạo thành công:
   ```bash
   kubectl --context tokyo get pods -n app2
   ```

### Bước 5: Xác thực Đọc và Ghi Nghiệp vụ (Validation)
1. **Kiểm tra Đọc (Read - $T_4$):**
   ```bash
   curl -s http://<GLOBAL_ACCELERATOR_IP>/api/v1/catalog | jq .
   ```
   Xác nhận HTTP 200 và dữ liệu trả về chính xác. Ghi nhận mốc **$T_4$**.
2. **Kiểm tra Ghi (Write - $T_5$):**
   Tạo một đơn hàng mới qua backend-3:
   ```bash
   curl -X POST http://<GLOBAL_ACCELERATOR_IP>/api/v1/orders \
     -H "Content-Type: application/json" \
     -d '{"item_id":"test-item","quantity":1,"marker":"FAILOVER_VERIFICATION"}'
   ```
   Xác nhận HTTP 201 Created và đơn hàng commit thành công vào cơ sở dữ liệu. Ghi nhận mốc **$T_5$**.
3. Tính toán RTO thực tế: $\text{RTO} = T_5 - T_0$.

---

## 5. Danh Sách Điều Cấm Tuyệt Đối (Crucial "DO NOT" Rules)
- ❌ **KHÔNG** chạy hai writer primary cùng lúc (Tránh rủi ro Split-Brain hủy hoại dữ liệu).
- ❌ **KHÔNG** vội vàng failback ngược lại Singapore ngay khi thấy Singapore vừa có tín hiệu mạng trở lại. Vùng sự cố cần được theo dõi tối thiểu 30-60 phút để đảm bảo không bị chập chờn (flapping).
- ❌ **KHÔNG** hardcode IP database thủ công trong Pod backend; luôn dùng Secret do Secrets Manager đồng bộ.
