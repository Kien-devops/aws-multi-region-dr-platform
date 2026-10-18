# Tài Liệu 04: Quy Trình Kích Hoạt Disaster Recovery (DR Runbook)

Tài liệu này diễn giải chi tiết từng bước trong quy trình diễn tập khắc phục thảm họa hợp nhất (Unified DR Drill), bao gồm chuyển đổi Aurora, thăng cấp FSx ONTAP, kiểm chứng ứng dụng và cách đo lường các mốc thời gian.

> [!IMPORTANT]
> **Lưu ý kiến trúc vận hành**:
> - Hệ thống này triển khai theo cơ chế **On-demand Automated DR** (Diễn tập tự động theo lệnh điều hành có kiểm soát an toàn), **không phải cơ chế tự động phát hiện thảm họa và tự kích hoạt (Automatic Disaster Detection)**.
> - Quyết định chuyển vùng luôn cần sự xác nhận của kỹ sư vận hành (Operator Approval Token) trước khi thực hiện các thao tác chuyển đổi tài nguyên.

---

## 1. Các Giai Đoạn Trong Quy Trình DR

Quy trình diễn tập gồm 5 giai đoạn liên tục được đồng bộ qua một định danh duy nhất (`RUN_ID`):

```text
GIAI ĐOẠN 1: Kiểm Tra Tiền Điều Kiện (Preflight Safety Audit)
        │
GIAI ĐOẠN 2: Tiêm Dữ Liệu Kiểm Thử Nền (Pre-drill Baseline Marker Injection)
        │
GIAI ĐOẠN 3: Cắt Mạch (T0 Cutoff) & Điều Phối Chuyển Đổi Song Song
        ├── Nhánh A: Aurora Global Database Planned Switchover
        └── Nhánh B: FSx ONTAP SnapMirror Break-off & Promotion
        │
GIAI ĐOẠN 4: Thăm Dò & Xác Thực Ứng Dụng Đầu Cuối (High-Frequency Verification Probes)
        │
GIAI ĐOẠN 5: Đo Lường Chỉ Số Độc Lập & Xuất Báo Cáo (RTO/RPO Calculation & Evidence Export)
```

Chi tiết sơ đồ tiến trình tham khảo tại: [docs/diagrams/04-unified-dr-execution-flow.md](diagrams/04-unified-dr-execution-flow.md).

---

## 2. Diễn Giải Chi Tiết Từng Giai Đoạn

### Giai Đoạn 1: Kiểm Tra Tiền Điều Kiện (Preflight Safety Audit)
Trước khi cho phép can thiệp vào tài nguyên, bộ kiểm tra tự động rà soát toàn bộ trạng thái hạ tầng:
- **Cơ sở dữ liệu**: Gọi RDS API xác nhận cụm `app2-global-db` đang ở trạng thái `available`, Singapore là writer hiện hành, Tokyo là reader sẵn sàng.
- **Lưu trữ tệp tin**: Kiểm tra Volume Tokyo (`fsvol-0aa304f04e3efc058`) đang tồn tại, quan hệ SnapMirror `ce3ce815-cb1c-11f1-8f09-75ce6ba06232` ở trạng thái `snapmirrored` và `healthy: true`.
- **Ứng dụng**: Kiểm tra mã phản hồi HTTP 200 từ các Ingress ALB tại cả hai vùng.

### Giai Đoạn 2: Tiêm Dữ Liệu Kiểm Thử Nền (Pre-drill Baseline Markers)
Để có cơ sở toán học tính toán RPO thực tế:
1. Gửi tuần tự 5 đơn hàng qua Singapore ALB (`/api/v1/orders`), nhận mã phản hồi ACK và lưu lại danh sách `Order ID` (100–104) cùng timestamp gửi.
2. Tải lên tuần tự 5 tệp tin văn bản qua Singapore ALB (`/api/v1/files`), nhận ACK và tính mã băm SHA-256 của từng tệp tin.
3. Kích hoạt một lượt truyền dữ liệu gia tăng khẩn cấp qua ONTAP REST API:
   ```http
   POST /api/snapmirror/relationships/{uuid}/transfers
   ```
   Đợi SnapMirror hoàn tất lượt đẩy dữ liệu này sang Tokyo trước khi ngắt mạch.

