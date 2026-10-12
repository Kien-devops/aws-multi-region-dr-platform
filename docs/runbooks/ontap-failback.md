# Sổ tay Vận hành: FSx ONTAP Failback về Singapore (Runbook)

## Phạm vi Áp dụng (Scope)

Đồng bộ dữ liệu có thẩm quyền từ Tokyo về Singapore (Reverse Resync), sau đó tái lập quan hệ bảo vệ chuẩn từ Singapore sang Tokyo.

## Điều kiện Tiên quyết (Preconditions)

- Hạ tầng Tokyo hoạt động ổn định và nắm giữ dữ liệu nguồn có thẩm quyền (authoritative); hạ tầng Singapore đã khắc phục xong sự cố và vẫn đang bị cô lập (fenced).
- Đã hoàn tất tạo snapshots và bản sao lưu FSx Backup hai đầu; định tuyến peering intercluster thông suốt.
- Bắt buộc có **hai kỹ sư độc lập** xác minh và ký duyệt hướng đồng bộ (source/destination).

## Cổng Ra Quyết định (Decision Gates)

1. Dữ liệu trên destination Singapore có chấp nhận bị ghi đè quay về snapshot chung gần nhất (newest common snapshot) không? Nếu chưa rõ, **dừng ngay lập tức**.
2. Hai cụm có tồn tại snapshot chung không? Nếu không, phải chuyển sang phương án di chuyển qua bản sao lưu backup/new volume.
3. Các tiến trình ghi tại Tokyo có thể tạm dừng (quiesce) để thực hiện đồng bộ chặng cuối không?

## Các Bước Thực hiện Chi tiết (Actions)

### Bước 1: Tạo FSx Backup trên AWS Console & Volume Snapshots

1. **Tạo FSx Backup trên AWS Console (Tokyo & Singapore):**
   - Mở **Amazon FSx Console** tại Tokyo -> File systems -> `dr-tokyo-fsx` -> Volumes -> chọn `dr-data-dr` -> menu **Actions** -> **Create backup** -> Tên: `dr-tokyo-pre-failback-backup` -> **Create backup**.
   - Đổi sang Region Singapore -> File systems -> `dr-sg-fsx` -> Volumes -> chọn `dr-data` -> menu **Actions** -> **Create backup** -> Tên: `dr-sg-pre-failback-backup` -> **Create backup**.
2. **Tạo snapshot trên ONTAP CLI hai phía:**
   ```text
   # Trên Tokyo cluster:
   volume snapshot create -vserver dr-tokyo-svm -volume dr-data-dr -snapshot pre-failback-manual

   # Trên Singapore cluster:
   volume snapshot create -vserver dr-sg-svm -volume dr-data -snapshot pre-failback-manual
   ```

---

### Bước 2: Thiết lập Reverse Resync (Tokyo -> Singapore)

1. Từ terminal SSM của EC2 Singapore, kết nối vào ONTAP CLI Singapore.
2. Hai người xác nhận hướng đồng bộ: Tokyo (`dr-tokyo-svm:dr-data-dr`) là source authoritative, Singapore (`dr-sg-svm:dr-data`) là destination nhận delta blocks.
3. Kích hoạt đảo chiều đồng bộ:
   ```text
   snapmirror resync -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data
   ```
4. Theo dõi đến khi trạng thái đạt `Snapmirrored` và `Idle`.

---

### Bước 3: Dừng Writer Tokyo và Cắt Ingress

1. Trên **AWS Global Accelerator Console**:
   - Chọn `dr-storage-accelerator` -> Listeners -> Port 80 -> nhóm `ap-northeast-1` (Tokyo) -> **Edit** -> Đổi **Traffic dial** về **`0`** -> **Save changes**.
2. Trên EC2 Tokyo qua SSM: Dừng container writer: `docker stop file-service`.

---

### Bước 4: Final Update, Quiesce và Break trên Singapore ONTAP

1. Trên ONTAP CLI của Singapore, thực hiện cập nhật chặng cuối và phá vỡ quan hệ:
   ```text
   snapmirror update -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data
   snapmirror quiesce -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data
   snapmirror break -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data
   ```
   *Kết quả:* Volume `dr-data` tại Singapore trở lại thành Read-Write (RW).

---

### Bước 5: Mount NFS 4.1 và Khởi động Container tại Singapore

