# LAB 00 - Chuẩn Bị Môi Trường và Cấu Hình Xác Thực (Prerequisites & OIDC Setup)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Chuẩn bị đầy đủ các công cụ dòng lệnh (CLI tools) cần thiết trên máy trạm cục bộ.
2. Thiết lập cấu hình tài khoản AWS với đầy đủ quyền quản trị cần thiết.
3. Tạo OpenID Connect (OIDC) Identity Provider trên AWS IAM kết nối với GitHub Actions.
4. Tạo IAM Role `GitHubActions-App2-ECRPush` với chính sách Defense-in-Depth và Least Privilege:
   - Chỉ cho phép nhánh `main` của repository `Kien-devops/app2` assume role.
   - Chỉ cấp quyền push lên kho chứa ECR tại Singapore (`ap-southeast-1`), hoàn toàn không cấp quyền push sang Tokyo vì AWS Cross-Region Replication sẽ tự động sao chép.
   - Không cần lưu trữ Access Key / Secret Key tĩnh trong GitHub Secrets.

---

## Architecture impact

Lab này thiết lập cầu nối xác thực bảo mật giữa nhà cung cấp mã nguồn (GitHub) và hạ tầng đám mây AWS:

```text
[ Developer Máy Trạm ]
  |-- AWS CLI v2
  |-- kubectl & kustomize
  |-- git, jq, bash
       |
       v
[ GitHub: Kien-devops/app2 ]
  |-- Workflow chạy GitHub Runner (chỉ kích hoạt trên branch main)
  |-- OIDC JWT Token
       |
       v (sts:AssumeRoleWithWebIdentity)
[ AWS IAM OIDC Provider ] ---> [ IAM Role: GitHubActions-App2-ECRPush ]
                                      |
                                      v
                      Cấp quyền ECR push DUY NHẤT tại ap-southeast-1
                      (AWS ECR tự động replicate sang Tokyo ap-northeast-1)
```

---

## Resource naming

- IAM OIDC Provider: `token.actions.githubusercontent.com`
- IAM Role Name: `GitHubActions-App2-ECRPush`
- IAM Policy Name: `GitHubActions-ECR-App2-PushPolicy`
- GitHub Secret/Variable: `AWS_GITHUB_ROLE_ARN`

---

## AWS Console Steps

### Bước 1: Tạo IAM OpenID Connect (OIDC) Provider
1. Đăng nhập vào **AWS Management Console**.
2. Trên thanh tìm kiếm ở trên cùng, nhập `IAM` và chọn dịch vụ **IAM**.
3. Ở menu thanh điều hướng bên trái, chọn **Identity providers** (Nhà cung cấp danh tính).
4. Nhấn nút **Add provider** (Thêm nhà cung cấp).
5. Tại mục **Provider type**, tích chọn ô tròn **OpenID Connect**.
6. Tại mục **Provider URL**, nhập chính xác:
   ```text
   https://token.actions.githubusercontent.com
   ```
7. Nhấn nút **Get thumbprint** bên cạnh để AWS tự động xác thực và tải chứng chỉ SSL thumbprint của GitHub.
8. Tại mục **Audience**, nhập chính xác:
   ```text
   sts.amazonaws.com
   ```
9. Nhấn nút **Add provider** ở góc dưới cùng bên phải.
10. Màn hình hiển thị thông báo màu xanh `Provider successfully added`.

### Bước 2: Tạo IAM Policy cho phép Push ECR Singapore (Least Privilege)
1. Tại menu bên trái của IAM Console, chọn **Policies** -> Nhấn nút **Create policy**.
2. Chuyển sang tab **JSON** ở góc phải bộ soạn thảo chính sách.
3. Xóa nội dung mặc định và dán đoạn JSON sau (thay `<ACCOUNT_ID>` bằng Account ID 12 chữ số của bạn):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "ECRAuthToken",
         "Effect": "Allow",
         "Action": [
           "ecr:GetAuthorizationToken"
         ],
         "Resource": "*"
       },
       {
         "Sid": "ECRPushApp2SingaporeOnly",
         "Effect": "Allow",
         "Action": [
           "ecr:BatchCheckLayerAvailability",
           "ecr:GetDownloadUrlForLayer",
           "ecr:BatchGetImage",
           "ecr:PutImage",
           "ecr:InitiateLayerUpload",
           "ecr:UploadLayerPart",
           "ecr:CompleteLayerUpload"
         ],
         "Resource": "arn:aws:ecr:ap-southeast-1:<ACCOUNT_ID>:repository/app2-*"
       }
     ]
   }
   ```
   > **Lưu ý bảo mật:** Policy trên **chỉ cấp quyền cho region `ap-southeast-1`**. CI không cần và không được cấp quyền push sang Tokyo (`ap-northeast-1`). Hạ tầng sao chép của AWS ECR sẽ tự động đảm nhiệm việc này.
4. Nhấn nút **Next**.
5. Đặt tên Policy: `GitHubActions-ECR-App2-PushPolicy`.
6. Nhấn nút **Create policy**.

### Bước 3: Tạo IAM Role với Trust Policy Chặt Chẽ (Defense in Depth)
1. Tại menu bên trái của IAM Console, chọn **Roles** -> Nhấn **Create role**.
2. Chọn **Web identity**:
   - Identity provider: `token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`
   - Nhấn **Next**.
3. Tại trang Add permissions:
   - Gắn policy: `GitHubActions-ECR-App2-PushPolicy`.
   - Nhấn **Next**.
4. Name, review, and create:
   - Role name: `GitHubActions-App2-ECRPush`.
   - Nhấn **Create role**.
5. **Cấu hình Trust Policy an toàn tuyệt đối:**
   - Trong danh sách Roles, bấm vào `GitHubActions-App2-ECRPush`.
   - Chọn tab **Trust relationships** -> Nhấn **Edit trust policy**.
   - Dán JSON sau:
     ```json
     {
       "Version": "2012-10-17",
       "Statement": [
         {
           "Effect": "Allow",
           "Principal": {
             "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
           },
           "Action": "sts:AssumeRoleWithWebIdentity",
           "Condition": {
             "StringEquals": {
               "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
               "token.actions.githubusercontent.com:sub": "repo:Kien-devops/app2:ref:refs/heads/main"
             }
           }
         }
       ]
     }
     ```
     > **Nguyên tắc Defense-in-Depth:**
     > - Không sử dụng wildcard `repo:Kien-devops/app2:*` vì sẽ vô tình cho phép các Pull Request hoặc feature branch chưa kiểm duyệt có quyền push image vào ECR.
     > - Chỉ chấp nhận chính xác `repo:Kien-devops/app2:ref:refs/heads/main`. Sự kết hợp giữa điều kiện kích hoạt workflow trong GitHub Actions và điều kiện IAM Trust Policy tạo nên 2 lớp phòng thủ độc lập.
   - Nhấn **Update policy**.
   - Sao chép lại ARN của Role (`arn:aws:iam::<ACCOUNT_ID>:role/GitHubActions-App2-ECRPush`).

### Bước 4: Cấu hình biến môi trường trên GitHub Repository
1. Mở repository `https://github.com/Kien-devops/app2`.
2. Settings -> **Secrets and variables** -> **Actions** -> Tab **Variables**.
3. Tạo biến mới:
   - Name: `AWS_GITHUB_ROLE_ARN`
   - Value: `arn:aws:iam::<ACCOUNT_ID>:role/GitHubActions-App2-ECRPush`
