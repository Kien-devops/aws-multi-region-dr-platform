# LAB 07 - Cài Đặt AWS Load Balancer Controller Đa Vùng (AWS Load Balancer Controller)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Tạo IAM OIDC Provider cho cả hai cụm EKS `dr-sg-eks` và `dr-tokyo-eks`.
2. Tạo IAM Role theo cơ chế IAM Roles for Service Accounts (IRSA) cho AWS Load Balancer Controller.
3. Cài đặt AWS Load Balancer Controller thông qua Helm trên cả hai cụm.
4. Triển khai một Ingress thử nghiệm để xác nhận Controller tự động kích hoạt tạo Application Load Balancer (ALB) công cộng tại cả Singapore và Tokyo với chế độ định tuyến IP (`target-type: ip`).

---

## Architecture impact

```text
[ Developer / Helm / Argo CD ]
              |
              v
[ Kubernetes Ingress Resource (target-type: ip) ]
              |
              v (Watches Ingress Events)
[ AWS Load Balancer Controller Pod (kube-system) ]
              |
              | (Giao tiếp qua IRSA: sts:AssumeRoleWithWebIdentity)
              v
[ AWS ELB API (ap-southeast-1 / ap-northeast-1) ]
              |
              v (Tự động khởi tạo hạ tầng AWS)
[ Application Load Balancer (Public Subnets) ]
              |
              +---> [ Target Group: IP Mode ]
                         |
                         +---> Pod IP 1: 10.10.10.x
                         +---> Pod IP 2: 10.10.11.y
```

---

## Resource naming

- IAM Policy: `AWSLoadBalancerControllerIAMPolicy`
- IAM Role Singapore: `dr-sg-aws-lb-controller-role`
- IAM Role Tokyo: `dr-tokyo-aws-lb-controller-role`
- Kubernetes ServiceAccount: `aws-load-balancer-controller`
- Kubernetes Namespace: `kube-system`
- Helm Release Name: `aws-load-balancer-controller`

---

## AWS Console & CLI Steps

### Bước 1: Tạo IAM Policy cho Load Balancer Controller
1. Tải file chính sách IAM chính thức do AWS cung cấp:
   ```bash
   curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.1/docs/install/iam_policy.json
   ```
2. Mở AWS Console -> **IAM** -> **Policies** -> **Create policy**.
3. Chuyển sang tab **JSON** -> Dán toàn bộ nội dung file `iam_policy.json` vừa tải.
4. Nhấn **Next** -> Đặt tên Policy: `AWSLoadBalancerControllerIAMPolicy`.
5. Nhấn **Create policy**.

### Bước 2: Thiết Lập OIDC Provider và IRSA cho Singapore
1. **Liên kết OIDC Provider cho cụm Singapore:**
   - Trong EKS Console -> Chọn cụm `dr-sg-eks` -> Copy chuỗi **OpenID Connect provider URL** (dạng `https://oidc.eks.ap-southeast-1.amazonaws.com/id/EXAMPLED5...`).
   - Vào IAM -> **Identity providers** -> **Add provider**:
     - Provider type: **OpenID Connect**.
     - Provider URL: Dán URL vừa copy -> Nhấn **Get thumbprint**.
     - Audience: Nhập `sts.amazonaws.com` -> Nhấn **Add provider**.
2. **Tạo IAM Role cho ServiceAccount Singapore:**
   - Vào IAM -> **Roles** -> **Create role** -> Chọn **Web identity**.
   - Identity provider: Chọn OIDC provider của `dr-sg-eks`.
   - Audience: `sts.amazonaws.com` -> Nhấn **Next**.
   - Gắn policy: `AWSLoadBalancerControllerIAMPolicy` -> Nhấn **Next**.
   - Role name: `dr-sg-aws-lb-controller-role` -> Nhấn **Create role**.
   - Vào tab **Trust relationships** của role, chỉnh sửa điều kiện `StringEquals` để gắn chặt vào ServiceAccount:
     ```json
     {
       "Version": "2012-10-17",
       "Statement": [
         {
           "Effect": "Allow",
           "Principal": {
             "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.ap-southeast-1.amazonaws.com/id/<OIDC_ID_SG>"
           },
           "Action": "sts:AssumeRoleWithWebIdentity",
           "Condition": {
             "StringEquals": {
               "oidc.eks.ap-southeast-1.amazonaws.com/id/<OIDC_ID_SG>:aud": "sts.amazonaws.com",
               "oidc.eks.ap-southeast-1.amazonaws.com/id/<OIDC_ID_SG>:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
             }
           }
         }
       ]
     }
     ```

### Bước 3: Thiết Lập OIDC Provider và IRSA cho Tokyo
Thực hiện tương tự Bước 2 cho cụm Tokyo:
1. Lấy OIDC URL của `dr-tokyo-eks` -> Tạo Identity Provider trên IAM.
2. Tạo Role `dr-tokyo-aws-lb-controller-role` gắn policy `AWSLoadBalancerControllerIAMPolicy`.
3. Cập nhật Trust Policy trỏ tới OIDC của Tokyo và ServiceAccount `system:serviceaccount:kube-system:aws-load-balancer-controller`.

### Bước 4: Cài Đặt Controller Bằng Helm Trên Cả Hai Cụm

