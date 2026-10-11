# LAB 07 - AWS Load Balancer Controller

## 1. Mục tiêu

Cài đặt AWS Load Balancer Controller độc lập trên hai EKS cluster bằng IRSA role riêng cho từng cluster và phiên bản Helm chart đã được rà soát.

## 2. Thành phần sẽ xây dựng

- IAM OIDC provider cho mỗi cluster.
- IAM policy đặc quyền tối thiểu dùng chung cho controller.
- IRSA role riêng `dr-sg-aws-lb-controller-role` và `dr-tokyo-aws-lb-controller-role`.
- Helm release `aws-load-balancer-controller` trong mỗi cluster.
- Chưa tạo Ingress/ALB cho tới LAB 11.

## 3. Bối cảnh kiến trúc

```text
Ingress -> controller pod -> IRSA -> ELB/EC2 APIs -> ALB/target groups/security groups
```

Trust policy của role phải riêng theo cluster vì mỗi EKS cluster có OIDC issuer khác nhau.

## 4. Điều kiện tiên quyết

- Hoàn thành LAB 05-06; Tokyo đang ở chế độ kiểm thử hai node.
- Public subnet có tag `kubernetes.io/role/elb=1`.
- Có sẵn `helm`, `kubectl`, `curl` và AWS CLI.
- Rà trang cài đặt controller chính thức hiện hành của AWS EKS; chọn `<GATEWAY_API_VERSION>`, `<LBC_APP_VERSION>` và `<LBC_CHART_VERSION>` tương thích. Tại ngày rà tài liệu, AWS liệt kê Gateway API CRD là điều kiện tiên quyết; không bỏ qua yêu cầu hiện hành chỉ vì lab dùng Ingress.

## 5. Quy ước đặt tên tài nguyên

| Hạng mục | Giá trị |
|---|---|
| IAM policy | `AWSLoadBalancerControllerIAMPolicy` |
| SG role | `dr-sg-aws-lb-controller-role` |
| Tokyo role | `dr-tokyo-aws-lb-controller-role` |
| ServiceAccount | `kube-system/aws-load-balancer-controller` |
| Helm release | `aws-load-balancer-controller` |

## 6. Các bước triển khai

### 6.1 Ghi lại OIDC issuer

```bash
aws eks describe-cluster --region ap-southeast-1 --name dr-sg-eks \
  --query 'cluster.identity.oidc.issuer' --output text
aws eks describe-cluster --region ap-northeast-1 --name dr-tokyo-eks \
  --query 'cluster.identity.oidc.issuer' --output text
```

### 6.2 Tạo OIDC provider trong IAM

Lặp lại cho từng issuer:

```text
IAM -> Identity providers -> Add provider
Provider type: OpenID Connect
Provider URL: exact EKS issuer URL
Audience: sts.amazonaws.com
-> Add provider
```

Kiểm tra provider hiện có trước khi tạo để tránh trùng lặp.

### 6.3 Tạo IAM policy chính thức cho controller

Tải policy từ đúng release tag của controller đã rà soát:

```bash
curl -o iam_policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v<LBC_APP_VERSION>/docs/install/iam_policy.json
```

Kiểm tra file đã tải. Sau đó:

```text
IAM -> Policies -> Create policy -> JSON
Paste reviewed iam_policy.json
Name: AWSLoadBalancerControllerIAMPolicy
-> Create
```

Không dùng `AdministratorAccess`.

### 6.4 Tạo IRSA role cho Singapore

```text
IAM -> Roles -> Create role -> Web identity
Identity provider: dr-sg-eks OIDC provider
Audience: sts.amazonaws.com
Attach: AWSLoadBalancerControllerIAMPolicy
Name: dr-sg-aws-lb-controller-role
```

Sửa điều kiện trust policy thành đúng các giá trị sau:

```text
<SG_OIDC_HOSTPATH>:aud = sts.amazonaws.com
<SG_OIDC_HOSTPATH>:sub = system:serviceaccount:kube-system:aws-load-balancer-controller
```

Lặp lại tại Tokyo bằng OIDC provider và tên role tương ứng.

### 6.5 Tạo ServiceAccount có annotation

