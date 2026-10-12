# LAB 23 - ONTAP Planned Switchover

## 1. Mục tiêu

Chuyển file workload có kế hoạch sang Tokyo, không split-brain, với final synchronization.

## 2. Thành phần sẽ xây dựng

Change record, write fence, final update, quiesce/break, Tokyo RW verification và traffic shift.

## 3. Bối cảnh kiến trúc

```text
stop SG writes -> update -> verify -> quiesce -> break Tokyo -> Tokyo RW -> shift traffic
```

## 4. Điều kiện tiên quyết

- LAB 21-22; relationship `Snapmirrored`/`Idle`; both Regions healthy.
- Approved window, operator/reviewer, rollback point, last acknowledged sequence recorded.
- Aurora switchover is separate; coordinate only if unified exercise requires both.

## 5. Quy ước đặt tên tài nguyên

Incident/change ID `<CHANGE_ID>`; timestamps UTC; source `dr-sg-svm:dr-data`; destination `dr-tokyo-svm:dr-data-dr`.

### 6.1 Cô lập luồng ghi tại Singapore (Write-Fencing)

Để đảm bảo không xảy ra hiện tượng Split-Brain (hai bên cùng ghi dữ liệu), bước đầu tiên bắt buộc phải cô lập hoàn toàn luồng ghi cũ:

1. **Hạ lưu lượng trên Storage Global Accelerator:**
   - Mở dịch vụ **AWS Global Accelerator** Console -> chọn `dr-file-global-accelerator`.
   - Vào tab **Listeners** -> chọn Listener cổng `80` -> tại bảng **Endpoint groups**, tích chọn nhóm **Singapore (`ap-southeast-1`)**.
   - Nhấp **Edit endpoint group** -> chỉnh **Traffic dial (%)** về `0` -> nhấp **Save changes**.
2. **Dừng Container File-Service tại Singapore:**
   - Mở Session Manager vào `dr-sg-storage-ec2`.
   - Dừng container để xả hết các tiến trình ghi đang dở dang:
     ```bash
     docker stop file-service
     docker ps -a
     ```
   - Xác nhận cổng 8080 đã đóng và không còn tiến trình nào truy xuất `/mnt/dr-data`.

### 6.2 Thực hiện SnapMirror Final Update và Break Mirror tại Tokyo

Thực hiện đồng bộ nốt các byte dữ liệu cuối cùng từ Singapore sang Tokyo trước khi bẻ gãy liên kết sao chép (Break):

1. Từ Session Manager của `dr-tokyo-storage-ec2`, kết nối SSH vào quản trị FSx Tokyo (`fsxadmin@<TOKYO_FSX_MANAGEMENT_IP>`):
2. Thực thi lệnh cập nhật đồng bộ cuối cùng:

```text
dr-tokyo-fsx::> snapmirror update -destination-path dr-tokyo-svm:dr-data-dr
```

3. Chờ trạng thái chuyển sang `Snapmirrored` và `Idle`:

```text
dr-tokyo-fsx::> snapmirror show -destination-path dr-tokyo-svm:dr-data-dr -fields state,status,last-transfer-end-timestamp
```

4. Tạm dừng quan hệ nhân bản (Quiesce):

```text
dr-tokyo-fsx::> snapmirror quiesce -destination-path dr-tokyo-svm:dr-data-dr
```

5. Thăng cấp volume Tokyo từ Data Protection (DP) thành Read/Write bằng lệnh **Break**:

```text
dr-tokyo-fsx::> snapmirror break -destination-path dr-tokyo-svm:dr-data-dr
```

6. Kiểm tra lại: Cột **Mirror State** sẽ chuyển sang `Broken-off` và kiểu volume `dr-data-dr` đã trở thành **Read/Write (RW)** độc lập.

### 6.3 Kích hoạt Junction Path và Mount NFS trên EC2 Tokyo

1. Tại ONTAP CLI của Tokyo, kiểm tra trạng thái Junction path:

```text
dr-tokyo-fsx::> volume show -vserver dr-tokyo-svm -volume dr-data-dr -fields junction-path
```

Nếu trường `junction-path` đang trống, kích hoạt gắn đường dẫn NFS:

