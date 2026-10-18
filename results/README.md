# Kết Quả Thực Nghiệm Disaster Recovery (DR)

Thư mục này lưu trữ toàn bộ dữ liệu, bằng chứng (evidence) và báo cáo thực nghiệm thu được từ quá trình kiểm thử Disaster Recovery thực tế trên môi trường AWS đa vùng (Singapore `ap-southeast-1` và Tokyo `ap-northeast-1`).

---

## 1. Cấu Trúc Thư Mục Kết Quả

```text
results/
├── README.md                  # Hướng dẫn và tổng hợp số liệu thực nghiệm
├── unified-dr/                # Kết quả tổng thể lần chạy Live Unified DR
│   ├── result.json            # Chi tiết thông số RTO/RPO và milestone ở định dạng JSON
│   ├── summary.md             # Tóm tắt kết quả kiểm thử và phân tích kỹ thuật
│   ├── timeline.csv           # Bảng tiến trình chi tiết từng mốc thời gian (UTC)
│   └── metadata.json          # Thông tin môi trường, phạm vi và thông số thử nghiệm
├── database/                  # Số liệu và bằng chứng phục hồi cơ sở dữ liệu (Aurora)
│   ├── rto.json               # Đo lường thời gian phục hồi cơ sở dữ liệu (RTO)
│   ├── rpo.json               # Đánh giá độ mất mát dữ liệu (RPO)
│   ├── orders-verification.csv # Đối soát chi tiết 5/5 đơn hàng thử nghiệm
│   ├── recovered-transactions.csv # Danh sách transaction markers được khôi phục
│   ├── transaction-markers.csv # Danh sách marker tạo trước thời điểm cutover
│   ├── missing-transactions.csv # Ghi nhận các khoảng dữ liệu bị thiếu (rỗng: không mất dữ liệu)
│   └── integrity.json         # Trạng thái toàn vẹn dữ liệu DB
├── storage/                   # Số liệu và bằng chứng phục hồi lưu trữ file (FSx ONTAP)
│   ├── rto.json               # Đo lường thời gian chuyển đổi và mount lưu trữ (RTO)
│   ├── rpo.json               # Đánh giá tính toàn vẹn và mất mát file (RPO)
│   ├── files-verification.csv # Đối soát chi tiết 5/5 file synthetic kèm mã băm SHA-256
│   ├── recovered-files.csv    # Danh sách file được khôi phục tại Tokyo kèm SHA-256
│   ├── file-markers.csv       # Danh sách file marker tạo trước thời điểm cutover
│   ├── missing-files.csv      # Ghi nhận file bị thiếu (rỗng: không mất file)
│   └── integrity.json         # Kết quả kiểm tra checksum SHA-256
├── evidence/                  # Raw evidence độc lập thu thập trực tiếp từ AWS API
│   ├── rds/                   # Snapshot describe-global-clusters từ RDS API
│   ├── fsx/                   # Snapshot describe-volumes từ FSx API
│   ├── ontap/                 # Snapshot REST API trạng thái SnapMirror từ SVM
│   └── application/           # Kết quả kiểm tra health probe và endpoint ứng dụng
└── charts/                    # Biểu đồ trực quan hóa tiến trình và phân tích RTO/RPO
    ├── rto-waterfall.png      # Biểu đồ thác nước thời gian hoàn thành từng nhánh
    ├── rpo-analysis.png       # Biểu đồ đối soát dữ liệu và phân tích RPO
    ├── unified-timeline.png   # Dòng thời gian tổng thể từ T0 đến khi hoàn tất
    ├── database-rto.png       # Biểu đồ thời gian chuyển đổi Aurora writer
    └── storage-rto.png        # Biểu đồ thời gian promotion FSx volume
```

---

## 2. Bảng Kết Quả Đo Lường Thực Tế (Live Run: `LIVE-RUN-20261018-230436`)

| Phân Hệ | Chỉ Số Đo Lường | Giá Trị Thực Nghiệm | Mục Tiêu SLA | Đánh Giá | Cơ Chế / Bằng Chứng Xác Minh |
|---|---|---:|---:|:---:|---|
| **Aurora Database** | Infrastructure RTO ($T_{\text{DB\_WRITER}}$) | **38.471 s** | — | **PASS** | RDS API xác nhận cụm Tokyo trở thành Global Writer |
| **Aurora Database** | Application Service RTO ($T_{\text{DB\_APP}}$) | **47.428 s** | $\le 240.0\text{ s}$ | **PASS** | Tokyo `backend-3` nhận và ghi nhận thành công đơn hàng kiểm tra |
| **Aurora Database** | Observed RPO | **0.000 s** | $\le 60.0\text{ s}$ | **PASS** | Thu hồi nguyên vẹn 5/5 đơn hàng pre-drill (ID 100–104) |
| **FSx ONTAP Storage** | Volume Promotion RTO ($T_7$) | **5.719 s** | — | **PASS** | ONTAP REST API xác nhận Tokyo volume chuyển trạng thái `RW` |
| **FSx ONTAP Storage** | Application Service RTO ($T_9, T_{11}$)| **6.402 s** | $\le 300.0\text{ s}$ | **PASS** | Tokyo `file-service` upload/download/sha256 round-trip thành công |
| **FSx ONTAP Storage** | Observed RPO | **0.000 s** | $\le 300.0\text{ s}$ | **PASS** | Thu hồi đủ 5/5 synthetic files, 100% khớp mã băm SHA-256 |
| **Unified Overall** | **Overall End-to-End RTO** | **47.429 s** | $\le 300.0\text{ s}$ | **PASS** | $\max(47.428\text{s}, 6.402\text{s})$ — Toàn bộ ứng dụng sẵn sàng phục vụ |

---

## 3. Lưu Ý Kỹ Thuật Quan Trọng Về Số Liệu

1. **Về RPO 0 giây**:
   - Giá trị $0.000\text{ s}$ là kết quả quan sát thực nghiệm (*Observed RPO*) trên tập 5 transaction markers và 5 synthetic files được đồng bộ hóa trước thời điểm ngắt kết nối.
   - Do Aurora Global Database sử dụng cơ chế nhân bản vật lý không đồng bộ (asynchronous storage replication) và FSx SnapMirror chạy lịch truyền dữ liệu định kỳ, trong trường hợp xảy ra thảm họa đột ngột (*unplanned outage*), RPO lý thuyết sẽ phụ thuộc vào độ trễ sao chép tại thời điểm sự cố (thường $< 1\text{s}$ đối với Aurora và theo chu kỳ update đối với SnapMirror).
2. **Về RTO 47.429 giây**:
   - RTO được tính từ thời điểm kích hoạt diễn tập ($T_0$: `2026-10-18T23:05:15.101Z`) cho đến khi hệ thống kiểm tra độc lập thực hiện thành công giao dịch ghi/đọc sau cutover ($T_{\text{RECOVERY}}$: `2026-10-18T23:06:02.530Z`).
   - Thời gian này bao gồm cả độ trễ phát hiện và xác thực đầu cuối (*end-to-end verification probe*), không đồng nhất với thời gian ngưng trệ kết nối thực tế ở tầng mạng của người dùng.
