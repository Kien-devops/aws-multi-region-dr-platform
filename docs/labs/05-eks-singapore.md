# LAB 05 - EKS Singapore

## 1. Mục tiêu

Tạo EKS cluster Singapore và Managed Node Group private bằng phiên bản Kubernetes còn được hỗ trợ, kiểm soát quyền truy cập API và đặt kubeconfig context rõ ràng.

## 2. Thành phần sẽ xây dựng

- Cluster `dr-sg-eks`.
- Node group `dr-sg-ng` trên hai private subnet.
- IAM role cho cluster và node.
- Cấu hình quyền truy cập EKS và các add-on lõi.
- Context `singapore`.

## 3. Bối cảnh kiến trúc

```text
EKS control plane do AWS quản lý
        | đường VPC endpoint private
node private-a ---- node private-b
        | outbound qua NAT tới các dịch vụ public bắt buộc
```

AWS quản lý EKS control plane trên nhiều AZ. Worker node luôn nằm trong private subnet.

## 4. Điều kiện tiên quyết

- Hoàn thành LAB 02; LAB 04 tùy chọn không chặn việc tạo cluster.
- Đã ghi lại hai private subnet ID và VPC ID.
- `<ADMIN_CIDR>` là public CIDR ổn định của người vận hành, không phải `0.0.0.0/0`.
- Chọn một phiên bản Kubernetes có trạng thái `STANDARD_SUPPORT` ở cả hai Region:

```bash
aws eks describe-cluster-versions --region ap-southeast-1 \
  --query "clusterVersions[?status=='STANDARD_SUPPORT'].[clusterVersion,defaultVersion,endOfStandardSupportDate]" --output table
```

Ghi lại thành `<EKS_VERSION>` và dùng cùng giá trị tại Tokyo.

## 5. Quy ước đặt tên tài nguyên

| Tài nguyên | Giá trị |
|---|---|
| Cluster | `dr-sg-eks` |
| Cluster role | `dr-sg-eks-cluster-role` |
| Node role | `dr-sg-eks-node-role` |
| Node group | `dr-sg-ng` |
| Context | `singapore` |

## 6. Các bước triển khai

### 6.1 Tạo IAM Role cho EKS Cluster

1. Mở AWS Management Console, trên thanh tìm kiếm gõ `IAM` và chọn dịch vụ **IAM**.
2. Trong menu bên trái, nhấp chọn **Roles** -> nhấp nút **Create role** màu cam.
3. Tại bước 1 - **Select trusted entity**:
   - **Trusted entity type**: Chọn **AWS service**.
   - **Use case**: Trong danh sách dịch vụ hoặc thanh tìm kiếm, chọn **EKS** -> chọn use case radio button là **EKS - Cluster**.
   - Nhấp nút **Next** ở cuối trang.
4. Tại bước 2 - **Add permissions**:
   - Hệ thống tự động đính kèm policy `AmazonEKSClusterPolicy`.
   - Nhấp nút **Next**.
5. Tại bước 3 - **Name, review, and create**:
   - **Role name**: Nhập `dr-sg-eks-cluster-role`.
   - **Description**: Nhập `IAM role for EKS control plane dr-sg-eks`.
   - Nhấp nút **Create role** màu cam.

### 6.2 Tạo IAM Role cho EKS Worker Nodes

1. Trong menu bên trái của IAM Console, nhấp chọn **Roles** -> nhấp nút **Create role** màu cam.
2. Tại bước 1 - **Select trusted entity**:
   - **Trusted entity type**: Chọn **AWS service**.
   - **Use case**: Chọn **EC2** -> nhấp **Next**.
3. Tại bước 2 - **Add permissions**:
   - Tìm kiếm và tích chọn 3 policy sau:
     1. `AmazonEKSWorkerNodePolicy`
     2. `AmazonEC2ContainerRegistryPullOnly`
     3. `AmazonEKS_CNI_Policy`
   - Nhấp nút **Next**.
4. Tại bước 3 - **Name, review, and create**:
   - **Role name**: Nhập `dr-sg-eks-node-role`.
   - **Description**: Nhập `IAM role for EKS managed node group dr-sg-ng`.
   - Nhấp nút **Create role** màu cam.

