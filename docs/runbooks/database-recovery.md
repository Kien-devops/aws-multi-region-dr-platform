# Sổ tay Vận hành: Phục hồi Aurora Global Database (Database Recovery Runbook)

## Chiến lược Điểm cuối Kết nối (Endpoint Strategy)

- Toàn bộ ứng dụng thực hiện ghi (Write) sử dụng **Aurora Global Database Writer Endpoint**.
- Các Regional Reader Endpoints chỉ phục vụ các tác vụ đọc được thiết kế phân tán theo vùng.
- Instance Endpoints riêng lẻ chỉ sử dụng cho mục đích chẩn đoán sự cố nội bộ.
- Secret `/app2/database` trong Secrets Manager lưu giữ **Global Writer Endpoint** để sau khi switchover/failover đổi vai trò giữa các Region, chuỗi kết nối của ứng dụng vẫn có hiệu lực tức thì mà không cần cập nhật secret.

## Kịch bản 1: Sự cố Node Nội bộ Vùng (Instance Failure Inside Primary Region)

Đây là sự cố mức Availability Zone hoặc phần cứng node đơn lẻ, **không phải sự cố thảm họa đa vùng (Multi-Region DR)**.
- **Cơ chế tự động:** Aurora Multi-AZ tự động thăng cấp một Read Replica trong cùng vùng lên làm Writer mới trong vòng < 60 giây. CNAME của Cluster Endpoint tự động trỏ tới node mới.
- **Thao tác thủ công trên RDS Console (nếu cần ép buộc failover node AZ):**
  1. Vào **Amazon RDS Console** -> **Databases**.
  2. Tích chọn DB Cluster tại Singapore (`dr-sg-aurora-cluster`).
  3. Chọn menu **Actions** -> chọn **Failover** -> xác nhận.
- **Lưu ý:** Giữ nguyên Global Accelerator traffic dial trỏ về Singapore (100%), không kích hoạt cross-region failover.

---

## Kịch bản 2: Chuyển đổi Chủ động Không Mất Dữ liệu (Planned Cross-Region Switchover)

Sử dụng khi cần bảo trì toàn bộ Region Singapore hoặc diễn tập DR có kế hoạch.
- **Thao tác trên RDS Console:**
  1. Mở **Amazon RDS Console** -> **Databases**.
  2. Tích chọn cụm toàn cầu **`dr-global-db`**.
  3. Nhấp menu **Actions** -> chọn **Switch over global database**.
  4. Chọn target secondary cluster: **`dr-tokyo-aurora-cluster`**.
  5. Nhấp nút màu cam **Switch over**.
- **Kết quả:** Aurora đồng bộ toàn bộ buffer dở dang, tạm dừng nhận ghi trong vài giây, đổi chiều replication (Tokyo trở thành Writer mới, Singapore thành Reader). RPO = 0.

---

## Kịch bản 3: Sự cố Thảm họa Bất ngờ (Unplanned Cross-Region Failover)

Kích hoạt khi Region Singapore bị ngắt kết nối hoàn toàn hoặc gặp thảm họa diện rộng.
- **Thao tác trên RDS Console:**
  1. Ngay lập tức cô lập lưu lượng Ingress Singapore trên **AWS Global Accelerator Console** (chỉnh Traffic dial về `0`).
  2. Mở **Amazon RDS Console** -> **Databases**.
  3. Tích chọn cụm toàn cầu **`dr-global-db`**.
  4. Nhấp menu **Actions** -> chọn **Fail over global database**.
  5. Chọn target secondary cluster: **`dr-tokyo-aurora-cluster`**.
  6. **Bắt buộc:** Tích chọn ô vuông xác nhận chấp nhận rủi ro mất mát dữ liệu (*"I acknowledge that failing over..."*).
  7. Nhấp nút màu cam **Fail over**.
- **Lưu ý:** Cụm Singapore cũ bị cô lập hoàn toàn khi hồi phục, không tự động nhận write để tránh Split-Brain.

---

## Kịch bản 4: Tái thiết lập Cụm Secondary Bị hỏng hoặc Phân nhánh (Broken or Divergent Secondary)

