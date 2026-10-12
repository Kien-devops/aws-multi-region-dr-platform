#!/usr/bin/env bash
# Freezes the last acknowledged sequences at disaster declaration time (T0).

set -euo pipefail

LIVE_STATE_FILE="${1:-unified-writer.state}"
SNAPSHOT_FILE="${2:-pre-failure.state}"

[[ -f "$LIVE_STATE_FILE" ]] || { echo "Missing live writer state: $LIVE_STATE_FILE" >&2; exit 2; }
[[ ! -e "$SNAPSHOT_FILE" ]] || {
  echo "Refusing to overwrite immutable snapshot: $SNAPSHOT_FILE" >&2
  exit 1
}

state_copy=$(mktemp)
trap 'rm -f "$state_copy"' EXIT
cp -- "$LIVE_STATE_FILE" "$state_copy"

read_value() {
  sed -n "s/^$1=//p" "$state_copy" | tail -n 1
}

run_id=$(read_value RUN_ID)
last_db=$(read_value LAST_DB_ACK)
last_storage=$(read_value LAST_STORAGE_ACK)
interval=$(read_value INTERVAL_SECONDS)

[[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,63}$ ]] || { echo "Invalid RUN_ID in live state" >&2; exit 2; }
[[ "$last_db" =~ ^[0-9]+$ && "$last_storage" =~ ^[0-9]+$ && "$interval" =~ ^[1-9][0-9]*$ ]] || {
  echo "Live writer state is incomplete or invalid; retry capture" >&2
  exit 2
}

captured_at=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
umask 077
{
  printf 'RUN_ID=%s\n' "$run_id"
  printf 'LAST_DB_ACK=%s\n' "$last_db"
  printf 'LAST_STORAGE_ACK=%s\n' "$last_storage"
  printf 'INTERVAL_SECONDS=%s\n' "$interval"
  printf 'CAPTURED_AT=%s\n' "$captured_at"
} > "$SNAPSHOT_FILE"

echo "Captured immutable T0 state in $SNAPSHOT_FILE for RUN_ID=$run_id"
