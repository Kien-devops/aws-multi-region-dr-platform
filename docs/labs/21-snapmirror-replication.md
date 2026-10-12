# LAB 21 - SnapMirror Replication

## 1. Mục tiêu

Thiết lập asynchronous volume-level SnapMirror Singapore -> Tokyo, monitor lag và chứng minh destination còn read-only.

## 2. Thành phần sẽ xây dựng

Cluster peer, SVM peer, relationship `dr-sg-svm:dr-data` -> `dr-tokyo-svm:dr-data-dr`, baseline initialization và schedule.

## 3. Bối cảnh kiến trúc

FSx for ONTAP hỗ trợ volume-level asynchronous SnapMirror. Lab này không dùng SVMDR, synchronous SnapMirror hoặc StrictSync.

## 4. Điều kiện tiên quyết

- LAB 04, 19, 20.
- Mọi source intercluster LIF kết nối được mọi destination intercluster LIF, hai chiều.
- Destination DP capacity >= source; credential/operator window được phê duyệt.

## 5. Quy ước đặt tên tài nguyên

Source `dr-sg-svm:dr-data`; destination `dr-tokyo-svm:dr-data-dr`; schedule tối thiểu `5min` chỉ khi ONTAP hiện hành cung cấp và tải cho phép.

### 6.1 Kiểm tra thông tin Intercluster LIFs và Định tuyến hai chiều

Trước khi thiết lập quan hệ SnapMirror, cần đối chiếu địa chỉ IP Intercluster giữa hai hệ thống tệp:

1. **Lấy IP Intercluster Singapore:**
   - Tại FSx Console ở **Singapore (`ap-southeast-1`)** -> nhấp vào `dr-sg-fsx-ontap` -> xem mục **Network & security** -> ghi lại danh sách **Intercluster IP addresses** (ví dụ: `10.10.11.x`, `10.10.12.y`).
2. **Lấy IP Intercluster Tokyo:**
   - Tại FSx Console ở **Tokyo (`ap-northeast-1`)** -> nhấp vào `dr-tokyo-fsx-ontap` -> ghi lại danh sách **Intercluster IP addresses** (ví dụ: `10.20.11.a`, `10.20.12.b`).
3. **Kiểm tra thông tuyến qua Peering:**
   - Mở Session Manager trên `dr-sg-storage-ec2`, chạy ping tới các Intercluster IP của Tokyo để đảm bảo VPC Peering và Security Group đã mở thông suốt:

```bash
ping -c 3 <TOKYO_INTERCLUSTER_IP_1>
nc -zv -w 3 <TOKYO_INTERCLUSTER_IP_1> 11105
```

### 6.2 Thiết lập Cluster Peering và SVM Peering

SnapMirror yêu cầu kết nối tin cậy giữa hai cluster và giữa hai Storage Virtual Machine (SVM):

#### Cách 1: Thiết lập qua AWS FSx Console (Replicate Volume)
1. Mở AWS Management Console tại **Singapore (`ap-southeast-1`)**.
2. Vào **Amazon FSx** -> chọn menu **Volumes** ở bên trái.
3. Tích chọn volume nguồn `dr-data`.
4. Nhấp vào menu **Actions** ở góc trên bên phải -> chọn **Create replication** (hoặc **Replicate with SnapMirror**).
5. Tại giao diện cấu hình replication:
   - **Destination**: Chọn **Another AWS Region** -> chọn **Asia Pacific (Tokyo) ap-northeast-1**.
   - **Destination file system**: Chọn `dr-tokyo-fsx-ontap`.
   - **Destination SVM**: Chọn `dr-tokyo-svm`.
   - **Destination volume name**: Nhập `dr-data-dr`.
   - **Replication schedule**: Chọn chu kỳ đồng bộ (ví dụ: `5 minutes` hoặc `15 minutes`).
6. Nhấp nút **Create replication**.

#### Cách 2: Thiết lập qua ONTAP CLI (Chuẩn NetApp)
Từ `dr-sg-storage-ec2`, SSH vào địa chỉ quản trị của FSx (`fsxadmin@<FSX_MANAGEMENT_IP>`):

