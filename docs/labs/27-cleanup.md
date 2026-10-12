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

### 6.0 Dừng và bảo toàn storage DR trước

1. Dừng traffic của `dr-file-global-accelerator` và hai storage ALB.
2. Dừng file-service; unmount `/mnt/dr-data` trên cả hai EC2.
3. Thu bằng chứng và tạo backup/snapshot theo retention policy.
4. Xác định volume authoritative. Xóa/release SnapMirror đúng hai phía; không chạy `resync` chỉ để cleanup.
5. Xóa destination volume/SVM/file system trước source khi được phê duyệt.
6. Terminate storage EC2, instance profile, SG và log groups sau khi dữ liệu đã được bảo toàn.

### 6.1 Kiểm kê trước khi xóa

```bash
aws sts get-caller-identity
aws eks list-clusters --region ap-southeast-1
aws eks list-clusters --region ap-northeast-1
aws rds describe-global-clusters --region <CURRENT_PRIMARY_REGION> --global-cluster-identifier app2-global-db
aws globalaccelerator list-accelerators --region us-west-2
```

Ghi lại tag và ARN. Dừng nếu có tài nguyên ngoài dự kiến dùng chung VPC hoặc security group.

### 6.2 Xóa trước các tài nguyên AWS do Kubernetes tạo

```bash
kubectl --context singapore delete -f gitops/infra-validation/singapore.yaml
kubectl --context tokyo delete -f gitops/infra-validation/tokyo.yaml
```

Nếu app2 được triển khai ở giai đoạn sau, xóa Argo CD Application qua quy trình GitOps đã phê duyệt trước khi gỡ controller. Chờ ALB, listener, target group và security group do controller quản lý biến mất.

### 6.3 Xóa Global Accelerator

AWS Console:

1. Global Accelerator -> accelerator -> Listener.
2. Gỡ endpoint khỏi từng endpoint group.
3. Xóa endpoint group.
4. Xóa listener.
5. Tắt accelerator.
6. Xóa accelerator.

Xác minh accelerator không còn xuất hiện trong `list-accelerators`.

### 6.4 Gỡ phần mềm nền tảng khỏi cluster

```bash
helm uninstall argocd --kube-context singapore -n argocd
helm uninstall argocd --kube-context tokyo -n argocd
helm uninstall aws-load-balancer-controller --kube-context singapore -n kube-system
helm uninstall aws-load-balancer-controller --kube-context tokyo -n kube-system
```

Gỡ External Secrets/add-on quan sát tùy chọn nếu đã cài. Xóa namespace không đảm bảo tài nguyên AWS bên ngoài đã biến mất; phải xác minh trước.

### 6.5 Xóa node group, sau đó xóa EKS cluster

```text
EKS Singapore -> dr-sg-eks -> Compute -> dr-sg-ng -> Delete
EKS Tokyo -> dr-tokyo-eks -> Compute -> dr-tokyo-ng -> Delete
```

Chờ node group biến mất rồi xóa từng cluster. Sau đó mới gỡ OIDC provider và IAM role riêng của cluster, sau khi xác nhận không cluster/service account nào khác sử dụng chúng.

### 6.6 Xóa Aurora Global Database an toàn

1. Xác nhận retention policy và tạo/xác minh final snapshot nếu bắt buộc.
2. Chỉ tắt deletion protection khi được phê duyệt.
3. Gỡ/xóa secondary regional cluster và các instance theo quy trình RDS Console hiện hành.
4. Chỉ gỡ primary khỏi global cluster khi quy trình Console yêu cầu.
5. Xóa regional instance, regional cluster, sau đó xóa global cluster rỗng.
6. Chỉ xóa DB subnet group và DB security group sau khi mọi tài nguyên DB đã biến mất.

Không mặc định chọn `Skip final snapshot`. Không xóa writer hiện tại trước khi xác nhận bản sao được giữ lại.

### 6.7 Xóa Secrets Manager replica và primary

Trong Region của primary secret, gỡ replica Region trước, sau đó lên lịch xóa `/app2/database` với recovery window bắt buộc. Force deletion tức thời không phải mặc định của lab.

### 6.8 Xóa ECR repository nếu được phê duyệt

Kiểm tra yêu cầu lưu giữ image. Xóa repository/image đích, sau đó repository nguồn và quy tắc registry replication. Thao tác buộc xóa repository sẽ xóa image vĩnh viễn.

### 6.9 Xóa peering và tài nguyên mạng

1. Chỉ xóa VPC peering sau khi SnapMirror relationship và intercluster dependency đã biến mất.
2. Xóa NAT Gateway; chờ trạng thái `deleted`.
3. Giải phóng Elastic IP allocation.
4. Gỡ non-main route table, network interface, endpoint và security group.
5. Tháo/xóa IGW.
6. Xóa subnet.
7. Xóa VPC.

Thực hiện riêng tại Singapore và Tokyo. Xác minh mỗi target thuộc `dr-sg-vpc` hoặc `dr-tokyo-vpc`.

### 6.10 Xóa alarm và log tùy chọn

Chỉ xóa alarm, dashboard, SNS topic/subscription và log group của lab sau khi đáp ứng yêu cầu lưu giữ/bằng chứng.

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
