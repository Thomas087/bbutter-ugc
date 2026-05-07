#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ../scripts/lib.sh

# --- test: load_env reads KEY=VALUE lines and exports them ---
tmp="$(mktemp)"
cat > "$tmp" <<EOF
FOO=bar
BAZ=qux quux
EOF
load_env "$tmp"
assert_eq "bar" "${FOO}" "FOO should be loaded"
assert_eq "qux quux" "${BAZ}" "BAZ should be loaded (with space)"
rm "$tmp"

# --- test: atomic_write writes to final path only after success ---
target="$(mktemp -u)"
atomic_write "$target" "hello"
assert_file_exists "$target"
assert_eq "hello" "$(cat "$target")" "atomic_write content"
rm "$target"

# --- test: merge_by_key unions arrays by key, deduping ---
existing='[{"id":"a","v":1},{"id":"b","v":2}]'
incoming='[{"id":"b","v":22},{"id":"c","v":3}]'
result="$(merge_by_key "id" "$existing" "$incoming")"
count="$(echo "$result" | jq 'length')"
assert_eq "3" "$count" "merged array length"
# incoming wins on conflict (b.v should be 22)
b_val="$(echo "$result" | jq -r '.[] | select(.id=="b") | .v')"
assert_eq "22" "$b_val" "incoming wins on conflict"

# --- test: load_env handles file without trailing newline ---
tmp="$(mktemp)"
printf 'NO_NL=end' > "$tmp"   # deliberately no \n
unset NO_NL
load_env "$tmp"
assert_eq "end" "${NO_NL:-}" "NO_NL should load even without trailing newline"
rm "$tmp"

# --- test: load_env trims whitespace around = and in key ---
tmp="$(mktemp)"
cat > "$tmp" <<'EOF'
SPACED = value-a
  LEADING=value-b
EOF
unset SPACED LEADING
load_env "$tmp"
assert_eq "value-a" "${SPACED:-}" "SPACED should parse with whitespace around ="
assert_eq "value-b" "${LEADING:-}" "LEADING should parse with leading whitespace on key"
rm "$tmp"

# --- test: load_env strips CR from values (CRLF line endings) ---
tmp="$(mktemp)"
printf 'CRLF=value\r\nSECOND=ok\r\n' > "$tmp"
unset CRLF SECOND
load_env "$tmp"
assert_eq "value" "${CRLF:-}" "CRLF value should be stripped of \\r"
assert_eq "ok" "${SECOND:-}" "SECOND should also be stripped of \\r"
rm "$tmp"

# --- test: load_env skips comment lines and blank lines ---
tmp="$(mktemp)"
cat > "$tmp" <<'EOF'
# comment
KEPT=yes

# another
SKIPPED_COMMENT=no
EOF
unset KEPT SKIPPED_COMMENT
# Note: "SKIPPED_COMMENT" is not actually skipped — it's a regular key.
# The blank line and the "# comment" lines should be skipped.
load_env "$tmp"
assert_eq "yes" "${KEPT:-}" "non-comment keys load"
assert_eq "no" "${SKIPPED_COMMENT:-}" "regular keys load even with 'SKIPPED' in name"
rm "$tmp"

# --- cache_fresh: missing file -> 1 ---
missing="$(mktemp -u)"
if cache_fresh "$missing" ".last_fetched" 86400; then
  echo "FAIL: cache_fresh returned 0 on missing file" >&2; exit 1
fi

# --- cache_fresh: recent timestamp (1h ago) within 24h -> 0 ---
tmp="$(mktemp)"
recent_iso=$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)
printf '{"last_fetched":"%s"}' "$recent_iso" > "$tmp"
if ! cache_fresh "$tmp" ".last_fetched" 86400; then
  echo "FAIL: cache_fresh should be fresh for 1h-old timestamp" >&2; exit 1
fi
rm "$tmp"

# --- cache_fresh: stale timestamp (2 days ago) outside 24h -> 1 ---
tmp="$(mktemp)"
stale_iso=$(date -u -v-2d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-2 days' +%Y-%m-%dT%H:%M:%SZ)
printf '{"last_fetched":"%s"}' "$stale_iso" > "$tmp"
if cache_fresh "$tmp" ".last_fetched" 86400; then
  echo "FAIL: cache_fresh should be stale for 2d-old timestamp" >&2; exit 1
fi
rm "$tmp"

# --- cache_fresh: missing JSON field -> 1 ---
tmp="$(mktemp)"
echo '{"other":"x"}' > "$tmp"
if cache_fresh "$tmp" ".last_fetched" 86400; then
  echo "FAIL: cache_fresh should return 1 when field is absent" >&2; exit 1
fi
rm "$tmp"

# --- cache_fresh: unparseable timestamp -> 1 ---
tmp="$(mktemp)"
echo '{"last_fetched":"not-a-date"}' > "$tmp"
if cache_fresh "$tmp" ".last_fetched" 86400 2>/dev/null; then
  echo "FAIL: cache_fresh should return 1 for unparseable timestamp" >&2; exit 1
fi
rm "$tmp"

echo "OK"
