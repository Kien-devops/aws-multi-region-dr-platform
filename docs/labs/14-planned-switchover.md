# LAB 14 - Diễn Tập Chuyển Đổi Vùng Có Kế Hoạch (Planned Switchover)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Thực hiện quy trình chuyển đổi vùng sản xuất có kế hoạch (Planned Switchover) từ Singapore (`ap-southeast-1`) sang Tokyo (`ap-northeast-1`) mà **hoàn toàn không làm mất mát dữ liệu (RPO = 0)**.
2. Ghi nhận chính xác chuỗi mốc thời gian $T_0, T_1, T_2, T_3, T_4, T_5$.
3. Sử dụng tính năng **Switch over global database** của Amazon Aurora để đồng bộ toàn bộ transaction buffer trước khi hoán đổi vai trò Primary và Secondary.
4. Điều chỉnh lưu lượng mạng trên AWS Global Accelerator và xác thực toàn diện ứng dụng `app2` trên vùng Tokyo thông qua các endpoint thực tế: `GET /health`, `GET /api/v1/catalog`, và `POST /api/v1/orders`.

---

## Architecture impact

```text
TRƯỚC KHI SWITCHOVER:
  Singapore: Primary Writer (100% Traffic)  ===[Replication]===>  Tokyo: Secondary Read-Only (Standby)

TRONG KHI SWITCHOVER (T0 -> T3):
  1. Flush sạch transaction buffer tại Singapore
  2. Thăng cấp Tokyo thành Primary Writer
  3. Hạ cấp Singapore thành Secondary Read-Only

SAU KHI SWITCHOVER (T3 -> T5):
  Singapore: Secondary Read-Only (Standby)  <===[Replication]===  Tokyo: Primary Writer (100% Traffic)
```

---

## Resource naming

- Aurora Global Database: `app2-global-db`
- Current Primary: `app2-sg-db` (Singapore)
- New Primary Target: `app2-tokyo-db` (Tokyo)
- Unique Test Record ID: `DR_PLANNED_TEST_<TIMESTAMP>`

---

## Bảng Theo Dõi Thời Gian Thực Nghiệm (Time Log Sheet)

| Mốc | Mô tả sự kiện | Timestamp (UTC / GMT+7) | Trạng thái đạt được |
|---|---|---|---|
| **$T_0$** | Bắt đầu kích hoạt lệnh Planned Switchover | `__:__:__` | Bắt đầu thao tác trên Console |
| **$T_1$** | AWS tạm dừng nhận lệnh ghi tại Singapore | `__:__:__` | Singapore chuyển sang chế độ chuẩn bị đổi vai trò |
| **$T_2$** | Điều chỉnh Traffic Dial trên Global Accelerator | `__:__:__` | Lưu lượng người dùng chuyển sang Tokyo |
| **$T_3$** | Cụm Aurora Tokyo hoàn tất thăng cấp thành Writer | `__:__:__` | Tokyo hiển thị `Regional primary` |
| **$T_4$** | Request đọc dữ liệu đầu tiên thành công tại Tokyo | `__:__:__` | `GET /api/v1/catalog` trả về HTTP 200 |
| **$T_5$** | Transaction ghi dữ liệu đầu tiên thành công tại Tokyo | `__:__:__` | `POST /api/v1/orders` ghi thành công |
| **RTO** | **$T_5 - T_0$** | **... phút ... giây** | Mục tiêu: < 5 phút |
| **RPO** | Kiểm tra bản ghi commit lúc $T_0$ | **0 giây (Zero Data Loss)** | Mục tiêu: < 30 giây |

---

## AWS Console Steps

### Bước 1: Ghi Bản Ghi Kiểm Thử Trước Khi Chuyển Vùng ($T_0$)
1. Trước khi bấm nút chuyển đổi, gửi một transaction ghi dữ liệu vào hệ thống tại Singapore:
   ```bash
   TEST_ID="DR_PLANNED_$(date +%Y%m%d_%H%M%S)"
   curl -X POST http://<GLOBAL_ACCELERATOR_IP>/api/v1/orders \
     -H "Content-Type: application/json" \
     -d "{\"item_id\":\"item-gold\",\"quantity\":1,\"test_marker\":\"$TEST_ID\"}"
   ```
2. Xác nhận transaction thành công và ghi nhận thời điểm bắt đầu $T_0$.

### Bước 2: Thực Hiện Aurora Switchover Trên Console
1. Mở AWS Console -> Dịch vụ **RDS** tại Region **Asia Pacific (Singapore) ap-southeast-1**.
2. Chọn mục **Databases** ở thanh điều hướng bên trái.
3. Chọn cụm Global Database `app2-global-db`.
4. Nhấn menu **Actions** ở góc trên bên phải -> Chọn **Switch over global database**.
5. **Tại màn hình Switch over global database:**
   - **New primary cluster:** Chọn cụm `app2-tokyo-db (ap-northeast-1)`.
