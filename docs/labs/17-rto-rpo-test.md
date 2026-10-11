# LAB 17 - Đánh Giá & Đo Đạc Chỉ Số RTO/RPO Tổng Thể (RTO/RPO Measurement)

## 1. Overview & Objective

Trong kiến trúc Disaster Recovery hiện đại, mọi tuyên bố về độ sẵn sàng cao đều vô nghĩa nếu không có số liệu đo đạc thực nghiệm. Không thể khẳng định "Hệ thống đạt RTO < 5 phút và RPO < 30 giây" nếu chưa từng chạy kịch bản ghi tải liên tục và đo chính xác từng mili-giây trong thời gian xảy ra sự cố.

Mục tiêu chính:
1. Nắm vững phương pháp luận kiểm thử phục hồi sau thảm họa (Disaster Recovery Validation Methodology) theo tiêu chuẩn SRE và ISO/IEC 27031.
2. Thực hiện kịch bản kiểm thử đo đạc liên tục (Continuous Writer Sequence) sử dụng hai script tự động hóa:
   - [`scripts/dr/rpo-writer.sh`](../../scripts/dr/rpo-writer.sh): Ghi tải tuần tự (`SEQ-000001`, `SEQ-000002`...) mỗi 1 giây và ghi nhận timestamp của transaction cuối cùng được commit thành công tại Singapore trước khi ngắt kết nối.
   - [`scripts/dr/rpo-check.sh`](../../scripts/dr/rpo-check.sh): Truy vấn marker lớn nhất hiện diện tại Tokyo sau khi thăng cấp và tính toán chính xác RPO thực tế.
3. Phân tích chuỗi phụ thuộc phục hồi (Dependency Chain): Hiểu rõ lý do vì sao khi traffic chuyển sang Tokyo trước khi DB được thăng cấp, các request đọc (`GET /health`, `GET /api/v1/catalog`) thành công ($T_4$) nhưng request ghi (`POST /api/v1/orders`) sẽ thất bại cho đến khi DB hoàn tất thăng cấp ($T_3$).
4. Xác định chính xác chỉ số RTO thực tế bằng mốc hoàn tất giao dịch ghi đầu tiên: $\text{RTO} = T_5 - T_0$.
5. Hoàn thiện Bảng Báo Cáo Diễn Tập DR Chính Thức (Official DR Test Evidence Report).

---

## 2. Architecture Diagram & Measurement Timeline

```text
       [ T0: BẮN LỖI SỰ CỐ TẠI SINGAPORE ]
                      |
                      v
[ 1. Traffic Layer: Global Accelerator ] ---> [ T1: Phát hiện Unhealthy ] ---> [ T2: Gói tin chạm Tokyo ALB ]
                      |
                      v
[ 2. Database Layer: Aurora Global ]     ---> [ T3: Hoàn tất thăng cấp Tokyo thành Primary Writer ]
                      |
                      v
[ 3. Application Layer: Tokyo Workloads ]---> [ T4: Đọc thành công ] ---------> [ T5: Ghi thành công ]
                                              (GET /api/v1/catalog)            (POST /api/v1/orders)

===> RTO THỰC TẾ = T5 - T0 (Thời gian từ khi sập nguồn tới khi giao dịch ghi đầu tiên hoàn tất)
===> RPO THỰC TẾ = Timestamp(Marker cuối tại SG) - Timestamp(Marker lớn nhất tại Tokyo)
```

---

## 3. Prerequisites & Pre-flight Checklist

- [ ] Script kiểm thử đã được cấp quyền thực thi trên máy trạm:
  - `chmod +x scripts/dr/rpo-writer.sh scripts/dr/rpo-check.sh`
- [ ] AWS Global Accelerator đang trỏ tới Singapore ALB (Traffic dial: Singapore 100%, Tokyo 0% hoặc Warm Standby).
- [ ] Công cụ `curl`, `jq`, `bc` đã được cài đặt sẵn trên máy trạm.
- [ ] Đường truyền mạng ổn định giữa máy trạm và các điểm kết nối AWS.
- [ ] Không có công việc bảo trì khác đang chạy trên hai vùng AWS.

