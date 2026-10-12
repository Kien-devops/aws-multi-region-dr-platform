#!/usr/bin/env bash
# Compares independently acknowledged DB/storage sequences with recovered APIs.

set -euo pipefail

STATE_FILE="${1:-pre-failure.state}"
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
run_id=$(read_value RUN_ID)
[[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,63}$ ]] || {
  echo "Invalid RUN_ID in pre-failure state" >&2
  exit 2
}
[[ "$last_db" =~ ^[0-9]+$ && "$last_storage" =~ ^[0-9]+$ && "$interval" =~ ^[1-9][0-9]*$ ]] || {
  echo "Invalid state file" >&2
  exit 2
}

append_query() {
  local separator='?'
  [[ "$1" == *'?'* ]] && separator='&'
  printf '%s%srunId=%s&maxSequence=%s' "$1" "$separator" "$run_id" "$2"
}

db_response=$(curl -fsS --connect-timeout 3 --max-time 10 "$(append_query "$DB_LATEST_URL" "$last_db")")
storage_response=$(curl -fsS --connect-timeout 3 --max-time 10 "$(append_query "$STORAGE_LATEST_URL" "$last_storage")")

extract_sequence() {
  printf '%s' "$1" | sed -n 's/.*"sequence"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | tail -n 1
}

extract_run_id() {
  printf '%s' "$1" | sed -n 's/.*"runId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tail -n 1
}

db_response_run_id=$(extract_run_id "$db_response")
storage_response_run_id=$(extract_run_id "$storage_response")
[[ "$db_response_run_id" == "$run_id" && "$storage_response_run_id" == "$run_id" ]] || {
  echo "Recovered API response RUN_ID does not match pre-failure state" >&2
  exit 1
}

db_recovered=$(extract_sequence "$db_response")
storage_recovered=$(extract_sequence "$storage_response")
[[ "$db_recovered" =~ ^[0-9]+$ && "$storage_recovered" =~ ^[0-9]+$ ]] || {
  echo "Recovered API response does not contain valid numeric sequences" >&2
  exit 1
}

(( db_recovered <= last_db )) || {
  echo "Database API contract violation: recovered sequence exceeds maxSequence=$last_db" >&2
  exit 1
}
(( storage_recovered <= last_storage )) || {
  echo "Storage API contract violation: recovered sequence exceeds maxSequence=$last_storage" >&2
  exit 1
}

db_lost=$((last_db - db_recovered))
storage_lost=$((last_storage - storage_recovered))

cat <<EOF
Run ID                : $run_id
Database acknowledged : $last_db
Database recovered    : $db_recovered
Database lost records : $db_lost
Database time gap     : approximately $((db_lost * interval)) seconds when cadence was stable

Storage acknowledged  : $last_storage
Storage recovered     : $storage_recovered
Storage lost records  : $storage_lost
Storage time gap      : approximately $((storage_lost * interval)) seconds when cadence was stable
EOF
