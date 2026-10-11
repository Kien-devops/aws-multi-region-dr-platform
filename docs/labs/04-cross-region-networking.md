# LAB 04 - Thiết Lập Kết Nối Mạng Đa Vùng (Cross-Region Networking & VPC Peering)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Tạo một kết nối mạng an toàn xuyên vùng (Inter-Region VPC Peering Connection) giữa `dr-sg-vpc` (`10.10.0.0/16`) tại Singapore và `dr-tokyo-vpc` (`10.20.0.0/16`) tại Tokyo.
2. Chấp nhận yêu cầu kết nối Peering tại Console vùng Tokyo và định tuyến bảng Route Tables hai đầu.
3. **Hiểu bản chất chính xác của VPC Peering trong kiến trúc:**
   - **Lưu ý cốt lõi:** Cơ chế sao chép lưu trữ của Amazon Aurora Global Database (Physical Storage Replication) **hoàn toàn tự động chạy trên mạng ngầm của AWS và KHÔNG PHỤ THUỘC vào VPC Peering**.
   - **Mục đích thực tế của VPC Peering:**
     - Phục vụ kết nối quản trị chéo vùng (Cross-Region DB Administration & Troubleshooting).
     - Cho phép ứng dụng/tooling tại Tokyo kết nối tạm thời tới Singapore Writer trong các kịch bản kiểm thử, đồng bộ cache, hoặc liên kết metrics giữa Prometheus của hai cụm.
4. Thiết lập Security Group liên vùng theo nguyên tắc Least Privilege (không mở 0.0.0.0/0).

---

## Architecture impact

```text
+------------------------------------+             +------------------------------------+
| SINGAPORE: dr-sg-vpc               |             | TOKYO: dr-tokyo-vpc                |
| CIDR: 10.10.0.0/16                 |             | CIDR: 10.20.0.0/16                 |
|                                    |             |                                    |
| [ Private Route Table ]            |             | [ Private Route Table ]            |
| Route: 10.20.0.0/16 -> pcx-xxxx    |             | Route: 10.10.0.0/16 -> pcx-xxxx    |
+------------------------------------+             +------------------------------------+
                  \                                               /
                   \                                             /
                    \                                           /
                     ===> [ Inter-Region VPC Peering ] <===
                               (dr-sg-to-tokyo-peering)
                         Mục đích: Admin, Debug, Metrics Sync
                         (Không dùng cho Aurora storage replication)
```

---

## Resource naming

- Peering Connection Name: `dr-sg-to-tokyo-peering`
- Requester VPC: `dr-sg-vpc` (`ap-southeast-1`)
- Accepter VPC: `dr-tokyo-vpc` (`ap-northeast-1`)
- Peering ID: Tự sinh bởi AWS (định dạng `pcx-xxxxxxxxxxxxxxxxx`)

---

## AWS Console Steps

### Bước 1: Tạo Yêu Cầu Kết Nối Peering tại Singapore (Requester)
1. Mở AWS Console, chuyển sang Region **Asia Pacific (Singapore) ap-southeast-1**.
2. Tìm kiếm và chọn dịch vụ **VPC**.
3. Ở menu thanh bên trái, cuộn xuống mục **Virtual private cloud** -> Chọn **Peering connections**.
4. Nhấn nút màu cam **Create peering connection**.
5. Điền các trường cấu hình:
   - **Name:** `dr-sg-to-tokyo-peering`
   - **VPC ID (Requester):** Chọn `dr-sg-vpc` từ danh sách.
6. Tại mục **Select another VPC to peer with**:
   - Tích chọn **Another Region** (Vùng khác).
   - Danh sách vùng: Chọn **Asia Pacific (Tokyo) ap-northeast-1**.
   - VPC ID (Accepter): Nhập chính xác VPC ID của `dr-tokyo-vpc`.
7. Nhấn nút **Create peering connection**.
8. Màn hình hiển thị trạng thái `Pending acceptance`.

### Bước 2: Chấp Nhận Kết Nối Peering tại Tokyo (Accepter)
1. Chuyển sang Region **Asia Pacific (Tokyo) ap-northeast-1** ở góc trên bên phải.
2. Vào dịch vụ **VPC** -> Chọn **Peering connections**.
3. Chọn kết nối `dr-sg-to-tokyo-peering` đang ở trạng thái `Pending acceptance`.
4. Nhấn menu **Actions** -> Chọn **Accept request**.
5. Xác nhận **Accept request**. Trạng thái chuyển sang màu xanh **Active**.

