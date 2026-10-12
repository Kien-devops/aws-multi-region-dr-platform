# Sổ tay Vận hành: Danh mục Kiểm tra Sự cố (Incident Checklist)

## Phân công Vai trò (Roles)

- **Chỉ huy Sự cố (Incident Commander):** Nắm quyền quyết định cao nhất và kiểm soát bán kính ảnh hưởng (blast radius).
- **Kỹ sư AWS (AWS Operator):** Trực tiếp thực thi các thay đổi hạ tầng đã được phê duyệt trên RDS / GA / EKS.
- **Quản trị viên Cơ sở Dữ liệu (DBA):** Xác thực cấu trúc topo, độ trễ sao chép dữ liệu, rủi ro mất mát dữ liệu và quy trình đối soát.
- **Kỹ sư Độc lập (Verifier):** Độc lập kiểm tra sức khỏe hệ thống và bằng chứng nghiệm thu.
- **Thư ký / Truyền thông (Recorder/Communications):** Ghi nhật ký dòng thời gian UTC và cập nhật trạng thái cho các bên liên quan.

## Phát hiện và Đánh giá (Detect and Assess)

*Phân loại độc lập Database/Application và Storage. Aurora writer khỏe không đồng nghĩa với FSx writable; process container khỏe không đồng nghĩa với NFS mount writable.*

- [ ] Ghi nhận Incident ID và mốc thời gian UTC `T0`.
- [ ] Xác định thành phần và Region bị ảnh hưởng.
- [ ] Rà soát tín hiệu cảnh báo trên **CloudWatch Console** (`dr-platform-dashboard`).
- [ ] Kiểm tra **Global Accelerator Console**: Trạng thái Unhealthy Endpoint của nhóm Singapore.
- [ ] Kiểm tra **EC2 Console -> Target Groups**: Trạng thái Healthy/Unhealthy của targets.
- [ ] Kiểm tra **RDS Console -> Databases**: Trạng thái của cụm `dr-global-db` và replication lag.
- [ ] Loại trừ nguyên nhân mạng/IAM cục bộ trước khi kích hoạt quy trình thảm họa vùng.
- [ ] Kiểm tra dung lượng và tình trạng sẵn sàng của Region Tokyo (EKS Nodes, Pods, Secret replica).

---

## Cổng Phê duyệt & Quyết định (Decision Gate)

*Đối với sự cố liên quan Storage/FSx, đối chiếu thêm với [storage-incident-checklist.md](storage-incident-checklist.md). Bắt buộc fence writer cũ và được duyệt data loss trước khi break SnapMirror.*

- [ ] **Incident Commander** phê chuẩn phương án: Planned Switchover (Không mất dữ liệu) hoặc Unplanned Failover (Chấp nhận mất dữ liệu khả dĩ).
- [ ] DBA xác định ranh giới độ trễ dữ liệu khả dĩ (Estimated RPO boundary).
- [ ] Thống nhất phương án cô lập triệt để Singapore cũ (Fencing Plan).
- [ ] Chỉ định chủ sở hữu phục hồi (Rollback/Failback Owner).

---

## Thực thi theo Runbook (Execute)

- [ ] **Fencing Singapore:** Trên **Global Accelerator Console**, chuyển Traffic dial của Singapore về `0`.
- [ ] Kiểm tra xác nhận Tokyo EKS, ALB, Secret replica `/app2/database` và RDS Secondary đều khỏe mạnh.
- [ ] **RDS Promotion:** Trên **RDS Console -> Databases -> Actions**:
  - Nếu Planned: Chọn **Switch over global database**.
  - Nếu Unplanned: Chọn **Fail over global database** (tích xác nhận data loss).
- [ ] Xác nhận trên Console chỉ duy nhất Tokyo có trạng thái **Primary cluster (Writer)**.
- [ ] **Traffic Shift:** Trên **Global Accelerator Console**, nâng Traffic dial của Tokyo lên `100`.
- [ ] Xác minh kết nối end-to-end và các CloudWatch Alarms.

---

## Ổn định Hệ thống (Stabilize)

- [ ] Các chỉ số Error Rate, Latency và Health checks trên CloudWatch trở lại bình thường.
- [ ] Giữ nguyên trạng thái cô lập của Singapore khi Region này hoạt động trở lại.
- [ ] Xác nhận Endpoint Global Writer và Secrets Manager hoạt động đúng thiết kế.
- [ ] Ghi nhận mốc thời gian phục hồi hạ tầng hoàn tất ($T_5$), tính toán RTO thực tế.
- [ ] Cập nhật báo cáo cho các bên liên quan (tránh tuyên bố RTO/RPO cảm tính khi chưa đo lường).

---

## Chuẩn bị Tái thiết lập Failback (Prepare Failback)

- [ ] Nguyên nhân gốc rễ (Root Cause) tại Singapore đã được khắc phục hoàn toàn.
- [ ] Tái gia nhập Singapore làm Secondary Cluster đồng bộ từ Primary Tokyo.
- [ ] Theo dõi độ trễ `AuroraGlobalDBReplicationLag` duy trì `<= 1s` trong ít nhất 15-30 phút.
- [ ] Phê duyệt kế hoạch Failback theo quy trình chuẩn tại [failback.md](failback.md).

---

## Đóng Sự cố & Kiểm toán (Close)

- [ ] Lưu trữ toàn bộ bằng chứng, log CloudTrail, RDS events, GA metrics.
- [ ] Hoàn thiện bảng đối chiếu Thiết kế mục tiêu vs Kết quả thực nghiệm đo đạc.
- [ ] Phân công các hành động sau sự cố (Post-Mortem Actions): Tinh chỉnh giám sát, tăng cường bảo mật, diễn tập GameDay.
