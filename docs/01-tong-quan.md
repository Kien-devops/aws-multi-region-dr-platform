# Tài Liệu 01: Tổng Quan Dự Án & Bài Toán Disaster Recovery

---

## 1. Bối Cảnh & Đặt Vấn Đề

Trong kỷ nguyên điện toán đám mây hiện đại, các hệ thống công nghệ thông tin trọng yếu phục vụ tài chính, thương mại điện tử và dịch vụ công đòi hỏi tính sẵn sàng liên tục ở mức cao nhất. Một sự cố diện rộng tại một vùng địa lý (AWS Region Outage) do thiên tai, mất điện lưới diện rộng hoặc đứt cáp viễn thông quốc tế có thể gây tê liệt hoàn toàn các dịch vụ triển khai đơn vùng (Single-Region).

Để bảo vệ hệ thống trước các thảm họa cấp vùng, việc xây dựng một **Nền tảng Khắc phục Thảm họa Đa vùng (AWS Multi-Region Disaster Recovery Platform)** là yêu cầu then chốt. Tuy nhiên, việc vận hành hệ thống đa vùng thường đối mặt với các thách thức kỹ thuật lớn:
1. **Độ trễ truyền dẫn xuyên lục địa (Cross-Region Latency)**: Việc sao chép dữ liệu đồng bộ (Synchronous Replication) qua khoảng cách lớn (ví dụ Singapore đến Tokyo ~5,300 km) làm giảm đáng kể hiệu năng ứng dụng do độ trễ RTT (Round Trip Time). Do đó, hệ thống buộc phải sử dụng cơ chế sao chép không đồng bộ (Asynchronous Replication).
2. **Nguy cơ mất mát dữ liệu (Data Loss Risk - RPO)**: Nhân bản không đồng bộ tiềm ẩn nguy cơ chênh lệch dữ liệu giữa vùng chính và vùng dự phòng tại thời điểm xảy ra sự cố.
3. **Thời gian phục hồi dịch vụ (Downtime - RTO)**: Quá trình chuyển đổi đòi hỏi nhiều bước phức tạp: thăng cấp cơ sở dữ liệu, ngắt liên kết lưu trữ tệp tin, cập nhật định tuyến lưu lượng mạng và đồng bộ trạng thái cấu hình ứng dụng.
4. **Phân mảnh dữ liệu giữa Cơ sở dữ liệu và Lưu trữ tệp tin**: Ứng dụng hiện đại vừa lưu trữ trạng thái giao dịch trong hệ quản trị cơ sở dữ liệu quan hệ (RDBMS), vừa lưu trữ tệp đính kèm/tài liệu trên hệ thống tệp tin chia sẻ (NFS/Shared File System). Nếu hai phân hệ này phục hồi lệch pha, tính toàn vẹn nghiệp vụ sẽ bị phá vỡ.

---

## 2. Mục Tiêu Đồ Án

Đồ án này tập trung nghiên cứu, thiết kế, triển khai và đánh giá thực nghiệm một giải pháp Disaster Recovery toàn diện trên nền tảng AWS:

- **Hạ tầng đa vùng chuẩn doanh nghiệp**: Xây dựng hạ tầng hoàn chỉnh trên hai vùng AWS: **Singapore (`ap-southeast-1`)** (Primary Region) và **Tokyo (`ap-northeast-1`)** (Warm Standby / Disaster Recovery Region).
- **Phục hồi Cơ sở dữ liệu quan hệ**: Tận dụng **Amazon Aurora Global Database (PostgreSQL)** để đạt mục tiêu nhân bản vật lý tốc độ cao và chuyển đổi vai trò writer nhanh chóng.
- **Phục hồi Lưu trữ tệp tin doanh nghiệp**: Ứng dụng **Amazon FSx for NetApp ONTAP** kết hợp công nghệ nhân bản **SnapMirror** để bảo vệ khối lượng tệp tin dùng chung giữa các Pods trong cụm EKS.
- **Tự động hóa GitOps**: Đồng bộ cấu hình ứng dụng trên **Amazon EKS** qua **Argo CD**, đảm bảo tính nhất quán của môi trường và khả năng phục hồi tự động khi cấu hình thay đổi.
- **Điều phối hợp nhất (Unified DR Orchestration)**: Phát triển quy trình điều phối song song cả hai nhánh lưu trữ (Database và File Storage) dưới một định danh duy nhất (Single RUN ID).
- **Thu thập số liệu thực nghiệm chuẩn xác**: Đo lường độc lập các chỉ số **RTO** và **RPO** thực tế trên tài nguyên AWS đang hoạt động, có bằng chứng đối soát byte-for-byte và record-by-record.

---

## 3. Các Mục Tiêu Chỉ Số Cốt Lõi (SLA Targets)

| Chỉ Số | Mục Tiêu Đồ Án | Định Nghĩa Kỹ Thuật |
|---|---|---|
| **Database RTO** | $\le 240.0\text{ giây}$ (4 phút) | Thời gian từ $T_0$ đến khi cụm Aurora Tokyo nhận và xác thực giao dịch ghi đầu tiên. |
| **Database RPO** | $\le 60.0\text{ giây}$ (1 phút) | Khoảng cách thời gian tối đa của các giao dịch bị mất khi xảy ra thảm họa. |
| **Storage RTO** | $\le 300.0\text{ giây}$ (5 phút) | Thời gian từ $T_0$ đến khi Tokyo FSx volume chuyển sang RW và ứng dụng ghi thành công tệp tin. |
| **Storage RPO** | $\le 300.0\text{ giây}$ (5 phút) | Độ mất mát tối đa về mặt tệp tin và dữ liệu lưu trữ trên hệ thống tệp tin ONTAP. |
| **Unified Overall RTO** | $\le 300.0\text{ giây}$ (5 phút) | Tổng thời gian để toàn bộ ứng dụng (cả DB và Storage) phục hồi trọn vẹn và sẵn sàng phục vụ người dùng. |

---

## 4. Phạm Vi Thực Hiện Của Đồ Án

1. **Phạm vi hạ tầng**:
   - VPC Peering kết nối liên vùng Singapore–Tokyo.
   - 2 Cụm Amazon EKS (`dr-sg-eks` và `dr-tokyo-eks`).
   - 1 Amazon Aurora Global Database (`app2-global-db`) gồm cụm Singapore (`app2-sg-db`) và cụm Tokyo (`app2-tokyo-db`).
   - 2 Hệ thống tệp tin FSx for NetApp ONTAP với SnapMirror relationship liên kết giữa 2 Storage Virtual Machines (SVMs).
   - 1 AWS Global Accelerator định tuyến Anycast IP tĩnh tới ALB hai vùng.
2. **Phạm vi kịch bản thử nghiệm**:
   - Kịch bản chính là **Planned Disaster Recovery Switchover** (Chuyển đổi vùng có kế hoạch, có kiểm soát an toàn trước khi ngắt mạch).
   - Đối soát toàn bộ dữ liệu mẫu (synthetic markers) trước và sau cutover để xác định chính xác độ trễ và tính toàn vẹn.