### Bước 3: Cập Nhật Route Table tại Singapore
1. Chuyển lại Region về **Asia Pacific (Singapore) ap-southeast-1**.
2. Vào VPC -> **Route tables** -> Chọn bảng `dr-sg-priv-rt`.
3. Chuyển sang tab **Routes** -> Nhấn **Edit routes** -> **Add route**:
   - **Destination:** Nhập `10.20.0.0/16`.
   - **Target:** Chọn **Peering Connection** -> Chọn `dr-sg-to-tokyo-peering`.
4. Nhấn **Save changes**.

### Bước 4: Cập Nhật Route Table tại Tokyo
1. Chuyển sang Region **Asia Pacific (Tokyo) ap-northeast-1**.
2. Vào VPC -> **Route tables** -> Chọn bảng `dr-tokyo-priv-rt`.
3. Chuyển sang tab **Routes** -> Nhấn **Edit routes** -> **Add route**:
   - **Destination:** Nhập `10.10.0.0/16`.
   - **Target:** Chọn **Peering Connection** -> Chọn `dr-sg-to-tokyo-peering`.
4. Nhấn **Save changes**.

---

## Configuration & Mô Hình Kết Nối Dữ Liệu

| Phía kết nối | Region | VPC CIDR | Route đích | Target |
|---|---|---|---|---|
| **Requester (Singapore)** | `ap-southeast-1` | `10.10.0.0/16` | `10.20.0.0/16` | `pcx-xxxx` |
| **Accepter (Tokyo)** | `ap-northeast-1` | `10.20.0.0/16` | `10.10.0.0/16` | `pcx-xxxx` |

> **Làm rõ mô hình kết nối của Ứng dụng:**
> - Trong điều kiện hoạt động bình thường, backend tại Singapore kết nối trực tiếp vào Aurora Singapore Writer qua mạng local VPC.
> - Cụm backend Warm Standby tại Tokyo kết nối vào Aurora Tokyo Secondary Replica (Read-Only). Các transaction ghi tại Tokyo sẽ bị chặn cho đến khi diễn ra sự kiện DR Failover thăng cấp cụm Tokyo thành Writer.
> - Nếu muốn Tokyo backend có thể ghi tạm thời về Singapore trước khi failover, đường truyền VPC Peering này cung cấp tuyến đường kết nối riêng tư (với độ trễ mạng khoảng 60-70ms giữa SG và Tokyo).

---

## Security considerations

- **Kiểm soát cổng bảo mật:** Chỉ cho phép cổng PostgreSQL 5432 hoặc cổng metrics/debug qua Peering.
- **Không bao giờ route 0.0.0.0/0 qua Peering:** Chỉ định tuyến gói tin nằm trong 2 dải CIDR riêng `10.10.0.0/16` và `10.20.0.0/16`.

---

## Expected result

- Peering connection hiển thị `Active`.
- Private Route Tables ở cả Singapore và Tokyo có route trỏ về mã `pcx-...`.

---

## Verification

### Kiểm tra bằng CLI
```bash
aws ec2 describe-vpc-peering-connections --region ap-southeast-1 \
  --filters "Name=status-code,Values=active" \
  --query "VpcPeeringConnections[*].[VpcPeeringConnectionId,RequesterVpcInfo.CidrBlock,AccepterVpcInfo.CidrBlock,Status.Code]" \
  --output table
```

---

## Troubleshooting

1. **Lỗi: Peering connection mãi ở `Pending acceptance`:**
   - *Nguyên nhân:* Chưa chấp nhận request ở Console vùng Tokyo.
   - *Cách sửa:* Sang Tokyo VPC Console -> Peering connections -> Actions -> Accept request.
2. **Lỗi: Route Table báo lỗi `blackhole`:**
   - *Nguyên nhân:* Peering connection bị xóa hoặc từ chối sau khi add route.
   - *Cách sửa:* Xóa route cũ và cấu hình lại.
3. **Lỗi: Nhầm lẫn Aurora storage replication cần Peering:**
   - *Nguyên nhân:* Hiểu sai bản chất hạ tầng AWS.
   - *Cách sửa:* Ghi nhớ: Aurora replication chạy ngầm trên Storage Virtualization Network của AWS, không đi qua VPC Peering.

---

## Cost note

- Bản thân kết nối VPC Peering là **hoàn toàn miễn phí** ($0.00/giờ).
- Chỉ phát sinh phí truyền tải dữ liệu thực tế xuyên vùng (Cross-Region Data Transfer Out): ~$0.09/GB (xấp xỉ, kiểm tra AWS Pricing Calculator).

---

## Next step

Tiếp tục chuyển sang [LAB 05 - Khởi Tạo Cụm Kubernetes EKS Singapore](05-eks-singapore.md).
