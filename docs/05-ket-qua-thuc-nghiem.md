# Tài Liệu 05: Kết Quả Thực Nghiệm & Bằng Chứng Đo Lường

Tài liệu này trình bày toàn bộ số liệu đo lường, dòng thời gian chi tiết, bằng chứng kỹ thuật và phân tích đối soát thu được từ cuộc diễn tập **Live Unified DR** (`LIVE-RUN-20261018-230436`).

---

## 1. Bảng Tổng Hợp Số Liệu Thực Nghiệm

| Phân Hệ & Chỉ Số | Ký Hiệu Mốc | Giá Trị Thực Nghiệm | Mục Tiêu SLA | Kết Luận | Trạng Thái Bằng Chứng |
|---|:---:|---:|---:|:---:|---|
| **Thời Điểm Cutoff** | $T_0$ | `2026-10-18T23:05:15.101Z` | — | GỐC | Lệnh ngắt traffic ghi Singapore |
| **Storage Volume Promotion** | $T_7$ | **5.719 s** | — | **PASS** | ONTAP REST API xác nhận Volume RW (`23:05:20.820Z`) |
| **Storage Service Round-Trip** | $T_9, T_{11}$ | **6.402 s** | $\le 300.0\text{ s}$ | **PASS** | File-service ghi & đọc thành công file post-cutover |
| **Database Writer Transition** | $T_{\text{DB\_WRITER}}$ | **38.471 s** | — | **PASS** | RDS API xác nhận Tokyo `IsWriter: True` (`23:05:53.572Z`) |
| **Database Service App Write** | $T_{\text{DB\_APP}}$ | **47.428 s** | $\le 240.0\text{ s}$ | **PASS** | `backend-3` xử lý thành công đơn hàng post-cutover |
| **Unified Overall End-to-End RTO** | $T_{\text{RECOVERY}}$ | **47.429 s** | $\le 300.0\text{ s}$ | **PASS** | $\max(47.428\text{s}, 6.402\text{s})$ — Toàn hệ thống sẵn sàng |
| **Database Observed RPO** | $\text{RPO}_{\text{DB}}$ | **0.000 s** | $\le 60.0\text{ s}$ | **PASS** | 5/5 đơn hàng pre-drill tìm thấy đầy đủ |
| **Storage Observed RPO** | $\text{RPO}_{\text{ST}}$ | **0.000 s** | $\le 300.0\text{ s}$ | **PASS** | 5/5 tệp tin pre-drill thu hồi nguyên vẹn, 100% SHA khớp |

---

## 2. Dòng Thời Gian Tiến Trình Diễn Tập (Timeline)

Trích xuất trực tiếp từ [results/unified-dr/timeline.csv](../results/unified-dr/timeline.csv):

```text
MilestoneCode,Milestone,TimestampUtc,Status,DurationMs
T0,DRILL_CUTOFF_T0,2026-10-18T23:05:15.101Z,COMPLETED,0
T_DB_PROMOTION_STARTED,Initiating RDS switchover_global_cluster to Tokyo,2026-10-18T23:05:15.101Z,COMPLETED,0
T6,SNAPMIRROR_PROMOTION_STARTED,2026-10-18T23:05:18.006Z,COMPLETED,0
T7,Tokyo FSx volume confirmed online and RW,2026-10-18T23:05:20.820Z,COMPLETED,5719
T9,Tokyo file-service upload/download/sha256 verified,2026-10-18T23:05:21.503Z,COMPLETED,6402
T11,External Tokyo storage round-trip verified,2026-10-18T23:05:21.503Z,COMPLETED,6402
T_DB_WRITER,Tokyo Aurora confirmed as Global Writer (RDS API),2026-10-18T23:05:53.572Z,COMPLETED,38471
T_DB_APP,Tokyo Aurora & backend-3 accepted and verified write transaction,2026-10-18T23:06:02.529Z,COMPLETED,47428
APP2_E2E_VERIFIED,Unified end-to-end multi-service recovery verified,2026-10-18T23:06:02.530Z,COMPLETED,47429
RECOVERY_COMPLETED,Disaster Recovery Probing Completed Successfully,2026-10-18T23:06:02.530Z,COMPLETED,47429
```

---

## 3. Bằng Chứng Đối Soát Dữ Liệu (Integrity Evidence)

### 3.1. Đối Soát Đơn Hàng Cơ Sở Dữ Liệu
Chi tiết lưu tại [results/database/orders-verification.csv](../results/database/orders-verification.csv):

