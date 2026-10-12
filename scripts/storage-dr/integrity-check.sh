#!/usr/bin/env bash
# Prepare a known file before DR, then download and compare SHA-256 after DR.

set -euo pipefail

MODE="${1:-}"
FILE_URL="${FILE_URL:-}"
STATE_FILE="${STATE_FILE:-storage-integrity.state}"
TEST_FILE="${TEST_FILE:-dr-test.bin}"
SIZE_MB="${SIZE_MB:-1}"

if [[ -z "$FILE_URL" || ( "$MODE" != prepare && "$MODE" != verify ) ]]; then
  echo "Usage: FILE_URL=https://.../api/v1/files $0 prepare|verify" >&2
  exit 2
fi

case "$SIZE_MB" in ''|*[!0-9]*|0) echo "SIZE_MB must be a positive integer" >&2; exit 2 ;; esac

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  else openssl dgst -sha256 "$1" | awk '{print $NF}'; fi
}

if [[ "$MODE" == prepare ]]; then
  dd if=/dev/zero of="$TEST_FILE" bs=1M count="$SIZE_MB" status=none
  original=$(sha256_file "$TEST_FILE")
  response=$(curl -fsS --connect-timeout 3 --max-time 60 -F "file=@$TEST_FILE" "$FILE_URL")
  file_id=$(printf '%s' "$response" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  [[ -n "$file_id" ]] || { echo "Upload response has no file id" >&2; exit 1; }
  umask 077
  {
    printf 'FILE_ID=%s\n' "$file_id"
    printf 'ORIGINAL_SHA256=%s\n' "$original"
    printf 'FILE_NAME=%s\n' "$TEST_FILE"
  } > "$STATE_FILE"
  printf 'File: %s\nOriginal SHA256: %s\nFile ID: %s\n' "$TEST_FILE" "$original" "$file_id"
  exit 0
fi

[[ -f "$STATE_FILE" ]] || { echo "Missing $STATE_FILE; run prepare first" >&2; exit 2; }
file_id=$(sed -n 's/^FILE_ID=//p' "$STATE_FILE" | tail -n 1)
original=$(sed -n 's/^ORIGINAL_SHA256=//p' "$STATE_FILE" | tail -n 1)
[[ "$file_id" =~ ^[A-Za-z0-9_-]+$ && "$original" =~ ^[a-fA-F0-9]{64}$ ]] || {
  echo "Invalid integrity state" >&2
  exit 2
}

recovered=$(mktemp)
trap 'rm -f "$recovered"' EXIT
curl -fsS --connect-timeout 3 --max-time 60 -o "$recovered" "$FILE_URL/$file_id/download"
actual=$(sha256_file "$recovered")

printf 'File ID          : %s\nOriginal SHA256  : %s\nRecovered SHA256 : %s\n' "$file_id" "$original" "$actual"
if [[ "$original" == "$actual" ]]; then
  echo 'Integrity: PASS'
else
  echo 'Integrity: FAIL'
  exit 1
fi
