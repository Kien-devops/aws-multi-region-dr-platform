#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

cat > "$TEST_DIR/unified-writer.state" <<'EOF'
RUN_ID=run-A
LAST_DB_ACK=100
LAST_STORAGE_ACK=100
INTERVAL_SECONDS=1
UPDATED_AT=2026-10-12T10:00:00Z
EOF

bash "$SCRIPT_DIR/capture-pre-failure-state.sh" \
  "$TEST_DIR/unified-writer.state" "$TEST_DIR/pre-failure.state" >/dev/null

sed -i 's/LAST_DB_ACK=100/LAST_DB_ACK=200/' "$TEST_DIR/unified-writer.state"
grep -q '^LAST_DB_ACK=100$' "$TEST_DIR/pre-failure.state"
if bash "$SCRIPT_DIR/capture-pre-failure-state.sh" \
  "$TEST_DIR/unified-writer.state" "$TEST_DIR/pre-failure.state" >/dev/null 2>&1; then
  echo 'capture unexpectedly overwrote pre-failure.state' >&2
  exit 1
fi

mkdir "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
url="${*: -1}"
[[ "$url" == *'runId=run-A'* ]] || exit 1
if [[ "$url" == *'/orders/latest'* ]]; then
  expected_cutoff="$EXPECT_DB_CUTOFF"
  recovered="$DB_RECOVERED"
else
  expected_cutoff="$EXPECT_STORAGE_CUTOFF"
  recovered="$STORAGE_RECOVERED"
fi
if [[ "$url" != *"maxSequence=$expected_cutoff"* ]]; then
  printf '{"runId":"run-A","marker":"DR-run-A-SEQ-000120","sequence":120}'
  exit 0
fi
printf '{"runId":"run-A","marker":"DR-run-A-SEQ-%06d","sequence":%d}' "$recovered" "$recovered"
EOF
chmod +x "$TEST_DIR/bin/curl"

PATH="$TEST_DIR/bin:$PATH" \
EXPECT_DB_CUTOFF=100 EXPECT_STORAGE_CUTOFF=100 DB_RECOVERED=98 STORAGE_RECOVERED=90 \
DB_LATEST_URL='https://app.example/api/v1/orders/latest' \
STORAGE_LATEST_URL='https://files.example/api/v1/storage/events/latest' \
  bash "$SCRIPT_DIR/unified-rpo-check.sh" "$TEST_DIR/pre-failure.state" > "$TEST_DIR/result.txt"

grep -q 'Database lost records : 2' "$TEST_DIR/result.txt"
grep -q 'Storage lost records  : 10' "$TEST_DIR/result.txt"

sed -e 's/LAST_STORAGE_ACK=100/LAST_STORAGE_ACK=97/' \
  "$TEST_DIR/pre-failure.state" > "$TEST_DIR/unequal.state"
PATH="$TEST_DIR/bin:$PATH" \
EXPECT_DB_CUTOFF=100 EXPECT_STORAGE_CUTOFF=97 DB_RECOVERED=98 STORAGE_RECOVERED=90 \
DB_LATEST_URL='https://app.example/api/v1/orders/latest' \
STORAGE_LATEST_URL='https://files.example/api/v1/storage/events/latest' \
  bash "$SCRIPT_DIR/unified-rpo-check.sh" "$TEST_DIR/unequal.state" > "$TEST_DIR/unequal-result.txt"
grep -q 'Database lost records : 2' "$TEST_DIR/unequal-result.txt"
grep -q 'Storage lost records  : 7' "$TEST_DIR/unequal-result.txt"

if PATH="$TEST_DIR/bin:$PATH" \
  EXPECT_DB_CUTOFF=100 EXPECT_STORAGE_CUTOFF=97 DB_RECOVERED=101 STORAGE_RECOVERED=90 \
  DB_LATEST_URL='https://app.example/api/v1/orders/latest' \
  STORAGE_LATEST_URL='https://files.example/api/v1/storage/events/latest' \
    bash "$SCRIPT_DIR/unified-rpo-check.sh" "$TEST_DIR/unequal.state" > /dev/null 2> "$TEST_DIR/contract-error.txt"; then
  echo 'checker accepted a recovered DB sequence above its cutoff' >&2
  exit 1
fi
grep -q 'Database API contract violation' "$TEST_DIR/contract-error.txt"
echo 'Unified RPO script tests: PASS'
