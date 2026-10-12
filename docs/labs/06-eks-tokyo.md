# LAB 06 - EKS Tokyo

## 1. Mục tiêu

Tạo EKS cluster warm standby tại Tokyo với cùng phiên bản Kubernetes, tư thế bảo mật như Singapore và context `tokyo` rõ ràng.

## 2. Thành phần sẽ xây dựng

- Cluster `dr-tokyo-eks`.
- Managed Node Group private `dr-tokyo-ng`.
- IAM role cho cluster/node.
- Chế độ dung lượng tiết kiệm chi phí và kiểm thử DR.

## 3. Bối cảnh kiến trúc

Tokyo phải hoạt động trước khi failover. Chế độ lab một node tiết kiệm chi phí nhưng không chịu lỗi AZ; dùng hai node để kiểm thử controller/ALB/DR.

## 4. Điều kiện tiên quyết

- Hoàn thành LAB 03 và LAB 05.
- Dùng chính xác `<EKS_VERSION>` đã chọn ở LAB 05.
- Đã ghi lại private subnet ID tại Tokyo và `<ADMIN_CIDR>`.

## 5. Quy ước đặt tên tài nguyên

| Tài nguyên | Giá trị |
|---|---|
| Cluster | `dr-tokyo-eks` |
| Cluster role | `dr-tokyo-eks-cluster-role` |
| Node role | `dr-tokyo-eks-node-role` |
| Node group | `dr-tokyo-ng` |
| Context | `tokyo` |

## 6. Các bước triển khai

### 6.1 Tạo IAM Role cho Cluster và Nodes tại Tokyo

Mặc dù IAM Role là tài nguyên mang tính toàn cầu (Global), việc đặt tên tách biệt giúp quản trị an toàn và tránh xung đột blast radius giữa 2 Region:

1. Mở AWS Console, truy cập dịch vụ **IAM** -> chọn mục **Roles** -> nhấp **Create role**.
2. *Tạo Cluster Role:*
   - **Trusted entity type**: Chọn **AWS service**.
   - **Use case**: Chọn **EKS** -> **EKS - Cluster** -> nhấp **Next**.
   - **Permissions**: Đảm bảo có `AmazonEKSClusterPolicy` -> nhấp **Next**.
   - **Role name**: Nhập `dr-tokyo-eks-cluster-role` -> nhấp **Create role**.
3. *Tạo Node Role:*
   - Quay lại trang Roles -> nhấp **Create role**.
   - **Trusted entity type**: Chọn **AWS service** -> **EC2** -> nhấp **Next**.
   - **Permissions**: Tích chọn 3 policy:
     1. `AmazonEKSWorkerNodePolicy`
     2. `AmazonEC2ContainerRegistryPullOnly`
     3. `AmazonEKS_CNI_Policy`
   - Nhấp **Next**.
   - **Role name**: Nhập `dr-tokyo-eks-node-role` -> nhấp **Create role**.

> [!IMPORTANT]
> **NGUYÊN TẮC BẢO MẬT BẮT BUỘC (Node Profile vs Pod IRSA):**
> - **Chỉ cấp 3 Policy nền tảng trên cho Node Role.** Tuyệt đối KHÔNG đính kèm các quyền quản lý Ingress/ALB, S3 hay Secrets Manager vào Role này để tránh nguy cơ chiếm quyền qua IMDS.
> - Toàn bộ các quyền AWS của Pod nghiệp vụ (Controller, Application) bắt buộc phải cấu hình riêng rẽ qua cơ chế **IRSA (IAM Roles for Service Accounts)** ở [LAB 07](07-aws-load-balancer-controller.md) và [LAB 09](09-secrets-manager.md).

### 6.2 Tạo EKS Cluster tại Tokyo

1. Tại góc trên bên phải của AWS Console, chuyển Region sang **Asia Pacific (Tokyo) `ap-northeast-1`**.
2. Trên thanh tìm kiếm, gõ `EKS` và chọn **Elastic Kubernetes Service**.
3. Trong menu bên trái, chọn **Clusters** -> nhấp nút **Add cluster** -> chọn **Create**.
4. **Bước 1: Configure cluster**:
   - **Name**: Nhập `dr-tokyo-eks`.
   - **Kubernetes version**: Phải chọn **hoàn toàn trùng khớp** với phiên bản đã chọn tại Singapore (`<EKS_VERSION>`).
   - **Cluster service role**: Chọn `dr-tokyo-eks-cluster-role`.
   - **Cluster access**:
     - Chọn **API and ConfigMap**.
     - Tích chọn **Bootstrap cluster creator admin permissions**.
   - Nhấp nút **Next**.
5. **Bước 2: Specify networking**:
   - **VPC**: Chọn `dr-tokyo-vpc`.
   - **Subnets**: Chỉ tích chọn 2 private subnets: `dr-tokyo-private-a` và `dr-tokyo-private-b`.
   - **Security groups**: Giữ mặc định.
   - **Cluster endpoint access**:
     - Chọn **Public and private**.
     - Tại **Public access sources**: Nhập địa chỉ `<ADMIN_CIDR>` của bạn.
   - Nhấp nút **Next**.
6. **Bước 3: Configure observability**:
   - Bật các loại control plane logs: **API server**, **Audit**, **Authenticator**.
   - Nhấp nút **Next**.