```bash
kubectl --context singapore -n kube-system create serviceaccount aws-load-balancer-controller
kubectl --context singapore -n kube-system annotate serviceaccount aws-load-balancer-controller \
  eks.amazonaws.com/role-arn=arn:aws:iam::<ACCOUNT_ID>:role/dr-sg-aws-lb-controller-role

kubectl --context tokyo -n kube-system create serviceaccount aws-load-balancer-controller
kubectl --context tokyo -n kube-system annotate serviceaccount aws-load-balancer-controller \
  eks.amazonaws.com/role-arn=arn:aws:iam::<ACCOUNT_ID>:role/dr-tokyo-aws-lb-controller-role
```

Nếu ServiceAccount đã tồn tại, kiểm tra quyền sở hữu rồi dùng `annotate --overwrite`.

### 6.6 Cài Gateway API CRD

Dùng bản phát hành Gateway API chính thức đã rà soát trên cả hai cluster:

```bash
kubectl --context singapore apply --server-side \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/<GATEWAY_API_VERSION>/standard-install.yaml
kubectl --context tokyo apply --server-side \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/<GATEWAY_API_VERSION>/standard-install.yaml
```

### 6.7 Cài đặt bằng Helm

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm search repo eks/aws-load-balancer-controller --versions | head
```

```bash
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --kube-context singapore -n kube-system \
  --version <LBC_CHART_VERSION> \
  --set clusterName=dr-sg-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-southeast-1 \
  --set vpcId=<SG_VPC_ID> \
  --wait --timeout 10m

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --kube-context tokyo -n kube-system \
  --version <LBC_CHART_VERSION> \
  --set clusterName=dr-tokyo-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-1 \
  --set vpcId=<TOKYO_VPC_ID> \
  --wait --timeout 10m
```

## 7. Xác minh

```bash
kubectl --context singapore -n kube-system get deployment aws-load-balancer-controller
kubectl --context tokyo -n kube-system get deployment aws-load-balancer-controller
kubectl --context singapore -n kube-system get serviceaccount aws-load-balancer-controller -o yaml
kubectl --context tokyo -n kube-system get serviceaccount aws-load-balancer-controller -o yaml
helm list --kube-context singapore -n kube-system
helm list --kube-context tokyo -n kube-system
```

Deployment phải có replica khả dụng. Không tạo ALB tại đây; LAB 11 sẽ kiểm chứng bằng workload tạm thời.

## 8. Kết quả mong đợi

Cả hai controller khỏe mạnh và dùng IRSA role đặc quyền tối thiểu riêng. Chưa có application Ingress.

## 9. Xử lý sự cố

- `WebIdentityErr`: OIDC provider, audience, subject hoặc role annotation không khớp.
- `AccessDenied`: so sánh IAM policy đã cài với tài liệu của đúng controller release.
- Không tìm thấy subnet ở bước sau: kiểm tra role tag của public/private subnet.
- Lỗi Helm CRD khi nâng cấp: Helm không phải lúc nào cũng cập nhật CRD; làm theo ghi chú nâng cấp chính thức của release.

## 10. Lưu ý bảo mật

- Trust policy phải chứa chính xác subject của ServiceAccount.
- Mỗi cluster dùng role riêng; có thể dùng chung policy.
- Rà diff của policy trước khi nâng cấp controller.
- CloudTrail nên ghi nhận thay đổi ELB/EC2 được thực hiện qua role.

## 11. Lưu ý chi phí

Pod controller dùng node hiện có. Chi phí ALB chỉ bắt đầu khi LAB 11 tạo tài nguyên Ingress.

## 12. Dọn dẹp / Quay lui

Gỡ Helm release, xóa ServiceAccount, sau đó chỉ gỡ role/OIDC provider khi không còn workload IRSA nào sử dụng chúng.

## 13. Bằng chứng cần thu thập

Phiên bản ứng dụng/chart của controller, source tag của IAM policy, OIDC issuer, điều kiện trust, annotation ServiceAccount và trạng thái sẵn sàng của deployment.

## 14. Lab tiếp theo

Tiếp tục với [LAB 08 - Aurora PostgreSQL Global Database](08-aurora-global-database.md).