---

## 4. Step-by-Step Implementation (Console-first + CLI)

### Bước 1: Khởi Động Bộ Ghi Tải Tuần Tự (Continuous RPO Writer)
Trước khi ngắt kết nối vùng Singapore, khởi động script ghi đơn hàng liên tục vào endpoint của Global Accelerator:

```bash
./scripts/dr/rpo-writer.sh "http://<GLOBAL_ACCELERATOR_IP>"
```

*Cơ chế hoạt động của script:*
- Mỗi giây gửi một request `POST /api/v1/orders` chứa payload:
  ```json
  {"item_id": "rpo-item", "quantity": 1, "marker": "SEQ-000001", "created_at": "..."}
  ```
- Ghi nhận trạng thái HTTP phản hồi và lưu file nhật ký `dr_rpo_writer.log`.
- In ra màn hình console:
  ```text
  [14:00:00.700] SUCCESS: Committed SEQ-001250 | HTTP 201 | Latency: 0.045s
  ```

### Bước 2: Kích Hoạt Sự Cố Vùng Singapore ($T_0$)
1. Ghi lại chính xác thời điểm bấm nút: $T_0 = \text{HH:MM:SS.mmm}$.
2. Giả lập lỗi sập toàn bộ dịch vụ backend tại Singapore bằng cách scale toàn bộ Pods về 0:
   ```bash
   kubectl --context singapore -n app2 scale deployment --all --replicas=0
   ```
3. Script `rpo-writer.sh` sẽ bắt đầu báo lỗi kết nối hoặc HTTP 502/503. Script tự động ghi nhận **Marker cuối cùng được commit thành công trước $T_0$** (Ví dụ: `SEQ-001250 @ 14:00:00.700`).

### Bước 3: Theo Dõi Chuyển Hướng Mạng ($T_1 \rightarrow T_2$)
1. **$T_1$ (Phát hiện sự cố):** Global Accelerator phát hiện ALB Singapore Unhealthy sau 3 consecutive health check probes thất bại trên `/health`.
2. **$T_2$ (Traffic tới Tokyo):** Bật Traffic Dial của Tokyo lên 100% (nếu dùng Option A) hoặc Global Accelerator tự chuyển traffic (nếu dùng Option B).
3. Kiểm tra phản hồi từ Tokyo bằng lệnh curl:
   ```bash
   curl -s http://<GLOBAL_ACCELERATOR_IP>/health | jq .
   ```
   *Khi body trả về `"region": "ap-northeast-1"` $\rightarrow$ Ghi nhận mốc $T_2$.*

### Bước 4: Thăng Cấp Cơ Sở Dữ Liệu Tokyo ($T_3$)
1. Mở RDS Console tại region Tokyo (`ap-northeast-1`).
2. Chọn cụm `app2-tokyo-db` -> **Actions** -> Chọn **Failover global database** (hoặc Switch over).
3. Xác nhận lệnh thăng cấp.
4. Chờ cho tới khi vai trò của cụm Tokyo chuyển thành `Regional primary` và trạng thái là `Available`.
5. Ghi nhận mốc $T_3$.

### Bước 5: Kiểm Tra Đọc Thành Công ($T_4$) và Ghi Thành Công ($T_5$)
1. **Kiểm tra Đọc ($T_4$):**
   ```bash
   curl -s http://<GLOBAL_ACCELERATOR_IP>/api/v1/catalog | jq .
   ```
   *Xác nhận HTTP 200 OK $\rightarrow$ Ghi nhận mốc $T_4$.*
2. **Kiểm tra Ghi ($T_5$ - Mốc quyết định RTO):**
   Gửi đơn hàng kiểm chứng ghi sau thăng cấp:
   ```bash
   curl -X POST http://<GLOBAL_ACCELERATOR_IP>/api/v1/orders \
     -H "Content-Type: application/json" \
     -d '{"item_id":"post-failover-check","quantity":1,"marker":"POST_FAILOVER_T5"}'
   ```
   *Khi lệnh trả về HTTP 201 Created $\rightarrow$ Ghi nhận mốc $T_5$.*

