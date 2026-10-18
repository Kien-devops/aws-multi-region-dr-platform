# Tài Liệu 06: Đánh Giá, Giới Hạn Kỹ Thuật & Hướng Phát Triển

Tài liệu này cung cấp cái nhìn khách quan, khoa học về những kết quả đã đạt được, các giới hạn kỹ thuật nội tại của đồ án, phân tích chi phí và đề xuất hướng mở rộng trong tương lai.

---

## 1. Những Kết Quả Đã Đạt Được

1. **Xây Dựng Thành Công Hạ Tầng Đa Vùng Hoàn Chỉnh**:
   - Tự động hóa 100% bằng Terraform v1.5+ cho toàn bộ mạng VPC, Inter-Region Peering, cụm EKS, Aurora Global Database và FSx for NetApp ONTAP trên hai vùng Singapore và Tokyo.
2. **Triển Khai Mô Hình GitOps Chuẩn Mực**:
   - Sử dụng Argo CD với cơ chế Kustomize phân tách rõ ràng giữa `base` và `overlays`.
   - Khắc phục triệt để lỗi phân quyền NFS read-only trên Kubernetes, đảm bảo tính bền vững của các phân vùng lưu trữ ngay cả khi Argo CD tự động kích hoạt `selfHeal`.
3. **Thực Nghiệm Thành Công Phục Hồi Lưu Trữ Phức Hợp**:
   - Chứng minh tính khả thi của việc kết hợp song song cả cơ sở dữ liệu quan hệ (Aurora) và hệ thống tệp tin phi cấu trúc (FSx ONTAP).
   - Đo lường được số liệu RTO thực tế: Overall RTO = **47.429 giây** (Mục tiêu: $\le 300\text{s}$).
   - Đo lường được số liệu RPO thực tế: Observed RPO = **0.000 giây** trên tập dữ liệu kiểm thử được kiểm soát.

---

## 2. Các Giới Hạn Kỹ Thuật Quan Trọng

Để đảm bảo tính trung thực và chuẩn mực kỹ thuật trong báo cáo đồ án, các giới hạn sau đây cần được trình bày rõ ràng:

### 2.1. Về Cơ Chế Điều Phối (DR Orchestration)
- **Hình thức thực thi**: Diễn tập được thực hiện dưới dạng **On-demand Automated DR** do kỹ sư vận hành kích hoạt và giám sát, **không phải hệ thống tự động phát hiện sự cố (Automatic Failure Detection)**.
- **Công cụ điều phối**: Quá trình điều phối hai nhánh song song trong lần diễn tập thành công được thực hiện bởi **Python DR Runner** gọi trực tiếp các AWS SDK API (`boto3`) và AWS Lambda.
- **Trạng thái AWS Step Functions**: Cấu trúc Step Functions State Machine cho Unified DR hiện mới dừng lại ở mức thiết kế mẫu kiến trúc (Terraform template: `unified_state_machine.asl.json.tftpl`), **chưa được triển khai và kiểm chứng dưới dạng state machine live trên AWS**.

### 2.2. Về Ý Nghĩa Thống Kê Của Dữ Liệu
- **Số lần thử nghiệm**: Báo cáo dựa trên **01 lần diễn tập Unified DR thành công trọn vẹn** (`LIVE-RUN-20261018-230436`) cùng các bài kiểm tra phân hệ đơn lẻ trước đó.
- **Tính đại diện**: Do chi phí và giới hạn thao tác trên môi trường Cloud thực tế, số lượng mẫu thử nghiệm hiện tại chưa đủ để đưa ra các kết luận thống kê phức tạp (như độ lệch chuẩn hay phân vị P95/P99 trên tập mẫu lớn). Các con số trình bày là kết quả đo đạc chính xác của lượt chạy này.

### 2.3. Về Bản Chất Kịch Bản Planned Switchover
- Cuộc diễn tập được thực hiện theo kịch bản **Planned Switchover** (chuyển đổi có kế hoạch): Singapore chủ động đồng bộ hết dữ liệu trước khi chuyển giao quyền ghi.
- Do đó, giá trị **RPO = 0 giây** là kết quả của việc đồng bộ có kiểm soát. Trong trường hợp thảm họa vật lý đột ngột (Hard Crash / Unplanned Failover), RPO sẽ phụ thuộc vào độ trễ mạng thực tế tại mili-giây xảy ra thảm họa.

---

## 3. Phân Tích Chi Phí Môi Trường (Cost Analysis)

Mô hình Multi-Region Warm Standby mang lại độ sẵn sàng vượt trội nhưng đi kèm chi phí tài nguyên song song:
- **FSx for NetApp ONTAP**: Chi phí lưu trữ SSD và dung lượng thông lượng (Throughput Capacity) phải duy trì đồng thời ở cả hai vùng.
- **Amazon Aurora Global Database**: Chi phí tính toán cho các instances tại cụm phụ (Tokyo) và cước phí truyền dữ liệu liên vùng (Inter-Region Data Transfer).
- **Amazon EKS**: Chi phí quản lý cụm ($0.10/giờ cho mỗi cluster) cùng chi phí các EC2 worker nodes ở trạng thái Warm Standby.

$\rightarrow$ *Khuyến nghị tối ưu*: Đối với môi trường thực tế, có thể áp dụng mô hình **Pilot Light** (chỉ bật Storage & Database Replicas, chỉ khởi tạo worker nodes EKS khi có sự cố) để tiết kiệm 40–60% chi phí điện toán tại vùng phụ.

---

## 4. Hướng Phát Triển Tương Lai

1. **Hoàn thiện AWS Step Functions Unified State Machine**: Chuyển đổi mã điều phối Python sang Step Functions native kết hợp AWS EventBridge để có quy trình trực quan hóa hoàn chỉnh trên AWS Console.
2. **Tích hợp Tự Động Hóa Chuyển Mạng Bằng AWS Route 53 Application Recovery Controller (ARC)**: Tự động hóa chuyển đổi Routing Control qua health checks liên vùng độc lập.
3. **Thực Nghiệm Kịch Bản Unplanned Failover Đột Ngột**: Giả lập ngắt kết nối đột ngột bằng AWS Fault Injection Simulator (FIS) để đo đạc RPO trong điều kiện mất mát tín hiệu cưỡng bức.
