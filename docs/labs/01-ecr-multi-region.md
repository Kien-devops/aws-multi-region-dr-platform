# LAB 01 - Amazon ECR Đa Vùng và Tự Động Sao Chép (ECR Multi-Region Replication)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Tạo 4 kho chứa container image trên Amazon ECR tại vùng chính Singapore (`ap-southeast-1`):
   - `app2-frontend`
   - `app2-backend-1`
   - `app2-backend-2`
   - `app2-backend-3`
2. Kích hoạt tính năng **Tag Immutability** (Bất biến thẻ tag) và **Scan on Push** (Quét lỗ hổng bảo mật).
3. Thiết lập tính năng **Cross-Region Replication** ở cấp độ Private Registry để mọi image có tiền tố `app2-` khi đẩy lên Singapore sẽ tự động được AWS sao chép sang vùng Tokyo (`ap-northeast-1`).
4. Hiểu rõ nguyên lý tại sao CI Pipeline chỉ cần push một lần tới Singapore mà hệ thống DR vẫn có sẵn image cục bộ với độ trễ thấp khi cần phục hồi.

---

## Architecture impact

```text
[ GitHub Actions CI ]
        |
        | 1. docker push app2-backend-2:sha-12345
        v
+--------------------------------------------------------+
| PRIMARY REGION: SINGAPORE (ap-southeast-1)             |
|                                                        |
|   Amazon ECR Private Registry                          |
|   |-- app2-frontend                                    |
|   |-- app2-backend-1                                   |
|   |-- app2-backend-2  <=== [Image mới vừa được push]  |
|   |-- app2-backend-3                                   |
+--------------------------------------------------------+
        |
        | 2. AWS Native Asynchronous Layer Replication
        |    (Replication Rule Prefix: "app2-")
        v
+--------------------------------------------------------+
| DR REGION: TOKYO (ap-northeast-1)                      |
|                                                        |
|   Amazon ECR Private Registry                          |
|   |-- app2-frontend                                    |
|   |-- app2-backend-1                                   |
|   |-- app2-backend-2  <=== [Tự động xuất hiện tại đây] |
|   |-- app2-backend-3                                   |
+--------------------------------------------------------+
        |
        v
   [ EKS dr-tokyo-eks pulls image locally with zero cross-region latency ]
```

---

## Resource naming

- Primary Region: `ap-southeast-1` (Singapore)
- Destination DR Region: `ap-northeast-1` (Tokyo)
- ECR Repository Names:
  - `app2-frontend`
  - `app2-backend-1`
  - `app2-backend-2`
  - `app2-backend-3`
- Replication Filter: Tiền tố (prefix) `app2-`

---

## AWS Console Steps

### Bước 1: Chọn Region Singapore
1. Mở AWS Management Console.
2. Tại thanh điều hướng trên cùng bên phải, nhấp vào tên vùng và chọn **Asia Pacific (Singapore) ap-southeast-1**.

### Bước 2: Tạo 4 Repositories tại Singapore
Lặp lại các bước sau lần lượt cho cả 4 repository: `app2-frontend`, `app2-backend-1`, `app2-backend-2`, `app2-backend-3`:
1. Trên thanh tìm kiếm ở đầu trang, nhập `ECR` và chọn **Elastic Container Registry**.
2. Ở thanh menu bên trái, chọn **Repositories**.
3. Nhấn nút màu cam **Create repository**.
4. Tại mục **General settings**:
   - Visibility settings: Chọn **Private** (Kho lưu trữ riêng tư).
   - Repository name: Nhập tên tương ứng (ví dụ: `app2-frontend`).
5. Tại mục **Image tag mutability**:
   - Tích chọn **Enabled** cho *Tag immutability* (Ngăn chặn việc ghi đè lên các tag đã tồn tại, bảo đảm tính toàn vẹn cho GitOps).
6. Tại mục **Scan settings**:
   - Tích chọn **Enabled** cho *Scan on push* (Tự động quét lỗ hổng bảo mật CVE mỗi khi có image mới được đẩy lên).
