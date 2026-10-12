# LAB 25 - ONTAP Failback về Singapore

## 1. Mục tiêu

Đưa authoritative file state từ Tokyo về Singapore và khôi phục Singapore-primary/Tokyo-DP.

## 2. Thành phần sẽ xây dựng

Reverse resync Tokyo -> Singapore, final cutback, rồi tái lập protection Singapore -> Tokyo.

## 3. Bối cảnh kiến trúc

Tokyo là source of truth sau promotion. `snapmirror resync` có thể rollback/xóa divergent destination data.

## 4. Điều kiện tiên quyết

- Tokyo stable/RW; Singapore repaired, fenced and not serving writes.
- Snapshot/backup/evidence complete; source/destination direction được hai người review.
- Capacity/network/peering healthy.

## 5. Quy ước đặt tên tài nguyên

Authoritative source: `dr-tokyo-svm:dr-data-dr`; recovery destination: `dr-sg-svm:dr-data`.

## 6. Các bước triển khai

1. Snapshot/backup both sides. Document divergent data decision.
2. Reverse resync **Tokyo -> Singapore** using exact paths verified by `snapmirror show`:

```text
snapmirror resync -source-path dr-tokyo-svm:dr-data-dr -destination-path dr-sg-svm:dr-data
```

3. Wait `Snapmirrored`/`Idle`; validate Singapore copy read-only/directly without serving traffic.
4. Stop Tokyo writes; record final sequence; final update Tokyo -> Singapore; quiesce; verify `Quiesced`; break Singapore destination.
5. Mount Singapore RW, start service, checksum/marker/write test, then shift storage GA Singapore `100`, Tokyo `0`.
6. Delete/release reverse relationship only after stable cutback.
7. Recreate/resync normal direction Singapore -> Tokyo; verify Tokyo returns DP/read-only and protected.

Commands for update/quiesce/break/delete/release vary by relationship context. Copy exact source/destination from verified state; do not paste placeholders into production.

## 7. Xác minh

Singapore writer only; Tokyo DP/read-only; relationship normal direction `Snapmirrored`/`Idle`; data/integrity/traffic checks PASS.

## 8. Kết quả mong đợi

Normal topology restored without discarding Tokyo-authoritative changes.

## 9. Xử lý sự cố

- No common snapshot/resync rejected: stop; use backup/new volume migration plan.
- Divergent Singapore data: preserve snapshot; do not force resync before owner decision.
- Cutback validation fails: keep traffic Tokyo if it remains authoritative and safe.

## 10. Lưu ý bảo mật

Two-person verification for destructive direction. `vserver stop` affects the whole SVM; prefer application/ALB/mount fencing for this single-volume workload.

## 11. Lưu ý chi phí

Reverse/full transfers and retained snapshots can increase transfer/capacity charges.

## 12. Dọn dẹp / Quay lui

Before cutback, remain Tokyo-primary. After Singapore promotion, use a new controlled switchover; never improvise reverse resync.

## 13. Bằng chứng cần thu thập

Direction review, snapshots, relationship states, final marker, first Singapore write, GA response, restored normal relationship.

## 14. Lab tiếp theo

[LAB 26 - Unified DR Test](26-unified-dr-test.md).

Nguồn: [NetApp resync warning](https://docs.netapp.com/us-en/ontap/data-protection/resynchronize-relationship-task.html), [reactivate original source](https://docs.netapp.com/us-en/ontap/data-protection/reactivate-original-source-volume-task.html).
