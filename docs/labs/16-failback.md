# LAB 16 - Quy Trình Khôi Phục Ngược Về Singapore (Failback Procedure)

## 1. Overview & Objective

Sau khi một sự cố thảm họa tại vùng chính Singapore (`ap-southeast-1`) được khắc phục và hệ sinh thái hạ tầng AWS đã hồi phục hoàn toàn, đội ngũ kỹ thuật đối mặt với thách thức lớn: **Làm thế nào để đưa toàn bộ hoạt động của hệ thống trở lại Singapore mà không làm mất mát bất kỳ dữ liệu giao dịch nào phát sinh trong thời gian ứng dụng chạy tại Tokyo?**

Mục tiêu chính:
1. Nắm vững nguyên tắc cốt tử: **Không bao giờ Failback vội vàng** – Vùng sự cố phải được theo dõi ổn định liên tục tối thiểu 30 phút.
2. Thiết lập quan hệ sao chép dữ liệu ngược chiều (Reverse Replication) trên Amazon Aurora Global Database (Tokyo là Primary Writer $\rightarrow$ Singapore là Secondary Reader).
3. Chờ đợi Replication Lag giảm về dưới 1 giây và thực hiện **Planned Switchover** đưa quyền ghi trở lại Singapore an toàn tuyệt đối (RPO = 0).
4. Áp dụng kỹ thuật điều tiết lưu lượng tuần tự (Canary Traffic Shift) trên AWS Global Accelerator (20% $\rightarrow$ 50% $\rightarrow$ 100%).
5. Thu hẹp quy mô vùng Tokyo về mức **Warm Standby (1 replica/service)** để tối ưu hóa chi phí.

---

## 2. Architecture Diagram & Traffic Flow

```text
PHA 1: THIẾT LẬP SAO CHÉP NGƯỢC (REVERSE REPLICATION)
  Tokyo (Primary Writer Đang Chạy)  ===[Replication Lag < 1s]===>  Singapore (Secondary Đã Hồi Phục)

PHA 2: PLANNED SWITCHOVER (ZERO DATA LOSS)
  Tokyo (Chuyển thành Secondary)    <===[Replication Đảo Chiều]===  Singapore (Trở lại thành Primary Writer)

PHA 3: CANARY TRAFFIC SHIFT (GLOBAL ACCELERATOR)
  Global Accelerator: 
    - Bước 1: 80% Tokyo / 20% Singapore (Kiểm thử tải nhỏ)
    - Bước 2: 0% Tokyo / 100% Singapore (Toàn bộ tải về vùng chính)

PHA 4: THU HẸP TOKYO VỀ WARM STANDBY
  Tokyo EKS: Scale Pods từ 2 về 1 replica (Warm Standby - Cost Optimized)
```

---

## 3. Prerequisites & Pre-flight Checklist

> [!IMPORTANT]
> **Quy tắc Vàng của SRE:** Tuyệt đối không bắt đầu Failback nếu chưa đánh dấu đủ tất cả các điều kiện sau:
> - [ ] Vùng Singapore (`ap-southeast-1`) đã hoạt động ổn định liên tục ít nhất **30 phút** (không còn hiện tượng chập chờn mạng, sụt điện áp AZ hay lỗi API AWS).
> - [ ] Cụm EKS `dr-sg-eks` có toàn bộ Worker Nodes ở trạng thái `Ready`.
> - [ ] Argo CD tại Singapore đã đồng bộ thành công và toàn bộ 8 Pods của `app2` đang `Running (1/1)` (2 replicas x 4 services).
> - [ ] Cụm Aurora Singapore đã kết nối lại vào Global Database với vai trò Secondary.
> - [ ] Metric CloudWatch `AuroraGlobalDBReplicationLag` từ Tokyo sang Singapore hiển thị `< 1000 ms`.
> - [ ] Đã chụp một bản snapshot lưu trữ khẩn cấp trên cụm Tokyo (`app2-tokyo-pre-failback`).

---

## 4. Step-by-Step Implementation (Console-first + CLI)

### Bước 1: Chuẩn bị Workload và Sức Khỏe Ứng Dụng tại Singapore
1. Mở terminal, đổi context sang cụm EKS Singapore:
   ```bash
   kubectl --context singapore config current-context
   ```
2. Đảm bảo toàn bộ workloads tại Singapore đang chạy đủ 2 replicas để sẵn sàng đón nhận 100% tải:
   ```bash
   kubectl --context singapore -n app2 get pods
   ```
   *Nếu pods đang bị scale down, scale lại:*
   ```bash
   kubectl --context singapore -n app2 scale deployment app2-frontend app2-backend-1 app2-backend-2 app2-backend-3 --replicas=2
   ```