### Bước 6: Chạy Script Kiểm Tra và Tính Toán RPO Thực Tế
Chạy script kiểm tra đối soát RPO:

```bash
./scripts/dr/rpo-check.sh "http://<GLOBAL_ACCELERATOR_IP>"
```

*Kết quả phân tích:*
```text
================================================================================
BÁO CÁO PHÂN TÍCH RPO THỰC TẾ (DISASTER RECOVERY BENCHMARK)
================================================================================
1. Bản ghi cuối cùng commit thành công tại Singapore (trước T0):
   - Marker:     SEQ-001250
   - Timestamp:  14:00:00.700

2. Bản ghi lớn nhất hiện diện tại Tokyo sau khi thăng cấp:
   - Marker:     SEQ-001248
   - Timestamp:  13:59:58.700

3. Đánh giá thất thoát:
   - Số bản ghi chênh lệch: 2 records (SEQ-001249, SEQ-001250)
   - RPO Thực tế:           2.000 giây (Mục tiêu: < 30 giây)
   ===> KẾT LUẬN: ĐẠT CHUẨN RPO (PASS)
================================================================================
```

---

## 5. Verification & Testing

### Bảng Phân Tích Chuỗi Phụ Thuộc (Dependency Sequence Analysis)

| Giai đoạn | Trạng thái Traffic | Trạng thái DB Tokyo | Kết quả `GET /health` | Kết quả `GET /catalog` | Kết quả `POST /orders` | Nhận định |
|---|---|---|---|---|---|---|
| **$T_0 \rightarrow T_2$** | Đang chuyển vùng | Read-Only Secondary | Lỗi kết nối / 502 | Lỗi kết nối / 502 | Lỗi kết nối / 502 | Mạng đang chuyển đổi |
| **$T_2 \rightarrow T_3$** | Đã chạm Tokyo | Read-Only Secondary | **200 OK (Tokyo)** | **200 OK (Catalog)** | **500 Error (ReadOnly DB)** | **Traffic đã tới nhưng DB chưa thăng cấp nên không thể ghi** |
| **$T_3 \rightarrow T_5$** | Tại Tokyo | **Primary Writer** | **200 OK (Tokyo)** | **200 OK (Catalog)** | **201 Created (Success)** | **Toàn bộ hệ thống phục hồi toàn diện** |

> [!NOTE]
> Bảng phân tích trên làm rõ nguyên nhân tại sao $T_4$ (Đọc thành công) luôn xuất hiện trước $T_5$ (Ghi thành công), và **chỉ có mốc $T_5$ mới được tính là mốc kết thúc của chỉ số RTO**.

---

## 6. Failure Modes & Troubleshooting

1. **Lỗi: Lệnh `POST /api/v1/orders` trả về HTTP 500 dù Aurora Tokyo đã báo `Available`:**
   - *Nguyên nhân:* Backend-3 chưa refresh connection pool hoặc đang cache DNS cũ của writer endpoint.
   - *Cách sửa:* Thực hiện restart nhẹ pods Backend-3:
     ```bash
     kubectl --context tokyo -n app2 rollout restart deployment app2-backend-3
     ```
2. **Lỗi: Số bản ghi bị mất vượt quá 30 giây:**
   - *Nguyên nhân:* Băng thông mạng liên vùng bị nghẽn đột ngột trước khi ngắt kết nối, khiến `AuroraGlobalDBReplicationLag` tăng vọt.
   - *Cách sửa:* Luôn kiểm tra CloudWatch metric replication lag trước khi tiến hành diễn tập.
3. **Lỗi: Script curl báo lỗi `Connection refused` kéo dài:**
   - *Nguyên nhân:* AWS Global Accelerator chưa hoàn tất việc update route table BGP hoặc client DNS bị cache IP cũ.
   - *Cách sửa:* Luôn dùng IP tĩnh trực tiếp của Global Accelerator thay vì DNS name trong quá trình chạy benchmark script.