7. **Bước 4: Select add-ons**:
   - Giữ các add-ons mặc định: **Amazon VPC CNI**, **CoreDNS**, **kube-proxy**, **Amazon EKS Pod Identity Agent**.
   - Nhấp **Next** qua trang cấu hình chi tiết add-on.
8. **Bước 5: Review and create**:
   - Nhấp nút **Create** màu cam. Đợi từ 8-12 phút cho đến khi cluster đạt trạng thái **Active**.

### 6.3 Tạo Managed Node Group tại Tokyo

1. Khi cluster `dr-tokyo-eks` đã **Active**, nhấp vào tên cluster để mở trang tổng quan.
2. Chuyển sang tab **Compute** -> tại mục **Node groups**, nhấp nút **Add node group** màu cam.
3. **Bước 1: Configure node group**:
   - **Name**: Nhập `dr-tokyo-ng`.
   - **Node IAM role**: Chọn `dr-tokyo-eks-node-role`.
   - Nhấp nút **Next**.
4. **Bước 2: Set compute and scaling configuration**:
   - **AMI type**: Chọn cùng loại với Singapore (ví dụ: `Amazon Linux 2023`).
   - **Capacity type**: Chọn **On-Demand** (đảm bảo tính ổn định và dự đoán được khi diễn tập DR, tránh dùng Spot).
   - **Instance types**: Chọn `t3.medium`.
   - **Disk size**: Nhập `30` GiB gp3.
   - **Node group scaling configuration**:
     - *Chế độ tiết kiệm ban đầu:* Min: `1`, Desired: `1`, Max: `4`.
     - *Chế độ kiểm thử DR hạ tầng (Khuyến nghị):* Min: `2`, Desired: `2`, Max: `4` (đảm bảo mỗi node phân bố trên 1 AZ).
   - Nhấp nút **Next**.
5. **Bước 3: Specify networking**:
   - **Subnets**: Đảm bảo chỉ chọn `dr-tokyo-private-a` và `dr-tokyo-private-b`.
   - **Configure SSH access to nodes**: Chọn **Off**.
   - Nhấp nút **Next**.
6. **Bước 4: Review and create**:
   - Nhấp nút **Create** màu cam. Đợi 3-5 phút cho các node EC2 chuyển sang trạng thái **Active**.

Các lựa chọn dung lượng:

| Chế độ | Tối thiểu | Mong muốn | Tối đa | Ý nghĩa |
|---|---:|---:|---:|---|
| Lab tiết kiệm | 1 | 1 | 4 | Không HA; có thể thiếu tài nguyên cho add-on |
| Kiểm thử DR hạ tầng | 2 | 2 | 4 | Bắt buộc trước LAB 07/11-17 |

Dùng On-Demand để bài diễn tập DR có tính dự đoán. Spot có thể bị thu hồi đúng lúc đang kiểm thử sự cố.

Cấu hình context:

```bash
aws eks update-kubeconfig --region ap-northeast-1 --name dr-tokyo-eks --alias tokyo
kubectl config get-contexts
kubectl --context singapore get nodes
kubectl --context tokyo get nodes
kubectl --context tokyo get pods -A
```

Trước LAB 07, đặt desired capacity thành hai:

```bash
aws eks update-nodegroup-config --region ap-northeast-1 \
  --cluster-name dr-tokyo-eks --nodegroup-name dr-tokyo-ng \
  --scaling-config minSize=2,desiredSize=2,maxSize=4
```

## 7. Xác minh

```bash
aws eks describe-cluster --region ap-northeast-1 --name dr-tokyo-eks \
  --query 'cluster.{Status:status,Version:version,EndpointAccess:resourcesVpcConfig,Access:accessConfig}'
aws eks describe-nodegroup --region ap-northeast-1 --cluster-name dr-tokyo-eks --nodegroup-name dr-tokyo-ng
kubectl --context tokyo get nodes -L topology.kubernetes.io/zone
```

## 8. Kết quả mong đợi

Cả hai context hoạt động, phiên bản khớp nhau, node Tokyo private/Ready và chế độ kiểm thử hai node đã bật trước khi kiểm tra controller/ALB.

## 9. Xử lý sự cố

Dùng các bước kiểm tra của LAB 05. Nếu instance type không khả dụng tại một AZ, chọn loại phổ biến hơn và ghi lại khác biệt; không âm thầm đặt toàn bộ node vào một AZ.

## 10. Lưu ý bảo mật

Áp dụng cùng kiểm soát như Singapore. IAM role là tài nguyên cấp tài khoản, không phụ thuộc Region, nhưng tên được tách riêng để giảm lỗi trust policy và blast radius.

## 11. Lưu ý chi phí

EKS control plane Tokyo vẫn tính phí khi không có node. Một node giảm chi phí nhưng không đủ cơ sở tuyên bố HA. Dùng hai node để đo khả năng sẵn sàng DR.

## 12. Dọn dẹp / Quay lui

Chỉ scale xuống một node khi không thực hiện kiểm thử hạ tầng. Khi teardown, xóa node group trước cluster.

## 13. Bằng chứng cần thu thập

Phiên bản khớp nhau, cấu hình endpoint/access, chế độ node group, node Ready/AZ và hai kubeconfig context.

## 14. Lab tiếp theo

Tiếp tục với [LAB 07 - AWS Load Balancer Controller](07-aws-load-balancer-controller.md).
