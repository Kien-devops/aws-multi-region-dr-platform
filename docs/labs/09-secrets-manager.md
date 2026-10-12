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

### 6.2 Tạo Primary Secret tại Singapore

1. Mở AWS Management Console, chuyển Region sang **Asia Pacific (Singapore) `ap-southeast-1`**.
2. Trên thanh tìm kiếm, gõ `Secrets Manager` và chọn dịch vụ **AWS Secrets Manager**.
3. Trong menu bên trái, chọn **Secrets** -> nhấp nút **Store a new secret** màu cam ở góc trên bên phải.
4. **Bước 1: Choose secret type**:
   - **Secret type**: Chọn **Other type of secret**.
   - Tại mục **Key/value pairs**, chuyển sang tab **Key/value** và nhấp **Add row** để nhập đủ 5 cặp khóa:
     - `DB_HOST`: Dán Global Writer Endpoint (hoặc Regional Cluster Endpoint của Singapore từ LAB 08).
     - `DB_PORT`: `5432`
     - `DB_USER`: `app2_runtime`
     - `DB_PASSWORD`: Mật khẩu an toàn đã đặt cho user `app2_runtime` ở bước 6.1.
     - `DB_NAME`: `app2`
   - **Encryption key**: Chọn `aws/secretsmanager` (Mặc định cho lab) hoặc KMS CMK đã chuẩn bị.
   - Nhấp nút **Next** ở cuối trang.
5. **Bước 2: Configure secret**:
   - **Secret name**: Nhập chính xác `/app2/database`.
   - **Description**: Nhập `Database credentials for app2 replicated to Tokyo`.
   - **Resource permissions**: Bỏ qua.
   - Nhấp nút **Next**.
6. **Bước 3: Configure rotation**:
   - **Automatic rotation**: Giữ công tắc ở chế độ **Disabled** (Tắt, do chưa cấu hình Lambda rotation chuyên biệt cho Aurora Global Database).
   - Nhấp nút **Next**.
7. **Bước 4: Review**:
   - Rà soát thông tin -> Nhấp nút **Store** màu cam ở cuối trang.
   - Secret `/app2/database` sẽ xuất hiện trong danh sách bí mật của Singapore.

### 6.3 Replicate Secret sang Tokyo

1. Tại danh sách Secrets ở Singapore, nhấp vào tên secret `/app2/database` để mở trang chi tiết.
2. Cuộn xuống mục **Replication** (hoặc nhấp vào menu **Actions** ở góc trên bên phải -> chọn **Replicate secret to other Regions**).
3. Nhấp vào nút **Replicate secret** màu cam.
4. Tại giao diện cấu hình nhân bản:
   - **Region**: Chọn **Asia Pacific (Tokyo) ap-northeast-1**.
   - **KMS key**: Chọn `(default) aws/secretsmanager` tại Tokyo (hoặc Customer Managed Key tại Tokyo).
5. Nhấp nút **Replicate secret**.
6. Trạng thái trong bảng Replication lúc đầu sẽ là *In progress*. Chờ 1-2 phút và bấm làm mới (Refresh) cho đến khi **Status** chuyển sang **InSync**.
7. Kiểm tra đối chiếu: Mở menu Region ở góc trên bên phải, chuyển sang **Tokyo (`ap-northeast-1`)** -> truy cập Secrets Manager -> bạn sẽ thấy secret `/app2/database` đã xuất hiện với nhãn *Replica* và cùng các key/value như ở Singapore.

### 6.4 Tạo IAM Policy cho phép đọc Secret (Least Privilege)

Chính sách này chỉ cho phép lấy giá trị secret của ứng dụng tại cả 2 Region, không cấp quyền sửa/xóa:

1. Chuyển đến dịch vụ **IAM** -> trong menu bên trái, chọn **Policies** -> nhấp **Create policy**.
2. Chuyển sang tab **JSON** trong Policy editor, dán nội dung sau (thay `<ACCOUNT_ID>` bằng Account ID thật của bạn):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowReadApp2DatabaseSecret",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:ap-southeast-1:<ACCOUNT_ID>:secret:/app2/database-*",
        "arn:aws:secretsmanager:ap-northeast-1:<ACCOUNT_ID>:secret:/app2/database-*"
      ]
    }
  ]
}
```

3. Nhấp nút **Next** ở cuối trang.
4. **Policy name**: Nhập `App2DatabaseSecretReadPolicy`.
5. **Description**: Nhập `Read-only access to /app2/database secret in SG and Tokyo for External Secrets Operator`.
6. Nhấp nút **Create policy** màu cam.

### 6.5 Tạo IAM IRSA Role cho External Secrets Operator (ESO)

#### Bước 1: Tạo Role cho Singapore (`dr-sg-eso-role`)
1. Trong menu bên trái của IAM, chọn **Roles** -> nhấp **Create role**.
2. **Select trusted entity**:
   - Chọn **Web identity**.
   - **Identity provider**: Chọn OIDC Provider của cluster `dr-sg-eks`.
   - **Audience**: Chọn `sts.amazonaws.com` -> nhấp **Next**.
3. **Add permissions**:
   - Tìm và tích chọn policy `App2DatabaseSecretReadPolicy` vừa tạo -> nhấp **Next**.
4. **Name, review, and create**:
   - **Role name**: Nhập `dr-sg-eso-role` -> nhấp **Create role**.
5. *Cập nhật Trust Policy chính xác:*
   - Nhấp vào role `dr-sg-eso-role` -> chuyển sang tab **Trust relationships** -> nhấp **Edit trust policy**.
   - Đảm bảo điều kiện `StringEquals` trỏ chính xác vào namespace `external-secrets` và serviceaccount `external-secrets`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.ap-southeast-1.amazonaws.com/id/<SG_OIDC_ID>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.ap-southeast-1.amazonaws.com/id/<SG_OIDC_ID>:aud": "sts.amazonaws.com",
          "oidc.eks.ap-southeast-1.amazonaws.com/id/<SG_OIDC_ID>:sub": "system:serviceaccount:external-secrets:external-secrets"
        }
      }
    }
  ]
}
```

   - Nhấp **Update policy**.

#### Bước 2: Tạo Role cho Tokyo (`dr-tokyo-eso-role`)
1. Lặp lại tương tự: Chọn **Create role** -> **Web identity** -> Chọn OIDC Provider của `dr-tokyo-eks` -> Audience: `sts.amazonaws.com`.
2. Gắn policy: `App2DatabaseSecretReadPolicy`.
3. Đặt Role name: `dr-tokyo-eso-role`.
4. Cập nhật Trust relationship trỏ đúng vào `<TOKYO_OIDC_ID>` và ServiceAccount `system:serviceaccount:external-secrets:external-secrets`.

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

Gỡ ESO khi quay lui. Gỡ replica Region trước khi lên lịch xóa primary secret. Dùng recovery window; tránh force deletion. Dọn dẹp đầy đủ ở LAB 27.

## 13. Bằng chứng cần thu thập

Metadata/trạng thái replication của secret, KMS key ID, sự tồn tại của trường global endpoint nhưng không lộ giá trị, phiên bản ESO chart, pod readiness, annotation ServiceAccount và xác nhận không có app2 ExternalSecret.

## 14. Lab tiếp theo

Tiếp tục với [LAB 10 - Điều kiện tiên quyết cho nền tảng Argo CD](10-argocd-gitops.md).
