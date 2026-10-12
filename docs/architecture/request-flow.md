# Luồng Xử lý Yêu cầu (Request Flow)

## Sơ đồ Luồng Xử lý Yêu cầu Kiến trúc (Request Flow Diagram)

```mermaid
sequenceDiagram
    autonumber
    actor Client as Người dùng / Client
    participant GA as AWS Global Accelerator (Anycast IP)
    participant ALB as Application Load Balancer
    participant Pod as EKS Ingress Pod / EC2 Container
    participant DB as Aurora / FSx ONTAP

    Note over Client,DB: Luồng 1: Application Workload (EKS & Aurora DB)
    Client->>GA: HTTP/HTTPS Request (app.example.com)
    GA->>ALB: Route tới Healthy Endpoint Group (Singapore 100%)
    ALB->>Pod: Chuyển tiếp tới Target Pods (IP Target Mode)
    Pod->>DB: Đọc/Ghi dữ liệu tới Aurora Global Writer Endpoint
    DB-->>Pod: Trả về kết quả SQL
    Pod-->>ALB-->>GA-->>Client: HTTP 200 OK

    Note over Client,DB: Luồng 2: File Service Workload (EC2 & FSx ONTAP)
    Client->>GA: POST /files (Storage Event & Binary Upload)
    GA->>ALB: Route tới Storage ALB Singapore (Port 80)
    ALB->>Pod: Chuyển tiếp tới EC2 file-service container (Port 8080)
    Pod->>DB: Ghi dữ liệu trực tiếp vào NFS 4.1 Mount (/mnt/dr-data)
    DB-->>Pod: Xác nhận ghi đĩa thành công trên FSx ONTAP
    Pod-->>ALB-->>GA-->>Client: HTTP 201 Created (JSON File Info)
```

## Trách nhiệm của từng Chặng (Hop-by-Hop Responsibilities)

1. **AWS Global Accelerator:** Cung cấp 2 địa chỉ Anycast IP tĩnh toàn cầu, giám sát sức khỏe của các Endpoint Groups theo vùng, và điều chuyển lưu lượng các kết nối TCP mới tới vùng khả dụng.
2. **Application Load Balancer (ALB):** Đóng vai trò Reverse Proxy, thực hiện SSL/TLS Termination trên môi trường Production, đánh giá sức khỏe của các Targets qua HTTP Health Check, và định tuyến dựa trên Host/Path.
3. **AWS Load Balancer Controller:** Chuyển đổi trạng thái khai báo của Kubernetes Ingress/Service thành cấu hình thực tế của ALB, Listeners, Target Groups và Security Groups trên AWS.
4. **Kubernetes Service & Pods:** Tiếp nhận và xử lý request. Chế độ `IP target mode` đăng ký trực tiếp địa chỉ Pod IP vào ALB Target Group để giảm bớt chặng trung gian NodePort.
5. **Ứng dụng (Application / File Service):** Thực thi business logic, xác thực người dùng và đọc/ghi dữ liệu.
6. **Amazon Aurora Global Database:** Endpoint ghi toàn cầu (`Global Writer Endpoint`) tự động trỏ tới cụm Primary hiện hành; các Regional Reader Endpoints phục vụ các tác vụ đọc phân tán theo vùng.

## Ý nghĩa của Kiểm tra Sức khỏe (Health Check Semantics)

- **Global Accelerator** đánh giá tình trạng của ALB dựa trên kết quả kiểm tra sức khỏe của các Targets trong Target Groups tương ứng.
- **ALB Health Path** phải phản ánh chính xác khả năng phục vụ lưu lượng của workload (Readiness), chứ không chỉ đơn thuần là tiến trình container còn sống (Liveness).
- Giai đoạn 1 kiểm thử hạ tầng bằng endpoint `/` trên disposable NGINX.
- Giai đoạn 2 sử dụng endpoint kiểm tra sẵn sàng chuyên biệt `/ready` hoặc `/health` mà không làm thay đổi trạng thái dữ liệu nghiệp vụ.

## Hành vi khi Xảy ra Sự cố (Failure Behavior)

- Việc thay đổi **Traffic dial** chỉ ảnh hưởng tới **các kết nối mới (New connections)**, không ngắt các kết nối TCP hiện có.
- Nếu một Endpoint Group bị lỗi toàn bộ (Unhealthy), Global Accelerator có thể tự động chuyển hướng sang Endpoint Group còn lại nếu nhóm đó có sức khỏe tốt và trọng số dương.
- Nếu tất cả các vùng đều mất kết nối (Unhealthy), GA có thể rơi vào trạng thái Fail-Open. Hệ thống giám sát CloudWatch Alarms phải bắt được tình trạng này ngay lập tức.
- Thao tác thăng cấp Database (Database promotion) và điều chuyển lưu lượng mạng là hai thao tác mặt bằng điều khiển (Control Plane) độc lập; bắt buộc phải thực hiện tuần tự theo đúng quy trình runbook.

## Ranh giới Bảo mật (Security)

- Giai đoạn 1 sử dụng HTTP thuần để kiểm thử hạ tầng, không mang dữ liệu nhạy cảm.
- Giai đoạn 2 bắt buộc áp dụng giao thức HTTPS, quản lý chứng chỉ số bằng AWS Certificate Manager (ACM), cấu hình AWS WAF, bảo mật Security Groups và mã hóa đường truyền.
- Cụm cơ sở dữ liệu Aurora và FSx ONTAP hoàn toàn nằm trong Private Subnets; chỉ các Pods và máy ảo được phân quyền mới có thể truy cập cổng 5432 (PostgreSQL) và 2049 (NFS).
