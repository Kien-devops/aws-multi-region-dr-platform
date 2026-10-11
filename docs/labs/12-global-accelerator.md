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

### 6.1 Tạo accelerator

AWS Console:

```text
Global Accelerator -> Accelerators -> Create accelerator
Name: dr-global-accelerator
Accelerator type: Standard
IP address type: IPv4
Enabled: Yes
-> Create accelerator
```

Ghi lại ARN, tên DNS và hai địa chỉ static IP của accelerator.

### 6.2 Thêm listener

```text
Accelerator detail -> Listeners -> Add listener
Ports: 80-80
Protocol: TCP
Client affinity: None
-> Add listener
```

Listener chỉ dùng HTTP này phục vụ lab tạm thời. Production phải dùng HTTPS end-to-end theo thiết kế TLS của ứng dụng.

### 6.3 Thêm endpoint group Singapore

```text
Listener -> Add endpoint group
Region: ap-southeast-1
Traffic dial: 100
Endpoint: dr-sg-validation-alb
Weight: 128
Client IP preservation: Enabled when available
-> Create endpoint group
```

### 6.4 Thêm endpoint group Tokyo

```text
Listener -> Add endpoint group
Region: ap-northeast-1
Traffic dial: 0
Endpoint: dr-tokyo-validation-alb
Weight: 128
Client IP preservation: Enabled when available
-> Create endpoint group
```

Không đặt endpoint weight của Tokyo thành `0`; endpoint có weight bằng không không được chọn trong đánh giá failover khỏe mạnh thông thường.

### 6.5 Chờ endpoint khỏe mạnh

Cả hai endpoint phải hiển thị `Healthy`. Nếu endpoint không khỏe, quay lại kiểm tra ALB target group; thay đổi health setting của GA không sửa được ALB endpoint.

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

Quay lui bài kiểm thử bằng cách khôi phục replica Singapore và endpoint weight. Việc xóa đầy đủ thuộc LAB 18 vì endpoint group, listener và accelerator có thứ tự phụ thuộc.

## 13. Bằng chứng cần thu thập

- Static IP và tên DNS của accelerator.
- Trạng thái Healthy của hai endpoint.
- Ảnh traffic dial và endpoint weight.
- Output curl của định tuyến bình thường/failover có timestamp.
- Chuyển trạng thái sức khỏe và phục hồi của ALB/target Singapore.

## 14. Lab tiếp theo

Tiếp tục với [LAB 13 - Quan sát hạ tầng](13-observability.md).
