# LAB 13 - Quan sát hạ tầng

## 1. Mục tiêu

Xây dựng khả năng quan sát CloudWatch tối thiểu cho EKS, ALB, Aurora Global Database, Global Accelerator và sự kiện audit nền tảng mà chưa dùng metric app2.

## 2. Thành phần sẽ xây dựng

- SNS topic `dr-platform-alerts` với subscription đã xác nhận.
- CloudWatch Container Insights trên hai EKS cluster.
- Regional alarm cho sức khỏe target ALB và Aurora replication lag.
- Alarm sức khỏe endpoint Global Accelerator.
- Dashboard liên Region `dr-platform-overview`.

## 3. Bối cảnh kiến trúc

```text
EKS / ALB / Aurora / Global Accelerator
             -> metric và alarm CloudWatch
             -> thông báo SNS
             -> người vận hành DR
```

Metric chứng minh sức khỏe thành phần, không chứng minh tính đúng đắn nghiệp vụ. Metric SLI/SLO của ứng dụng được hoãn lại.

## 4. Điều kiện tiên quyết

- Hoàn thành LAB 12.
- Hai ALB và GA endpoint group đã tồn tại.
- Aurora secondary phát metric `AuroraGlobalDBReplicationLag` tại Tokyo.
- Đích nhận thông báo đã được phê duyệt.

## 5. Quy ước đặt tên tài nguyên

| Tài nguyên | Giá trị |
|---|---|
| SNS topic | `dr-platform-alerts` |
| Dashboard | `dr-platform-overview` |
| Alarm mẫu | `dr-sg-alb-unhealthy`, `dr-tokyo-alb-unhealthy`, `app2-global-replication-lag`, `dr-ga-endpoint-unhealthy` |

## 6. Các bước triển khai

### 6.1 Tạo SNS Topic và Đăng ký nhận thông báo (Email Alerts)

1. Mở AWS Management Console tại Region **Singapore (`ap-southeast-1`)** (hoặc Region quản trị giám sát chính).
2. Trên thanh tìm kiếm, gõ `SNS` và chọn dịch vụ **Simple Notification Service**.
3. Trong menu bên trái, nhấp chọn **Topics** -> nhấp nút **Create topic** màu cam ở góc trên bên phải.
4. **Type**: Chọn **Standard**.
5. **Name**: Nhập `dr-platform-alerts`.
6. **Display name**: Nhập `DR-Alerts`.
7. **Encryption**: Chọn mã hóa mặc định AWS-managed hoặc CMK.
8. Nhấp nút **Create topic** màu cam ở cuối trang.
9. Đăng ký nhận email thông báo (Subscription):
   - Trong trang chi tiết của topic vừa tạo, chuyển sang tab **Subscriptions** -> nhấp nút **Create subscription**.
   - **Protocol**: Chọn **Email**.
   - **Endpoint**: Nhập địa chỉ `<EMAIL>` của bạn.
   - Nhấp nút **Create subscription**.
   - Mở hòm thư email cá nhân -> tìm email tiêu đề *AWS Notification - Subscription Confirmation* -> nhấp vào liên kết **Confirm subscription**. Trạng thái trong SNS Console sẽ chuyển từ *PendingConfirmation* sang **Confirmed**.

### 6.2 Bật EKS Container Insights qua EKS Add-ons

Thực hiện lần lượt cho cả hai cluster tại Singapore và Tokyo:

#### Bước 1: Kích hoạt tại Singapore (`dr-sg-eks`)
1. Chuyển Region sang **Singapore (`ap-southeast-1`)** -> truy cập dịch vụ **EKS** -> chọn cluster `dr-sg-eks`.
2. Chuyển sang tab **Add-ons** -> nhấp nút **Get more add-ons**.
3. Trong danh sách add-ons, tìm kiếm `Amazon CloudWatch Observability`.
4. Tích chọn add-on -> nhấp nút **Next**.
5. Giữ phiên bản tương thích mới nhất.
6. Tại mục **Select IAM role**: Nếu chưa có role, tạo nhanh một IAM Role gắn policy `CloudWatchAgentServerPolicy` cho service account của add-on hoặc chọn role phù hợp.
7. Nhấp **Next** -> rà soát và nhấp **Create**. Chờ trạng thái add-on chuyển sang **Active**.

#### Bước 2: Kích hoạt tại Tokyo (`dr-tokyo-eks`)
1. Chuyển Region sang **Tokyo (`ap-northeast-1`)** -> vào cluster `dr-tokyo-eks` -> tab **Add-ons**.
2. Thực hiện thêm add-on `Amazon CloudWatch Observability` tương tự như Singapore.

### 6.3 Tạo CloudWatch Alarm giám sát sức khỏe ALB (UnHealthyHostCount)

