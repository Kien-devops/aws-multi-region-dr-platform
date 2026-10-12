# LAB 26 - Unified Database và Storage DR Test

## 1. Mục tiêu

Đo độc lập transaction RPO, storage RPO, database/application/storage/end-to-end RTO và file integrity trong cùng timeline.

## 2. Thành phần sẽ xây dựng

- `scripts/dr/unified-writer.sh`, `scripts/dr/capture-pre-failure-state.sh`, `scripts/dr/unified-rpo-check.sh`, `scripts/dr/test-unified-rpo.sh`.
- `scripts/storage-dr/integrity-check.sh`.
- Evidence CSV và report template; không chứa secret.

## 3. Bối cảnh kiến trúc

```text
DR-dr-20261012T100000Z-SEQ-000001 -> backend-3 -> Aurora
                                    -> file-service -> FSx ONTAP
```

Hai POST cùng sequence không phải distributed transaction. Một path thành công và path kia lỗi phải được log riêng.

## 4. Điều kiện tiên quyết

- Application APIs deployed and authorized; LAB 17 database method understood; LAB 21-22 storage healthy.
- Approved planned/unplanned scenario, recovery owner, synchronized UTC clocks.
- Known-file checksum captured before failure.

## 5. Quy ước đặt tên tài nguyên

Mỗi lần chạy có `RUN_ID` riêng, mặc định dạng `dr-YYYYMMDDTHHMMSSZ`. Marker là `DR-<RUN_ID>-SEQ-%06d`; storage lưu dưới `events/<RUN_ID>/`. Log CSV dùng `timestamp,sequence,db_status,storage_status`; evidence directory nằm ngoài Git hoặc đã sanitize.

## 6. Các bước triển khai

### Bước 1: Thu thập Endpoints từ AWS Console và Chuẩn bị Tham số Kiểm thử

