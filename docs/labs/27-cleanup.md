# LAB 27 - Dọn dẹp an toàn theo thứ tự phụ thuộc

> **Lab có thao tác phá hủy:** Lab này xóa hạ tầng đang tính phí và có thể xóa dữ liệu vĩnh viễn. Xác nhận tài khoản, Region, resource ID, yêu cầu lưu giữ và quyết định final snapshot trước từng thao tác xóa.

## 1. Mục tiêu

Xóa lab an toàn theo thứ tự phụ thuộc, xác minh không còn tài nguyên tính phí và giữ bằng chứng/snapshot bắt buộc.

## 2. Thành phần sẽ xây dựng

Không tạo tài nguyên. Lab này tạo ra:

- Checklist xóa đã được phê duyệt.
- Inventory cuối cùng và kiểm tra chi phí.
- Bản ghi lưu giữ snapshot/bằng chứng.

## 3. Bối cảnh kiến trúc

```text
Kubernetes Ingress/workload
  -> ALB/target group/security group
  -> Global Accelerator endpoint/group/listener/accelerator
  -> Argo CD/add-on nền tảng
  -> EKS node group/cluster
  -> Aurora secondary/primary/global cluster
  -> Secrets/ECR/IAM
  -> Peering/NAT/IGW/subnet/VPC
```

Xóa VPC trước sẽ gây lỗi phụ thuộc và bỏ sót tài nguyên vẫn tính phí.

## 4. Điều kiện tiên quyết

- Có phê duyệt bằng văn bản để phá hủy lab.
- Đã xác nhận đúng tài khoản AWS bằng `aws sts get-caller-identity`.
- Đã ghi Region writer hiện tại và database topology.
- Đã ghi quyết định cho final snapshot, ECR image, recovery window của secret, log và bằng chứng.
- app2 vẫn chưa triển khai; nếu Giai đoạn 2 đã bắt đầu, phải mở rộng kế hoạch dọn dẹp trước khi tiếp tục.

## 5. Quy ước đặt tên tài nguyên

Các tài nguyên chuẩn gồm:

- EKS: `dr-sg-eks`, `dr-tokyo-eks`; node group `dr-sg-ng`, `dr-tokyo-ng`.
- VPC: `dr-sg-vpc`, `dr-tokyo-vpc`.
- NAT: `dr-sg-nat`, `dr-tokyo-nat`.
- Aurora: `app2-global-db`, `app2-sg-db`, `app2-tokyo-db`.
- Secret: `/app2/database`.
- GA: `dr-global-accelerator`.
- Storage: `dr-file-global-accelerator`, `dr-*-storage-alb`, `dr-*-storage-ec2`, `dr-*-fsx-ontap`, `dr-*-svm`, `dr-data*`.
- ECR: năm repository `app2-*`, gồm `app2-file-service`.

Dùng ID thực tế từ tài khoản; chỉ tên tài nguyên không đủ để cho phép xóa.

## 6. Các bước triển khai

> [!CAUTION]
> **Thứ tự phụ thuộc bắt buộc (Strict Teardown Order):** Bắt buộc phải xóa từ tầng trên cùng (Global Accelerator, Load Balancers, Compute workloads) xuống tầng lưu trữ dữ liệu (FSx, RDS), rồi mới đến tầng hạ tầng mạng cơ sở (VPC Peering, NAT Gateways, Subnets, VPCs). Việc xóa VPC trước sẽ luôn thất bại do vi phạm ràng buộc phụ thuộc (ENIs, Route Tables, Security Groups đang hoạt động).

---

### Bước 1: Xóa Tầng Định tuyến Toàn cầu (AWS Global Accelerator)