Khi cụm Secondary bị lỗi đồng bộ, hoặc sau khi Singapore hồi phục sau Unplanned Failover và cần được tái gia nhập làm Secondary:
1. **Gỡ bỏ cụm cũ bị phân nhánh khỏi Global Database:**
   - Trên RDS Console -> Databases -> chọn cụm Singapore cũ.
   - Nhấp **Actions** -> chọn **Remove from global database** -> xác nhận gỡ bỏ.
   - Xóa cụm độc lập cũ sau khi đã lưu trữ snapshot kiểm toán (nếu cần).
2. **Tái tạo Secondary Cluster từ Primary hiện tại (Tokyo):**
   - Trên RDS Console -> Databases -> chọn cụm Primary hiện hành (**`dr-tokyo-aurora-cluster`**).
   - Nhấp menu **Actions** -> chọn **Add AWS Region**.
   - **Target region:** Chọn **Asia Pacific (Singapore) `ap-southeast-1`**.
   - **DB cluster identifier:** Nhập `dr-sg-aurora-cluster`.
   - **DB subnet group:** Chọn `dr-sg-db-subnet-group`.
   - **VPC security groups:** Chọn `dr-sg-db-sg`.
   - Bấm nút cam **Add region**.
3. **Chờ đồng bộ:** Chờ hệ thống khởi tạo và sao chép dữ liệu (Storage clone) qua đường truyền nội bộ AWS cho đến khi cụm Singapore hiển thị **Available (Reader)** và metric `AuroraGlobalDBReplicationLag` trở về `<= 1s`.

## Lệnh Kiểm tra Xác minh (Verification Commands)

```bash
# Kiểm tra vai trò các cluster trong cụm toàn cầu
aws rds describe-global-clusters --region <CURRENT_PRIMARY_REGION> --global-cluster-identifier app2-global-db \
  --query 'GlobalClusters[0].{Status:Status,Endpoint:Endpoint,Members:GlobalClusterMembers[*].{Arn:DBClusterArn,Writer:IsWriter,Sync:SynchronizationStatus}}'

# Kiểm tra tình trạng cụm vùng
aws rds describe-db-clusters --region ap-southeast-1 --db-cluster-identifier dr-sg-aurora-cluster
aws rds describe-db-clusters --region ap-northeast-1 --db-cluster-identifier dr-tokyo-aurora-cluster
```

Kiểm tra trên CloudWatch các metric: `AuroraGlobalDBReplicationLag`, `AuroraGlobalDBProgressLag`, `AuroraGlobalDBRPOLag`, RDS events, mức sử dụng CPU, RAM, số lượng Database Connections và Storage IOPS.

---

## Kiểm soát Chống Phân nhánh Dữ liệu (Split-Brain Prevention)

- Luôn duy trì đúng một topology toàn cầu có căn cứ và đúng **một Primary Writer duy nhất**.
- Bắt buộc phải khóa lưu lượng Ingress trước khi kích hoạt failover khẩn cấp.
- Giới hạn nghiêm ngặt quyền gọi API `failover-global-cluster` cho các tài khoản người dùng thông thường.
- Không bao giờ trỏ secret của ứng dụng hoặc DNS vào một cụm database độc lập đã bị phân nhánh (divergent).
- Yêu cầu sự phê chuẩn của Lead DBA và Incident Commander trước khi tái hòa mạng một cụm Singapore cũ sau sự cố.

---

## Phục hồi Thông tin Xác thực (Credential Recovery)

- Tuyệt đối không tự ý rotate hoặc in thông tin mật khẩu ra log chỉ để debug lỗi kết nối mạng.
- Mọi hoạt động rotate mật khẩu cơ sở dữ liệu phải thực hiện qua **AWS Secrets Manager**.
- Xác nhận trạng thái replica secret giữa Singapore và Tokyo luôn đạt **InSync**.
- Nếu một replica secret bị cô lập, phải có tài liệu ghi nhận rõ ràng trước khi khôi phục hoạt động bình thường.

---

## Các Bước Phụ thuộc Ứng dụng (Application-Dependent Steps)

Việc chạy migration lược đồ dữ liệu (Flyway / Liquibase), đối chiếu các giao dịch tài chính bị gián đoạn và đo đạc transaction RPO thực tế sẽ được tích hợp trong giai đoạn triển khai ứng dụng.
