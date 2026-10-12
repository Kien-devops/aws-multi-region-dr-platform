# LAB 16 - Failback hạ tầng có kiểm soát

## 1. Mục tiêu

Chỉ đưa primary database và đường lưu lượng ưu tiên về Singapore sau khi Singapore đã được khôi phục, đồng bộ, khỏe mạnh và phê duyệt.

Storage remains an independent state machine. If Tokyo ONTAP is authoritative, use LAB 25 instead of assuming this database failback moves file state.

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

### 6.1 Tái thiết lập Singapore thành Secondary (Re-sync topology)

Sau khi Singapore hồi phục sau thảm họa, không được vội vã chuyển traffic về ngay mà phải đưa Singapore trở lại làm bản sao Secondary đồng bộ của Tokyo:

1. **Trường hợp Singapore vẫn còn trong Global Database:**
   - Mở AWS Console tại **Tokyo (`ap-northeast-1`)** -> kiểm tra RDS Console -> đảm bảo `app2-sg-db` đang ở trạng thái **Available** với vai trò **Secondary / Reader**.
2. **Trường hợp Singapore bị tách rời (Detached) sau Unplanned Failover:**
   - Tại Singapore, xóa cluster cũ đã phân kỳ dữ liệu (sau khi đã backup snapshot nếu cần điều tra).
   - Tại Tokyo RDS Console, chọn `app2-global-db` -> nhấp **Actions** -> **Add AWS Region**.
   - Chọn Region đích là **Asia Pacific (Singapore) ap-southeast-1**.
   - Cấu hình cluster identifier là `app2-sg-db`, chọn VPC `dr-sg-vpc`, DB subnet group `app2-sg-db-subnet-group`, Security group `app2-sg-db-sg`.
   - Nhấp **Add Region** và chờ AWS hoàn tất đồng bộ storage từ Tokyo sang Singapore.

### 6.2 Xác minh đồng bộ và độ trễ Replication Lag

1. Mở dịch vụ **CloudWatch** tại Singapore (`ap-southeast-1`).
2. Kiểm tra metric **AuroraGlobalDBReplicationLag** của cluster Singapore trỏ từ Tokyo:
   - Đảm bảo độ trễ duy trì ổn định dưới mức mục tiêu (dưới 30 giây, lý tưởng là dưới 1 giây).
   - Kiểm tra bằng lệnh CLI:

```bash
aws rds describe-global-clusters --region ap-northeast-1 --global-cluster-identifier app2-global-db
aws rds describe-db-clusters --region ap-southeast-1 --db-cluster-identifier app2-sg-db
```

### 6.3 Xác minh trực tiếp traffic stack Singapore trước khi Failback

Kiểm tra hạ tầng mạng và EKS tại Singapore phải hoạt động hoàn hảo trước khi đón khách:

```bash
kubectl --context singapore get nodes
kubectl --context singapore -n infra-validation get pods,ingress
curl -sS http://<SINGAPORE_ALB_DNS>/
```

### 6.4 Thực hiện Managed Switchover đưa quyền Primary về Singapore

Thao tác Switchover phải được kích hoạt từ Region đang nắm quyền Writer hiện tại (Tokyo):

1. Mở AWS Management Console, chuyển Region sang **Asia Pacific (Tokyo) `ap-northeast-1`**.
2. Truy cập dịch vụ **RDS** -> chọn **Databases**.
3. Tích chọn Global Database `app2-global-db`.
4. Nhấp vào menu **Actions** ở góc trên bên phải -> chọn **Switchover global database**.
5. Tại giao diện **Switchover global database**:
   - **Target DB cluster**: Chọn `app2-sg-db` (Singapore cluster ARN).
   - Nhấp nút **Switchover** màu cam.
6. Chờ quá trình hoán đổi vai trò hoàn tất:
   - `app2-sg-db` (Singapore) chuyển thành **Primary / Writer**.
   - `app2-tokyo-db` (Tokyo) chuyển thành **Secondary / Reader**.
   - Trạng thái cả hai cluster đều chuyển về **Available**.

### 6.5 Khôi phục lưu lượng người dùng về Singapore trên Global Accelerator

1. Truy cập dịch vụ **AWS Global Accelerator** Console.
2. Chọn `dr-global-accelerator` -> chuyển sang tab **Listeners** -> chọn Listener cổng `80`.
3. Tại danh sách **Endpoint groups**:
   - *Khôi phục Singapore lên 100%:*
     - Tích chọn endpoint group của Region **Singapore (`ap-southeast-1`)**.
     - Nhấp **Edit endpoint group** -> chỉnh **Traffic dial (%)** thành `100` -> nhấp **Save changes**.
   - *Hạ Tokyo về chế độ Standby (0%):*
     - Tích chọn endpoint group của Region **Tokyo (`ap-northeast-1`)**.
     - Nhấp **Edit endpoint group** -> chỉnh **Traffic dial (%)** thành `0` -> nhấp **Save changes**.
4. Chờ Accelerator chuyển trạng thái sang **Deployed**.
5. Gửi request mới qua DNS của Global Accelerator:

```bash
curl -sS -H 'Connection: close' http://<ACCELERATOR_DNS_NAME>/
# Kết quả mong đợi trả về: singapore infrastructure validation
```

### 6.6 Đưa Tokyo về trạng thái Warm Standby ổn định

Tokyo duy trì hoạt động với EKS nodes sẵn sàng, ALB khỏe mạnh, Aurora secondary tiếp tục nhận replicate liên tục từ Singapore. Trạng thái nền tảng đã hoàn tất chu trình Failback an toàn.

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
