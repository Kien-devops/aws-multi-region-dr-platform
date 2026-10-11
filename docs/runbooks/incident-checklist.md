# Runbook: Bảng Kiểm Sự Cố và Ứng Phó Khẩn Cấp (Incident Checklist)

> **Mục đích:** Cung cấp quy trình phản ứng nhanh chuẩn mực (Incident Response Checklist) dành cho Incident Commander, SRE Lead và Ban Quản Lý khi đối mặt với thảm họa gián đoạn dịch vụ diện rộng trên nền tảng AWS Multi-Region.

---

## 1. Phân Loại Mức Độ Sự Cố (Severity Levels)

| Mức độ | Định nghĩa | Tiêu chí kích hoạt | Thời gian phản hồi mục tiêu |
|---|---|---|---|
| **SEV-1 (Critical)** | Thảm họa hệ thống diện rộng | Toàn bộ vùng Singapore mất kết nối, người dùng không thể truy cập, cả 4 microservices không phản hồi | `< 5 phút` (Họp War Room tức thì) |
| **SEV-2 (Major)** | Suy giảm nghiêm trọng | 1 trong 3 backend không hoạt động hoặc database replication lag vượt quá 60 giây | `< 15 phút` |
| **SEV-3 (Minor)** | Sự cố nội bộ không ảnh hưởng người dùng | Lỗi build ECR hoặc 1 Node worker bị crash nhưng pods tự failover sang node khác | `< 1 giờ` |

---

## 2. Phân Vai Trong Nhóm Ứng Phó (Incident Roles)

Trong một sự cố mức SEV-1, các thành viên cần phân định rõ trách nhiệm:
1. **Incident Commander (IC):** Người nắm toàn quyền quyết định kích hoạt DR Failover hay không; điều phối các luồng công việc; ngăn ngừa các hành động vội vàng gây mất mát dữ liệu.
2. **Operations Lead (Ops):** Kỹ sư phụ trách hạ tầng mạng, AWS Global Accelerator, EKS cluster và pod scaling.
3. **Database Lead (DBA):** Kỹ sư phụ trách Aurora Global Database, kiểm tra replication lag, thực hiện switchover/failover DB.
4. **Communications Lead (Comms):** Chịu trách nhiệm cập nhật trạng thái lên kênh nội bộ (Slack/Teams) và trang thông báo khách hàng (Status Page).

---

## 3. Bảng Kiểm Từng Pha Xử Lý (Phase-by-Phase Checklist)

### Pha 1: Nhận diện & Đánh giá (T0 -> T1)
- [ ] Xác nhận cảnh báo từ CloudWatch / Alertmanager / Global Accelerator.
- [ ] Kiểm tra AWS Health Dashboard xem có thông báo AWS Outage tại `ap-southeast-1` hay không.
- [ ] Xác minh lỗi độc lập từ ít nhất 2 nguồn mạng khác nhau (tránh báo động giả từ một ISP đơn lẻ).
- [ ] Mở kênh War Room (Google Meet / Zoom / Slack `#warroom-dr`).
- [ ] Khởi tạo bảng Incident Time Tracker để ghi lại các mốc thời gian $T_0, T_1...$.

### Pha 2: Ra quyết định Kích hoạt DR (Decision Gate)
- [ ] Kiểm tra trạng thái vùng dự phòng Tokyo (`ap-northeast-1`): EKS cluster và Pods đang ở trạng thái sẵn sàng?
- [ ] Kiểm tra replication lag của Aurora Tokyo trước khi sập kết nối: có dưới 5 giây không?
- [ ] Incident Commander đưa ra tuyên bố chính thức: **"KÍCH HOẠT QUY TRÌNH DR FAILOVER SANG TOKYO"**.

### Pha 3: Triển khai Cứu hộ (Execution T2 -> T5)
- [ ] **Ops Lead:** Chuyển traffic dial của Global Accelerator sang Tokyo (hoặc xác nhận AGA đã tự động cô lập Singapore).
- [ ] **DBA Lead:** Thực hiện thăng cấp Aurora Tokyo thành Primary Writer (theo [database-recovery.md](database-recovery.md)).
- [ ] **Ops Lead:** Scale các deployment của `app2` tại Tokyo lên số lượng replica phù hợp với tải sản xuất (2 replicas/service).
- [ ] **Ops Lead:** Xác thực curl kiểm tra HTTP 200 trên endpoint đọc dữ liệu ($T_4$).
- [ ] **DBA & App Lead:** Xác thực đơn hàng mới được tạo thành công vào DB Tokyo ($T_5$).
- [ ] Ghi nhận thời gian hoàn tất và tính toán chỉ số RTO thực tế.

### Pha 4: Ổn định Dịch vụ & Theo dõi (Stabilization)
- [ ] Giám sát tỷ lệ lỗi HTTP 5xx và latency trên dashboard Grafana / CloudWatch của Tokyo.
- [ ] Bật auto-scaling (HPA) cho các service để ứng phó với biến động lưu lượng.
- [ ] Thông báo cho các bên liên quan: "Hệ thống đã được chuyển vùng thành công sang Tokyo, dịch vụ hoạt động bình thường".

### Pha 5: Chuẩn bị Phục hồi ngược (Failback Readiness)
- [ ] Đợi thông báo chính thức từ AWS về việc hạ tầng Singapore đã được khắc phục hoàn toàn.
- [ ] Giữ hệ thống chạy ổn định tại Tokyo tối thiểu **30 - 60 phút** trước khi xem xét phương án Failback.
- [ ] Tuân thủ nghiêm ngặt runbook [failback.md](failback.md).

---

## 4. Mẫu Thông Báo Sự Cố Chuẩn (Communication Templates)

### Thông báo khởi động sự cố (Incident Broadcast):
```text
🚨 [SEV-1 INCIDENT ALERT] Gián đoạn dịch vụ trên Vùng Singapore (ap-southeast-1)
- Thời gian phát hiện: YYYY-MM-DD HH:MM UTC
- Ảnh hưởng: Người dùng không thể truy cập ứng dụng app2 qua vùng Singapore
- Tình trạng: War room đang mở. Incident Commander đã kích hoạt quy trình DR Failover sang Tokyo (ap-northeast-1).
- Trực tiếp điều phối: @IncidentCommander, @OpsLead, @DBALead.
```

### Thông báo dịch vụ đã phục hồi (Recovery Broadcast):
```text
✅ [SEV-1 UPDATE] Hệ thống đã khôi phục thành công trên Vùng Tokyo (ap-northeast-1)
- Thời gian phục hồi: YYYY-MM-DD HH:MM UTC
- RTO thực tế ghi nhận: XX phút YY giây (Mục tiêu: < 5 phút)
- RPO ước tính: < ZZ giây (Mục tiêu: < 30 giây)
- Trạng thái hiện tại: 100% traffic đang được phục vụ bởi Tokyo ALB và Aurora Tokyo Primary. Đang theo dõi ổn định.
```
