# Luồng Triển Khai GitOps và CI/CD (Deployment Flow)

Tài liệu này giải thích chi tiết quy trình CI/CD và GitOps đồng bộ xuyên suốt từ kho mã nguồn ứng dụng (`app2`), đóng gói container image, sao chép đa vùng trên Amazon ECR, cho tới việc tự động đồng bộ hạ tầng Kubernetes trên hai cụm EKS bằng Argo CD.

---

## 1. Sơ đồ Luồng Triển Khai Tổng Thể (Deployment Flow Diagram)

```text
+-----------------------------------------------------------------------------------+
| 1. APPLICATION SOURCE CODE REPO (GitHub: Kien-devops/app2)                        |
+-----------------------------------------------------------------------------------+
   Developer Git Commit & Push (feature/PR or main)
         |
         v
   [ GitHub Actions CI Engine ]
         |
         +---> Paths filter phân tích thư mục thay đổi:
         |     - Chỉ chạy test & build cho component thay đổi (frontend, backend-1,2,3)
         |     - Nếu thay đổi 'shared/', kích hoạt build toàn bộ 4 components
         |
         +---> Bảo mật: GitHub OIDC Token Exchange qua AWS STS
         |     (Không dùng static AWS Access Key / Secret Key)
         |     Nhận temporary credentials gắn quyền IAM Role: GitHubActions-App2-ECRPush
         |
         +---> Docker Build & Tagging với commit SHA bất biến (e.g., app2-backend-2:a1b2c3d)
         |
         v
+-----------------------------------------------------------------------------------+
| 2. CONTAINER REGISTRY MULTI-REGION (Amazon ECR)                                   |
+-----------------------------------------------------------------------------------+
   [ ECR Singapore (ap-southeast-1) ]  <--- CI chỉ push duy nhất tới đây
         |
         | (AWS Native ECR Cross-Region Replication - không tốn compute của CI)
         v
   [ ECR Tokyo (ap-northeast-1) ]      <--- Sẵn sàng image cục bộ cho DR Cluster
         |
         v
+-----------------------------------------------------------------------------------+
| 3. GITOPS DESIRED STATE REPO (GitHub: Kien-devops/aws-multi-region-dr-platform)   |
+-----------------------------------------------------------------------------------+
   Cập nhật GitOps manifests với SHA tag mới (e.g., gitops/app2/base/... hoặc overlay)
         |
         +---------------------------------------+
         |                                       |
         v                                       v
+-------------------------------+       +-------------------------------+
| 4a. EKS SINGAPORE CLUSTER     |       | 4b. EKS TOKYO CLUSTER (DR)    |
+-------------------------------+       +-------------------------------+
  [ Argo CD Singapore ]                   [ Argo CD Tokyo ]
         |                                       |
         v (Sync Overlay Singapore)              v (Sync Overlay Tokyo)
  [ K8s Deployment Replicas: 2 ]          [ K8s Deployment Replicas: 1 ]
         |                                       |
         v                                       v
  Pull Image từ ECR Singapore             Pull Image từ ECR Tokyo (local latency)
```

---

## 2. Chi tiết 4 Giai đoạn Triển Khai (Phase-by-Phase Breakdown)

### Giai đoạn 1: Kiểm thử và Đóng gói (CI tại `app2`)
1. **Repository:** `Kien-devops/app2` chứa mã nguồn của:
   - `frontend/`
   - `services/backend-1/`
   - `services/backend-2/`
   - `services/backend-3/`
   - `shared/`
2. **Selective Component CI (Tối ưu hóa thời gian CI):**
   - Workflow sử dụng `on.push.paths` hoặc dynamic path evaluation.
   - Khi kỹ sư chỉ sửa đổi logic trong `services/backend-2/**`, hệ thống CI chỉ chạy unit test, linter và build Docker image cho `backend-2`. Các service khác được bỏ qua (skip), tiết kiệm tài nguyên GitHub Runners và giảm thời gian phản hồi.
   - Nếu có thay đổi tại thư mục dùng chung `shared/**`, toàn bộ 4 workflows sẽ tự động kích hoạt để đảm bảo tính tương thích.
