#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./assert.sh

# Source the script first so the real function is defined, then override
# the HTTP layer. Bash resolves function names at call-time, so the later
# definitions win when fetch_instagram is invoked below.
source ../scripts/fetch_instagram.sh

# _http_get is called with a "purpose" tag so tests can serve different
# fixtures depending on which API call is being made.
_http_get() {
  case "$1" in
    brightdata_download) cat fixtures/brightdata_response.json ;;
    *) echo "unexpected http call: $1" >&2; return 1 ;;
  esac
}
# _http_post is called for snapshot-trigger. In tests it returns a fake snapshot id.
_http_post() {
  case "$1" in
    brightdata_trigger) echo '{"snapshot_id":"S_TEST"}' ;;
    *) echo "unexpected http post: $1" >&2; return 1 ;;
  esac
}
# _http_get_status for polling. In tests it returns "ready" immediately.
_http_get_status() {
  echo "ready"
}

# Case A: empty cache. After fetch, cache contains the two non-video posts;
# videos/reels in the fixture (V1, V2) are dropped before merge.
tmpdir="$(mktemp -d)"
export CACHE_DIR="$tmpdir"
fetch_instagram "buttbutter_official" "gd_TEST_DATASET"
cache="$tmpdir/instagram/buttbutter_official.json"
assert_file_exists "$cache"
assert_json_field "$cache" ".handle" "buttbutter_official"
assert_json_field "$cache" ".posts | length" "2"
assert_json_field "$cache" '.posts | map(.post_id) | sort | join(",")' "P1,P2"

# Case B: existing cache with P1 (old version). Incoming P1 wins; P2 added.
echo '{"handle":"buttbutter_official","last_fetched":"2026-04-01T00:00:00Z","posts":[{"post_id":"P1","caption":"old caption","likes":1}]}' > "$cache"
fetch_instagram "buttbutter_official" "gd_TEST_DATASET"
assert_json_field "$cache" ".posts | length" "2"
assert_json_field "$cache" '.posts | map(select(.post_id=="P1"))[0].caption' "post 1"

rm -rf "$tmpdir"

# --- Case C: snapshot failed -> exit 1, cache untouched ---
tmpdir_c="$(mktemp -d)"
export CACHE_DIR="$tmpdir_c"
pre_cache="$tmpdir_c/instagram/buttbutter_official.json"
mkdir -p "$(dirname "$pre_cache")"
echo '{"handle":"buttbutter_official","last_fetched":"2026-04-01T00:00:00Z","posts":[{"post_id":"PRE","caption":"untouched"}]}' > "$pre_cache"
pre_mtime="$(stat -f %m "$pre_cache" 2>/dev/null || stat -c %Y "$pre_cache")"

_http_get_status() { echo "failed"; }
rc=0
fetch_instagram "buttbutter_official" "gd_TEST_DATASET" || rc=$?
assert_eq "1" "$rc" "fetch_instagram should exit 1 on 'failed' status"
assert_json_field "$pre_cache" '.posts[0].post_id' "PRE"
assert_json_field "$pre_cache" '.posts[0].caption' "untouched"
post_mtime="$(stat -f %m "$pre_cache" 2>/dev/null || stat -c %Y "$pre_cache")"
assert_eq "$pre_mtime" "$post_mtime" "cache file mtime should be unchanged on 'failed'"
rm -rf "$tmpdir_c"

# --- Case D: snapshot never becomes ready -> exit 2, cache untouched ---
tmpdir_d="$(mktemp -d)"
export CACHE_DIR="$tmpdir_d"
pre_cache_d="$tmpdir_d/instagram/buttbutter_official.json"
mkdir -p "$(dirname "$pre_cache_d")"
echo '{"handle":"buttbutter_official","last_fetched":"2026-04-01T00:00:00Z","posts":[{"post_id":"PRE","caption":"untouched"}]}' > "$pre_cache_d"

_http_get_status() { echo "running"; }
# Override sleep to make the test instant (no actual wait).
sleep() { :; }
rc=0
fetch_instagram "buttbutter_official" "gd_TEST_DATASET" || rc=$?
unset -f sleep
assert_eq "2" "$rc" "fetch_instagram should exit 2 on poll timeout"
assert_json_field "$pre_cache_d" '.posts[0].post_id' "PRE" "cache content preserved on timeout"
rm -rf "$tmpdir_d"

