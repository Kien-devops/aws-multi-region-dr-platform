# LAB 13 - Thiết Lập Hệ Thống Quan Sát và Giám Sát DR (Observability Stack)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Thiết lập hệ thống quan sát kết hợp giữa **Amazon CloudWatch**, **Prometheus**, **Grafana**, và **Alertmanager** trên cả hai vùng.
2. Theo dõi các chỉ số quan trọng quyết định trạng thái hệ thống:
   - **ALB Metrics:** `HealthyHostCount`, `HTTPCode_Target_5XX_Count`, `TargetResponseTime`.
   - **Aurora Metrics:** `AuroraGlobalDBReplicationLag` (chỉ số quyết định RPO), `DatabaseConnections`, `CPUUtilization`.
   - **Application Metrics:** Synthetic check định kỳ tới `GET /health`.
3. Xây dựng một **DR Executive Dashboard** trực quan hiển thị thông tin phục vụ chỉ đạo sự cố.

---

## Architecture impact

```text
[ AWS CloudWatch Metrics ] <---+--- [ ALB: HealthyHostCount, HTTPCode_Target_5XX_Count ]
                               +--- [ Aurora: AuroraGlobalDBReplicationLag, Connections ]
                                      |
+-------------------------------------+-------------------------------------+
| SINGAPORE CLUSTER                   | TOKYO CLUSTER                       |
| [ Prometheus Agent ]                | [ Prometheus Agent ]                |
|       |                             |       |                             |
|       v                             |       v                             |
| [ Grafana Server ] <----------------+-------+                             |
| Dashboard: DR Unified Control       |                                     |
+-------------------------------------+-------------------------------------+
```

---

## Resource naming

- CloudWatch Metric Alarms:
  - `dr-sg-alb-high-5xx`: Cảnh báo khi ALB Singapore có `HTTPCode_Target_5XX_Count` > 10 trong 1 phút
  - `dr-aurora-high-replication-lag`: Cảnh báo khi `AuroraGlobalDBReplicationLag` > 5000ms
  - `dr-sg-alb-zero-healthy-hosts`: Cảnh báo khi `HealthyHostCount` < 1
- Prometheus Namespace: `monitoring`
- Grafana Dashboard: `AWS-MultiRegion-DR-Dashboard`

---

## AWS Console Steps: Thiết Lập Cảnh Báo CloudWatch

### Bước 1: Tạo CloudWatch Alarm Giám Sát Replication Lag của Aurora
1. Mở AWS Console -> Region **Asia Pacific (Singapore) ap-southeast-1** -> Dịch vụ **CloudWatch**.
2. Menu bên trái chọn **Alarms** -> Nhấn **Create alarm**.
3. Nhấn **Select metric**:
   - Chọn namespace: **RDS** -> **SourceRegion, SourceRegionDBClusterIdentifier Metrics**.
   - Metric: `AuroraGlobalDBReplicationLag` (đơn vị mili-giây).
   - Cụm: `app2-sg-db`.
4. Điều kiện cảnh báo:
   - Statistic: **Average**.
   - Period: **1 minute**.
   - Threshold: **Greater than** `5000` (5 giây).
5. Gửi thông báo tới SNS topic `dr-alerts-team`.
6. Tên Alarm: `dr-aurora-high-replication-lag` -> Nhấn **Create alarm**.

### Bước 2: Tạo Alarm Giám Sát Lỗi 5XX Trên Application Load Balancer
1. Trong CloudWatch Console -> **Create alarm** -> **Select metric**.
2. Chọn **ApplicationELB** -> Metric: `HTTPCode_Target_5XX_Count` của ALB Singapore.
3. Điều kiện: `Sum >= 10` trong 1 phút.
4. Tên Alarm: `dr-sg-alb-high-5xx` -> Nhấn **Create alarm**.

---

## Cài Đặt Prometheus và Grafana Qua Helm

```bash
kubectl config use-context singapore

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community

helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  --set grafana.adminPassword="AdminDRPlatform2026!" \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

---

## Đặc Tả DR Executive Dashboard

Một Dashboard DR hoàn chỉnh phải trả lời được các câu hỏi cốt lõi sau:

```text
+----------------------------------------------------------------------------------------------------+
|                             AWS MULTI-REGION DR EXECUTIVE DASHBOARD                                |
+----------------------------------+----------------------------------+------------------------------+
| 1. CURRENT ACTIVE REGION         | 2. CURRENT DATABASE WRITER       | 3. APPLICATION STATUS        |
|    [ SINGAPORE (ap-southeast-1)] |    [ app2-sg-db (Singapore) ]    |    [ HEALTHY (/health 200) ] |
+----------------------------------+----------------------------------+------------------------------+
| 4. AURORA REPLICATION LAG        | 5. HEALTHY HOSTS PER ALB         | 6. POD READINESS             |
|    [ 124 ms ] (Target: < 30s)    |    SG: 8 hosts | TOKYO: 4 hosts  |    SG: 8/8 | TOKYO: 4/4      |
+----------------------------------+----------------------------------+------------------------------+
| 7. MEASURED RTO (LAST DRILL)     | 8. MEASURED RPO (LAST DRILL)     | 9. LAST DRILL TIMESTAMP      |
|    [ 2m 14s ] (Target: < 5m)     |    [ 0s / 1s ] (Target: < 30s)   |    [ YYYY-MM-DD HH:MM ]      |
+----------------------------------+----------------------------------+------------------------------+
```

---

## Verification

### Kiểm tra Alarms trên Console
1. CloudWatch Console -> Alarms: Xác nhận cả hai alarm `dr-aurora-high-replication-lag` và `dr-sg-alb-high-5xx` đều hiển thị trạng thái xanh `OK`.

### Mở Grafana Dashboard
```bash
kubectl --context singapore -n monitoring port-forward svc/prometheus-stack-grafana 3000:80
```
Mở trình duyệt truy cập: `http://localhost:3000`.

---

## Troubleshooting

1. **Lỗi: Metric `AuroraGlobalDBReplicationLag` không hiển thị:**
   - *Nguyên nhân:* Chọn sai Region (phải chọn Singapore nơi Primary Writer đang đặt) hoặc cụm Secondary Tokyo chưa đồng bộ xong.
   - *Cách sửa:* Kiểm tra tại Region Singapore trong namespace RDS.
2. **Lỗi: Grafana Pod bị thiếu RAM:**
   - *Nguyên nhân:* Dung lượng memory trên node `t3.medium` bị chiếm dụng.
   - *Cách sửa:* Điều chỉnh tài nguyên requests/limits của prometheus-stack.
3. **Lỗi: Synthetic check báo lỗi:**
   - *Nguyên nhân:* URL synthetic check gọi nhầm `/healthz` thay vì `/health`.
   - *Cách sửa:* Cập nhật URL synthetic test thành `http://<ALB_OR_AGA>/health`.

---

## Cost note

- CloudWatch Metric Alarms: ~$0.10/alarm/tháng (với 2-3 alarms = ~$0.30/tháng).
- Prometheus & Grafana mã nguồn mở chạy trên tài nguyên compute EKS hiện có.

---

## Next step

Tiếp tục chuyển sang [LAB 14 - Diễn Tập Chuyển Đổi Vùng Có Kế Hoạch (Planned Switchover)](14-planned-switchover.md).