3. Kiểm tra ALB Target Groups tại Singapore:
   - Mở EC2 Console -> **Target Groups** tại `ap-southeast-1`.
   - Xác nhận tất cả targets của 4 microservices đều hiển thị trạng thái xanh **Healthy** trên endpoint `/health`.

### Bước 2: Chụp Snapshot Dự Phòng và Kiểm Tra Replication Lag
1. Mở AWS Console -> Dịch vụ **RDS** tại Region **Asia Pacific (Tokyo) ap-northeast-1**.
2. Chọn cụm `app2-tokyo-db` -> Chọn **Actions** -> **Take snapshot**.
   - Đặt tên: `app2-tokyo-pre-failback`.
   - Nhấn **Take snapshot** và đợi trạng thái chuyển sang `Available`.
3. Kiểm tra cụm Global Database `app2-global-db`:
   - Tokyo đang hiển thị vai trò **Regional primary**.
   - Singapore hiển thị vai trò **Secondary**.
   - Cột **Replication lag** của Singapore hiển thị `0 ms` hoặc `< 1 s`.

### Bước 3: Thực Hiện Planned Switchover Đưa Quyền Ghi Về Singapore
1. Tại RDS Console, chọn cụm Global Database `app2-global-db`.
2. Nhấn menu **Actions** -> Chọn **Switch over global database**.
3. **New primary cluster:** Chọn cụm `app2-sg-db (ap-southeast-1)`.
4. Nhấn **Switch over global database**.
5. AWS RDS sẽ:
   - Tạm dừng ghi trên cụm Tokyo trong vài giây để xả sạch transaction logs sang Singapore.
   - Thăng cấp `app2-sg-db` thành Primary Writer.
   - Đổi `app2-tokyo-db` thành Secondary Read-Only Replica.
6. Chờ 60 - 90 giây. Khi hoàn tất, cụm Singapore quay lại làm **Primary** và Tokyo trở thành **Secondary**.

### Bước 4: Điều Chỉnh Lưu Lượng Mạng Bằng Global Accelerator
1. Mở Console **AWS Global Accelerator** -> Chọn `app2-global`.
2. Chọn Listener port 80 -> Chọn tab **Endpoint groups**.
3. **Pha 1 (Canary 20%):**
   - Đặt Endpoint Group Singapore: **Traffic dial** = `20%`.
   - Đặt Endpoint Group Tokyo: **Traffic dial** = `100%`.
   - Nhấn **Save changes**.
   - Giám sát CloudWatch Alarm trong 5 phút. Nếu không có lỗi HTTP 5xx xuất hiện, chuyển sang Pha 2.
4. **Pha 2 (Toàn diện 100%):**
   - Đặt Endpoint Group Singapore: **Traffic dial** = `100%`.
   - Đặt Endpoint Group Tokyo: **Traffic dial** = `0%`.
   - Nhấn **Save changes**.

### Bước 5: Thu Hẹp Cụm Tokyo Về Trạng Thái Warm Standby
Sau khi Singapore đã tiếp nhận 100% lưu lượng và vận hành ổn định trong 15 phút:
1. Thu nhỏ các deployment tại Tokyo về mức tiết kiệm chi phí (1 replica mỗi service):
   ```bash
   kubectl --context tokyo -n app2 scale deployment app2-frontend app2-backend-1 app2-backend-2 app2-backend-3 --replicas=1
   ```
2. Xác nhận 4 pods của `app2` tại Tokyo vẫn duy trì `Running` để tiếp tục làm nhiệm vụ Warm Standby.

---

## 5. Verification & Testing

### Kiểm tra Đơn Hàng Ghi Tại Tokyo Vẫn Tồn Tại Nguyên Vẹn Sau Failback
1. Truy vấn các đơn hàng được ghi trong suốt thời gian hệ thống vận hành tại Tokyo (trong Lab 15):
   ```bash
   curl -s http://<GLOBAL_ACCELERATOR_IP>/api/v1/orders | jq .
   ```
   *Xác nhận:* Tất cả các giao dịch ghi nhận tại Tokyo vẫn hiện diện đầy đủ trong cơ sở dữ liệu Singapore $\rightarrow$ **Khẳng định tính toàn vẹn dữ liệu 100% (RPO = 0)**.

### Kiểm tra Giao Dịch Mới Tại Singapore
1. Kiểm tra health check:
   ```bash
   curl -s http://<GLOBAL_ACCELERATOR_IP>/health
   ```
   *Xác nhận:* Trả về JSON chứa `"region": "ap-southeast-1"`.
