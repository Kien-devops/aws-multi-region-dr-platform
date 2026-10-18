# Sơ Đồ Kiến Trúc Đa Vùng (Multi-Region Architecture)

Tài liệu này mô tả tổng thể kiến trúc hệ thống phân tán giữa hai vùng AWS: **Singapore (`ap-southeast-1`)** (Primary Region) và **Tokyo (`ap-northeast-1`)** (Disaster Recovery Region).

```mermaid
flowchart TB
    subgraph Users ["Client Traffic"]
        Client["Người Dùng / External Probes"]
    end

    subgraph Edge ["Global Routing Tier"]
        AGA["AWS Global Accelerator\n(Static Anycast IPs: 75.2.109.112 / 99.83.197.80)"]
    end

    subgraph SG ["Primary Region: Singapore (ap-southeast-1)"]
        subgraph SG_VPC ["VPC: 10.10.0.0/16"]
            SG_ALB["Application Load Balancer\n(Internet-Facing)"]

            subgraph SG_EKS ["EKS Cluster: dr-sg-eks"]
                SG_Frontend["app2-frontend (Node.js)"]
                SG_B1["app2-backend-1 (Order Intake)"]
                SG_B2["app2-backend-2 (Inventory)"]
                SG_B3["app2-backend-3 (Order Process)"]
                SG_FS["app2-file-service (Storage I/O)"]
            end

            subgraph SG_Storage ["Storage Tier"]
                SG_Aurora[("Aurora PostgreSQL Global DB\n(app2-sg-db - Primary Writer)")]
                SG_FSx["FSx for NetApp ONTAP\n(dr-sg-svm : drdata - RW)"]
            end
        end
    end

    subgraph Tokyo ["Recovery Region: Tokyo (ap-northeast-1)"]
        subgraph Tokyo_VPC ["VPC: 10.20.0.0/16"]
            Tokyo_ALB["Application Load Balancer\n(Internet-Facing)"]

            subgraph Tokyo_EKS ["EKS Cluster: dr-tokyo-eks (Warm Standby)"]
                Tokyo_Frontend["app2-frontend (Standby)"]
                Tokyo_B1["app2-backend-1 (Standby)"]
                Tokyo_B2["app2-backend-2 (Standby)"]
                Tokyo_B3["app2-backend-3 (Standby)"]
                Tokyo_FS["app2-file-service (Standby)"]
            end

            subgraph Tokyo_Storage ["Storage Tier (DR)"]
                Tokyo_Aurora[("Aurora PostgreSQL Cluster\n(app2-tokyo-db - Reader / Target Writer)")]
                Tokyo_FSx["FSx for NetApp ONTAP\n(dr-tokyo-svm : dr_data_dr - DP / RW upon Failover)"]
            end
        end
    end

    %% Client Routing
    Client --> AGA
    AGA -->|Traffic Dial: 100%| SG_ALB
    AGA -.->|Traffic Dial: 0% -> 100% (DR)| Tokyo_ALB

    %% Ingress to Services
    SG_ALB --> SG_Frontend
    SG_ALB --> SG_B1
    SG_ALB --> SG_FS
    SG_Frontend --> SG_B1
    SG_B1 --> SG_B2
    SG_B2 --> SG_B3
    SG_B3 --> SG_Aurora
    SG_FS -->|NFSv4.1 Mount| SG_FSx

    Tokyo_ALB --> Tokyo_Frontend
    Tokyo_ALB --> Tokyo_B1
    Tokyo_ALB --> Tokyo_FS
    Tokyo_Frontend --> Tokyo_B1
    Tokyo_B1 --> Tokyo_B2
    Tokyo_B2 --> Tokyo_B3
    Tokyo_B3 --> Tokyo_Aurora
    Tokyo_FS -->|NFSv4.1 Mount| Tokyo_FSx

    %% Replication Streams
    SG_Aurora ==>|Aurora Storage-Level Physical Async Replication (<1s lag)| Tokyo_Aurora
    SG_FSx ==>|SnapMirror Async Volume Replication (Cross-Cluster Inter-SVM)| Tokyo_FSx

    %% Inter-region Peering
    SG_VPC <===>|Inter-Region VPC Peering (10.10.0.0/16 <-> 10.20.0.0/16)| Tokyo_VPC
```

---

## Các Thành Phần Chính Trong Kiến Trúc

1. **Tầng Định Tuyến Toàn Cầu (Global Routing Tier)**:
   - Sử dụng **AWS Global Accelerator (AGA)** với hai địa chỉ Anycast IP tĩnh nhằm định tuyến lưu lượng người dùng và chuyển dịch lưu lượng (Traffic Dial) khi thực hiện chuyển đổi vùng.
2. **Tầng Ứng Dụng (Kubernetes Microservices)**:
   - Triển khai trên **Amazon EKS** đồng bộ giữa hai vùng bằng **GitOps (Argo CD)**.
   - Kiến trúc 5 microservices: Frontend, Backend-1, Backend-2, Backend-3 (kết nối cơ sở dữ liệu), và File-Service (kết nối hệ thống tệp tin NFS).
3. **Tầng Cơ Sở Dữ Liệu (Relational Database)**:
   - Sử dụng **Amazon Aurora Global Database (PostgreSQL compatible)** với cơ chế replication trực tiếp tại tầng storage engine, giúp độ trễ nhân bản thường dưới 1 giây.
4. **Tầng Lưu Trữ File Doanh Nghiệp (File Storage)**:
   - Sử dụng **FSx for NetApp ONTAP** với tính năng **SnapMirror** nhân bản giữa hai Storage Virtual Machine (SVM) qua Inter-Region VPC Peering.