1. Kiểm tra junction-path trên ONTAP CLI Singapore:
   ```text
   volume show -vserver dr-sg-svm -volume dr-data -fields junction-path
   ```
   - Nếu trống: `volume mount -vserver dr-sg-svm -volume dr-data -junction-path /dr-data -active true`.
2. Trên terminal SSM của EC2 Singapore (`dr-sg-storage-ec2`):
   ```bash
   sudo mkdir -p /mnt/dr-data
   sudo mount -t nfs -o nfsvers=4.1 <SINGAPORE_SVM_NFS_DNS>:/dr-data /mnt/dr-data
   sudo chown 1000:1000 /mnt/dr-data
   sudo chmod 0770 /mnt/dr-data
   docker run -d --name file-service --restart unless-stopped -p 8080:8080 -u 1000:1000 -v /mnt/dr-data:/data -e DATA_DIR=/data <IMAGE_URI>
   curl -s http://localhost:8080/ready
   ```

---

### Bước 6: Khôi phục Traffic Dial trên AWS Global Accelerator

1. Mở lại **AWS Global Accelerator Console**.
2. Chọn `dr-storage-accelerator` -> Listeners -> Port 80:
   - Nhóm Singapore (`ap-southeast-1`): Edit Traffic dial thành **`100`** -> **Save changes**.
   - Nhóm Tokyo (`ap-northeast-1`): Đảm bảo Traffic dial là **`0`**.

---

### Bước 7: Tái lập Quan hệ Bảo vệ Chuẩn (Singapore -> Tokyo)

1. Xóa quan hệ đảo chiều trên **Singapore ONTAP CLI**:
   ```text
   snapmirror delete -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data
   ```
2. Release metadata trên **Tokyo ONTAP CLI**:
   ```text
   snapmirror release -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data
   ```
3. Khôi phục đồng bộ xuôi trên **Tokyo ONTAP CLI**:
   ```text
   snapmirror resync -source-path dr-sg-svm:dr-data -destination-path dr-tokyo-svm:dr-data-dr
   snapmirror show -source-path dr-sg-svm:dr-data -destination-path dr-tokyo-svm:dr-data-dr -fields state,status,healthy
   ```
   *Kết quả:* Trạng thái quan hệ là `Snapmirrored` và `Idle`. Volume Tokyo trở lại thành Data Protection (DP).

## Phương án Quay lui (Rollback)

- **Trước khi thăng cấp Singapore:** Duy trì toàn bộ lưu lượng phục vụ trên Tokyo.
- **Sau khi đã thăng cấp Singapore:** Coi Singapore là nguồn chân lý mới (authoritative) và thực hiện quy trình Controlled Switchover có kế hoạch sang Tokyo nếu muốn đổi lại.

## Cảnh báo Bảo mật & Toàn vẹn Dữ liệu (Warning)

> [!CAUTION]
> Lệnh `snapmirror resync` có khả năng xóa toàn bộ các snapshot trên destination mới hơn snapshot chung và hủy bỏ vĩnh viễn các khối dữ liệu phân nhánh (divergent data). Trong quá trình Reverse Resync, **Singapore chính là destination chịu tác động hủy dữ liệu này**. Tuyệt đối không bao giờ suy diễn hướng đồng bộ dựa theo tên Region; bắt buộc phải tạo snapshot, FSx Backup, chạy lệnh kiểm tra `snapmirror show` và có sự phê duyệt độc lập từ hai kỹ sư trước khi chạy lệnh.

## Bằng chứng Cần Thu thập (Evidence)

Danh sách bản sao lưu Snapshots/Backups, trạng thái quan hệ peer và SnapMirror, biên bản phê duyệt hướng đồng bộ (Direction Approval), mã sequence cuối cùng tại Tokyo, bản ghi write đầu tiên tại Singapore, và trạng thái phục hồi quan hệ bảo vệ xuôi bình thường.

## Tài liệu Tham khảo (References)

- [NetApp SnapMirror Resync Warning & Behavior](https://docs.netapp.com/us-en/ontap-cli/snapmirror-resync.html)
- [NetApp Reactivate Original Source Volume](https://docs.netapp.com/us-en/ontap/data-protection/reactivate-original-source-volume-task.html)
- [NetApp Volume Mount Documentation](https://docs.netapp.com/us-en/ontap-cli/volume-mount.html)
- [AWS FSx for ONTAP Backups Guide](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/using-backups.html)
