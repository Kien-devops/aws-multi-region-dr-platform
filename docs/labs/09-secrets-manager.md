# LAB 09 - Quản Lý Bí Mật Với AWS Secrets Manager Đa Vùng (Secrets Manager & ESO)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Tạo Secret `app2/database` trên AWS Secrets Manager tại vùng chính Singapore (`ap-southeast-1`) chứa thông tin kết nối PostgreSQL theo đúng hợp đồng ứng dụng:
   - `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`.
2. Thiết lập tính năng **Multi-Region Secret Replication** để tự động đồng bộ bí mật sang vùng dự phòng Tokyo (`ap-northeast-1`).
3. Cài đặt **External Secrets Operator (ESO)** trên cả hai cụm EKS bằng Helm sử dụng IRSA.
4. Triển khai `ClusterSecretStore` và `ExternalSecret` để tạo Kubernetes Secret `app2-db-secret` trong namespace `app2`.
5. Áp dụng nguyên tắc **Least Privilege (Đặc quyền tối thiểu)**: Chỉ cung cấp thông tin kết nối cơ sở dữ liệu cho duy nhất microservice `app2-backend-3` (Order & Payment Service). Hai dịch vụ `app2-backend-1` và `app2-backend-2` hoàn toàn không được cấp secret này.

---

## Architecture impact

```text
[ AWS Secrets Manager: Singapore ]
  Secret: app2/database
  (DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME)
            |
            | (AWS Native Multi-Region Replication)
            v
[ AWS Secrets Manager: Tokyo ]
  Secret: app2/database (Replicated Replica)
            |
            +---------------------------------------+
            |                                       |
            v                                       v
[ External Secrets Operator (SG) ]      [ External Secrets Operator (Tokyo) ]
  (dr-sg-eks - IRSA)                      (dr-tokyo-eks - IRSA)
            |                                       |
            v                                       v
[ K8s Secret: app2-db-secret ]          [ K8s Secret: app2-db-secret ]
            |                                       |
            v (Chỉ inject vào backend-3)            v (Chỉ inject vào backend-3)
[ app2-backend-3 Pods ]                 [ app2-backend-3 Pods ]
(backend-1 và backend-2 KHÔNG nhận DB secret để bảo đảm Least Privilege)
```

---

## Resource naming

- Secret Name: `app2/database`
- Secret Keys:
  - `DB_HOST`: Hostname của Writer Endpoint
  - `DB_PORT`: `5432`
  - `DB_USER`: `app2_admin`
  - `DB_PASSWORD`: Mật khẩu cơ sở dữ liệu đã tạo tại Lab 08
  - `DB_NAME`: `app2`
- IAM Policy Name: `App2SecretsManagerReadPolicy`
- IAM Role Singapore: `dr-sg-eso-role`
- IAM Role Tokyo: `dr-tokyo-eso-role`
- Kubernetes Target Secret: `app2-db-secret` (trong namespace `app2`)

---

## AWS Console Steps

### Bước 1: Tạo Secret tại Singapore
1. Mở AWS Console tại Region **Asia Pacific (Singapore) ap-southeast-1**.
2. Tìm kiếm và chọn dịch vụ **Secrets Manager**.
3. Nhấn **Store a new secret**.
4. Chọn **Other type of secret** -> **Key/value**:
   - `DB_HOST`: Điền Endpoint của Singapore Aurora Writer (`app2-sg-db.cluster-....rds.amazonaws.com`)
   - `DB_PORT`: `5432`
   - `DB_USER`: `app2_admin`
   - `DB_PASSWORD`: Mật khẩu của `app2_admin`
   - `DB_NAME`: `app2`
5. Nhấn **Next**.
6. **Secret name:** Nhập `app2/database`.
7. Nhấn **Next** -> Bỏ qua Automatic rotation -> Nhấn **Next**.
8. Tại trang Review, cuộn xuống mục **Replication secret in other Regions**:
   - Nhấn **Add Region**.
   - Chọn vùng: **Asia Pacific (Tokyo) ap-northeast-1**.
   - KMS key: Giữ mặc định `aws/secretsmanager`.
9. Nhấn **Store**. Secret được tạo và ngầm đồng bộ sang Tokyo.

### Bước 2: Xác Nhận Secret tại Tokyo
1. Chuyển sang Region **Asia Pacific (Tokyo) ap-northeast-1**.
2. Vào Secrets Manager -> Xác nhận secret `app2/database` xuất hiện với trạng thái `Replicated`.

