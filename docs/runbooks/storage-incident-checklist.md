# Sổ tay Vận hành: Danh mục Kiểm tra Sự cố Lưu trữ (Storage Incident Checklist)

## Phát hiện & Đánh giá (Detect and Assess)

- [ ] Ghi nhận thời điểm UTC `T0`, Incident ID, người báo cáo và các File APIs bị gián đoạn.
- [ ] Kiểm tra **Global Accelerator Console** (`dr-storage-accelerator`): Tình trạng Endpoint group Singapore.
- [ ] Kiểm tra **EC2 Console -> Target Groups** (`dr-sg-storage-tg`): Targets có bị Unhealthy không.
- [ ] Kiểm tra **EC2 Console -> Instances**: EC2 `dr-sg-storage-ec2` có đang Running và kết nối được qua SSM không.
- [ ] Kiểm tra container nội bộ: `curl http://localhost:8080/health` và `curl http://localhost:8080/ready`.
- [ ] Kiểm tra **Amazon FSx Console**: File system `dr-sg-fsx`, SVM `dr-sg-svm` và Volume `dr-data` có trạng thái Available không.
- [ ] Kiểm tra quan hệ SnapMirror qua ONTAP CLI Tokyo: Ghi nhận `state`, `status`, `last-transfer-end-timestamp` và lag time.
- [ ] Phân biệt rõ sự cố xảy ra ở tầng nào: Application container, Host EC2, NFS Mount point, FSx File system, hay VPC Peering mạng.

---

## Cô lập Chiều Ghi (Fence)

- [ ] **Khóa Ingress:** Trên **Global Accelerator Console**, chuyển Traffic dial của `ap-southeast-1` về `0` trên `dr-storage-accelerator`.
- [ ] **Dừng Writer Container:** Trên EC2 Singapore qua SSM, chạy `docker stop file-service` để xả toàn bộ buffer vào volume.
- [ ] Rà soát xác nhận không còn client/pod nào khác có thể ghi vào Singapore SVM.
- [ ] Giữ nguyên snapshot/log; **tuyệt đối không** tự ý chạy `resync` trong lúc phân tích sự cố.

---

## Phê chuẩn Kích hoạt (Decision)

- [ ] Kiểm tra hạ tầng Tokyo: FSx Tokyo `dr-tokyo-fsx`, SVM `dr-tokyo-svm`, Volume DP `dr-data-dr`, EC2 Tokyo sẵn sàng.
- [ ] Incident Commander công bố và chấp nhận ranh giới mất mát dữ liệu (Estimated Storage RPO).
- [ ] Nhận phê chuẩn phá vỡ quan hệ từ Approver; reviewer thứ hai xác nhận chính xác destination path `dr-tokyo-svm:dr-data-dr`.

---

## Phục hồi tại Tokyo (Recover)

- [ ] **Planned:** Chạy final update -> kiểm tra `Idle` -> quiesce -> kiểm tra `Quiesced`.
- [ ] **Phá vỡ SnapMirror:** Trên ONTAP CLI Tokyo, chạy `snapmirror break -destination-path dr-tokyo-svm:dr-data-dr`.
- [ ] Kiểm tra junction-path và mount vào namespace: `/dr-data`.
- [ ] Trên EC2 Tokyo qua SSM: Mount NFSv4.1 `/mnt/dr-data` với quyền non-root `1000:1000` mode `0770` (tuyệt đối không 777).
- [ ] Khởi chạy container `file-service` (UID 1000), kiểm tra `/health` và `/ready`.
- [ ] Kiểm tra Target Group Tokyo trên EC2 Console (`dr-tokyo-storage-tg`) chuyển sang **Healthy**.
- [ ] **Mở Ingress:** Trên **Global Accelerator Console**, nâng Traffic dial của Tokyo lên `100`.

---

## Ổn định & Đo đạc (Stabilize)

- [ ] Xác nhận chỉ có duy nhất Tokyo là writer; Singapore vẫn bị cô lập hoàn toàn.
- [ ] Ghi nhận thời điểm $T_3$ (Volume RW) và $T_4$ (First client write), tính toán Storage RTO ($T_4 - T_0$).
- [ ] Đo lường độ trễ dữ liệu Storage RPO (so sánh latest recovered sequence với snapshot trước sự cố).
- [ ] Giữ nguyên trạng thái Singapore khi Region này online trở lại; bàn giao cho quy trình Failback tại [ontap-failback.md](ontap-failback.md).

---

## Đóng Sự cố & Kiểm toán (Close)

- [ ] Lưu trữ evidence, SHA-256 integrity report và CloudTrail audit logs.
- [ ] Hoàn thành báo cáo đối chiếu Target, Expected và Measured Result riêng biệt.
