# Sổ tay Vận hành: Kích hoạt Failover sang Tokyo (Failover to Tokyo Runbook)

> [!CAUTION]
> **Quy trình Nhạy cảm trên Production:** Thao tác này đòi hỏi sự phê chuẩn chính thức của **Incident Commander**. Việc failover Aurora Global Database có thể gây mất mát những dữ liệu chưa kịp đồng bộ (unreplicated data).

## Phạm vi Áp dụng (Scope)

Runbook Giai đoạn 1 tập trung xác thực và chuyển đổi hạ tầng cốt lõi (Mạng, Load Balancer, EKS Ingress, Database). Việc mở rộng tải của ứng dụng `app2`, ghi dữ liệu nghiệp vụ và đo lường transaction RPO thực tế được tích hợp ở Giai đoạn 2 và 3.

## Điều kiện Kích hoạt (Activation Criteria)

- Region Singapore không thể truy cập hoặc được công bố là không an toàn để tiếp tục nhận write.
- Hạ tầng Tokyo (EKS Cluster, ALB, Database Secondary, Secret replica và quyền truy cập của người vận hành) đều ở trạng thái khỏe mạnh (Healthy).
- Đã phân công đầy đủ các vai trò: Approver (Phê duyệt), Operator (Thao tác), Verifier (Kiểm chứng độc lập), Recorder (Ghi chép timeline).
- Đã ghi nhận chỉ số độ trễ replication lag cuối cùng của Aurora.

## Quy trình Thao tác Chi tiết (Execution Sequence)

### Bước 1: Khai báo Incident và Fence Primary Singapore ($T_0$)

