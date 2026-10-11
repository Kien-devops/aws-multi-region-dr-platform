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

### 6.1 Tạo topic thông báo

```text
SNS -> Topics -> Create topic
Type: Standard
Name: dr-platform-alerts
Encryption: AWS managed key or approved customer-managed KMS key
-> Create topic
-> Create subscription -> Email or approved incident integration
```

Xác nhận subscription trước khi tiếp tục. Không đặt secret trong tên hoặc mô tả alarm.

### 6.2 Bật EKS Container Insights

Trên AWS Console, lặp lại cho từng cluster và Region:

```text
EKS -> Clusters -> <cluster> -> Add-ons -> Get more add-ons
Amazon CloudWatch Observability
Select a compatible current version
IAM role: role with CloudWatchAgentServerPolicy, scoped for the add-on
-> Create
```

Xác minh:

```bash
aws eks describe-addon --region ap-southeast-1 --cluster-name dr-sg-eks --addon-name amazon-cloudwatch-observability
aws eks describe-addon --region ap-northeast-1 --cluster-name dr-tokyo-eks --addon-name amazon-cloudwatch-observability
```

Trạng thái phải là `ACTIVE`.

### 6.3 Tạo alarm sức khỏe ALB

Trong mỗi Region:

```text
CloudWatch -> Alarms -> Create alarm -> Select metric
ApplicationELB -> Per AppELB, per TG Metrics -> UnHealthyHostCount
Statistic: Maximum
Period: 1 minute
Threshold: >= 1
Datapoints: 2 of 3
Missing data: breaching
Notification: dr-platform-alerts
```

Dùng ALB kiểm thử và target group của nó. Đồng thời hiển thị `HealthyHostCount` trên dashboard; không tạo alarm từ aggregate không đủ dimension làm trộn nhiều target group.

### 6.4 Tạo Aurora replication alarm tại Tokyo

```text
CloudWatch Tokyo -> Metrics -> RDS -> DBClusterIdentifier
Metric: AuroraGlobalDBReplicationLag
Cluster: app2-tokyo-db
Statistic: Average
Period: 1 minute
Threshold: > <REVIEWED_LAG_THRESHOLD_MS>
Datapoints: 3 of 5
Missing data: breaching
```

Bắt đầu bằng ngưỡng lab được ghi rõ, ví dụ `30000` ms, chỉ như mục tiêu thiết kế. Điều chỉnh sau khi có baseline. Thêm `AuroraGlobalDBProgressLag`, `AuroraGlobalDBRPOLag`, CPU, connection, freeable memory và volume capacity vào dashboard khi khả dụng.

Tạo thêm alarm Aurora instance cho `CPUUtilization`, `FreeableMemory` và database connection bằng ngưỡng workload đã rà soát. Đây là tín hiệu dung lượng/sức khỏe, không phải tín hiệu RPO của replication.

### 6.5 Tạo alarm sức khỏe Global Accelerator

```text
CloudWatch -> Metrics -> GlobalAccelerator
Metric: HealthyEndpointCount
Select accelerator and endpoint group dimensions
Threshold: < 1
Period: 1 minute
Datapoints: 2 of 3
Missing data: breaching
```

Tạo một alarm cho mỗi endpoint group. Tên metric/dimension hiển thị trên Console là nguồn tham chiếu chính; kiểm tra trực tiếp trong tài khoản trước khi lưu.

### 6.6 Tạo dashboard liên Region

```text
CloudWatch -> Dashboards -> Create dashboard
Name: dr-platform-overview
```

Thêm:

- Hàng trạng thái alarm ở trên cùng.
- Số node EKS lỗi và CPU/bộ nhớ node của cả hai Region.
- Số host ALB khỏe/không khỏe và số lỗi 5XX.
- Aurora replication lag và RPO/progress lag tại Tokyo.
- Số endpoint GA khỏe mạnh của hai endpoint group.
- Widget Markdown ghi mục tiêu thiết kế RTO/RPO và `Đo thực tế: Chưa kiểm thử`.

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