> [!IMPORTANT]
> **NGUYÊN TẮC BẢO MẬT BẮT BUỘC (Node Profile vs Pod IRSA):**
> - **Chỉ cấp 3 Policy nền tảng trên cho Node Role.** Tuyệt đối KHÔNG đính kèm các quyền quản lý Ingress/ALB, S3 hay Secrets Manager vào Role này.
> - Nếu cấp thừa quyền vào Node Role, **bất kỳ Pod nào** chạy trên máy ảo này đều có thể lợi dụng IMDS để chiếm đoạt quyền hạn đó.
> - Mọi quyền quản trị AWS nâng cao của Pod nghiệp vụ (như AWS Load Balancer Controller ở [LAB 07](07-aws-load-balancer-controller.md) hoặc External Secrets Operator ở [LAB 09](09-secrets-manager.md)) bắt buộc phải được cấp riêng rẽ qua cơ chế **IRSA (IAM Roles for Service Accounts)**.

> [!NOTE]
> **ĐƠN GIẢN HÓA CHO LAB:** Quyền CNI tạm thời nằm trực tiếp trên node role. Với môi trường Production, nên chuyển `AmazonEKS_CNI_Policy` sang một IAM Role riêng sử dụng EKS Pod Identity hoặc IRSA cho ServiceAccount `aws-node`, sau đó gỡ bỏ policy này khỏi node role.

### 6.3 Tạo EKS Cluster tại Singapore

1. Chuyển Region sang **Asia Pacific (Singapore) `ap-southeast-1`**.
2. Trên thanh tìm kiếm, gõ `EKS` và chọn **Elastic Kubernetes Service**.
3. Trong menu bên trái, nhấp chọn **Clusters** -> nhấp nút **Add cluster** -> chọn **Create**.
4. **Bước 1: Configure cluster**:
   - **Name**: Nhập `dr-sg-eks`.
   - **Kubernetes version**: Chọn phiên bản đã xác định ở điều kiện tiên quyết (ví dụ: `1.30` hoặc `1.31`).
   - **Cluster service role**: Chọn role `dr-sg-eks-cluster-role` đã tạo ở bước 6.1.
   - Tại mục **Cluster access**:
     - **Authentication mode**: Chọn **API and ConfigMap** (hoặc **EKS API**).
     - Tích chọn **Bootstrap cluster creator admin permissions** để gán quyền quản trị cluster cao nhất cho tài khoản hiện tại của bạn.
   - Nhấp nút **Next**.
5. **Bước 2: Specify networking**:
   - **VPC**: Chọn `dr-sg-vpc`.
   - **Subnets**: Chỉ chọn 2 Private subnets: `dr-sg-private-a` và `dr-sg-private-b` (Xóa bỏ các public subnets nếu giao diện tự động chọn).
   - **Security groups**: Để AWS tự động tạo Cluster security group mặc định (hoặc chọn Security Group riêng biệt không mở cổng tùy tiện).
   - **Cluster endpoint access**:
     - Chọn **Public and private**.
     - Tại mục **Public access sources**: Chọn **Specific IP addresses / CIDR blocks** -> nhập IP WAN cá nhân của bạn dạng CIDR (ví dụ: `1.2.3.4/32` hoặc `<ADMIN_CIDR>`).
     - *Tuyệt đối không để `0.0.0.0/0`.*
   - Nhấp nút **Next**.
6. **Bước 3: Configure observability**:
   - Bật các loại control plane logs cần thiết: **API server**, **Audit**, **Authenticator**.
   - Nhấp nút **Next**.
7. **Bước 4: Select add-ons**:
   - Đảm bảo các add-ons mặc định được chọn: **Amazon VPC CNI**, **CoreDNS**, **kube-proxy**, và tích chọn thêm **Amazon EKS Pod Identity Agent** (nếu có).
   - Nhấp nút **Next** qua màn hình cấu hình chi tiết add-on.
8. **Bước 5: Review and create**:
   - Rà soát lại toàn bộ thông tin -> Nhấp nút **Create** màu cam.
   - Quá trình khởi tạo control plane sẽ mất từ **8 đến 12 phút**. Đợi đến khi trạng thái chuyển sang **Active**.

### 6.4 Tạo Managed Node Group (Worker Nodes)

1. Khi cluster `dr-sg-eks` đã đạt trạng thái **Active**, nhấp vào tên cluster để vào trang chi tiết.
2. Chuyển sang tab **Compute** -> tại mục **Node groups**, nhấp nút **Add node group** màu cam.
3. **Bước 1: Configure node group**:
   - **Name**: Nhập `dr-sg-ng`.
   - **Node IAM role**: Chọn `dr-sg-eks-node-role` đã tạo ở bước 6.2.
   - Nhấp nút **Next**.
