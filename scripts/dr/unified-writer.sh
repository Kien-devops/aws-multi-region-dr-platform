#!/usr/bin/env bash
# Generates the same deterministic marker for database and storage paths.

set -u

DB_URL="${DB_URL:-}"
STORAGE_URL="${STORAGE_URL:-}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-1}"
LOG_FILE="${LOG_FILE:-unified-writer.csv}"
STATE_FILE="${STATE_FILE:-unified-writer.state}"

if [[ -z "$DB_URL" || -z "$STORAGE_URL" ]]; then
  echo "Usage: DB_URL=https://.../orders STORAGE_URL=https://.../storage/events $0" >&2
  exit 2
fi

case "$INTERVAL_SECONDS" in
  ''|*[!0-9]*) echo "INTERVAL_SECONDS must be a positive integer" >&2; exit 2 ;;
  0) echo "INTERVAL_SECONDS must be greater than zero" >&2; exit 2 ;;
esac

printf 'timestamp,sequence,db_status,storage_status\n' > "$LOG_FILE"
seq=1
last_db=0
last_storage=0

write_state() {
  umask 077
  {
    printf 'LAST_DB_ACK=%s\n' "$last_db"
    printf 'LAST_STORAGE_ACK=%s\n' "$last_storage"
    printf 'INTERVAL_SECONDS=%s\n' "$INTERVAL_SECONDS"
    printf 'UPDATED_AT=%s\n' "$1"
  } > "$STATE_FILE"
}

trap 'echo "Writer stopped; evidence: $LOG_FILE, $STATE_FILE"; exit 0' INT TERM

while true; do
  marker=$(printf 'DR-SEQ-%06d' "$seq")
  timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  db_payload=$(printf '{"item_id":"item-dr-benchmark","quantity":1,"marker":"%s","client_timestamp":"%s"}' "$marker" "$timestamp")
  storage_payload=$(printf '{"sequence":%d,"marker":"%s"}' "$seq" "$marker")

  if ! db_status=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    -H 'Content-Type: application/json' -X POST -d "$db_payload" "$DB_URL" 2>/dev/null); then
    db_status=000
  fi
  if ! storage_status=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    -H 'Content-Type: application/json' -X POST -d "$storage_payload" "$STORAGE_URL" 2>/dev/null); then
    storage_status=000
  fi

  [[ "$db_status" =~ ^20[0-9]$ ]] && last_db=$seq
  [[ "$storage_status" =~ ^20[0-9]$ ]] && last_storage=$seq
  printf '%s,%d,%s,%s\n' "$timestamp" "$seq" "$db_status" "$storage_status" | tee -a "$LOG_FILE"
  write_state "$timestamp"
  seq=$((seq + 1))
  sleep "$INTERVAL_SECONDS"
done