1. **Khóa Ingress trên AWS Global Accelerator Console:**
   - Mở **AWS Global Accelerator Console** tại [https://console.aws.amazon.com/globalaccelerator/](https://console.aws.amazon.com/globalaccelerator/).
   - Nhấp vào accelerator **`dr-platform-accelerator`** (hoặc `dr-global-accelerator`).
   - Chuyển sang tab **Listeners** -> chọn listener **`Port 80 (TCP)`**.
   - Trong danh sách **Endpoint groups**, tìm nhóm **`ap-southeast-1`** (Singapore):
     - Tích chọn checkbox `ap-southeast-1` -> bấm nút **Edit** ở góc trên bên phải.
     - Tại mục **Traffic dial**, kéo thanh trượt hoặc gõ đổi giá trị từ `100` về **`0`**.
     - Nhấp nút cam **Save changes**.
   - *CLI tương đương:*
     ```bash
     aws globalaccelerator update-endpoint-group \
       --endpoint-group-arn <SG_ENDPOINT_GROUP_ARN> \
       --traffic-dial-percentage 0
     ```

2. **Cô lập Ingress / Workload Singapore (nếu Singapore Console còn phản hồi):**
   - Đảm bảo các pod application cũ không nhận thêm write request. Nếu có Argo CD, tạm dừng auto-sync trước khi can thiệp.

---

### Bước 2: Kiểm tra Mức độ Sẵn sàng tại Tokyo (Health Checks)

1. **Kiểm tra EKS & Ingress Tokyo:**
   ```bash
   kubectl --context tokyo get nodes
   kubectl --context tokyo -n infra-validation get pods,ingress
   ```
2. **Kiểm tra Secrets Manager Replica tại Tokyo:**
   - Mở **AWS Secrets Manager Console** tại Region **Tokyo (`ap-northeast-1`)**.
   - Tìm secret **`/app2/database`**, xác nhận trạng thái replica là **InSync**.
   - *CLI tương đương:*
     ```bash
     aws secretsmanager describe-secret --region ap-northeast-1 --secret-id /app2/database
     ```

---

### Bước 3: Thăng cấp Tokyo thành Primary trên Amazon RDS Console

> [!CAUTION]
> **Thao tác cưỡng bức (Unplanned Failover):** Thao tác này sẽ ngắt liên kết replication và có thể làm mất dữ liệu chưa kịp đồng bộ (unreplicated data). Bắt buộc phải có sự phê chuẩn của Incident Commander.

1. **Thao tác trên AWS Console:**
   - Mở **Amazon RDS Console** tại [https://console.aws.amazon.com/rds/](https://console.aws.amazon.com/rds/).
   - Trong menu bên trái, nhấp chọn **Databases**.
   - Tích chọn cụm cơ sở dữ liệu toàn cầu **`dr-global-db`** (hoặc `app2-global-db`).
   - Nhấp vào menu dropdown **Actions** ở góc trên bên phải -> chọn **Fail over global database**.
   - Trong màn hình cấu hình Failover:
     - Tại mục **Target secondary DB cluster**, chọn cụm Tokyo: **`dr-tokyo-aurora-cluster`** (hoặc `app2-tokyo-db`).
     - Tích chọn ô vuông xác nhận: **"I acknowledge that failing over to a secondary cluster will result in data loss if replication is not up to date"**.
     - Nhấp nút màu cam **Fail over**.
   - Quan sát bảng Databases cho đến khi cụm Tokyo chuyển từ trạng thái `Failing over` sang **`Available`** và cột Role hiển thị **Primary cluster (Writer)**.

2. **Thao tác qua AWS CLI (Dành cho Automation / DevOps):**
   ```bash
   aws rds failover-global-cluster \
     --region ap-southeast-1 \
     --global-cluster-identifier app2-global-db \
     --target-db-cluster-identifier <TOKYO_DB_CLUSTER_ARN> \
     --allow-data-loss
   ```

---

### Bước 4: Chuyển hướng Toàn bộ Lưu lượng sang Tokyo trên Global Accelerator

1. Mở lại **AWS Global Accelerator Console**.
2. Nhấp vào **`dr-platform-accelerator`** -> tab **Listeners** -> chọn **`Port 80 (TCP)`**.
3. Trong bảng **Endpoint groups**, tìm nhóm **`ap-northeast-1`** (Tokyo):
   - Tích chọn `ap-northeast-1` -> bấm nút **Edit**.
   - Chỉnh **Traffic dial** từ `0` lên **`100`**.
   - Nhấp nút cam **Save changes**.
4. Chờ trạng thái Accelerator hiển thị **Deployed**.

---

### Bước 5: Xác minh Kết nối và Nghiệm thu Hệ thống ($T_5$)

1. **Gửi request kiểm tra qua Global Accelerator:**
   ```bash
   curl -sS -i -H 'Connection: close' http://<ACCELERATOR_DNS_NAME>/
   ```
   *Kỳ vọng:* Trả về HTTP 200 từ Backend Pods tại Tokyo.

2. **Kiểm tra trạng thái Topology toàn cầu:**
   ```bash
   aws rds describe-global-clusters \
     --region ap-northeast-1 \
     --global-cluster-identifier app2-global-db \
     --query 'GlobalClusters[0].Members[*].{ARN:DBClusterArn,IsWriter:IsWriter}'
   ```
   *Kỳ vọng:* Chỉ duy nhất cụm Tokyo có `IsWriter: true`.

3. Ghi nhận mốc thời gian hoàn tất, xác định RTO hạ tầng ($T_5 - T_0$) và thông báo trạng thái phục hồi cho các bên liên quan.

## Các Điều Cấm kỵ Tuyệt đối (Do Not)

- **Tuyệt đối không** thăng cấp Tokyo trước khi kiểm chứng sức khỏe của cụm này.
- **Tuyệt đối không** tuyên bố "RPO = 0" (không mất dữ liệu) khi chưa có bằng chứng đối chiếu sequence markers sau sự cố đột ngột.
- **Tuyệt đối không** tái kết nối độc lập cụm Singapore cũ đang có nguy cơ phân nhánh khi nó online trở lại.
- **Tuyệt đối không** chạy lệnh `kubectl scale` thủ công khi Argo CD đang bật chế độ tự chữa lành (`selfHeal=true`).
- **Tuyệt đối không** để lộ mật khẩu, chuỗi kết nối nhạy cảm trên các kênh chat xử lý sự cố.

## Phụ lục Giai đoạn Ứng dụng (Application Phase Addendum)

Sẽ được kích hoạt khi ứng dụng `app2` được triển khai:
- Mở rộng (Scale)/thăng cấp trạng thái mong muốn của ứng dụng tại Tokyo thông qua GitOps commit.
- Xác thực hoạt động của Frontend/Backend và request ghi nghiệp vụ đầu tiên thành công.
- Chạy script `scripts/dr/rpo-check.sh` đối chiếu sequence markers để xác định độ lệch dữ liệu.

## Bàn giao và Duy trì (Recovery Handoff)

Tokyo sẽ tiếp tục giữ vai trò Primary duy nhất cho đến khi hạ tầng Singapore được sửa chữa và tái thiết lập hoàn toàn thành một cụm Secondary đồng bộ. Thực hiện quy trình tại [failback.md](failback.md); tuyệt đối không đảo ngược lưu lượng một cách vội vã.
