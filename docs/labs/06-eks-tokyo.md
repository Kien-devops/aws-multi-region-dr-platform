# LAB 06 - Khởi Tạo Cụm Kubernetes EKS Tokyo Standby (EKS Tokyo)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Tạo IAM Roles và khởi tạo cụm Kubernetes EKS `dr-tokyo-eks` tại vùng dự phòng Tokyo (`ap-northeast-1`) đặt trong VPC `dr-tokyo-vpc`.
2. Tạo Managed Node Group `dr-tokyo-workers` trong các **Private Subnets** của Tokyo.
3. Hiểu rõ sự khác biệt giữa **Cấu hình tiết kiệm chi phí cho Lab** (1 node) và **Cấu hình chuẩn bị diễn tập DR** (2 node multi-AZ).
4. Cấu hình context dòng lệnh `kubectl` để có thể quản lý đồng thời cả hai cụm Singapore và Tokyo từ một máy trạm.

---

## Architecture impact

```text
[ EKS Control Plane: dr-tokyo-eks (Tokyo Managed Multi-AZ) ]
                        |
            +-----------+-----------+
            | (Private VPC Connectivity)
            v                       v
  [ Private Subnet AZ-a ]   [ Private Subnet AZ-c ]
  ---------------------     ---------------------
  Node 1: dr-tokyo-workers  Node 2: (Khi DR test / HPA scale)
  (Warm Standby Pods)       (Tự động scale up khi failover)
            |                       |
            +-----------+-----------+
                        |
                        v
        Kéo container images từ ECR Tokyo cục bộ
```

---

## Resource naming

- Region: `ap-northeast-1` (Tokyo)
- EKS Cluster Name: `dr-tokyo-eks`
- EKS Cluster IAM Role: `dr-tokyo-eks-cluster-role`
- Node Group IAM Role: `dr-tokyo-eks-node-role`
- Managed Node Group Name: `dr-tokyo-workers`
- Kubernetes Version: `1.29`
- Instance Type: `t3.medium`

---

## AWS Console Steps

### Bước 1: Tạo IAM Roles cho Cluster và Node Group tại Tokyo
1. Mở AWS Management Console -> Dịch vụ **IAM**.
2. **Tạo Cluster Role:**
   - **Roles** -> **Create role** -> Chọn **AWS service** -> Use case: **EKS - Cluster**.
   - Kiểm tra policy: `AmazonEKSClusterPolicy`.
   - Role name: `dr-tokyo-eks-cluster-role`.
   - Nhấn **Create role**.
3. **Tạo Node Group Role:**
   - **Roles** -> **Create role** -> Chọn **AWS service** -> Use case: **EC2**.
   - Gắn 3 policies:
     - `AmazonEKSWorkerNodePolicy`
     - `AmazonEC2ContainerRegistryReadOnly`
     - `AmazonEKS_CNI_Policy`
   - Role name: `dr-tokyo-eks-node-role`.
   - Nhấn **Create role**.

### Bước 2: Khởi Tạo Cụm EKS `dr-tokyo-eks`
1. Đảm bảo góc trên bên phải đang chọn Region **Asia Pacific (Tokyo) ap-northeast-1**.
2. Tìm kiếm và chọn dịch vụ **Elastic Kubernetes Service (EKS)**.
3. Menu bên trái chọn **Clusters** -> Nhấn **Add cluster** -> Chọn **Create**.
4. **Trang 1: Configure cluster:**
   - **Name:** `dr-tokyo-eks`
   - **Kubernetes version:** `1.29` (Khớp phiên bản với Singapore).
   - **Cluster service role:** Chọn `dr-tokyo-eks-cluster-role`.
   - Nhấn **Next**.
5. **Trang 2: Specify networking:**
   - **VPC:** Chọn `dr-tokyo-vpc`.
   - **Subnets:** Chỉ chọn 2 Private Subnets (`dr-tokyo-priv-sub-a` và `dr-tokyo-priv-sub-c`).
   - **Cluster endpoint access:** Chọn **Public and private**.
   - Nhấn **Next**.
6. **Trang 3 & 4: Observability & Add-ons:**
   - Giữ các add-on cốt lõi mặc định -> Nhấn **Next** cho đến màn hình Review.
7. **Trang 5: Review and create:**
   - Nhấn **Create**.
   - Chờ cụm chuyển trạng thái sang **Active** (khoảng 8-10 phút).

### Bước 3: Tạo Managed Node Group `dr-tokyo-workers`
1. Khi cluster đã `Active`, chuyển sang tab **Compute** -> Nhấn **Add node group**.
2. **Trang 1: Configure node group:**
   - **Name:** `dr-tokyo-workers`
   - **Node IAM Role:** Chọn `dr-tokyo-eks-node-role`.
   - Nhấn **Next**.
