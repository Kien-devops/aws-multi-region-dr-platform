#!/usr/bin/env bash
# scripts/dr/rpo-check.sh
# Compares acknowledged and recovered markers for Phase 3 RPO evidence.
# Usage: ./scripts/dr/rpo-check.sh [TOKYO_ENDPOINT_URL]
# Phase 3 only: requires app2 /api/v1/orders and timestamped writer evidence.

set -euo pipefail

TOKYO_URL="${1:-http://localhost/api/v1/orders}"
STATE_FILE="rpo-last-committed.json"

echo "=== KIỂM TRA & TÍNH TOÁN RPO THỰC NGHIỆM ==="

if [[ ! -f "$STATE_FILE" ]]; then
  echo "Lỗi: Không tìm thấy $STATE_FILE. Chạy rpo-writer.sh và giữ file bằng chứng trước failover."
  exit 2
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
  echo "=> MARKER GAP: 0 transaction trong tập mẫu quan sát được."
  echo "Không suy ra RPO = 0 giây nếu chưa đối chiếu timestamp, request rate và phạm vi dữ liệu đầy đủ."
elif [[ "$MAX_TOKYO_MARKER" == "NONE" ]]; then
  echo "=> CẢNH BÁO: Không tìm thấy bản ghi benchmark nào tại Tokyo. Kiểm tra lại kết nối DB hoặc table orders."
elif [[ "$LAST_SG_MARKER" =~ ^SEQ-[0-9]{6}$ && "$MAX_TOKYO_MARKER" =~ ^SEQ-[0-9]{6}$ ]]; then
  echo "=> Chênh lệch phát hiện:"
  echo "   Singapore commit cuối: $LAST_SG_MARKER"
  echo "   Tokyo nhận được cuối: $MAX_TOKYO_MARKER"
  SG_NUM=$(echo "$LAST_SG_MARKER" | sed 's/SEQ-0*//')
  TOKYO_NUM=$(echo "$MAX_TOKYO_MARKER" | sed 's/SEQ-0*//')
  DIFF=$((SG_NUM - TOKYO_NUM))
  if [[ $DIFF -lt 0 ]]; then
    echo "   Tokyo có marker cao hơn mốc client lưu: kiểm tra writer song song hoặc state file không đầy đủ."
  else
    echo "   Khoảng mất quan sát được: $DIFF transaction(s); không tự động quy đổi thành RPO thời gian."
  fi
  if [[ $DIFF -ge 0 && $DIFF -le 30 ]]; then
    echo "   [OBSERVATION] Marker gap <= 30 requests; cần timestamp để đánh giá mục tiêu RPO thời gian."
  elif [[ $DIFF -gt 30 ]]; then
    echo "   [OBSERVATION] Marker gap > 30 requests; chưa quy đổi thành RPO thời gian."
  fi
else
  echo "=> CẢNH BÁO: Marker không đúng định dạng SEQ-000000; không thể tính khoảng chênh lệch."
fi
echo "========================================================"
