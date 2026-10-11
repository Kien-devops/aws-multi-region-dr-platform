# AWS Multi-Region Disaster Recovery Platform

Dự án danh mục (Portfolio Project) xây dựng và kiểm chứng thực tế một nền tảng **Khôi Phục Sau Thảm Họa Đa Vùng (Multi-Region Disaster Recovery Platform)** trên nền tảng Amazon Web Services (AWS) với thời gian downtime tối thiểu, hỗ trợ chuyển dịch lưu lượng tức thì, bảo vệ dữ liệu xuyên suốt và đo lường định lượng các chỉ số RTO/RPO thực tế.

---

## 1. Giới Thiệu Dự Án (Project Overview)

Mục tiêu cốt lõi của nền tảng là cung cấp khả năng tự chịu lỗi và phục hồi sau sự cố ở cấp độ khu vực địa lý (Regional Failure) cho hệ thống thương mại điện tử / microservices `app2` (gồm 1 Web Frontend và 3 Backend Services). Hệ thống được thiết kế theo mô hình **Warm Standby** nhằm cân bằng tối ưu giữa chi phí vận hành hàng tháng và tốc độ khôi phục dịch vụ.

- **Vùng Chính (Primary Region):** `ap-southeast-1` (Singapore) - Chịu 100% tải người dùng thông thường, cấu hình nhiều bản sao (2 replicas/service), tích hợp PodDisruptionBudget (PDB) và Topology Spread Constraints, nắm giữ quyền ghi cơ sở dữ liệu (**Aurora Primary Writer**).
- **Vùng Dự Phòng (DR Region):** `ap-northeast-1` (Tokyo) - Chạy ở chế độ **Warm Standby** (1 replica/service), hạ tầng tính toán luôn trong trạng thái "ấm" (Warm), cơ sở dữ liệu đóng vai trò **Aurora Secondary Read Replica** với độ trễ sao chép vật lý theo dõi qua metric `AuroraGlobalDBReplicationLag` (thông thường $< 1\text{s}$, cam kết mục tiêu thiết kế RPO $< 30\text{s}$).
- **Phương châm thiết kế:** Thực hành từng bước trên **AWS Console** để hiểu tường tận bản chất $\rightarrow$ Kiểm chứng kiến trúc và đo đạc RTO/RPO $\rightarrow$ Tự động hóa toàn bộ bằng **Terraform (IaC)**.

---

## 2. Hợp Đồng Ứng Dụng Thực Tế (Application Contract)

