# LAB 21 - SnapMirror Replication

## 1. Mục tiêu

Thiết lập quan hệ đồng bộ bất đồng bộ (Asynchronous volume-level SnapMirror) giữa hệ thống lưu trữ **Singapore (Source RW)** sang **Tokyo (Destination DP)**, theo dõi độ trễ (SnapMirror Lag) và kiểm chứng tính toàn vẹn dữ liệu.

---

## 2. Bảng thông số tài nguyên thực tế đã triển khai

| Thông số | Region Singapore (`ap-southeast-1`) | Region Tokyo (`ap-northeast-1`) |
|---|---|---|
| **File System Name** | `dr-sg-fsx-ontap` | `dr-tokyo-fsx-ontap` |
| **File System ID** | `fs-0955146589825df51` | `fs-0104cc857c91c78e2` |
| **Management DNS** | `management.fs-0955146589825df51.fsx.ap-southeast-1.amazonaws.com` | `management.fs-0104cc857c91c78e2.fsx.ap-northeast-1.amazonaws.com` |
| **Management IP** | `10.10.12.163` | `10.20.11.183` |
| **Intercluster IPs** | `10.10.12.218`, `10.10.12.145` | `10.20.11.215`, `10.20.11.142` |
| **SVM Name** | `dr-sg-svm` (`svm-0d7a5a310c9ded152`) | `dr-tokyo-svm` (`svm-0c6499bac116da7a2`) |
| **SVM Management IP** | `10.10.12.156` | `10.20.11.230` |
| **Volume Name** | `drdata` (10 GiB, Type `RW`, Junction `/dr-data`) | `dr_data_dr` (10 GiB, Type `DP` - Secondary) |
| **SnapMirror Path** | `dr-sg-svm:drdata` (Source) | `dr-tokyo-svm:dr_data_dr` (Destination) |
| **Jumpbox / Truy cập** | Bất kỳ EKS Node Singapore qua SSM Session Manager | Bất kỳ EKS Node Tokyo qua SSM Session Manager |

> [!NOTE]
> NetApp ONTAP không cho phép ký tự gạch ngang `-` trong tên Volume, do đó tên volume thực tế là `drdata` (Singapore) và `dr_data_dr` (Tokyo).

---

## 3. Điều kiện tiên quyết và kiểm tra kết nối

### 3.1 Kiểm tra thông tuyến mạng Intercluster hai chiều

SnapMirror sử dụng cổng TCP `11104` và `11105` để trao đổi dữ liệu giữa các Intercluster LIFs thông qua VPC Peering (`pcx-0cbc2b7685a2cfe78`).

1. Mở AWS Systems Manager Session Manager vào một Node EKS tại **Singapore** (ví dụ node `i-03913ecfa2e401c69`).
2. Chạy kiểm tra kết nối tới các địa chỉ Intercluster IP của Tokyo:

```bash
# Ping kiểm tra định tuyến ICMP
ping -c 3 10.20.11.215
ping -c 3 10.20.11.142

# Kiểm tra mở cổng SnapMirror Intercluster (11104, 11105)
nc -zv -w 3 10.20.11.215 11104
nc -zv -w 3 10.20.11.215 11105
nc -zv -w 3 10.20.11.142 11105

# Kiểm tra cổng ONTAP HTTPS Management
nc -zv -w 3 10.20.11.183 443
```

---

## 4. Hướng dẫn thiết lập SnapMirror qua ONTAP CLI (Khuyên dùng)

Thiết lập qua CLI của NetApp ONTAP cho phép quan sát chi tiết từng bước xác thực, thiết lập mật khẩu mã hóa bắt tay và kiểm soát toàn diện.

### Bước 4.1: Đăng nhập vào ONTAP CLI của hai hệ thống

Từ node EC2 (được truy cập qua Session Manager):

```bash
# Đăng nhập vào FSx Singapore
ssh fsxadmin@management.fs-0955146589825df51.fsx.ap-southeast-1.amazonaws.com

# Đăng nhập vào FSx Tokyo
ssh fsxadmin@management.fs-0104cc857c91c78e2.fsx.ap-northeast-1.amazonaws.com
```
*(Mật khẩu là mật khẩu quản trị `fsxadmin` đã đặt khi tạo File System)*.

---

### Bước 4.2: Thiết lập Cluster Peering (Bắt tay cụm lưu trữ)

1. **Tại FSx Singapore CLI:** Khởi tạo yêu cầu kết nối tới Intercluster IP của Tokyo và đặt mật khẩu xác thực phiên (passphrase):
   ```text
   dr-sg-fsx::> cluster peer create -peer-addrs 10.20.11.215,10.20.11.142
   ```
   *Hệ thống sẽ yêu cầu nhập passphrase (ví dụ: `SnapMirrorPass123!`). Nhớ passphrase này để nhập vào bước sau.*

