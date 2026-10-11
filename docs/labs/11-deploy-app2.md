# LAB 11 - Triển Khai Bộ Microservices app2 Đa Vùng (Deploy app2)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Triển khai trọn bộ 4 microservices của ứng dụng `app2` trên cả hai cụm Kubernetes EKS theo đúng cấu hình cổng và endpoint thực tế:
   - `app2-frontend`: Container Port 3000, Service Port 80 (Routes: `GET /`, `GET /health`).
   - `app2-backend-1`: Container Port 8081, Service Port 8081 (Routes: `GET /health`, `GET /api/v1/info`).
   - `app2-backend-2`: Container Port 8082, Service Port 8082 (Routes: `GET /health`, `GET /api/v1/info`, `GET /api/v1/catalog`).
   - `app2-backend-3`: Container Port 8083, Service Port 8083 (Routes: `GET /health`, `GET /api/v1/info`, `GET /api/v1/orders`, `POST /api/v1/orders`).
2. Thiết lập chính sách phân bổ bản sao (Replica Policy) và phục hồi:
   - Singapore (Primary): **2 replicas** mỗi dịch vụ, tích hợp **PodDisruptionBudget (minAvailable: 1)** và **TopologySpreadConstraints (Zone Anti-Affinity)** để bảo đảm tính sẵn sàng cao trong vùng (In-Region HA).
   - Tokyo (Warm Standby): **1 replica** mỗi dịch vụ, không dùng PDB để tránh chặn thao tác drain node khi chỉ có 1 node.
3. Cấu hình Ingress và AWS Load Balancer Controller với Target Group Health Check thống nhất tại `/health`.
4. Inject biến môi trường vùng (`AWS_REGION`): `ap-southeast-1` cho Singapore và `ap-northeast-1` cho Tokyo để xác thực chuyển vùng chính xác.

---

## Architecture impact

```text
===================================================================================
               VÙNG SINGAPORE (dr-sg-vpc)         VÙNG TOKYO (dr-tokyo-vpc)
===================================================================================
                      |                                   |
                      v                                   v
             [ Singapore Public ALB ]             [ Tokyo Public ALB ]
                      | (Health: /health)                 | (Health: /health)
             [ Ingress: app2-ingress ]           [ Ingress: app2-ingress ]
                      |                                   |
        +-------------+-------------+       +-------------+-------------+
        |             |             |       |             |             |
        v             v             v       v             v             v
  [frontend (2)]  [bk-1 (2)]   [bk-2/3 (2)] [frontend (1)] [bk-1 (1)]   [bk-2/3 (1)]
  (Port: 3000)    (Port: 8081) (Port: 8082/8083) (Port: 3000) (Port: 8081) (Port: 8082/8083)
  (PDB + Spread)  (PDB + Spread) (PDB + Spread) (No PDB)    (No PDB)    (No PDB)
                                    |                                   |
                                    v (Chỉ backend-3)                   v (Chỉ backend-3)
                            [ app2-db-secret ]                  [ app2-db-secret ]
                                    |                                   |
                                    v                                   v
                        [ Aurora Singapore Writer ]         [ Aurora Tokyo Secondary ]
```

---

## Resource naming

- Kubernetes Namespace: `app2`
- Deployments & Services:
  - `app2-frontend` (Port 80 -> TargetPort 3000)
  - `app2-backend-1` (Port 8081 -> TargetPort 8081)
  - `app2-backend-2` (Port 8082 -> TargetPort 8082)
  - `app2-backend-3` (Port 8083 -> TargetPort 8083)
- Ingress: `app2-ingress` (Health Path: `/health`)

---

## Cấu Trúc Manifest GitOps (`gitops/app2/`)

```text
gitops/app2/
├── base/
│   ├── kustomization.yaml    (Quản lý logical images & initial tags)
│   ├── namespace.yaml
│   ├── frontend.yaml         (Node.js port 3000, /health)
│   ├── backend-1.yaml        (Node.js port 8081, /health, /api/v1/info)
│   ├── backend-2.yaml        (Node.js port 8082, /health, /api/v1/catalog)
│   ├── backend-3.yaml        (Node.js port 8083, DB secrets, /api/v1/orders)
│   └── ingress.yaml          (ALB Ingress, health path: /health)
└── overlays/
    ├── singapore/
    │   ├── kustomization.yaml (Replicas: 2, ECR SG Registry mapping, labels)
    │   ├── pdb.yaml           (PodDisruptionBudget minAvailable: 1)
    │   └── patches/
    │       └── workload-ha-patches.yaml (AWS_REGION=ap-southeast-1, topology spread)
    └── tokyo/
        ├── kustomization.yaml (Replicas: 1, ECR Tokyo Registry mapping, labels)
        └── patches/
            └── env-patches.yaml         (AWS_REGION=ap-northeast-1)
```

---

## Các Bước Triển Khai Thực Hiện

### Bước 1: Áp Dụng Manifests Bằng Kustomize
Nếu sử dụng Argo CD (đã cài ở Lab 10), Argo CD sẽ tự động đồng bộ.
Để xác thực cục bộ bằng CLI:

```bash
# Áp dụng cho cụm Singapore
kubectl --context singapore apply -k gitops/app2/overlays/singapore

# Áp dụng cho cụm Tokyo
kubectl --context tokyo apply -k gitops/app2/overlays/tokyo
```

### Bước 2: Kiểm Tra Trạng Thái Pods và In-Region HA
```bash
# Kiểm tra pods tại Singapore:
kubectl --context singapore -n app2 get pods -o wide
```
*Expected output:* Cả 8 pods đều ở trạng thái `Running (1/1)` và được phân bổ đều qua 2 worker nodes nhờ `topologySpreadConstraints`.

```bash
# Kiểm tra PodDisruptionBudget tại Singapore:
kubectl --context singapore -n app2 get pdb
```
*Expected output:* Cả 4 PDBs đều hiển thị `MIN AVAILABLE: 1` và `ALLOWED DISRUPTIONS: 1`.

```bash
# Kiểm tra pods tại Tokyo (Warm Standby):
kubectl --context tokyo -n app2 get pods -o wide
```
*Expected output:* Cả 4 pods đều ở trạng thái `Running (1/1)`.

### Bước 3: Lấy Địa Chỉ ALB Public của Từng Vùng
```bash
ALB_SG=$(kubectl --context singapore -n app2 get ingress app2-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB Singapore: $ALB_SG"

ALB_TOKYO=$(kubectl --context tokyo -n app2 get ingress app2-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB Tokyo: $ALB_TOKYO"
```

---

## Lưu Ý Quan Trọng Về Định Tuyến Đường Dẫn (Path Routing Caveat)

> [!IMPORTANT]
> **Hành vi của AWS ALB Ingress Controller:**
> - ALB Ingress không tự động cắt bỏ tiền tố đường dẫn (strip path prefix) khi chuyển tiếp gói tin tới Pod.
> - Nếu Ingress chuyển tiếp `/api/v1/orders` tới `app2-backend-3:8083`, thì máy chủ HTTP bên trong container backend-3 phải lắng nghe và xử lý chính xác đường dẫn `/api/v1/orders`.
> - Ứng dụng `app2` đã được cấu hình khớp 100% với các routing rules:
>   - `/` $\rightarrow$ `app2-frontend:80`
>   - `/api/v1/info` $\rightarrow$ `app2-backend-1:8081`
>   - `/api/v1/catalog` $\rightarrow$ `app2-backend-2:8082`
>   - `/api/v1/orders` $\rightarrow$ `app2-backend-3:8083`

---

## Verification

### Kiểm tra bằng cURL
```bash
# 1. Kiểm tra Frontend & Region của Singapore
curl -s http://$ALB_SG/health | jq .
```
*Expected output:*
```json
{
  "status": "ok",
  "service": "frontend",
  "region": "ap-southeast-1"
}
```

```bash
# 2. Kiểm tra Frontend & Region của Tokyo
curl -s http://$ALB_TOKYO/health | jq .
```
*Expected output:*
```json
{
  "status": "ok",
  "service": "frontend",
  "region": "ap-northeast-1"
}
```

```bash
# 3. Kiểm tra Backend-1 Info
curl -s http://$ALB_SG/api/v1/info | jq .

# 4. Kiểm tra Backend-2 Catalog
curl -s http://$ALB_SG/api/v1/catalog | jq .

# 5. Kiểm tra Backend-3 Orders
curl -s http://$ALB_SG/api/v1/orders | jq .
```

---

## Troubleshooting

1. **Lỗi: ALB Target Group báo lỗi Unhealthy với mã 404:**
   - *Nguyên nhân:* Health check path của Target Group bị cấu hình là `/healthz` hoặc `/` thay vì `/health`.
   - *Cách sửa:* Kiểm tra annotation `alb.ingress.kubernetes.io/healthcheck-path: /health` trong Ingress manifest.
2. **Lỗi: Backend-3 bị Crash khi không kết nối được PostgreSQL:**
   - *Nguyên nhân:* Secret `app2-db-secret` chưa được External Secrets Operator tạo hoặc Security Group chặn port 5432.
   - *Cách sửa:* Xem log bằng `kubectl -n app2 logs deployment/app2-backend-3`, kiểm tra lại Lab 08 và Lab 09.
3. **Lỗi: Pod bị Pending do TopologySpreadConstraints:**
   - *Nguyên nhân:* `whenUnsatisfiable: DoNotSchedule` trong khi cụm chỉ có 1 worker node khả dụng.
   - *Cách sửa:* Luôn cấu hình `whenUnsatisfiable: ScheduleAnyway` để Kubernetes vẫn lên lịch chạy pod nếu thiếu node đa AZ.

---

## Cost note

- Chi phí máy ảo nằm trong gói các worker node EC2 `t3.medium` hiện tại.

---

## Next step

Tiếp tục chuyển sang [LAB 12 - Định Tuyến Toàn Cầu Với AWS Global Accelerator](12-global-accelerator.md).