```text
dr-tokyo-fsx::> volume mount -vserver dr-tokyo-svm -volume dr-data-dr -junction-path /dr-data -active true
```

2. Mở Session Manager trên `dr-tokyo-storage-ec2`, mount thư mục `/mnt/dr-data`:

```bash
sudo mkdir -p /mnt/dr-data
sudo mount -t nfs -o nfsvers=4.1 <TOKYO_SVM_NFS_DNS>:/dr-data /mnt/dr-data
mount | grep /mnt/dr-data

# Đảm bảo phân quyền non-root UID 1000
sudo chown 1000:1000 /mnt/dr-data
sudo chmod 0770 /mnt/dr-data

# Thử nghiệm ghi thực tế bằng user 1000
sudo -u '#1000' -g '#1000' sh -c 'umask 0007; printf tokyo-rw-probe > /mnt/dr-data/.tokyo-rw-probe; test "$(cat /mnt/dr-data/.tokyo-rw-probe)" = tokyo-rw-probe; rm /mnt/dr-data/.tokyo-rw-probe'
echo "Tokyo FSx Volume is now Read/Write ACTIVE!"
```

### 6.4 Khởi động File-Service tại Tokyo và Chuyển dịch lưu lượng

1. Trên `dr-tokyo-storage-ec2`, khởi động container:

```bash
docker restart file-service
# Kiểm tra endpoint sẵn sàng
curl -fsS http://localhost:8080/ready
# Kết quả mong đợi: {"status":"ready","writable":true,...}
```

2. Chuyển lưu lượng người dùng trên **Storage Global Accelerator**:
   - Truy cập **AWS Global Accelerator** Console -> `dr-file-global-accelerator`.
   - Tab **Listeners** -> chọn Listener cổng 80 -> tại **Endpoint groups**:
     - Chọn nhóm **Tokyo (`ap-northeast-1`)** -> **Edit endpoint group** -> chỉnh **Traffic dial (%)** thành `100` -> **Save changes**.
     - Đảm bảo nhóm **Singapore (`ap-southeast-1`)** vẫn giữ nguyên Traffic dial là `0`.
3. Kiểm tra phản hồi qua Storage Global Accelerator:

```bash
curl -sS -H 'Connection: close' http://<STORAGE_GA_DNS_NAME>/health
curl -sS -H 'Connection: close' http://<STORAGE_GA_DNS_NAME>/ready
```

## 7. Xác minh

Tokyo volume RW; first successful storage event/file write; integrity PASS; GA request mới tới Tokyo; Singapore write bị từ chối.

## 8. Kết quả mong đợi

Tokyo là writer duy nhất. Planned loss kỳ vọng tối thiểu nhưng chỉ report measured RPO từ marker thực tế.

## 9. Xử lý sự cố

- Final update lỗi: không break; khôi phục Singapore nếu source còn an toàn.
- Tokyo mount/write lỗi sau break: giữ traffic fenced; sửa export/junction/SG trước khi mở writes.
- Hai phía writable: emergency fence cả hai, chọn authoritative side, bảo toàn snapshot/evidence.

## 10. Lưu ý bảo mật

Break/quiesce quyền cao; audit operator/reviewer. Không gửi credential trong ticket/screenshots.

## 11. Lưu ý chi phí

Không thay đổi đáng kể; transfer/update và resources hai Region vẫn tính phí.

## 12. Dọn dẹp / Quay lui

Trước break có thể hủy maintenance và resume Singapore. Sau break, không gọi đó là rollback; dùng LAB 25 vì Tokyo đã authoritative.

## 13. Bằng chứng cần thu thập

Write-fence proof, last sequence, relationship states/timestamps, break approval, first Tokyo write, GA response.

## 14. Lab tiếp theo

[LAB 24 - ONTAP Unplanned Failover](24-ontap-unplanned-failover.md) cho drill riêng, hoặc [LAB 25](25-ontap-failback.md) để trở về Singapore.

Nguồn: [AWS Linux mount](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/attach-linux-client.html), [AWS SnapMirror cutover](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/migrating-fsx-ontap-snapmirror.html), [NetApp volume mount](https://docs.netapp.com/us-en/ontap-cli/volume-mount.html).