1. **Lấy địa chỉ Application Global Accelerator:**
   - Mở **AWS Global Accelerator Console** tại [https://console.aws.amazon.com/globalaccelerator/](https://console.aws.amazon.com/globalaccelerator/).
   - Nhấp vào **`dr-platform-accelerator`** (hoặc DNS ALB Singapore `dr-sg-alb`).
   - Sao chép **DNS name** hoặc một trong hai **Static IP addresses** (ví dụ: `http://a1b2c3d4e5f6.awsglobalaccelerator.com`).
2. **Lấy địa chỉ Storage Global Accelerator:**
   - Trong bảng Accelerators, nhấp vào **`dr-storage-accelerator`**.
   - Sao chép **DNS name** hoặc **Static IP address** (ví dụ: `http://f6e5d4c3b2a1.awsglobalaccelerator.com`).
3. Khởi tạo phiên làm việc với các biến môi trường:

```bash
export APP_ENDPOINT="<APPLICATION_GA_DNS_HOAC_IP>"
export FILE_ENDPOINT="<STORAGE_GA_DNS_HOAC_IP>"
export RUN_ID="dr-$(date -u +%Y%m%dT%H%M%SZ)"
export INTERVAL_SECONDS=1
```

---

### Bước 2: Tạo File Mẫu và Ghi nhận Checksum Toàn vẹn Ban đầu

1. Chạy kịch bản chuẩn bị file kiểm tra toàn vẹn dữ liệu (tải file mẫu lên storage và lưu SHA-256):

```bash
FILE_URL="http://${FILE_ENDPOINT}" bash ./scripts/storage-dr/integrity-check.sh prepare
```

*Kết quả mong đợi:* Sinh ra file mẫu (ví dụ 1 MiB) với checksum SHA-256 được lưu vào file `original-file.sha256`.

---

### Bước 3: Khởi động Unified Writer Ghi Dữ liệu Đồng thời

1. Bắt đầu luồng ghi liên tục vào cả Cơ sở dữ liệu và Storage với nhãn sequence đồng nhất:

```bash
DB_URL="http://${APP_ENDPOINT}/api/v1/orders" \
STORAGE_URL="http://${FILE_ENDPOINT}/api/v1/storage/events" \
RUN_ID="${RUN_ID}" \
INTERVAL_SECONDS=1 \
bash ./scripts/dr/unified-writer.sh
```

- Writer script sẽ gửi tuần tự các bản ghi với `RUN_ID` và `SEQ-%06d` vào cả hai dịch vụ.
- Theo dõi log thấy output tăng dần: `ACK DB SEQ-000010 | ACK Storage SEQ-000010`.

---

### Bước 4: Khai báo Sự cố ($T_0$), Chụp Bất biến Pre-Failure State và Cô lập Singapore

1. **Ghi nhận mốc thời gian $T_0$:**
   - Ngay khi Incident Commander quyết định diễn tập DR, ghi lại chính xác thời gian UTC hiện tại ($T_0$).

2. **Chụp trạng thái bất biến trước sự cố:**
   - Trên một cửa sổ terminal riêng, chạy ngay lệnh chụp snapshot:

```bash
bash ./scripts/dr/capture-pre-failure-state.sh unified-writer.state pre-failure.state
cat pre-failure.state
```

> [!IMPORTANT]
> File `pre-failure.state` lưu giữ số sequence ACK cuối cùng của DB và Storage tại thời điểm $T_0$. Script bảo vệ tuyệt đối không cho phép ghi đè file này.

3. **Cô lập lưu lượng Ingress Singapore trên AWS Global Accelerator Console:**
   - Mở **AWS Global Accelerator Console**.
   - Vào `dr-platform-accelerator` -> Listeners -> Port 80 -> nhóm `ap-southeast-1`:
     - Nhấp **Edit** -> Chỉnh **Traffic dial** từ `100` về **`0`** -> **Save changes**.
   - Vào `dr-storage-accelerator` -> Listeners -> Port 80 -> nhóm `ap-southeast-1`:
     - Nhấp **Edit** -> Chỉnh **Traffic dial** từ `100` về **`0`** -> **Save changes**.

---

### Bước 5: Thực hiện Kích hoạt Failover Song song (Database & Storage)

1. **Thăng cấp Aurora Global Database sang Tokyo (RDS Console):**
   - Mở **Amazon RDS Console** tại [https://console.aws.amazon.com/rds/](https://console.aws.amazon.com/rds/).
   - Tại menu trái, chọn **Databases**.
   - Nhấp chọn cluster đầu mục **`dr-global-db`**.
   - Nhấp menu **Actions** ở góc trên bên phải:
     - Với kịch bản Planned: Chọn **Switch over global database** -> Chọn Tokyo cluster (`dr-tokyo-aurora-cluster`) -> Bấm **Switch over**.
     - Với kịch bản Unplanned: Chọn **Fail over global database** -> Chọn `dr-tokyo-aurora-cluster` -> Tích ô xác nhận data loss -> Bấm **Fail over**.
   - Theo dõi cho đến khi Tokyo cluster chuyển thành **Available (Writer)**.
   - **Ghi nhận thời điểm $T_1$:** Aurora Tokyo writer sẵn sàng.
   - Kiểm tra EKS Tokyo application pods kết nối thành công: **Ghi nhận thời điểm $T_2$**.

2. **Thăng cấp FSx ONTAP Volume sang Tokyo (SSM / ONTAP CLI):**
   - Kết nối SSM vào **`dr-tokyo-storage-ec2`**, SSH vào ONTAP CLI Tokyo:
     ```text
     snapmirror break -destination-path dr-tokyo-svm:dr-data-dr
     ```
   - Kiểm tra và mount junction-path nếu cần:
     ```text
     volume mount -vserver dr-tokyo-svm -volume dr-data-dr -junction-path /dr-data -active true
     ```
   - **Ghi nhận thời điểm $T_3$:** Tokyo ONTAP volume chuyển sang RW online.
   - Trên EC2 Tokyo: mount NFS `/mnt/dr-data` (1000:1000, 0770) và chạy container `file-service`.
   - Kiểm tra target group Tokyo trên EC2 Console (`dr-tokyo-storage-tg`) chuyển sang **Healthy**.
   - Gửi test write nội bộ: **Ghi nhận thời điểm $T_4$**.

3. **Ghi nhận thời điểm $T_5$:** Cả Database và File Storage tại Tokyo đều đã sẵn sàng phục vụ.

---

### Bước 6: Chuyển hướng Toàn bộ Lưu lượng sang Tokyo trên AWS Global Accelerator

1. Mở lại **AWS Global Accelerator Console**.
2. Với `dr-platform-accelerator`:
   - Listeners -> Port 80 -> nhóm endpoint Tokyo (`ap-northeast-1`):
   - Nhấp **Edit** -> Nâng **Traffic dial** từ `0` lên **`100`** -> **Save changes**.
3. Với `dr-storage-accelerator`:
   - Listeners -> Port 80 -> nhóm endpoint Tokyo (`ap-northeast-1`):
   - Nhấp **Edit** -> Nâng **Traffic dial** từ `0` lên **`100`** -> **Save changes**.
4. Chờ cả hai Accelerator hiển thị trạng thái **Deployed**.

---

### Bước 7: Kiểm tra và Đo lường Khoảng cách RPO (Unified RPO Check)

1. Thực thi kịch bản kiểm tra RPO độc lập cho cả DB và Storage so với bản snapshot `pre-failure.state`:

```bash
DB_LATEST_URL="http://${APP_ENDPOINT}/api/v1/orders/latest" \
STORAGE_LATEST_URL="http://${FILE_ENDPOINT}/api/v1/storage/events/latest" \
bash ./scripts/dr/unified-rpo-check.sh pre-failure.state
```

- Kịch bản sẽ truy vấn các endpoint latest, lấy sequence lớn nhất được ghi nhận tại Tokyo nhỏ hơn hoặc bằng sequence trước sự cố.
- Tính toán chính xác:
  $$\text{Database lost records} = \text{Last DB ACK} - \text{Latest DB Recovered}$$
  $$\text{Storage lost records} = \text{Last Storage ACK} - \text{Latest Storage Recovered}$$

---

### Bước 8: Xác minh Tính toàn vẹn File (Integrity Check)

1. Tải về file mẫu từ Tokyo file service và so sánh mã băm SHA-256:

```bash
FILE_URL="http://${FILE_ENDPOINT}" bash ./scripts/storage-dr/integrity-check.sh verify
```

*Kết quả mong đợi:* `INTEGRITY CHECK: PASS` (Mã SHA-256 của file tải về từ Tokyo trùng khớp tuyệt đối với file gốc được tạo tại Singapore trước sự cố).

---

### Bước 9: Tổng hợp Báo cáo Nghiệm thu RTO / RPO Thống nhất

1. Điền các giá trị đo đạc thực tế vào bảng tổng kết kết quả:

$$\text{Database RTO} = T_1 - T_0$$
$$\text{Application RTO} = T_2 - T_0$$
$$\text{Storage RTO} = T_4 - T_0$$
$$\text{End-to-End RTO} = T_5 - T_0$$

## 7. Xác minh

CSV remains parseable during timeout/failure; `pre-failure.state` không đổi sau T0; latest endpoints trả đúng `RUN_ID`; recovered sequences là số; integrity so sánh actual downloaded bytes.

Local script self-check không cần AWS:

```bash
bash ./scripts/dr/test-unified-rpo.sh
```

Kỳ vọng `Unified RPO script tests: PASS`; test chứng minh snapshot không bị overwrite, mỗi path dùng đúng ACK cutoff, post-recovery writes không che dữ liệu mất và response vượt cutoff làm checker fail.

## 8. Kết quả mong đợi

Measured fields contain observed timestamps/gaps only after live execution. Otherwise write `NOT MEASURED`.

## 9. Xử lý sự cố

- Endpoint returns non-2xx: preserve status, do not advance that path's acknowledged marker.
- `pre-failure.state` đã tồn tại: không overwrite; tạo evidence directory/run mới hoặc xác minh đây đúng snapshot cần giữ.
- Latest response thiếu/sai `RUN_ID`: stop và sửa endpoint/URL; không fallback về global latest.
- Latest response schema differs: stop and update parser; do not guess values.
- Clock skew: use request log ordering/sequence and fix NTP before time claims.

## 10. Lưu ý bảo mật

Use short-lived tokens via environment/approved secret store; scripts must not echo auth headers. Test files contain no sensitive data.

## 11. Lưu ý chi phí

Writer traffic, ALB, logs, Aurora I/O, FSx capacity/transfer and snapshots can incur cost. Bound test duration.

## 12. Dọn dẹp / Quay lui

Stop writer, retain sanitized evidence, delete test data only after owner approval, restore normal topology via LAB 16 and LAB 25.

## 13. Bằng chứng cần thu thập

Writer CSV/live state, immutable `pre-failure.state`, `RUN_ID`, T0-T5, relationship/DB states, per-run latest markers, RPO calculation, original/recovered SHA-256, integrity outcome.

Report template:

| Metric | Target | Measured Result | Evidence |
|---|---:|---:|---|
| Database RPO | `< 30s` | `NOT MEASURED` | `<path>` |
| Storage RPO | `< 5m` | `NOT MEASURED` | `<path>` |
| Database RTO | `< 5m` | `NOT MEASURED` | `<path>` |
| Storage RTO | `< 15m` | `NOT MEASURED` | `<path>` |
| End-to-End RTO | `< 15m` | `NOT MEASURED` | `<path>` |
| File integrity | `PASS` | `NOT MEASURED` | `<path>` |

## 14. Lab tiếp theo

[LAB 27 - Cleanup](27-cleanup.md).
