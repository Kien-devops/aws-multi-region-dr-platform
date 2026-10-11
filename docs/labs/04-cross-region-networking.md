# LAB 04 - Kết nối mạng liên Region tùy chọn

## 1. Mục tiêu

Tạo VPC peering liên Region tùy chọn cho lưu lượng kiểm tra quản trị/cơ sở dữ liệu qua mạng riêng, đồng thời làm rõ rằng replication của các managed service không phụ thuộc vào kết nối này.

## 2. Thành phần sẽ xây dựng

- Peering connection `dr-sg-to-tokyo-peering`.
- Route trên private route table giữa `10.10.0.0/16` và `10.20.0.0/16`.
- Quy tắc CIDR liên Region tối thiểu trên security group, chỉ khi luồng đã kiểm thử thực sự cần.

## 3. Bối cảnh kiến trúc

Replication storage của Aurora Global Database, ECR replication, Secrets Manager replication và Global Accelerator không đi qua VPC peering này. Peering không bắc cầu và không cung cấp điểm kiểm tra tập trung.

Trường hợp sử dụng:

- Tạm thời kiểm tra kết nối từ Tokyo tới writer hiện tại thông qua Aurora global writer endpoint.
- Luồng quản trị/giám sát riêng được chủ động thiết kế giữa hai Region.

Nếu không cần luồng private liên Region, ghi lại quyết định và bỏ qua việc tạo peering; các lab sau vẫn hoạt động sau regional failover.

## 4. Điều kiện tiên quyết

- Hoàn thành LAB 02-03.
- CIDR không chồng lấn.
- Đã ghi lại VPC ID thực tế.
- Ma trận lưu lượng cần thiết đã được phê duyệt.

## 5. Quy ước đặt tên tài nguyên

| Hạng mục | Giá trị |
|---|---|
| Peering | `dr-sg-to-tokyo-peering` |
| Bên yêu cầu | `dr-sg-vpc` / `ap-southeast-1` |
| Bên chấp nhận | `dr-tokyo-vpc` / `ap-northeast-1` |

## 6. Các bước triển khai

### 6.1 Tạo yêu cầu tại Singapore

```text
VPC Singapore -> Peering connections -> Create peering connection
Name: dr-sg-to-tokyo-peering
Requester VPC: dr-sg-vpc
Account: My account
Region: Another Region -> ap-northeast-1
Accepter VPC ID: <TOKYO_VPC_ID>
-> Create
```

### 6.2 Chấp nhận tại Tokyo

```text
VPC Tokyo -> Peering connections
Select pending request -> Actions -> Accept request
```

### 6.3 Thêm private route

Singapore `dr-sg-private-rt`:

```text
Destination 10.20.0.0/16 -> Peering connection <PCX_ID>
```

Tokyo `dr-tokyo-private-rt`:

```text
Destination 10.10.0.0/16 -> Peering connection <PCX_ID>
```

Không thêm route `0.0.0.0/0` qua peering.

### 6.4 Chỉ thêm quy tắc bảo mật cần thiết

Peering liên Region không thể tham chiếu security group ở Region còn lại. Dùng CIDR private subnet nhỏ nhất khớp luồng đã phê duyệt, tránh dùng toàn bộ CIDR VPC nếu có thể. Ví dụ cho kiểm tra PostgreSQL tạm thời:

```text
DB SG inbound TCP 5432 from peer private subnet CIDRs only
```

Gỡ quy tắc khi không còn phụ thuộc kiểm tra này.

### 6.5 DNS resolution tùy chọn

Chỉ bật DNS resolution cho peering khi hành vi private DNS được yêu cầu rõ ràng và đã kiểm thử. Aurora endpoint đã dùng DNS của dịch vụ; không thay đổi cấu hình khi chưa có nhu cầu cụ thể.

## 7. Xác minh

```bash
aws ec2 describe-vpc-peering-connections --region ap-southeast-1 \
  --filters Name=tag:Name,Values=dr-sg-to-tokyo-peering \
  --query 'VpcPeeringConnections[0].{Id:VpcPeeringConnectionId,Status:Status.Code,Requester:RequesterVpcInfo.CidrBlock,Accepter:AccepterVpcInfo.CidrBlock}'
```

Có route là điều kiện cần nhưng chưa đủ. Kiểm thử từ nguồn private đã được phê duyệt sau khi EKS tồn tại; không tạo public test host.

## 8. Kết quả mong đợi

Peering ở trạng thái active và có private route đối xứng, hoặc có quyết định bỏ qua được ghi nhận, chứng minh peering không bắt buộc cho managed replication.

## 9. Xử lý sự cố

- `Pending acceptance`: chấp nhận yêu cầu tại Tokyo.
- Route `Blackhole`: peering đã bị xóa hoặc chưa active.
- Timeout: kiểm tra cả hai route table, NACL, SG, DNS và đường về.
- Tham chiếu SG bị từ chối: đây là hành vi dự kiến giữa hai Region; dùng CIDR của peer.
- Mong đợi route bắc cầu: không được hỗ trợ; peering chỉ nối trực tiếp hai VPC.

## 10. Lưu ý bảo mật

- Không mở rộng port hoặc dùng quy tắc `0.0.0.0/0`.
- Ghi log/giám sát lưu lượng liên Region khi cần.
- Với nhiều VPC/tài khoản hoặc yêu cầu kiểm tra tập trung, Transit Gateway có thể dễ vận hành hơn nhưng chi phí cao hơn.

## 11. Lưu ý chi phí

Peering không tính phí theo giờ, nhưng lưu lượng dữ liệu liên Region có tính phí. Kiểm tra bảng giá hiện hành.

## 12. Dọn dẹp / Quay lui

Gỡ các quy tắc SG và route phụ thuộc, sau đó xóa peering connection. Thao tác này không dừng Aurora/ECR/Secrets replication.

## 13. Bằng chứng cần thu thập

Trạng thái peering, hai route entry, ma trận lưu lượng đã phê duyệt, quy tắc SG và bằng chứng kết nối tùy chọn.

## 14. Lab tiếp theo

Tiếp tục với [LAB 05 - EKS Singapore](05-eks-singapore.md).
