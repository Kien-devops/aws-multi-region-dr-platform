# LAB 24 - ONTAP Unplanned Failover

## 1. Mục tiêu

Promote Tokyo khi Singapore unavailable, chấp nhận khả năng mất writes chưa replicate và đo storage RPO.

## 2. Thành phần sẽ xây dựng

Incident declaration, old-primary fencing, lag assessment, authorized break, Tokyo activation, evidence handoff.

## 3. Bối cảnh kiến trúc

Asynchronous replication không bảo đảm last acknowledged write đã tới Tokyo. `last acknowledged - latest recovered` là observed data loss.

## 4. Điều kiện tiên quyết

- Tokyo FSx/EC2/ALB healthy; latest relationship evidence accessible.
- Incident Commander và data-loss authority được chỉ định.
- Singapore cannot safely serve writes; fencing options reviewed.

## 5. Quy ước đặt tên tài nguyên

Incident `<INCIDENT_ID>`; UTC timeline; destination `dr-tokyo-svm:dr-data-dr`.

## 6. Các bước triển khai

### Bước 1: Khai báo Incident và Fence Writer Singapore trên AWS Console

> [!CAUTION]
> **Nguyên tắc cô lập tức thì (Immediate Fencing):** Trong sự cố đột ngột, việc đầu tiên là cô lập lập tức chiều ghi tại Singapore trên tầng định tuyến toàn cầu để chặn triệt để client gửi request vào primary lỗi hoặc sinh split-brain.

