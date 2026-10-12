# LAB 21 - SnapMirror Replication

## 1. Mục tiêu

Thiết lập asynchronous volume-level SnapMirror Singapore -> Tokyo, monitor lag và chứng minh destination còn read-only.

## 2. Thành phần sẽ xây dựng

Cluster peer, SVM peer, relationship `dr-sg-svm:dr-data` -> `dr-tokyo-svm:dr-data-dr`, baseline initialization và schedule.

## 3. Bối cảnh kiến trúc

FSx for ONTAP hỗ trợ volume-level asynchronous SnapMirror. Lab này không dùng SVMDR, synchronous SnapMirror hoặc StrictSync.

## 4. Điều kiện tiên quyết

- LAB 04, 19, 20.
- Mọi source intercluster LIF kết nối được mọi destination intercluster LIF, hai chiều.
- Destination DP capacity >= source; credential/operator window được phê duyệt.

## 5. Quy ước đặt tên tài nguyên

Source `dr-sg-svm:dr-data`; destination `dr-tokyo-svm:dr-data-dr`; schedule tối thiểu `5min` chỉ khi ONTAP hiện hành cung cấp và tải cho phép.

## 6. Các bước triển khai

1. Ghi intercluster endpoint IPs, route tables và SG rules: ICMP, TCP `443`, `10000`, `11104`, `11105` hai chiều.
2. Tạo cluster peer và SVM peer theo AWS FSx Console/ONTAP workflow hiện hành; xác nhận trạng thái `peered` trước relationship.
3. Trên destination, dùng source local name thực tế:

```text
FSx-Dest::> snapmirror create \
  -source-path <SOURCE_LOCAL_NAME>:dr-data \
  -destination-path dr-tokyo-svm:dr-data-dr \
  -vserver dr-tokyo-svm \
  -throttle unlimited

FSx-Dest::> snapmirror initialize \
  -destination-path dr-tokyo-svm:dr-data-dr \
  -source-path <SOURCE_LOCAL_NAME>:dr-data
```

4. Theo dõi baseline. Nếu file system reboot/takeover trong initialization, kiểm tra và restart thủ công; không giả định tự resume.
5. Khi `Snapmirrored`/`Idle`, đặt schedule đã phê duyệt:

```text
FSx-Dest::> snapmirror modify -destination-path dr-tokyo-svm:dr-data-dr -schedule <SCHEDULE>
FSx-Dest::> snapmirror show -fields state,status,last-transfer-end-timestamp
```

6. Tạo file marker tại Singapore, chạy `snapmirror update`, xác minh marker xuất hiện read-only tại Tokyo.

## 7. Xác minh

Relationship `Snapmirrored`, transfer `Idle`, last-transfer timestamp mới; destination không writable; schedule và actual lag được ghi riêng.

## 8. Kết quả mong đợi

File state replicate asynchronous tới Tokyo. Schedule là design configuration, không phải measured RPO.

## 9. Xử lý sự cố

- Peer unavailable: route/SG/NACL/DNS/intercluster LIF matrix.
- Initialize treo: events, capacity, credentials, takeover/reboot.
- Lag cao: source change rate, throughput, network, destination capacity và concurrent operations.

## 10. Lưu ý bảo mật

Giới hạn management/intercluster flows; audit ONTAP admin commands; không đưa peer passphrase/credential vào evidence.

## 11. Lưu ý chi phí

Cross-Region transfer, capacity, throughput và backup tính phí. Schedule ngắn tăng traffic/operational load.

## 12. Dọn dẹp / Quay lui

Trước xóa: quiesce khi phù hợp, delete destination relationship, release source relationship, sau đó mới xóa volume/peer.

## 13. Bằng chứng cần thu thập

Peer status, relationship fields, schedule, baseline duration, last transfer, marker read-only, CloudTrail/operator record.

## 14. Lab tiếp theo

[LAB 22 - File-service Deployment](22-file-service-deployment.md).

Nguồn: [AWS migration workflow](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/migrating-fsx-ontap-snapmirror.html), [scheduled replication](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/scheduled-replication.html).