6. Nhấn nút màu cam **Switch over global database**.
7. AWS Aurora sẽ tiến hành:
   - Dừng các kết nối ghi mới tại Singapore.
   - Chờ các transaction đang xử lý đồng bộ sang Tokyo.
   - Thăng cấp cụm Tokyo thành Primary và biến Singapore thành Secondary.
8. Quan sát trạng thái trên Console. Khi cụm Tokyo hiển thị `Available` với vai trò `Primary`, ghi nhận mốc **$T_3$**.

### Bước 3: Điều Chuyển Lưu Lượng Mạng Bằng Global Accelerator
1. Mở dịch vụ **AWS Global Accelerator** Console.
2. Chọn accelerator `app2-global` -> Chuyển sang tab **Listeners** -> Chọn Port 80.
3. Chỉnh sửa Endpoint Groups:
   - Endpoint Group Singapore: Đặt **Traffic dial** = `0%`.
   - Endpoint Group Tokyo: Đặt **Traffic dial** = `100%`.
4. Nhấn **Save changes**. Ghi nhận mốc **$T_2$**.

### Bước 4: Scale Workload tại Tokyo (Nếu Cần)
1. Tăng số lượng Pods tại Tokyo lên mức sản xuất:
   ```bash
   kubectl --context tokyo scale deployment -n app2 --replicas=2 --all
   ```

---

## Verification & Kiểm Tra Tính Toàn Vẹn

### Kiểm tra Đọc ($T_4$) và Xác Minh Dữ Liệu Cũ Vẫn Còn Nguyên Vẹn
1. Gửi request đọc sản phẩm qua Global Accelerator:
   ```bash
   curl -i http://<GLOBAL_ACCELERATOR_IP>/api/v1/catalog
   ```
   *Xác nhận:* HTTP 200 OK. Ghi nhận mốc **$T_4$**.
2. Truy vấn tìm lại bản ghi `TEST_ID` đã tạo ở Bước 1:
   ```bash
   curl -s http://<GLOBAL_ACCELERATOR_IP>/api/v1/orders | grep "$TEST_ID"
   ```
   *Kết quả:* Bản ghi xuất hiện nguyên vẹn $\rightarrow$ **Xác nhận RPO = 0 (Hoàn toàn không mất dữ liệu)**.

### Kiểm tra Ghi Mới Vào Vùng Tokyo ($T_5$)
1. Gửi một transaction đơn hàng mới:
   ```bash
   curl -X POST http://<GLOBAL_ACCELERATOR_IP>/api/v1/orders \
     -H "Content-Type: application/json" \
     -d "{\"item_id\":\"item-silver\",\"quantity\":2,\"test_marker\":\"TOKYO_WRITE_VERIFIED\"}"
   ```
   *Xác nhận:* Giao dịch trả về HTTP 200 OK hoặc HTTP 201 Created.
2. Ghi nhận thời điểm hoàn tất **$T_5$**.
3. Tính toán RTO thực tế: $RTO = T_5 - T_0$.

---

## Troubleshooting

1. **Lỗi: Nút `Switch over` bị mờ (disabled) trên Console:**
   - *Nguyên nhân:* Cụm Secondary tại Tokyo chưa ở trạng thái `Available` hoặc replication lag hiện tại đang quá cao.
   - *Cách sửa:* Đợi 1-2 phút cho cụm Tokyo ổn định, kiểm tra metric replication lag dưới 10 giây.
2. **Lỗi: Backend-3 pods tại Tokyo báo lỗi `read-only transaction` sau khi switchover:**
   - *Nguyên nhân:* Connection pool của backend-3 vẫn đang giữ connection cũ trỏ tới trạng thái read-only trước đó.
   - *Cách sửa:* Thực hiện restart rolling deployment backend-3:
     ```bash
     kubectl --context tokyo rollout restart deployment -n app2 app2-backend-3
     ```
3. **Lỗi: Client vẫn kết nối tới Singapore sau khi chỉnh Traffic Dial:**
   - *Nguyên nhân:* Client sử dụng kết nối HTTP Keep-Alive mở sẵn (persistent TCP connection).
   - *Cách sửa:* Đóng kết nối cũ hoặc test bằng lệnh `curl` mới.

---

## Cost note

- Thao tác Switchover không tạo thêm tài nguyên mới nên **không phát sinh thêm chi phí AWS**.

---

## Next step

Tiếp tục chuyển sang [LAB 15 - Mô Phỏng Sự Cố và Unplanned Failover](15-unplanned-failover.md).
