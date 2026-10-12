# LAB 19 - FSx for NetApp ONTAP Singapore

## 1. Mục tiêu

Tạo source volume RW tại Singapore và mount NFS 4.1 vào `/mnt/dr-data`.

## 2. Thành phần sẽ xây dựng

`dr-sg-fsx-ontap`, SVM `dr-sg-svm`, volume `dr-data`, junction `/dr-data`, export policy và private NFS endpoint.

## 3. Bối cảnh kiến trúc

```text
dr-sg-storage-ec2 -> NFS 4.1 -> dr-sg-svm:/dr-data (RW)
```

## 4. Điều kiện tiên quyết

- LAB 18; quota/capacity/throughput/deployment type được kiểm tra trong Console.
- Chọn **Single-AZ** cho lab chi phí thấp và peering-accessible client endpoints. Production phải đánh giá Multi-AZ và Transit Gateway vì floating client endpoints không đi qua VPC peering.
- KMS key, backup retention và ONTAP credential handling được phê duyệt.

## 5. Quy ước đặt tên tài nguyên

| File system | SVM | Volume | Junction |
|---|---|---|---|
| `dr-sg-fsx-ontap` | `dr-sg-svm` | `dr-data` | `/dr-data` |

## 6. Các bước triển khai

1. FSx -> Create file system -> Amazon FSx for NetApp ONTAP.
2. Chọn deployment type hiện hành phù hợp lab; private subnet Singapore; encryption enabled; backup window/retention đã ghi nhận.
3. Tạo SVM `dr-sg-svm`, NFS enabled. Lưu ONTAP admin credential trong Secrets Manager hoặc password manager được phê duyệt, không Git/user data.
4. Tạo volume `dr-data`, type RW, junction `/dr-data`, capacity/tiering theo budget.
5. Export policy chỉ cho CIDR/host private của storage EC2; root/superuser mapping theo least privilege.
6. SG NFS theo bảng AWS: TCP/UDP `111`, `635`, `2049`, `4045`, `4046`; UDP `4049`, nguồn chỉ storage EC2 subnet/SG-compatible CIDR. Với NFSv4.1-only, chỉ thu hẹp về TCP `2049` sau kiểm thử.
7. Qua SSM trên EC2:

```bash
sudo dnf install -y nfs-utils
sudo mkdir -p /mnt/dr-data
sudo mount -t nfs -o nfsvers=4.1 <SG_SVM_NFS_DNS>:/dr-data /mnt/dr-data
mount | grep /mnt/dr-data
sudo touch /mnt/dr-data/.rw-test && sudo rm /mnt/dr-data/.rw-test
```

8. Sau validation, thêm `/etc/fstab`:

```fstab
<SG_SVM_NFS_DNS>:/dr-data /mnt/dr-data nfs nfsvers=4.1,defaults,_netdev 0 0
```

Hard mount là mặc định; không dùng `soft` cho workload ghi cần toàn vẹn.

## 7. Xác minh

FSx `AVAILABLE`; SVM/volume online; mount dùng `vers=4.1`; create/read/delete test thành công; không có public endpoint.

## 8. Kết quả mong đợi

Singapore EC2 đọc/ghi `/mnt/dr-data`; dữ liệu nằm trên `dr-data`, không nằm trong container/EBS.

## 9. Xử lý sự cố

- Mount timeout: kiểm tra SVM DNS, route, NACL, SG, export policy.
- `access denied`: export policy/client match hoặc junction path sai.
- Boot treo: dùng `_netdev`, kiểm tra DNS/network readiness; cân nhắc `nofail` chỉ khi failure semantics được chấp nhận.

## 10. Lưu ý bảo mật

FSx private, encryption at rest, least-privilege export; NFS không phải authentication boundary cho Internet-facing client.

## 11. Lưu ý chi phí

FSx tính phí capacity, throughput, backup, SSD/tiering và transfer. Xác minh giá Region hiện hành trước Create.

## 12. Dọn dẹp / Quay lui

Unmount client trước khi xóa volume/SVM/file system. Backup theo retention policy; không mặc định xóa dữ liệu.

## 13. Bằng chứng cần thu thập

Deployment type, subnets, KMS, capacity/throughput, export policy, SG, mount options, RW test.

## 14. Lab tiếp theo

[LAB 20 - FSx ONTAP Tokyo](20-fsx-ontap-tokyo.md).

Nguồn: [AWS Linux mount](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/attach-linux-client.html), [security-group ports](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/limit-access-security-groups.html#fsx-vpc-security-groups).
