# LAB 15 - Chuẩn bị failover hạ tầng ngoài kế hoạch

> **Mức ảnh hưởng cao:** Global Database failover có thể chấp nhận mất dữ liệu. Chỉ chạy trong tài khoản lab cô lập hoặc production GameDay đã được phê duyệt rõ ràng.

## 1. Mục tiêu

Chuẩn bị và thực hiện Aurora Global Database failover ngoài kế hoạch sang Tokyo khi được phê duyệt rõ ràng, đồng thời xác minh định tuyến GA. Giao dịch nghiệp vụ ứng dụng tiếp tục được hoãn.

## 2. Thành phần sẽ xây dựng

- Cổng quyết định sự cố và kiểm soát split-brain.
- Bằng chứng failover hạ tầng có timestamp.
- Không cần giả lập sự cố phá hủy cả Region; người vận hành gọi trực tiếp quy trình managed failover.

## 3. Bối cảnh kiến trúc

```text
Singapore không khả dụng hoặc bị tuyên bố không an toàn
  -> đóng băng ghi / cô lập primary cũ
  -> promote Tokyo bằng Global Database failover
  -> định tuyến kết nối GA mới tới Tokyo
  -> xác minh EKS, ALB, secret và database writer
```

Failover có thể làm mất giao dịch chưa được replicate. Đây là thao tác khác planned switchover.

## 4. Điều kiện tiên quyết

- Incident Commander tuyên bố failover rõ ràng.
- Có bằng chứng Singapore không khả dụng hoặc không an toàn để phục vụ ghi.
- EKS Tokyo, ALB kiểm thử, secret replica và dung lượng node đều khỏe mạnh.
- Đã thu bằng chứng replication/RPO lag mới nhất nếu có.
- Đường ghi vào primary cũ được cô lập tối đa trong khả năng vận hành.
- Không giả định có rollback/failback tức thời; quá trình phục hồi tiếp tục qua LAB 16.

## 5. Quy ước đặt tên tài nguyên

Dùng cùng tên chuẩn như LAB 14. Ghi lại `<TOKYO_DB_CLUSTER_ARN>`, ARN endpoint group, incident ID, người vận hành và người phê duyệt.

## 6. Các bước triển khai

### 6.1 Tuyên bố sự cố và ghi timestamp

Ghi `T0`, lý do, blast radius, Aurora lag cuối cùng đã biết và xác nhận chưa triển khai workload app2.

### 6.2 Cô lập Singapore

- Đặt GA endpoint weight hoặc traffic dial Singapore thành `0` nếu control plane còn truy cập được.
- Không scale thủ công workload ứng dụng do GitOps quản lý ở Giai đoạn 2, trừ khi đã tạm dừng automated sync hoặc thay đổi desired state trong Git.
- Không cho phép cả hai regional database cluster cùng nhận ghi.

### 6.3 Gọi Global Database failover

AWS Console:

```text
RDS -> Global databases -> app2-global-db
Actions -> Switchover or failover global database
Operation: Failover
Target: app2-tokyo-db
Review possible data loss -> Confirm only with authorization
```

Lệnh CLI tương đương đã được phê duyệt:

```bash
aws rds failover-global-cluster \
  --region ap-southeast-1 \
  --global-cluster-identifier app2-global-db \
  --target-db-cluster-identifier <TOKYO_DB_CLUSTER_ARN> \
  --allow-data-loss
```

Không chạy lệnh này như một bài kiểm tra kết nối.

### 6.4 Định tuyến lưu lượng tới Tokyo

Đặt traffic dial Tokyo `100` và Singapore `0`. Xác nhận endpoint weight Tokyo vẫn dương và trạng thái sức khỏe màu xanh.

### 6.5 Xác minh hạ tầng

```bash
aws rds describe-global-clusters --region ap-northeast-1 --global-cluster-identifier app2-global-db
kubectl --context tokyo get nodes
kubectl --context tokyo -n infra-validation get pods,ingress
aws secretsmanager describe-secret --region ap-northeast-1 --secret-id /app2/database
curl -sS -H 'Connection: close' http://<ACCELERATOR_DNS_NAME>/
```

## 7. Xác minh

- Tokyo là writer duy nhất và global writer endpoint phân giải được.
- Kết nối GA mới tới Tokyo.
- ALB Tokyo có target khỏe mạnh.
- Secret replica vẫn khả dụng.
- Singapore không được coi là primary khỏe mạnh có thể ghi.
- RPO ứng dụng là `Chưa đo`; chỉ báo cáo metric dịch vụ và timestamp.

## 8. Kết quả mong đợi

Có thể promote nền tảng sang Tokyo trong tình huống ngoài kế hoạch. Mọi mất dữ liệu phải được ghi nhận, không bao giờ mặc định bằng không.

## 9. Xử lý sự cố

- Failover API không khả dụng qua endpoint Singapore: dùng AWS control-plane endpoint/Console session khác còn truy cập được theo quy trình sự cố; không tạo cơ sở dữ liệu độc lập thứ hai.
- Target cluster không khỏe: dừng; promote standby đang lỗi sẽ làm sự cố nghiêm trọng hơn.
- GA fail-open: nếu không có endpoint khỏe, GA có thể định tuyến tới endpoint không khỏe. Kiểm tra sức khỏe endpoint trước khi tuyên bố phục hồi.
- Primary cũ hoạt động trở lại: tiếp tục cô lập tới khi topology RDS và kế hoạch reconciliation được xác nhận.

## 10. Lưu ý bảo mật

- Tách vai trò sự cố: người phê duyệt, người vận hành, người xác minh, người ghi nhận.
- Bảo vệ quyền failover bằng đặc quyền tối thiểu, MFA và CloudTrail.
- Không dán secret vào kênh trao đổi sự cố hoặc bằng chứng.
- Không fault injection khi chưa có điều kiện dừng và blast radius được phê duyệt.

## 11. Lưu ý chi phí

Không có dịch vụ cố định mới. Log sự cố, truyền dữ liệu, snapshot và thời gian vận hành hai Region kéo dài có thể tăng chi phí.

## 12. Dọn dẹp / Quay lui

Không có rollback tức thời sau unplanned failover. Ổn định Tokyo, đánh giá primary cũ, tái thiết lập secondary khỏe mạnh rồi làm theo LAB 16. Không chuyển lưu lượng về chỉ vì Singapore xuất hiện trở lại.

## 13. Bằng chứng cần thu thập

- Quyết định và phê duyệt sự cố.
- Lag metric cuối cùng đã biết.
- RDS event và writer topology.
- Trạng thái định tuyến/sức khỏe GA.
- Timestamp từ `T0` tới khi xác minh xong hạ tầng.
- Ghi rõ `RTO/RPO ứng dụng: HOÃN SANG GIAI ĐOẠN ỨNG DỤNG`.

## 14. Lab tiếp theo

Tiếp tục với [LAB 16 - Failback hạ tầng có kiểm soát](16-failback.md).