---

## 7. Production Hardening & Best Practices

- **Automated Synthetic Monitoring:** Trong môi trường sản xuất, duy trì một cronjob chạy `rpo-writer` với tần suất thấp (1 request/phút) để liên tục kiểm tra tính toàn vẹn của chuỗi replication.
- **Circuit Breaker trong Ứng Dụng:** Khi database đang ở chế độ Read-Only trong khoảng thời gian $T_2 \rightarrow T_3$, Backend-3 nên trả về mã lỗi HTTP 503 kèm thông báo thân thiện "Hệ thống đang bảo trì đơn hàng, vui lòng thử lại sau giây lát" thay vì crash sập tiến trình.

---

## 8. Security & IAM Guardrails

- Dữ liệu tạo ra từ bài test sử dụng mã định danh giả lập `rpo-item` và không chứa bất kỳ thông tin nhạy cảm (PII) nào.
- Sau khi hoàn thành kiểm thử, chạy lệnh dọn dẹp các đơn hàng test khỏi bảng database:
  ```sql
  DELETE FROM orders WHERE item_id = 'rpo-item' OR marker LIKE 'SEQ-%';
  ```

---

## 9. Cost Estimation & Optimization

- Chi phí thực thi bài đo đạc benchmark này chủ yếu là chi phí gọi API và truyền tải dữ liệu HTTP trong khoảng 5-10 phút chạy script, ước tính $< \$0.05$.

---

## 10. Rollback & Disaster Recovery Runbook

- Sau khi thu thập đủ dữ liệu đo đạc, chuẩn bị thực hiện quy trình khôi phục ngược (Failback) theo [LAB 16](16-failback.md) và [docs/runbooks/failback.md](../runbooks/failback.md).

---

## 11. Next Steps & Handoff

### Biểu Mẫu Báo Cáo Kết Quả Diễn Tập Chính Thức (Official DR Evidence Report)

Điền toàn bộ kết quả đo đạc thực tế vào bảng dưới đây:

| Thông số đánh giá | Giá trị thực tế đo được | Mục tiêu tiêu chuẩn | Kết luận |
|---|---|---|---|
| **Mã đợt kiểm thử (Test ID)** | `DR-BENCHMARK-20261011-01` | N/A | Hoàn thành |
| **Ngày thực hiện** | `2026-10-11` | N/A | |
| **Vùng chính (Primary Region)** | `ap-southeast-1` (Singapore) | N/A | |
| **Vùng dự phòng (DR Region)** | `ap-northeast-1` (Tokyo) | N/A | |
| **$T_0$ (Failure Injected)** | `HH:MM:SS.mmm` | Điểm gốc | Gốc tính toán |
| **$T_1$ (Failure Detected)** | `HH:MM:SS.mmm` | $< 30\text{s}$ | |
| **$T_2$ (Traffic Reaches Tokyo)** | `HH:MM:SS.mmm` | $< 45\text{s}$ | |
| **$T_3$ (Aurora Tokyo Promoted)** | `HH:MM:SS.mmm` | $< 180\text{s}$ | |
| **$T_4$ (First Read Success)** | `HH:MM:SS.mmm` | $< 200\text{s}$ | |
| **$T_5$ (First Write Success)** | `HH:MM:SS.mmm` | $< 300\text{s}$ | |
| **Chỉ số RTO Thực Tế ($T_5 - T_0$)** | **... phút ... giây** | **< 5 phút (300s)** | **ĐẠT / CHƯA ĐẠT** |
| **Chỉ số RPO Thực Tế** | **... giây** | **< 30 giây** | **ĐẠT / CHƯA ĐẠT** |
| **Số lượng bản ghi chênh lệch** | `... bản ghi` | Càng ít càng tốt | |
| **Đánh giá tổng thể** | **THÀNH CÔNG (PASS)** | Sẵn sàng Production | |

Chuyển sang [LAB 18 - Dọn Dẹp Tài Nguyên Tránh Phát Sinh Chi Phí](18-cleanup.md) để giải phóng toàn bộ tài nguyên.
