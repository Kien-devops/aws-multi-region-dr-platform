#!/usr/bin/env bash
# Compares independently acknowledged DB/storage sequences with recovered APIs.

set -euo pipefail

STATE_FILE="${1:-unified-writer.state}"
DB_LATEST_URL="${DB_LATEST_URL:-}"
STORAGE_LATEST_URL="${STORAGE_LATEST_URL:-}"

if [[ ! -f "$STATE_FILE" || -z "$DB_LATEST_URL" || -z "$STORAGE_LATEST_URL" ]]; then
  echo "Usage: DB_LATEST_URL=https://... STORAGE_LATEST_URL=https://... $0 [state-file]" >&2
  exit 2
fi

read_value() {
  sed -n "s/^$1=//p" "$STATE_FILE" | tail -n 1
}

last_db=$(read_value LAST_DB_ACK)
last_storage=$(read_value LAST_STORAGE_ACK)
interval=$(read_value INTERVAL_SECONDS)
[[ "$last_db" =~ ^[0-9]+$ && "$last_storage" =~ ^[0-9]+$ && "$interval" =~ ^[0-9]+$ ]] || {
  echo "Invalid state file" >&2
  exit 2
}

db_response=$(curl -fsS --connect-timeout 3 --max-time 10 "$DB_LATEST_URL")
storage_response=$(curl -fsS --connect-timeout 3 --max-time 10 "$STORAGE_LATEST_URL")

db_recovered=$(printf '%s' "$db_response" | grep -o 'DR-SEQ-[0-9]\{6\}' | sed 's/DR-SEQ-0*//' | sort -n | tail -n 1 || true)
storage_recovered=$(printf '%s' "$storage_response" | sed -n 's/.*"sequence"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | tail -n 1)
db_recovered=${db_recovered:-0}
storage_recovered=${storage_recovered:-0}
[[ "$db_recovered" =~ ^[0-9]+$ && "$storage_recovered" =~ ^[0-9]+$ ]] || {
  echo "Recovered API response does not contain valid numeric sequences" >&2
  exit 1
}

db_lost=$((last_db > db_recovered ? last_db - db_recovered : 0))
storage_lost=$((last_storage > storage_recovered ? last_storage - storage_recovered : 0))

cat <<EOF
Database acknowledged : $last_db
Database recovered    : $db_recovered
Database lost records : $db_lost
Database time gap     : approximately $((db_lost * interval)) seconds when cadence was stable

Storage acknowledged  : $last_storage
Storage recovered     : $storage_recovered
Storage lost records  : $storage_lost
Storage time gap      : approximately $((storage_lost * interval)) seconds when cadence was stable
EOF
