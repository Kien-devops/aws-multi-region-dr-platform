# LAB 15 - Mô Phỏng Sự Cố Vùng và Unplanned Failover (Unplanned Failover)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Thực hiện kịch bản **Mô phỏng sự cố có kiểm soát (Controlled Simulation)** làm tê liệt vùng chính Singapore mà **không phá hủy hạ tầng thật của tài khoản AWS**.
2. Quan sát cơ chế phát hiện lỗi và chuyển hướng lưu lượng sang Tokyo của AWS Global Accelerator.
3. Kích hoạt quy trình cứu hộ khẩn cấp (**Unplanned Failover**) và thăng cấp cụm cơ sở dữ liệu Tokyo thành Primary Writer.
4. Nắm vững cơ chế phòng chống **Split-Brain (Lỗi hai Writer đồng thời)**.
5. Ghi nhận chính xác 6 mốc thời gian $T_0, T_1, T_2, T_3, T_4, T_5$, hiểu rõ chuỗi phụ thuộc (Dependency Sequence) và đo lường RTO/RPO thực tế.

---

## Chuỗi Phụ Thuộc Trong Cứu Hộ Khẩn Cấp (Dependency Sequence)

Trong một sự cố sập vùng thực tế, có một khoảng thời gian trễ giữa việc **chuyển hướng mạng** và **thăng cấp cơ sở dữ liệu**:
1. **$T_2$ (Traffic Reaches Tokyo):** Global Accelerator phát hiện Singapore Unhealthy và đẩy người dùng sang Tokyo ALB. Lúc này, người dùng gọi `GET /health` hoặc `GET /api/v1/info` sẽ thành công.
2. **Nhưng giao dịch Ghi vẫn thất bại:** Vì Aurora Tokyo lúc này vẫn đang là Read-Only Secondary, các request `POST /api/v1/orders` sẽ bị từ chối cho đến khi quá trình thăng cấp database hoàn tất.
3. **$T_3$ (DB Promoted):** Cụm Aurora Tokyo được thăng cấp thành Writer.
4. **$T_4$ (First Read Success):** `GET /api/v1/catalog` thành công.
5. **$T_5$ (First Write Success):** `POST /api/v1/orders` thành công ghi dữ liệu mới.
6. **Công thức RTO chuẩn xác:** $RTO = T_5 - T_0$ (thời điểm hệ thống sẵn sàng tiếp nhận lại đầy đủ các giao dịch ghi của khách hàng).

---

## Phòng Chống Lỗi Split-Brain (Prevent Split-Brain)

> [!CAUTION]
> **Quy tắc vàng chống Split-Brain:**
> - Tuyệt đối không để hai vùng cùng nhận lệnh ghi (dual writable primaries).
> - Trước khi thăng cấp cụm Tokyo trong kịch bản diễn tập, cô lập cụm Singapore bằng cách thu hồi quyền kết nối (xóa Inbound rules của Security Group Singapore DB hoặc scale deployment SG về 0).
> - Trong sự cố thật, khi Singapore có mạng trở lại, cụm Singapore cũ **phải được giữ ở trạng thái cô lập** cho đến khi thực hiện quy trình Failback chính thức tại Lab 16.

---

## Bảng Nhật Ký Sự Cố Khẩn Cấp (Emergency Incident Log)

| Mốc | Tên sự kiện | Thời gian thực tế | Phương pháp xác nhận |
|---|---|---|---|
| **$T_0$** | **Failure Injected** | `__:__:__` | Kích hoạt script mô phỏng làm sập dịch vụ tại Singapore |
| **$T_1$** | **Health Failure Detected** | `__:__:__` | Global Accelerator nhận diện Singapore ALB `UNHEALTHY` |
| **$T_2$** | **Traffic Reaches Tokyo** | `__:__:__` | `GET /health` bắt đầu trả về `region: ap-northeast-1` |
| **$T_3$** | **DB Promoted** | `__:__:__` | Cụm Aurora Tokyo hoàn tất thăng cấp thành Primary Writer |
| **$T_4$** | **First Successful Read** | `__:__:__` | `GET /api/v1/catalog` trả về HTTP 200 |
| **$T_5$** | **First Successful Write**| `__:__:__` | `POST /api/v1/orders` ghi transaction mới thành công |
| **RTO** | **$T_5 - T_0$** | **... phút ... giây** | **Mục tiêu: < 5 phút** |
| **RPO** | Chênh lệch bản ghi trước $T_0$ | **... giây** | **Mục tiêu: < 30 giây** |

---

## Quy Trình Thực Hiện Diễn Tập Từng Bước

### Bước 1: Khởi Động RPO Continuous Writer
Trên máy trạm, mở một cửa sổ terminal riêng và chạy script tạo luồng ghi liên tục (đã tạo tại thư mục `scripts/dr/`):
```bash
./scripts/dr/rpo-writer.sh http://<GLOBAL_ACCELERATOR_IP>/api/v1/orders
```
Script sẽ gửi transaction đơn hàng mỗi 1 giây và ghi vết các mã `SEQ-000001, SEQ-000002...` vào file `rpo-last-committed.json`.

