# Sơ Đồ Cơ Chế Aurora Global Database Replication & DR

Tài liệu này mô tả chi tiết cơ chế nhân bản dữ liệu và quy trình chuyển đổi vai trò (Switchover/Failover) của **Amazon Aurora Global Database (PostgreSQL)** giữa Singapore và Tokyo.

```mermaid
sequenceDiagram
    autonumber
    actor Operator as "Kỹ Sư Vận Hành / DR Orchestrator"
    participant SG_Writer as "Singapore Aurora (app2-sg-db)<br/>[Writer]"
    participant Aurora_Engine as "Aurora Storage Engine<br/>(Cross-Region Replication)"
    participant Tokyo_Reader as "Tokyo Aurora (app2-tokyo-db)<br/>[Reader]"
    participant Tokyo_App as "Tokyo Backend-3 Pod"

    Note over SG_Writer,Tokyo_Reader: TRẠNG THÁI BÌNH THƯỜNG (NORMAL OPERATION)
    SG_Writer->>Aurora_Engine: Ghi log giao dịch (Write Transaction)
    Aurora_Engine-->>Tokyo_Reader: Sao chép vật lý trực tiếp ở tầng Storage (< 1s Lag)
    Tokyo_Reader-->>Tokyo_App: Cho phép đọc (Read-Only)

    Note over Operator,Tokyo_App: KÍCH HOẠT DISASTER RECOVERY (PLANNED SWITCHOVER)
    Operator->>Tokyo_Reader: Gọi API rds.switchover_global_cluster(Target: Tokyo)
    Note over SG_Writer: T0: Bắt đầu ngắt kết nối ghi tại Singapore
    SG_Writer->>SG_Writer: Đóng các giao dịch ghi đang mở, đồng bộ hết redo log sang Tokyo
    SG_Writer->>Aurora_Engine: Flush toàn bộ dữ liệu đang chờ (Zero In-flight Loss)
    Aurora_Engine->>Tokyo_Reader: Đồng bộ triệt để dữ liệu cuối cùng

    Note over SG_Writer,Tokyo_Reader: BƯỚC ĐỔI VAI TRÒ (ROLE SWAP)
    SG_Writer->>SG_Writer: Chuyển thành Reader Cluster (IsWriter: False)
    Tokyo_Reader->>Tokyo_Reader: Chuyển thành Global Writer Cluster (IsWriter: True)
    Note over Tokyo_Reader: T_DB_WRITER: 38.471s kể từ T0 (Xác nhận qua RDS API)

    Note over Tokyo_App,Tokyo_Reader: XÁC MINH HOẠT ĐỘNG ỨNG DỤNG (APPLICATION VERIFICATION)
    Tokyo_App->>Tokyo_Reader: Gửi giao dịch ghi thử nghiệm (INSERT Order Probe)
    Tokyo_Reader-->>Tokyo_App: Xác nhận ghi thành công (200 OK, Commit ACID)
    Tokyo_App->>Tokyo_Reader: Đọc lại đơn hàng vừa ghi (Read-after-Write Consistency)
    Tokyo_Reader-->>Tokyo_App: Trả về bản ghi hợp lệ
    Note over Tokyo_App: T_DB_APP: 47.428s kể từ T0 (Database Service RTO Đạt Yêu Cầu)
```

---

## Điểm Khác Biệt Giữa Planned Switchover và Unplanned Failover

| Đặc Điểm | Planned Switchover (Đã Thực Nghiệm) | Unplanned Failover (Kịch Bản Khẩn Cấp) |
|---|---|---|
| **Mục đích** | Bảo trì định kỳ, diễn tập DR có kế hoạch | Vùng chính gặp sự cố thảm họa vật lý mất điện/mạng hoàn toàn |
| **Bảo toàn dữ liệu** | **Không mất mát (Zero Data Loss)**: Chờ đồng bộ hết buffer | Có thể mất một khoảng dữ liệu nhỏ tương ứng với lag time (< 1s) |
| **Cụm ban đầu** | Tự động chuyển thành Reader Cluster để tiếp tục nhân bản ngược | Bị cô lập (Fenced); cần thao tác xóa hoặc tái tích hợp sau sự cố |
| **Lệnh AWS API** | `rds:SwitchoverGlobalCluster` | `rds:FailoverGlobalCluster` |
