# LAB 09 - Secrets Manager đa Region và điều kiện tiên quyết cho ESO

## 1. Mục tiêu

Tạo secret kết nối cơ sở dữ liệu không phụ thuộc một Region, replicate sang Tokyo và cài điều kiện tiên quyết cho External Secrets Operator mà chưa tạo `ExternalSecret` của app2.

## 2. Thành phần sẽ xây dựng

- Primary secret `/app2/database` tại Singapore.
- Replica secret tại Tokyo.
- User runtime riêng cho cơ sở dữ liệu được tạo an toàn, tùy chọn.
- ESO và IRSA role riêng theo cluster trên cả hai cluster.
- Chưa có Kubernetes Secret, `ExternalSecret` hoặc application Deployment của app2.

## 3. Bối cảnh kiến trúc

```text
/app2/database primary (Singapore)
        -> Secrets Manager replication -> replica (Tokyo)
        -> future ESO ExternalSecret in Phase 2
```

Dùng Aurora **Global Database writer endpoint** làm `DB_HOST`. Vì endpoint này đi theo primary hiện tại, secret được replicate không giữ hostname cũ chỉ thuộc Singapore sau switchover/failover có quản lý.

## 4. Điều kiện tiên quyết

- Hoàn thành LAB 08.
- Đã ghi lại global writer endpoint.
- Phương án username/password cơ sở dữ liệu đã được phê duyệt.
- EKS OIDC provider từ LAB 07 đã tồn tại.
- Phiên bản ESO chart hiện hành đã được rà từ repository chính thức.

## 5. Quy ước đặt tên tài nguyên

| Tài nguyên | Giá trị |
|---|---|
| Secret | `/app2/database` |
| Runtime DB user | `app2_runtime` |
| Database | `app2` |
| IAM policy | `App2DatabaseSecretReadPolicy` |
| SG ESO role | `dr-sg-eso-role` |
| Tokyo ESO role | `dr-tokyo-eso-role` |
| Namespace | `external-secrets` |
| ServiceAccount | `external-secrets` |

Các key JSON của secret:

```json
{
  "DB_HOST": "<GLOBAL_WRITER_ENDPOINT>",
  "DB_PORT": "5432",
  "DB_USER": "app2_runtime",
  "DB_PASSWORD": "<GENERATED_SECRET>",
  "DB_NAME": "app2"
}
```

## 6. Các bước triển khai

### 6.1 Tạo user runtime riêng cho cơ sở dữ liệu

Không dùng Aurora master user từ pod ứng dụng trong production. Từ đường client PostgreSQL private đã được phê duyệt, kết nối tương tác bằng master secret do RDS quản lý. Sau đó:

```sql
CREATE ROLE app2_runtime LOGIN;
\password app2_runtime
GRANT CONNECT ON DATABASE app2 TO app2_runtime;
```

Nhập mật khẩu đã tạo theo cách tương tác để không xuất hiện trong shell history hoặc Git. Quyền trên schema thuộc giai đoạn migration ứng dụng; bước này chỉ thiết lập khả năng kết nối.

Nếu chưa có đường client private, tạo secret bằng mật khẩu sinh an toàn nhưng đánh dấu `Database user creation: pending`; LAB 11 không được tuyên bố xác thực cơ sở dữ liệu đã sẵn sàng cho tới khi hoàn tất việc này.

### 6.2 Tạo primary secret

AWS Console tại Singapore:

```text
Secrets Manager -> Store a new secret
Secret type: Other type of secret
Key/value: DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME
Encryption key: aws/secretsmanager for lab or approved CMK
Secret name: /app2/database
Rotation: disabled until a compatible rotation design exists
-> Store
```

Dán mật khẩu từ password manager an toàn, không lấy từ file đã commit.

### 6.3 Replicate sang Tokyo

```text
Open /app2/database -> Replicate secret to other Regions
Destination: ap-northeast-1
Encryption key: Tokyo regional key
-> Start replication
```

Chờ trạng thái `InSync`. Dữ liệu và metadata của secret được replicate từ primary. Việc rotation tại primary sau này sẽ truyền giá trị mới tới replica.

### 6.4 Tạo read policy đặc quyền tối thiểu

Tạo `App2DatabaseSecretReadPolicy` với `secretsmanager:GetSecretValue` và `secretsmanager:DescribeSecret`, giới hạn trong:

