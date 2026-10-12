# LAB 04 - Kết nối mạng liên Region

## 1. Mục tiêu

Tạo VPC peering liên Region. Peering vẫn tùy chọn cho Aurora/ECR/Secrets, nhưng là điều kiện bắt buộc của SnapMirror intercluster trong storage DR design này.

## 2. Thành phần sẽ xây dựng

- Peering connection `dr-sg-to-tokyo-peering`.
- Route trên private route table giữa `10.10.0.0/16` và `10.20.0.0/16`.
- Quy tắc CIDR liên Region tối thiểu trên security group, chỉ khi luồng đã kiểm thử thực sự cần.

## 3. Bối cảnh kiến trúc

Replication của Aurora Global Database, ECR, Secrets Manager và Global Accelerator không đi qua peering. SnapMirror giữa hai FSx ONTAP file system dùng private intercluster endpoints và cần route hai chiều.

Trường hợp sử dụng:

- Tạm thời kiểm tra kết nối từ Tokyo tới writer hiện tại thông qua Aurora global writer endpoint.
- Luồng quản trị/giám sát riêng được chủ động thiết kế giữa hai Region.

Có thể bỏ qua peering nếu chỉ làm LAB 00-17. Không được bỏ qua khi tiếp tục LAB 18-26.

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

### 6.1 Khởi tạo yêu cầu Peering tại Singapore

1. Trước khi thực hiện, mở một tab khác vào Region **Tokyo (`ap-northeast-1`)** -> vào **Your VPCs** -> sao chép (copy) **VPC ID** của `dr-tokyo-vpc` (dạng `vpc-0xxxxxxxxxxxxxx`).
2. Quay lại tab AWS Console tại Region **Singapore (`ap-southeast-1`)**.
3. Trong menu bên trái của VPC Console, cuộn xuống mục **Virtual private cloud** -> nhấp chọn **Peering connections**.
4. Nhấp vào nút **Create peering connection** màu cam ở góc trên bên phải.
5. Tại giao diện cấu hình:
   - **Name**: Nhập `dr-sg-to-tokyo-peering`.
   - **VPC ID (Requester)**: Chọn `dr-sg-vpc`.
   - Tại phần **Select another VPC to peer with**:
     - **Account**: Chọn **My account** (Cùng tài khoản AWS).
     - **Region**: Chọn **Another Region** -> trong danh sách dropdown, chọn **Asia Pacific (Tokyo) ap-northeast-1**.
     - **VPC ID (Accepter)**: Dán mã `VPC ID` của `dr-tokyo-vpc` đã copy ở bước 1.
6. Nhấp nút **Create peering connection** màu cam.
7. Trạng thái kết nối ban đầu sẽ hiển thị là *Pending acceptance*. Lưu lại mã **Peering connection ID** (dạng `pcx-0xxxxxxxxxxxxxx`).

### 6.2 Chấp nhận yêu cầu kết nối Peering tại Tokyo

1. Tại góc trên bên phải của AWS Console, chuyển Region sang **Asia Pacific (Tokyo) `ap-northeast-1`**.
2. Trong thanh menu bên trái của VPC Console, nhấp chọn **Peering connections**.
3. Bạn sẽ thấy kết nối `dr-sg-to-tokyo-peering` (hoặc ID tương ứng) đang ở trạng thái *Pending acceptance*.
4. Tích chọn kết nối peering này.
5. Nhấp vào menu **Actions** ở góc trên bên phải -> chọn **Accept request**.
6. Tại hộp thoại xác nhận, nhấp nút **Accept request** màu cam. Trạng thái kết nối sẽ lập tức chuyển sang **Active**.

### 6.3 Cập nhật Bảng định tuyến (Route Tables) hai chiều

Để gói tin có thể đi qua lại giữa 2 VPC, bắt buộc phải cập nhật bảng định tuyến private ở cả hai Region:

#### Bước 1: Thêm tuyến đường tại Singapore (`dr-sg-private-rt`)
1. Chuyển Region về **Asia Pacific (Singapore) `ap-southeast-1`**.
2. Trong menu bên trái, chọn **Route tables** -> tích chọn `dr-sg-private-rt`.
3. Chuyển sang tab **Routes** ở nửa dưới màn hình -> nhấp nút **Edit routes**.
4. Nhấp nút **Add route**:
   - **Destination**: Nhập CIDR của VPC Tokyo: `10.20.0.0/16`.
   - **Target**: Chọn **Peering Connection** -> chọn kết nối `dr-sg-to-tokyo-peering` (`pcx-...`).
5. Nhấp nút **Save changes**.