3. **Trang 2: Set compute and scaling configuration:**
   - **AMI type:** Amazon Linux 2 (AL2_x86_64) hoặc AL2023.
   - **Capacity type:** On-Demand.
   - **Instance types:** Chọn `t3.medium`.
   - **Disk size:** 20 GiB.
   - **Scaling configuration (Cấu hình linh hoạt):**
     > **Lựa chọn cho Lab tiết kiệm chi phí:**
     > - **Minimum size:** `1`
     > - **Desired size:** `1`
     > - **Maximum size:** `6`
     >
     > *(Lưu ý: Trước khi bước vào Lab 14-17 diễn tập DR benchmark, bạn chỉ cần chỉnh Desired size lên `2` để đảm bảo tính sẵn sàng đa AZ).*
   - Nhấn **Next**.
4. **Trang 3: Specify networking:**
   - **Subnets:** Chỉ chọn 2 Private Subnets (`dr-tokyo-priv-sub-a` và `dr-tokyo-priv-sub-c`).
   - Tắt cấu hình SSH -> Nhấn **Next**.
5. **Trang 4: Review and create:**
   - Nhấn **Create**.
   - Đợi node group chuyển sang `Active`.

---

## Configuration

| Chế độ triển khai | Min Nodes | Desired Nodes | Max Nodes | Mục đích sử dụng |
|---|---|---|---|---|
| **Lab Cost-Saving Mode** | `1` | `1` | `6` | Tiết kiệm tiền khi phát triển, cấu hình GitOps |
| **DR Benchmark Mode** | `2` | `2` | `6` | Multi-AZ High Availability sẵn sàng nhận tải tức thì khi Singapore sập |

---

## Security considerations

- **Phân tách vùng an toàn:** Cluster Tokyo có cụm IAM Role độc lập với Singapore, tuân thủ nguyên tắc cách ly sự cố vùng (Failure Domain Isolation).
- **Worker Node không có Public IP:** Nằm hoàn toàn trong private subnets của Tokyo, giao tiếp ra ngoài qua Tokyo NAT Gateway.

---

## Expected result

- Cụm EKS `dr-tokyo-eks` hiển thị **Active** trên Console Tokyo.
- Node Group `dr-tokyo-workers` hiển thị **Active**.
- Có 1 node (hoặc 2 nodes nếu chạy DR mode) hiển thị trạng thái **Ready**.

---

## Verification

### Kiểm tra bằng Console
1. EKS Console tại Tokyo -> `dr-tokyo-eks` -> Tab *Compute*: Node group hiển thị xanh `Active`.

### Cấu hình Kubeconfig và kiểm tra song song hai cụm
```bash
# 1. Thêm cụm Tokyo vào kubeconfig
aws eks update-kubeconfig --region ap-northeast-1 --name dr-tokyo-eks --alias tokyo

# 2. Thêm lại cụm Singapore để đặt alias thuận tiện
aws eks update-kubeconfig --region ap-southeast-1 --name dr-sg-eks --alias singapore

# 3. Kiểm tra cụm Tokyo
kubectl --context tokyo get nodes -o wide
```
*Expected output:*
```text
NAME                                                STATUS   ROLES    AGE   VERSION               INTERNAL-IP
ip-10-20-10-31.ap-northeast-1.compute.internal     Ready    <none>   4m    v1.29.3-eks-ae9a62a   10.20.10.31
```

Kiểm tra danh sách contexts:
```bash
kubectl config get-contexts
```
*Expected output:* Xuất hiện cả hai context `singapore` và `tokyo`.

---

## Troubleshooting

1. **Lỗi: `error: the server has asked for the client to provide credentials`:**
   - *Nguyên nhân:* Khi chuyển đổi giữa hai cụm, AWS CLI cần có quyền của IAM Principal tương ứng.
   - *Cách sửa:* Chạy lại lệnh `aws eks update-kubeconfig --region ap-northeast-1 --name dr-tokyo-eks`.
2. **Lỗi: Pod bị kẹt ở trạng thái `Pending` trong chế độ Lab Cost-Saving:**
   - *Nguyên nhân:* Khi chỉ chạy 1 node `t3.medium`, tài nguyên CPU/RAM có thể bị quá tải nếu chạy nhiều add-ons cùng lúc.
   - *Cách sửa:* Nâng `Desired size` của node group lên `2` bằng lệnh:
     ```bash
     aws eks update-nodegroup-config --region ap-northeast-1 --cluster-name dr-tokyo-eks --nodegroup-name dr-tokyo-workers --scaling-config minSize=1,maxSize=6,desiredSize=2
     ```
3. **Lỗi: Worker node không thể kéo image từ ECR Tokyo:**
   - *Nguyên nhân:* IAM Node Role thiếu policy `AmazonEC2ContainerRegistryReadOnly`.
   - *Cách sửa:* Vào IAM Role `dr-tokyo-eks-node-role`, gắn thêm policy này.

---

## Cost note

- Cụm Control Plane Tokyo: $0.10/giờ ($\approx$ $73/tháng).
- 1 worker node `t3.medium` tại Tokyo: $\approx$ $0.04/giờ ($\approx$ $30/tháng).
- Chế độ 1 node giúp giảm 50% chi phí compute cho vùng DR trong suốt quá trình thử nghiệm.

---

## Next step

Tiếp tục chuyển sang [LAB 07 - Cài Đặt AWS Load Balancer Controller Đa Vùng](07-aws-load-balancer-controller.md).
