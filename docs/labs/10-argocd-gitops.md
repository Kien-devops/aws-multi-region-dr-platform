# LAB 10 - Thiết Lập Argo CD và Quy Trình GitOps Đa Vùng (Argo CD GitOps)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Cài đặt Argo CD trên cả hai cụm EKS `dr-sg-eks` (Singapore) và `dr-tokyo-eks` (Tokyo) trong namespace `argocd`.
2. Phân định rõ ràng trách nhiệm giữa kho mã nguồn (`app2`) và kho trạng thái khát vọng (`aws-multi-region-dr-platform`).
3. Khởi tạo 2 Argo CD Applications độc lập:
   - `app2-singapore`: Đồng bộ từ thư mục `gitops/app2/overlays/singapore`.
   - `app2-tokyo`: Đồng bộ từ thư mục `gitops/app2/overlays/tokyo`.
4. Cấu hình chính sách đồng bộ tự động (Automated Sync, Prune, Self-Heal) và hiểu tại sao không được dùng `kubectl apply` trực tiếp từ GitHub Actions lên production cluster.

---

## Architecture impact

```text
[ GitOps Repository: Kien-devops/aws-multi-region-dr-platform ]
  └── gitops/app2/
      ├── base/ (Manifests dùng chung)
      └── overlays/
          ├── singapore/ (kustomization.yaml: Replicas 2)
          └── tokyo/     (kustomization.yaml: Replicas 1 - Warm Standby)
                   |
         +---------+---------+
         | (Git Poll / Webhook)
         v                   v
[ Argo CD Singapore ]    [ Argo CD Tokyo ]
  (dr-sg-eks)              (dr-tokyo-eks)
         |                   |
         v (K8s Reconcile)   v (K8s Reconcile)
[ Production Pods ]      [ Warm Standby Pods ]
(Replicas: 2x4 = 8)      (Replicas: 1x4 = 4)
```

---

## Resource naming

- Kubernetes Namespace: `argocd`
- Argo CD Singapore Application: `app2-singapore`
- Argo CD Tokyo Application: `app2-tokyo`
- Git Repository URL: `https://github.com/Kien-devops/aws-multi-region-dr-platform.git`
- Target Revision: `HEAD` (hoặc branch `main`)

---

## Các Bước Triển Khai Chi Tiết

### Bước 1: Cài Đặt Argo CD Trên Cụm Singapore
```bash
# Đổi context sang Singapore
kubectl config use-context singapore

# Tạo namespace argocd
kubectl create namespace argocd

# Cài đặt Argo CD manifest chính thức
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.4/manifests/install.yaml

# Đợi tất cả pods khởi động thành công
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
```

### Bước 2: Cài Đặt Argo CD Trên Cụm Tokyo
```bash
# Đổi context sang Tokyo
kubectl config use-context tokyo

# Tạo namespace argocd
kubectl create namespace argocd

# Cài đặt Argo CD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.4/manifests/install.yaml

# Đợi Argo CD sẵn sàng
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
```

### Bước 3: Lấy Mật Khẩu Admin Mặc Định của Argo CD
Mật khẩu khởi tạo ban đầu được lưu trong secret `argocd-initial-admin-secret`:
```bash
# Lấy mật khẩu tại Singapore:
kubectl --context singapore -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode
echo ""

# Lấy mật khẩu tại Tokyo:
kubectl --context tokyo -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode
echo ""
```

*(Bạn có thể mở giao diện Web UI bằng lệnh: `kubectl --context singapore port-forward svc/argocd-server -n argocd 8080:443`, truy cập `https://localhost:8080` với user `admin`).*

### Bước 4: Tạo Argo CD Application Manifests

Tạo Application cho cụm Singapore (`argocd/application-singapore.yaml`):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app2-singapore
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/Kien-devops/aws-multi-region-dr-platform.git
    targetRevision: main
    path: gitops/app2/overlays/singapore
  destination:
    server: https://kubernetes.default.svc
    namespace: app2
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Tạo Application cho cụm Tokyo (`argocd/application-tokyo.yaml`):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app2-tokyo
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/Kien-devops/aws-multi-region-dr-platform.git
    targetRevision: main
    path: gitops/app2/overlays/tokyo
  destination:
    server: https://kubernetes.default.svc
    namespace: app2
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Bước 5: Áp Dụng Application Lên Từng Cụm
```bash
# Áp dụng lên cụm Singapore
kubectl --context singapore apply -f gitops/app2/argocd/application-singapore.yaml

# Áp dụng lên cụm Tokyo
kubectl --context tokyo apply -f gitops/app2/argocd/application-tokyo.yaml
```

