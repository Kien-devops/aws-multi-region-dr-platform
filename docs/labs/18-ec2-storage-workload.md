# LAB 18 - EC2 Storage Workload

## 1. Mục tiêu

Tạo hai EC2 Linux private cho `file-service`, quản trị bằng SSM Session Manager, không dùng public IP/SSH.

## 2. Thành phần sẽ xây dựng

- `dr-sg-storage-ec2`, `dr-tokyo-storage-ec2`.
- IAM role/profile có `AmazonSSMManagedInstanceCore` và quyền pull đúng ECR repository.
- Security group chỉ nhận HTTP từ storage ALB SG và NFS tới FSx theo flow đã phê duyệt.

## 3. Bối cảnh kiến trúc

```text
Internet -> ALB -> private EC2 -> /mnt/dr-data -> FSx ONTAP
                    ^
                    SSM, không SSH
```

## 4. Điều kiện tiên quyết

- LAB 00-04 hoàn tất; private subnet có NAT hoặc VPC endpoints cho SSM/ECR/CloudWatch.
- AMI, instance type và ngân sách được phê duyệt.
- ECR có `app2-file-service`; không dùng tag `latest`.

## 5. Quy ước đặt tên tài nguyên

| Thành phần | Singapore | Tokyo |
|---|---|---|
| Instance | `dr-sg-storage-ec2` | `dr-tokyo-storage-ec2` |
| Role | `dr-sg-storage-role` | `dr-tokyo-storage-role` |
| SG | `dr-sg-storage-ec2-sg` | `dr-tokyo-storage-ec2-sg` |

## 6. Các bước triển khai

1. IAM -> Roles -> Create role -> EC2; gắn `AmazonSSMManagedInstanceCore` và policy ECR pull đặc quyền tối thiểu.
2. EC2 -> Launch instance; chọn Amazon Linux hiện hành, private subnet, `Auto-assign public IP: Disable`, encrypted EBS, IMDSv2 required.
3. Không tạo key pair nếu quy trình tổ chức chỉ dùng SSM. Không mở TCP 22.
4. Cho outbound HTTPS tới SSM/ECR/CloudWatch qua NAT hoặc endpoints; ghi lại lựa chọn.
5. Qua Session Manager, cài Docker từ repository chính thức của AMI, bật service, tạo `/mnt/dr-data` nhưng chưa ghi dữ liệu ứng dụng.
6. Bật CloudWatch agent/log shipping khi scope yêu cầu; không ghi token hoặc secret vào user data.

## 7. Xác minh

```bash
aws ssm describe-instance-information --region ap-southeast-1 --filters Key=tag:Name,Values=dr-sg-storage-ec2
aws ssm describe-instance-information --region ap-northeast-1 --filters Key=tag:Name,Values=dr-tokyo-storage-ec2
```

Trong SSM session: `docker version`, `test -d /mnt/dr-data`, `curl` tới metadata phải bị chặn nếu không dùng IMDSv2 token.

## 8. Kết quả mong đợi

Hai instance private xuất hiện `Online` trong SSM, Docker chạy, không public IP, không inbound SSH.

## 9. Xử lý sự cố

- SSM offline: kiểm tra role, DNS, NAT/endpoints, time sync và SSM Agent.
- ECR pull lỗi: kiểm tra regional repository, token endpoint, IAM và route.
- ALB unhealthy sau LAB 22: kiểm tra app bind `0.0.0.0`, port, SG và `/health`.

## 10. Lưu ý bảo mật

IMDSv2 bắt buộc; EBS mã hóa; patch AMI; Session Manager logging; IAM không có push/delete ECR; không lưu ONTAP admin password trên instance.

## 11. Lưu ý chi phí

EC2, EBS, NAT/VPC endpoints, CloudWatch và public ALB ở lab sau đều tính phí.

## 12. Dọn dẹp / Quay lui

Stop instance khi tạm dừng ngắn; terminate chỉ sau khi unmount FSx và giữ log/evidence. Xóa role sau instance profile.

## 13. Bằng chứng cần thu thập

Instance ID/subnet/SG, no-public-IP, IAM policy, SSM Online, Docker version, EBS encryption.

## 14. Lab tiếp theo

[LAB 19 - FSx ONTAP Singapore](19-fsx-ontap-singapore.md).
