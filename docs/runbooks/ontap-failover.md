# Sổ tay Vận hành: FSx ONTAP Failover sang Tokyo (Runbook)

## Phạm vi Áp dụng (Scope)

Chỉ áp dụng cho tầng lưu trữ tệp tin (Storage path). Cơ sở dữ liệu Aurora và khối lượng công việc EKS sử dụng runbook chuyên biệt riêng.

## Điều kiện Tiên quyết (Preconditions)

- Mã định danh sự cố/thay đổi (Incident/Change ID), Chỉ huy Sự cố (Incident Commander), Kỹ sư vận hành ONTAP và Người phê duyệt.
- Hạ tầng Tokyo (FSx / SVM / EC2 / ALB) đã sẵn sàng hoạt động.
- Ghi nhận mã sequence ACK lưu trữ cuối cùng và mốc thời gian chuyển dữ liệu (last transfer timestamp) khi có thể.

## Cổng Ra Quyết định (Decision Gates)

1. Singapore có còn ghi được hoặc client còn truy cập được không? Nếu có, **phải cô lập (fence) trước**.
2. Đây là kịch bản có kế hoạch (Planned) hay đột ngột? Nếu có kế hoạch, chạy final update và quiesce. Nếu đột ngột, ghi nhận lý do không thể đồng bộ chặng cuối.
3. Rủi ro mất mát dữ liệu (nếu có) đã được người có thẩm quyền phê duyệt chưa? Nếu chưa phê duyệt, **tuyệt đối không chạy lệnh break**.
4. Người đánh giá thứ hai đã xác nhận chính xác destination path `dr-tokyo-svm:dr-data-dr` chưa?

## Các Bước Thực hiện Chi tiết (Actions)

### Bước 1: Cô lập Writer Singapore trên AWS Console