```text
arn:aws:secretsmanager:ap-southeast-1:<ACCOUNT_ID>:secret:/app2/database-*
arn:aws:secretsmanager:ap-northeast-1:<ACCOUNT_ID>:secret:/app2/database-*
```

Nếu dùng customer-managed KMS key, chỉ thêm quyền `kms:Decrypt` cần thiết và giới hạn bằng encryption context/key policy.

### 6.5 Tạo IRSA role cho ESO

Tạo một Web identity role cho mỗi cluster. Điều kiện trust:

```text
aud = sts.amazonaws.com
sub = system:serviceaccount:external-secrets:external-secrets
```

Gắn read policy. Tên role: `dr-sg-eso-role`, `dr-tokyo-eso-role`.

### 6.6 Cài đặt ESO

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets
helm search repo external-secrets/external-secrets --versions | head
```

```bash
helm upgrade --install external-secrets external-secrets/external-secrets \
  --kube-context singapore -n external-secrets --create-namespace \
  --version <ESO_CHART_VERSION> \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-secrets \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::<ACCOUNT_ID>:role/dr-sg-eso-role \
  --wait --timeout 10m

helm upgrade --install external-secrets external-secrets/external-secrets \
  --kube-context tokyo -n external-secrets --create-namespace \
  --version <ESO_CHART_VERSION> \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-secrets \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::<ACCOUNT_ID>:role/dr-tokyo-eso-role \
  --wait --timeout 10m
```

Không tạo `ClusterSecretStore`, `SecretStore` hoặc `ExternalSecret` của app2 trong Giai đoạn 1. Các object đó thuộc cấu hình triển khai ứng dụng.

## 7. Xác minh

```bash
aws secretsmanager describe-secret --region ap-southeast-1 --secret-id /app2/database \
  --query '{ARN:ARN,ReplicationStatus:ReplicationStatus,KmsKeyId:KmsKeyId}'
aws secretsmanager describe-secret --region ap-northeast-1 --secret-id /app2/database \
  --query '{ARN:ARN,PrimaryRegion:PrimaryRegion,KmsKeyId:KmsKeyId}'
kubectl --context singapore -n external-secrets get pods,serviceaccount
kubectl --context tokyo -n external-secrets get pods,serviceaccount
kubectl --context singapore get externalsecrets.external-secrets.io -A
kubectl --context tokyo get externalsecrets.external-secrets.io -A
```

Hai lệnh cuối không được hiển thị ExternalSecret của app2.

## 8. Kết quả mong đợi

Secret replica ở trạng thái `InSync`, global writer endpoint đã được lưu, ESO khỏe mạnh trên hai cluster và chưa có Kubernetes Secret của app2.

## 9. Xử lý sự cố

- Replica `Failed`: quyền Region/KMS hoặc tên secret bị xung đột tại đích.
- ESO `WebIdentityErr`: subject/audience trong OIDC trust hoặc annotation không khớp.
- Secret vẫn trỏ tới regional endpoint: cập nhật primary thành global writer endpoint và xác nhận replication.
- Runtime login lỗi: database user/quyền/mật khẩu chưa đồng bộ với secret; không tuyên bố đã sẵn sàng.

## 10. Lưu ý bảo mật

- Không bao giờ xuất giá trị secret trong bước xác minh/bằng chứng.
- Dùng runtime user riêng, TLS, quyền giới hạn và kế hoạch rotation.
- Không thể chỉnh sửa độc lập replicated secret cho tới khi promote thành standalone.
- Thông thường không cần promote trong DR nếu Aurora global writer endpoint và managed secret replication vẫn hoạt động; phải ghi rõ quy trình ngoại lệ.

## 11. Lưu ý chi phí

Mỗi primary/replica secret và API call đều tính phí. ESO dùng node hiện có. Customer-managed KMS phát sinh phí key/request.

## 12. Dọn dẹp / Quay lui

Gỡ ESO khi quay lui. Gỡ replica Region trước khi lên lịch xóa primary secret. Dùng recovery window; tránh force deletion. Dọn dẹp đầy đủ ở LAB 18.

## 13. Bằng chứng cần thu thập

Metadata/trạng thái replication của secret, KMS key ID, sự tồn tại của trường global endpoint nhưng không lộ giá trị, phiên bản ESO chart, pod readiness, annotation ServiceAccount và xác nhận không có app2 ExternalSecret.

## 14. Lab tiếp theo

Tiếp tục với [LAB 10 - Điều kiện tiên quyết cho nền tảng Argo CD](10-argocd-gitops.md).