4. **Bước 2: Set compute and scaling configuration**:
   - **AMI type**: Chọn **Amazon Linux 2023 (AL2023_x86_64_STANDARD)** hoặc **Amazon Linux 2 (AL2_x86_64)**.
   - **Capacity type**: Chọn **On-Demand**.
   - **Instance types**: Chọn `t3.medium` (hoặc `t3a.medium`).
   - **Disk size**: Nhập `30` GiB (loại gp3).
   - **Node group scaling configuration**:
     - **Minimum size**: `2`
     - **Desired size**: `2`
     - **Maximum size**: `4`
   - Nhấp nút **Next**.
5. **Bước 3: Specify networking**:
   - **Subnets**: Đảm bảo chỉ chọn 2 private subnets: `dr-sg-private-a` và `dr-sg-private-b`.
   - **Configure SSH access to nodes**: Chọn **Off** (Tắt truy cập SSH trực tiếp để đảm bảo an ninh mạng; truy cập debug có thể dùng AWS Systems Manager Session Manager).
   - Nhấp nút **Next**.
6. **Bước 4: Review and create**:
   - Rà soát thông tin -> Nhấp nút **Create** màu cam.
   - Đợi khoảng 3 đến 5 phút để các node EC2 khởi động, gia nhập cluster và chuyển trạng thái sang **Active**.

### 6.5 Cấu hình kubeconfig và context

```bash
aws eks update-kubeconfig --region ap-southeast-1 --name dr-sg-eks --alias singapore
kubectl --context singapore get nodes -o wide
kubectl --context singapore get pods -A
```

## 7. Xác minh

```bash
aws eks describe-cluster --region ap-southeast-1 --name dr-sg-eks \
  --query 'cluster.{Status:status,Version:version,EndpointAccess:resourcesVpcConfig,Access:accessConfig,Logs:logging}'
aws eks describe-nodegroup --region ap-southeast-1 --cluster-name dr-sg-eks --nodegroup-name dr-sg-ng
kubectl --context singapore get nodes -L topology.kubernetes.io/zone
```

Node phải ở trạng thái Ready và sau khi có đủ pod, phải sử dụng được cả hai AZ. Số lượng node không tự chứng minh mỗi AZ có một node; cần kiểm tra placement.

## 8. Kết quả mong đợi

Cluster và node group ở trạng thái Active, có hai private node Ready, các add-on lõi khỏe mạnh và context `singapore` hoạt động.

## 9. Xử lý sự cố

- Node group `CREATE_FAILED`: kiểm tra NAT/DNS, policy của node role, IP trống trong subnet hoặc instance type/AZ không được hỗ trợ.
- `Unauthorized`: tạo EKS access entry và chỉ gắn `AmazonEKSClusterAdminPolicy` cho admin principal đã được phê duyệt.
- API timeout: `<ADMIN_CIDR>` đã thay đổi hoặc đường endpoint/security sai.
- CoreDNS pending: thiếu node/tài nguyên hoặc CNI lỗi.

## 10. Lưu ý bảo mật

- Node private, không SSH, public API CIDR bị giới hạn, truy cập IAM ngắn hạn.
- Chuyển quyền CNI khỏi node role.
- Dùng EKS access entry thay cho chỉnh sửa `aws-auth` không được quản lý đối với người dùng.
- Bật mã hóa secret/KMS và admission/security control trước khi đưa workload production vào cluster.

## 11. Lưu ý chi phí

EKS control plane, EC2 node, EBS, NAT/data, public IPv4 và log tính phí liên tục. Extended Kubernetes Support có phí cao hơn; duy trì phiên bản trong Standard Support.

## 12. Dọn dẹp / Quay lui

Xóa node group trước cluster. Chỉ gỡ OIDC/access/IAM sau khi controller và service account không còn. Teardown đầy đủ nằm ở LAB 27.

## 13. Bằng chứng cần thu thập

Phiên bản/ngày hết Standard Support, chế độ endpoint/access, private subnet đã chọn, cấu hình scaling node group, output node/AZ, system pod và control-plane logging.

## 14. Lab tiếp theo

Tiếp tục với [LAB 06 - EKS Tokyo](06-eks-tokyo.md).
