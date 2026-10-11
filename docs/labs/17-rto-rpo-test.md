# LAB 17 - Bằng chứng RTO/RPO hạ tầng

## 1. Mục tiêu

Tạo báo cáo DR có bằng chứng, tách biệt mục tiêu thiết kế, số đo hạ tầng, quan sát database lag và số đo ứng dụng được hoãn.

## 2. Thành phần sẽ xây dựng

- Bảng timestamp phục hồi từng thành phần.
- Số đo RTO hạ tầng bằng workload kiểm thử và GA.
- Bằng chứng Aurora replication/RPO lag.
- Checklist hoãn rõ ràng cho RTO/RPO nghiệp vụ app2.

## 3. Bối cảnh kiến trúc

```text
T0 tuyên bố sự cố/thay đổi
T1 GA phát hiện endpoint nguồn không khỏe
T2 request mới thành công qua ALB kiểm thử Tokyo
T3 Aurora Tokyo trở thành writer
T4 hoàn tất xác minh hạ tầng

Ứng dụng T5 lần ghi nghiệp vụ thành công đầu tiên: hoãn
Khoảng trống giao dịch RPO ứng dụng: hoãn
```

RTO hạ tầng và RTO ứng dụng là hai tuyên bố khác nhau. CloudWatch lag metric không thay thế kiểm thử RPO cấp giao dịch.

## 4. Điều kiện tiên quyết

- Đã hoàn thành ít nhất một lần chạy LAB 14 hoặc LAB 15 được phê duyệt.
- Đã giữ timestamp UTC và biểu đồ CloudWatch.
- Không giả định app2 đã được triển khai.
- Mọi bằng chứng xác định tài khoản, Region, tài nguyên và ngày kiểm thử nhưng không chứa secret.

## 5. Quy ước đặt tên tài nguyên

Thư mục bằng chứng đề xuất, nằm ngoài dữ liệu secret của Git:

```text
evidence/<YYYY-MM-DD>-dr-drill/
```

Tên báo cáo: `infrastructure-dr-report.md`. Không commit ảnh chứa dữ liệu nhạy cảm của tài khoản nếu chưa làm sạch.

## 6. Các bước triển khai

### 6.1 Ghi mục tiêu thiết kế

| Mục tiêu | Mục tiêu thiết kế | Đo thực tế |
|---|---:|---|
| Phục hồi lưu lượng hạ tầng | `< 5 phút` | `Chưa kiểm thử` tới khi có số liệu |
| Mục tiêu Aurora RPO lag | `< 30 giây` | `Chưa kiểm thử` tới khi có số liệu |
| RTO ghi của ứng dụng | `< 5 phút` | `HOÃN SANG GIAI ĐOẠN ỨNG DỤNG` |
| RPO giao dịch ứng dụng | `< 30 giây` | `HOÃN SANG GIAI ĐOẠN ỨNG DỤNG` |

### 6.2 Điền timestamp sự kiện

| Sự kiện | Timestamp UTC | Nguồn bằng chứng |
|---|---|---|
| T0 tuyên bố diễn tập/sự cố | | incident log |
| T1 endpoint SG không khỏe | | GA/CloudWatch |
| T2 HTTP Tokyo thành công | | curl log |
| T3 writer Tokyo hoạt động | | RDS event/topology |
| T4 hoàn tất xác minh nền tảng | | checklist |

Tính và báo cáo:

- Phục hồi mạng: `T2 - T0`.
- Promote cơ sở dữ liệu: `T3 - T0`.
- Phục hồi hạ tầng: `T4 - T0`.

### 6.3 Thu bằng chứng Aurora lag

Export hoặc chụp metric Tokyo quanh `T0`:

- `AuroraGlobalDBReplicationLag`
- `AuroraGlobalDBProgressLag`
- `AuroraGlobalDBRPOLag`
- `AuroraReplicaLag` khi phù hợp

Ghi statistic, period, timezone, giá trị lớn nhất quan sát được và khoảng thiếu dữ liệu của metric.

### 6.4 Xác minh trạng thái nền tảng sau diễn tập

```bash
aws rds describe-global-clusters --region <CURRENT_PRIMARY_REGION> --global-cluster-identifier app2-global-db
kubectl --context singapore get nodes
kubectl --context tokyo get nodes
kubectl --context singapore -n infra-validation get pods,ingress
kubectl --context tokyo -n infra-validation get pods,ingress
aws secretsmanager describe-secret --region ap-southeast-1 --secret-id /app2/database
aws secretsmanager describe-secret --region ap-northeast-1 --secret-id /app2/database
```

### 6.5 Giữ phương pháp kiểm thử ứng dụng cho Giai đoạn 3

Hai script `scripts/dr/rpo-writer.sh` và `scripts/dr/rpo-check.sh` cần endpoint app2 `/api/v1/orders`. Không chạy ở giai đoạn này. Trong Giai đoạn 3, chúng sẽ đo sequence cuối cùng đã được xác nhận so với sequence cao nhất phục hồi được sau failover.

## 7. Xác minh

Báo cáo chỉ đạt khi mọi số đo liên kết tới bằng chứng có timestamp và mọi số chưa đo được ghi `Chưa kiểm thử` hoặc `Đã hoãn`.

## 8. Kết quả mong đợi

Báo cáo DR hạ tầng trung thực. Không bịa RTO/RPO và không tuyên bố ứng dụng thành công.

## 9. Xử lý sự cố

- Đồng hồ lệch: dùng UTC và đồng bộ clock hệ thống.
- Thiếu metric: ghi lại khoảng trống; không nội suy thành kết quả đạt được.
- Không rõ nguồn phản hồi GA: dùng nội dung phản hồi riêng theo Region trong workload kiểm thử ở lần cải tiến sau, hoặc đối chiếu ALB access log/target metric.
- Database lag nhỏ hơn độ phân giải period: báo cáo độ phân giải và giới hạn của metric.

## 10. Lưu ý bảo mật

- Che account ID nếu chính sách portfolio public yêu cầu.
- Không thu giá trị secret, token, kubeconfig, cookie hoặc private key.
- Với diễn tập production, lưu bằng chứng thô ở dạng bất biến và giới hạn truy cập.

## 11. Lưu ý chi phí

Bài diễn tập dùng tài nguyên đang chạy; log, metric, request, snapshot và truyền dữ liệu phát sinh chi phí bổ sung.

## 12. Dọn dẹp / Quay lui

Trở về topology ổn định mong muốn được mô tả trong LAB 16. Không xóa bằng chứng cần cho audit. Teardown tài nguyên theo LAB 18.

## 13. Bằng chứng cần thu thập

- Bảng mục tiêu so với số đo đã hoàn tất.
- Event log UTC thô.
- Biểu đồ CloudWatch đã export.
- Trạng thái RDS và GA trước/sau.
- Danh sách rõ ràng các kiểm thử ứng dụng được hoãn.

## 14. Lab tiếp theo

Tiếp tục với [LAB 18 - Dọn dẹp an toàn theo thứ tự phụ thuộc](18-cleanup.md).
