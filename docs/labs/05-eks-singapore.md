# LAB 05 - Khởi Tạo Cụm Kubernetes EKS Singapore (EKS Singapore)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Tạo IAM Role cho EKS Control Plane và IAM Role cho EKS Worker Nodes theo chuẩn AWS.
2. Khởi tạo cụm Kubernetes EKS `dr-sg-eks` tại vùng Singapore (`ap-southeast-1`) đặt trong VPC `dr-sg-vpc`.
3. Tạo Managed Node Group `dr-sg-workers` hoạt động trên các **Private Subnets** với khả năng tự động co giãn (Auto Scaling) từ 2 đến 6 nodes.
4. Cấu hình xác thực và kết nối `kubectl` từ máy trạm vào cụm EKS.
5. Không sử dụng EKS Auto Mode để nắm vững toàn diện cơ chế networking, node group, và pod scheduling.

---

## Architecture impact

```text
[ EKS Control Plane: dr-sg-eks (AWS Managed Multi-AZ) ]
                        |
            +-----------+-----------+
            | (Private VPC Connectivity)
            v                       v
  [ Private Subnet AZ-a ]   [ Private Subnet AZ-b ]
  ---------------------     ---------------------
  Node 1: dr-sg-workers     Node 2: dr-sg-workers
  (t3.medium / m5.large)    (t3.medium / m5.large)
            |                       |
            +-----------+-----------+
                        |
                        v
        Kéo container images từ ECR qua NAT Gateway
```

---

## Resource naming

- EKS Cluster Name: `dr-sg-eks`
- EKS Cluster IAM Role: `dr-sg-eks-cluster-role`
- Node Group IAM Role: `dr-sg-eks-node-role`
- Managed Node Group Name: `dr-sg-workers`
- Kubernetes Version: `1.29` (hoặc phiên bản ổn định mới nhất được AWS hỗ trợ)
- Instance Type: `t3.medium` (phù hợp học tập) hoặc `m5.large`

---

## AWS Console Steps

### Bước 1: Tạo IAM Role cho EKS Cluster Control Plane
1. Mở AWS Management Console -> Dịch vụ **IAM**.
2. Chọn **Roles** -> Nhấn **Create role**.
3. Chọn **AWS service** -> Tại mục *Use case for other AWS services*, chọn **EKS** -> Chọn **EKS - Cluster** -> Nhấn **Next**.
4. AWS sẽ tự động gắn policy: `AmazonEKSClusterPolicy`. Nhấn **Next**.
5. Đặt Role name: `dr-sg-eks-cluster-role`.
6. Nhấn nút **Create role**.

### Bước 2: Tạo IAM Role cho EKS Node Group
1. Tại IAM Console -> **Roles** -> Nhấn **Create role**.
2. Chọn **AWS service** -> Use case: Chọn **EC2** -> Nhấn **Next**.
3. Tại trang *Add permissions*, tìm và tích chọn 3 policies sau:
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEC2ContainerRegistryReadOnly`
   - `AmazonEKS_CNI_Policy`
4. Nhấn **Next**.
5. Đặt Role name: `dr-sg-eks-node-role`.
6. Nhấn nút **Create role**.

### Bước 3: Khởi Tạo EKS Cluster `dr-sg-eks`
1. Đảm bảo Region đang chọn là **Asia Pacific (Singapore) ap-southeast-1**.
2. Tìm kiếm và chọn dịch vụ **Elastic Kubernetes Service (EKS)**.
3. Ở menu bên trái, chọn **Clusters** -> Nhấn nút **Add cluster** -> Chọn **Create**.
4. **Trang 1: Configure cluster:**
   - **Name:** `dr-sg-eks`
   - **Kubernetes version:** Chọn `1.29` (hoặc phiên bản mặc định khuyến nghị).
   - **Cluster service role:** Chọn `dr-sg-eks-cluster-role`.
   - Nhấn **Next**.
5. **Trang 2: Specify networking:**
   - **VPC:** Chọn `dr-sg-vpc`.
   - **Subnets:** Chỉ chọn 2 Private Subnets (`dr-sg-priv-sub-a` và `dr-sg-priv-sub-b`). Xóa các public subnets khỏi danh sách này để đảm bảo Control Plane ENI chỉ gắn vào private subnets.
   - **Security groups:** Để mặc định (AWS sẽ tự tạo cluster security group).
   - **Cluster endpoint access:** Chọn **Public and private** (Cho phép bạn thao tác `kubectl` từ máy trạm qua public endpoint nhưng worker nodes giao tiếp với control plane qua private VPC).
   - Nhấn **Next**.
6. **Trang 3: Configure observability:**
   - Giữ mặc định (hoặc bật API, Audit nếu cần) -> Nhấn **Next**.
7. **Trang 4: Select add-ons:**
   - Giữ các add-on cốt lõi: *Amazon VPC CNI*, *CoreDNS*, *Kube-proxy*, *EKS Pod Identity Agent* -> Nhấn **Next** -> **Next**.
8. **Trang 5: Review and create:**
   - Kiểm tra lại toàn bộ thông tin -> Nhấn **Create**.
   - Trạng thái cluster sẽ là `Creating` trong khoảng 8 - 12 phút. Đợi đến khi chuyển sang màu xanh **Active**.

### Bước 4: Tạo Managed Node Group `dr-sg-workers`
1. Khi cluster `dr-sg-eks` đã `Active`, chuyển sang tab **Compute** trong chi tiết cluster.
2. Tại mục *Node groups*, nhấn nút **Add node group**.
3. **Trang 1: Configure node group:**
   - **Name:** `dr-sg-workers`
   - **Node IAM Role:** Chọn `dr-sg-eks-node-role`.
   - Nhấn **Next**.
4. **Trang 2: Set compute and scaling configuration:**
   - **AMI type:** Amazon Linux 2 (AL2_x86_64) hoặc AL2023.
   - **Capacity type:** On-Demand.
   - **Instance types:** Chọn `t3.medium` (2 vCPU, 4 GiB RAM).
   - **Disk size:** 20 GiB.
   - **Scaling configuration:**
     - **Minimum size:** `2`
     - **Maximum size:** `6`
     - **Desired size:** `2`
   - Nhấn **Next**.
5. **Trang 3: Specify networking:**
   - **Subnets:** Bắt buộc chỉ chọn 2 Private Subnets (`dr-sg-priv-sub-a` và `dr-sg-priv-sub-b`).
   - Tắt tùy chọn *Configure SSH access to nodes* (Tuân thủ Zero Trust).
   - Nhấn **Next**.
6. **Trang 4: Review and create:**
   - Nhấn **Create**.
   - Node group sẽ chuyển sang `Active` sau 3 - 5 phút.

---

## Configuration

| Thành phần | Cấu hình áp dụng | Ghi chú |
|---|---|---|
| **Cluster Name** | `dr-sg-eks` | Cụm Primary tại Singapore |
| **Node Group** | `dr-sg-workers` | Managed Node Group |
| **Instance Type** | `t3.medium` | 2 vCPU, 4GB RAM |
| **Subnet Placement** | Private Subnets (`10.10.10.0/24`, `10.10.11.0/24`) | An toàn, không có Public IP |
| **Capacity** | Min: 2, Desired: 2, Max: 6 | Multi-AZ High Availability |

---

## Security considerations

- **Node trong Private Subnet:** Worker nodes tuyệt đối không có Public IP, triệt tiêu nguy cơ bị scan cổng từ Internet.
- **IAM Node Role Least Privilege:** Chỉ cấp quyền kéo image (ECR ReadOnly), quản lý ENI IP (VPC CNI) và kết nối cluster. Không cấp quyền Admin hay Full S3.
- **Cluster Endpoint Access:** Thiết lập *Public and private* cho phép quản trị an toàn mà không làm lộ mạng nội bộ.

---

## Expected result

- EKS Cluster `dr-sg-eks` trạng thái **Active**.
- Managed Node Group `dr-sg-workers` trạng thái **Active**.
- Có 2 Worker Nodes hiển thị trong danh sách Nodes với trạng thái **Ready**.

---

## Verification

### Kiểm tra bằng Console
1. EKS Console -> Clusters -> `dr-sg-eks` -> Tab *Compute*: Thấy `dr-sg-workers` có 2 nodes Ready.

### Cấu hình kubeconfig và kiểm tra bằng CLI
```bash
# Cập nhật kubeconfig từ AWS
aws eks update-kubeconfig --region ap-southeast-1 --name dr-sg-eks