# --- Case E: trigger returns no snapshot_id -> exit 1 ---
tmpdir_e="$(mktemp -d)"
export CACHE_DIR="$tmpdir_e"

_http_post() {
  case "$1" in
    brightdata_trigger) echo '{"error":"bad dataset id"}' ;;
    *) echo "unexpected: $1" >&2; return 1 ;;
  esac
}
_http_get_status() { echo "ready"; }
rc=0
fetch_instagram "buttbutter_official" "gd_TEST_DATASET" 2>/dev/null || rc=$?
assert_eq "1" "$rc" "fetch_instagram should exit 1 when trigger returns no snapshot_id"
# Cache should not have been created.
[[ ! -f "$tmpdir_e/instagram/buttbutter_official.json" ]] \
  || { echo "FAIL: cache file should not exist on early failure" >&2; exit 1; }
rm -rf "$tmpdir_e"

# --- Cases F-H: trigger body capture, with the 30-day lookback floor ---
# fetch_instagram captures the trigger response via $(_http_post ...), which
# runs in a subshell. Shell variables don't survive that, so we capture the
# body to a file that the parent shell can read.
_BODY_CAPTURE_FILE="$(mktemp)"
_http_post() {
  case "$1" in
    brightdata_trigger)
      # $@ is: tag url --data body. Extract the body.
      shift 2
      while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--data" ]]; then
          printf '%s' "$2" > "$_BODY_CAPTURE_FILE"
          shift 2
        else
          shift
        fi
      done
      echo '{"snapshot_id":"S_TEST"}' ;;
    *) echo "unexpected: $1" >&2; return 1 ;;
  esac
}
_http_get() { cat fixtures/brightdata_response.json; }
_http_get_status() { echo "ready"; }

