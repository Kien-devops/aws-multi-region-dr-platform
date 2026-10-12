# LAB 00 - Tài khoản, công cụ, IAM và hàng rào kiểm soát chi phí

## 1. Mục tiêu

Chuẩn bị một tài khoản AWS gần như trống và máy trạm Windows cho chuỗi lab hạ tầng, chưa tạo tích hợp CI/CD cho app2.

## 2. Thành phần sẽ xây dựng

- Tài khoản root được bảo vệ và quyền quản trị thông qua IAM Identity Center.
- AWS CLI profile có tên, sử dụng thông tin xác thực ngắn hạn.
- Các công cụ CLI bắt buộc.
- Ngân sách thanh toán và cảnh báo bất thường chi phí.
- Bộ placeholder và quy ước lưu bằng chứng dùng chung cho toàn bộ lab.

GitHub OIDC cho repository app2 được hoãn sang Giai đoạn 2.

## 3. Bối cảnh kiến trúc

```text
Người vận hành -> IAM Identity Center/MFA -> phiên AWS role tạm thời
               -> AWS Console + AWS CLI
               -> hạ tầng Singapore và Tokyo
```

Không dùng tài khoản root hoặc IAM access key dài hạn cho công việc lab hằng ngày.

## 4. Điều kiện tiên quyết

- Quyền chủ sở hữu tài khoản AWS để thực hiện thiết lập ban đầu.
- Email/số điện thoại cho MFA và cảnh báo thanh toán.
- Windows PowerShell có quyền cài đặt công cụ.
- Giới hạn chi phí đã được chủ tài khoản phê duyệt.

## 5. Quy ước đặt tên tài nguyên

| Hạng mục | Giá trị |
|---|---|
| CLI profile | `dr-lab` |
| Region chính | `ap-southeast-1` |
| Region DR | `ap-northeast-1` |
| Ngân sách | `dr-platform-monthly-budget` |
| Tag dùng chung | `Project=aws-multi-region-dr-platform` |
| Tag môi trường | `Environment=lab` |
| Tag chủ sở hữu | `<OWNER>` |

Các placeholder dùng xuyên suốt:

```text
<ACCOUNT_ID> <OWNER> <ADMIN_CIDR> <EMAIL>
<AWS_PROFILE> <KMS_KEY_ARN> <SNS_TOPIC_ARN>
```

## 6. Các bước triển khai

### 6.1 Bảo vệ tài khoản root

Đăng nhập AWS Console bằng root:

```text
Account menu -> Security credentials
-> Assign MFA device
-> Choose passkey or hardware/virtual MFA
-> Complete registration
```

Không tạo access key cho root. Lưu thông tin khôi phục ở nơi an toàn. Bật thông tin liên hệ thay thế cho thanh toán và bảo mật.

### 6.2 Cấu hình IAM Identity Center

```text
AWS Console -> IAM Identity Center -> Enable
-> Users -> Add user -> create named administrator user
-> AWS accounts -> select account -> Assign users or groups
-> Permission set: AdministratorAccess
```

**ĐƠN GIẢN HÓA CHO LAB:** Chấp nhận quyền quản trị cho người vận hành lab vì chuỗi lab tạo nhiều loại dịch vụ. Phương án production: tách role cho mạng, EKS, cơ sở dữ liệu, bảo mật và vận hành DR; áp dụng permission boundary và quy trình phê duyệt thay đổi.

Bật MFA cho nguồn danh tính. Ngừng sử dụng root sau bước này.

### 6.3 Cài đặt công cụ trên máy trạm

Cài phiên bản ổn định hiện hành từ nguồn chính thức:

- AWS CLI v2
- `kubectl`
- Helm 3
- Git
- Docker Desktop, chỉ cần cho bài kiểm tra ECR replication tùy chọn
- `jq` và môi trường Bash, chỉ cần khi chạy các shell script được cung cấp ở những lab sau

Kiểm tra:

```powershell
aws --version
kubectl version --client
helm version
git --version
docker version
```

### 6.4 Cấu hình AWS CLI SSO

```powershell
aws configure sso --profile dr-lab
aws sso login --profile dr-lab
$env:AWS_PROFILE='dr-lab'
aws sts get-caller-identity
```

Không lưu access key trong repository, shell profile hoặc ảnh chụp màn hình.

### 6.5 Bật Region và thiết lập giá trị mặc định

