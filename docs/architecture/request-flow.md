# Luồng Xử Lý Request (Request Flow)

Tài liệu này mô tả chi tiết đường đi của gói tin từ khi người dùng gửi yêu cầu HTTP/HTTPS qua Internet cho tới các tầng tính toán và cơ sở dữ liệu trên kiến trúc AWS Multi-Region.

---

## 1. Sơ đồ Luồng Request Tổng thể (End-to-End Request Flow)

```text
                                [ CLIENT / BROWSER ]
                                         |
                                         v
                         [ 1. Anycast DNS Resolution ]
                           (Hai địa chỉ IP tĩnh cố định)
                                         |
                                         v
                      [ 2. AWS Global Accelerator (AGA) ]
                       - Tuyến đường tối ưu qua AWS Backbone
                       - Health Check liên tục tới cả 2 ALBs (/health)
                                         |
            +----------------------------+----------------------------+
            | (Trạng thái bình thường: 100% Traffic)                  | (Khi Singapore gặp sự cố: Chuyển vùng)
            v                                                         v
   [ 3a. Singapore ALB ]                                     [ 3b. Tokyo ALB ]
   - Internet-facing ALB                                     - Internet-facing ALB
   - Multi-AZ Public Subnets                                 - Multi-AZ Public Subnets
   - Port 80 listener                                        - Port 80 listener
            |                                                         |
            v                                                         v
   [ 4a. AWS LB Controller / Target Group ]                  [ 4b. AWS LB Controller / Target Group ]
   - Target Type: ip (AWS VPC CNI)                           - Target Type: ip (AWS VPC CNI)
   - Chuyển tiếp tới Private Pod IPs                         - Chuyển tiếp tới Private Pod IPs
            |                                                         |
            v                                                         v
   [ 5a. app2-frontend Pods (Port 3000) ]                    [ 5b. app2-frontend Pods (Port 3000) ]
   - Nhận traffic từ ALB Port 80                             - Nhận traffic từ ALB Port 80
   - Gọi API nội bộ Kubernetes                               - Gọi API nội bộ Kubernetes
            |                                                         |
   +--------+--------+                                       +--------+--------+
   |        |        |                                       |        |        |
   v        v        v                                       v        v        v
[backend-1] [backend-2] [backend-3]                      [backend-1] [backend-2] [backend-3]
(Port 8081) (Port 8082) (Port 8083)                      (Port 8081) (Port 8082) (Port 8083)
/api/v1/info /catalog   /orders                          /api/v1/info /catalog   /orders
(No DB)     (No DB)     (PostgreSQL)                     (No DB)     (No DB)     (PostgreSQL)
                         |                                                        |
                         | (SQL Query qua Private Subnet Port 5432)               | (SQL Query qua Private Subnet Port 5432)
                         v                                                        v
  ===================================================================================
                   [ 6. Amazon Aurora PostgreSQL Global Database ]
  ===================================================================================
            |                                                         |
            v                                                         v
   [ Aurora Primary Cluster ]                                [ Aurora Secondary Cluster ]
      (Singapore Writer)                                          (Tokyo Read-Only)
   - Viết trực tiếp vào storage volume                       - Nhận dữ liệu qua Aurora
   - Phản hồi kết quả cho Backend-3                          Storage Replication Engine (< 1s)
```

---

## 2. Chi tiết từng chặng xử lý (Hop-by-Hop Breakdown)

### Chặng 1 & 2: Client -> AWS Global Accelerator
1. Client phân giải tên miền hoặc kết nối trực tiếp đến **2 Anycast Static IP** do AWS Global Accelerator cung cấp.
2. Lưu lượng truy cập đi vào Edge Location gần nhất của AWS (Point of Presence - PoP), sau đó đi trên mạng trục bảo mật tốc độ cao toàn cầu của AWS (AWS Global Private Backbone Network) thay vì đi qua internet công cộng nhiều nút trung gian.
3. Listener trên Global Accelerator phân tích cấu hình **Traffic Dial** và kết quả **Health Check**:
   - **Tùy chọn A (Kiểm soát chủ động):** Endpoint Group Singapore đặt Traffic Dial = 100%, Tokyo đặt 0% (Warm Standby). Khi phát hiện sự cố, người vận hành hoặc kịch bản tự động đổi Singapore về 0% và Tokyo lên 100%.
   - **Tùy chọn B (Điều hướng tự động dựa trên sức khỏe):** Cả 2 Endpoint Groups đặt Traffic Dial 100%. Global Accelerator kiểm tra sức khỏe của ALB thông qua Target Groups bên dưới kiểm tra path `/health`. Khi phát hiện Singapore ALB Unhealthy, AGA tự động cách ly Singapore và chuyển lưu lượng sang Tokyo ALB trong vòng 20 - 30 giây.

