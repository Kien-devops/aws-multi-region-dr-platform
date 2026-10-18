# Sơ Đồ Cơ Chế FSx ONTAP SnapMirror Replication & Promotion

Tài liệu này mô tả chi tiết cơ chế sao chép tệp tin đa vùng bằng **NetApp ONTAP SnapMirror** trên dịch vụ **Amazon FSx for NetApp ONTAP**, cùng quy trình kích hoạt chuyển đổi lưu trữ tệp tin (Storage Promotion).

```mermaid
sequenceDiagram
    autonumber
    actor Operator as "Kỹ Sư Vận Hành / DR Orchestrator"
    participant SG_SVM as "Singapore SVM (dr-sg-svm)<br/>Volume: drdata [RW]"
    participant SnapMirror as "ONTAP SnapMirror Engine<br/>(Cluster Peer qua VPC Peering)"
    participant Tokyo_SVM as "Tokyo SVM (dr-tokyo-svm)<br/>Volume: dr_data_dr [DP]"
    participant Tokyo_Pod as "Tokyo EKS Pod (app2-file-service)"

    Note over SG_SVM,Tokyo_SVM: TRẠNG THÁI BÌNH THƯỜNG (REPLICATION BASELINE)
    SG_SVM->>SG_SVM: Ghi nhận file vào volume (RW)
    SnapMirror->>Tokyo_SVM: Đồng bộ định kỳ (State: snapmirrored, Healthy: true)
    Tokyo_SVM-->>Tokyo_Pod: Mount NFSv4.1 qua IP 10.20.11.230 (/mnt/dr-data)
    Note over Tokyo_Pod: Trạng thái Volume là DP (Data Protection) -> Chỉ cho phép đọc

    Note over Operator,Tokyo_Pod: KÍCH HOẠT DISASTER RECOVERY (STORAGE PROMOTION)
    Operator->>Operator: T0: Xác nhận cutoff giao dịch Singapore
    Operator->>Tokyo_SVM: Kích hoạt Lambda dr-fsx-failover-promote-tokyo
    Note over Operator: T6: Bắt đầu ngắt SnapMirror (23:05:18.006Z)

    Tokyo_SVM->>SnapMirror: Gửi lệnh REST API: POST /api/snapmirror/relationships/{uuid} (action=break)
    SnapMirror->>Tokyo_SVM: Hoàn tất ngắt quan hệ (Relationship Status: broken_off)
    Tokyo_SVM->>Tokyo_SVM: Chuyển đổi trạng thái volume từ DP sang Read-Write (RW)
    Note over Tokyo_SVM: T7: Tokyo Volume xác nhận RW sau 5.719s (23:05:20.820Z)

    Note over Tokyo_Pod,Tokyo_SVM: XÁC MINH HOẠT ĐỘNG GHI TRÊN ỨNG DỤNG TOKYO
    Tokyo_Pod->>Tokyo_Pod: Kiểm tra endpoint nội bộ /ready
    Note over Tokyo_Pod: Kết quả: {"ready": true, "storage": {"writable": true}}
    Tokyo_Pod->>Tokyo_SVM: Ghi file kiểm tra post-cutover (DR-POST-SEQ-000006.txt)
    Tokyo_SVM-->>Tokyo_Pod: Xác nhận ghi thành công vào đĩa NFS
    Tokyo_Pod->>Tokyo_SVM: Tải lại file vừa ghi và tính toán mã băm SHA-256
    Note over Tokyo_Pod: T9 & T11: Round-trip SHA-256 thành công sau 6.402s (23:05:21.503Z)
```

---

## Chi Tiết Các Mốc Thời Gian (Storage Milestones)

- **$T_0$**: Thời điểm bắt đầu diễn tập cutover.
- **$T_6$ (`SNAPMIRROR_PROMOTION_STARTED`)**: Lambda function gọi ONTAP REST API để thực hiện thao tác `break-off` quan hệ SnapMirror.
- **$T_7$ (`T_VOL_RW`)**: Volume tại Tokyo hoàn tất chuyển trạng thái thành `RW` (Read-Write) trên hệ điều hành ONTAP.
- **$T_9$ (`T_SVC_VERIFY`)**: Dịch vụ `app2-file-service` tại Tokyo ghi file mới, đọc lại và xác thực mã băm SHA-256 trùng khớp 100%.
- **$T_{11}$ (`T_EXTERNAL`)**: Đầu cuối xác thực hoàn tất, dịch vụ lưu trữ sẵn sàng phục vụ toàn diện.
