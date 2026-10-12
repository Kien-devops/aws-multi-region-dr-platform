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

### 6.1 Tạo IAM role cho cluster

```text
IAM -> Roles -> Create role
Trusted entity: AWS service
Use case: EKS - Cluster
Policy: AmazonEKSClusterPolicy
Name: dr-sg-eks-cluster-role
-> Create role
```

### 6.2 Tạo IAM role cho node

```text
IAM -> Roles -> Create role
Trusted entity: AWS service -> EC2
Policies:
- AmazonEKSWorkerNodePolicy
- AmazonEC2ContainerRegistryPullOnly
- AmazonEKS_CNI_Policy
Name: dr-sg-eks-node-role
```

**ĐƠN GIẢN HÓA CHO LAB:** Quyền CNI tạm thời nằm trên node role. Với production, chuyển `AmazonEKS_CNI_Policy` sang role VPC CNI riêng bằng EKS Pod Identity hoặc IRSA, sau đó gỡ policy khỏi node role.

### 6.3 Tạo cluster

```text
EKS Singapore -> Clusters -> Create cluster
Name: dr-sg-eks
Kubernetes version: <EKS_VERSION>
Cluster service role: dr-sg-eks-cluster-role
Cluster access: API_AND_CONFIG_MAP
Bootstrap cluster creator admin permissions: enabled for lab operator
VPC: dr-sg-vpc
Subnets: dr-sg-private-a, dr-sg-private-b
Security groups: create/use dedicated cluster SG; no broad inbound rule
Endpoint access: Public and private
Public access CIDRs: <ADMIN_CIDR>
Control-plane logs: API, audit, authenticator enabled; controller/scheduler optional
Add-ons: VPC CNI, CoreDNS, kube-proxy, EKS Pod Identity Agent
-> Create; wait for Active
```

Với production, ưu tiên endpoint chỉ private cùng đường quản trị qua VPN/bastion/SSM.

### 6.4 Tạo Managed Node Group

```text
EKS -> dr-sg-eks -> Compute -> Add node group
Name: dr-sg-ng
Node IAM role: dr-sg-eks-node-role
AMI: Amazon Linux 2023 x86_64 if compatible with selected version
Capacity: On-Demand
Instance type: t3.medium for lab; right-size before production
Disk: 30 GiB gp3
Minimum: 2
Desired: 2
Maximum: 4
Subnets: dr-sg-private-a, dr-sg-private-b
Remote SSH access: disabled
-> Create; wait for Active
```

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
