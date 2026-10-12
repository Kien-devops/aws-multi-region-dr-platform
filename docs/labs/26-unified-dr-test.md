# LAB 26 - Unified Database và Storage DR Test

## 1. Mục tiêu

Đo độc lập transaction RPO, storage RPO, database/application/storage/end-to-end RTO và file integrity trong cùng timeline.

## 2. Thành phần sẽ xây dựng

- `scripts/dr/unified-writer.sh`, `scripts/dr/unified-rpo-check.sh`.
- `scripts/storage-dr/integrity-check.sh`.
- Evidence CSV và report template; không chứa secret.

## 3. Bối cảnh kiến trúc

```text
DR-SEQ-000001 -> backend-3 -> Aurora
              -> file-service -> FSx ONTAP
```

Hai POST cùng sequence không phải distributed transaction. Một path thành công và path kia lỗi phải được log riêng.

## 4. Điều kiện tiên quyết

- Application APIs deployed and authorized; LAB 17 database method understood; LAB 21-22 storage healthy.
- Approved planned/unplanned scenario, recovery owner, synchronized UTC clocks.
- Known-file checksum captured before failure.

## 5. Quy ước đặt tên tài nguyên

Marker `DR-SEQ-%06d`; log CSV `timestamp,sequence,db_status,storage_status`; evidence directory outside Git or sanitized.

## 6. Các bước triển khai

1. Run writer with explicit URLs and interval:

```bash
DB_URL=https://<APP_ENDPOINT>/api/v1/orders \
STORAGE_URL=https://<FILE_ENDPOINT>/api/v1/storage/events \
INTERVAL_SECONDS=1 \
./scripts/dr/unified-writer.sh
```

2. Generate/upload known file and save original checksum:

```bash
FILE_URL=https://<FILE_ENDPOINT> ./scripts/storage-dr/integrity-check.sh prepare
```

3. Record last independently acknowledged DB/storage sequences, then declare disaster at `T0`.
4. Execute the approved Aurora and ONTAP runbooks. Record:

```text
T0 disaster declared
T1 Aurora Tokyo writer ready
T2 Tokyo EKS application ready
T3 Tokyo ONTAP volume RW
T4 Tokyo file-service successful write
T5 both workloads operational
```

5. Query recovered latest endpoints and calculate gaps:

```bash
DB_LATEST_URL=https://<APP_ENDPOINT>/api/v1/orders \
STORAGE_LATEST_URL=https://<FILE_ENDPOINT>/api/v1/storage/events/latest \
./scripts/dr/unified-rpo-check.sh unified-writer.state
```

6. Verify known file after recovery:

```bash
FILE_URL=https://<FILE_ENDPOINT> ./scripts/storage-dr/integrity-check.sh verify
```

7. Report:

```text
Database lost records = last DB acknowledged - latest DB recovered
Storage lost records  = last storage acknowledged - latest storage recovered
Approximate time gap  = lost records * writer interval, only when cadence was stable

Database RTO    = T1 - T0
Application RTO = T2 - T0
Storage RTO     = T4 - T0
End-to-End RTO  = T5 - T0
```

## 7. Xác minh

CSV remains parseable during timeout/failure; state records each path separately; recovered sequences are numeric; integrity compares actual downloaded bytes.

## 8. Kết quả mong đợi

Measured fields contain observed timestamps/gaps only after live execution. Otherwise write `NOT MEASURED`.

## 9. Xử lý sự cố

- Endpoint returns non-2xx: preserve status, do not advance that path's acknowledged marker.
- Latest response schema differs: stop and update parser; do not guess values.
- Clock skew: use request log ordering/sequence and fix NTP before time claims.

## 10. Lưu ý bảo mật

Use short-lived tokens via environment/approved secret store; scripts must not echo auth headers. Test files contain no sensitive data.

## 11. Lưu ý chi phí

Writer traffic, ALB, logs, Aurora I/O, FSx capacity/transfer and snapshots can incur cost. Bound test duration.

## 12. Dọn dẹp / Quay lui

Stop writer, retain sanitized evidence, delete test data only after owner approval, restore normal topology via LAB 16 and LAB 25.

## 13. Bằng chứng cần thu thập

Writer CSV/state, T0-T5, relationship/DB states, latest markers, RPO calculation, original/recovered SHA-256, integrity outcome.

Report template:

| Metric | Target | Measured Result | Evidence |
|---|---:|---:|---|
| Database RPO | `< 30s` | `NOT MEASURED` | `<path>` |
| Storage RPO | `< 5m` | `NOT MEASURED` | `<path>` |
| Database RTO | `< 5m` | `NOT MEASURED` | `<path>` |
| Storage RTO | `< 15m` | `NOT MEASURED` | `<path>` |
| End-to-End RTO | `< 15m` | `NOT MEASURED` | `<path>` |
| File integrity | `PASS` | `NOT MEASURED` | `<path>` |

## 14. Lab tiếp theo

[LAB 27 - Cleanup](27-cleanup.md).