#### 1. Cài đặt trên cụm Singapore:
```bash
# Đổi context sang Singapore
kubectl config use-context singapore

# Thêm Helm repo của EKS
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

# Tạo ServiceAccount gắn IAM Role Singapore
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/dr-sg-aws-lb-controller-role
EOF

# Lấy VPC ID của Singapore
VPC_ID_SG=$(aws ec2 describe-vpcs --region ap-southeast-1 --filters "Name=tag:Name,Values=dr-sg-vpc" --query "Vpcs[0].VpcId" --output text)

# Cài đặt Controller qua Helm
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=dr-sg-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-southeast-1 \
  --set vpcId=$VPC_ID_SG
```

#### 2. Cài đặt trên cụm Tokyo:
```bash
# Đổi context sang Tokyo
kubectl config use-context tokyo

# Tạo ServiceAccount gắn IAM Role Tokyo
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/dr-tokyo-aws-lb-controller-role
EOF

# Lấy VPC ID của Tokyo
VPC_ID_TOKYO=$(aws ec2 describe-vpcs --region ap-northeast-1 --filters "Name=tag:Name,Values=dr-tokyo-vpc" --query "Vpcs[0].VpcId" --output text)

# Cài đặt Controller qua Helm
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=dr-tokyo-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-1 \
  --set vpcId=$VPC_ID_TOKYO
```

---

## Configuration

Các annotations bắt buộc trên Ingress resource để kích hoạt ALB:
```yaml
annotations:
  alb.ingress.kubernetes.io/scheme: internet-facing
  alb.ingress.kubernetes.io/target-type: ip
  alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
  alb.ingress.kubernetes.io/healthcheck-path: /health
```

---

## Security considerations

- **IRSA (IAM Roles for Service Accounts):** Không cấp quyền IAM ở cấp độ EC2 Node mà cấp quyền trực tiếp cho ServiceAccount của Pod Controller bằng cơ chế ký số OIDC.
- **Target-Type IP Mode:** ALB gửi gói tin trực tiếp tới IP của Pod trong Private Subnet mà không cần thông qua NodePort mở rộng, tránh để lộ các cổng lạ trên EC2 Host.

---

## Expected result

- Deployment `aws-load-balancer-controller` trong namespace `kube-system` có 2 pods ở trạng thái `Running (1/1)`.
- Khi tạo Ingress, AWS Load Balancer Controller tự động tạo 1 Application Load Balancer tại EC2 Console.

---

## Verification

### Kiểm tra trạng thái Pods trên cả hai cụm
```bash
kubectl --context singapore -n kube-system get deployment aws-load-balancer-controller
kubectl --context tokyo -n kube-system get deployment aws-load-balancer-controller
```
*Expected output:*
```text
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
aws-load-balancer-controller   2/2     2            2           3m
```

### Triển khai ứng dụng mẫu 2048 để xác nhận ALB tạo thành công
```bash
# Triển khai thử nghiệm trên Singapore
kubectl --context singapore apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.1/docs/examples/2048/2048_full.yaml

# Đợi 1-2 phút và kiểm tra Ingress
kubectl --context singapore get ingress ingress-2048 -n game-2048
```
*Expected output:* Cột `ADDRESS` sẽ xuất hiện DNS Name của ALB (ví dụ: `k8s-game2048-xxxxxx.ap-southeast-1.elb.amazonaws.com`).
*(Sau khi test thành công, xóa bằng: `kubectl --context singapore delete -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.1/docs/examples/2048/2048_full.yaml`).*

---

## Troubleshooting

1. **Lỗi: `Failed deploy model due to couldn't auto-discover subnets` trong log controller:**
   - *Nguyên nhân:* Các public subnets thiếu tag `kubernetes.io/role/elb=1`.
   - *Cách sửa:* Quay lại Lab 02/03 và gắn tag `kubernetes.io/role/elb=1` cho cả 2 public subnets.
2. **Lỗi: `WebIdentityErr: failed to retrieve credentials`:**
   - *Nguyên nhân:* Trust relationship trong IAM Role không khớp chính xác với OIDC provider ID hoặc namespace/serviceaccount name.
   - *Cách sửa:* Mở IAM Role, kiểm tra trường `sub` xem có đúng là `system:serviceaccount:kube-system:aws-load-balancer-controller` không.
3. **Lỗi: ALB Target Group hiển thị toàn bộ targets là `Unused` hoặc `Unhealthy`:**
   - *Nguyên nhân:* Security Group của Worker Node chặn traffic từ Security Group của ALB, hoặc path healthcheck trả về mã lỗi khác 200.
   - *Cách sửa:* Kiểm tra Security Group cho phép traffic từ ALB vào port của Pod, và đảm bảo endpoint `/health` trả về HTTP 200.

---

## Cost note

- Mỗi Application Load Balancer phát sinh phí ~$0.0225/giờ ($\approx$ $16.20/tháng) cộng với phí LCU (Load Balancer Capacity Units).
- Khi chạy đồng thời 2 ALB ở 2 vùng, chi phí cố định là khoảng $33/tháng.

---

## Next step

Tiếp tục chuyển sang [LAB 08 - Khởi Tạo Amazon Aurora PostgreSQL Global Database](08-aurora-global-database.md).
