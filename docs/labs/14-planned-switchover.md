# LAB 14 - Chuyển đổi hạ tầng có kế hoạch

## 1. Mục tiêu

Thực hiện Aurora Global Database switchover có kiểm soát sang Tokyo, chuyển kết nối Global Accelerator mới tới Tokyo, xác minh hạ tầng, sau đó giữ Tokyo làm primary cho LAB 16 hoặc chuyển lại.

Lab này chỉ đổi database/application infrastructure. Storage vẫn Singapore RW cho tới LAB 23; không suy ra ONTAP role từ Aurora role.

## 2. Thành phần sẽ xây dựng

Không tạo tài nguyên dài hạn mới. Lab này thay đổi trạng thái control plane:

- Aurora primary Region: từ Singapore sang Tokyo.
- Ưu tiên lưu lượng GA: từ Singapore sang Tokyo.
- Timeline bằng chứng cho RTO hạ tầng.

## 3. Bối cảnh kiến trúc

```text
Trước: GA -> ALB Singapore; Aurora writer tại Singapore
Sau:   GA -> ALB Tokyo;     Aurora writer tại Tokyo
```

Aurora instance failover trong một Region không phải Global Database switchover. Phải dùng thao tác của Global Database.

## 4. Điều kiện tiên quyết

- Maintenance/change window đã được phê duyệt.
- Aurora global cluster và hai regional cluster ở trạng thái `available`.
- Engine version của primary/secondary tương thích; không có pending maintenance gây chặn.
- Replication lag ổn định và alarm ở trạng thái OK.
- Hai ALB kiểm thử khỏe mạnh.
- Không tồn tại Application của app2.
- Đã ghi người chịu trách nhiệm rollback và thời hạn ra quyết định.

## 5. Quy ước đặt tên tài nguyên

- Global cluster: `app2-global-db`
- Primary hiện tại: `app2-sg-db`
- Primary mục tiêu: `app2-tokyo-db`
- GA endpoint group: ghi ARN thực tế thành `<SG_ENDPOINT_GROUP_ARN>` và `<TOKYO_ENDPOINT_GROUP_ARN>`.

## 6. Các bước triển khai

### 6.1 Ghi lại baseline

```bash
date -u
aws rds describe-global-clusters --region ap-southeast-1 --global-cluster-identifier app2-global-db
curl -sS http://<ACCELERATOR_DNS_NAME>/
```

Chỉ ghi `T0` khi người vận hành bắt đầu switchover.

### 6.2 Thực hiện switchover có quản lý

AWS Console:

```text
RDS Singapore -> Databases -> app2-global-db
Actions -> Switchover or failover global database
Operation: Switchover
Target: app2-tokyo-db
Review impact -> Confirm
```

Lệnh CLI tương đương, dùng để xác minh hoặc trong runbook đã phê duyệt:

```bash
aws rds switchover-global-cluster \
  --region ap-southeast-1 \
  --global-cluster-identifier app2-global-db \
  --target-db-cluster-identifier <TOKYO_DB_CLUSTER_ARN>
```

Chờ global cluster trở lại `available` và member Tokyo có `IsWriter=true`.

### 6.3 Chuyển kết nối GA mới

Đặt traffic dial Singapore thành `0`, Tokyo thành `100`. Thay đổi traffic dial chỉ ảnh hưởng kết nối mới.

```bash
aws globalaccelerator update-endpoint-group \
  --region us-west-2 \
  --endpoint-group-arn <SG_ENDPOINT_GROUP_ARN> \
  --traffic-dial-percentage 0

aws globalaccelerator update-endpoint-group \
  --region us-west-2 \
  --endpoint-group-arn <TOKYO_ENDPOINT_GROUP_ARN> \
  --traffic-dial-percentage 100
```

### 6.4 Xác minh hạ tầng

```bash
kubectl --context tokyo get nodes
kubectl --context tokyo -n infra-validation get pods,ingress
curl -sS -H 'Connection: close' http://<ACCELERATOR_DNS_NAME>/
aws rds describe-global-clusters --region ap-northeast-1 --global-cluster-identifier app2-global-db
```

Xác minh global writer endpoint vẫn tồn tại và hiện định tuyến tới primary mới. Có thể kiểm tra ghi cơ sở dữ liệu bằng client `psql` tạm thời đã được phê duyệt; không để lộ credential trong command history.

## 7. Xác minh

Chỉ đạt khi:

- Tokyo là writer duy nhất.
- Singapore được kết nối với vai trò secondary.
- Hai regional cluster trở lại `available`.
- Kết nối GA mới tới Tokyo.
- EKS và ALB Tokyo tiếp tục khỏe mạnh.
- Alarm không hiển thị lỗi kéo dài ngoài dự kiến.

## 8. Kết quả mong đợi

Đảo vai trò hạ tầng thành công và có timestamp đo thực tế. Mục tiêu thiết kế và kết quả đo phải tách biệt.

## 9. Xử lý sự cố

- Switchover bị từ chối: kiểm tra tương thích engine patch, trạng thái cluster, pending maintenance và target ARN.
- GA có vẻ chưa đổi: kiểm tra bằng kết nối mới; TCP session hiện có vẫn được giữ.
- Primary cũ chưa thành secondary: dừng thay đổi lưu lượng và kiểm tra RDS event trước khi tiếp tục.
- Kết nối global writer endpoint lỗi: kiểm tra DNS resolution, peering/route nếu kết nối liên Region, DB SG và trạng thái cluster.

## 10. Lưu ý bảo mật

- Chỉ cấp `rds:SwitchoverGlobalCluster` và quyền thay đổi GA cho người vận hành DR.
- Production phải có MFA/phê duyệt thay đổi.
- Giữ bằng chứng CloudTrail và timeline sự cố.
- Không bao giờ dùng `--allow-data-loss` trong planned switchover.

## 11. Lưu ý chi phí

Không có tài nguyên lớn mới. Kiểm thử liên Region có thể phát sinh phí truyền dữ liệu. Mọi tài nguyên theo giờ hiện có tiếp tục tính phí.

## 12. Dọn dẹp / Quay lui

Nếu xác minh thất bại và cả hai Region vẫn khỏe, thực hiện một managed switchover khác về Singapore, sau đó khôi phục GA traffic dial Singapore `100`, Tokyo `0`. Không tự ứng biến bước detach/promote trong sự kiện có kế hoạch.

## 13. Bằng chứng cần thu thập

- Điều kiện trước khi chạy và người phê duyệt.
- `T0`, thời điểm đổi writer hoàn tất, chuyển lưu lượng hoàn tất và xác minh hoàn tất.
- RDS event log và ảnh topology.
- Sức khỏe endpoint/traffic dial GA trước và sau.
- Thời gian phục hồi hạ tầng đo được; RTO/RPO ứng dụng được đánh dấu hoãn.

## 14. Lab tiếp theo

Tiếp tục với [LAB 15 - Chuẩn bị failover hạ tầng ngoài kế hoạch](15-unplanned-failover.md).