3. **Bảo mật xác thực qua OIDC (OpenID Connect):**
   - GitHub Runner yêu cầu OIDC JWT token từ token provider của GitHub (`token.actions.githubusercontent.com`).
   - Sử dụng action `aws-actions/configure-aws-credentials` để gửi OIDC token sang AWS STS thông qua API `sts:AssumeRoleWithWebIdentity`.
   - IAM Role `GitHubActions-App2-ECRPush` kiểm tra Trust Policy ràng buộc đúng `repo:Kien-devops/app2:ref:refs/heads/main`.
   - Tuyệt đối không lưu trữ `AWS_ACCESS_KEY_ID` hay `AWS_SECRET_ACCESS_KEY` tĩnh trong GitHub Secrets.

### Giai đoạn 2: Phân phối Image Đa vùng (Amazon ECR Cross-Region Replication)
1. **Push một lần (Single-Region Push):**
   - CI Pipeline chỉ login và push image Docker tới ECR tại Singapore (`ap-southeast-1`).
   - Image được gán tag bất biến (Immutable Tag) là git commit SHA đầy đủ hoặc ngắn gọn (ví dụ: `sha-7f2a1b9`).
2. **Sao chép tự động ở tầng hạ tầng AWS (Native Replication):**
   - ECR Private Registry cấu hình Replication Rule: khi có image mới với prefix `app2-` tại Singapore, AWS backend tự động replicate image layers sang kho lưu trữ tương ứng tại Tokyo (`ap-northeast-1`).
   - Lợi ích: CI không cần duy trì kết nối mạng sang nhiều vùng, giảm rủi ro network timeout, không cần cấp quyền IAM xuyên vùng phức tạp cho GitHub Actions.
   - Khi thảm họa xảy ra ở Singapore, Tokyo EKS kéo image trực tiếp từ Tokyo ECR mà không phụ thuộc vào ECR Singapore.

### Giai đoạn 3: Quản lý Trạng thái Khát vọng (GitOps Desired State)
1. **Kho lưu trữ cấu hình hạ tầng:**
   - Kho `Kien-devops/aws-multi-region-dr-platform` là Single Source of Truth chứa toàn bộ manifest Kubernetes của ứng dụng (Kustomize/Helm).
2. **Nguyên tắc phân định trách nhiệm:**
   - Không cho phép GitHub Actions của repo ứng dụng chạy lệnh `kubectl apply` trực tiếp vào production EKS cluster.
   - Thay vào đó, sau khi build xong image, CI cập nhật SHA tag vào file manifest trong repo GitOps thông qua commit hoặc pull request tự động.
   - Cấu trúc Kustomize cho phép tái sử dụng cấu hình chung tại thư mục `base/` và tinh chỉnh số lượng replica, environment variable riêng biệt qua `overlays/singapore/` và `overlays/tokyo/`.

### Giai đoạn 4: Đồng bộ trạng thái trên Kubernetes (Argo CD Synchronization)
1. **Argo CD Cụm Singapore:**
   - Trỏ vào overlay `gitops/app2/overlays/singapore`.
   - Giữ trạng thái mong muốn (Desired State) chạy full tải (2 replicas cho mỗi microservice).
2. **Argo CD Cụm Tokyo:**
   - Trỏ vào overlay `gitops/app2/overlays/tokyo`.
   - Giữ trạng thái Warm Standby (1 replica cho mỗi microservice).
3. **Cơ chế tự sửa đổi (Self-Healing & Pruning):**
   - Nếu có ai đó can thiệp thủ công (chạy `kubectl edit` hoặc xóa pod bất hợp lệ trên cluster), Argo CD sẽ phát hiện chênh lệch (Out of Sync) và tự động kéo trạng thái về đúng chuẩn đã định nghĩa trên Git.
