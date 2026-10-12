# LAB 12 - Kiểm thử hạ tầng Global Accelerator

## 1. Mục tiêu

Tạo AWS Global Accelerator loại standard bằng hai ALB kiểm thử tạm thời; chứng minh định tuyến bình thường tới Singapore và failover theo sức khỏe sang Tokyo mà chưa triển khai app2.

## 2. Thành phần sẽ xây dựng

- Standard accelerator `dr-global-accelerator`.
- TCP listener trên cổng `80` cho bài kiểm thử hạ tầng dùng một lần.
- Endpoint group Singapore với traffic dial `100`.
- Endpoint group Tokyo với traffic dial `0`; health failover vẫn xét endpoint khỏe mạnh có endpoint weight khác không.
- Một ALB endpoint mỗi Region, endpoint weight `128`.

Giai đoạn ứng dụng production phải bổ sung TLS termination và thay hai ALB kiểm thử bằng ALB của app2.

## 3. Bối cảnh kiến trúc

```text
Client -> static IP của Global Accelerator
              | bình thường: traffic dial 100
              +--> Singapore validation ALB -> EKS
              |
              `--> Tokyo validation ALB -> EKS
                   traffic dial 0; đủ điều kiện health failover
```

Với ALB endpoint, Global Accelerator dùng trạng thái sức khỏe của ALB target group. Các trường health check của Global Accelerator không ghi đè health check của ALB. ALB chỉ được coi là khỏe khi mỗi target group gắn kèm có ít nhất một target khỏe mạnh.

## 4. Điều kiện tiên quyết

- Đạt mọi tiêu chí của LAB 11.
- Hai ALB kiểm thử đều internet-facing và khỏe mạnh.
- IAM principal có quyền tạo và gắn tag tài nguyên Global Accelerator.
- Đã thống nhất change window trước khi kiểm thử failover.

## 5. Quy ước đặt tên tài nguyên

| Tài nguyên | Giá trị |
|---|---|
| Accelerator | `dr-global-accelerator` |
| Listener | TCP `80` |
| Singapore ALB | `dr-sg-validation-alb` |
| Tokyo ALB | `dr-tokyo-validation-alb` |
| Endpoint weight | `128` mỗi endpoint |

## 6. Các bước triển khai

### 6.1 Khởi tạo AWS Global Accelerator

1. Mở AWS Management Console, trên thanh tìm kiếm gõ `Global Accelerator` và chọn dịch vụ **AWS Global Accelerator**.
   *(Lưu ý: Global Accelerator là một dịch vụ toàn cầu - Global Service, do đó danh sách tài nguyên không bị phân chia theo Region cụ thể trên thanh điều hướng).*
2. Tại trang tổng quan, nhấp vào nút **Create accelerator** màu cam ở góc trên bên phải.
3. Tại giao diện **Create accelerator**:
   - **Accelerator name**: Nhập `dr-global-accelerator`.
   - **Accelerator type**: Chọn **Standard** (Cung cấp 2 địa chỉ IP tĩnh Anycast định tuyến qua mạng backbone của AWS).
   - **IP address type**: Chọn **IPv4**.
   - **Tags**: Thêm tag `Project=aws-multi-region-dr-platform`, `Environment=lab`.
4. Nhấp nút **Next** ở cuối trang để chuyển sang bước cấu hình Listeners.

### 6.2 Cấu hình Listener (Cổng 80 TCP)

1. Tại bước **Listeners**:
   - **Ports**: Nhập `80`.
   - **Protocol**: Chọn **TCP**.
   - **Client affinity**: Chọn **None** (Không giữ session dính, giúp kiểm tra phân phối và chuyển hướng kết nối failover linh hoạt ngay lập tức).
2. Nhấp nút **Next** để chuyển sang bước tạo Endpoint groups.

> [!NOTE]
> Cấu hình HTTP (cổng 80) này nhằm phục vụ kiểm thử hạ tầng lab. Trong môi trường Production, bắt buộc cấu hình Listener HTTPS (cổng 443) với chứng chỉ TLS/SSL đính kèm trên Application Load Balancers.

### 6.3 Cấu hình Endpoint Group tại Singapore (`ap-southeast-1`)

1. Tại bước **Endpoint groups**:
   - Nhấp nút **Add endpoint group** (hoặc cấu hình tại group đầu tiên):
   - **Region**: Trong danh sách dropdown, chọn **Asia Pacific (Singapore) ap-southeast-1**.
   - **Traffic dial**: Nhập `100` (Cho phép 100% lưu lượng bình thường đi vào Region này).
   - **Health check settings**:
     - **Health check port**: Giữ cổng `80` (hoặc Traffic port).
     - **Health check protocol**: Chọn **TCP** hoặc **HTTP** (Path: `/`).
     - **Health check interval**: `30` seconds.
     - **Threshold count**: `3`.
2. Thêm Endpoint cho Singapore:
   - Tại mục **Endpoints**:
     - **Endpoint type**: Chọn **Application Load Balancer**.
     - **Endpoint**: Nhấp vào ô tìm kiếm và chọn `dr-sg-validation-alb`.
     - **Weight**: Nhập `128` (Trọng số mặc định tối đa).
     - **Client IP preservation**: Tích chọn (được hỗ trợ tự động với ALB).

### 6.4 Cấu hình Endpoint Group tại Tokyo (`ap-northeast-1`)

1. Tiếp tục nhấp nút **Add endpoint group** ở phía dưới:
   - **Region**: Chọn **Asia Pacific (Tokyo) ap-northeast-1**.
   - **Traffic dial**:
     - *Lựa chọn 1 (Failover tự động theo sức khỏe):* Đặt là `100`. Khi cả 2 Region đều khỏe, client gần khu vực Đông Nam Á sẽ ưu tiên Singapore. Khi Singapore sập và chuyển sang Unhealthy, Global Accelerator sẽ tự động chuyển 100% kết nối mới sang Tokyo.
     - *Lựa chọn 2 (Warm Standby thủ công):* Đặt là `0` trong điều kiện hoạt động bình thường, và chỉ tăng lên `100` khi người vận hành ban bố lệnh chuyển đổi DR (xem LAB 14/15).
     - Trong bài lab này, nhập `100` để kiểm tra khả năng tự động failover, hoặc nhập `0` tùy kịch bản diễn tập bạn muốn thực hiện.
   - **Health check settings**: Giữ cổng `80`, giao thức TCP/HTTP path `/`.
2. Thêm Endpoint cho Tokyo:
   - **Endpoint type**: Chọn **Application Load Balancer**.
   - **Endpoint**: Chọn `dr-tokyo-validation-alb`.
   - **Weight**: Nhập `128`.
   - *Lưu ý:* Tuyệt đối không đặt Weight bằng `0` (nếu đặt weight = 0, endpoint sẽ bị loại trừ hoàn toàn khỏi bộ cân bằng tải ngay cả khi khỏe mạnh).
3. Nhấp nút **Next** -> Rà soát lại toàn bộ thông tin -> Nhấp nút **Create accelerator** màu cam.

### 6.5 Chờ kích hoạt và kiểm tra trạng thái sức khỏe (Health status)

1. Trạng thái của Accelerator lúc mới tạo sẽ là *InProgress*. Chờ khoảng 3-5 phút cho đến khi **Status** chuyển sang **Deployed**.
2. Nhấp vào tên `dr-global-accelerator` để mở trang chi tiết:
   - Ghi lại **DNS name** (ví dụ: `a123456789abcdef.awsglobalaccelerator.com`).
   - Ghi lại 2 địa chỉ **Static IP addresses** Anycast (ví dụ: `15.197.xxx.xxx` và `3.33.xxx.xxx`).
3. Chuyển sang tab **Listeners** -> nhấp vào Listener cổng `80`:
   - Kiểm tra bảng **Endpoint groups**: Cả 2 nhóm vùng Singapore và Tokyo phải xuất hiện.
   - Cột **Endpoint health** của cả hai nhóm phải hiển thị màu xanh lá: **Healthy (1/1)**.
   - Nếu hiển thị *Unhealthy*, kiểm tra lại Target Group của ALB tại Region đó xem các Pod có đang phản hồi HTTP 200 tại `/` hay không.

### 6.6 Kiểm thử định tuyến bình thường

```bash
curl -sS http://<GA_STATIC_IP_1>/
curl -sS http://<GA_STATIC_IP_2>/
curl -sS http://<ACCELERATOR_DNS_NAME>/
```

### 6.7 Kiểm thử failover hạ tầng an toàn

Dùng một phương pháp có kiểm soát:

1. Kiểm thử thuận nghịch được ưu tiên: đặt endpoint weight Singapore thành `0`, quan sát kết nối mới dùng Tokyo, sau đó khôi phục về `128`.
2. Kiểm thử sức khỏe: scale Deployment kiểm thử Singapore về không và chờ ALB target group, sau đó GA endpoint, chuyển sang không khỏe.

```bash
kubectl --context singapore -n infra-validation scale deployment/hello --replicas=0
```

Gửi kết nối mới tới địa chỉ GA và xác nhận nội dung đổi thành `tokyo infrastructure validation`. Khôi phục ngay:

```bash
kubectl --context singapore -n infra-validation scale deployment/hello --replicas=2
kubectl --context singapore -n infra-validation rollout status deployment/hello --timeout=5m
```

Kết nối TCP hiện có không được di chuyển; phải kiểm tra bằng request mới.

## 7. Xác minh

```bash
aws globalaccelerator list-accelerators --region us-west-2
aws globalaccelerator list-listeners --accelerator-arn <ACCELERATOR_ARN> --region us-west-2
aws globalaccelerator list-endpoint-groups --listener-arn <LISTENER_ARN> --region us-west-2
aws globalaccelerator describe-endpoint-group --endpoint-group-arn <SG_ENDPOINT_GROUP_ARN> --region us-west-2
aws globalaccelerator describe-endpoint-group --endpoint-group-arn <TOKYO_ENDPOINT_GROUP_ARN> --region us-west-2
```

Global Accelerator là dịch vụ global; AWS CLI sử dụng endpoint `us-west-2`.

## 8. Kết quả mong đợi

- Kết nối mới trong điều kiện bình thường tới Singapore.
- Khi Singapore không còn endpoint khỏe mạnh có weight dương, kết nối mới tới Tokyo dù traffic dial tại đó bằng không.
- Không tuyên bố đã kiểm thử nghiệp vụ ứng dụng hoặc cơ sở dữ liệu.

## 9. Xử lý sự cố

- Endpoint không khỏe: kiểm tra mọi target group gắn với ALB; mỗi target group cần một target khỏe mạnh.
- Request vẫn tới Singapore: kết nối cũ đang được tái sử dụng; buộc tạo kết nối mới.
- Không có phản hồi sau failover: kiểm tra trực tiếp ALB Tokyo, route table, security group, controller và pod.
- Định tuyến ngoài dự kiến: kiểm tra riêng endpoint weight và traffic dial.

## 10. Lưu ý bảo mật

- Listener tạm thời dùng HTTP. Không truyền credential hoặc dữ liệu nhạy cảm.
- Giai đoạn production cần HTTPS, chứng chỉ ACM trên ALB, quyết định về security header/WAF và kiểm soát public origin.
- Giới hạn quyền thay đổi accelerator/endpoint group; audit thay đổi bằng CloudTrail.

## 11. Lưu ý chi phí

Global Accelerator tính phí theo giờ accelerator và dữ liệu truyền. Hai ALB tiếp tục tính phí. Xóa stack sớm sau khi kiểm thử nếu tạm dừng dự án.

## 12. Dọn dẹp / Quay lui

Quay lui bài kiểm thử bằng cách khôi phục replica Singapore và endpoint weight. Việc xóa đầy đủ thuộc LAB 27 vì endpoint group, listener và accelerator có thứ tự phụ thuộc.

## 13. Bằng chứng cần thu thập

- Static IP và tên DNS của accelerator.
- Trạng thái Healthy của hai endpoint.
- Ảnh traffic dial và endpoint weight.
- Output curl của định tuyến bình thường/failover có timestamp.
- Chuyển trạng thái sức khỏe và phục hồi của ALB/target Singapore.

## 14. Lab tiếp theo

Tiếp tục với [LAB 13 - Quan sát hạ tầng](13-observability.md).
