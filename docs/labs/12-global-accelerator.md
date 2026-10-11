# LAB 12 - Định Tuyến Toàn Cầu Với AWS Global Accelerator (AWS Global Accelerator)

## Goal

Sau khi hoàn thành lab này, người học sẽ:
1. Tạo một Standard AWS Global Accelerator với **2 địa chỉ IP tĩnh Anycast độc lập toàn cầu**.
2. Thiết lập Listener tiếp nhận lưu lượng HTTP (Port 80).
3. Cấu hình hai Endpoint Groups tại Singapore (`ap-southeast-1`) và Tokyo (`ap-northeast-1`), gắn kết tương ứng vào hai Application Load Balancers đã tạo tại Lab 11.
4. **Hiểu bản chất chính xác của cơ chế định tuyến và chuyển vùng:**
   - Phân biệt rõ giữa cân bằng tải theo vị trí địa lý (Geo-Proximity Routing) và chuyển vùng chủ động/thụ động (Active/Passive Warm Standby).
   - Nắm rõ cách Global Accelerator kiểm tra sức khỏe của ALB: **Sử dụng trạng thái sức khỏe ngầm của ALB Target Groups** (Target Group Health Check tại `/health`), không phải probe tùy biến như đối với EC2.
   - So sánh hai phương án cấu hình DR Warm Standby: **Option A (Controlled Dial Switching)** và **Option B (Health-Driven Automatic Failover)**.

---

## Architecture impact

```text
                                [ CLIENT TRÊN TOÀN CẦU ]
                                            |
                                            v
               [ 2 Anycast Static IPs: e.g., 75.2.x.x & 99.83.y.y ]
                     (AWS Global Edge Locations / PoPs Toàn Cầu)
                                            |
                         [ AWS Global Accelerator: app2-global ]
                                            |
            +-------------------------------+-------------------------------+
            |                                                               |
            v (Traffic Dial: 100%)                                          v (Traffic Dial: 0% hoặc Standby)
+---------------------------------------+       +---------------------------------------+
| ENDPOINT GROUP SINGAPORE              |       | ENDPOINT GROUP TOKYO                  |
| Region: ap-southeast-1                |       | Region: ap-northeast-1                |
| Target: Singapore ALB                 |       | Target: Tokyo ALB                     |
| Health State: Kế thừa từ ALB TG       |       | Health State: Kế thừa từ ALB TG       |
| Target Group Path: /health            |       | Target Group Path: /health            |
+---------------------------------------+       +---------------------------------------+
            | (Bình thường: 100% Traffic)                   | (Khi Failover: Bật 100% Traffic)
            v                                               v
   [ Singapore Production EKS ]                    [ Tokyo Warm Standby EKS ]
```

---

## Resource naming

- Accelerator Name: `app2-global`
- Accelerator Type: **Standard**
- Listener: Port `80` (TCP)
- Endpoint Group 1:
  - Region: `ap-southeast-1` (Singapore)
  - Endpoint: Singapore ALB (`app2-ingress`)
  - Traffic Dial: `100%`
  - Weight: `128`
- Endpoint Group 2:
  - Region: `ap-northeast-1` (Tokyo)
  - Endpoint: Tokyo ALB (`app2-ingress`)
  - Traffic Dial: `0%` (trong Option A) hoặc `100%` (trong Option B)
  - Weight: `128`

---

## AWS Console Steps

### Bước 1: Khởi Tạo Accelerator
1. Mở AWS Management Console -> Dịch vụ **AWS Global Accelerator**.
2. Nhấn **Create accelerator**.
3. **Step 1: Enter accelerator details:**
   - **Accelerator name:** `app2-global`.
   - **Accelerator type:** Chọn **Standard**.
   - **IP address type:** **IPv4**.
   - Nhấn **Next**.
4. **Step 2: Add listeners:**
   - **Ports:** Nhập `80`.
   - **Protocol:** **TCP**.
   - **Client affinity:** **None**.
   - Nhấn **Next**.

### Bước 2: Thêm Endpoint Groups
1. **Step 3: Add endpoint groups:**
   - **Endpoint group 1 (Singapore):**
     - Region: **ap-southeast-1 (Singapore)**.
     - Traffic dial: Đặt `100%`.
   - Nhấn **Add endpoint group** bên dưới:
   - **Endpoint group 2 (Tokyo):**
     - Region: **ap-northeast-1 (Tokyo)**.
     - Traffic dial: Đặt `0%` nếu theo Option A (Warm Standby có kiểm soát), hoặc `100%` nếu theo Option B.
   - Nhấn **Next**.

