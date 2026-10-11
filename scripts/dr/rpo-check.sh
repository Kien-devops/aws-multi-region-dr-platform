#!/usr/bin/env bash
# scripts/dr/rpo-check.sh
# Checks max available marker in Tokyo after DR promotion and calculates measured RPO
# Usage: ./scripts/dr/rpo-check.sh [TOKYO_ENDPOINT_URL]

set -euo pipefail

TOKYO_URL="${1:-http://localhost/api/v1/orders}"
STATE_FILE="rpo-last-committed.json"

echo "=== KIỂM TRA & TÍNH TOÁN RPO THỰC NGHIỆM ==="

if [[ ! -f "$STATE_FILE" ]]; then
  echo "Cảnh báo: Không tìm thấy $STATE_FILE! Cần chạy rpo-writer.sh trước khi bắn lỗi để lưu mốc cuối."
  LAST_SG_MARKER="UNKNOWN"
  LAST_SG_TIME="UNKNOWN"
else
  LAST_SG_MARKER=$(grep '"last_marker"' "$STATE_FILE" | cut -d'"' -f4)
  LAST_SG_TIME=$(grep '"committed_at"' "$STATE_FILE" | cut -d'"' -f4)
  echo "Bản ghi commit cuối tại Singapore trước sự cố: $LAST_SG_MARKER lúc $LAST_SG_TIME"
fi

echo "Đang truy vấn cơ sở dữ liệu Tokyo qua endpoint: $TOKYO_URL ..."
RESP=$(curl -s --connect-timeout 3 --max-time 5 "$TOKYO_URL" || echo "[]")

# Extract markers from response
MAX_TOKYO_MARKER=$(echo "$RESP" | grep -o 'SEQ-[0-9]\{6\}' | sort | tail -n 1 || echo "NONE")
TOTAL_RECORDS=$(echo "$RESP" | grep -o 'SEQ-[0-9]\{6\}' | wc -l || echo "0")

echo "Bản ghi cao nhất tìm thấy tại Tokyo sau failover: $MAX_TOKYO_MARKER (Tổng số bản ghi: $TOTAL_RECORDS)"

echo "--------------------------------------------------------"
if [[ "$LAST_SG_MARKER" == "$MAX_TOKYO_MARKER" && "$LAST_SG_MARKER" != "NONE" ]]; then
  echo "=> KẾT LUẬN RPO: 0 GIÂY (ZERO DATA LOSS!)"
  echo "Tất cả các transaction trước thời điểm sự cố đều được sao chép nguyên vẹn sang Tokyo."
elif [[ "$MAX_TOKYO_MARKER" == "NONE" ]]; then
  echo "=> CẢNH BÁO: Không tìm thấy bản ghi benchmark nào tại Tokyo. Kiểm tra lại kết nối DB hoặc table orders."
else
  echo "=> Chênh lệch phát hiện:"
  echo "   Singapore commit cuối: $LAST_SG_MARKER"
  echo "   Tokyo nhận được cuối: $MAX_TOKYO_MARKER"
  SG_NUM=$(echo "$LAST_SG_MARKER" | sed 's/SEQ-0*//')
  TOKYO_NUM=$(echo "$MAX_TOKYO_MARKER" | sed 's/SEQ-0*//')
  DIFF=$((SG_NUM - TOKYO_NUM))
  echo "   Số bản ghi bị mất trong replication buffer: $DIFF transaction(s)"
  echo "   RPO ước tính: ~$DIFF giây (Dựa trên tần suất ghi 1 req/giây)"
  if [[ $DIFF -le 30 ]]; then
    echo "   [PASS] Đạt tiêu chí mục tiêu RPO < 30 giây."
  else
    echo "   [FAIL] Vượt quá tiêu chí mục tiêu RPO < 30 giây."
  fi
fi
echo "========================================================"