# Compute expected dates using the same logic as the script, so tests are
# independent of when they run.
recent_iso=$(date -u -v-5d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-5 days' +%Y-%m-%dT%H:%M:%SZ)
recent_mmddyyyy=$(date -u -v-5d +%m-%d-%Y 2>/dev/null || date -u -d '-5 days' +%m-%d-%Y)

# Case F: empty cache -> no start_date (full backfill from account origin).
tmpdir_f="$(mktemp -d)"
export CACHE_DIR="$tmpdir_f"
: > "$_BODY_CAPTURE_FILE"
fetch_instagram "buttbutter_official" "gd_TEST_DATASET"
has_start_date="$(jq -r '.input[0] | has("start_date")' "$_BODY_CAPTURE_FILE")"
assert_eq "false" "$has_start_date" "first fetch omits start_date (full backfill)"
url_in_body="$(jq -r '.input[0].url' "$_BODY_CAPTURE_FILE")"
assert_eq "https://www.instagram.com/buttbutter_official/" "$url_in_body"
rm -rf "$tmpdir_f"

# Case G: cache with recent last_fetched (5 days ago) -> start_date = that date.
tmpdir_g="$(mktemp -d)"
export CACHE_DIR="$tmpdir_g"
pre_cache_g="$tmpdir_g/instagram/buttbutter_official.json"
mkdir -p "$(dirname "$pre_cache_g")"
printf '{"handle":"buttbutter_official","last_fetched":"%s","posts":[{"post_id":"OLD"}]}' "$recent_iso" > "$pre_cache_g"
: > "$_BODY_CAPTURE_FILE"
fetch_instagram "buttbutter_official" "gd_TEST_DATASET"
start_date_in_body="$(jq -r '.input[0].start_date' "$_BODY_CAPTURE_FILE")"
assert_eq "$recent_mmddyyyy" "$start_date_in_body" "start_date = last_fetched (incremental)"
rm -rf "$tmpdir_g"

# Case H: cache with stale last_fetched (2 years ago) -> start_date = that date
# (no floor, trust the cache as the incremental anchor).
tmpdir_h="$(mktemp -d)"
export CACHE_DIR="$tmpdir_h"
pre_cache_h="$tmpdir_h/instagram/buttbutter_official.json"
mkdir -p "$(dirname "$pre_cache_h")"
echo '{"handle":"buttbutter_official","last_fetched":"2024-01-01T00:00:00Z","posts":[{"post_id":"OLD"}]}' > "$pre_cache_h"
: > "$_BODY_CAPTURE_FILE"
fetch_instagram "buttbutter_official" "gd_TEST_DATASET"
start_date_in_body="$(jq -r '.input[0].start_date' "$_BODY_CAPTURE_FILE")"
assert_eq "01-01-2024" "$start_date_in_body" "stale last_fetched used as-is (no floor)"
rm -rf "$tmpdir_h"
rm -f "$_BODY_CAPTURE_FILE"

# --- Case I: fresh cache (<24h) -> fetch skipped, no HTTP call, cache untouched ---
tmpdir_i="$(mktemp -d)"
export CACHE_DIR="$tmpdir_i"
pre_cache_i="$tmpdir_i/instagram/buttbutter_official.json"
mkdir -p "$(dirname "$pre_cache_i")"
fresh_iso=$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)
printf '{"handle":"buttbutter_official","last_fetched":"%s","posts":[{"post_id":"FRESH"}]}' "$fresh_iso" > "$pre_cache_i"
pre_mtime_i="$(stat -f %m "$pre_cache_i" 2>/dev/null || stat -c %Y "$pre_cache_i")"
# Any HTTP call would fail the test.
_http_post() { echo "FAIL: _http_post called despite fresh cache" >&2; return 99; }
_http_get() { echo "FAIL: _http_get called despite fresh cache" >&2; return 99; }
_http_get_status() { echo "FAIL: _http_get_status called despite fresh cache" >&2; return 99; }
rc=0
fetch_instagram "buttbutter_official" "gd_TEST_DATASET" 2>/dev/null || rc=$?
assert_eq "0" "$rc" "fresh cache should skip cleanly with exit 0"
assert_json_field "$pre_cache_i" '.posts[0].post_id' "FRESH" "cache content untouched"
post_mtime_i="$(stat -f %m "$pre_cache_i" 2>/dev/null || stat -c %Y "$pre_cache_i")"
assert_eq "$pre_mtime_i" "$post_mtime_i" "cache file mtime unchanged on fresh-skip"
rm -rf "$tmpdir_i"

# --- Case J: fresh cache + --force -> fetch proceeds ---
tmpdir_j="$(mktemp -d)"
export CACHE_DIR="$tmpdir_j"
pre_cache_j="$tmpdir_j/instagram/buttbutter_official.json"
mkdir -p "$(dirname "$pre_cache_j")"
printf '{"handle":"buttbutter_official","last_fetched":"%s","posts":[{"post_id":"OLD"}]}' "$fresh_iso" > "$pre_cache_j"
# Restore real stubs.
_http_post() {
  case "$1" in
    brightdata_trigger) echo '{"snapshot_id":"S_TEST"}' ;;
    *) echo "unexpected: $1" >&2; return 1 ;;
  esac
}
_http_get() { cat fixtures/brightdata_response.json; }
_http_get_status() { echo "ready"; }
fetch_instagram "buttbutter_official" "gd_TEST_DATASET" --force
# Merged P1+P2 plus pre-existing OLD = 3 posts.
assert_json_field "$pre_cache_j" ".posts | length" "3" "--force bypasses freshness guard"
rm -rf "$tmpdir_j"

# --- Case K: fresh cache + FORCE_REFRESH=1 -> fetch proceeds ---
tmpdir_k="$(mktemp -d)"
export CACHE_DIR="$tmpdir_k"
pre_cache_k="$tmpdir_k/instagram/buttbutter_official.json"
mkdir -p "$(dirname "$pre_cache_k")"
printf '{"handle":"buttbutter_official","last_fetched":"%s","posts":[{"post_id":"OLD"}]}' "$fresh_iso" > "$pre_cache_k"
FORCE_REFRESH=1 fetch_instagram "buttbutter_official" "gd_TEST_DATASET"
assert_json_field "$pre_cache_k" ".posts | length" "3" "FORCE_REFRESH=1 bypasses freshness guard"
rm -rf "$tmpdir_k"

echo "OK"