# Kiểm tra danh sách Node
kubectl get nodes -o wide
```
*Expected output:*
```text
NAME                                                STATUS   ROLES    AGE   VERSION               INTERNAL-IP
ip-10-10-10-45.ap-southeast-1.compute.internal     Ready    <none>   5m    v1.29.3-eks-ae9a62a   10.10.10.45
ip-10-10-11-82.ap-southeast-1.compute.internal     Ready    <none>   5m    v1.29.3-eks-ae9a62a   10.10.11.82
```

Kiểm tra trạng thái các Pods hệ thống:
```bash
kubectl get pods -A
```
*Expected output:* Toàn bộ pods của `kube-system` (coredns, aws-node, kube-proxy) đều ở trạng thái `Running`.

---

## Troubleshooting

1. **Lỗi: Nodes không join vào cluster (Node Group mãi ở trạng thái NotReady hoặc Degraded):**
   - *Nguyên nhân:* Private subnets không đi được ra Internet qua NAT Gateway nên Node không thể kết nối tới EKS Control Plane API.
   - *Cách sửa:* Kiểm tra bảng định tuyến của `dr-sg-priv-rt` đã có route `0.0.0.0/0 -> dr-sg-nat-a` chưa, và đảm bảo NAT Gateway đang `Available`.
2. **Lỗi: `error: You must be logged in to the server (Unauthorized)` khi chạy kubectl:**
   - *Nguyên nhân:* User IAM hiện tại chưa được cấp quyền trong EKS Access Entries.
   - *Cách sửa:* Trong EKS Console -> `dr-sg-eks` -> Tab **Access** -> Chọn **Create access entry** -> Nhập IAM Principal ARN của bạn -> Gán policy `AmazonEKSClusterAdminPolicy`.
3. **Lỗi: Coredns Pod ở trạng thái `CrashLoopBackOff` hoặc `Pending`:**
   - *Nguyên nhân:* Add-on `aws-node` (VPC CNI) bị lỗi cấp phát IP do subnet bị hết địa chỉ IP khả dụng.
   - *Cách sửa:* Kiểm tra subnet CIDR có đủ IP trống không (dải `/24` cung cấp hơn 250 IPs, hoàn toàn đủ cho lab).

---

## Cost note

- **EKS Control Plane:** AWS thu phí cố định $0.10/giờ ($\approx$ $73/tháng cho mỗi cluster).
- **EC2 Worker Nodes:** 2 node `t3.medium` tiêu tốn khoảng $0.0416/giờ/node ($\approx$ $60/tháng).
- **Cảnh báo chi phí:** Đây là tài nguyên tốn kém nhất. Nếu không sử dụng trong nhiều ngày, bạn có thể xóa Node Group và Cluster rồi tái tạo lại nhanh chóng bằng script.

---

## Next step

Tiếp tục chuyển sang [LAB 06 - Khởi Tạo Cụm Kubernetes EKS Tokyo Standby](06-eks-tokyo.md).
