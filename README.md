# AWS Multi-Region Disaster Recovery Platform
### Nền Tảng Khắc Phục Thảm Họa Đa Vùng Cho Cơ Sở Dữ Liệu & Hệ Thống Lưu Trữ Doanh Nghiệp Trên AWS

![AWS Multi-Region DR](https://img.shields.io/badge/AWS-Multi--Region%20DR-FF9900?logo=amazon-aws&logoColor=white)
![Kubernetes EKS](https://img.shields.io/badge/Kubernetes-EKS%20v1.29-326CE5?logo=kubernetes&logoColor=white)
![Aurora PostgreSQL](https://img.shields.io/badge/Database-Aurora%20Global%20PostgreSQL-336791?logo=postgresql&logoColor=white)
![NetApp ONTAP](https://img.shields.io/badge/Storage-FSx%20for%20NetApp%20ONTAP-0067B8?logo=netapp&logoColor=white)
![GitOps](https://img.shields.io/badge/GitOps-Argo%20CD-EF6B48?logo=argo&logoColor=white)
![IaC](https://img.shields.io/badge/IaC-Terraform%20v1.5+-844FBA?logo=terraform&logoColor=white)

---

## 1. Giới Thiệu Dự Án & Mục Tiêu

Dự án **AWS Multi-Region Disaster Recovery Platform** là đồ án kỹ thuật chuyên sâu về kiến trúc phục hồi thảm họa đa vùng (Multi-Region DR) trên nền tảng đám mây Amazon Web Services. Hệ thống bảo vệ một ứng dụng phân tán 5 microservices (`app2`) hoạt động giữa hai khu vực địa lý:
- **Singapore (`ap-southeast-1`)**: Vùng chính (Primary Active Region).
- **Tokyo (`ap-northeast-1`)**: Vùng phục hồi thảm họa (Disaster Recovery Warm Standby Region).

### Mục Tiêu Kỹ Thuật Trọng Tâm
1. **Bảo vệ tính toàn vẹn song song**: Giải quyết đồng thời bài toán phục hồi cơ sở dữ liệu quan hệ (Relational DB) và hệ thống tệp tin phi cấu trúc dùng chung (Shared File Storage).
2. **Đạt chỉ tiêu RTO/RPO nghiêm ngặt**:
   - Database Service RTO ≤ 240.0 s, RPO ≤ 60.0 s.
   - Storage Service RTO ≤ 300.0 s, RPO ≤ 300.0 s.
   - Unified Overall RTO ≤ 300.0 s.
3. **Thực chứng bằng số liệu thực tế**: Đo đạc bằng chứng thực nghiệm trên hạ tầng AWS đang hoạt động, có đối soát byte-for-byte và record-by-record, không sử dụng số liệu giả lập hay hardcoded.

---

## 2. Kiến Trúc Hệ Thống Đa Vùng (Singapore ↔ Tokyo)

Hệ thống được thiết kế theo mô hình **Warm Standby** với kết nối mạng riêng Inter-Region VPC Peering:

```text
                                  [ Client Traffic ]
                                          │
                            [ AWS Global Accelerator ]
                         (Anycast IPs: 75.2.109.112 / 99.83.197.80)
                                    /           \
                 (Traffic Dial: 100%)           (Traffic Dial: 0% -> 100% DR)
                                  /               \
       ┌─────────────────────────┴──┐           ┌──┴─────────────────────────┐
       │ Primary: Singapore         │           │ Recovery: Tokyo            │
       │ (ap-southeast-1)           │           │ (ap-northeast-1)           │
       │ VPC: 10.10.0.0/16          │           │ VPC: 10.20.0.0/16          │
       ├────────────────────────────┤           ├────────────────────────────┤
       │ • Application Load Balancer│           │ • Application Load Balancer│
       │ • Amazon EKS: dr-sg-eks    │           │ • Amazon EKS: dr-tokyo-eks │
       │   - app2-frontend (2 pods) │           │   - app2-frontend (1 pod)  │
       │   - app2-backend-1 (2 pods)│           │   - app2-backend-1 (1 pod) │
       │   - app2-backend-2 (2 pods)│           │   - app2-backend-2 (1 pod) │
       │   - app2-backend-3 (2 pods)│           │   - app2-backend-3 (1 pod) │
       │   - app2-file-service (2)  │           │   - app2-file-service (1)  │
       │                            │           │                            │
       │ [Storage & DB Tier]        │           │ [Storage & DB Tier]        │
       │ • Aurora: app2-sg-db       │           │ • Aurora: app2-tokyo-db    │
       │   (Primary Writer)         │══════════>│   (Reader -> Writer on DR) │
       │   [Storage-level Async Rep]│  <1s lag  │                            │
       │                            │           │                            │
       │ • FSx ONTAP: dr-sg-svm     │           │ • FSx ONTAP: dr-tokyo-svm  │
       │   Volume: drdata (RW)      │══════════>│   Volume: dr_data_dr (DP)  │
       │   [SnapMirror Async Rep]   │           │   (Promoted to RW on DR)   │
       └────────────────────────────┘           └────────────────────────────┘
```

Chi tiết sơ đồ kiến trúc: [docs/diagrams/01-multi-region-architecture.md](docs/diagrams/01-multi-region-architecture.md).

---

## 3. Các Dịch Vụ AWS Trọng Yếu

| Dịch Vụ AWS | Vai Trò Trong Hệ Thống | Cấu Hình Kỹ Thuật |
|---|---|---|
| **Amazon Aurora Global Database** | Quản lý dữ liệu quan hệ giao dịch (PostgreSQL 15) | Cụm đa vùng `app2-global-db`, nhân bản vật lý tầng lưu trữ. |
| **Amazon FSx for NetApp ONTAP** | Lưu trữ tệp tin chia sẻ doanh nghiệp qua NFSv4.1 | 2 SVMs (`dr-sg-svm`, `dr-tokyo-svm`) kết nối qua SnapMirror. |
| **Amazon EKS** | Chạy các microservices nghiệp vụ của ứng dụng | Cụm v1.29 tại 2 vùng, quản lý bằng Kustomize & Argo CD. |
| **AWS Global Accelerator** | Định tuyến Anycast IP và chuyển dịch lưu lượng | 2 Static Anycast IPs, điều khiển phân bổ lưu lượng qua Traffic Dial. |
| **AWS Lambda** | Tự động hóa ngắt và thăng cấp volume ONTAP | Function `dr-fsx-failover-promote-tokyo` tương tác ONTAP REST API. |
| **AWS Secrets Manager & ESO** | Quản trị thông tin xác thực an toàn | Đồng bộ secret cơ sở dữ liệu và ONTAP credentials vào Kubernetes. |

---

## 4. Mô Hình Aurora Global Database DR

- **Cơ chế sao chép**: Nhân bản trực tiếp ở tầng lưu trữ chuyên dụng của Aurora (Storage Engine Replication), hoàn toàn tách biệt với engine tính toán, giúp giảm thiểu độ trễ xuống < 1s mà không ảnh hưởng tới throughput của writer.
- **Cơ chế chuyển đổi (Planned Switchover)**:
  - Gọi API `rds.switchover_global_cluster` chỉ định target là cụm Tokyo.
  - Vùng chính Singapore đóng luồng ghi, đồng bộ toàn bộ buffer tồn đọng sang Tokyo.
  - Tokyo thăng cấp thành Global Writer Cluster (`IsWriter: True`), cụm Singapore tự động chuyển thành Read Replica để duy trì chuỗi dữ liệu.

Chi tiết quy trình: [docs/diagrams/02-aurora-replication-dr.md](docs/diagrams/02-aurora-replication-dr.md).

---

## 5. Mô Hình FSx for NetApp ONTAP SnapMirror DR

- **Cơ chế sao chép**: Thiết lập quan hệ Inter-Cluster SnapMirror giữa hai Storage Virtual Machine (SVM). Dữ liệu được đồng bộ dưới dạng snapshot gia tăng định kỳ qua đường kết nối VPC Peering.
- **Cơ chế thăng cấp (Volume Promotion)**:
  - Khi kích hoạt DR, Lambda gọi ONTAP REST API gửi lệnh `break_off` quan hệ SnapMirror `ce3ce815-cb1c-11f1-8f09-75ce6ba06232`.
  - Phân vùng Tokyo (`dr_data_dr`) lập tức chuyển đổi từ `DP` (Data Protection) sang `RW` (Read-Write).
  - Ứng dụng `app2-file-service` tại Tokyo với cấu hình NFS mount `readOnly: false` có thể thực hiện ghi đọc tệp tin ngay lập tức.

Chi tiết quy trình: [docs/diagrams/03-fsx-snapmirror-dr.md](docs/diagrams/03-fsx-snapmirror-dr.md).

---

## 6. Cơ Chế Điều Phối DR (Unified DR Orchestration)

Quy trình diễn tập được điều phối thông qua **Python Automated DR Runner** kết hợp AWS SDK (`boto3`) và ONTAP REST API:

1. **Preflight Safety Gate**: Rà soát trạng thái healthy của cả hai phân hệ; yêu cầu token phê duyệt tường minh (`--confirm-live-drill`) trước khi thực hiện bất kỳ thay đổi nào.
2. **Pre-drill Marker Injection**: Ghi 5 đơn hàng vào DB và 5 tệp tin vào FSx tại Singapore; kích hoạt SnapMirror update transfer để bảo đảm dữ liệu đã sang Tokyo.
3. **Coordinated Parallel Failover ($T_0$)**: Phát lệnh chuyển đổi song song cho cả hai nhánh.
4. **High-Frequency Probing**: Thăm dò độc lập đến khi cả hai phân hệ chứng minh được khả năng ghi đọc dữ liệu thực tế tại Tokyo.

Chi tiết quy trình: [docs/diagrams/04-unified-dr-execution-flow.md](docs/diagrams/04-unified-dr-execution-flow.md).

---

## 7. Kết Quả Đo Lường RTO/RPO Thực Tế

Toàn bộ số liệu dưới đây được trích xuất từ lượt chạy diễn tập **Live Unified DR** (`LIVE-RUN-20261018-230436`):

| Chỉ Số Đo Lường | Giá Trị Thực Nghiệm | Mục Tiêu SLA | Kết Luận | Cơ Chế Xác Minh |
|---|---:|---:|:---:|---|
| **Storage Volume RTO (T7)** | **5.719 s** | — | **PASS** | ONTAP REST API xác nhận Tokyo volume chuyển sang `RW` |
| **Storage Application RTO (T9, T11)** | **6.402 s** | ≤ 300.0 s | **PASS** | Tokyo `file-service` upload/download/sha256 tệp tin mới |
| **Database Writer RTO (T_DB_WRITER)** | **38.471 s** | — | **PASS** | AWS RDS API xác nhận Tokyo cluster là Global Writer |
| **Database Application RTO (T_DB_APP)** | **47.428 s** | ≤ 240.0 s | **PASS** | Tokyo `backend-3` xử lý thành công đơn hàng mới |
| **Unified Overall End-to-End RTO** | **47.429 s** | ≤ 300.0 s | **PASS** | max(47.428s, 6.402s) — Toàn bộ ứng dụng sẵn sàng |
| **Database Observed RPO** | **0.000 s** | ≤ 60.0 s | **PASS** | Thu hồi đủ 5/5 đơn hàng pre-drill (ID 100–104) |
| **Storage Observed RPO** | **0.000 s** | ≤ 300.0 s | **PASS** | Thu hồi đủ 5/5 tệp tin pre-drill, khớp 100% SHA-256 |

*Chi tiết toàn bộ bảng đối soát dữ liệu và phân tích kết quả xem tại: [docs/05-ket-qua-thuc-nghiem.md](docs/05-ket-qua-thuc-nghiem.md).*

---

## 8. Bảng Trạng Thái Triển Khai (Implementation Status)

| Hạng Mục Kỹ Thuật | Trạng Thái | Mô Tả Thực Hiện |
|---|:---:|---|
| **Hạ tầng mạng & VPC Peering** | **HOÀN TẤT** | Triển khai tự động bằng Terraform tại 2 vùng. |
| **Cụm Kubernetes EKS** | **HOÀN TẤT** | 2 cụm hoạt động, triển khai 5 microservices. |
| **GitOps Argo CD Reconcile** | **HOÀN TẤT** | Tự động đồng bộ `main`, `selfHeal: true`, NFS `readOnly: false`. |
| **Aurora Planned Switchover** | **HOÀN TẤT** | Thực nghiệm live trên AWS thành công. |
| **FSx ONTAP SnapMirror DR** | **HOÀN TẤT** | Thực nghiệm promotion và ghi đọc tệp tin thành công. |
| **Unified DR Orchestration** | **HOÀN TẤT** | Điều phối song song qua Python DR Runner. |
| **AWS Step Functions Unified** | **THIẾT KẾ** | Mẫu kiến trúc ASL template (`unified_state_machine.asl.json.tftpl`). |

---

## 9. Cấu Trúc Thư Mục Repository

```text
aws-multi-region-dr-platform/
│
├── README.md                  # Tài liệu tổng quan dự án (Tiếng Việt)
├── .gitignore                 # Cấu hình bỏ qua tệp tin rác và bí mật
│
├── iac/                       # Infrastructure as Code
│   └── terraform/             # Mã nguồn triển khai tài nguyên AWS
│       ├── envs/lab/          # Cấu hình môi trường lab thực nghiệm
│       └── modules/           # Các Terraform modules tái sử dụng (FSx, EKS, VPC, DR)
│
├── gitops/                    # Khai báo cấu hình ứng dụng Kubernetes (Argo CD)
│   └── app2/                  # Manifest microservices của ứng dụng app2
│       ├── base/              # Cấu hình chuẩn chung
│       └── overlays/          # Cấu hình đặc thù từng vùng
│           ├── singapore/     # Primary region overlay
│           └── tokyo/         # Warm standby region overlay (NFS readOnly: false)
│
├── results/                   # Bằng chứng và kết quả đo lường thực nghiệm
│   ├── README.md              # Báo cáo đối soát và chỉ số RTO/RPO
│   ├── unified-dr/            # Dữ liệu tổng thể lần chạy Live Unified DR
│   ├── database/              # Bằng chứng đo lường và đối soát đơn hàng Aurora
│   ├── storage/               # Bằng chứng đo lường và đối soát file FSx ONTAP
│   ├── evidence/              # Snapshot raw AWS API & ONTAP REST API
│   └── charts/                # Biểu đồ trực quan hóa RTO/RPO
│
└── docs/                      # Tài liệu kỹ thuật chi tiết
    ├── 01-tong-quan.md        # Bối cảnh, bài toán và mục tiêu SLA
    ├── 02-kien-truc-he-thong.md # Kiến trúc đa vùng và luồng dữ liệu
    ├── 03-ha-tang-aws.md      # Đặc tả kỹ thuật tài nguyên AWS và mạng
    ├── 04-quy-trinh-disaster-recovery.md # Diễn giải quy trình thực thi DR
    ├── 05-ket-qua-thuc-nghiem.md # Bảng kết quả RTO/RPO và đối soát integrity
    ├── 06-danh-gia-va-gioi-han.md # Đánh giá, giới hạn kỹ thuật và hướng phát triển
    └── diagrams/              # Sơ đồ kiến trúc định dạng Mermaid
```

> [!NOTE]
> **Về vị trí thư mục GitOps**: Thư mục `gitops/` được duy trì tại thư mục gốc của repository nhằm đảm bảo tương thích tuyệt đối với đường dẫn `spec.source.path: gitops/app2/overlays/tokyo` của Argo CD Application đang chạy trên cụm EKS Tokyo.

---

## 10. Danh Mục Tài Liệu Chi Tiết

- [Tài Liệu 01: Tổng Quan & Mục Tiêu Dự Án](docs/01-tong-quan.md)
- [Tài Liệu 02: Kiến Trúc Hệ Thống & Luồng Dữ Liệu](docs/02-kien-truc-he-thong.md)
- [Tài Liệu 03: Đặc Tả Hạ Tầng AWS & Mạng Liên Vùng](docs/03-ha-tang-aws.md)
- [Tài Liệu 04: Quy Trình Kích Hoạt Disaster Recovery](docs/04-quy-trinh-disaster-recovery.md)
- [Tài Liệu 05: Kết Quả Đo Lường & Bằng Chứng Thực Nghiệm](docs/05-ket-qua-thuc-nghiem.md)
- [Tài Liệu 06: Đánh Giá, Giới Hạn & Hướng Mở Rộng](docs/06-danh-gia-va-gioi-han.md)
- [Sơ Đồ Kiến Trúc Đa Vùng (Mermaid)](docs/diagrams/01-multi-region-architecture.md)
- [Sơ Đồ Chuyển Đổi Aurora Global Database](docs/diagrams/02-aurora-replication-dr.md)
- [Sơ Đồ Thăng Cấp FSx ONTAP SnapMirror](docs/diagrams/03-fsx-snapmirror-dr.md)
- [Sơ Đồ Tiến Trình Unified DR Execution Flow](docs/diagrams/04-unified-dr-execution-flow.md)

---

## 11. Các Giới Hạn Thực Nghiệm Cần Lưu Ý

1. **Cơ chế điều phối**: Diễn tập được thực thi theo mô hình **On-demand Automated DR** do người vận hành kích hoạt qua script Python, không phải hệ thống tự động phát hiện sự cố (Automatic Disaster Detection).
2. **Step Functions**: Cấu trúc Step Functions Unified hiện tại là mẫu thiết kế (template), chưa được triển khai live trên AWS.
3. **Kịch bản kiểm thử**: Kết quả đo lường dựa trên kịch bản **Planned Switchover** (chuyển đổi có kế hoạch, đồng bộ hết dữ liệu trước khi ngắt mạch). RPO quan sát được là 0 giây đối với tập dữ liệu mẫu và không đồng nghĩa với cam kết 0 RPO trong mọi tình huống thảm họa vật lý đột ngột.
4. **Mẫu dữ liệu**: Kết quả phản ánh chính xác lượt chạy thực tế `LIVE-RUN-20261018-230436`, không khẳng định ý nghĩa thống kê trên số lượng lớn lượt chạy lặp lại.

---

## 12. Trạng Thái Hạ Tầng & Dọn Dẹp Chi Phí (Cost Optimization & Decommissioning)

Sau khi hoàn thành xuất sắc toàn bộ thực nghiệm đo đạc RTO/RPO và đối soát bằng chứng, toàn bộ hạ tầng tính phí trên AWS đã được dỡ bỏ an toàn nhằm tối ưu hóa chi phí về **$0.00 / tháng**:
- **Bản sao lưu dữ liệu đầy đủ**: Toàn bộ dữ liệu nhị phân FSx (53 file) và toàn bộ 50 giao dịch Aurora đã được sao lưu cục bộ tại `docs/cleanup/backups/`.
- **Hạ tầng đã dỡ bỏ**: Toàn bộ cụm EKS (Singapore & Tokyo), Aurora Global Database, FSx for NetApp ONTAP, NAT Gateways, ALBs, Global Accelerator, Lambdas, và ECR repositories đã được xóa sạch.
- **Hạ tầng kiểm toán**: Giữ lại S3 bucket lưu trữ Terraform state `aws-multi-region-dr-platform-620306387033` phục vụ tra cứu kiểm toán đồ án.
- **Tài liệu kiểm kê chi tiết**:
  - [Kế Hoạch Dọn Dẹp & Kiểm Kê Trước Khi Xóa](docs/cleanup/cleanup-plan.md)
  - [Kiểm Kê Trước Khi Xóa (Inventory Before)](docs/cleanup/inventory-before.json)
  - [Kiểm Kê Sau Khi Xóa (Inventory After)](docs/cleanup/inventory-after.json)
  - [Nhật Ký Thực Hiện Xóa Chi Tiết (Deletion Log)](docs/cleanup/deletion-log.md)