```text
# 1. Tại Singapore: Khởi tạo cluster peering
dr-sg-fsx::> cluster peer create -peer-addrs <TOKYO_INTERCLUSTER_IPS>

# 2. Tại Tokyo: Chấp nhận cluster peering
dr-tokyo-fsx::> cluster peer create -peer-addrs <SG_INTERCLUSTER_IPS>

# 3. Thiết lập SVM Peering
dr-sg-fsx::> vserver peer create -vserver dr-sg-svm -peer-vserver dr-tokyo-svm -peer-cluster dr-tokyo-fsx -applications snapmirror
dr-tokyo-fsx::> vserver peer accept -vserver dr-tokyo-svm -peer-vserver dr-sg-svm
```

### 6.3 Khởi tạo quan hệ SnapMirror (Baseline Initialization)

Tại ONTAP CLI của hệ thống Tokyo (hoặc theo dõi tự động trên FSx Console nếu cấu hình qua Cách 1):

1. Tạo quan hệ SnapMirror trên cluster đích (Tokyo):

```text
dr-tokyo-fsx::> snapmirror create \
  -source-path dr-sg-svm:dr-data \
  -destination-path dr-tokyo-svm:dr-data-dr \
  -vserver dr-tokyo-svm \
  -throttle unlimited
```

2. Kích hoạt quá trình đồng bộ toàn bộ dữ liệu ban đầu (Baseline Transfer):

```text
dr-tokyo-fsx::> snapmirror initialize -destination-path dr-tokyo-svm:dr-data-dr
```

3. Theo dõi trạng thái hoàn tất:

```text
dr-tokyo-fsx::> snapmirror show -destination-path dr-tokyo-svm:dr-data-dr
```

Chờ cho đến khi cột **Mirror State** hiển thị là `Snapmirrored` và **Status** hiển thị là `Idle`.

### 6.4 Thiết lập Lịch đồng bộ tự động và Kiểm thử Marker File

1. Gán lịch trình đồng bộ định kỳ 5 phút/lần (nếu chưa gán):

```text
dr-tokyo-fsx::> snapmirror modify -destination-path dr-tokyo-svm:dr-data-dr -schedule 5min
```

2. Kiểm chứng ghi dữ liệu tại Singapore và đồng bộ sang Tokyo:
   - Trên `dr-sg-storage-ec2`:
     ```bash
     echo "dr-test-marker-$(date -u +%s)" | sudo tee /mnt/dr-data/snapmirror-marker.txt
     ```
   - Chạy lệnh cập nhật SnapMirror tức thì trên ONTAP CLI Tokyo:
     ```text
     dr-tokyo-fsx::> snapmirror update -destination-path dr-tokyo-svm:dr-data-dr
     ```
   - Xác nhận file marker đã được đồng bộ sang Tokyo và volume đích `dr-data-dr` ở trạng thái Read-only không thể bị ghi đè trực tiếp bởi client.

## 7. Xác minh

Relationship `Snapmirrored`, transfer `Idle`, last-transfer timestamp mới; destination không writable; schedule và actual lag được ghi riêng.

## 8. Kết quả mong đợi

File state replicate asynchronous tới Tokyo. Schedule là design configuration, không phải measured RPO.

## 9. Xử lý sự cố

- Peer unavailable: route/SG/NACL/DNS/intercluster LIF matrix.
- Initialize treo: events, capacity, credentials, takeover/reboot.
- Lag cao: source change rate, throughput, network, destination capacity và concurrent operations.

## 10. Lưu ý bảo mật

Giới hạn management/intercluster flows; audit ONTAP admin commands; không đưa peer passphrase/credential vào evidence.

## 11. Lưu ý chi phí

Cross-Region transfer, capacity, throughput và backup tính phí. Schedule ngắn tăng traffic/operational load.

## 12. Dọn dẹp / Quay lui

Trước xóa: quiesce khi phù hợp, delete destination relationship, release source relationship, sau đó mới xóa volume/peer.

## 13. Bằng chứng cần thu thập

Peer status, relationship fields, schedule, baseline duration, last transfer, marker read-only, CloudTrail/operator record.

## 14. Lab tiếp theo

[LAB 22 - File-service Deployment](22-file-service-deployment.md).

Nguồn: [AWS migration workflow](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/migrating-fsx-ontap-snapmirror.html), [scheduled replication](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/scheduled-replication.html).
