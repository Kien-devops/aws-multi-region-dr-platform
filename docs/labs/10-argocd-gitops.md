# LAB 10 - Điều kiện tiên quyết cho nền tảng Argo CD

> **Ranh giới giai đoạn:** Lab này chỉ cài Argo CD như một thành phần nền tảng. Không tạo `Application`, không đồng bộ `gitops/app2`, không triển khai app2.

## 1. Mục tiêu

Cài Argo CD độc lập trên `dr-sg-eks` và `dr-tokyo-eks`, xác minh GitOps control plane sẵn sàng cho Giai đoạn 2.

## 2. Thành phần sẽ xây dựng

- Namespace `argocd` trên hai cluster.
- Argo CD server, repository server, application controller và Redis.
- Truy cập quản trị tạm thời bằng `kubectl port-forward`.
- Không có Argo CD `Application` nào trong giai đoạn này.

## 3. Bối cảnh kiến trúc

```text
Git repository --HTTPS--> nền tảng Argo CD --Kubernetes API--> EKS
                              |
                              +-- Giai đoạn 1: đã cài, chưa đồng bộ ứng dụng
                              +-- Giai đoạn 2: bật Application của app2
```

Hai file `gitops/app2/argocd/application-*.yaml` là artifact của Giai đoạn 2. Không áp dụng chúng trong LAB 10.

## 4. Điều kiện tiên quyết

- Hoàn thành LAB 05-07.
- Context `singapore` và `tokyo` hoạt động.
- Máy trạm có `kubectl`, `helm`.
- Có quyền tạo namespace, CRD, ClusterRole và Deployment.

## 5. Quy ước đặt tên tài nguyên

| Tài nguyên | Giá trị |
|---|---|
| Namespace | `argocd` |
| Helm release | `argocd` |
| Contexts | `singapore`, `tokyo` |
| Application được hoãn | `app2-singapore`, `app2-tokyo` |

## 6. Các bước triển khai

### 6.1 Chọn phiên bản chart đã rà soát

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm search repo argo/argo-cd --versions | head
```

Ghi phiên bản đã rà soát thành `<ARGO_CD_CHART_VERSION>`. Không dùng phiên bản trôi nổi chưa được rà trong production.

### 6.2 Cài đặt tại Singapore

```bash
helm upgrade --install argocd argo/argo-cd \
  --kube-context singapore \
  --namespace argocd \
  --create-namespace \
  --version <ARGO_CD_CHART_VERSION> \
  --set configs.params.server\.insecure=false \
  --wait --timeout 10m
```

### 6.3 Cài đặt tại Tokyo

```bash
helm upgrade --install argocd argo/argo-cd \
  --kube-context tokyo \
  --namespace argocd \
  --create-namespace \
  --version <ARGO_CD_CHART_VERSION> \
  --set configs.params.server\.insecure=false \
  --wait --timeout 10m
```

### 6.4 Truy cập và cấu hình quản trị trên Argo CD Web UI

#### Bước 1: Truy cập Argo CD Singapore
1. Mở terminal, chạy lệnh port-forward dịch vụ `argocd-server` ra cổng máy trạm:

```bash
kubectl --context singapore -n argocd port-forward svc/argocd-server 8080:443
```

2. Mở một terminal khác, lấy mật khẩu quản trị khởi tạo (`argocd-initial-admin-secret`):

```bash
kubectl --context singapore -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode; echo
```

3. Mở trình duyệt web, truy cập địa chỉ: `https://localhost:8080`
   - Trình duyệt sẽ hiện cảnh báo bảo mật SSL do dùng Self-signed certificate -> Nhấp **Advanced** (Nâng cao) -> Chọn **Proceed to localhost (unsafe)** (Tiếp tục truy cập).
4. Tại màn hình đăng nhập Argo CD:
   - **Username**: Nhập `admin`.
   - **Password**: Dán chuỗi mật khẩu vừa giải mã ở bước 2.
   - Nhấp nút **Sign In**.
5. Đổi mật khẩu quản trị và xóa mật khẩu mặc định:
   - Trong thanh điều hướng bên trái, nhấp vào biểu tượng người dùng hoặc chọn **User Info**.
   - Nhấp nút **Update Password**.
   - Nhập mật khẩu hiện tại, sau đó nhập mật khẩu mới an toàn và xác nhận -> Nhấp **Save Password**.
   - Quay lại terminal, xóa secret khởi tạo để đảm bảo an toàn:

```bash
kubectl --context singapore -n argocd delete secret argocd-initial-admin-secret
```

#### Bước 2: Truy cập Argo CD Tokyo
1. Mở terminal mới, forward dịch vụ Argo CD Tokyo ra một cổng khác (ví dụ: `8081`):

```bash
kubectl --context tokyo -n argocd port-forward svc/argocd-server 8081:443
```

2. Lấy mật khẩu khởi tạo của Tokyo:

```bash
kubectl --context tokyo -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode; echo
```

3. Mở trình duyệt truy cập `https://localhost:8081`, đăng nhập `admin`, đổi mật khẩu và xóa secret khởi tạo tương tự như Singapore.

### 6.5 Xác nhận chưa triển khai ứng dụng

```bash
kubectl --context singapore -n argocd get applications.argoproj.io
kubectl --context tokyo -n argocd get applications.argoproj.io
```

Hai lệnh phải trả về không có resource. Không chạy:

```text
kubectl apply -f gitops/app2/argocd/application-singapore.yaml
kubectl apply -f gitops/app2/argocd/application-tokyo.yaml
```

## 7. Xác minh

```bash
kubectl --context singapore -n argocd get pods
kubectl --context tokyo -n argocd get pods
kubectl --context singapore -n argocd rollout status deployment/argocd-server --timeout=5m
kubectl --context tokyo -n argocd rollout status deployment/argocd-server --timeout=5m
```

Mọi pod bắt buộc phải ở trạng thái `Running` hoặc hoàn tất thành công. Số lượng Application phải bằng không.

## 8. Kết quả mong đợi

- Nền tảng Argo CD khỏe mạnh tại cả hai Region.
- Đã chứng minh truy cập UI/CLI qua local port-forward.
- Trạng thái vẫn là `ỨNG DỤNG CHƯA ĐƯỢC TRIỂN KHAI`.

## 9. Xử lý sự cố

- `ImagePullBackOff`: kiểm tra NAT route, DNS và HTTPS outbound.
- Pod `Pending`: tăng dung lượng node group Tokyo; Argo CD dùng lượng CPU/bộ nhớ đáng kể.
- Lỗi repository: bỏ qua tới Giai đoạn 2 trừ khi đang kiểm tra xác thực private repository; không tạo Application cho ứng dụng.
- Thiếu admin secret: secret có thể đã bị xóa sau lần đăng nhập đầu; đặt lại credential theo quy trình Argo CD chính thức.

## 10. Lưu ý bảo mật

- Giữ `argocd-server` ở loại `ClusterIP`; dùng port-forward trong lab.
- Không public admin UI qua ALB không có xác thực.
- Thay tài khoản admin tích hợp bằng SSO/RBAC trước production.
- Credential của repository phải nằm trong Kubernetes Secret/Secrets Manager, không nằm trong Git.
- Argo CD reconciliation có thể hoàn tác manual DR scaling. Giai đoạn 2 phải chọn chế độ DR do Git kiểm soát hoặc chủ động tạm dừng automated sync trong bài diễn tập có kiểm soát.

## 11. Lưu ý chi phí

Argo CD không có phí bản quyền nhưng các pod sử dụng dung lượng node EKS. Chế độ tiết kiệm tại Tokyo có thể cần node thứ hai trong lúc cài đặt.

## 12. Dọn dẹp / Quay lui

```bash
helm uninstall argocd --kube-context singapore -n argocd
helm uninstall argocd --kube-context tokyo -n argocd
kubectl --context singapore delete namespace argocd
kubectl --context tokyo delete namespace argocd
```

Chỉ chạy dọn dẹp khi chủ động quay lui lab này.

## 13. Bằng chứng cần thu thập

- Phiên bản Helm release trên hai cluster.
- Output `kubectl get pods -n argocd`.
- Ảnh Argo CD UI với không có Application.
- Output CLI chứng minh Argo CD chưa tạo namespace/workload app2.

## 14. Lab tiếp theo

Tiếp tục với [LAB 11 - Xác minh mức độ sẵn sàng của hạ tầng](11-infrastructure-readiness.md).
