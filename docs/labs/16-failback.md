# LAB 16 - Failback hạ tầng có kiểm soát

## 1. Mục tiêu

Chỉ đưa primary database và đường lưu lượng ưu tiên về Singapore sau khi Singapore đã được khôi phục, đồng bộ, khỏe mạnh và phê duyệt.

## 2. Thành phần sẽ xây dựng

Không tạo kiến trúc mới. Lab này khôi phục trạng thái ổn định:

- Singapore trở lại làm Aurora primary thông qua managed switchover.
- GA ưu tiên Singapore; traffic dial Tokyo trở về `0`.
- Tokyo tiếp tục là warm standby khỏe mạnh.

## 3. Bối cảnh kiến trúc

Failback là một thay đổi có kế hoạch mới, không phải nút đảo ngược failover. Primary cũ trước hết phải là secondary khỏe mạnh trong global topology hiện tại.

## 4. Điều kiện tiên quyết

- Tokyo hiện là writer duy nhất.
- Regional cluster Singapore tồn tại dưới vai trò secondary đã kết nối và ở trạng thái `available`.
- Engine version/patch tương thích.
- Replication lag và RPO/progress lag ổn định trong khoảng quan sát đã thống nhất.
- EKS, ALB, secret và alarm tại Singapore khỏe mạnh.
- Maintenance window và kế hoạch rollback đã được phê duyệt.

## 5. Quy ước đặt tên tài nguyên

- Primary mục tiêu: `app2-sg-db`
- Primary hiện tại: `app2-tokyo-db`
- ARN mục tiêu: `<SINGAPORE_DB_CLUSTER_ARN>`
- Trạng thái GA ổn định mong muốn: Singapore dial `100`, Tokyo dial `0`.

## 6. Các bước triển khai

### 6.1 Tái thiết lập Singapore thành secondary

Nếu Singapore đã bị detach trong quá trình DR, dùng quy trình RDS Console để thêm/xây lại secondary regional cluster từ primary Tokyo hiện tại. Không tái sử dụng standalone cluster đã phân kỳ như thể nó đã đồng bộ.

### 6.2 Xác minh đồng bộ

```bash
aws rds describe-global-clusters --region ap-northeast-1 --global-cluster-identifier app2-global-db
aws rds describe-db-clusters --region ap-southeast-1 --db-cluster-identifier app2-sg-db
```

Rà lag từ primary Tokyo tới secondary Singapore trong CloudWatch. Ghi lại thời gian quan sát và ngưỡng.

### 6.3 Xác minh trực tiếp traffic stack Singapore

```bash
kubectl --context singapore get nodes
kubectl --context singapore -n infra-validation get pods,ingress
curl -sS http://<SINGAPORE_ALB_DNS>/
```

### 6.4 Thực hiện managed switchover về Singapore

```bash
aws rds switchover-global-cluster \
  --region ap-northeast-1 \
  --global-cluster-identifier app2-global-db \
  --target-db-cluster-identifier <SINGAPORE_DB_CLUSTER_ARN>
```

Chạy tại Region đang chứa primary hiện tại. Chờ Singapore `IsWriter=true`, Tokyo `IsWriter=false` và trạng thái global là `available`.

### 6.5 Khôi phục ưu tiên GA

Đặt traffic dial Singapore `100`, Tokyo `0`. Xác minh kết nối mới qua accelerator.

### 6.6 Đưa Tokyo về warm standby

Giữ stack kiểm thử Tokyo khỏe mạnh. Việc giảm replica ứng dụng được hoãn. Khi app2 được GitOps quản lý, thay desired state trong Git hoặc tạm dừng automated sync theo change control; không dùng lệnh `kubectl scale` không được theo dõi.

## 7. Xác minh

- Singapore là writer duy nhất.
- Tokyo là secondary đã kết nối.
- Global writer endpoint định tuyến ghi tới Singapore.
- Kết nối GA mới dùng Singapore.
- Endpoint Tokyo tiếp tục khỏe và đủ điều kiện failover.
- Mọi alarm trở lại OK hoặc trạng thái dự kiến đã được ghi nhận.

## 8. Kết quả mong đợi

Khôi phục trạng thái warm standby ổn định mà không tuyên bố đã xác minh ứng dụng.

## 9. Xử lý sự cố

- Không chọn được Singapore: cluster chưa phải global secondary khỏe mạnh hoặc engine version khác nhau.
- Lag không ổn định: hoãn failback; không đổi một Region đang ổn định lấy target chưa sẵn sàng.
- Request GA vẫn ở Tokyo: kết nối cũ đang được tái sử dụng hoặc traffic dial chưa cập nhật.
- Dữ liệu endpoint trong secret vẫn trỏ tới regional endpoint cũ: ưu tiên Aurora global writer endpoint; nếu không, cập nhật primary secret và xác minh replication trước khi triển khai ứng dụng.

## 10. Lưu ý bảo mật

- Áp dụng cùng ranh giới change control như planned switchover.
- Giới hạn quyền thay đổi RDS/GA.
- Giữ bằng chứng và bản ghi CloudTrail.
- Không kết nối lại Region có khả năng bị xâm phạm trước khi được bảo mật phê duyệt.

## 11. Lưu ý chi phí

Xây lại secondary, snapshot và truyền dữ liệu liên Region phát sinh chi phí tạm thời. Giữ cả hai Region tới khi bằng chứng phục hồi được chấp nhận.

## 12. Dọn dẹp / Quay lui

Nếu xác minh Singapore thất bại sau switchover và Tokyo vẫn khỏe, dùng managed switchover trở lại Tokyo và khôi phục ưu tiên GA. Ghi đây là một thay đổi riêng.

## 13. Bằng chứng cần thu thập

- Khoảng thời gian đồng bộ và biểu đồ lag.
- RDS topology trước/sau.
- Kiểm tra trực tiếp ALB Singapore và GA.
- GA traffic dial.
- Phê duyệt, timestamp và quyết định rollback.

## 14. Lab tiếp theo

Tiếp tục với [LAB 17 - Bằng chứng RTO/RPO hạ tầng](17-rto-rpo-test.md).