### Bước 3: Tạo IAM Roles cho External Secrets Operator (IRSA)
1. Vào **IAM** -> **Policies** -> **Create policy**:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "secretsmanager:GetResourcePolicy",
           "secretsmanager:GetSecretValue",
           "secretsmanager:DescribeSecret",
           "secretsmanager:ListSecretVersionIds"
         ],
         "Resource": [
           "arn:aws:secretsmanager:ap-southeast-1:*:secret:app2/database*",
           "arn:aws:secretsmanager:ap-northeast-1:*:secret:app2/database*"
         ]
       }
     ]
   }
   ```
   - Đặt tên: `App2SecretsManagerReadPolicy`.
2. Tạo Role `dr-sg-eso-role` với Web identity OIDC của `dr-sg-eks`, gán policy trên và giới hạn ServiceAccount: `system:serviceaccount:external-secrets:external-secrets-sa`.
3. Tạo Role `dr-tokyo-eso-role` với Web identity OIDC của `dr-tokyo-eks`.

---

## Cài Đặt External Secrets Operator Bằng Helm

### Trên Cụm Singapore:
```bash
kubectl config use-context singapore

helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets

helm install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-secrets-sa \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::<ACCOUNT_ID>:role/dr-sg-eso-role"
```

### Trên Cụm Tokyo:
```bash
kubectl config use-context tokyo

helm install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-secrets-sa \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::<ACCOUNT_ID>:role/dr-tokyo-eso-role"
```

---

## Cấu Hình ClusterSecretStore và ExternalSecret

Áp dụng manifest sau (thay đổi `region` phù hợp: `ap-southeast-1` cho Singapore, `ap-northeast-1` cho Tokyo):

```yaml
# cluster-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-southeast-1 # Đổi thành ap-northeast-1 cho cụm Tokyo
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
---
# external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app2-database-sync
  namespace: app2
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: app2-db-secret
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: app2/database
```

---

## Security considerations & Nguyên Tắc Least Privilege

- **Zero DB Secret cho frontend, backend-1, backend-2:** Chỉ microservice `app2-backend-3` (Order & Payment) mới cần kết nối cơ sở dữ liệu để tạo và truy vấn đơn hàng. Việc không inject biến môi trường `DB_*` vào frontend, backend-1 và backend-2 giúp ngăn chặn việc rò rỉ thông tin kết nối nếu một trong các service này bị khai thác lỗ hổng.
- **Không lưu Secret trong Git:** Repo `aws-multi-region-dr-platform` chỉ lưu định nghĩa `ExternalSecret` mang tính tham chiếu, hoàn toàn không có mật khẩu dạng text.
- **Tự Động Luân Chuyển (Automatic Refresh):** External Secrets Operator định kỳ làm mới secret từ AWS Secrets Manager theo chu kỳ `refreshInterval`.

---

## Expected result

- Secret `app2/database` có mặt tại cả Singapore và Tokyo trên AWS Secrets Manager.
- Trong namespace `app2`, Kubernetes Secret `app2-db-secret` chứa đủ 5 keys: `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`.
- ExternalSecret hiển thị trạng thái `SecretSynced: True`.

---

## Verification

```bash
# Kiểm tra Secret trên cụm Singapore
kubectl --context singapore -n app2 get externalsecret app2-database-sync
kubectl --context singapore -n app2 get secret app2-db-secret -o jsonpath='{.data.DB_NAME}' | base64 --decode
```
*Expected output:* Trả về `app2`.

```bash
# Kiểm tra Secret trên cụm Tokyo
kubectl --context tokyo -n app2 get externalsecret app2-database-sync
kubectl --context tokyo -n app2 get secret app2-db-secret -o jsonpath='{.data.DB_USER}' | base64 --decode
```
*Expected output:* Trả về `app2_admin`.

---

## Troubleshooting

1. **Lỗi: `SecretSyncedError` do sai tên secret:**
   - *Nguyên nhân:* Khóa `extract.key` trong YAML không khớp chính xác với `app2/database`.
   - *Cách sửa:* Kiểm tra tên secret trên AWS Secrets Manager.
2. **Lỗi: IAM Role thiếu quyền đọc:**
   - *Nguyên nhân:* Policy chưa bao gồm cả hai vùng `ap-southeast-1` và `ap-northeast-1`.
   - *Cách sửa:* Xem lại chính sách `App2SecretsManagerReadPolicy` đảm bảo Resource ARN bao phủ cả hai vùng.
3. **Lỗi: Backend-3 báo thiếu biến môi trường DB:**
   - *Nguyên nhân:* Deployment áp dụng trước khi Secret được sync.
   - *Cách sửa:* Kiểm tra `kubectl -n app2 get secret app2-db-secret` đã có chưa, sau đó restart deployment bằng `kubectl -n app2 rollout restart deployment/app2-backend-3`.

---

## Cost note

- AWS Secrets Manager: ~$0.40/secret/tháng/vùng $\approx$ $0.80/tháng cho cả hai vùng.

---

## Next step

Tiếp tục chuyển sang [LAB 10 - Thiết Lập Argo CD và Quy Trình GitOps Đa Vùng](10-argocd-gitops.md).