1. **Khóa ingress traffic trên AWS Global Accelerator Console:**
   - Mở **AWS Global Accelerator Console** tại [https://console.aws.amazon.com/globalaccelerator/](https://console.aws.amazon.com/globalaccelerator/) (Global service).
   - Trong bảng Accelerators, nhấp vào tên **`dr-storage-accelerator`**.
   - Chuyển sang tab **Listeners**, nhấp chọn listener **`Port 80 (TCP)`**.
   - Tại danh sách **Endpoint groups**, tìm nhóm endpoint **`ap-southeast-1`** (Singapore):
     - Nhấp chọn checkbox bên cạnh `ap-southeast-1` và bấm nút **Edit** (góc trên bên phải bảng).
     - Tại mục **Traffic dial**, kéo thanh trượt hoặc gõ đổi giá trị từ `100` thành **`0`**.
     - Nhấp nút cam **Save changes**.
   - Chờ trạng thái Accelerator cập nhật sang **Deployed**.

2. **Dừng writer container / instance tại Singapore (nếu console/mạng còn phản hồi):**
   - Đổi region sang **Singapore (`ap-southeast-1`)** trên thanh Navigation bar.
   - Truy cập **EC2 Console** -> mục **Instances**.
   - Tìm chọn instance **`dr-sg-storage-ec2`**:
     - Nhấp menu dropdown **Instance state** -> chọn **Stop instance**.
     - Nhấp **Stop** trong hộp thoại xác nhận.
   - Hoặc tại **Target Groups**, chọn **`dr-sg-storage-tg`** -> tab **Targets** -> chọn instance và bấm **Deregister**.

---

### Bước 2: Kiểm tra trạng thái FSx ONTAP Tokyo trên AWS Console

1. Chuyển region sang **Tokyo (`ap-northeast-1`)** trên thanh Navigation bar.
2. Mở dịch vụ **Amazon FSx** tại [https://console.aws.amazon.com/fsx/](https://console.aws.amazon.com/fsx/).
3. Tại menu bên trái, chọn **File systems** -> nhấp vào **`dr-tokyo-fsx`**.
4. Chuyển sang tab **Storage virtual machines**:
   - Xác nhận SVM **`dr-tokyo-svm`** có trạng thái **Created** (màu xanh lá).
   - Nhấp vào tên `dr-tokyo-svm`, chuyển sang tab **Volumes**:
     - Tìm volume **`dr-data-dr`**.
     - Xác nhận volume đang ở trạng thái **Created**, loại volume là **DP (Data Protection)**.
   - Ghi lại **NFS DNS name** hoặc **IP address** của SVM hiển thị tại tab **Endpoints** (ví dụ: `svm-0xxxxxxxxxxxx.fs-0xxxxxxxxxxxx.fsx.ap-northeast-1.amazonaws.com`).

---

### Bước 3: Đánh giá Lag và Kích hoạt Emergency SnapMirror Break

1. Mở **EC2 Console** tại Region **Tokyo (`ap-northeast-1`)** -> mục **Instances**.
2. Nhấp chọn instance **`dr-tokyo-storage-ec2`** -> bấm nút **Connect** ở thanh công cụ trên cùng.
3. Chuyển sang tab **Session Manager** -> bấm nút cam **Connect** để mở terminal SSM.
4. Từ terminal SSM, kết nối SSH vào quản trị ONTAP của Tokyo FSx:

```bash
ssh fsxadmin@<FSX_MANAGEMENT_IP_HOAC_DNS_TOKYO>
```

5. Kiểm tra tình trạng replication và điểm dữ liệu cuối cùng được replicate:

```text
snapmirror show -destination-path dr-tokyo-svm:dr-data-dr -fields state,status,last-transfer-end-timestamp,lag-time
```

- Ghi lại mốc thời gian `last-transfer-end-timestamp` và `lag-time`.
- Nhận phê duyệt chính thức (Authorization) từ Incident Commander để chấp nhận độ trễ dữ liệu này.

6. Thực hiện cưỡng bức phá vỡ quan hệ SnapMirror (Emergency Break) mà không chờ sync:

```text
snapmirror break -destination-path dr-tokyo-svm:dr-data-dr
```

7. Xác minh trạng thái quan hệ đã chuyển sang `Broken-off`:

```text
snapmirror show -destination-path dr-tokyo-svm:dr-data-dr -fields state,status
```

*Kết quả mong đợi:* Cột `State` hiển thị `broken-off`, `Status` hiển thị `idle`. Volume `dr-data-dr` đã được chuyển sang chế độ Read-Write (RW).

---

### Bước 4: Kiểm tra Junction-Path và Export Policy trên Tokyo ONTAP CLI

1. Trên giao diện ONTAP CLI của Tokyo, kiểm tra junction-path của volume vừa break:

```text
volume show -vserver dr-tokyo-svm -volume dr-data-dr -fields junction-path
```

2. Nếu trường `junction-path` đang trống hoặc hiển thị `-`, thực hiện mount volume vào namespace nội bộ của SVM:

```text
volume mount -vserver dr-tokyo-svm -volume dr-data-dr -junction-path /dr-data -active true
```

3. Xác nhận lại trạng thái volume và export-policy rule:

```text
volume show -vserver dr-tokyo-svm -volume dr-data-dr -fields junction-path,state,type
vserver export-policy rule show -vserver dr-tokyo-svm -policyname default
```

*Kết quả mong đợi:* `junction-path` là `/dr-data`, `state` là `online`, `type` là `RW`. Thoát khỏi ONTAP CLI (`exit`) để quay lại SSM shell của EC2 Tokyo.

---

### Bước 5: Mount NFS 4.1 lên EC2 Tokyo và Kiểm tra Quyền Non-root

1. Tại terminal SSM của EC2 Tokyo (`dr-tokyo-storage-ec2`), thực hiện mount volume và phân quyền an toàn:

```bash
# Tạo mount point
sudo mkdir -p /mnt/dr-data

# Mount NFSv4.1 từ Tokyo SVM
sudo mount -t nfs -o nfsvers=4.1 <TOKYO_SVM_NFS_DNS>:/dr-data /mnt/dr-data

# Kiểm tra mount thành công
df -hT /mnt/dr-data

# Cấu hình quyền sở hữu non-root 1000:1000 và mode 0770 (tuyệt đối không dùng chmod 777)
sudo chown 1000:1000 /mnt/dr-data
sudo chmod 0770 /mnt/dr-data
stat -c 'owner=%u group=%g mode=%a path=%n' /mnt/dr-data
```

2. Kiểm tra đọc ghi non-root trên Host:

```bash
sudo -u '#1000' -g '#1000' sh -c 'umask 0007; printf "host-probe-emergency" > /mnt/dr-data/.host-rw-probe; test "$(cat /mnt/dr-data/.host-rw-probe)" = "host-probe-emergency"; rm /mnt/dr-data/.host-rw-probe'
echo "Host probe status: $?"
```

---

### Bước 6: Khởi chạy File Service Container trên EC2 Tokyo

1. Khởi chạy container `file-service` với quyền non-root `UID:GID 1000:1000`:

```bash
docker run -d \
  --name file-service \
  --restart unless-stopped \
  -p 8080:8080 \
  -u 1000:1000 \
  -v /mnt/dr-data:/data \
  -e DATA_DIR=/data \
  <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-1.amazonaws.com/dr-platform-file-service:v1.0.0
```

2. Kiểm tra health check của container qua curl nội bộ:

```bash
curl -s http://localhost:8080/health
curl -s http://localhost:8080/ready
```

*Kết quả:* Cả hai endpoint đều trả về HTTP 200 `{"status":"ok"}`.

---

### Bước 7: Xác minh Target Group Tokyo trên EC2 Console

1. Mở **EC2 Console** tại Region **Tokyo (`ap-northeast-1`)**.
2. Tại menu bên trái, cuộn xuống mục **Load Balancing** -> chọn **Target Groups**.
3. Nhấp vào target group **`dr-tokyo-storage-tg`**.
4. Chuyển sang tab **Targets**:
   - Quan sát danh sách registered targets.
   - Instance **`dr-tokyo-storage-ec2`** tại Port `8080` phải chuyển từ `Initial` sang **`Healthy`** (màu xanh lá).

---

### Bước 8: Chuyển hướng Lưu lượng trên AWS Global Accelerator Console

1. Mở lại **AWS Global Accelerator Console** tại [https://console.aws.amazon.com/globalaccelerator/](https://console.aws.amazon.com/globalaccelerator/).
2. Nhấp vào accelerator **`dr-storage-accelerator`**.
3. Chuyển sang tab **Listeners** -> chọn listener **`Port 80 (TCP)`**.
4. Trong danh sách **Endpoint groups**, tìm nhóm **`ap-northeast-1`** (Tokyo):
   - Nhấp chọn checkbox bên cạnh `ap-northeast-1` -> bấm nút **Edit** ở góc trên bảng.
   - Tại mục **Traffic dial**, đổi giá trị từ `0` thành **`100`**.
   - Bấm nút cam **Save changes**.
5. Chờ trạng thái Accelerator hiển thị **Deployed**.

---

### Bước 9: Đo lường RTO và RPO Thực tế

1. Gửi request tạo file mới thông qua Global IP của Storage Accelerator:

```bash
STORAGE_GA_IP="<GLOBAL_ACCELERATOR_STATIC_IP>"
curl -X POST http://${STORAGE_GA_IP}/files -H "Content-Type: application/json" -d '{"filename":"failover-marker.txt","content":"tokyo-recovered"}'
curl -s http://${STORAGE_GA_IP}/files/failover-marker.txt
```

2. Xác định mốc thời gian:
   - **$T_0$**: Thời điểm ghi nhận sự cố Singapore và bắt đầu failover.
   - **$T_4$**: Thời điểm request ghi file đầu tiên thành công trên Tokyo.
   - **RTO thực tế** = $T_4 - T_0$.
3. Xác định chênh lệch dữ liệu (RPO):
   - So sánh marker cuối cùng mà client tại Singapore ghi nhận trước khi ngắt với các marker hiện có trong thư mục `/mnt/dr-data/` trên Tokyo.
   - Ghi nhận chính xác số byte / số marker bị mất (Storage RPO thực tế).

---

### Bước 10: Duy trì Fencing Singapore

> [!WARNING]
> Khi Singapore phục hồi nguồn điện hoặc mạng, **tuyệt đối không mở lại** Traffic dial hay start lại container tại Singapore. Singapore hiện tại chứa dữ liệu cũ và phân nhánh so với Tokyo. Bắt buộc giữ nguyên trạng thái cô lập cho đến khi thực hiện quy trình Failback có kiểm soát tại LAB 25.

## 7. Xác minh

One writer only; Tokyo write/read/delete/verify PASS; recovered latest marker captured; old primary cannot accept writes.

## 8. Kết quả mong đợi

Service restored in Tokyo. Data gap may exist and must be reported, never hidden as `RPO = 0`.

## 9. Xử lý sự cố

- Destination inconsistent/unavailable: do not fabricate recovery; restore from backup or escalate.
- Singapore returns: do not route back or resync automatically.
- Break command uncertain: stop and verify destination path/source direction before retry.

## 10. Lưu ý bảo mật

Emergency access remains time-bound and logged. Preserve CloudTrail, ONTAP audit and application logs.

## 11. Lưu ý chi phí

Incident operation does not stop resources; backup/forensic retention can increase cost.

## 12. Dọn dẹp / Quay lui

No instant rollback. Stabilize Tokyo, preserve snapshots, then use LAB 25.

## 13. Bằng chứng cần thu thập

T0, fencing, last transfer, authorization, break, T4 first Tokyo write, marker gap, integrity result.

## 14. Lab tiếp theo

[LAB 25 - ONTAP Failback](25-ontap-failback.md).

Nguồn: [AWS SnapMirror cutover](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/migrating-fsx-ontap-snapmirror.html), [NetApp volume mount](https://docs.netapp.com/us-en/ontap-cli/volume-mount.html), [AWS Linux mount](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/attach-linux-client.html).
