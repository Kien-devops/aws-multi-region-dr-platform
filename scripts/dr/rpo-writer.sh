#!/usr/bin/env bash
# scripts/dr/rpo-writer.sh
# Continuous writer generating sequential orders every 1 second to measure RPO
# Usage: ./scripts/dr/rpo-writer.sh [TARGET_URL]
# Phase 3 only: requires app2 /api/v1/orders and must not run during infrastructure-only labs.

set -euo pipefail

TARGET_URL="${1:-http://localhost/api/v1/orders}"
LOG_FILE="rpo-writer.log"
STATE_FILE="rpo-last-committed.json"

echo "==> Starting Continuous RPO Writer against [$TARGET_URL]..."
echo "==> State tracked in [$STATE_FILE] and [$LOG_FILE]."
echo "==> Press [Ctrl+C] to stop."

SEQ=1
trap 'echo -e "\n==> Writer stopped. Last state preserved in $STATE_FILE."; exit 0' INT TERM

while true; do
  MARKER=$(printf "SEQ-%06d" "$SEQ")
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

  PAYLOAD=$(cat <<EOF
{
  "item_id": "item-rpo-benchmark",
  "quantity": 1,
  "marker": "$MARKER",
  "client_timestamp": "$TIMESTAMP"
}
EOF
)

  # Send POST request
  HTTP_STATUS=$(curl -s -o /tmp/rpo-res.json -w "%{http_code}" \
    -X POST "$TARGET_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    --connect-timeout 2 --max-time 3 || echo "000")

  if [[ "$HTTP_STATUS" =~ ^20[0-9]$ ]]; then
    # Record success
    cat <<EOF > "$STATE_FILE"
{
  "last_marker": "$MARKER",
  "seq": $SEQ,
  "committed_at": "$TIMESTAMP",
  "http_status": "$HTTP_STATUS"
}
EOF
    echo "[$TIMESTAMP] COMMITTED: $MARKER (HTTP $HTTP_STATUS)" | tee -a "$LOG_FILE"
    SEQ=$((SEQ + 1))
  else
    echo "[$TIMESTAMP] FAILED: $MARKER (HTTP $HTTP_STATUS)" | tee -a "$LOG_FILE"
  fi

  sleep 1
done
