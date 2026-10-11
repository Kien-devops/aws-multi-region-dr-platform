# Luồng Phục Hồi Thảm Họa Đa Vùng (Disaster Recovery Flow)

Tài liệu này định nghĩa chi tiết cơ chế nhận diện sự cố, chuyển đổi lưu lượng, thăng cấp cơ sở dữ liệu và khôi phục hoạt động bình thường giữa hai vùng AWS: **Singapore (Primary)** và **Tokyo (DR Warm Standby)**.

---

## 1. Sơ đồ Luồng Phục Hồi (DR Failover & Failback State Machine)

```text
+-----------------------------------------------------------------------------------+
| TRẠNG THÁI BÌNH THƯỜNG (NORMAL OPERATION)                                         |
| - Singapore: Traffic 100%, EKS Replicas 2, Aurora Writer                          |
| - Tokyo: Warm Standby, EKS Replicas 1, Aurora Read Replica (Lag < 1s)             |
+-----------------------------------------------------------------------------------+
                                       |
                                       | T0: Sự cố xảy ra tại Singapore (Regional Outage / Disaster)
                                       v
+-----------------------------------------------------------------------------------+
| BƯỚC 1: PHÁT HIỆN SỰ CỐ (T1 - DETECTION)                                          |
| - Global Accelerator Health Check liên tiếp thất bại trên Singapore ALB           |
| - CloudWatch Alarms kích hoạt cảnh báo tổng thể                                   |
+-----------------------------------------------------------------------------------+
                                       |
                   +-------------------+-------------------+
                   |                                       |
                   v (Khoảng 20 - 30 giây)                 v (Thao tác vận hành / Automation)
+--------------------------------------+   +--------------------------------------+
| BƯỚC 2: CHUYỂN HƯỚNG TRAFFIC (T2)    |   | BƯỚC 3: THĂNG CẤP DATABASE (T3)      |
| - Global Accelerator cô lập SG       |   | - Kích hoạt Failover / Switchover    |
| - Bắt đầu đưa user traffic tới Tokyo |   | - Aurora Tokyo DB Cluster trở thành  |
| - Backend Tokyo nhận HTTP requests   |   |   Primary Writer                     |
+--------------------------------------+   +--------------------------------------+
                   |                                       |
                   +-------------------+-------------------+
                                       |
                                       v
+-----------------------------------------------------------------------------------+
| BƯỚC 4: SCALE WORKLOAD VÀ XÁC THỰC PHỤC HỒI (T4 & T5)                            |
| - HPA / Argo CD scale Pods tại Tokyo từ 1 lên mức Production (2-6 replicas)       |
| - T4: Xác thực đọc dữ liệu (Read) thành công từ ứng dụng tại Tokyo               |
| - T5: Xác thực ghi dữ liệu (Write) thành công vào Aurora Tokyo Writer             |
| ===> ĐO ĐẠC RTO = T5 - T0, RPO = Dữ liệu chênh lệch trước và sau sự cố            |
+-----------------------------------------------------------------------------------+
                                       |
                                       | Khi Singapore khắc phục xong hoàn toàn & ổn định
                                       v
+-----------------------------------------------------------------------------------+
| BƯỚC 5: KHÔI PHỤC NGƯỢC (FAILBACK TO SINGAPORE)                                  |
| 1. Kiểm tra Singapore EKS và Pods sẵn sàng                                        |
| 2. Kiểm tra Aurora Singapore đồng bộ ngược từ Tokyo (Replication healthy)         |
| 3. Thực hiện Planned Switchover (Zero Data Loss) đưa Writer về lại Singapore       |
| 4. Điều chỉnh Global Accelerator đưa 100% traffic về Singapore                   |
| 5. Thu hẹp Tokyo về Warm Standby (1 replica)                                      |
+-----------------------------------------------------------------------------------+
```

---

## 2. Chi tiết Dòng Thời gian Đo đạc (RTO & RPO Timeline)

Để đánh giá chính xác hiệu quả của nền tảng DR theo đúng chuẩn SRE và ISO/IEC 27031, quy trình kiểm thử ghi nhận chính xác 6 mốc thời gian:

| Mốc thời gian | Tên sự kiện | Ý nghĩa kỹ thuật | Phương thức xác định |
|---|---|---|---|
| **$T_0$** | **Failure Injected** | Thời điểm lỗi bắt đầu xảy ra trên hệ thống chính | Timestamp khi kịch bản giả lập sự cố được kích hoạt (ví dụ: tắt pods / scale down / chặn network) |
| **$T_1$** | **Failure Detected** | Hệ thống giám sát phát hiện ra sự cố | Timestamp khi Global Accelerator chuyển trạng thái Singapore ALB thành `UNHEALTHY` hoặc CloudWatch Alarm nhảy trạng thái `ALARM` |
| **$T_2$** | **Traffic at Tokyo** | Lưu lượng người dùng đầu tiên chạm tới ALB Tokyo | Timestamp của access log đầu tiên trên Tokyo ALB hoặc phản hồi curl chứa header/body chỉ định vùng Tokyo |
| **$T_3$** | **DB Promoted** | Cơ sở dữ liệu Tokyo chính thức giữ quyền ghi (Writer) | Timestamp khi API Aurora trả về trạng thái `available` cho cụm Tokyo với vai trò Primary Writer |
| **$T_4$** | **First Read Success**| Request đọc dữ liệu đầu tiên thành công tại Tokyo | Kiểm tra HTTP GET `/api/v1/catalog` trả về HTTP 200 từ pod Tokyo |
| **$T_5$** | **First Write Success**| Transaction ghi dữ liệu đầu tiên thành công tại Tokyo | Kiểm tra HTTP POST `/api/v1/orders` ghi thành công bản ghi mới vào cơ sở dữ liệu |

### Công thức tính toán:
$$RTO = T_5 - T_0$$
*Giải thích:* Toàn bộ thời gian gián đoạn nghiệp vụ ghi của hệ thống kể từ khi bắt đầu gặp sự cố đến khi ứng dụng sẵn sàng nhận đơn hàng mới tại Tokyo.

$$RPO = \text{Bản ghi commit cuối tại SG trước } T_0 - \text{Bản ghi hiện diện tại Tokyo sau } T_3$$
*Giải thích:* Nếu bản ghi test mang mã `DR_TEST_RECORD_001` được commit lúc $T_0 - 2\text{s}$ và sau khi thăng cấp Tokyo vẫn đọc được bản ghi này nguyên vẹn, thì $RPO \approx \text{Replication Lag} < 1\text{s}$ (đáp ứng mục tiêu thiết kế $< 30\text{s}$).

---

## 3. So sánh Planned Switchover và Unplanned Failover

| Tiêu chí | Planned Switchover (Chuyển đổi theo kế hoạch) | Unplanned Failover (Cứu hộ khẩn cấp) |
|---|---|---|
| **Ngữ cảnh sử dụng** | Bảo trì định kỳ vùng Singapore, diễn tập DR theo quý | Singapore gặp thảm họa bất khả kháng, sập data center hoặc mất mạng diện rộng |
| **Tính toàn vẹn dữ liệu** | **RPO = 0 (Hoàn toàn không mất dữ liệu)**. Aurora đảm bảo flush toàn bộ transaction logs sang Tokyo trước khi hoán đổi vai trò. | **RPO $\ge$ 0 (Có thể mất vài giây dữ liệu)** tương ứng với khoảng trễ replication lag vật lý tại thời điểm xảy ra sự cố. |
| **Thao tác trên Aurora** | Sử dụng tính năng native `Switchover` trên Aurora Global Database. Singapore tự động chuyển thành Secondary. | Sử dụng tính năng `Failover` (Detach/Promote). Cụm Tokyo được tách khỏi Global Database thành cụm độc lập. |
| **Rủi ro Split-Brain** | Không có (AWS tự động phối hợp chuyển giao vai trò tuần tự). | Cần kiểm soát nghiêm ngặt tránh để cả hai vùng cùng nhận lệnh ghi khi vùng chính khôi phục mạng đột ngột. |

---

## 4. Nguyên tắc Chống Lỗi Split-Brain (Dual-Primary Prevention)

Một trong những thảm họa lớn nhất trong kiến trúc Multi-Region là **Split-Brain** (hai vùng cùng tưởng mình là Primary và đồng thời ghi dữ liệu khác nhau, dẫn tới xung đột và mất toàn vẹn dữ liệu).

Để ngăn chặn Split-Brain, nền tảng DR tuân thủ 3 nguyên tắc:
1. **Fencing ở tầng Mạng:** Khi quyết định failover sang Tokyo, Security Group của Aurora Singapore phải bị thu hồi quyền truy cập hoặc EKS Singapore phải được scale down.
2. **Aurora Global Database Single Writer:** Cơ chế phân tán của Aurora Global Database chỉ cho phép tồn tại duy nhất 1 Primary Cluster được ghi dữ liệu vào shared storage.
3. **Quy trình Failback có Kiểm Soát:** Không bao giờ tự động chuyển quyền ghi về Singapore ngay khi Singapore vừa bật lại. Luôn phải đợi kiểm tra tính toàn vẹn và thực hiện **Planned Switchover** ngược từ Tokyo về Singapore.