1. **Khóa lưu lượng Storage Ingress trên AWS Global Accelerator Console:**
   - Mở **AWS Global Accelerator Console** tại [https://console.aws.amazon.com/globalaccelerator/](https://console.aws.amazon.com/globalaccelerator/).
   - Chọn accelerator **`dr-storage-accelerator`** -> tab **Listeners** -> chọn **`Port 80 (TCP)`**.
   - Trong bảng Endpoint groups, chọn nhóm **`ap-southeast-1`** (Singapore) -> bấm **Edit**.
   - Chỉnh **Traffic dial** từ `100` về **`0`** -> bấm nút cam **Save changes**.
2. **Dừng Writer Container tại Singapore (nếu reachable):**
   - Mở **EC2 Console** tại Region Singapore -> Instances -> `dr-sg-storage-ec2` -> bấm **Connect** (Session Manager).
   - Dừng container writer: `docker stop file-service`.

---

### Bước 2: Kiểm tra Quan hệ SnapMirror và Thực hiện Break

1. Mở **EC2 Console** tại Region Tokyo -> Instances -> chọn **`dr-tokyo-storage-ec2`** -> bấm **Connect** (Session Manager).
2. SSH vào giao diện quản trị ONTAP của Tokyo FSx: `ssh fsxadmin@<TOKYO_FSX_MANAGEMENT_IP>`.
3. Kiểm tra quan hệ SnapMirror:
   ```text
   snapmirror show -source-path dr-sg-svm:dr-data -destination-path dr-tokyo-svm:dr-data-dr -fields state,status,last-transfer-end-timestamp
   ```
4. **Đối với kịch bản Planned (Có kế hoạch):**
   - Thực hiện cập nhật chặng cuối và tạm dừng:
     ```text
     snapmirror update -source-path dr-sg-svm:dr-data -destination-path dr-tokyo-svm:dr-data-dr
     snapmirror quiesce -source-path dr-sg-svm:dr-data -destination-path dr-tokyo-svm:dr-data-dr
     ```
5. **Kích hoạt Break (Áp dụng cho cả Planned và Unplanned):**
   - Phá vỡ quan hệ SnapMirror để thăng cấp destination thành volume Read-Write (RW):
     ```text
     snapmirror break -source-path dr-sg-svm:dr-data -destination-path dr-tokyo-svm:dr-data-dr
     ```
   - Xác nhận trạng thái quan hệ chuyển sang `broken-off`.

---

### Bước 3: Kiểm tra Junction-Path và Mount NFS 4.1 lên EC2 Tokyo

1. Trên ONTAP CLI Tokyo, kiểm tra đường dẫn namespace:
   ```text
   volume show -vserver dr-tokyo-svm -volume dr-data-dr -fields junction-path
   ```
   - Nếu trống, mount volume: `volume mount -vserver dr-tokyo-svm -volume dr-data-dr -junction-path /dr-data -active true`.
2. Trên terminal SSM của EC2 Tokyo (`dr-tokyo-storage-ec2`):
   ```bash
   sudo mkdir -p /mnt/dr-data
   sudo mount -t nfs -o nfsvers=4.1 <TOKYO_SVM_NFS_DNS>:/dr-data /mnt/dr-data
   sudo chown 1000:1000 /mnt/dr-data
   sudo chmod 0770 /mnt/dr-data
   ```
   *(Tuyệt đối không dùng chmod 777 hoặc root).*
3. Chạy probe kiểm tra đọc/ghi non-root và khởi động container `file-service`:
   ```bash
   docker run -d --name file-service --restart unless-stopped -p 8080:8080 -u 1000:1000 -v /mnt/dr-data:/data -e DATA_DIR=/data <IMAGE_URI>
   curl -s http://localhost:8080/ready
   ```

---

### Bước 4: Chuyển hướng Lưu lượng sang Tokyo trên AWS Global Accelerator

1. Mở lại **AWS Global Accelerator Console**.
2. Chọn `dr-storage-accelerator` -> Listeners -> Port 80.
3. Chọn nhóm endpoint **`ap-northeast-1`** (Tokyo) -> bấm **Edit**:
   - Chỉnh **Traffic dial** từ `0` thành **`100`** -> bấm **Save changes**.
4. Chờ trạng thái Accelerator hiển thị **Deployed**.
5. Gửi request tạo file kiểm tra qua Global IP của Storage Accelerator để nghiệm thu.

## Trạng thái Mong đợi sau Failover (Expected State)

Tokyo là Region duy nhất nhận ghi (sole writer). Singapore tiếp tục bị cô lập (fenced). Quan hệ SnapMirror ở trạng thái `broken-off` cho đến khi bắt đầu quy trình phục hồi (failback).

## Xử lý Tình huống Bất thường (Failure Handling)

- **Lệnh Break chưa thực thi:** Khôi phục lưu lượng về Singapore nếu môi trường an toàn và ổn định.
- **Lệnh Break đã thực thi nhưng nghiệm thu Tokyo thất bại:** Giữ cô lập cả hai hướng lưu lượng; tiến hành sửa lỗi tại Tokyo hoặc khôi phục từ bản sao lưu FSx Backup gần nhất.
- **Singapore phục hồi đột ngột:** Tuyệt đối không tự động mở route hoặc tự ý chạy đồng bộ resync ngược.

## Bằng chứng Cần Thu thập (Evidence)

Biên bản cô lập (Fencing proof), trạng thái quan hệ SnapMirror kèm mốc thời gian transfer, biên bản phê duyệt DR, bản ghi write đầu tiên tại Tokyo, mã sequence/checksum phục hồi, kết quả kiểm thử lưu lượng qua Global Accelerator.

## Tài liệu Tham khảo (References)

- [AWS SnapMirror Cutover Guide](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/migrating-fsx-ontap-snapmirror.html)
- [NetApp Volume Mount Documentation](https://docs.netapp.com/us-en/ontap-cli/volume-mount.html)
- [AWS Linux NFS Mount Guide](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/attach-linux-client.html)
