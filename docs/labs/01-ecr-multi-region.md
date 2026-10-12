# LAB 01 - ECR đa Region

## 1. Mục tiêu

Tạo năm ECR repository bất biến tại Singapore và cấu hình replication sang Tokyo.

## 2. Thành phần sẽ xây dựng

- Các repository tại Singapore: `app2-frontend`, `app2-backend-1`, `app2-backend-2`, `app2-backend-3`, `app2-file-service`.
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

### 6.1 Cấu hình quét lỗ hổng Registry (Scanning)

1. Mở AWS Console, chuyển Region sang **Asia Pacific (Singapore) `ap-southeast-1`**.
2. Trên thanh tìm kiếm, gõ `ECR` và chọn **Elastic Container Registry**.
3. Trong thanh điều hướng bên trái, mở mục **Private registry** -> chọn **Scanning** (hoặc **Settings** -> **Scanning** tùy phiên bản giao diện).
4. Tại tab **Scanning configuration**, nhấp nút **Edit** ở góc trên bên phải:
   - **Scan type**:
     - *Basic scanning*: Sử dụng bộ quét Clair mã nguồn mở của AWS (Miễn phí, thích hợp cho lab).
     - *Enhanced scanning*: Tích hợp sâu với Amazon Inspector (Tính phí theo số lượng image và quét liên tục, khuyến nghị cho Production).
   - Chọn **Basic scanning** cho mục đích tiết kiệm chi phí lab.
   - Tại mục **Scanning frequency**:
     - Chọn **Scan on push** (Tự động quét ngay khi image được đẩy lên) hoặc chọn **Continuous scanning** nếu chọn Enhanced.
   - Tại mục **Filters**:
     - Chọn **Filter repositories** -> nhấp **Add filter**.
     - **Filter type**: Chọn `Prefix match`.
     - **Value**: Nhập `app2-` (hoặc chọn `Scan all repositories` nếu muốn quét toàn bộ).
5. Nhấp nút **Save** màu cam ở cuối trang để lưu cấu hình.

### 6.2 Tạo 5 Private Repositories nguồn tại Singapore

Thực hiện lần lượt cho 5 repository: `app2-frontend`, `app2-backend-1`, `app2-backend-2`, `app2-backend-3`, `app2-file-service`.

1. Đảm bảo vẫn đang ở Region **Singapore (`ap-southeast-1`)**.
2. Trong menu bên trái của ECR Console, chọn **Repositories**.
3. Nhấp nút **Create repository** màu cam ở góc trên bên phải.
4. Tại mục **General settings**:
   - **Visibility settings**: Chọn **Private**.
   - **Repository name**: Nhập tên repository (ví dụ: `app2-frontend`).
5. Tại mục **Tag immutability**:
   - Gạt công tắc chuyển sang **Enabled**.
   - *Ý nghĩa:* Ngăn chặn việc ghi đè lên các tag đã tồn tại (chẳng hạn chống ghi đè tag commit SHA), đảm bảo tính toàn vẹn và bất biến của bản phát hành.
6. Tại mục **Image scan settings**:
   - Gạt công tắc **Scan on push** sang **Enabled** (nếu hiển thị ở cấp repository).
7. Tại mục **KMS encryption**:
   - Mặc định là AWS-managed key (AES-256). Nếu tổ chức yêu cầu Customer Managed Key (CMK), gạt bật **KMS encryption** và chọn ARN của KMS Key đã chuẩn bị. Với bài lab này, giữ mặc định AES-256 (KMS encryption: Disabled).
8. Nhấp nút **Create repository** ở cuối trang.
9. Lặp lại các bước 3 đến 8 cho 4 repository còn lại:
   - `app2-backend-1`
   - `app2-backend-2`
   - `app2-backend-3`
   - `app2-file-service`

### 6.3 Cấu hình Repository Creation Template tại Tokyo

Khi ECR sao chép một image sang Tokyo lần đầu tiên, nếu repository đích chưa tồn tại, ECR sẽ tự động tạo repository đó. Template này đảm bảo repository đích tại Tokyo cũng tự động kế thừa tính bất biến (Immutable) và mã hóa giống như Singapore.

1. Tại góc trên bên phải của AWS Console, nhấp vào menu Region và chuyển sang **Asia Pacific (Tokyo) `ap-northeast-1`**.
2. Trong thanh menu bên trái, mở mục **Private registry** -> chọn **Repository creation templates**.
3. Nhấp vào nút **Create template** màu cam.
4. Tại mục **Template details**:
   - **Prefix**: Nhập `app2-`.
   - **Description**: Nhập `Creation template for replicated app2 repositories`.
   - **Applied for**: Tích chọn vào ô **Replication** (Bắt buộc).
5. Tại mục **Image tag immutability**:
   - Chọn **Immutable** (hoặc gạt switch sang **Enabled**).
6. Tại mục **KMS encryption**:
   - Giữ cấu hình đồng nhất với Singapore (Mặc định AES-256 hoặc chọn CMK Tokyo tương ứng).
7. Tại mục **Repository permissions & Lifecycle policy**:
   - Có thể để trống hoặc chọn cấu hình mặc định.
8. Nhấp nút **Create** ở cuối trang.

### 6.4 Cấu hình Replication Rule tại Singapore

1. Chuyển Region trên AWS Console quay trở lại **Asia Pacific (Singapore) `ap-southeast-1`**.
2. Trong menu bên trái, mở mục **Private registry** -> chọn **Replication**.
3. Tại trang **Replication configuration**, nhấp nút **Edit** màu cam ở góc trên bên phải.
4. Nhấp nút **Add rule**:
   - **Destination type**: Chọn **Cross-region** (hoặc giữ mặc định cùng account).
   - **Destination**:
     - Chọn **Your account** (hoặc cùng tài khoản).
     - **Destination region**: Trong danh sách dropdown, cuộn và chọn **Asia Pacific (Tokyo) ap-northeast-1**.
   - **Repository filters**:
     - Nhấp **Add filter**.
     - **Filter type**: Chọn `Prefix match`.
     - **Filter value**: Nhập `app2-`.
5. Nhấp nút **Save** (hoặc **Submit**) để lưu quy tắc nhân bản.
6. Xác nhận trên màn hình danh sách: Rule mới xuất hiện hiển thị đích đến là `ap-northeast-1` với bộ lọc repository `app2-`.

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

- Có năm repository nguồn bất biến.
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

Chỉ xóa image kiểm thử theo đúng digest/tag khi đã được phê duyệt. Việc xóa toàn bộ repository và replication thuộc LAB 27.

## 13. Bằng chứng cần thu thập

- Cấu hình repository nguồn.
- Repository creation template tại đích.
- JSON của quy tắc replication.
- Digest nguồn/đích và thời gian replication quan sát được.
- Kết quả quét image dùng một lần, không tuyên bố image app2 đã được xây dựng.

## 14. Lab tiếp theo

Tiếp tục với [LAB 02 - VPC Singapore](02-networking-singapore.md).