2. **Tại FSx Tokyo CLI:** Chấp nhận kết nối peering từ Intercluster IP của Singapore bằng cùng passphrase:
   ```text
   dr-tokyo-fsx::> cluster peer create -peer-addrs 10.10.12.218,10.10.12.145
   ```
   *Nhập chính xác passphrase đã đặt ở Singapore (`SnapMirrorPass123!`).*

3. **Kiểm tra trạng thái Cluster Peering:**
   ```text
   dr-sg-fsx::> cluster peer show
   ```
   *Kết quả mong đợi: Cột **Availability** hiển thị `Available` và **Authentication** hiển thị `ok`.*

---

### Bước 4.3: Thiết lập SVM Peering (Bắt tay Virtual Machine)

1. **Tại FSx Singapore CLI:** Cấp quyền kết nối cho SVM `dr-sg-svm` với SVM `dr-tokyo-svm`:
   ```text
   dr-sg-fsx::> vserver peer create -vserver dr-sg-svm -peer-vserver dr-tokyo-svm -peer-cluster FsxId0104cc857c91c78e2 -applications snapmirror
   ```
   *(Tên peer-cluster của Tokyo là `FsxId0104cc857c91c78e2`, xem bằng lệnh `cluster peer show`).*

2. **Tại FSx Tokyo CLI:** Chấp nhận lời mời peering:
   ```text
   dr-tokyo-fsx::> vserver peer accept -vserver dr-tokyo-svm -peer-vserver dr-sg-svm
   ```

3. **Kiểm tra trạng thái SVM Peering:**
   ```text
   dr-tokyo-fsx::> vserver peer show
   ```
   *Kết quả mong đợi: Cột **Peer State** hiển thị `peered`.*

---

### Bước 4.4: Tạo quan hệ SnapMirror (SnapMirror Create)

Quan hệ SnapMirror luôn được tạo và quản lý từ **Cluster Đích (Tokyo)**:

1. **Tại FSx Tokyo CLI:** Tạo quan hệ SnapMirror giữa volume nguồn `drdata` và volume đích `dr_data_dr`:
   ```text
   dr-tokyo-fsx::> snapmirror create \
     -source-path dr-sg-svm:drdata \
     -destination-path dr-tokyo-svm:dr_data_dr \
     -vserver dr-tokyo-svm \
     -throttle unlimited
   ```

2. **Xác nhận quan hệ đã được ghi nhận:**
   ```text
   dr-tokyo-fsx::> snapmirror show -destination-path dr-tokyo-svm:dr_data_dr
   ```
   *Lúc này cột **Mirror State** sẽ là `Uninitialized`.*

---

### Bước 4.5: Khởi tạo đồng bộ toàn bộ ban đầu (Baseline Initialization)

1. **Tại FSx Tokyo CLI:** Kích hoạt quá trình sao chép toàn bộ dữ liệu ban đầu:
   ```text
   dr-tokyo-fsx::> snapmirror initialize -destination-path dr-tokyo-svm:dr_data_dr
   ```

2. **Theo dõi tiến trình đồng bộ:**
   ```text
   dr-tokyo-fsx::> snapmirror show -destination-path dr-tokyo-svm:dr_data_dr
   ```
   *Trong quá trình truyền tải, cột **Status** sẽ báo `Transferring`.*

3. **Xác nhận hoàn tất Baseline:**
   Chờ vài phút cho quá trình đồng bộ hoàn thành, kiểm tra lại:
   ```text
   dr-tokyo-fsx::> snapmirror show -destination-path dr-tokyo-svm:dr_data_dr
   ```
   *Kết quả mong đợi:*
   - **Mirror State**: `Snapmirrored`
   - **Relationship Status**: `Idle`
   - **Healthy**: `true`

---

### Bước 4.6: Cấu hình lịch đồng bộ định kỳ (Schedule)

Gán lịch tự động đồng bộ mỗi 5 phút một lần để đảm bảo RPO $\le 5$ phút:

```text
dr-tokyo-fsx::> snapmirror modify -destination-path dr-tokyo-svm:dr_data_dr -schedule 5min
```

---

## 5. Hướng dẫn thiết lập qua AWS FSx Console (Cách giao diện)

Nếu không muốn dùng SSH / ONTAP CLI, bạn có thể thực hiện trực tiếp trên giao diện AWS Console:

1. Đăng nhập AWS Console tại **Region Singapore (`ap-southeast-1`)**.
2. Vào dịch vụ **Amazon FSx** -> chọn **Volumes** ở menu bên trái.
3. Nhấp chọn volume nguồn `drdata`.
4. Nhấp nút **Actions** ở góc trên bên phải -> chọn **Create replication** (hoặc **Replicate with SnapMirror**).
5. Điền cấu hình Replication:
   - **Destination**: Chọn *Another AWS Region* -> Chọn **Asia Pacific (Tokyo) ap-northeast-1**.
   - **Destination file system**: Chọn `dr-tokyo-fsx-ontap` (`fs-0104cc857c91c78e2`).
   - **Destination storage virtual machine**: Chọn `dr-tokyo-svm`.
   - **Destination volume**: Chọn *Existing volume* -> Chọn `dr_data_dr` (hoặc chọn tạo mới nếu chưa có).
   - **Replication schedule**: Chọn `5 minutes` (hoặc `15 minutes`).
6. Nhấp nút **Create replication**. Hệ thống AWS FSx sẽ tự động thực hiện cluster peering, SVM peering và kích hoạt baseline initialization ngầm.

---

## 6. Kiểm chứng đồng bộ dữ liệu (Marker Verification)

Để chứng minh dữ liệu mới tạo tại Singapore tự động replicate sang Tokyo:

1. **Ghi tệp kiểm thử tại Singapore:**
   Truy cập giao diện web `http://k8s-app2-app2ingr-4a5ceed8d3-1408847069.ap-southeast-1.elb.amazonaws.com/files` hoặc chạy lệnh trực tiếp trên EKS node:
   ```bash
   echo "snapmirror-test-marker-$(date -u +%Y%m%d-%H%M%S)" | sudo tee /mnt/dr-data/snapmirror-marker.txt
   ```

2. **Kích hoạt đồng bộ tức thì trên Tokyo CLI (hoặc chờ 5 phút):**
   ```text
   dr-tokyo-fsx::> snapmirror update -destination-path dr-tokyo-svm:dr_data_dr
   ```

3. **Kiểm tra độ trễ (Lag Time) và thời gian truyền tải gần nhất:**
   ```text
   dr-tokyo-fsx::> snapmirror show -destination-path dr-tokyo-svm:dr_data_dr -fields last-transfer-end-timestamp,lag-time,healthy
   ```

4. **Chứng minh Volume Tokyo là Read-Only (DP):**
   Volume `dr_data_dr` ở trạng thái Snapmirrored không cho phép ghi trực tiếp, bảo vệ dữ liệu dự phòng khỏi bị xung đột hay sửa đổi ngoài ý muốn cho đến khi thực hiện quy trình Failover có kiểm soát.

---

## 7. Bằng chứng cần thu thập

- [x] Output `cluster peer show` (`Availability: Available`, `Authentication: ok`).
- [x] Output `vserver peer show` (`Peer State: peered`).
- [x] Output `snapmirror show -destination-path dr-tokyo-svm:dr_data_dr`:
  - `Mirror State`: `Snapmirrored`
  - `Status`: `Idle`
  - `Healthy`: `true`
  - `Lag Time`: `< 5 minutes` (Đạt: ~22s)
  - `Schedule`: `5min`
- [x] Ghi file marker test `/mnt/dr-data/snapmirror-marker.txt` tại Singapore và đồng bộ thành công sang Tokyo (`last-transfer-type: update`).

---

## 8. Xử lý sự cố thường gặp (Troubleshooting)

- **Lỗi `cluster peer create` không tìm thấy peer**:
  - Kiểm tra lại Security Group `dr-sg-fsx-sg` và `dr-tokyo-fsx-sg` đã mở cổng `11104`, `11105`, `10000`, `443` cho dải mạng CIDR của nhau chưa.
  - Kiểm tra route table của VPC Peering `pcx-0cbc2b7685a2cfe78` đã add route `10.10.0.0/16` $\leftrightarrow$ `10.20.0.0/16` chưa.
- **Lỗi xác thực Passphrase**:
  - Dùng lệnh `cluster peer modify -peer-cluster <CLUSTER_NAME>` để nhập lại passphrase trên cả hai phía.
- **Lỗi Volume Destination đã có dữ liệu hoặc không phải Type DP**:
  - SnapMirror yêu cầu volume đích phải là loại `DP` (`OntapVolumeType = DP`), dung lượng phải $\ge$ dung lượng volume nguồn (10 GiB).

---

## 9. Lab tiếp theo

Sau khi SnapMirror ở trạng thái `Snapmirrored` và `Idle`, chuyển sang:
👉 [LAB 22 - File-service Deployment](22-file-service-deployment.md) hoặc [LAB 23 - ONTAP Planned Switchover](23-ontap-planned-switchover.md).