Nền tảng GitOps manifests và cấu hình Ingress phản ánh chính xác 100% mã nguồn thực tế của repo [`app2`](https://github.com/Kien-devops/app2):

| Dịch vụ | Ngôn ngữ / Runtime | Container Port | Service Port | Endpoints hỗ trợ | Kết nối Database | Biến môi trường đặc thù |
|---|---|:---:|:---:|---|:---:|---|
| **`app2-frontend`** | Node.js (Web UI) | `3000` | `80` | `GET /`<br>`GET /health` | Không | `AWS_REGION` |
| **`app2-backend-1`**| Node.js (Info API) | `8081` | `8081` | `GET /health`<br>`GET /api/v1/info` | Không | `AWS_REGION` |
| **`app2-backend-2`**| Node.js (Catalog) | `8082` | `8082` | `GET /health`<br>`GET /api/v1/info`<br>`GET /api/v1/catalog` | Không | `AWS_REGION` |
| **`app2-backend-3`**| Node.js (Orders) | `8083` | `8083` | `GET /health`<br>`GET /api/v1/info`<br>`GET /api/v1/orders`<br>`POST /api/v1/orders` | **PostgreSQL** (Port 5432) | `AWS_REGION`<br>`DB_HOST`<br>`DB_PORT`<br>`DB_USER`<br>`DB_PASSWORD`<br>`DB_NAME` |

> [!NOTE]
> **Least Privilege Secret Injection:** Chỉ duy nhất `app2-backend-3` được cấp quyền nhận Secret thông tin cơ sở dữ liệu từ AWS Secrets Manager qua External Secrets Operator. `frontend`, `backend-1`, `backend-2` hoàn toàn không lưu trữ credential database.

---

## 3. Sơ Đồ Kiến Trúc (Architecture Diagram)

```text
                                   [ USERS ]
                                       |
                                       v
                         [ AWS Global Accelerator ]
                          (Anycast Static Anycast IPs)
                                       |
              +------------------------+------------------------+
              | (Normal 100% Traffic)                           | (Standby / Failover)
              v                                                 v
   =============================                     =============================
    PRIMARY REGION: SINGAPORE                         DR REGION: TOKYO
    (ap-southeast-1)                                  (ap-northeast-1)
   =============================                     =============================
              |                                                 |
              v                                                 v
      [ Application LB ]                                [ Application LB ]
    (Public Subnets Multi-AZ)                         (Public Subnets Multi-AZ)
              |                                                 |
              v                                                 v
    [ EKS: dr-sg-eks ]                                [ EKS: dr-tokyo-eks ]
  (Replicas: 2, PDB, TopologySpread)                (Replicas: 1 - Warm Standby)
              |                                                 |
              +---+-------------+                               +---+-------------+
              |   |             |                               |   |             |
              v   v             v                               v   v             v
        [app2 Microservices]                              [app2 Warm Standby Pods]
     (Frontend, Backend-1,2,3)                         (Frontend, Backend-1,2,3)
              |                                                 |
              +------------------------+------------------------+
                                       |
                                       v
                     [ Aurora PostgreSQL Global Database ]
              +------------------------+------------------------+
              | (Physical Storage Replication - RPO < 30s)      |
              v                                                 v
    [ app2-sg-db Cluster ]                            [ app2-tokyo-db Cluster ]
      (PRIMARY WRITER)                                    (READ-ONLY REPLICA)
```

Xem phân tích kiến trúc chi tiết tại:
- [Kiến trúc tổng quan (Architecture Overview)](docs/architecture/overview.md)
- [Luồng xử lý Request (Request Flow)](docs/architecture/request-flow.md)
- [Luồng triển khai GitOps & CI/CD (Deployment Flow)](docs/architecture/deployment-flow.md)
- [Luồng phục hồi thảm họa (Disaster Recovery Flow)](docs/architecture/dr-flow.md)

---

## 4. Phân Định Trách Nhiệm Repository (Repository Responsibility)

Dự án được chia tách tường minh giữa mã nguồn ứng dụng và cấu hình hạ tầng GitOps:

1. **Repository Ứng Dụng:** [`Kien-devops/app2`](https://github.com/Kien-devops/app2)
   - Chịu trách nhiệm về mã nguồn nghiệp vụ của `frontend/`, `backend-1/`, `backend-2/`, `backend-3/`, và `shared/`.
   - Chạy GitHub Actions CI với bộ lọc thư mục (Paths Filter), xác thực an toàn qua GitHub OIDC Token Exchange với IAM Trust Policy ràng buộc nghiêm ngặt `repo:Kien-devops/app2:ref:refs/heads/main`.
   - Build và push Docker image kèm commit SHA bất biến duy nhất lên Amazon ECR Singapore (`ap-southeast-1`).
   - Kích hoạt cập nhật GitOps manifest thông qua script chuyên dụng [`scripts/update-image-tag.sh`](scripts/update-image-tag.sh).
2. **Repository Trạng Thái Khát Vọng (Repo Hiện Tại):** [`Kien-devops/aws-multi-region-dr-platform`](https://github.com/Kien-devops/aws-multi-region-dr-platform)
   - Chịu trách nhiệm về toàn bộ tài liệu kiến trúc, bộ bài tập thực hành Labs từng bước trên AWS Console, và các Runbooks cứu hộ khẩn cấp.
   - Chứa manifests GitOps ([`gitops/app2/`](gitops/app2/)) quản lý cấu hình triển khai trên cụm EKS Singapore và Tokyo qua Argo CD.
   - **Tuyệt đối không để CI của repo app2 chạy `kubectl apply` trực tiếp vào production cluster.**

---

## 5. Công Nghệ Sử Dụng (Tech Stack)

- **Đám Mây & Mạng:** AWS VPC (Multi-AZ), Subnets Public/Private, NAT Gateway, Internet Gateway, Inter-Region VPC Peering, Route Tables, Security Groups.
- **Định Tuyến Toàn Cầu:** AWS Global Accelerator (Anycast Static IPs, BGP Anycast Routing, Endpoint Groups, Health Checks qua ALB Target Groups `/health`).
- **Container & Điều Phối:** Amazon EKS, Managed Node Groups, AWS Load Balancer Controller (Target-type: IP), Amazon ECR (Cross-Region Replication từ SG sang Tokyo).
- **Cơ Sở Dữ Liệu:** Amazon Aurora PostgreSQL-Compatible Global Database (Physical Storage Replication Engine).
- **Quản Lý Bí Mật:** AWS Secrets Manager (Multi-Region Secret Replication) + External Secrets Operator (ESO) + IAM Roles for Service Accounts (IRSA).
- **GitOps:** Argo CD (Kustomize Base & Overlays, Auto-Sync, Self-Healing, Pruning).
- **Quan Sát & Giám Sát:** Amazon CloudWatch Metric Alarms, Prometheus, Grafana, Alertmanager.
- **Công Cụ Tự Động Hóa Diễn Tập:** Bash test scripts đo đạc RPO/RTO tuần tự thời gian thực.

---

## 6. Mục Tiêu Phục Hồi Thảm Họa (DR Targets)

> [!IMPORTANT]
> **Các chỉ số dưới đây là mục tiêu thiết kế (Targets), không phải kết quả đã đạt được khi chưa trải qua kiểm thử thực tế:**
> - **RTO (Recovery Time Objective):** `< 5 phút` (Kể từ khi sự cố xảy ra cho tới khi request ghi đầu tiên hoàn tất trên Tokyo: $T_5 - T_0$).
> - **RPO (Recovery Point Objective):** `< 30 giây` (Độ chênh lệch transaction tối đa trước khi xảy ra thảm họa, đo đạc qua kịch bản Continuous Writer).
>
> Bằng chứng đo đạc thực nghiệm sẽ được ghi nhận tại [LAB 17 - Đánh Giá & Đo Đạc RTO/RPO](docs/labs/17-rto-rpo-test.md).

---

## 7. Bộ Scripts Tự Động Hóa (Automation & DR Tooling)

Thư mục [`scripts/`](scripts/) cung cấp bộ công cụ tự động hóa hoàn chỉnh phục vụ CI/CD Handoff và diễn tập DR:

- [`scripts/update-image-tag.sh`](scripts/update-image-tag.sh): Cập nhật commit SHA tag cho từng component trong Kustomize base và tự động chạy `kubectl kustomize` kiểm thử render cho cả Singapore và Tokyo overlay.
  ```bash
  ./scripts/update-image-tag.sh backend-2 abcdef123
  ```
- [`scripts/dr/rpo-writer.sh`](scripts/dr/rpo-writer.sh): Kịch bản Continuous Writer liên tục gửi các transaction tuần tự (`SEQ-000001`, `SEQ-000002`...) mỗi giây vào Global Accelerator và ghi nhận mốc commit thành công cuối cùng trước khi sập vùng chính.
  ```bash
  ./scripts/dr/rpo-writer.sh "http://<GLOBAL_ACCELERATOR_IP>"
  ```
- [`scripts/dr/rpo-check.sh`](scripts/dr/rpo-check.sh): Truy vấn marker lớn nhất đã có mặt tại Tokyo sau thăng cấp, đối chiếu độ lệch bản ghi và tính toán chính xác chỉ số RPO thực tế.
  ```bash
  ./scripts/dr/rpo-check.sh "http://<GLOBAL_ACCELERATOR_IP>"
  ```

---

## 8. Lộ Trình Thực Hành Labs (Complete Lab Roadmap)

Hệ thống tài liệu hướng dẫn từng bước chi tiết (click-by-click) trên AWS Console được tổ chức tuần tự:

| STT | Tên bài Lab | Mô tả tóm tắt | Liên kết tài liệu |
|:---:|---|---|:---:|
| **00** | Chuẩn bị môi trường & OIDC | Thiết lập CLI tools, OIDC Provider, IAM Role với trust condition nghiêm ngặt | [LAB 00](docs/labs/00-prerequisites.md) |
| **01** | Amazon ECR Đa Vùng | Tạo 4 ECR repos, Tag Immutability, Cross-Region Replication SG $\rightarrow$ Tokyo | [LAB 01](docs/labs/01-ecr-multi-region.md) |
| **02** | Hạ Tầng Mạng VPC Singapore | VPC `10.10.0.0/16`, 4 Subnets Multi-AZ, IGW, NAT GW, Tags | [LAB 02](docs/labs/02-networking-singapore.md) |
| **03** | Hạ Tầng Mạng VPC Tokyo | VPC `10.20.0.0/16`, 4 Subnets Multi-AZ, NAT GW, Tags | [LAB 03](docs/labs/03-networking-tokyo.md) |
| **04** | Kết Nối Đa Vùng VPC Peering | Tạo Peering liên vùng phục vụ admin/metrics federation, cấu hình Route Tables | [LAB 04](docs/labs/04-cross-region-networking.md) |
| **05** | Khởi Tạo EKS Singapore | EKS Cluster `dr-sg-eks`, Managed Node Group trong Private Subnet | [LAB 05](docs/labs/05-eks-singapore.md) |
| **06** | Khởi Tạo EKS Tokyo Standby | EKS Cluster `dr-tokyo-eks`, Chế độ Cost-Saving vs DR Benchmark | [LAB 06](docs/labs/06-eks-tokyo.md) |
| **07** | AWS Load Balancer Controller | Thiết lập IRSA, cài đặt Helm Controller tạo Public ALBs | [LAB 07](docs/labs/07-aws-load-balancer-controller.md) |
| **08** | Aurora Global Database | Khởi tạo Aurora PostgreSQL SG Writer, Tokyo Secondary Replica, 4 endpoints | [LAB 08](docs/labs/08-aurora-global-database.md) |
| **09** | Quản Lý Bí Mật Đa Vùng | Secrets Manager Replication + External Secrets Operator (chỉ cấp backend-3) | [LAB 09](docs/labs/09-secrets-manager.md) |
| **10** | Argo CD và GitOps | Cài đặt Argo CD, Application đồng bộ Kustomize Overlays | [LAB 10](docs/labs/10-argocd-gitops.md) |
| **11** | Triển Khai Microservices app2 | Triển khai Frontend (3000), Backend-1 (8081), Backend-2 (8082), Backend-3 (8083) | [LAB 11](docs/labs/11-deploy-app2.md) |
| **12** | AWS Global Accelerator | Thiết lập Anycast IP, Traffic Dial, ALB Target Group health `/health` | [LAB 12](docs/labs/12-global-accelerator.md) |
| **13** | Giám Sát & Quan Sát DR | CloudWatch Alarms (`HealthyHostCount`, `AuroraGlobalDBReplicationLag`) | [LAB 13](docs/labs/13-observability.md) |
| **14** | Diễn Tập Planned Switchover | Hoán đổi vai trò có kế hoạch với RPO = 0 (Zero Data Loss) | [LAB 14](docs/labs/14-planned-switchover.md) |
| **15** | Diễn Tập Unplanned Failover | Mô phỏng sập vùng có kiểm soát, đo thời gian $T_0 \dots T_5$, chống Split-Brain | [LAB 15](docs/labs/15-unplanned-failover.md) |
| **16** | Khôi Phục Ngược (Failback) | Kiểm tra điều kiện ổn định 30 phút, Canary Traffic Shift về lại SG | [LAB 16](docs/labs/16-failback.md) |
| **17** | Đánh Giá & Đo Đạc RTO/RPO | Chạy Continuous Writer, lập Evidence Report chính thức | [LAB 17](docs/labs/17-rto-rpo-test.md) |
| **18** | Dọn Dẹp Tài Nguyên | Thứ tự hủy tài nguyên chuẩn xác tránh khóa phụ thuộc, đưa chi phí về $0 | [LAB 18](docs/labs/18-cleanup.md) |

---

## 9. Cẩm Nang Vận Hành Khẩn Cấp (Operational Runbooks)

Dành cho đội ngũ trực chiến SRE / DevOps khi xử lý sự cố trong môi trường sản xuất:
- [Runbook: DR Failover to Tokyo](docs/runbooks/failover.md) - Hướng dẫn chuyển vùng khẩn cấp từng bước, cơ chế chống Split-Brain.
- [Runbook: DR Failback to Singapore](docs/runbooks/failback.md) - Hướng dẫn đưa hệ thống trở lại vùng chính an toàn, quy tắc ổn định 30 phút.
- [Runbook: Aurora Database Recovery](docs/runbooks/database-recovery.md) - Chiến lược endpoints, xử lý đứt gãy replication, reconciliation.
- [Runbook: Bảng Kiểm Sự Cố (Incident Checklist)](docs/runbooks/incident-checklist.md) - Quy trình War Room, phân vai IC/Ops/DBA và truyền thông sự cố.

---

## 10. Cảnh Báo Chi Phí Vận Hành (Cost Disclaimer)

> [!CAUTION]
> Hạ tầng Multi-Region tiêu tốn nhiều tài nguyên có phí tính theo giờ. Ước tính chi phí duy trì khoảng **$400 - $450/tháng** (tham khảo, có thể thay đổi theo bảng giá AWS):
> - 2 Cụm EKS Control Planes: ~$146/tháng
> - 2 NAT Gateways: ~$65/tháng
> - 2 Application Load Balancers: ~$33/tháng
> - 1 AWS Global Accelerator: ~$18/tháng
> - 3 Aurora PostgreSQL Instances (SG & Tokyo): ~$158/tháng
> 
> **Khuyến nghị:** Khi hoàn thành bài thực hành, hãy luôn tuân thủ [LAB 18 - Dọn Dẹp Tài Nguyên](docs/labs/18-cleanup.md) để giải phóng các tài nguyên tính phí và release Elastic IPs.

---

## 11. Trạng Thái Hiện Tại Của Dự Án (Current Project Status)

Bảng theo dõi tiến độ hoàn thiện nền tảng:

- [x] Thiết kế Kiến trúc Multi-Region & Tài liệu kỹ thuật
- [x] Xây dựng bộ 19 bài Labs thực hành chi tiết trên AWS Console
- [x] Soạn thảo bộ 4 Runbooks vận hành sự cố tiêu chuẩn
- [x] Thiết kế cấu trúc GitOps Desired State (`gitops/app2/`) hoàn toàn khớp với application contract thật
- [x] Bộ công cụ kiểm thử tự động đo đạc RPO/RTO tuần tự (`scripts/`)
- [ ] Triển khai thực tế trên AWS Console:
  - [ ] Networking (VPC, Subnets, IGW, NAT GW, Peering)
  - [ ] ECR Multi-Region Replication
  - [ ] EKS Clusters & Managed Node Groups
  - [ ] Aurora PostgreSQL Global Database
  - [ ] GitOps (Argo CD & External Secrets Operator)
  - [ ] AWS Global Accelerator
  - [ ] Observability (CloudWatch, Prometheus, Grafana)
- [ ] Diễn tập thực tế DR & Đo lường RTO/RPO được chứng thực
- [ ] Tự động hóa toàn bộ hạ tầng bằng Terraform (Terraform Migration)