4. Tạo biến:
   - Name: `AWS_REGION`
   - Value: `ap-southeast-1`

---

## Configuration

Các phiên bản công cụ khuyến nghị trên máy trạm cục bộ:
- **AWS CLI:** `v2.15.0+`
- **kubectl:** `v1.28.0+`
- **kustomize:** `v5.0.0+` (hoặc sử dụng `kubectl kustomize`)
- **git:** `v2.40.0+`
- **jq:** `v1.6+`
- **bash:** Hỗ trợ chạy các test scripts và benchmark.

---

## Security considerations

- **Phạm vi quyền ECR tối thiểu:** Chỉ cấp quyền push cho `ap-southeast-1` với prefix `app2-*`.
- **Ràng buộc nhánh `main`:** Ngăn chặn hoàn toàn việc build image từ fork hoặc pull request lạ.
- **Không Access Key dài hạn:** Khử bỏ hoàn toàn nguy cơ lộ credential trong log hoặc trên máy trạm.

---

## Expected result

- OIDC Provider `token.actions.githubusercontent.com` hoạt động.
- Role `GitHubActions-App2-ECRPush` chỉ tin cậy nhánh `main` của repo `app2`.
- GitHub variable `AWS_GITHUB_ROLE_ARN` sẵn sàng.

---

## Verification

### Kiểm tra bằng CLI trên máy trạm
```bash
aws sts get-caller-identity
```
*Expected output:* Trả về JSON chứa Account ID 12 chữ số hợp lệ.

Kiểm tra Trust Policy của Role:
```bash
aws iam get-role --role-name GitHubActions-App2-ECRPush \
  --query "Role.AssumeRolePolicyDocument.Statement[0].Condition" --output json
```
*Expected output:*
```json
{
  "StringEquals": {
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
    "token.actions.githubusercontent.com:sub": "repo:Kien-devops/app2:ref:refs/heads/main"
  }
}
```

---

## Troubleshooting

1. **Lỗi: `Could not assume role with OIDC: Access Denied`:**
   - *Nguyên nhân:* GitHub Action đang chạy trên một branch không phải `main` (ví dụ `feature/login`), hoặc `sub` trong Trust Policy bị sai chính tả.
   - *Cách sửa:* Kiểm tra log của bước `configure-aws-credentials`, đối chiếu `sub` trả về từ GitHub OIDC.
2. **Lỗi: `User is not authorized to perform: ecr:PutImage on resource ap-northeast-1`:**
   - *Nguyên nhân:* GitHub Actions workflow cố gắng push image sang Tokyo.
   - *Cách sửa:* CI workflow bên `app2` chỉ push về ECR Singapore `ap-southeast-1`. AWS Replication Rule sẽ tự động đưa image sang Tokyo.
3. **Lỗi: `Thumbprint did not match any certificate`:**
   - *Nguyên nhân:* Thumbprint GitHub chưa cập nhật.
   - *Cách sửa:* Nhấn lại `Get thumbprint` trên IAM Console hoặc nhập thumbprint chính thức của GitHub.

---

## Cost note

- AWS IAM, OIDC Provider, Roles, và GitHub Variables hoàn toàn **miễn phí ($0.00)**.

---

## Next step

Tiếp tục chuyển sang [LAB 01 - Tạo Kho Chứa ECR và Cấu Hình Cross-Region Replication](01-ecr-multi-region.md).
