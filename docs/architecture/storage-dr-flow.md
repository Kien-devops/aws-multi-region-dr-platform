# Luồng Khắc phục Thảm họa Lưu trữ (Storage Disaster Recovery Flow)

## Phân tách Trạng thái (Separation of State)

```text
backend-3 -> Aurora Global Database -> Trạng thái giao dịch (transaction state)
file-service -> EC2 -> NFS 4.1 -> FSx ONTAP -> Trạng thái tệp tin (file state)
```

Metadata tệp tin, nhật ký sự kiện và các byte dữ liệu tải lên đều nằm chung dưới thư mục `/mnt/dr-data`; không phụ thuộc vào cơ sở dữ liệu Aurora để tái tạo danh mục tệp tin.

## Tô pô Trạng thái Hoạt động Bình thường (Normal State Topology)
 
```mermaid
flowchart LR
    subgraph Clients["Tầng Client"]
        User["Người dùng"]
    end

    subgraph GA["AWS Global Accelerator"]
        GA_Storage["dr-storage-accelerator"]
    end

    subgraph SG["Singapore (Primary RW)"]
        ALB_SG["Storage ALB (SG)"]
        EC2_SG["EC2: dr-sg-storage-ec2\n(file-service non-root 1000:1000)"]
        FSx_SG["FSx ONTAP: dr-sg-fsx\n(SVM: dr-sg-svm | Volume: dr-data RW)"]
    end

    subgraph Tokyo["Tokyo (Standby DP)"]
        ALB_Tokyo["Storage ALB (Tokyo)"]
        EC2_Tokyo["EC2: dr-tokyo-storage-ec2\n(Standby container)"]
        FSx_Tokyo["FSx ONTAP: dr-tokyo-fsx\n(SVM: dr-tokyo-svm | Volume: dr-data-dr DP)"]
    end

    User --> GA_Storage
    GA_Storage -->|Traffic dial: 100%| ALB_SG
    GA_Storage -.->|Traffic dial: 0%| ALB_Tokyo
    ALB_SG --> EC2_SG
    EC2_SG -->|NFS 4.1 /mnt/dr-data| FSx_SG

    ALB_Tokyo --> EC2_Tokyo
    EC2_Tokyo -.->|Mount khi promote| FSx_Tokyo

    FSx_SG ===|SnapMirror Asynchronous Replication\n(VPC Peering Ports 11104-11105)| FSx_Tokyo
```

Global Accelerator của tầng Storage (`dr-storage-accelerator`) tách biệt hoàn toàn với Global Accelerator của EKS (`dr-platform-accelerator`), bởi vì Global Accelerator hoạt động ở tầng L4 không hỗ trợ định tuyến theo HTTP Path, đồng thời AWS Load Balancer Controller trong Kubernetes nắm toàn quyền quản lý vòng đời của EKS ALB.

## Ranh giới Mạng (Network Boundary)

- **VPC Peering xuyên vùng:** Dịch vụ Aurora, ECR và Secrets Manager sao chép dữ liệu hoàn toàn qua mạng backbone của AWS mà không cần VPC Peering. Tuy nhiên, NetApp SnapMirror bắt buộc phải có kết nối mạng hai chiều giữa các intercluster LIFs của hai cụm FSx.
- **Quy tắc Security Group xuyên vùng:** Sử dụng dải CIDR (`10.10.0.0/16` và `10.20.0.0/16`), không thể tham chiếu ID của Security Group khác Region.
- **Cổng dịch vụ Intercluster:** Chỉ mở đúng các cổng đã được NetApp và AWS kiểm chứng: ICMP (Ping), TCP `443` (REST API / HTTPS), `10000` (NDMP), `11104` và `11105` (SnapMirror Data & Control).
- **Giao thức NFS Client:** Client EC2 kết nối qua địa chỉ DNS hoặc IP nội bộ của SVM. Sử dụng NFSv4.1 qua cổng TCP `2049` (kèm RPC ports 111, 635 để hỗ trợ mount).

## Ranh giới Thăng cấp Quyền Ghi (Promotion Boundary)

```text
1. Cô lập Writer Singapore (GA dial = 0 và dừng container)
2. Chạy final update (nếu Singapore còn kết nối được)
3. Xác minh trạng thái quan hệ và mốc transfer cuối cùng
4. Tạm dừng chuyển dữ liệu (Quiesce)
5. Phá vỡ quan hệ SnapMirror (Break destination thành RW)
6. Mount volume vào namespace SVM Tokyo (/dr-data)
7. Khởi động file-service container non-root tại Tokyo
8. Chuyển hướng lưu lượng Global Accelerator sang Tokyo (dial = 100)
```

Đối với sự cố đột ngột (Unplanned Failover), bước final update có thể không thực hiện được. Mốc sequence cuối cùng được replicate trước sự cố sẽ xác định **Storage RPO thực tế**.

## Ranh giới Khôi phục Về Singapore (Failback Boundary)

Tokyo là nguồn chân lý duy nhất (Authoritative Source) sau khi thăng cấp. Để khôi phục:
1. Đảo chiều quan hệ SnapMirror (Tokyo -> Singapore).
2. Chờ đồng bộ dữ liệu hoàn tất (`Snapmirrored` / `Idle`).
3. Dừng ghi tại Tokyo và chạy final update sang Singapore.
4. Thăng cấp volume Singapore trở lại thành Read-Write (RW).
5. Tái lập mô hình bảo vệ chuẩn (Singapore Primary -> Tokyo Standby DP).

> [!CAUTION]
> Lệnh `snapmirror resync` ngược có thể xóa vĩnh viễn các snapshot và dữ liệu mới hơn trên destination (Singapore). Bắt buộc phải tạo bản sao lưu FSx Backup / Snapshot đầy đủ và có sự phê duyệt từ hai kỹ sư độc lập trước khi thực hiện.

## Bằng chứng Cần Thu thập (Evidence)

- Trạng thái `State`, `Status` và mốc thời gian `Last Transfer` của SnapMirror.
- Mã sequence ACK cuối cùng tại Singapore và sequence phục hồi thành công tại Tokyo.
- Bằng chứng cô lập chiều ghi cũ (Fencing Proof).
- Mã băm SHA-256 đối chiếu tính toàn vẹn file trước và sau diễn tập.
