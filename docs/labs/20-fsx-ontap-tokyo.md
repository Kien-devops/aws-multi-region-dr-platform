# LAB 20 - FSx for NetApp ONTAP Tokyo

## 1. Mục tiêu

Tạo Tokyo destination foundation và chuẩn bị volume DP cho SnapMirror.

## 2. Thành phần sẽ xây dựng

`dr-tokyo-fsx-ontap`, `dr-tokyo-svm`, destination volume `dr-data-dr`, junction `/dr-data` sau promotion.

## 3. Bối cảnh kiến trúc

```text
Singapore dr-data (RW) -> SnapMirror -> Tokyo dr-data-dr (DP/read-only)
```

## 4. Điều kiện tiên quyết

- LAB 19; Tokyo deployment type/capacity đủ chứa source.
- Peering/routes/intercluster SG flow của LAB 04 hoàn tất.
- Không có application writer tại Tokyo.

## 5. Quy ước đặt tên tài nguyên

| File system | SVM | Volume |
|---|---|---|
| `dr-tokyo-fsx-ontap` | `dr-tokyo-svm` | `dr-data-dr` |

## 6. Các bước triển khai

1. Tạo FSx ONTAP trong private subnet Tokyo, encryption/backup/deployment type theo cùng decision record Singapore.
2. Tạo SVM `dr-tokyo-svm`, NFS enabled, credential không lưu trong Git.
3. Từ ONTAP CLI destination, tạo DP volume dung lượng ít nhất bằng source; lấy aggregate thực tế thay placeholder:

```text
FSx-Dest::> vol create -vserver dr-tokyo-svm -volume dr-data-dr \
  -aggregate <TOKYO_AGGREGATE> -size <SIZE_AT_LEAST_SOURCE> -type DP -tiering-policy all
```

4. Chuẩn bị export policy cho Tokyo EC2 nhưng không cho write khi relationship còn DP.
5. Tạo mount point `/mnt/dr-data` trên Tokyo EC2. Chỉ mount/read-test sau initialization; `/ready` phải báo `writable: false` trước break.
6. Dùng cùng NFS port baseline LAB 19, nguồn chỉ Tokyo storage EC2.

## 7. Xác minh

```text
FSx-Dest::> volume show -vserver dr-tokyo-svm -volume dr-data-dr -fields type,state,size
```

Kỳ vọng type `DP`, state online, capacity không nhỏ hơn source. Không tạo file trực tiếp tại destination.

## 8. Kết quả mong đợi

Tokyo foundation sẵn sàng nhận baseline; chưa writable và chưa phục vụ traffic.

## 9. Xử lý sự cố

- Không tạo được DP: kiểm tra aggregate/capacity/volume name.
- Client mount không thấy data: relationship chưa initialize hoặc junction/export chưa sẵn sàng.
- Ghi thành công trước promotion: dừng lại; kiểm tra nhầm volume/relationship vì đây là split-brain risk.

## 10. Lưu ý bảo mật

Tách ONTAP admin khỏi application runtime. Chỉ operator role được phép peer/create/break/resync.

## 11. Lưu ý chi phí

Tokyo FSx tính phí liên tục kể cả destination read-only; tiering không loại bỏ capacity/throughput/backup costs.

## 12. Dọn dẹp / Quay lui

Không xóa DP volume khi relationship còn tồn tại. Xóa/release relationship theo LAB 27 trước.

## 13. Bằng chứng cần thu thập

File system/SVM/volume IDs, type DP, size, KMS, subnets, SG/export policy, no-write evidence.

## 14. Lab tiếp theo

[LAB 21 - SnapMirror Replication](21-snapmirror-replication.md).