---

## Configuration

| Thuộc tính | Cụm Singapore | Cụm Tokyo |
|---|---|---|
| **Application Name** | `app2-singapore` | `app2-tokyo` |
| **Source Path** | `gitops/app2/overlays/singapore` | `gitops/app2/overlays/tokyo` |
| **Destination Namespace** | `app2` | `app2` |
| **Prune** | `true` (Tự động xóa tài nguyên nếu bị xóa khỏi Git) | `true` |
| **Self-Heal** | `true` (Tự khôi phục nếu ai đó sửa bằng kubectl thủ công)| `true` |

---

## Security considerations

- **Không mở quyền truy cập cụm cho CI:** Tránh cấp token kubeconfig có quyền admin cho GitHub Actions Runners. Nếu GitHub Actions bị hack, kẻ tấn công cũng không thể xóa hay thao túng cluster vì không có kết nối vào API Server.
- **Pull-based Deployment Model:** Argo CD chạy bên trong mạng nội bộ của VPC, chỉ kéo (Pull) manifest từ GitHub qua cổng HTTPS 443 đi ra (Outbound). Không cần mở bất kỳ cổng Inbound nào từ bên ngoài Internet vào Kubernetes API Server.
- **Audit Trail:** Mọi thay đổi trên cluster đều bắt buộc phải là một Git commit, tạo nên lịch sử kiểm toán hoàn chỉnh (Git Commit History).

---

## Expected result

- Cả hai cụm đều có các thành phần Argo CD chạy trong namespace `argocd`.
- Ứng dụng `app2-singapore` và `app2-tokyo` hiển thị trạng thái `Synced` và `Healthy`.

---

## Verification

### Kiểm tra bằng CLI
```bash
# Kiểm tra trạng thái đồng bộ tại Singapore
kubectl --context singapore -n argocd get application app2-singapore
```
*Expected output:*
```text
NAME             SYNC STATUS   HEALTH STATUS
app2-singapore   Synced        Healthy
```

```bash
# Kiểm tra trạng thái đồng bộ tại Tokyo
kubectl --context tokyo -n argocd get application app2-tokyo
```
*Expected output:*
```text
NAME         SYNC STATUS   HEALTH STATUS
app2-tokyo   Synced        Healthy
```

---

## Troubleshooting

1. **Lỗi: Application ở trạng thái `ComparisonError: repository not found`:**
   - *Nguyên nhân:* Kho Git cấu hình là Private nhưng chưa khai báo SSH Key hoặc Personal Access Token trong Argo CD Repositories.
   - *Cách sửa:* Đặt repo ở chế độ Public hoặc vào Settings -> Repositories trong Argo CD để add thông tin xác thực.
2. **Lỗi: `Unknown field spec.template...` khi đồng bộ:**
   - *Nguyên nhân:* Lỗi cú pháp trong file manifest Kustomize.
   - *Cách sửa:* Chạy thử lệnh `kubectl kustomize gitops/app2/overlays/singapore` ở máy trạm cục bộ để kiểm tra cú pháp trước khi commit lên Git.
3. **Lỗi: Pod bị tạo lại liên tục do Self-Heal flapping:**
   - *Nguyên nhân:* Có sự xung đột giữa Kustomize manifest và một mutating webhook hoặc HPA đang tự động sửa trường replica.
   - *Cách sửa:* Thêm cấu hình `ignoreDifferences` trong Application spec cho trường `.spec.replicas` nếu sử dụng HPA.

---

## Cost note

- Argo CD là phần mềm mã nguồn mở hoàn toàn miễn phí.
- Chạy dưới dạng pods tiêu tốn khoảng 500m CPU và 1GB RAM trên cụm EKS hiện có, không phát sinh chi phí dịch vụ AWS mới.

---

## Next step

Tiếp tục chuyển sang [LAB 11 - Triển Khai Microservices app2 Đa Vùng](11-deploy-app2.md).
