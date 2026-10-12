# Luồng Triển khai Ứng dụng (Deployment Flow)

## 1. Giai đoạn 1 Hiện tại (Current Phase 1)

Chưa kích hoạt luồng triển khai tự động cho ứng dụng `app2`:
- Argo CD đã được cài đặt nhưng chưa kích hoạt tự động đồng bộ Application.
- Kho chứa Amazon ECR và quy tắc Cross-region replication đã sẵn sàng.
- Các tệp cấu hình tại `gitops/app2` và script `scripts/update-image-tag.sh` được lưu giữ để phục vụ cho Giai đoạn 2.
- Các tệp cấu hình `gitops/infra-validation` được áp dụng thủ công để kiểm chứng sức khỏe Ingress, ALB và EKS.

---

## 2. Kiến trúc Mục tiêu Giai đoạn 2 (Target Phase 2 Flow)
 
```mermaid
flowchart TD
    subgraph Dev["Nhà phát triển / Git Repo"]
        Commit["Git Commit (Source code app2)"]
        GitOps_Repo["GitOps Repository (gitops/app2)"]
    end

    subgraph CI["CI Pipeline (GitHub Actions)"]
        Build["Build Container Image"]
        Test["Unit & Integration Tests"]
        Tag["Tag Image với Git Commit SHA"]
    end

    subgraph Registry["Amazon ECR Registry"]
        ECR_SG["ECR Private Repo (Singapore)\n`app2-*`"]
        ECR_Tokyo["ECR Private Repo (Tokyo)\n(Replication tự động)"]
    end

    subgraph CD["GitOps CD Engine (Argo CD)"]
        Argo_SG["Argo CD Singapore (dr-sg-eks)"]
        Argo_Tokyo["Argo CD Tokyo (dr-tokyo-eks)"]
    end

    subgraph EKS["Kubernetes Workloads"]
        Pods_SG["EKS Singapore Pods (Primary Active)"]
        Pods_Tokyo["EKS Tokyo Pods (Warm Standby)"]
    end

    Commit --> Build --> Test --> Tag
    Tag -->|Push Image| ECR_SG
    ECR_SG ===|ECR Cross-Region Replication| ECR_Tokyo

    Tag -->|Update Image Tag PR| GitOps_Repo
    GitOps_Repo -->|Sync manifests| Argo_SG
    GitOps_Repo -->|Sync manifests (Overlays)| Argo_Tokyo

    Argo_SG -->|Deploy| Pods_SG
    Argo_Tokyo -->|Deploy| Pods_Tokyo
    Pods_SG -.->|Pull Image| ECR_SG
    Pods_Tokyo -.->|Pull Image| ECR_Tokyo
```

---

## 3. Ranh giới Artifacts Bất biến (Artifact Boundaries)

- **Source Artifact:** Mã nguồn ứng dụng được checkout tại một Git commit hash cụ thể, bất biến.
- **Build Artifact:** Container image được định danh duy nhất bằng digest và Git Commit SHA.
- **Deployment Artifact:** Trạng thái mong muốn (Desired State) trong Kubernetes/Kustomize đã được review và trỏ chính xác vào image tag bất biến trên.

> [!WARNING]
> **Tuyệt đối không sử dụng tag `latest`.** Không cho phép CI chạy trực tiếp lệnh `kubectl apply` vào production cluster nhằm bảo toàn tính toàn vẹn của mô hình GitOps.

---

## 4. Quản lý Trạng thái DR qua GitOps (GitOps and DR State)

Giai đoạn 2 sẽ mã hóa trạng thái hoạt động bình thường (Normal) và thảm họa (DR) dưới dạng khai báo (Declarative):
- Commit số lượng replica mong muốn cho Region đang active.
- Duy trì các thư mục Kustomize overlays đã được rà soát cho tình huống DR và kích hoạt thông qua Git commit.
- Khi cần ứng phó sự cố khẩn cấp: Tạm dừng chế độ tự động đồng bộ (Suspend automated sync), thực hiện điều chỉnh khẩn cấp đã được duyệt, sau đó tiến hành đối chiếu (reconcile) cập nhật lại Git ngay lập tức.
- **Anti-pattern cấm kỵ:** Không chạy lệnh `kubectl scale` thủ công khi Argo CD đang bật tính năng `selfHeal=true`, vì Argo CD sẽ tự động rollback trạng thái của bạn về giá trị trên Git!

---

## 5. Quy trình Quay lui (Rollback)

1. Phát hiện sự cố triển khai thông qua tình trạng sức khỏe của Pods, ALB Target Group hoặc Application metrics.
2. Dừng quá trình promotion hoặc thực hiện Git Revert trạng thái mong muốn trong kho GitOps.
3. Argo CD tự động đồng bộ cụm EKS quay trở lại phiên bản artifact bất biến liền trước đó.
4. Kiểm tra xác nhận lại ALB Targets, Pods, Logs và các chỉ số nghiệp vụ.
5. Lưu trữ bằng chứng phục vụ phân tích nguyên nhân gốc rễ (Post-Mortem).
