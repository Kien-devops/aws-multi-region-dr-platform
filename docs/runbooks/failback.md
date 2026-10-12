# Sổ tay Vận hành: Khôi phục Về Singapore (Failback to Singapore Runbook)

## Phạm vi Áp dụng (Scope)

Đưa quyền điều hành và lưu lượng chính trở về Region Singapore thông qua quy trình chuyển đổi chủ động có kiểm soát (Planned Change) sau khi Tokyo đã vận hành ổn định. Đây là một quy trình kỹ thuật riêng biệt, **không phải là thao tác đảo chiều tự động hay đột ngột**.

## Điều kiện Tiên quyết (Preconditions)

- Tokyo hiện đang là Writer duy nhất của hệ thống.
- Cụm Singapore đã được sửa chữa, tái gia nhập thành công làm một Secondary Cluster lành mạnh trong Global Database.
- Độ trễ replication lag duy trì ổn định `<= 1s` trong suốt cửa sổ quan sát ít nhất 15-30 phút.
- Phiên bản database engine và patch tương thích hoàn toàn; không có tác vụ bảo trì ngầm nào đang chạy.
- Cụm EKS và ALB kiểm thử tại Singapore đều ở trạng thái Healthy.
- Đã được cấp phê duyệt thay đổi (Change Approval) và chỉ định người chịu trách nhiệm rollback nếu có sự cố.

## Quy trình Thao tác Chi tiết (Execution Sequence)

### Bước 1: Xác nhận Đồng bộ và Đánh giá Replication Lag

1. Mở **Amazon CloudWatch Console** tại [https://console.aws.amazon.com/cloudwatch/](https://console.aws.amazon.com/cloudwatch/).
2. Đổi Region sang **Singapore (`ap-southeast-1`)** -> vào mục **Metrics** -> chọn namespace **`AWS/RDS`**.
3. Xem metric `AuroraGlobalDBReplicationLag`:
   - Xác nhận độ trễ nhỏ hơn ngưỡng quy định (ví dụ: `< 5s` hoặc `0s`) ổn định trong suốt cửa sổ quan sát ít nhất 15 phút.
4. Kiểm tra sức khỏe hạ tầng EKS và ALB tại Singapore:
   ```bash
   kubectl --context singapore get nodes
   kubectl --context singapore -n infra-validation get pods,ingress
   ```

---

### Bước 2: Thực hiện Managed Switchover trên Amazon RDS Console

> [!NOTE]
> **Quy trình Zero Data Loss:** Managed Switchover đồng bộ hóa hoàn toàn mọi write transactions đang dở dang trước khi đổi vai trò. Không có rủi ro mất dữ liệu.

1. **Thao tác trên AWS Console:**
   - Mở **Amazon RDS Console** tại [https://console.aws.amazon.com/rds/](https://console.aws.amazon.com/rds/).
   - Tại menu bên trái, chọn **Databases**.
   - Tích chọn cụm toàn cầu **`dr-global-db`** (hoặc `app2-global-db`).
   - Nhấp menu dropdown **Actions** ở góc trên bên phải -> chọn **Switch over global database**.
   - Trong cửa sổ xác nhận:
     - Tại mục **Target secondary DB cluster**, chọn cụm Singapore: **`dr-sg-aurora-cluster`** (hoặc `app2-sg-db`).
     - Nhấp nút cam **Switch over**.
   - Quá trình switchover diễn ra trong khoảng 1-3 phút. Đợi đến khi trạng thái cụm toàn cầu chuyển thành **Available**, cụm Singapore trở thành **Primary cluster (Writer)** và cụm Tokyo trở thành **Secondary cluster (Reader)**.

2. **Thao tác qua AWS CLI (Dành cho Automation):**
   ```bash
   aws rds switchover-global-cluster \
     --region ap-northeast-1 \
     --global-cluster-identifier app2-global-db \
     --target-db-cluster-identifier <SINGAPORE_DB_CLUSTER_ARN>
   ```

---

### Bước 3: Điều chuyển Lưu lượng trên AWS Global Accelerator Console

1. Mở **AWS Global Accelerator Console** tại [https://console.aws.amazon.com/globalaccelerator/](https://console.aws.amazon.com/globalaccelerator/).
2. Nhấp vào tên accelerator **`dr-platform-accelerator`**.
3. Chuyển sang tab **Listeners** -> chọn listener **`Port 80 (TCP)`**.
4. Cập nhật nhóm endpoint Singapore (`ap-southeast-1`):
   - Tích chọn checkbox `ap-southeast-1` -> bấm nút **Edit**.
   - Đổi **Traffic dial** từ `0` thành **`100`** -> bấm **Save changes**.
5. Cập nhật nhóm endpoint Tokyo (`ap-northeast-1`):
   - Tích chọn checkbox `ap-northeast-1` -> bấm nút **Edit**.
   - Đổi **Traffic dial** từ `100` thành **`0`** -> bấm **Save changes**.
6. Chờ trạng thái Accelerator hiển thị **Deployed**.

---

### Bước 4: Xác minh Kết nối và Trạng thái Hệ thống

1. Gửi request kiểm tra tới Global Accelerator IP/DNS:
   ```bash
   curl -sS -i -H 'Connection: close' http://<ACCELERATOR_DNS_NAME>/
   ```
   *Kỳ vọng:* Traffic phản hồi trơn tru từ pods tại Singapore.
2. Kiểm tra topology phân bố role trên CLI:
   ```bash
   aws rds describe-global-clusters \
     --region ap-southeast-1 \
     --global-cluster-identifier app2-global-db \
     --query 'GlobalClusters[0].Members[*].{ARN:DBClusterArn,IsWriter:IsWriter}'
   ```
   *Kỳ vọng:* `dr-sg-aurora-cluster` có `IsWriter: true`, `dr-tokyo-aurora-cluster` có `IsWriter: false`.
3. Giữ cụm Tokyo luôn sẵn sàng ở chế độ Warm Standby.

## Quy tắc GitOps (GitOps Rule)

Khi ứng dụng `app2` đi vào hoạt động, việc điều chỉnh replica và năng lực xử lý của Tokyo về trạng thái dự phòng bắt buộc phải thực hiện thông qua Git commit hoặc quy trình tạm ngưng đồng bộ đã được phê duyệt. Tuyệt đối không để trạng thái runtime trên cluster phân nhánh so với kho GitOps.

## Quy trình Quay lui Khẩn cấp (Rollback)

Nếu sau khi switchover mà hệ thống tại Singapore gặp lỗi nghiêm trọng trong khi Tokyo vẫn hoàn toàn khỏe mạnh: Thực hiện ngay một phiên **Managed Switchover đảo chiều khẩn cấp** để đưa quyền Writer quay lại Tokyo và điều chuyển lại Global Accelerator preference về Tokyo. Lưu trữ toàn bộ timeline của cả hai sự kiện.

## Bằng chứng Cần Lưu trữ (Evidence)

Thu thập đồ thị replication lag từ CloudWatch, ảnh chụp màn hình Topology trước/sau trên RDS Console, giá trị Traffic dial trên Global Accelerator, log các request kiểm chứng, biên bản phê duyệt và các mốc thời gian UTC chính xác. Xác thực nghiệp vụ ứng dụng chi tiết sẽ được tích hợp ở Giai đoạn 3.