2. Gửi một transaction đơn hàng mới sau khi đã failback:
   ```bash
   curl -X POST http://<GLOBAL_ACCELERATOR_IP>/api/v1/orders \
     -H "Content-Type: application/json" \
     -d '{"item_id":"item-failback-success","quantity":1,"marker":"FAILBACK_COMPLETED"}'
   ```
   *Xác nhận:* HTTP 201 Created từ Singapore cluster và order được lưu trữ thành công.

---

## 6. Failure Modes & Troubleshooting

1. **Lỗi: Cụm Singapore không tự động trở thành Secondary sau sự cố sập vùng thật:**
   - *Nguyên nhân:* Trong kịch bản sập vùng thật diện rộng, nếu cụm Tokyo bị tách ra (detached/promoted độc lập), quan hệ Global Database cũ bị xóa bỏ.
   - *Cách sửa:* Tuân thủ hướng dẫn tại [database-recovery.md](../runbooks/database-recovery.md) để thực hiện lệnh `Add AWS Region` từ Tokyo sang Singapore nhằm thiết lập lại Global Database mới.
2. **Lỗi: Tỷ lệ lỗi HTTP 5xx tăng vọt ngay sau khi chuyển 100% traffic về Singapore:**
   - *Nguyên nhân:* Số lượng Pods trên Singapore chưa kịp khởi động hoặc các Pods chưa warm-up bộ nhớ đệm (cold start).
   - *Cách sửa:* Luôn scale Pods lên 2 replicas và kiểm tra health check trước khi đẩy traffic.
3. **Lỗi: Replication lag giữa Tokyo và Singapore bị đứng (stuck):**
   - *Nguyên nhân:* Security Group của Aurora Singapore bị thiếu port 5432 từ dải VPC Tokyo hoặc đường truyền Peering bị lỗi.
   - *Cách sửa:* Kiểm tra lại Security Group `app2-sg-db-sg` và Route Table của cả 2 vùng.

---

## 7. Production Hardening & Best Practices

- **Quy tắc Flapping Prevention:** Nếu hạ tầng Singapore vừa hồi phục mà lại sụt mạng thêm 1 lần nữa trong 30 phút theo dõi, reset đồng hồ đếm thời gian 30 phút lại từ đầu.
- **Canary Progression:** Trong môi trường sản xuất lớn, thực hiện bước nhảy traffic dial: 10% $\rightarrow$ 25% $\rightarrow$ 50% $\rightarrow$ 100%, mỗi bước theo dõi 10 phút.
- **Automated PDB Enforcement:** Tại Singapore, PodDisruptionBudget luôn duy trì `minAvailable: 1` để đảm bảo an toàn khi node worker drain.

---

## 8. Security & IAM Guardrails

- **Snapshot Retention:** Snapshot khẩn cấp `app2-tokyo-pre-failback` phải được lưu trữ tối thiểu 7 ngày trước khi dọn dẹp để phục vụ đối soát kiểm toán (Audit Trail).
- **Least Privilege Access:** Thao tác switchover database chỉ được phân quyền cho IAM Role DBA Lead hoặc Automation Runbook Role chuyên biệt.

---

## 9. Cost Estimation & Optimization

- **Tiết kiệm Compute tại Tokyo:** Việc thu hẹp Tokyo từ 2 replicas về 1 replica giúp tiết kiệm 50% chi phí compute pod cho vùng DR trong thời gian vận hành bình thường.
- **Replication Costs:** Phí truyền dữ liệu liên vùng (Inter-Region Data Transfer) của Aurora Global Database chỉ tính trên lượng byte thay đổi thực tế (~$0.02/GB), cực kỳ tối ưu so với snapshot dump/restore.

---

## 10. Rollback & Disaster Recovery Runbook

- Nếu trong quá trình Canary 20% phát hiện Singapore có lỗi tiềm ẩn:
  1. Ngay lập tức chỉnh **Traffic dial** của Singapore về `0%` và Tokyo về `100%`.
  2. Toàn bộ lưu lượng quay trở lại Tokyo trong vòng 10 giây.
  3. Hoãn quy trình Failback và tiếp tục điều tra nguyên nhân gốc rễ trên Singapore.

---

## 11. Next Steps & Handoff

Tiếp tục chuyển sang [LAB 17 - Đánh Giá & Đo Đạc Chỉ Số RTO/RPO Tổng Thể](17-rto-rpo-test.md) để thực hiện bài đo đạc benchmark tự động với kịch bản Continuous Writer.
