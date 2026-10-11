# AWS Multi-Region Disaster Recovery Platform - Architecture Overview

## 1. Giới thiệu tổng quan (Introduction)

Dự án **AWS Multi-Region Disaster Recovery Platform** được thiết kế nhằm xây dựng một hệ thống phân tán đa vùng (Multi-Region) có tính sẵn sàng cao (High Availability) và khả năng phục hồi sau thảm họa (Disaster Recovery - DR) với thời gian gián đoạn tối thiểu (**RTO < 5 phút**, **RPO < 30 giây**).

Hệ thống triển khai ứng dụng thương mại điện tử / microservices `app2` (gồm 1 frontend và 3 backend services) trên nền tảng AWS EKS kết hợp AWS Global Accelerator và Amazon Aurora PostgreSQL Global Database.

### Thông tin cơ bản:
- **Primary Region (Vùng chính):** `ap-southeast-1` (Singapore) - Chịu toàn bộ lưu lượng sản xuất thông thường, cấu hình nhiều replica, Aurora Writer.
- **DR Region (Vùng dự phòng):** `ap-northeast-1` (Tokyo) - Chạy ở chế độ **Warm Standby** (sẵn sàng ngay với số lượng replica nhỏ hơn), Aurora Secondary (Read Replica cross-region), sẵn sàng nhận traffic và scale tức thì khi có sự cố.
- **Chiến lược DR:** **Warm Standby** (tối ưu hóa giữa chi phí và thời gian khôi phục RTO/RPO).

---

## 2. Sơ đồ kiến trúc tổng thể (High-Level Architecture Diagram)

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
 (Managed Node Groups: 2-6)                        (Managed Node Groups: 1-6)
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
             | (Low Latency Storage Replication < 1s)          |
             v                                                 v
   [ app2-sg-db Cluster ]                            [ app2-tokyo-db Cluster ]
     (PRIMARY WRITER)                                    (READ-ONLY REPLICA)