7. Tại mục **KMS encryption**:
   - Giữ mặc định **AWS KMS** (hoặc AWS managed key `KMS`).
8. Cuộn xuống cuối trang và nhấn nút **Create repository**.
9. Lặp lại cho 3 repositories còn lại: `app2-backend-1`, `app2-backend-2`, và `app2-backend-3`.

### Bước 3: Cấu hình Tự Động Sao Chép (Private Registry Replication)
1. Vẫn trong giao diện ECR tại Singapore (`ap-southeast-1`), nhìn vào menu thanh bên trái.
2. Tại nhóm **Private registry**, nhấp chọn **Settings** (Cài đặt).
3. Tìm đến thẻ **Replication configuration** (Cấu hình sao chép) -> Nhấn nút **Edit** (hoặc **Set up replication**).
4. Nhấn nút **Add rule** (Thêm quy tắc).
5. Tại trang cấu hình quy tắc sao chép:
   - **Destination type:** Chọn **Cross-region** (Sao chép giữa các vùng).
   - **Destination region:** Nhấp vào danh sách thả xuống và chọn **Asia Pacific (Tokyo) ap-northeast-1**.
6. Tại mục **Repository filters** (Bộ lọc kho lưu trữ):
   - Chọn **Add repository filter**.
   - Filter type: Chọn **Prefix match** (Khớp theo tiền tố).
   - Value: Nhập `app2-` (Đảm bảo chỉ các repo có tiền tố `app2-` mới được replicate sang Tokyo).
   - Nhấn **Apply**.
7. Nhấn nút **Save** ở góc dưới cùng bên phải.
8. Màn hình hiển thị trạng thái quy tắc sao chép: Destination `ap-northeast-1`, Filter `app2-`.

---

## Configuration

| Thuộc tính | Giá trị cấu hình | Giải thích |
|---|---|---|
| **Primary Region** | `ap-southeast-1` | Vùng chính nơi CI Pipeline đẩy image |
| **Replication Region** | `ap-northeast-1` | Vùng DR tiếp nhận image tự động |
| **Visibility** | Private | Bảo mật nội bộ trong tài khoản AWS |
| **Tag Immutability** | Enabled | Chống đè tag `sha-...`, bảo vệ tính nhất quán của GitOps |
| **Scan on push** | Enabled | Quét lỗ hổng bảo mật tự động bằng Basic Scanning (Clair) |
| **Replication Filter Prefix** | `app2-` | Chỉ replicate image của dự án app2, không replicate các image không liên quan |

---

## Security considerations

- **Tag Immutability:** Nếu một image được tag bằng commit SHA (ví dụ: `sha-9a8b7c6`), việc bật immutability ngăn chặn kẻ xấu hoặc pipeline bị lỗi vô tình ghi đè một container image độc hại hoặc sai lệch phiên bản lên cùng một tag.
- **KMS Encryption:** Dữ liệu container layers khi lưu trữ (at-rest) trên S3 bucket ngầm của ECR luôn được mã hóa bằng AES-256 (KMS).
- **Phân tách thẩm quyền (Least Privilege):** Quá trình sao chép xuyên vùng do chính dịch vụ hạ tầng AWS quản lý (AWS Service Internal). GitHub Actions của bạn **chỉ cần quyền push lên ECR Singapore**, hoàn toàn không cần cấp quyền truy cập vào ECR Tokyo, giảm 50% diện tích tấn công (Attack Surface).

---

## Expected result

- Tại Singapore (`ap-southeast-1`): Xuất hiện đủ 4 repositories `app2-frontend`, `app2-backend-1`, `app2-backend-2`, `app2-backend-3`.
- Bảng Private Registry Settings hiển thị Replication rule sang `ap-northeast-1` với filter `app2-`.
- Khi một image được đẩy lên Singapore, kho lưu trữ tại Tokyo tự động được tạo ra (nếu chưa có) và image tương ứng xuất hiện với cùng digest/tag sau khoảng 1-2 phút.

---

## Verification

### Kiểm tra bằng Console
1. Mở Console ECR tại Singapore -> Repositories: Thấy cả 4 repo hiển thị `Mutable: False`, `Scan on push: True`.
2. Kiểm tra Settings -> Replication: Thấy rule `ap-northeast-1` với filter `app2-`.

