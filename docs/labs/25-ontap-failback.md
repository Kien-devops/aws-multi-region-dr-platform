# LAB 25 - ONTAP Failback về Singapore

## 1. Mục tiêu

Đưa authoritative file state từ Tokyo về Singapore và khôi phục Singapore-primary/Tokyo-DP.

## 2. Thành phần sẽ xây dựng

Reverse resync Tokyo -> Singapore, final cutback, rồi tái lập protection Singapore -> Tokyo.

## 3. Bối cảnh kiến trúc

Tokyo là source of truth sau promotion. `snapmirror resync` có thể rollback/xóa divergent destination data.

## 4. Điều kiện tiên quyết

- Tokyo stable/RW; Singapore repaired, fenced and not serving writes.
- Snapshot/backup/evidence complete; source/destination direction được hai người review.
- Capacity/network/peering healthy.

## 5. Quy ước đặt tên tài nguyên

Authoritative source: `dr-tokyo-svm:dr-data-dr`; recovery destination: `dr-sg-svm:dr-data`.

## 6. Các bước triển khai

### Bước 1: Sao lưu Bảo vệ (FSx Backup trên AWS Console) & Tạo Snapshot Hai Phía

> [!CAUTION]
> **Nguy cơ mất dữ liệu Divergent:** Thao tác `snapmirror resync` ngược (Tokyo -> Singapore) sẽ ghi đè và loại bỏ toàn bộ dữ liệu mới hơn trên destination (Singapore). Bắt buộc phải tạo bản snapshot/backup đầy đủ ở cả hai Region trước khi thực hiện.