Thực hiện tạo alarm tại Singapore:

1. Chuyển Region sang **Singapore (`ap-southeast-1`)** -> truy cập dịch vụ **CloudWatch**.
2. Trong menu bên trái, chọn **Alarms** -> chọn **All alarms** -> nhấp nút **Create alarm** màu cam.
3. Nhấp nút **Select metric**:
   - Chọn danh mục **ApplicationELB** -> chọn **Per AppELB, per TG Metrics**.
   - Tìm theo tên Load Balancer `dr-sg-validation-alb`.
   - Chọn metric mang tên **UnHealthyHostCount** -> nhấp **Select metric**.
4. **Specify metric and conditions**:
   - **Statistic**: Chọn **Maximum**.
   - **Period**: Chọn **1 minute**.
   - **Threshold type**: Chọn **Static**.
   - **Whenever UnHealthyHostCount is...**: Chọn **Greater/Equal (>=)** và nhập `1`.
   - Mở mục **Additional configuration**:
     - **Datapoints to alarm**: Nhập `2` out of `3`.
     - **Missing data treatment**: Chọn **Treat missing data as bad (breaching)**.
   - Nhấp nút **Next**.
5. **Configure actions**:
   - **Alarm state trigger**: Chọn **In alarm**.
   - **Send a notification to...**: Chọn **Select an existing SNS topic** -> chọn `dr-platform-alerts`.
   - Nhấp nút **Next**.
6. **Add name and description**:
   - **Alarm name**: Nhập `dr-sg-alb-unhealthy`.
   - **Alarm description**: Nhập `Singapore Validation ALB has unhealthy pod targets`.
   - Nhấp **Next** -> nhấp **Create alarm**.
7. Lặp lại các bước trên tại **Tokyo (`ap-northeast-1`)** với tên alarm là `dr-tokyo-alb-unhealthy` trỏ vào `dr-tokyo-validation-alb`.

### 6.4 Tạo Alarm giám sát độ trễ nhân bản Aurora tại Tokyo (Replication Lag)

Metric độ trễ nhân bản của Aurora Global Database được phát ra từ cluster đóng vai trò Secondary/Read-only (tức Tokyo):

1. Chuyển Region sang **Asia Pacific (Tokyo) `ap-northeast-1`** -> truy cập dịch vụ **CloudWatch**.
2. Chọn **Alarms** -> nhấp **Create alarm** -> nhấp **Select metric**.
3. Duyệt tìm metric:
   - Chọn dịch vụ **RDS** -> chọn **DBClusterIdentifier**.
   - Tìm cluster `app2-tokyo-db`.
   - Chọn metric mang tên **AuroraGlobalDBReplicationLag** (đơn vị: milliseconds) -> nhấp **Select metric**.
4. **Specify metric and conditions**:
   - **Statistic**: Chọn **Average**.
   - **Period**: Chọn **1 minute**.
   - **Threshold type**: Chọn **Static**.
   - **Whenever AuroraGlobalDBReplicationLag is...**: Chọn **Greater (>)** và nhập ngưỡng cảnh báo: `30000` (tương đương 30 giây độ trễ).
   - **Datapoints to alarm**: Nhập `3` out of `5`.
   - **Missing data treatment**: Chọn **Treat missing data as bad (breaching)**.
   - Nhấp nút **Next**.
5. **Configure actions**:
   - Chọn SNS Topic thông báo (tạo hoặc liên kết topic thông báo tại Tokyo).
   - Nhấp **Next**.
6. **Add name and description**:
   - **Alarm name**: Nhập `app2-global-replication-lag`.
   - **Alarm description**: Nhập `Aurora Global Database replication lag to Tokyo exceeds 30 seconds`.
   - Nhấp **Next** -> nhấp **Create alarm**.

### 6.5 Tạo Alarm giám sát sức khỏe Global Accelerator Endpoints

1. Truy cập CloudWatch Console (tại Region us-west-2 hoặc Region chính):
2. Chọn **Alarms** -> nhấp **Create alarm** -> **Select metric**.
3. Chọn dịch vụ **GlobalAccelerator** -> chọn dimensions theo Accelerator và Endpoint Group:
   - Chọn metric **HealthyEndpointCount** cho Singapore Endpoint Group -> Ngưỡng: **Lower (<)** `1` (cảnh báo nếu số endpoint khỏe nhỏ hơn 1).
   - Đặt tên alarm: `dr-ga-sg-endpoint-unhealthy`.
4. Tạo thêm một alarm tương tự cho Tokyo Endpoint Group:
   - Đặt tên alarm: `dr-ga-tokyo-endpoint-unhealthy`.