1. Mở **AWS Global Accelerator Console** tại [https://console.aws.amazon.com/globalaccelerator/](https://console.aws.amazon.com/globalaccelerator/) (Global service).
2. **Xóa `dr-storage-accelerator`:**
   - Nhấp vào tên **`dr-storage-accelerator`**.
   - Chuyển sang tab **Listeners** -> nhấp vào **`Port 80 (TCP)`**.
   - Trong danh sách **Endpoint groups**:
     - Chọn nhóm `ap-southeast-1` -> bấm nút **Delete endpoint group** -> xác nhận xóa.
     - Chọn nhóm `ap-northeast-1` -> bấm nút **Delete endpoint group** -> xác nhận xóa.
   - Quay lại tab **Listeners** -> chọn listener `Port 80` -> bấm nút **Delete**.
   - Quay lại trang chi tiết Accelerator:
     - Nhấp nút **Edit** ở góc phải -> bỏ chọn **Enabled** -> bấm **Save changes**.
     - Sau khi trạng thái chuyển sang **Disabled**, nhấp nút **Delete** -> gõ `delete` vào hộp thoại -> bấm **Delete**.
3. **Xóa `dr-platform-accelerator`:**
   - Lặp lại toàn bộ các thao tác trên để xóa Endpoint groups, Listener, Disable và Delete `dr-platform-accelerator`.

---

### Bước 2: Xóa Tầng Load Balancer và Target Groups

1. **Tại Region Tokyo (`ap-northeast-1`):**
   - Mở **EC2 Console** -> cuộn xuống mục **Load Balancing** -> chọn **Load Balancers**.
   - Tìm chọn các ALB của lab: ALB do Ingress tạo ra (`k8s-drplatform-...`) và ALB Storage **`dr-tokyo-storage-alb`**.
   - Nhấp menu dropdown **Actions** ở góc trên -> chọn **Delete load balancer** -> xác nhận xóa.
   - Tại menu trái chọn **Target Groups**:
     - Chọn các target groups liên quan: `dr-tokyo-storage-tg` và các target groups của EKS.
     - Nhấp menu **Actions** -> chọn **Delete** -> xác nhận xóa.
2. **Tại Region Singapore (`ap-southeast-1`):**
   - Đổi region sang Singapore trên Navigation bar.
   - Lặp lại thao tác xóa Load Balancers (`dr-sg-storage-alb`, `k8s-...`) và xóa các Target Groups liên quan (`dr-sg-storage-tg`).

---

### Bước 3: Dọn dẹp Tầng Storage DR (EC2 Instances & Amazon FSx for ONTAP)

1. **Terminate Storage EC2 Instances:**
   - Tại EC2 Console Singapore: Chọn **Instances** -> tích chọn **`dr-sg-storage-ec2`** -> chọn menu **Instance state** -> **Terminate instance** -> bấm **Terminate**.
   - Đổi sang Region Tokyo: Chọn **Instances** -> tích chọn **`dr-tokyo-storage-ec2`** -> chọn menu **Instance state** -> **Terminate instance** -> bấm **Terminate**.

2. **Xóa Amazon FSx for ONTAP tại Tokyo (`ap-northeast-1`):**
   - Chọn Region Tokyo -> Mở **Amazon FSx Console** tại [https://console.aws.amazon.com/fsx/](https://console.aws.amazon.com/fsx/).
   - Tại menu trái, chọn **Volumes**:
     - Tích chọn volume **`dr-data-dr`** -> nhấp menu **Actions** -> chọn **Delete volume**.
     - Bỏ tích ô "Create final backup" (nếu không cần lưu trữ sau lab) hoặc tạo backup nếu cần lưu giữ.
     - Gõ tên volume `dr-data-dr` để xác nhận -> bấm **Delete volume**.
   - Chọn mục **Storage virtual machines**:
     - Tích chọn **`dr-tokyo-svm`** -> nhấp **Actions** -> chọn **Delete storage virtual machine** -> xác nhận xóa.
   - Chọn mục **File systems**:
     - Tích chọn **`dr-tokyo-fsx`** -> nhấp **Actions** -> chọn **Delete file system**.
     - Bỏ tích ô "Create final backup" -> gõ File system ID (ví dụ: `fs-0123456789abcdef0`) -> bấm **Delete file system**.

3. **Xóa Amazon FSx for ONTAP tại Singapore (`ap-southeast-1`):**
   - Đổi Region sang Singapore trên Navigation bar.
   - Thực hiện tương tự: Xóa volume **`dr-data`** -> Xóa SVM **`dr-sg-svm`** -> Xóa File system **`dr-sg-fsx`**.

---

### Bước 4: Xóa EKS Node Groups và EKS Clusters

> [!IMPORTANT]
> Bắt buộc phải xóa Managed Node Group trước và đợi chuyển sang trạng thái đã xóa hoàn toàn thì mới được xóa EKS Cluster.

1. **Xóa EKS Cluster Tokyo (`ap-northeast-1`):**
   - Mở **Amazon EKS Console** tại Region Tokyo.
   - Chọn **Clusters** -> nhấp vào **`dr-tokyo-eks`**.
   - Chuyển sang tab **Compute**:
     - Trong mục **Node groups**, chọn **`dr-tokyo-ng`** -> bấm nút **Delete** -> gõ `dr-tokyo-ng` -> bấm **Delete**.
     - Chờ khoảng 3-5 phút cho đến khi Node group biến mất hoàn toàn.
   - Quay lại trang chi tiết cluster `dr-tokyo-eks`:
     - Nhấp nút **Delete cluster** ở góc trên bên phải -> gõ `dr-tokyo-eks` -> bấm **Delete**.

2. **Xóa EKS Cluster Singapore (`ap-southeast-1`):**
   - Mở **Amazon EKS Console** tại Region Singapore.
   - Chọn **Clusters** -> nhấp vào **`dr-sg-eks`**.
   - Chuyển sang tab **Compute**:
     - Chọn node group **`dr-sg-ng`** -> bấm **Delete** -> gõ `dr-sg-ng` -> bấm **Delete**.
     - Chờ node group biến mất hoàn toàn.
   - Nhấp nút **Delete cluster** -> gõ `dr-sg-eks` -> bấm **Delete**.

---

### Bước 5: Xóa Amazon Aurora Global Database

1. Mở **Amazon RDS Console** tại [https://console.aws.amazon.com/rds/](https://console.aws.amazon.com/rds/).
2. Chọn mục **Databases** tại menu bên trái:
3. **Gỡ Deletion Protection (nếu đang bật):**
   - Với từng regional cluster (`dr-tokyo-aurora-cluster` và `dr-sg-aurora-cluster`): Chọn cluster -> bấm **Modify** -> cuộn xuống mục **Deletion protection** -> bỏ tích ô **Enable deletion protection** -> bấm **Continue** -> chọn **Apply immediately** -> bấm **Modify cluster**.
4. **Xóa Secondary Cluster Tokyo:**
   - Mở rộng nhóm `dr-global-db`.
   - Chọn DB instance bên trong cluster Tokyo (ví dụ: `dr-tokyo-aurora-instance-1`) -> chọn menu **Actions** -> chọn **Delete** -> gõ `delete me` -> bấm **Delete**.
   - Sau khi instance bị xóa, chọn regional cluster **`dr-tokyo-aurora-cluster`** -> chọn **Actions** -> chọn **Delete** (hoặc **Remove from global database** trước nếu yêu cầu) -> xác nhận xóa.
5. **Xóa Primary Cluster Singapore:**
   - Chọn DB instance bên trong cluster Singapore -> chọn **Actions** -> chọn **Delete** -> gõ `delete me` -> bấm **Delete**.
   - Chọn regional cluster **`dr-sg-aurora-cluster`** -> chọn **Actions** -> chọn **Delete** -> bỏ tích ô "Create final snapshot" -> tích ô xác nhận rủi ro mất dữ liệu -> gõ `delete me` -> bấm **Delete**.
6. **Xóa Global Cluster:**
   - Sau khi cả hai cluster vùng đã bị xóa, chọn mục gốc **`dr-global-db`** -> chọn **Actions** -> chọn **Delete** -> bấm **Delete**.
7. **Xóa DB Subnet Groups:**
   - Tại menu trái RDS, chọn **Subnet groups**:
   - Tại Singapore: Chọn **`dr-sg-db-subnet-group`** -> bấm **Delete** -> xác nhận.
   - Tại Tokyo: Đổi region sang Tokyo -> Chọn **`dr-tokyo-db-subnet-group`** -> bấm **Delete** -> xác nhận.

---

### Bước 6: Xóa AWS Secrets Manager và ECR Repositories

1. **Xóa Secret `/app2/database` trên Secrets Manager Console:**
   - Chọn Region **Singapore (`ap-southeast-1`)** -> Mở **AWS Secrets Manager Console**.
   - Nhấp vào secret **`/app2/database`**.
   - Cuộn xuống tab **Replication**:
     - Chọn replica tại Region Tokyo (`ap-northeast-1`) -> nhấp menu **Actions** trong bảng replica -> chọn **Delete secret replica** -> bấm **Delete**.
   - Sau khi gỡ replica, nhấp menu **Actions** ở trên cùng trang -> chọn **Delete secret**.
   - Chọn thời gian lưu giữ (ví dụ: 7 ngày) hoặc tích chọn **Schedule deletion** -> bấm **Schedule deletion**.

2. **Xóa ECR Repositories:**
   - Mở **Amazon ECR Console** tại [https://console.aws.amazon.com/ecr/](https://console.aws.amazon.com/ecr/).
   - Tại cả 2 Region (Singapore và Tokyo):
     - Vào **Private registry** -> **Repositories**.
     - Chọn tất cả các repository đã tạo: `dr-platform-file-service`, `app2-*`.
     - Nhấp nút **Delete** -> gõ `delete` vào hộp thoại -> bấm **Delete**.
     - Vào mục **Registry settings** -> tab **Replication** -> chọn rule đồng bộ sang Tokyo -> bấm **Delete**.

---

### Bước 7: Xóa Tầng Mạng Cơ sở (VPC Peering, NAT Gateways, EIPs, VPCs)

1. **Xóa VPC Peering Connection:**
   - Mở **Amazon VPC Console** tại Region **Singapore (`ap-southeast-1`)**.
   - Tại menu trái, chọn **Peering connections**.
   - Tích chọn kết nối **`dr-peer-sg-tokyo`** -> nhấp menu **Actions** -> chọn **Delete peering connection**.
   - Tích chọn ô xóa các route liên quan trong route tables -> gõ `delete` -> bấm **Delete**.

2. **Xóa NAT Gateway & Release Elastic IP tại Tokyo (`ap-northeast-1`):**
   - Đổi sang Region Tokyo trên Navigation bar.
   - Tại VPC Console, chọn **NAT gateways**:
     - Tích chọn **`dr-tokyo-nat`** -> nhấp **Actions** -> chọn **Delete NAT gateway** -> gõ `delete` -> bấm **Delete**.
     - Đợi trạng thái chuyển từ `Deleting` sang **`Deleted`**.
   - Chọn **Elastic IPs** tại menu trái:
     - Chọn EIP vừa giải phóng khỏi NAT Gateway -> nhấp menu **Actions** -> chọn **Release Elastic IP addresses** -> bấm **Release**.

3. **Xóa NAT Gateway & Release Elastic IP tại Singapore (`ap-southeast-1`):**
   - Đổi sang Region Singapore trên Navigation bar.
   - Chọn **NAT gateways** -> chọn **`dr-sg-nat`** -> **Actions** -> **Delete NAT gateway**.
   - Chờ trạng thái `Deleted` -> chọn **Elastic IPs** -> chọn EIP -> **Actions** -> **Release Elastic IP addresses**.

4. **Xóa Virtual Private Clouds (VPCs):**
   - Tại Region **Tokyo (`ap-northeast-1`)**:
     - Trong VPC Console, chọn **Your VPCs**.
     - Tích chọn **`dr-tokyo-vpc`** -> nhấp menu **Actions** -> chọn **Delete VPC**.
     - Hộp thoại sẽ liệt kê các tài nguyên con sẽ được tự động xóa kèm (Subnets, Internet Gateway, Security Groups con, Route Tables).
     - Gõ `delete` -> bấm **Delete**.
   - Tại Region **Singapore (`ap-southeast-1`)**:
     - Trong VPC Console, chọn **Your VPCs**.
     - Tích chọn **`dr-sg-vpc`** -> nhấp menu **Actions** -> chọn **Delete VPC**.
     - Gõ `delete` -> bấm **Delete**.

---

### Bước 8: Dọn dẹp CloudWatch Alarms, SNS Topic và IAM Roles

1. **Xóa CloudWatch Alarms & Dashboards:**
   - Mở **CloudWatch Console** tại cả Singapore và Tokyo:
   - Vào **Alarms** -> chọn tất cả các alarms đã tạo cho lab -> chọn **Actions** -> **Delete**.
   - Vào **Dashboards** -> chọn `dr-platform-dashboard` -> chọn **Delete**.
2. **Xóa Amazon SNS Topic:**
   - Mở **Amazon SNS Console** tại Singapore:
   - Vào **Topics** -> chọn **`dr-alert-topic`** -> bấm **Delete**.
3. **Xóa IAM Roles:**
   - Mở **IAM Console** -> mục **Roles**.
   - Tìm và xóa các role phục vụ riêng cho lab (nếu không dùng lại):
     - `dr-eks-cluster-role`
     - `dr-eks-nodegroup-role`
     - `dr-alb-controller-role-sg`, `dr-alb-controller-role-tokyo`
     - `dr-storage-ec2-role`
     - `dr-secrets-eso-role-sg`, `dr-secrets-eso-role-tokyo`

## 7. Xác minh

Chạy kiểm kê chỉ đọc:

```bash
aws eks list-clusters --region ap-southeast-1
aws eks list-clusters --region ap-northeast-1
aws ec2 describe-nat-gateways --region ap-southeast-1 --filter Name=state,Values=pending,available,deleting
aws ec2 describe-nat-gateways --region ap-northeast-1 --filter Name=state,Values=pending,available,deleting
aws ec2 describe-addresses --region ap-southeast-1
aws ec2 describe-addresses --region ap-northeast-1
aws rds describe-db-clusters --region ap-southeast-1
aws rds describe-db-clusters --region ap-northeast-1
aws globalaccelerator list-accelerators --region us-west-2
```

Đồng thời kiểm tra Cost Explorer sau khi dữ liệu billing cập nhật; việc xóa không loại bỏ chi phí đã phát sinh.

## 8. Kết quả mong đợi

- Không còn FSx, storage EC2/ALB/accelerator, EKS, EC2 node, NAT Gateway, Aurora cluster, GA hoặc EIP không gắn tài nguyên của lab.
- Snapshot/log/bằng chứng được giữ lại đã được ghi nhận.
- Tài nguyên IAM/OIDC chỉ bị gỡ khi không còn sử dụng.

## 9. Xử lý sự cố

- VPC dependency violation: kiểm tra ENI, load balancer, target group, NAT Gateway, endpoint và tài nguyên RDS.
- Security group đang được dùng: kiểm tra network interface gắn kèm trước khi xóa.
- Xóa cluster bị treo: xác minh managed node group/Fargate profile và load balancer đã biến mất.
- Xóa secret bị chặn: gỡ replica khỏi primary trước.
- ECR repository không rỗng: quyết định thời gian lưu giữ; không buộc xóa khi chưa được phê duyệt.

## 10. Lưu ý bảo mật

- Quyền phá hủy phải tạm thời và được audit.
- Giữ CloudTrail và bằng chứng sự cố bắt buộc.
- Gỡ trust relationship và repository credential cũ sau khi hệ thống phụ thuộc đã biến mất.
- Xác minh access policy của snapshot và secret sau teardown.

## 11. Lưu ý chi phí

Tài nguyên ưu tiên cao nhất cần dừng tính phí: FSx ONTAP, Aurora, EKS control plane/node, EC2, NAT Gateway, ALB, Global Accelerator và public IPv4. Log, backup/snapshot, ECR storage, KMS key và Secrets Manager có thể tiếp tục tính phí.

## 12. Dọn dẹp / Quay lui

Thao tác xóa thường không thể đảo ngược. Khả năng phục hồi phụ thuộc snapshot, ECR image, Git và bằng chứng được giữ lại. Nếu chưa chắc chắn về bất kỳ target nào, dừng trước khi xóa và xác minh quyền sở hữu.

## 13. Bằng chứng cần thu thập

- Ticket/bản ghi thay đổi phá hủy đã được phê duyệt.
- Inventory trước khi xóa.
- ID final snapshot và người chịu trách nhiệm retention.
- Inventory CLI sau khi xóa.
- Ngày kiểm tra lại Cost Explorer.
- Tài nguyên tính phí được chủ động giữ lại.

## 14. Lab tiếp theo

Không có lab tiếp theo. Chỉ đánh dấu hoàn tất sau khi inventory và Cost Explorer không còn tài nguyên ngoài ý muốn; không suy ra RTO/RPO từ việc hoàn thành tài liệu.
