# Luồng Khắc phục Thảm họa (Disaster Recovery Flow)

## Máy Trạng thái Hạ tầng (Infrastructure State Machine)

```mermaid
stateDiagram-v2
    [*] --> NORMAL_SG_PRIMARY: Triển khai mặc định

    state NORMAL_SG_PRIMARY {
        [*] --> Aurora_SG_Writer
        [*] --> Storage_SG_RW
        note right of NORMAL_SG_PRIMARY
            Singapore: Traffic Dial 100%
            Tokyo: Traffic Dial 0% (Standby)
        end note
    }

    NORMAL_SG_PRIMARY --> PLANNED_SWITCHOVER: Kế hoạch bảo trì / Diễn tập DR
    state PLANNED_SWITCHOVER {
        Aurora_Switchover --> Zero_Data_Loss
        SnapMirror_Quiesce_Break --> Storage_Tokyo_RW
    }
    PLANNED_SWITCHOVER --> TOKYO_PRIMARY: Switchover thành công (RPO = 0)

    NORMAL_SG_PRIMARY --> UNPLANNED_FAILOVER: Sự cố thảm họa Singapore (T0)
    state UNPLANNED_FAILOVER {
        Fence_SG_GA_Dial_0 --> Emergency_Failover_RDS
        Emergency_SnapMirror_Break --> Loss_Acknowledged
    }
    UNPLANNED_FAILOVER --> TOKYO_PRIMARY_DEGRADED: Failover hoàn tất (Đo RPO/RTO)

    TOKYO_PRIMARY_DEGRADED --> FAILBACK_PREPARATION: Singapore khắc phục xong
    TOKYO_PRIMARY --> FAILBACK_PREPARATION: Chuẩn bị khôi phục

    state FAILBACK_PREPARATION {
        Rebuild_SG_Secondary --> Sync_Lag_Stable
        Reverse_SnapMirror_Resync --> Destination_SG_Updated
    }

    FAILBACK_PREPARATION --> NORMAL_SG_PRIMARY: Managed Switchover đảo chiều (Failback)
```

## 1. Chuyển đổi Chủ động có Kế hoạch (Planned Switchover)

1. Kiểm tra xác nhận cả hai Region đều khỏe mạnh, phiên bản database tương thích và replication lag `<= 1s` ổn định.
2. Thực hiện lệnh `switchover-global-cluster` trên RDS Console hoặc CLI sang cụm Tokyo.
3. Xác nhận chỉ duy nhất cụm Tokyo có vai trò `IsWriter: true` và topology đạt trạng thái `available`.
4. Điều chuyển Traffic dial trên Global Accelerator: Singapore = 0%, Tokyo = 100% cho các kết nối mới.
5. Kiểm tra EKS, ALB, Secret replica, Application endpoints và CloudWatch Alarms.

*Mục tiêu Planned Switchover là Zero Data Loss (RPO = 0).*

---

## 2. Kích hoạt Failover Khẩn cấp khi có Sự cố (Unplanned Failover)

1. **Incident Commander** tuyên bố Region Singapore gặp thảm họa không thể tiếp tục nhận write an toàn.
2. Ngay lập tức cô lập Ingress Singapore (Traffic dial = 0) và dừng container writer để triệt tiêu nguy cơ Split-Brain.
3. Kiểm tra hạ tầng Warm Standby tại Tokyo đảm bảo đủ năng lực tiếp nhận tải.
4. Kích hoạt **Managed Failover** trên RDS Console với sự phê duyệt chính thức chấp nhận rủi ro mất mát dữ liệu (*Acknowledge Data Loss*).
5. Nâng Traffic dial của Tokyo lên 100% trên Global Accelerator.
6. Xác minh hoạt động của hạ tầng tại Tokyo và ghi nhận dữ liệu bị mất (RPO quan sát).

---

## 3. Khôi phục Về Singapore (Failback)

1. Khắc phục sự cố tại Singapore, tái kết nối Singapore thành một cụm Secondary đồng bộ từ Primary Tokyo.
2. Quan sát độ trễ `AuroraGlobalDBReplicationLag` duy trì ổn định `<= 1s` và kiểm tra sức khỏe hạ tầng Singapore trực tiếp.
3. Thực hiện Managed Switchover đưa quyền Primary Writer trở lại Singapore (Zero Data Loss).
4. Khôi phục Traffic dial: Singapore = 100%, Tokyo = 0%.
5. Giữ Tokyo ở trạng thái Warm Standby lành mạnh để sẵn sàng cho các đợt diễn tập tiếp theo.

---

## 4. Kiểm soát Chống Phân nhánh Dữ liệu (Split-Brain Prevention)

- Tuyệt đối không bao giờ để hai cụm DB cùng nhận ghi độc lập tại một thời điểm rồi gộp lại.
- Giữ cụm Singapore cũ bị cô lập triệt để cho đến khi vai trò trong RDS Topology được phân định rõ ràng.
- Ứng dụng luôn sử dụng **Global Writer Endpoint** để tự động nhận diện writer mới sau switchover.
- Kiểm soát phân quyền IAM chặt chẽ đối với các API Failover / Switchover.
- Cấu hình auto-scaling và replicas trên Kubernetes phải được đồng bộ với GitOps Argo CD; tránh xung đột tự chữa lành (`selfHeal`).
- Phải cô lập file-service container và ngắt các kết nối NFS client tại Singapore trước khi thăng cấp Tokyo storage.
- Lệnh `snapmirror break` là một ranh giới thăng cấp ghi (promotion boundary), không phải là lệnh kiểm tra sức khỏe thông thường.
- Coi Tokyo là nguồn chân lý duy nhất (Authoritative Source) sau khi đã failover; tuyệt đối không tự ý chạy resync ngược về Singapore khi chưa có biên bản phê duyệt chiều đồng bộ từ hai người.

---

## 5. Mốc Đo lường Thời gian (Measurement Boundaries)

Trục thời gian đo lường hạ tầng (Infrastructure Timeline):

```text
T0: Khai báo thảm họa / Bắt đầu diễn tập
T1: Endpoint chính bị khóa / Cô lập Ingress thành công
T2: Endpoint kiểm thử tại Tokyo trả về HTTP 200 thành công
T3: Cơ sở dữ liệu Tokyo (Aurora Writer) và Storage (FSx ONTAP RW) sẵn sàng nhận ghi
T4: Request ghi dữ liệu / tệp tin đầu tiên tại Tokyo thành công
T5: Toàn bộ hai khối lượng công việc (DB & Storage) hoạt động ổn định và sẵn sàng phục vụ
```

- **RTO Thực tế** = $T_5 - T_0$.
- **RPO Thực tế** = Độ lệch giữa bản ghi cuối cùng client ghi nhận tại Singapore và dữ liệu phục hồi thành công tại Tokyo. Chi tiết tham khảo tại [LAB 26](../labs/26-unified-dr-test.md).
