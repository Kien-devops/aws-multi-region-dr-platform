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

1. Đăng nhập vào [AWS Management Console](https://console.aws.amazon.com/) bằng địa chỉ email của tài khoản Root.
2. Tại góc trên cùng bên phải, nhấp vào tên tài khoản (Account menu) -> chọn **Security credentials** (hoặc truy cập trực tiếp qua dịch vụ IAM -> chọn mục **Dashboard** -> phần **Root user credentials**).
3. Tại mục **Multi-factor authentication (MFA)**:
   - Nhấp vào nút **Assign MFA device** (hoặc **Add MFA**).
   - **Device name**: Nhập tên gợi nhớ (ví dụ: `root-admin-authenticator` hoặc `root-yubikey`).
   - **MFA device**:
     - Chọn **Authenticator app** (khuyến nghị dùng Microsoft Authenticator, Google Authenticator hoặc 1Password) hoặc **FIDO2 security key** (YubiKey).
   - Nhấp nút **Next** màu cam.
   - Quét mã QR bằng ứng dụng Authenticator, sau đó nhập 2 mã MFA liên tiếp vào ô **MFA code 1** và **MFA code 2**.
   - Nhấp nút **Add MFA**.
4. Kiểm tra mục **Access keys**: Đảm bảo không có Access Key nào tồn tại cho tài khoản Root. Nếu có, nhấp **Actions** -> **Delete**.
5. Kéo xuống mục **Alternate contacts** (hoặc truy cập **Billing and Cost Management** -> **Account settings**):
   - Nhấp nút **Edit** tại các mục **Billing**, **Operations**, **Security**.
   - Nhập thông tin Email, Số điện thoại và Tên người liên hệ dự phòng -> nhấp **Update**.

### 6.2 Cấu hình IAM Identity Center

1. Tại thanh tìm kiếm trên cùng của AWS Console (Search bar), gõ `IAM Identity Center` và chọn dịch vụ.
2. Đảm bảo bạn đang ở Region quản trị chính (thường khuyến nghị `ap-southeast-1` hoặc Region mặc định của tổ chức). Nếu dịch vụ chưa được kích hoạt:
   - Nhấp nút **Enable** (Kích hoạt).
   - Chọn **Enable with AWS Organizations** (hoặc kích hoạt độc lập tùy cấu hình tài khoản).
3. Tạo nhóm người dùng quản trị (Groups):
   - Ở menu bên trái, nhấp **Groups** -> nhấp nút **Create group** màu cam.
   - **Group name**: Nhập `dr-platform-admins`.
   - **Description**: Nhập `Disaster Recovery Platform Administrators`.
   - Nhấp **Create group**.
4. Tạo tài khoản người dùng có tên (User):
   - Ở menu bên trái, chọn **Users** -> nhấp nút **Add user** màu cam.
   - **Username**: Nhập tên định danh người vận hành (ví dụ: `admin.operator`).
   - **Password generation**: Chọn **Send an email with password setup instructions** hoặc tạo mật khẩu một lần (One-time password).
   - **Email address**: Nhập email nhận thông tin đăng nhập của bạn.
   - **First name / Last name**: Nhập họ tên người vận hành.
   - Nhấp nút **Next**.
   - Tại màn hình **Add user to groups**: Tích chọn nhóm `dr-platform-admins` vừa tạo -> nhấp **Next** -> rà soát lại thông tin và nhấp **Add user**.
5. Tạo Permission Set (Tập quyền):
   - Ở menu bên trái, chọn **Permission sets** -> nhấp nút **Create permission set**.
   - **Permission set type**: Chọn **Predefined permission set**.
   - Chọn **AdministratorAccess** trong danh sách các chính sách có sẵn.
   - Nhấp **Next**.
   - **Session duration**: Chọn `8 hours` hoặc `12 hours` (đủ cho phiên làm việc lab).
   - Nhấp **Next** -> nhấp **Create**.
6. Gán quyền cho tài khoản AWS (AWS Accounts assignment):
   - Ở menu bên trái, chọn **AWS accounts** -> chuyển sang tab **AWS organization** hoặc danh sách tài khoản.
   - Tích chọn tài khoản AWS hiện tại của bạn -> nhấp nút **Assign users or groups** màu cam.
   - Chuyển sang tab **Groups** -> tích chọn nhóm `dr-platform-admins` -> nhấp **Next**.
   - Tích chọn Permission set `AdministratorAccess` vừa tạo -> nhấp **Next**.
   - Nhấp **Submit** để hoàn tất liên kết quyền.
7. Cấu hình bắt buộc MFA cho IAM Identity Center:
   - Ở menu bên trái, chọn **Settings** -> chọn tab **Authentication** (hoặc **MFA**).
   - Nhấp **Configure** -> chọn **Prompt users for MFA: Every time they sign in** hoặc **When context changes**.
   - Tích chọn các loại MFA hợp lệ (Authenticator apps, Security keys).
   - Nhấp **Save changes**.
8. Lấy thông tin URL đăng nhập:
   - Tại trang **Dashboard** của IAM Identity Center, copy đường dẫn **AWS access portal URL** (ví dụ: `https://d-xxxxxx.awsapps.com/start`).
   - Mở cửa sổ trình duyệt ẩn danh, đăng nhập bằng tài khoản người dùng vừa tạo, kích hoạt MFA và đăng xuất hoàn toàn khỏi tài khoản Root.

> [!NOTE]
> **ĐƠN GIẢN HÓA CHO LAB:** Chấp nhận quyền quản trị `AdministratorAccess` cho người vận hành lab vì chuỗi lab thao tác trên nhiều tài nguyên đa vùng (VPC, EKS, RDS, FSx, Route53/Global Accelerator). Với môi trường Production, bắt buộc áp dụng nguyên tắc đặc quyền tối thiểu (Least Privilege), phân tách role mạng, cơ sở dữ liệu, bảo mật và vận hành DR kèm Permission Boundaries.

### 6.3 Cài đặt công cụ trên máy trạm

Cài phiên bản ổn định hiện hành từ nguồn chính thức:

- AWS CLI v2
- `kubectl`
- Helm 3
- Git
- Docker Desktop, chỉ cần cho bài kiểm tra ECR replication tùy chọn
- `jq` và môi trường Bash (hoặc Git Bash / WSL), chỉ cần khi chạy các shell script được cung cấp ở những lab sau

Kiểm tra:

```powershell
aws --version
kubectl version --client
helm version
git --version
docker version
```

### 6.4 Cấu hình AWS CLI SSO

1. Mở PowerShell và chạy lệnh cấu hình SSO tương tác:

```powershell
aws configure sso --profile dr-lab
```

2. Điền các tham số khi CLI yêu cầu:
   - **SSO session name**: `dr-sso`
   - **SSO start URL**: Dán `AWS access portal URL` từ bước 6.2 (ví dụ: `https://d-xxxxxx.awsapps.com/start`)
   - **SSO region**: Region nơi bạn bật IAM Identity Center (ví dụ: `ap-southeast-1` hoặc `us-east-1`)
   - **SSO registration scopes**: Giữ mặc định (`sso:account:access`)
3. Trình duyệt web sẽ tự động bật lên yêu cầu xác thực -> Đăng nhập tài khoản Identity Center của bạn -> Nhập mã MFA -> Nhấp nút **Allow access**.
4. Quay lại cửa sổ PowerShell:
   - Chọn tài khoản AWS của bạn trong danh sách.
   - Chọn Role `AdministratorAccess`.
   - **CLI default client Region**: Nhập `ap-southeast-1`.
   - **CLI default output format**: Nhập `json`.
   - **CLI profile name**: Đặt là `dr-lab`.
5. Đăng nhập và kiểm tra định danh:

```powershell
aws sso login --profile dr-lab
$env:AWS_PROFILE='dr-lab'
aws sts get-caller-identity
```

Tuyệt đối không sử dụng hardcoded IAM access key lưu trong máy trạm hay commit lên Git.

### 6.5 Bật Region và thiết lập giá trị mặc định

1. Mở AWS Console -> tại góc trên bên phải, bấm vào tên Region hiện tại -> kiểm tra xem **Asia Pacific (Singapore) `ap-southeast-1`** và **Asia Pacific (Tokyo) `ap-northeast-1`** có hiển thị bình thường không.
2. Lưu ý: Hai Region này là các Region mặc định được kích hoạt sẵn của AWS (Default Enabled). Nếu sử dụng các Region mở rộng mới (Opt-in Regions), cần vào **Account settings** -> **AWS Regions** để Enable.
3. Khi thực hiện các lệnh CLI, luôn chỉ định tham số `--region ap-southeast-1` hoặc `--region ap-northeast-1` cụ thể, không ỷ lại vào cấu hình profile mặc định.

### 6.6 Tạo cơ chế kiểm soát chi phí (AWS Budgets & Anomaly Detection)

#### Thiết lập Ngân sách cảnh báo (AWS Budgets)
1. Trên thanh tìm kiếm AWS Console, gõ `Billing and Cost Management` và truy cập dịch vụ.
2. Trong menu bên trái, nhấp vào mục **Budgets** (hoặc **Cost budgets**).
3. Nhấp vào nút **Create budget** màu cam ở góc trên bên phải.
4. Tại bước **Choose budget type**:
   - Chọn **Cost budget - Recommended** (Theo dõi chi phí tổng thể theo USD).
   - Nhấp nút **Next** ở cuối trang.
5. Tại bước **Set budget amount**:
   - **Budget name**: Nhập `dr-platform-monthly-budget`.
   - **Period**: Chọn `Monthly` (Hằng tháng).
   - **Budget effective date**: Chọn `Recurring budget` (Lặp lại mỗi tháng).
   - **Start month**: Chọn tháng hiện tại.
   - **Budgeting method**: Chọn `Fixed`.
   - **Enter your budgeted amount ($)**: Nhập mức ngân sách tối đa được phê duyệt (ví dụ: `200` hoặc `300` USD).
   - **Budget scope**: Chọn `All AWS services` (Mặc định).
   - Nhấp nút **Next**.
6. Tại bước **Set alert thresholds** (Cấu hình cảnh báo):
   - *Cảnh báo 1 (50% thực tế):*
     - Nhấp **Add an alert threshold**.
     - **Threshold**: Nhập `50` (% of budgeted amount).
     - **Trigger**: Chọn `Actual` (Chi phí thực tế đã phát sinh).
     - **Email recipients**: Nhập địa chỉ `<EMAIL>` của bạn.
   - *Cảnh báo 2 (80% thực tế):*
     - Nhấp **Add an alert threshold**.
     - **Threshold**: Nhập `80` (%), Trigger: `Actual`, Email: `<EMAIL>`.
   - *Cảnh báo 3 (100% thực tế):*
     - Nhấp **Add an alert threshold**.
     - **Threshold**: Nhập `100` (%), Trigger: `Actual`, Email: `<EMAIL>`.
   - *Cảnh báo 4 (100% dự báo):*
     - Nhấp **Add an alert threshold**.
     - **Threshold**: Nhập `100` (%), Trigger: `Forecasted` (Dự báo chi phí cuối tháng sẽ chạm mốc), Email: `<EMAIL>`.
   - Nhấp nút **Next**.
7. Bỏ qua bước đính kèm Action tự động (nhấp **Next**) -> Rà soát lại toàn bộ thiết lập -> Nhấp nút **Create budget** màu cam.

#### Kích hoạt Cost Anomaly Detection
1. Trong menu bên trái của Billing Console, chọn **Cost Anomaly Detection**.
2. Nhấp nút **Get started** (hoặc **Create monitor**).
3. **Monitor type**: Chọn **AWS services** (Theo dõi chi phí bất thường của tất cả các dịch vụ độc lập).
4. **Monitor name**: Nhập `all-services-anomaly-monitor`.
5. Nhấp nút **Next**.
6. Cấu hình kênh nhận cảnh báo (Alert subscription):
   - **Subscription name**: Nhập `dr-platform-cost-anomalies`.
   - **Threshold**: Chọn **Absolute amount** (ví dụ: phát hiện chi phí vượt bất thường lớn hơn `20` USD) hoặc chọn **Percentage**.
   - **Alert frequency**: Chọn **Individual alerts** (gửi email ngay khi phát hiện bất thường).
   - **Email recipients**: Nhập `<EMAIL>` của bạn.
7. Nhấp nút **Create monitor**.

### 6.7 Kiểm tra Service Quotas

1. Trên thanh tìm kiếm AWS Console, gõ `Service Quotas` và truy cập dịch vụ.
2. Kiểm tra lần lượt tại Region **Singapore (`ap-southeast-1`)** và **Tokyo (`ap-northeast-1`)**:
   - Chọn **AWS services** ở menu bên trái.
   - Tìm kiếm `Amazon Virtual Private Cloud (Amazon VPC)`:
     - **VPCs per Region**: Tối thiểu 5 (mặc định 5).
     - **Internet gateways per Region**: Tối thiểu 5.
     - **NAT gateways per Availability Zone**: Tối thiểu 5.
     - **Elastic IPs per Region**: Đảm bảo còn ít nhất 2 EIP trống cho mỗi Region.
   - Tìm kiếm `Amazon Elastic Compute Cloud (Amazon EC2)`:
     - **Running On-Demand Standard (A, C, D, I, M, R, T, Z) instances**: Kiểm tra vCPU quota (tối thiểu 32 vCPUs) để đảm bảo khởi tạo đủ EKS Node Groups và EC2 Storage instance.
   - Tìm kiếm `Elastic Load Balancing`:
     - **Application Load Balancers per Region**: Tối thiểu 5.
   - Tìm kiếm `Amazon FSx`:
     - Kiểm tra khả năng tạo hệ thống tệp FSx for NetApp ONTAP (SSD storage capacity & Throughput capacity).
3. Nếu tài khoản của bạn là tài khoản mới và bị giới hạn hạn mức (đặc biệt là EIP hoặc vCPU), nhấp vào quota tương ứng -> nhấp nút **Request quota increase** màu cam để yêu cầu AWS hỗ trợ trước khi bắt đầu bài lab tiếp theo.

### 6.8 Tạo thư mục lưu bằng chứng cục bộ

Tạo một thư mục riêng biệt nằm ngoài Git tracking để lưu lại toàn bộ snapshot cấu hình, log và kết quả kiểm tra xuyên suốt các bài lab:

```powershell
New-Item -ItemType Directory -Force -Path ".\evidence\phase1" | Out-Null
```

> [!CAUTION]
> Tuyệt đối không lưu Access Key, Token, Kubeconfig bí mật hay thông tin đăng nhập trong các file lưu bằng chứng.

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
