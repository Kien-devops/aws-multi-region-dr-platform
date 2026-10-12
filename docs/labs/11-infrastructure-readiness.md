# LAB 11 - Xác minh mức độ sẵn sàng của hạ tầng

> **Ranh giới giai đoạn:** Đây là kiểm tra hạ tầng. Workload `infra-validation` là tạm thời, không phải app2.

## 1. Mục tiêu

Chứng minh hai EKS cluster, AWS Load Balancer Controller, public subnets, ALB target groups, Aurora Global Database, Secrets Manager và Argo CD đã sẵn sàng trước khi cấu hình Global Accelerator.

## 2. Thành phần sẽ xây dựng

- Namespace tạm thời `infra-validation` trên hai cluster.
- NGINX Deployment, Service và ALB internet-facing tạm thời tại mỗi Region.
- Không tạo frontend/backend app2, không dùng image app2, không tạo Argo CD Application.

## 3. Bối cảnh kiến trúc

```text
Internet
  |-- dr-sg-validation-alb --> pod kiểm thử trên EKS Singapore
  `-- dr-tokyo-validation-alb --> pod kiểm thử trên EKS Tokyo

Aurora Global Database + replicated secret + Argo CD
  `-- xác minh độc lập; không phụ thuộc ứng dụng
```

Hai ALB tạm thời trở thành endpoint thật cho LAB 12. Xóa chúng ở LAB 27 hoặc ngay sau khi hoàn tất GA test.

## 4. Điều kiện tiên quyết

- Hoàn thành LAB 00-10.
- Controller deployment `Available` ở hai cluster.
- Public subnet tags `kubernetes.io/role/elb=1` tồn tại.
- Node group Tokyo có đủ capacity cho hai validation pods.

## 5. Quy ước đặt tên tài nguyên

| Tài nguyên | Singapore | Tokyo |
|---|---|---|
| Namespace | `infra-validation` | `infra-validation` |
| Deployment/Service/Ingress | `hello` | `hello` |
| ALB | `dr-sg-validation-alb` | `dr-tokyo-validation-alb` |
| Manifest | `gitops/infra-validation/singapore.yaml` | `gitops/infra-validation/tokyo.yaml` |

## 6. Các bước triển khai

### 6.1 Rà soát manifest tạm thời

```bash
kubectl apply --dry-run=server --context singapore -f gitops/infra-validation/singapore.yaml
kubectl apply --dry-run=server --context tokyo -f gitops/infra-validation/tokyo.yaml
```

Image chỉ dùng để kiểm thử. Phân giải và pin digest trước khi dùng cùng mô hình bên ngoài workload lab dùng một lần này.

### 6.2 Triển khai workload kiểm thử

```bash
kubectl --context singapore apply -f gitops/infra-validation/singapore.yaml
kubectl --context tokyo apply -f gitops/infra-validation/tokyo.yaml

kubectl --context singapore -n infra-validation rollout status deployment/hello --timeout=5m
kubectl --context tokyo -n infra-validation rollout status deployment/hello --timeout=5m
```

### 6.3 Chờ cả hai ALB

```bash
kubectl --context singapore -n infra-validation get ingress hello -w
kubectl --context tokyo -n infra-validation get ingress hello -w
```

Dừng từng lệnh watch khi `ADDRESS` xuất hiện. Ghi lại giá trị:

```bash
kubectl --context singapore -n infra-validation get ingress hello \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
kubectl --context tokyo -n infra-validation get ingress hello \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### 6.4 Xác minh sức khỏe target của ALB

AWS Console:

```text
EC2 -> Load Balancers -> dr-sg-validation-alb -> Resource map
EC2 -> Target Groups -> Targets -> confirm healthy targets
```

Lặp lại tại Tokyo. Kiểm tra từng tên DNS ALB bằng `curl -sS http://<ALB_DNS_NAME>/`; nội dung trả về phải xác định `singapore` hoặc `tokyo`.

### 6.5 Xác minh thành phần nền tảng khi chưa có app2

```bash
kubectl --context singapore get nodes
kubectl --context tokyo get nodes
kubectl --context singapore -n kube-system get deployment aws-load-balancer-controller
kubectl --context tokyo -n kube-system get deployment aws-load-balancer-controller
kubectl --context singapore -n argocd get pods
kubectl --context tokyo -n argocd get pods

aws rds describe-global-clusters --region ap-southeast-1 --global-cluster-identifier app2-global-db \
  --query 'GlobalClusters[0].{Status:Status,Endpoint:Endpoint,Members:GlobalClusterMembers[*].{Arn:DBClusterArn,Writer:IsWriter,Sync:SynchronizationStatus}}'

aws secretsmanager describe-secret --region ap-southeast-1 --secret-id /app2/database
aws secretsmanager describe-secret --region ap-northeast-1 --secret-id /app2/database
```

Không in giá trị secret vào terminal log hoặc file bằng chứng.

## 7. Xác minh

Tiêu chí đạt:

- Cả hai cluster báo node Ready.
- Cả hai controller deployment ở trạng thái Available.
- Hai ALB tồn tại trên hai public subnet và có IP target khỏe mạnh.
- Aurora global cluster là `available`; chính xác một member là writer.
- Trạng thái secret replication là `InSync`.
- Pod Argo CD khỏe mạnh; số lượng Application vẫn bằng không.

## 8. Kết quả mong đợi

Có thể tuyên bố `HẠ TẦNG SẴN SÀNG` cho các thành phần đã xác minh trực tiếp. Trạng thái `ỨNG DỤNG CHƯA ĐƯỢC TRIỂN KHAI` vẫn phải được nêu rõ.

## 9. Xử lý sự cố

- Ingress không có address: kiểm tra controller log và role tag của subnet.
- ALB tồn tại nhưng target không khỏe: kiểm tra readiness path `/`, target-type `ip`, mạng node/pod và quy tắc security group.
- Pod Tokyo `Pending`: scale `dr-tokyo-ng` lên hai node để kiểm thử.
- Aurora member chưa đồng bộ: dừng; không tiếp tục diễn tập DR.

## 10. Lưu ý bảo mật

- Workload kiểm thử không chứa credential và chỉ public trang tĩnh.
- ALB được chủ động đặt public; xóa khi kết thúc kiểm thử.
- Không public Kubernetes API hoặc Argo CD UI qua các ALB này.
- Không thu giá trị secret làm bằng chứng.

## 11. Lưu ý chi phí

Mỗi ALB tính phí theo giờ và LCU. Hai ALB kiểm thử là điều kiện có chủ đích để LAB Global Accelerator có thể chạy thực tế.

## 12. Dọn dẹp / Quay lui

Để dừng kiểm thử GA tại đây:

```bash
kubectl --context singapore delete -f gitops/infra-validation/singapore.yaml
kubectl --context tokyo delete -f gitops/infra-validation/tokyo.yaml
```

Chờ controller xóa cả hai ALB và target group. Nếu tiếp tục, giữ chúng tới hết LAB 17.

## 13. Bằng chứng cần thu thập

- `kubectl get nodes` cho cả hai context.
- Trạng thái controller deployment.
- ALB resource map và ảnh target khỏe mạnh.
- Topology Aurora Global Database với một writer.
- Trạng thái secret replication, chỉ metadata.
- Pod Argo CD và xác nhận không có Application.

## 14. Lab tiếp theo

Tiếp tục với [LAB 12 - Kiểm thử hạ tầng Global Accelerator](12-global-accelerator.md).