### Chặng 3 & 4: Application Load Balancer -> EKS Pods (IP Target Mode)
1. ALB nhận gói tin tại Public Subnet (Multi-AZ) trên Port 80.
2. Ingress resource được quản lý bởi **AWS Load Balancer Controller** sử dụng chế độ routing `target-type: ip`.
3. Thay vì đi qua NodePort rồi đến `kube-proxy` (gây thêm 1 hop mạng và che giấu Client IP), ALB chuyển tiếp trực tiếp gói tin tới chính xác địa chỉ IP riêng của Pod (thuộc dải CIDR của VPC nhờ AWS VPC CNI).

### Chặng 5: Ingress Routing và Microservices Architecture
Application microservices `app2` tuân thủ nghiêm ngặt API Contract:
- **`app2-frontend` (Port 3000):**
  - Nhận HTTP GET `/` và GET `/health`
  - Service Kubernetes mở Port 80 trỏ tới `targetPort: 3000`
- **`app2-backend-1` (Port 8081):**
  - Nhận HTTP GET `/health` và GET `/api/v1/info`
  - Đóng vai trò cung cấp thông tin metadata hệ thống, **không kết nối cơ sở dữ liệu**
- **`app2-backend-2` (Port 8082):**
  - Nhận HTTP GET `/health`, GET `/api/v1/info`, và GET `/api/v1/catalog`
  - Đóng vai trò Catalog microservice, dữ liệu in-memory/cache, **không kết nối cơ sở dữ liệu**
- **`app2-backend-3` (Port 8083):**
  - Nhận HTTP GET `/health`, GET `/api/v1/info`, GET `/api/v1/orders`, và POST `/api/v1/orders`
  - **Microservice duy nhất kết nối cơ sở dữ liệu PostgreSQL** để thực hiện các nghiệp vụ đặt hàng và ghi nhận transaction

> [!IMPORTANT]
> **Path Routing Caveat:** ALB Ingress Controller không tự động strip prefix đường dẫn. Mọi request gửi tới `/api/v1/orders` sẽ được chuyển tiếp nguyên vẹn tới backend container. Mã nguồn ứng dụng `app2` đã được thiết kế sẵn để khớp chính xác các routes này.

### Chặng 6: Backend-3 -> Aurora PostgreSQL Global Database
1. Backend-3 kết nối tới cơ sở dữ liệu qua giao thức PostgreSQL (Port 5432) sử dụng 5 biến môi trường:
   - `DB_HOST`: Writer Endpoint của cụm cơ sở dữ liệu
   - `DB_PORT`: `5432`
   - `DB_USER`: Tên tài khoản quản trị
   - `DB_PASSWORD`: Mật khẩu đồng bộ qua AWS Secrets Manager
   - `DB_NAME`: Tên database
2. **Chiến lược Endpoint Cơ sở dữ liệu:**
   - **Cluster Writer Endpoint:** Trỏ trực tiếp tới DB Instance có quyền ghi trong cụm khu vực.
   - **Cluster Reader Endpoint:** Tự động cân bằng tải giữa các read replicas trong nội bộ vùng.
   - **Aurora Global Database Writer Endpoint (Nếu hỗ trợ):** Đại diện toàn cục cho Primary Cluster hiện tại.
   - **Phương án dự phòng (Fallback):** Cập nhật `DB_HOST` qua Secrets Manager hoặc Route 53 Private Hosted Zone CNAME trong quá trình thăng cấp.
3. Khi Singapore là Primary Region:
   - Backend-3 tại Singapore gửi query ghi/đọc đến Singapore Writer Endpoint.
   - Dữ liệu được ghi vào storage volume của Singapore, sau đó được replication engine vật lý của Aurora sao chép bất đồng bộ (cross-region physical replication) sang storage volume của Tokyo với độ trễ đo đạc qua `AuroraGlobalDBReplicationLag` (thông thường $< 1\text{s}$, cam kết mục tiêu thiết kế RPO $< 30\text{s}$).
4. Khi Tokyo được thăng cấp (Failover):
   - Tokyo DB Instance chuyển từ Read-Only sang Read-Write.
   - Backend-3 tại Tokyo kết nối tới endpoint writer mới được kích hoạt và thực thi giao dịch thành công.

---

## 3. Cân nhắc Bảo mật trong Luồng Request (Security Guardrails)
- **Zero Public Exposure for Compute & Data:** Node EKS và Database Aurora chỉ nằm trong Private Subnets. Không thể truy cập từ internet nếu không qua ALB.
- **Least Privilege Database Access:** Chỉ duy nhất Backend-3 được cấp quyền kết nối mạng và Secret truy cập database. Frontend, Backend-1, Backend-2 hoàn toàn không có thông tin đăng nhập database.
- **Security Group Chaining:**
  - ALB Security Group: Chỉ mở inbound port 80 từ Internet.
  - Node & Pod Security Group: Chỉ chấp nhận inbound ports của ứng dụng (`3000`, `8081`, `8082`, `8083`) từ ALB Security Group.
  - Aurora Security Group: Chỉ chấp nhận inbound port 5432 từ Security Group của EKS Node / Pods trong VPC.