### Giai Đoạn 3: Cắt Mạch $T_0$ & Điều Phối Chuyển Đổi Song Song
Tại thời điểm $T_0$ (`2026-10-18T23:05:15.101Z`), điều phối viên ngắt lưu lượng ghi tại Singapore và đồng thời phát lệnh:
1. **Nhánh Cơ Sở Dữ Liệu (RDS Switchover)**:
   - Gọi API AWS RDS:
     ```python
     rds_client.switchover_global_cluster(
         GlobalClusterIdentifier="app2-global-db",
         TargetDBClusterIdentifier="arn:aws:rds:ap-northeast-1:620306387033:cluster:app2-tokyo-db"
     )
     ```
   - Quá trình này đồng bộ toàn bộ buffer chưa ghi từ Singapore sang Tokyo, sau đó chuyển cụm Tokyo thành Global Writer.
2. **Nhánh Lưu Trữ Tệp Tin (FSx SnapMirror Break)**:
   - Kích hoạt AWS Lambda function `dr-fsx-failover-promote-tokyo` trong vùng Tokyo.
   - Lambda function kết nối vào ONTAP REST API của Tokyo SVM và gửi lệnh ngắt quan hệ nhân bản:
     ```http
     PATCH /api/snapmirror/relationships/{uuid}
     Body: {"state": "broken_off"}
     ```
   - Khi quan hệ bị ngắt, volume `dr_data_dr` tại Tokyo tự động được ONTAP chuyển trạng thái từ Data Protection (DP) sang Read-Write (RW).

### Giai Đoạn 4: Thăm Dò & Xác Thực Ứng Dụng (Application Verification)
Không dừng lại ở việc kiểm tra trạng thái AWS API (vì trạng thái API "Available" chưa đồng nghĩa với việc ứng dụng đã phục hồi hoàn toàn), một tiến trình thăm dò tần suất cao liên tục kiểm tra:
1. **Kiểm tra Storage**:
   - Thăm dò ONTAP API: Volume Tokyo chuyển `RW` lúc T7 (`23:05:20.820Z`, sau **5.719s**).
   - Thăm dò Application: Gửi yêu cầu ghi tệp tin mới `DR-POST-SEQ-000006.txt` vào Tokyo `app2-file-service`, tải lại và so khớp SHA-256 lúc T9 & T11 (`23:05:21.503Z`, sau **6.402s**).
2. **Kiểm tra Database**:
   - Thăm dò RDS API: Cụm Tokyo xác nhận `IsWriter: True` lúc T_DB_WRITER (`23:05:53.572Z`, sau **38.471s**).
   - Thăm dò Application: Gửi đơn hàng kiểm tra post-cutover #133 qua Tokyo ALB, đọc lại bản ghi để chứng minh tính bền vững ACID lúc T_DB_APP (`23:06:02.529Z`, sau **47.428s**).

### Giai Đoạn 5: Đo Lường Chỉ Số Độc Lập & Đối Soát Dữ Liệu
Khi cả hai nhánh đều xác thực thành công:
- **Overall RTO** được xác định là thời điểm hoàn thành của nhánh chậm hơn:
  ```text
  Overall RTO = max(Database Service RTO, Storage Service RTO) = max(47.428s, 6.402s) = 47.429s
  ```
- **RPO Verification**:
  - Truy vấn bảng `orders` của Tokyo: Tìm thấy đầy đủ 5/5 đơn hàng pre-drill (ID 100, 101, 102, 103, 104) → Database RPO = 0.000 s (0 lost records).
  - Truy vấn thư viện file của Tokyo: Tìm thấy đầy đủ 5/5 tệp tin pre-drill, đối chiếu mã băm SHA-256 khớp 100% → Storage RPO = 0.000 s (0 lost files).
