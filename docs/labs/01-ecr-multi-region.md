# LAB 01 - ECR đa Region

## 1. Mục tiêu

Tạo bốn ECR repository bất biến tại Singapore và cấu hình replication sang Tokyo mà chưa xây dựng image app2.

## 2. Thành phần sẽ xây dựng

- Các repository tại Singapore: `app2-frontend`, `app2-backend-1`, `app2-backend-2`, `app2-backend-3`.
- Cấu hình quét registry.
- Repository creation template tại Tokyo cho các repository có tiền tố `app2-` được tạo bởi replication.
- Quy tắc private registry replication từ Singapore sang Tokyo.
- Bài kiểm chứng replication bằng image nhỏ, tùy chọn.

## 3. Bối cảnh kiến trúc

```text
CI app2 tương lai -> ECR Singapore -> ECR replication bất đồng bộ -> ECR Tokyo
```

Chỉ image được push sau khi cấu hình replication mới tự động được sao chép. Cấu hình repository và lifecycle policy không tự đồng bộ; phải cấu hình rõ hành vi tại đích.

## 4. Điều kiện tiên quyết

- Hoàn thành LAB 00.
- Docker, chỉ cần cho bài kiểm chứng tùy chọn.
- Quyền cấu hình ECR registry/repository ở cả hai Region.
- Chốt phương án mã hóa trước khi tạo repository; không thể đổi kiểu mã hóa ECR repository sau khi tạo.

## 5. Quy ước đặt tên tài nguyên

| Hạng mục | Giá trị |
|---|---|
| Region nguồn | `ap-southeast-1` |
| Region đích | `ap-northeast-1` |
| Tiền tố repository | `app2-` |
| Image tag ở Giai đoạn 2 | Git commit SHA bất biến; không dùng `latest` |

## 6. Các bước triển khai

### 6.1 Cấu hình quét registry

AWS Console tại Singapore:

```text
ECR -> Private registry -> Scanning
Choose Basic or Enhanced scanning according to budget/security requirements
Filter: app2-* or scan all repositories
Continuous/scan-on-push behavior: enable as supported by selected mode
-> Save
```

Enhanced scanning sử dụng Amazon Inspector và có chi phí cao hơn; nên chọn cho production.

### 6.2 Tạo repository nguồn

Lặp lại cho cả bốn tên:

```text
ECR Singapore -> Repositories -> Create repository
Visibility: Private
Repository name: <name>
Tag mutability: Immutable
Encryption: AES-256 default, or approved customer-managed KMS key
-> Create repository
```

Nếu Console vẫn hiển thị tùy chọn scan-on-push ở cấp repository, bật nhất quán với chế độ quét registry đã chọn.

### 6.3 Cấu hình repository creation template tại Tokyo

AWS Console tại Tokyo:

```text
ECR -> Private registry -> Repository creation templates
-> Create template
Applied for: Replication
Repository namespace prefix: app2-
Tag mutability: Immutable
Encryption: same approved class; choose Tokyo KMS key if using customer-managed KMS
Lifecycle/repository policy: configure if required
-> Create
```

Template này ngăn repository đích do replication tạo ra âm thầm dùng cấu hình mặc định yếu hơn.

### 6.4 Cấu hình replication tại Singapore

```text
ECR Singapore -> Private registry -> Replication
-> Edit -> Add rule
Destination: same account, ap-northeast-1
Repository filter: Prefix match, app2-
-> Save
```

### 6.5 Kiểm chứng replication tùy chọn

Dùng một public image dùng một lần; đây không phải app2:

```bash
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com

docker pull public.ecr.aws/docker/library/busybox:stable
docker tag public.ecr.aws/docker/library/busybox:stable \
  <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/app2-backend-1:infra-test-<UNIQUE_ID>
docker push <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/app2-backend-1:infra-test-<UNIQUE_ID>
```

Kiểm tra lặp tại Tokyo bằng `describe-images`. Không cam kết thời gian replication; ghi lại thời gian quan sát thực tế.

## 7. Xác minh

```bash
aws ecr describe-repositories --region ap-southeast-1 \
  --query "repositories[?starts_with(repositoryName, 'app2-')].[repositoryName,imageTagMutability,encryptionConfiguration.encryptionType]" --output table

aws ecr describe-registry --region ap-southeast-1 \
  --query 'replicationConfiguration.rules' --output json

aws ecr describe-repository-creation-templates --region ap-northeast-1

aws ecr describe-images --region ap-northeast-1 \
  --repository-name app2-backend-1 --output table
```

So sánh digest nguồn và đích của image kiểm thử tùy chọn.

## 8. Kết quả mong đợi

- Có bốn repository nguồn bất biến.
- Quy tắc replication trỏ tới Tokyo với tiền tố `app2-`.
- Template đích áp dụng đúng cấu hình dự kiến.
- Image kiểm thử tùy chọn xuất hiện tại Tokyo với cùng digest.

## 9. Xử lý sự cố

- Chưa có repository đích: replication chỉ tạo repository sau khi có một image mới khớp bộ lọc được push.
- Không thấy image cũ: cấu hình replication trước, sau đó push/copy lại image.
- Lỗi tag đã tồn tại: tính bất biến đang hoạt động; dùng tag duy nhất.
- Lỗi KMS: kiểm tra quyền của dịch vụ ECR và người vận hành trên regional key.
- Cấu hình Tokyo khác dự kiến: xác nhận repository creation template đã khớp tiền tố trước lần replication đầu tiên.

## 10. Lưu ý bảo mật

- Dùng private repository, SHA tag bất biến, quét lỗ hổng và mã hóa dữ liệu lưu trữ.
- CI tương lai chỉ nhận quyền push tại Region nguồn; không dùng static AWS key.
- Cấu hình lifecycle policy riêng ở cả hai Region sau khi xác định thời gian lưu giữ.
- Ở Giai đoạn 2, chặn deployment theo vulnerability policy; chỉ bật scanning không tự ngăn image có lỗ hổng.

## 11. Lưu ý chi phí

Chi phí gồm lưu image ở cả hai Region, truyền dữ liệu replication liên Region, scanning và KMS request tùy chọn. Xóa tag kiểm thử dùng một lần sau khi thu bằng chứng nếu không cần lưu giữ.

## 12. Dọn dẹp / Quay lui

Chỉ xóa image kiểm thử theo đúng digest/tag khi đã được phê duyệt. Việc xóa toàn bộ repository và cấu hình replication được thực hiện ở LAB 18.

## 13. Bằng chứng cần thu thập

- Cấu hình repository nguồn.
- Repository creation template tại đích.
- JSON của quy tắc replication.
- Digest nguồn/đích và thời gian replication quan sát được.
- Kết quả quét image dùng một lần, không tuyên bố image app2 đã được xây dựng.

## 14. Lab tiếp theo

Tiếp tục với [LAB 02 - VPC Singapore](02-networking-singapore.md).