```

---

## 3. Các thành phần chính trong kiến trúc (Key Architecture Components)

| Thành phần | Singapore (`ap-southeast-1`) | Tokyo (`ap-northeast-1`) | Vai trò trong hệ thống |
|---|---|---|---|
| **VPC & Mạng** | `dr-sg-vpc` (`10.10.0.0/16`) | `dr-tokyo-vpc` (`10.20.0.0/16`) | Mạng cô lập Multi-AZ, 2 Public subnets, 2 Private subnets |
| **Cross-Region Peering** | `dr-sg-vpc` <--> `dr-tokyo-vpc` | VPC Peering kết nối bảo mật nội bộ phục vụ backup/admin |
| **Container Registry** | ECR (`app2-*`) Primary | ECR (`app2-*`) Replicated | ECR Cross-Region Replication tự động đồng bộ image SHA tag |
| **Kubernetes Cluster** | `dr-sg-eks` | `dr-tokyo-eks` | EKS Managed Cluster chạy node trong private subnet |
| **Node Groups** | `dr-sg-workers` (Min 2, Desired 2, Max 6) | `dr-tokyo-workers` (Min 1/2, Desired 1/2, Max 6) | Managed Node Group trên EC2 x86/ARM trong Private Subnet |
| **Ingress Controller** | AWS Load Balancer Controller | AWS Load Balancer Controller | Tự động tạo và quản lý Public Application Load Balancers |
| **Cơ sở dữ liệu** | `app2-sg-db` (Primary Cluster) | `app2-tokyo-db` (Secondary Cluster) | Aurora PostgreSQL Global Database (asynchronous replication) |
| **Quản lý bí mật** | Secrets Manager (`app2/database`) | Secrets Manager (Replication) | Multi-Region Secret Replication + External Secrets Operator |
| **GitOps Engine** | Argo CD trên `dr-sg-eks` | Argo CD trên `dr-tokyo-eks` | Đồng bộ desired state tự động từ repo `aws-multi-region-dr-platform` |
| **Global Traffic Routing**| AWS Global Accelerator Endpoint Group (SG) | AWS Global Accelerator Endpoint Group (Tokyo) | Chuyển hướng traffic toàn cầu cực nhanh (< 30s) bằng Anycast IP |
| **Observability** | CloudWatch, Prometheus, Grafana | CloudWatch, Prometheus, Grafana | Giám sát trạng thái pod, latency, 5xx, replication lag và RTO/RPO |

---

## 4. Mô hình DR Warm Standby

### Trạng thái hoạt động bình thường (Normal Operation):
1. **Lưu lượng mạng:** Toàn bộ người dùng truy cập qua 2 IP tĩnh của Global Accelerator. Traffic dial dẫn 100% về Endpoint Group Singapore ALB.
2. **Compute:** 
   - Singapore: Chạy full tải (mỗi service 2 replicas, tổng cộng 8 pods phân bổ đều 2 AZ).
   - Tokyo: Chạy warm standby (mỗi service 1 replica để giữ ấm Pod, test connectivity và cache bộ nhớ).
3. **Database:**
   - Singapore giữ quyền **Primary Writer**. Toàn bộ dữ liệu ghi và đọc được xử lý tại Singapore.
   - Storage volume của Aurora tự động sao chép vật lý không đồng bộ (asynchronous replication) sang Tokyo. Độ trễ sao chép được đo lường thực tế qua CloudWatch metric `AuroraGlobalDBReplicationLag` (thường dưới 1 giây, cam kết mục tiêu thiết kế RPO < 30 giây, không phải SLA cố định).
4. **Secret & Image:**
   - Image từ CI được push về ECR Singapore và tự động sao chép sang Tokyo.
   - Database secret trong AWS Secrets Manager Singapore tự động replicate sang Tokyo (chỉ cấp cho backend-3).

### Khi xảy ra sự cố vùng Singapore (Regional Outage / Failover):
1. **Phát hiện lỗi (Detection):** Global Accelerator health check hoặc hệ thống giám sát CloudWatch/Alertmanager phát hiện Singapore không phản hồi.
2. **Chuyển hướng Traffic:** Global Accelerator phát hiện ALB Singapore Unhealthy và tự động chuyển routing sang ALB Tokyo.
3. **Thăng cấp Database (DB Promotion):** Kích hoạt Aurora Global Database switchover (hoặc failover) để biến cụm Tokyo thành **Primary Writer**.
4. **Scale Compute:** Tokyo HPA hoặc Argo CD scale số lượng Pod từ 1 lên mức production để đáp ứng toàn bộ traffic.
5. **Đo đạc RTO/RPO:** Đo thời gian phục hồi dịch vụ (RTO) và mức độ mất mát dữ liệu (RPO).

---

## 5. Mục tiêu phục hồi (RTO / RPO Targets)

> [!IMPORTANT]
> **RTO & RPO là mục tiêu thiết kế (Targets), không phải kết quả khẳng định trước khi kiểm thử thực tế.** Kết quả chỉ được công nhận sau khi hoàn thành đo đạc tại Lab 17.

- **RTO (Recovery Time Objective):** `< 5 phút`
  - Thời gian từ khi sự cố xảy ra ($T_0$) cho đến khi request ghi đầu tiên thành công trên vùng Tokyo ($T_5$).
- **RPO (Recovery Point Objective):** `< 30 giây`
  - Khoảng thời gian chênh lệch giữa transaction cuối cùng được commit thành công ở Singapore trước sự cố so với bản ghi còn nguyên vẹn tại Tokyo sau thăng cấp.

---

## 6. Lộ trình triển khai (Implementation Roadmap)

1. **Phase 1: Chuẩn bị & Quản lý Container Image (Labs 00 - 01)**: Cấu hình OIDC, CI/CD và ECR Multi-Region Replication.
2. **Phase 2: Xây dựng nền tảng Mạng Multi-Region (Labs 02 - 04)**: Thiết lập VPC Singapore, VPC Tokyo và Cross-Region Peering.
3. **Phase 3: Cụm EKS & Ingress Controller (Labs 05 - 07)**: Khởi tạo EKS Singapore, EKS Tokyo và AWS Load Balancer Controller.
4. **Phase 4: Dữ liệu & Bảo mật Tập trung (Labs 08 - 09)**: Triển khai Aurora PostgreSQL Global Database và Secrets Manager Multi-Region.
5. **Phase 5: GitOps & Triển khai Ứng dụng app2 (Labs 10 - 11)**: Cấu hình Argo CD và triển khai kiến trúc 4 microservices app2.
6. **Phase 6: Định tuyến Toàn cầu & Giám sát (Labs 12 - 13)**: Thiết lập AWS Global Accelerator và bộ giải pháp Observability toàn diện.
7. **Phase 7: Diễn tập DR & Đo đạc RTO/RPO (Labs 14 - 17)**: Planned Switchover, Unplanned Failover, Failback và đo nghiệm RTO/RPO.
8. **Phase 8: Dọn dẹp & Tối ưu hóa Chi phí (Lab 18)**: Quy trình hủy tài nguyên an toàn tránh phát sinh chi phí ngoài ý muốn.
9. **Phase 9: Tương lai - Tự động hóa bằng Infrastructure as Code (Terraform)**.