### Kiểm tra bằng AWS CLI
Liệt kê các repositories tại Singapore:
```bash
aws ecr describe-repositories --region ap-southeast-1 \
  --query "repositories[?starts_with(repositoryName, 'app2-')].repositoryName" \
  --output table
```
*Expected output:*
```text
-------------------------
|  DescribeRepositories |
+-----------------------+
|  app2-frontend        |
|  app2-backend-1       |
|  app2-backend-2       |
|  app2-backend-3       |
+-----------------------+
```

Kiểm tra cấu hình replication:
```bash
aws ecr get-registry-scanning-configuration --region ap-southeast-1
aws ecr describe-registry --region ap-southeast-1 \
  --query "replicationConfiguration.rules" --output json
```
*Expected output:*
```json
[
    {
        "destinations": [
            {
                "region": "ap-northeast-1",
                "registryId": "<ACCOUNT_ID>"
            }
        ],
        "repositoryFilters": [
            {
                "filter": "app2-",
                "filterType": "PREFIX_MATCH"
            }
        ]
    }
]
```

### Kiểm tra Thử nghiệm Đẩy và Sao Chép Image Thực tế (Mô phỏng cục bộ)
```bash
# 1. Login Docker vào ECR Singapore
aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com

# 2. Tạo một image test nhẹ từ alpine
docker pull alpine:latest
docker tag alpine:latest <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/app2-backend-1:test-v1

# 3. Đẩy image lên Singapore
docker push <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/app2-backend-1:test-v1

# 4. Đợi 30-60 giây và kiểm tra tại Tokyo
aws ecr describe-images --repository-name app2-backend-1 --region ap-northeast-1 \
  --query "imageDetails[*].imageTags" --output json
```
*Expected output tại Tokyo:* Danh sách trả về chứa `["test-v1"]`.

---

## Troubleshooting

1. **Lỗi: Image được đẩy lên Singapore nhưng không xuất hiện ở Tokyo:**
   - *Nguyên nhân:* Bộ lọc Prefix trong Replication Rule bị nhập sai (ví dụ nhập `app2` thiếu dấu gạch nối, hoặc nhập sai chữ hoa/thường).
   - *Cách sửa:* Vào ECR -> Private Registry -> Settings -> Edit Replication Configuration. Kiểm tra filter có khớp chính xác với `app2-` hay không.
2. **Lỗi: `The image tag 'test-v1' already exists in the repository` khi push:**
   - *Nguyên nhân:* Bạn đang cố gắng đẩy lại cùng một tag lên một repo đã kích hoạt *Tag Immutability*.
   - *Cách sửa:* Đây là tính năng bảo vệ mong muốn. Luôn sử dụng tag mới (như mã commit SHA độc nhất `sha-abc1234` hoặc số build).
3. **Lỗi: `denied: Your authorization token has expired`:**
   - *Nguyên nhân:* Token xác thực ECR từ lệnh `get-login-password` chỉ có hiệu lực trong 12 giờ.
   - *Cách sửa:* Chạy lại lệnh `aws ecr get-login-password --region ap-southeast-1 | docker login ...` để lấy token mới.

---

## Cost note

- **Tạo Repository:** Hoàn toàn miễn phí.
- **Lưu trữ Image:** Chi phí tiêu chuẩn $0.10/GB/tháng cho dung lượng lưu trữ tại cả Singapore và Tokyo.
- **Data Transfer Out (Cross-Region):** Quá trình sao chép image từ Singapore sang Tokyo tính phí truyền tải dữ liệu giữa các vùng của AWS (khoảng $0.09/GB).
- **Khuyến nghị tiết kiệm chi phí:** Khi thực hành lab, có thể tạo Lifecycle Policy để tự động xóa các image cũ hơn 7 ngày hoặc chỉ giữ lại 3 image gần nhất.

---

## Next step

Tiếp tục chuyển sang [LAB 02 - Xây Dựng Hạ Tầng Mạng VPC Singapore](02-networking-singapore.md).