### Bước 3: Gắn Kết ALBs vào Endpoint Groups
1. **Step 4: Add endpoints:**
   - Tại Endpoint group `ap-southeast-1`:
     - Nhấn **Add endpoint** -> Endpoint type: **Application Load Balancer** -> Chọn ALB của Singapore (`k8s-app2-app2ingr-...`).
     - Weight: `128`.
   - Tại Endpoint group `ap-northeast-1`:
     - Nhấn **Add endpoint** -> Endpoint type: **Application Load Balancer** -> Chọn ALB của Tokyo.
     - Weight: `128`.
   - Nhấn **Create accelerator**.
2. Đợi 3 - 5 phút cho đến khi **Status** chuyển sang **Deployed**.
3. Lưu lại 2 IP Anycast và DNS Name của Accelerator.

---

## Bản Chất Kỹ Thuật Về Định Tuyến và Kiểm Tra Sức Khỏe

### 1. Cơ Chế Health Check Khi Endpoint Là Application Load Balancer
> [!IMPORTANT]
> - Đối với endpoint loại ALB, AWS Global Accelerator **không tự mở một kết nối HTTP riêng để probe vào pod**, mà nó **kế thừa trực tiếp trạng thái sức khỏe tổng hợp (Health State)** từ các Target Groups của chính ALB đó.
> - Do đó, tính năng phát hiện sự cố của Global Accelerator phụ thuộc trực tiếp vào việc Target Group của ALB kiểm tra đúng endpoint `/health` của các container trên EKS.
> - Khi toàn bộ targets của Singapore ALB bị lỗi (0 Healthy Hosts), ALB sẽ tự báo trạng thái `Unhealthy` lên Global Accelerator.

### 2. Hai Thiết Kế Warm Standby Cho Global Accelerator

| Tiêu chí | **Option A: Controlled Dial Switching (Khuyến nghị cho Lab)** | **Option B: Health-Driven Automatic Failover** |
|---|---|---|
| **Cấu hình Traffic Dial** | Singapore: `100%`, Tokyo: `0%` | Singapore: `100%`, Tokyo: `100%` |
| **Bình thường** | 100% traffic vào Singapore. Tokyo hoàn toàn không nhận traffic công cộng. | Client ở gần Singapore vào SG, client ở gần Tokyo vào Tokyo. |
| **Hành vi khi có sự cố** | SRE hoặc script DR kích hoạt lệnh API tăng Traffic Dial của Tokyo lên `100%`. | Global Accelerator tự động cô lập Singapore khi phát hiện Unhealthy và đẩy toàn bộ traffic sang Tokyo trong 20-30s. |
| **Ưu điểm** | Kiểm soát 100% luồng dữ liệu, tránh việc client tại Nhật Bản bị phân tán vào Tokyo khi DB Tokyo đang là Read-Only. | Hoàn toàn tự động, không cần con người can thiệp. |

---

## Verification

```bash
AGA_IP="<GLOBAL_ACCELERATOR_STATIC_IP>"

# Kiểm tra phản hồi trả về từ Singapore
curl -s http://$AGA_IP/health | jq .
```
*Expected output:*
```json
{
  "status": "ok",
  "service": "frontend",
  "region": "ap-southeast-1"
}
```

---

## Troubleshooting

1. **Lỗi: Cả hai vùng cùng nhận traffic trong khi muốn cô lập Tokyo:**
   - *Nguyên nhân:* Để Traffic Dial của Tokyo là 100% nên các client có latency gần Tokyo hơn sẽ được định tuyến vào Tokyo.
   - *Cách sửa:* Chỉnh Traffic Dial của Tokyo về `0%` trong điều kiện hoạt động bình thường theo Option A.
2. **Lỗi: Endpoint ALB hiển thị Unhealthy trên Global Accelerator Console:**
   - *Nguyên nhân:* Target Group của ALB bên dưới đang có 0 healthy hosts vì cấu hình sai health check path (`/healthz` thay vì `/health`).
   - *Cách sửa:* Kiểm tra Target Group trên EC2 Console, đảm bảo health check path là `/health`.
3. **Lỗi: Không thêm được ALB vào Endpoint:**
   - *Nguyên nhân:* ALB là loại internal hoặc chưa hoàn tất tạo.
   - *Cách sửa:* ALB phải là internet-facing.

---

## Cost note

- Phí cố định: ~$0.025/giờ ($\approx$ $18/tháng) + Premium Data Transfer fee (~$0.015 - $0.035/GB).

---

## Next step

Tiếp tục chuyển sang [LAB 13 - Thiết Lập Hệ Thống Quan Sát và Giám Sát DR](13-observability.md).