### Bước 2: Bắn Lỗi Mô Phỏng Sự Cố Vùng Singapore ($T_0$)
Làm sập toàn bộ dịch vụ ứng dụng trên cụm Singapore bằng cách hạ số lượng Pod về 0:
```bash
echo "T0 (Failure Injected): $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
kubectl --context singapore -n app2 scale deployment --all --replicas=0
```

### Bước 3: Quan Sát Global Accelerator Nhận Diện Lỗi ($T_1$) và Đổi Hướng ($T_2$)
1. Sau 20 - 30 giây, Target Group của Singapore ALB rơi vào tình trạng 0 healthy hosts.
2. Global Accelerator chuyển trạng thái Endpoint Group Singapore thành **Unhealthy** ($T_1$).
3. Nếu sử dụng Option B, Global Accelerator tự động chuyển traffic sang Tokyo. Nếu sử dụng Option A, chạy lệnh bật Traffic Dial của Tokyo lên 100%:
   ```bash
   while true; do
     RESP=$(curl -s --connect-timeout 2 http://<GLOBAL_ACCELERATOR_IP>/health || true)
     echo "$(date +%T): $RESP"
     if [[ "$RESP" == *"ap-northeast-1"* ]]; then
       echo "TRAFFIC ĐÃ CHUYỂN SANG TOKYO (T2)!"
       break
     fi
     sleep 2
   done
   ```
4. Ghi nhận thời điểm **$T_2$**.

### Bước 4: Thăng Cấp Khẩn Cấp Cơ Sở Dữ Liệu Tokyo ($T_3$)
1. Mở AWS Console -> Dịch vụ **RDS** -> Region **Asia Pacific (Tokyo) ap-northeast-1**.
2. Chọn cụm database `app2-tokyo-db`.
3. Nhấn menu **Actions** -> Chọn **Failover global database** (hoặc *Remove from global database*).
4. Xác nhận thăng cấp ngay lập tức.
5. Cập nhật secret hoặc kết nối để backend-3 trỏ tới Tokyo Writer nếu cần.
6. Khi cụm Tokyo hiển thị trạng thái `Available` với vai trò Writer, ghi nhận mốc **$T_3$**.

### Bước 5: Mở Rộng Năng Lực Ứng Dụng tại Tokyo
Scale các deployments tại Tokyo lên 2 replicas để chịu tải sản xuất:
```bash
kubectl --context tokyo -n app2 scale deployment --all --replicas=2
```

### Bước 6: Xác Thực Đọc ($T_4$) và Ghi ($T_5$) Nghiệp Vụ
1. **Xác thực Đọc ($T_4$):**
   ```bash
   curl -i http://<GLOBAL_ACCELERATOR_IP>/api/v1/catalog
   ```
   *Xác nhận:* HTTP 200 OK từ Tokyo Pod. Ghi nhận mốc **$T_4$**.
2. **Xác thực Ghi ($T_5$):**
   Gửi đơn hàng kiểm thử vào hệ thống:
   ```bash
   curl -X POST http://<GLOBAL_ACCELERATOR_IP>/api/v1/orders \
     -H "Content-Type: application/json" \
     -d '{"item_id":"item-post-failover","quantity":1,"marker":"FIRST_WRITE_POST_OUTAGE"}'
   ```
   *Xác nhận:* HTTP 200 OK. Ghi nhận thời điểm **$T_5$**.

### Bước 7: Dừng RPO Writer và Chạy Script Kiểm Tra RPO
1. Nhấn `Ctrl+C` tại terminal chạy `rpo-writer.sh`.
2. Chạy script kiểm tra RPO:
   ```bash
   ./scripts/dr/rpo-check.sh http://<GLOBAL_ACCELERATOR_IP>/api/v1/orders
   ```
3. Script sẽ in ra độ chênh lệch số lượng bản ghi và RPO đo được tính bằng giây.

---

## Troubleshooting

1. **Lỗi: Request ghi bị từ chối với lỗi Read-Only tại Tokyo:**
   - *Nguyên nhân:* Gửi request ghi trước khi bước $T_3$ (DB Promotion) hoàn tất, hoặc connection pool của backend-3 chưa nhận diện endpoint writer mới.
   - *Cách sửa:* Chờ cụm Tokyo chuyển trạng thái `Available` và chạy `kubectl --context tokyo -n app2 rollout restart deployment/app2-backend-3`.
2. **Lỗi: `GET /health` trả về lỗi kết nối:**
   - *Nguyên nhân:* Pods tại Tokyo chưa hoàn tất việc kéo image từ ECR Tokyo.
   - *Cách sửa:* Kiểm tra trạng thái pods bằng `kubectl --context tokyo -n app2 get pods`.
3. **Lỗi: Mất mát dữ liệu vượt quá 30 giây:**
   - *Nguyên nhân:* Replication lag tại thời điểm xảy ra sự cố quá cao.
   - *Cách sửa:* Xem lại biểu đồ CloudWatch `AuroraGlobalDBReplicationLag`.

---

## Cost note

- Việc scale Pods và thăng cấp DB không làm phát sinh thêm chi phí mới ngoài phí vận hành định kỳ của các tài nguyên sẵn có.

---

## Next step

Tiếp tục chuyển sang [LAB 16 - Quy Trình Khôi Phục Ngược Về Singapore (Failback)](16-failback.md).
