# Runbook: Quy Trình Failback Về Singapore (DR Failback to Singapore)

> **Mục đích:** Hướng dẫn quy trình đưa hệ thống từ Tokyo (`ap-northeast-1`) trở về lại vùng chính Singapore (`ap-southeast-1`) một cách an toàn, có kiểm soát và **hoàn toàn không làm mất mát dữ liệu phát sinh trong thời gian chạy tại Tokyo**.

---

## 1. Điều Kiện Tiên Quyết Bắt Buộc (Mandatory Preconditions)

> [!CAUTION]
> Tuyệt đối **KHÔNG** bắt đầu quá trình Failback nếu chưa thỏa mãn toàn bộ các điều kiện sau:
> - [ ] Vùng Singapore đã hoàn toàn ổn định liên tục ít nhất **30 phút** (không còn hiện tượng chập chờn mạng, sụt nguồn hoặc lỗi API AWS). Nếu phát sinh lỗi trong 30 phút này, đồng hồ đếm thời gian được reset lại từ đầu.
> - [ ] Cụm EKS `dr-sg-eks` và Managed Node Group `dr-sg-workers` đã ở trạng thái `ACTIVE` và các nodes đều `Ready`.
> - [ ] Toàn bộ 4 microservices của `app2` tại Singapore đang chạy đủ 2 replicas (`Running 1/1`) và sẵn sàng nhận kết nối.
> - [ ] Cơ sở dữ liệu Aurora tại Singapore đã được thêm lại vào Global Database và đóng vai trò **Secondary Region** (nhận replication từ Tokyo).
> - [ ] **Replication Lag** từ Tokyo sang Singapore đã giảm về mức an toàn: `AuroraGlobalDBReplicationLag < 1000 ms`.
> - [ ] Đã hoàn tất việc sao lưu nhanh (Snapshot) dữ liệu tại Tokyo trước khi thực hiện chuyển đổi (`app2-tokyo-pre-failback`).

---

## 2. Quy Trình Thao Tác Từng Bước (Step-by-Step Failback Procedure)

### Bước 1: Sao lưu An toàn tại Tokyo
Tạo một snapshot khẩn cấp trên cụm Aurora Tokyo để làm phương án cứu hộ nếu có lỗi bất ngờ xảy ra:
1. Mở AWS Console -> Dịch vụ **RDS** tại region **ap-northeast-1 (Tokyo)**.
2. Chọn cụm cơ sở dữ liệu `app2-tokyo-db`.
3. Chọn **Actions** -> Chọn **Take snapshot**.
4. Đặt tên snapshot: `app2-tokyo-pre-failback`.
5. Đợi snapshot chuyển trạng thái `Available`.

### Bước 2: Kiểm tra Độ trễ Đồng bộ (Verify Replication Lag)
1. Mở AWS Console -> RDS -> Chọn cụm Global Database `app2-global-db`.
2. Kiểm tra thông số **Replication lag** của cụm Singapore (`app2-sg-db`).
3. Giá trị phải hiển thị `0 ms` hoặc dưới `1000 ms`. Nếu lag còn cao, phải đợi cho tới khi cụm Singapore bắt kịp hoàn toàn dữ liệu mới nhất được ghi tại Tokyo.

### Bước 3: Thực hiện Switchover Database Có Kế Hoạch (Zero Data Loss)
Vì cả 2 vùng lúc này đều đang hoạt động và có kết nối, ta sử dụng tính năng **Planned Switchover**:
1. Tại AWS Console RDS, chọn cụm Global Database `app2-global-db`.
2. Chọn menu **Actions** -> Chọn **Switch over global database**.
3. Chọn vùng đích: `app2-sg-db (ap-southeast-1)`.
4. Nhấn **Confirm**.
5. Hệ thống RDS sẽ:
   - Tạm dừng ghi trên cụm Tokyo trong vài giây để xả sạch transaction logs sang Singapore.
   - Thăng cấp cụm Singapore (`app2-sg-db`) thành **Primary Cluster (Writer)**.
   - Chuyển cụm Tokyo (`app2-tokyo-db`) thành **Secondary Cluster (Read-Only)**.
6. Xác nhận cụm Singapore hiển thị vai trò `Primary` và trạng thái `Available`.

### Bước 4: Chuyển Dần Lưu Lượng Mạng Bằng Global Accelerator
Để tránh sốc tải cho hạ tầng Singapore, thực hiện chuyển đổi lưu lượng theo từng bước (Canary Traffic Shift):
1. Mở AWS Console -> Dịch vụ **AWS Global Accelerator** -> Chọn `app2-global`.
2. Chọn Listener port 80 -> Edit Endpoint Groups.
3. **Pha 1 (Kiểm thử 20%):**
   - Đặt Traffic dial cho Singapore = `20%`.
   - Đặt Traffic dial cho Tokyo = `100%`.
   - Theo dõi lỗi 5xx trên CloudWatch Dashboard trong 5 phút.
4. **Pha 2 (Chuyển đổi hoàn toàn 100%):**
   - Đặt Traffic dial cho Singapore = `100%`.
   - Đặt Traffic dial cho Tokyo = `0%`.
   - Chọn **Save changes**.

### Bước 5: Xác Thực Hoạt Động Trên Vùng Singapore
1. Kiểm tra request health check từ bên ngoài:
   ```bash
   curl -s http://<GLOBAL_ACCELERATOR_IP>/health | jq .
   ```
   *Xác nhận trả về `"region": "ap-southeast-1"`.*
2. Kiểm tra dữ liệu đơn hàng đã ghi trong thời gian chạy tại Tokyo vẫn tồn tại:
   ```bash
   curl -s http://<GLOBAL_ACCELERATOR_IP>/api/v1/orders | jq .
   ```
3. Thực hiện transaction ghi dữ liệu thử nghiệm tại Singapore:
   ```bash
   curl -X POST http://<GLOBAL_ACCELERATOR_IP>/api/v1/orders \
     -H "Content-Type: application/json" \
     -d '{"item_id":"test-item","quantity":1,"marker":"FAILBACK_VERIFICATION"}'
   ```
   *Xác nhận trả về HTTP 201 Created.*

### Bước 6: Đưa Vùng Tokyo Trở Về Trạng Thái Warm Standby
Sau khi hệ thống tại Singapore đã chạy ổn định ít nhất 15 phút:
1. Thu hẹp số lượng Pods tại Tokyo về mức tiết kiệm chi phí (1 replica mỗi service):
   ```bash
   kubectl --context tokyo scale deployment -n app2 --replicas=1 --all
   ```
2. Đảm bảo 1 replica của mỗi service vẫn tiếp tục chạy để giữ trạng thái Warm Standby sẵn sàng cho lần diễn tập tiếp theo.
3. Đóng ticket sự cố và cập nhật báo cáo diễn tập.