1. **Tạo FSx Backup trên AWS Console (Tokyo):**
   - Chọn Region **Tokyo (`ap-northeast-1`)** trên Navigation bar.
   - Mở **Amazon FSx Console** tại [https://console.aws.amazon.com/fsx/](https://console.aws.amazon.com/fsx/).
   - Tại menu trái chọn **File systems** -> nhấp vào **`dr-tokyo-fsx`**.
   - Chọn tab **Storage virtual machines** -> nhấp vào **`dr-tokyo-svm`** -> tab **Volumes**.
   - Tích chọn volume **`dr-data-dr`** -> nhấp menu **Actions** ở góc trên -> chọn **Create backup**.
   - Tại ô **Backup name**, nhập: `dr-tokyo-backup-pre-failback`.
   - Nhấp nút cam **Create backup**.

2. **Tạo FSx Backup trên AWS Console (Singapore):**
   - Đổi Region sang **Singapore (`ap-southeast-1`)** trên Navigation bar.
   - Trong Amazon FSx Console -> **File systems** -> **`dr-sg-fsx`** -> tab **Storage virtual machines** -> **`dr-sg-svm`** -> tab **Volumes**.
   - Tích chọn volume **`dr-data`** -> nhấp menu **Actions** -> chọn **Create backup**.
   - Tại ô **Backup name**, nhập: `dr-sg-backup-pre-failback`.
   - Nhấp nút cam **Create backup**.

3. **Tạo Volume Snapshots qua ONTAP CLI hai phía:**
   - Kết nối SSM vào EC2 Tokyo (`dr-tokyo-storage-ec2`) và SSH vào ONTAP CLI Tokyo:
     ```text
     volume snapshot create -vserver dr-tokyo-svm -volume dr-data-dr -snapshot pre-failback-manual
     ```
   - Kết nối SSM vào EC2 Singapore (`dr-sg-storage-ec2`) và SSH vào ONTAP CLI Singapore:
     ```text
     volume snapshot create -vserver dr-sg-svm -volume dr-data -snapshot pre-failback-manual
     ```

---

### Bước 2: Thiết lập Reverse Resync (Tokyo -> Singapore) trên Singapore ONTAP

1. Từ terminal SSM của **EC2 Singapore (`dr-sg-storage-ec2`)**, SSH vào giao diện quản trị ONTAP của Singapore FSx:

```bash
ssh fsxadmin@<FSX_MANAGEMENT_IP_HOAC_DNS_SINGAPORE>
```

2. Kiểm tra quan hệ SnapMirror cũ giữa hai bên:

```text
snapmirror show -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data -fields state,status,last-transfer-end-timestamp
```

3. Kích hoạt đảo chiều đồng bộ hóa (**Tokyo -> Singapore**). Destination bây giờ là Singapore:

```text
snapmirror resync -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data
```

4. Theo dõi quá trình đồng bộ hoàn tất:

```text
snapmirror show -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data -fields state,status,healthy
```

*Kết quả mong đợi:* Cột `State` hiển thị `Snapmirrored`, `Status` hiển thị `Idle`, `Healthy` hiển thị `true`. Volume Singapore đang ở chế độ Data Protection (DP) và nhận delta blocks từ Tokyo.

---

### Bước 3: Dừng Writer Container trên EC2 Tokyo (Fencing Tokyo Writer)

1. Mở **AWS Global Accelerator Console** tại [https://console.aws.amazon.com/globalaccelerator/](https://console.aws.amazon.com/globalaccelerator/).
2. Chọn **`dr-storage-accelerator`** -> tab **Listeners** -> chọn **`Port 80 (TCP)`**.
3. Chọn nhóm endpoint **`ap-northeast-1`** (Tokyo) -> nhấp **Edit**:
   - Chỉnh **Traffic dial** từ `100` về **`0`**.
   - Bấm **Save changes**.
4. Mở **EC2 Console** tại Region **Tokyo (`ap-northeast-1`)** -> nhấp chọn **`dr-tokyo-storage-ec2`** -> bấm **Connect** (tab Session Manager).
5. Dừng container writer tại Tokyo để xả toàn bộ buffer vào storage:

```bash
docker stop file-service
```

---

### Bước 4: Final Update, Quiesce và Break trên Singapore ONTAP

1. Quay lại terminal ONTAP CLI của Singapore (từ SSM EC2 Singapore):
2. Thực hiện cập nhật những byte dữ liệu cuối cùng từ Tokyo sang Singapore:

```text
snapmirror update -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data
```

3. Tạm dừng chuyển dữ liệu (Quiesce):

```text
snapmirror quiesce -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data
```

4. Xác nhận trạng thái quan hệ là `Quiesced`:

```text
snapmirror show -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data -fields state,status
```

5. Phá vỡ quan hệ SnapMirror đảo chiều để thăng cấp Singapore trở lại Read-Write:

```text
snapmirror break -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data
```

*Kết quả mong đợi:* Cột `State` hiển thị `broken-off`. Volume `dr-data` trên Singapore đã trở lại thành Read-Write (RW).

---

### Bước 5: Kiểm tra Junction-Path và Mount Volume Singapore

1. Trên ONTAP CLI của Singapore, kiểm tra đường dẫn namespace:

```text
volume show -vserver dr-sg-svm -volume dr-data -fields junction-path
```

2. Nếu trường `junction-path` đang trống hoặc hiển thị `-`, thực hiện mount volume:

```text
volume mount -vserver dr-sg-svm -volume dr-data -junction-path /dr-data -active true
```

3. Xác nhận volume trực tuyến và export policy hợp lệ:

```text
volume show -vserver dr-sg-svm -volume dr-data -fields junction-path,state,type
vserver export-policy rule show -vserver dr-sg-svm -policyname default
```

*Kết quả mong đợi:* `junction-path` là `/dr-data`, `state` là `online`, `type` là `RW`. Thoát khỏi ONTAP CLI (`exit`) để về terminal SSM của EC2 Singapore.

---

### Bước 6: Mount NFS 4.1 và Khởi chạy File Service Container tại Singapore

1. Trên terminal SSM của EC2 Singapore (`dr-sg-storage-ec2`):

```bash
# Đảm bảo mount point tồn tại
sudo mkdir -p /mnt/dr-data

# Mount NFSv4.1 từ Singapore SVM
sudo mount -t nfs -o nfsvers=4.1 <SINGAPORE_SVM_NFS_DNS>:/dr-data /mnt/dr-data

# Cấu hình quyền sở hữu non-root 1000:1000 và mode 0770
sudo chown 1000:1000 /mnt/dr-data
sudo chmod 0770 /mnt/dr-data
stat -c 'owner=%u group=%g mode=%a path=%n' /mnt/dr-data
```

2. Khởi chạy container `file-service` với quyền non-root `UID:GID 1000:1000`:

```bash
docker run -d \
  --name file-service \
  --restart unless-stopped \
  -p 8080:8080 \
  -u 1000:1000 \
  -v /mnt/dr-data:/data \
  -e DATA_DIR=/data \
  <AWS_ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/dr-platform-file-service:v1.0.0
```

3. Kiểm tra tính sẵn sàng của service nội bộ:

```bash
curl -s http://localhost:8080/health
curl -s http://localhost:8080/ready
```

---

### Bước 7: Xác minh Target Group Singapore trên EC2 Console

1. Mở **EC2 Console** tại Region **Singapore (`ap-southeast-1`)**.
2. Tại menu trái, chọn **Target Groups** -> nhấp vào **`dr-sg-storage-tg`**.
3. Chọn tab **Targets**:
   - Đảm bảo instance **`dr-sg-storage-ec2`** tại Port `8080` hiển thị trạng thái **`Healthy`** (màu xanh lá).

---

### Bước 8: Khôi phục Traffic Dial trên AWS Global Accelerator Console

1. Mở lại **AWS Global Accelerator Console** tại [https://console.aws.amazon.com/globalaccelerator/](https://console.aws.amazon.com/globalaccelerator/).
2. Nhấp vào accelerator **`dr-storage-accelerator`**.
3. Chuyển sang tab **Listeners** -> chọn listener **`Port 80 (TCP)`**.
4. Cập nhật nhóm endpoint Singapore (`ap-southeast-1`):
   - Chọn checkbox `ap-southeast-1` -> bấm **Edit**.
   - Đổi **Traffic dial** thành **`100`** -> bấm **Save changes**.
5. Cập nhật nhóm endpoint Tokyo (`ap-northeast-1`):
   - Chọn checkbox `ap-northeast-1` -> bấm **Edit**.
   - Đổi **Traffic dial** thành **`0`** -> bấm **Save changes**.
6. Đợi Accelerator chuyển sang trạng thái **Deployed**.

---

### Bước 9: Dọn dẹp Reverse Relationship & Tái lập Quan hệ SnapMirror Chuẩn (Singapore -> Tokyo)

1. **Xóa quan hệ đảo chiều trên Singapore ONTAP CLI:**
   - Kết nối vào ONTAP CLI Singapore:
     ```text
     snapmirror delete -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data
     ```
2. **Giải phóng metadata trên Tokyo ONTAP CLI:**
   - Kết nối vào ONTAP CLI Tokyo (từ SSM EC2 Tokyo):
     ```text
     snapmirror release -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data
     ```
3. **Tái lập đồng bộ theo chiều chuẩn (Singapore Primary -> Tokyo Secondary/DP):**
   - Trên ONTAP CLI Tokyo, chạy resync với Singapore là source và Tokyo là destination:
     ```text
     snapmirror resync -source-path dr-sg-svm:dr-data -destination-path dr-tokyo-svm:dr-data-dr
     ```
   - Kiểm tra trạng thái khôi phục:
     ```text
     snapmirror show -source-path dr-sg-svm:dr-data -destination-path dr-tokyo-svm:dr-data-dr -fields state,status,healthy
     ```

*Kết quả mong đợi:* Cột `State` là `Snapmirrored`, `Status` là `Idle`. Mô hình bảo vệ chuẩn (Singapore là Primary RW, Tokyo là Secondary DP) đã được khôi phục nguyên vẹn 100%.

## 7. Xác minh

Singapore writer only; Tokyo DP/read-only; relationship normal direction `Snapmirrored`/`Idle`; data/integrity/traffic checks PASS.

## 8. Kết quả mong đợi

Normal topology restored without discarding Tokyo-authoritative changes.

## 9. Xử lý sự cố

- No common snapshot/resync rejected: stop; use backup/new volume migration plan.
- Divergent Singapore data: preserve snapshot; do not force resync before owner decision.
- Cutback validation fails: keep traffic Tokyo if it remains authoritative and safe.

## 10. Lưu ý bảo mật

Two-person verification for destructive direction. `vserver stop` affects the whole SVM; prefer application/ALB/mount fencing for this single-volume workload.

## 11. Lưu ý chi phí

Reverse/full transfers and retained snapshots can increase transfer/capacity charges.

## 12. Dọn dẹp / Quay lui

Before cutback, remain Tokyo-primary. After Singapore promotion, use a new controlled switchover; never improvise reverse resync.

## 13. Bằng chứng cần thu thập

Direction review, snapshots, relationship states, final marker, first Singapore write, GA response, restored normal relationship.

## 14. Lab tiếp theo

[LAB 26 - Unified DR Test](26-unified-dr-test.md).

Nguồn: [NetApp resync warning](https://docs.netapp.com/us-en/ontap-cli/snapmirror-resync.html), [reactivate original source](https://docs.netapp.com/us-en/ontap/data-protection/reactivate-original-source-volume-task.html), [NetApp volume mount](https://docs.netapp.com/us-en/ontap-cli/volume-mount.html), [AWS backups](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/using-backups.html).
