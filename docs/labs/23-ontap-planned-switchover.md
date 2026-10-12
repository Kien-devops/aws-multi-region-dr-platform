# LAB 23 - ONTAP Planned Switchover

## 1. Mục tiêu

Chuyển file workload có kế hoạch sang Tokyo, không split-brain, với final synchronization.

## 2. Thành phần sẽ xây dựng

Change record, write fence, final update, quiesce/break, Tokyo RW verification và traffic shift.

## 3. Bối cảnh kiến trúc

```text
stop SG writes -> update -> verify -> quiesce -> break Tokyo -> Tokyo RW -> shift traffic
```

## 4. Điều kiện tiên quyết

- LAB 21-22; relationship `Snapmirrored`/`Idle`; both Regions healthy.
- Approved window, operator/reviewer, rollback point, last acknowledged sequence recorded.
- Aurora switchover is separate; coordinate only if unified exercise requires both.

## 5. Quy ước đặt tên tài nguyên

Incident/change ID `<CHANGE_ID>`; timestamps UTC; source `dr-sg-svm:dr-data`; destination `dr-tokyo-svm:dr-data-dr`.

## 6. Các bước triển khai

1. Set Singapore file-service read-only/maintenance; stop container after in-flight writes drain.
2. Prove no writer: ALB deregistered/GA dial fenced, process stopped, no writable client mount in use.
3. Destination CLI:

```text
snapmirror update -destination-path dr-tokyo-svm:dr-data-dr
snapmirror show -fields state,status,last-transfer-end-timestamp
snapmirror quiesce -destination-path dr-tokyo-svm:dr-data-dr
snapmirror show
snapmirror break -destination-path dr-tokyo-svm:dr-data-dr
```

4. Chỉ break sau `Idle`, timestamp mới và `Quiesced` được reviewer xác nhận.
5. Mount Tokyo NFS 4.1, create/read/delete probe, start Tokyo file-service; `/ready` phải writable.
6. Đặt Tokyo storage endpoint group dial `100`, Singapore `0`; dùng request mới để verify.
7. Giữ Singapore fenced. Không chạy resync cho tới kế hoạch failback.

## 7. Xác minh

Tokyo volume RW; first successful storage event/file write; integrity PASS; GA request mới tới Tokyo; Singapore write bị từ chối.

## 8. Kết quả mong đợi

Tokyo là writer duy nhất. Planned loss kỳ vọng tối thiểu nhưng chỉ report measured RPO từ marker thực tế.

## 9. Xử lý sự cố

- Final update lỗi: không break; khôi phục Singapore nếu source còn an toàn.
- Tokyo mount/write lỗi sau break: giữ traffic fenced; sửa export/junction/SG trước khi mở writes.
- Hai phía writable: emergency fence cả hai, chọn authoritative side, bảo toàn snapshot/evidence.

## 10. Lưu ý bảo mật

Break/quiesce quyền cao; audit operator/reviewer. Không gửi credential trong ticket/screenshots.

## 11. Lưu ý chi phí

Không thay đổi đáng kể; transfer/update và resources hai Region vẫn tính phí.

## 12. Dọn dẹp / Quay lui

Trước break có thể hủy maintenance và resume Singapore. Sau break, không gọi đó là rollback; dùng LAB 25 vì Tokyo đã authoritative.

## 13. Bằng chứng cần thu thập

Write-fence proof, last sequence, relationship states/timestamps, break approval, first Tokyo write, GA response.

## 14. Lab tiếp theo

[LAB 24 - ONTAP Unplanned Failover](24-ontap-unplanned-failover.md) cho drill riêng, hoặc [LAB 25](25-ontap-failback.md) để trở về Singapore.
