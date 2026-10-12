# LAB 24 - ONTAP Unplanned Failover

## 1. Mục tiêu

Promote Tokyo khi Singapore unavailable, chấp nhận khả năng mất writes chưa replicate và đo storage RPO.

## 2. Thành phần sẽ xây dựng

Incident declaration, old-primary fencing, lag assessment, authorized break, Tokyo activation, evidence handoff.

## 3. Bối cảnh kiến trúc

Asynchronous replication không bảo đảm last acknowledged write đã tới Tokyo. `last acknowledged - latest recovered` là observed data loss.

## 4. Điều kiện tiên quyết

- Tokyo FSx/EC2/ALB healthy; latest relationship evidence accessible.
- Incident Commander và data-loss authority được chỉ định.
- Singapore cannot safely serve writes; fencing options reviewed.

## 5. Quy ước đặt tên tài nguyên

Incident `<INCIDENT_ID>`; UTC timeline; destination `dr-tokyo-svm:dr-data-dr`.

## 6. Các bước triển khai

1. Record `T0`; disable Singapore storage GA endpoint, deregister target/stop instance/revoke write path where reachable.
2. Confirm no alternate client can write source. Network isolation alone is insufficient if disconnected clients remain.
3. Record `snapmirror show -fields state,status,last-transfer-end-timestamp` and latest recovered marker.
4. Obtain explicit authorization for possible loss, then:

```text
snapmirror break -destination-path dr-tokyo-svm:dr-data-dr
```

5. Mount Tokyo RW, start file-service, verify `/ready`, create storage event/file, verify checksum.
6. Shift storage accelerator to Tokyo; record first successful client write.
7. Keep Singapore fenced when it returns. Treat Tokyo as authoritative.

## 7. Xác minh

One writer only; Tokyo write/read/delete/verify PASS; recovered latest marker captured; old primary cannot accept writes.

## 8. Kết quả mong đợi

Service restored in Tokyo. Data gap may exist and must be reported, never hidden as `RPO = 0`.

## 9. Xử lý sự cố

- Destination inconsistent/unavailable: do not fabricate recovery; restore from backup or escalate.
- Singapore returns: do not route back or resync automatically.
- Break command uncertain: stop and verify destination path/source direction before retry.

## 10. Lưu ý bảo mật

Emergency access remains time-bound and logged. Preserve CloudTrail, ONTAP audit and application logs.

## 11. Lưu ý chi phí

Incident operation does not stop resources; backup/forensic retention can increase cost.

## 12. Dọn dẹp / Quay lui

No instant rollback. Stabilize Tokyo, preserve snapshots, then use LAB 25.

## 13. Bằng chứng cần thu thập

T0, fencing, last transfer, authorization, break, T4 first Tokyo write, marker gap, integrity result.

## 14. Lab tiếp theo

[LAB 25 - ONTAP Failback](25-ontap-failback.md).