### 6.6 Tạo CloudWatch Dashboard tổng hợp đa vùng (Cross-Region Dashboard)

1. Trong menu bên trái của CloudWatch Console, chọn **Dashboards** -> nhấp nút **Create dashboard** màu cam.
2. **Dashboard name**: Nhập `dr-platform-overview` -> nhấp **Create dashboard**.
3. Thêm các widget quan sát chính:
   - *Widget 1 (Alarm status):* Chọn loại widget **Alarm status** -> thêm các alarm đã tạo (`dr-sg-alb-unhealthy`, `dr-tokyo-alb-unhealthy`, `app2-global-replication-lag`, `dr-ga-sg-endpoint-unhealthy`).
   - *Widget 2 (Aurora Replication Lag):* Chọn loại **Line** -> Metric: chọn `AuroraGlobalDBReplicationLag` tại Tokyo -> Title: `Aurora Global DB Lag (Tokyo)`.
   - *Widget 3 (ALB Healthy & Unhealthy Hosts):* Thêm biểu đồ thể hiện `HealthyHostCount` và `UnHealthyHostCount` của cả hai Region SG và Tokyo.
   - *Widget 4 (Global Accelerator Traffic/Health):* Thêm metric `HealthyEndpointCount` của 2 endpoint groups.
   - *Widget 5 (Markdown Note):* Chọn widget **Text** -> nhập ghi chú:
     ```markdown
     ### DR Objectives & Real-time Status
     - **Traffic Failover Target**: < 5 minutes
     - **Aurora Replication Lag Target**: < 30 seconds
     - **Current Mode**: Phase 1 Infrastructure Readiness
     ```
4. Nhấp nút **Save dashboard** màu cam ở góc trên bên phải.

Đặt đúng Region cho từng widget. Dùng khoảng thời gian mặc định tám giờ.

## 7. Xác minh

- Kích hoạt rồi khôi phục bài kiểm thử scale workload Singapore từ LAB 12.
- Xác nhận alarm ALB và GA chuyển trạng thái, gửi thông báo rồi phục hồi.
- Xác nhận Aurora lag metric có datapoint thực tế; không cố tình gây lỗi cơ sở dữ liệu để thử alarm.
- Xác nhận Container Insights hiển thị cả hai cluster.

## 8. Kết quả mong đợi

Người vận hành có thể quan sát và nhận cảnh báo cho tín hiệu lỗi nền tảng. Chưa đưa ra tuyên bố về availability, latency, RTO hoặc RPO của ứng dụng.

## 9. Xử lý sự cố

- Alarm `INSUFFICIENT_DATA`: sai dimension/Region hoặc metric chưa phát dữ liệu.
- Không có email SNS: subscription vẫn pending hoặc topic policy/quyền KMS chặn gửi tin.
- Thiếu metric EKS: add-on chưa `ACTIVE`, thiếu IAM role hoặc node không tới được CloudWatch endpoint.
- Không có Aurora lag metric tại Singapore: đúng dự kiến; Global Database lag metric được phát tại secondary Region.

## 10. Lưu ý bảo mật

- Mã hóa SNS topic và giới hạn publisher/subscriber.
- Giới hạn chia sẻ dashboard; CloudWatch metric và tên tài nguyên có thể tiết lộ kiến trúc.
- Bật CloudTrail cấp organization/tài khoản, bảo vệ log bằng mã hóa và retention.
- Không public Grafana trong giai đoạn này.

## 11. Lưu ý chi phí

Container Insights observation/log ingestion, alarm, dashboard, SNS và lưu giữ log phát sinh phí. Prometheus/Grafana là tùy chọn và chủ động được hoãn để tránh chi phí và tải vận hành bổ sung.

## 12. Dọn dẹp / Quay lui

Chỉ xóa alarm/dashboard/SNS kiểm thử khi bỏ toàn bộ lớp quan sát. Gỡ EKS add-on sẽ dừng telemetry nhưng không tự xóa log đã lưu.

## 13. Bằng chứng cần thu thập

- Output add-on `ACTIVE` của cả hai cluster.
- Ảnh dashboard có cả hai Region.
- Cấu hình alarm, lịch sử alarm và thông báo đã nhận.
- Aurora lag datapoint kèm timestamp.

## 14. Lab tiếp theo

Tiếp tục với [LAB 14 - Chuyển đổi hạ tầng có kế hoạch](14-planned-switchover.md).

Storage labs 18-26 must extend the dashboard with FSx capacity/throughput/network metrics, file-system events, EC2 status checks, storage ALB healthy targets and file-service `/ready`. SnapMirror relationship state, last-transfer timestamp and lag evidence come from ONTAP/AWS operational views; verify exact metric names available for the selected FSx generation before creating alarms.