#### Bước 2: Thêm tuyến đường tại Tokyo (`dr-tokyo-private-rt`)
1. Chuyển Region sang **Asia Pacific (Tokyo) `ap-northeast-1`**.
2. Trong menu bên trái, chọn **Route tables** -> tích chọn `dr-tokyo-private-rt`.
3. Chuyển sang tab **Routes** -> nhấp nút **Edit routes**.
4. Nhấp nút **Add route**:
   - **Destination**: Nhập CIDR của VPC Singapore: `10.10.0.0/16`.
   - **Target**: Chọn **Peering Connection** -> chọn kết nối `dr-sg-to-tokyo-peering` (`pcx-...`).
5. Nhấp nút **Save changes**.

> [!CAUTION]
> Tuyệt đối không thêm tuyến đường `0.0.0.0/0` trỏ qua Peering Connection. Gói tin ra Internet vẫn phải đi qua NAT Gateway cục bộ của từng VPC.

### 6.4 Cấu hình Security Group cho liên kết Cross-Region

Do Security Group trên AWS **không thể** tham chiếu ID chéo vùng (Cross-Region Security Group referencing không được hỗ trợ), mọi quy tắc kết nối phải sử dụng dải IP CIDR cụ thể:

1. **Cho mục đích kiểm thử Database (tạm thời):**
   - Chỉ cho phép Inbound cổng PostgreSQL `5432` từ đúng dải private subnets của VPC đối diện (`10.20.11.0/24`, `10.20.12.0/24` hoặc `10.10.11.0/24`, `10.10.12.0/24`).
2. **Cho SnapMirror (FSx for ONTAP Intercluster Replication):**
   - Cần cho phép các cổng giao tiếp hai chiều giữa các Subnet chứa Intercluster LIFs:
     - **ICMP** (Ping kiểm tra kết nối mạng).
     - **TCP 443** (ONTAP REST API / Quản trị).
     - **TCP 10000** (ONTAP NDMP / Quản trị bổ sung).
     - **TCP 11104** (SnapMirror intercluster communication).
     - **TCP 11105** (SnapMirror data transfer).
   - Tuyệt đối không mở các cổng này ra dải `0.0.0.0/0` hay toàn bộ public subnets.

### 6.5 Tùy chọn phân giải DNS qua Peering (DNS Resolution)

1. Mặc định, các tài nguyên chỉ phân giải được Public IP khi truy vấn hostname của tài nguyên ở VPC bên kia. Nếu muốn phân giải trực tiếp Private IP của EC2/Endpoint:
   - Tại trang **Peering connections** của VPC Singapore, chọn `dr-sg-to-tokyo-peering` -> **Actions** -> **Edit DNS settings**.
   - Tích chọn **Accepter DNS resolution: Allow requester VPC to resolve DNS of accepter VPC to private IP** (nếu cần).
   - Lặp lại tại Tokyo nếu có yêu cầu tương tự.
   - *Lưu ý:* Với kiến trúc này, Aurora và FSx đều sử dụng cơ chế endpoint chuyên biệt nên chưa bắt buộc phải bật DNS resolution qua peering.

## 7. Xác minh

```bash
aws ec2 describe-vpc-peering-connections --region ap-southeast-1 \
  --filters Name=tag:Name,Values=dr-sg-to-tokyo-peering \
  --query 'VpcPeeringConnections[0].{Id:VpcPeeringConnectionId,Status:Status.Code,Requester:RequesterVpcInfo.CidrBlock,Accepter:AccepterVpcInfo.CidrBlock}'
```

Có route là điều kiện cần nhưng chưa đủ. Kiểm thử từ nguồn private đã được phê duyệt sau khi EKS tồn tại; không tạo public test host.

## 8. Kết quả mong đợi

Peering active, route đối xứng, intercluster LIF reachability hai chiều và rules khớp flow matrix. Nếu chỉ làm core labs, quyết định bỏ qua phải được ghi lại.

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

Gỡ SnapMirror relationship/intercluster dependency trước. Sau đó gỡ SG/routes và xóa peering. Thao tác này không dừng Aurora/ECR/Secrets replication nhưng sẽ phá storage replication.

## 13. Bằng chứng cần thu thập

Trạng thái peering, hai route entry, ma trận lưu lượng đã phê duyệt, quy tắc SG và bằng chứng kết nối tùy chọn.

## 14. Lab tiếp theo

Tiếp tục với [LAB 05 - EKS Singapore](05-eks-singapore.md). Storage path quay lại dùng peering ở LAB 19-21.

Nguồn: [AWS SnapMirror prerequisites](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/migrating-fsx-ontap-snapmirror.html), [VPC peering routes](https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-routing.html), [cross-Region SG restriction](https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-security-groups.html).