Xác nhận Singapore và Tokyo đã được bật cho tài khoản. Các lệnh CLI trong lab phải chỉ rõ `--region`; không phụ thuộc vào một Region mặc định duy nhất khi làm việc đa Region.

### 6.6 Tạo cơ chế kiểm soát chi phí

Trên AWS Console:

```text
Billing and Cost Management -> Budgets -> Create budget
Budget type: Cost budget
Name: dr-platform-monthly-budget
Period: Monthly
Amount: <APPROVED_MONTHLY_LIMIT>
Alerts: 50%, 80%, 100% actual; 100% forecasted
Email: <EMAIL>
```

Sau đó bật Cost Anomaly Detection với AWS services monitor và đăng ký nhận thông báo qua email/SNS. Cảnh báo không tự giới hạn mức chi tiêu.

### 6.7 Kiểm tra service quota

Kiểm tra quota cho VPC, Elastic IP, NAT Gateway, EKS, On-Demand vCPU, ALB, RDS và FSx for ONTAP SSD capacity/throughput ở cả hai Region. Yêu cầu tăng quota trước khi bắt đầu lab nếu cần.

### 6.8 Tạo thư mục lưu bằng chứng cục bộ

Tạo thư mục không chứa secret và không được Git theo dõi, ví dụ `evidence/<date>-phase1/`. Lưu lệnh và ảnh chụp màn hình, tuyệt đối không lưu giá trị secret.

## 7. Xác minh

```powershell
$env:AWS_PROFILE='dr-lab'
aws sts get-caller-identity
aws ec2 describe-regions --all-regions --query "Regions[?RegionName=='ap-southeast-1' || RegionName=='ap-northeast-1'].[RegionName,OptInStatus]" --output table
aws eks describe-cluster-versions --region ap-southeast-1 --query "clusterVersions[?status=='STANDARD_SUPPORT'].[clusterVersion,defaultVersion,endOfStandardSupportDate]" --output table
```

Xác nhận ngân sách và đăng ký Cost Anomaly Detection trong Billing Console.

## 8. Kết quả mong đợi

- Root được bảo vệ bằng MFA và không có root access key.
- Người vận hành dùng thông tin xác thực SSO ngắn hạn.
- Các công cụ bắt buộc phản hồi bình thường.
- Cả hai Region khả dụng.
- Cảnh báo chi phí đã được cấu hình.

## 9. Xử lý sự cố

- `ExpiredToken`: chạy lại `aws sso login --profile dr-lab`.
- Sai tài khoản: dừng ngay; kiểm tra `aws sts get-caller-identity`.
- Không có `describe-cluster-versions`: cập nhật AWS CLI v2 và dùng trang vòng đời phiên bản trong EKS Console.
- Không truy cập được menu Billing: bật IAM access to billing và cấp quyền thanh toán phù hợp.

## 10. Lưu ý bảo mật

- Dùng MFA, phiên role tạm thời và đặc quyền tối thiểu cho các service role.
- Bật CloudTrail; production nên dùng organization trail, S3 bucket được bảo vệ, xác thực log và cảnh báo cho các thay đổi nhạy cảm trên IAM/mạng/RDS/GA.
- Không commit credential, kubeconfig, mật khẩu DB hoặc file kiểu `server.txt`.
- Ở lab sau, giới hạn CIDR truy cập EKS public API thành `<ADMIN_CIDR>`.

## 11. Lưu ý chi phí

IAM, IAM Identity Center và thiết lập CLI cơ bản thường miễn phí. Chi phí đáng kể gồm NAT, EKS, Aurora, ALB/GA, EC2 và hai FSx ONTAP file systems; storage DR có thể vượt xa chi phí app demo.

## 12. Dọn dẹp / Quay lui

Không gỡ MFA hoặc đường khôi phục quản trị. Chỉ xóa profile thử nghiệm và subscription không còn dùng. Giữ cảnh báo chi phí trong suốt dự án.

## 13. Bằng chứng cần thu thập

- Caller identity đã che thông tin nhạy cảm.
- Phiên bản công cụ.
- Danh sách phiên bản EKS còn Standard Support kèm ngày kiểm tra.
- Ngưỡng ngân sách và xác nhận nhận thông báo.
- Ảnh chụp service quota ở cả hai Region.

## 14. Lab tiếp theo

Tiếp tục với [LAB 01 - ECR đa Region](01-ecr-multi-region.md).