| Sequence | Order ID | Marker ID | Thời Gian Ghi Nhận (UTC) | Trạng Thái Thu Hồi |
|:---:|:---:|---|---|:---:|
| 1 | 100 | `DR-LIVE-RUN-20261018-230436-SEQ-000001` | 2026-10-18T23:04:45.140Z | **VERIFIED** |
| 2 | 101 | `DR-LIVE-RUN-20261018-230436-SEQ-000002` | 2026-10-18T23:04:46.056Z | **VERIFIED** |
| 3 | 102 | `DR-LIVE-RUN-20261018-230436-SEQ-000003` | 2026-10-18T23:04:46.946Z | **VERIFIED** |
| 4 | 103 | `DR-LIVE-RUN-20261018-230436-SEQ-000004` | 2026-10-18T23:04:47.811Z | **VERIFIED** |
| 5 | 104 | `DR-LIVE-RUN-20261018-230436-SEQ-000005` | 2026-10-18T23:04:48.717Z | **VERIFIED** |

*Ngoài ra, sau khi thăng cấp thành công, giao dịch kiểm tra post-cutover đã ghi nhận đơn hàng ID #133 (`DR-LIVE-RUN-20261018-230436-POST-SEQ-000037`) lúc `23:06:06.304Z`, chứng minh Aurora Tokyo hoàn toàn cho phép ghi đọc bình thường.*

### 3.2. Đối Soát Tệp Tin Lưu Trữ
Chi tiết lưu tại [results/storage/files-verification.csv](../results/storage/files-verification.csv):

| Sequence | File ID | Tên Tệp Tin | Mã Băm SHA-256 | Khớp Mã Băm |
|:---:|---|---|---|:---:|
| 1 | `502bce91-...` | `DR-LIVE-RUN-20261018-230436-SEQ-000001.txt` | `36c101f8279ba80853e320a7e8e8ae63...` | **100% MATCH** |
| 2 | `acdc9a20-...` | `DR-LIVE-RUN-20261018-230436-SEQ-000002.txt` | `45527486c6846c637e4ae438235ed6b5...` | **100% MATCH** |
| 3 | `1e66e4e9-...` | `DR-LIVE-RUN-20261018-230436-SEQ-000003.txt` | `b9e95786b3124f36a4509a837e0794f9...` | **100% MATCH** |
| 4 | `bc0b1c39-...` | `DR-LIVE-RUN-20261018-230436-SEQ-000004.txt` | `a35e0f5f8d7df6a01be238fc8e19ca72...` | **100% MATCH** |
| 5 | `794f729a-...` | `DR-LIVE-RUN-20261018-230436-SEQ-000005.txt` | `bee8a545702213460a740f8edeb5cafb...` | **100% MATCH** |

*File post-cutover `DR-LIVE-RUN-20261018-230436-POST-SEQ-000006.txt` (ID: `81ba685e-...`) được ghi trực tiếp tại Tokyo lúc `23:05:25.161Z` với mã băm SHA-256 `b0ee72afbb29c7bb...`, xác nhận pod Tokyo đã ghi thành công vào volume vừa thăng cấp.*

---

## 4. Phân Tích Kỹ Thuật

1. **Hiệu Năng Của FSx SnapMirror Promotion**:
   - Tốc độ chuyển đổi trạng thái của NetApp ONTAP từ `DP` sang `RW` diễn ra cực kỳ ấn tượng: chỉ mất **5.719 giây** ($T_7$) và ứng dụng ghi đọc thành công sau **6.402 giây** ($T_9$).
   - Điều này chứng minh SnapMirror trên FSx ONTAP là giải pháp tối ưu cho khối lượng dữ liệu tệp tin phi cấu trúc trong các bài toán DR khắt khe.
2. **Hiệu Năng Của Aurora Planned Switchover**:
   - Chuyển đổi vai trò Writer trên Amazon Aurora Global Database mất **38.471 giây** ở tầng AWS API và **47.428 giây** ở tầng ứng dụng kết nối xử lý giao dịch.
   - Sở dĩ thời gian này lớn hơn lưu trữ tệp tin là do quy trình planned switchover phải đảm bảo đồng bộ triệt để mọi WAL log đang tồn đọng trên các storage nodes trước khi hoán đổi vai trò và mở quyền ghi.
3. **Mối Tương Quan Hợp Nhất**:
   - Thời gian phục hồi tổng thể của hệ thống bị giới hạn bởi nhánh chậm hơn (Database: 47.428s). Dù vậy, kết quả 47.429 giây vượt trội hoàn toàn so với mục tiêu đặt ra ban đầu là 300 giây (đạt 15.8% thời gian trần SLA cho phép).
