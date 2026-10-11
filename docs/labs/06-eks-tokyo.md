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

### 6.1 Tạo IAM role

```text
IAM -> Roles -> Create role -> AWS service -> EKS - Cluster
Policy: AmazonEKSClusterPolicy
Name: dr-tokyo-eks-cluster-role

IAM -> Roles -> Create role -> AWS service -> EC2
Policies: AmazonEKSWorkerNodePolicy, AmazonEC2ContainerRegistryPullOnly, AmazonEKS_CNI_Policy
Name: dr-tokyo-eks-node-role
```

Áp dụng cùng nguyên tắc **ĐƠN GIẢN HÓA CHO LAB**: chuyển quyền CNI sang role Pod Identity/IRSA riêng trước production.

### 6.2 Tạo cluster

```text
EKS Tokyo -> Clusters -> Create cluster
Name: dr-tokyo-eks
Version: <EKS_VERSION> (must match Singapore)
Role: dr-tokyo-eks-cluster-role
Access: API_AND_CONFIG_MAP; bootstrap creator admin enabled for lab
VPC: dr-tokyo-vpc
Subnets: dr-tokyo-private-a, dr-tokyo-private-b
Endpoint: Public and private
Public CIDR: <ADMIN_CIDR>
Logs/add-ons: match Singapore
-> Create; wait for Active
```

### 6.3 Tạo Managed Node Group

```text
EKS -> dr-tokyo-eks -> Compute -> Add node group
Name: dr-tokyo-ng
Node role: dr-tokyo-eks-node-role
AMI: Amazon Linux 2023 if compatible
Capacity: On-Demand
Instance: t3.medium for lab
Disk: 30 GiB gp3
Subnets: dr-tokyo-private-a, dr-tokyo-private-b
SSH: disabled
```

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
