#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./assert.sh

# Source the script first, then override HTTP. Bash resolves functions
# at call-time, so the later definition wins.
source ../scripts/fetch_reviews.sh

# Fixtures use per_page=2; tell the script to match so pagination logic exercises.
export JUDGEME_PER_PAGE=2

# Track pagination across calls.
_PAGE_CALLS=0
_http_get() {
  case "$1" in
    judgeme_page)
      _PAGE_CALLS=$((_PAGE_CALLS + 1))
      if [[ $_PAGE_CALLS -eq 1 ]]; then
        cat fixtures/judgeme_response_page1.json
      else
        cat fixtures/judgeme_response_page2.json
      fi ;;
    *) echo "unexpected: $1" >&2; return 1 ;;
  esac
}

# Case A: empty cache, two pages of reviews. All 3 merged.
tmpdir="$(mktemp -d)"
export CACHE_DIR="$tmpdir"
fetch_reviews "butt-butter-original" "12345"
cache="$tmpdir/reviews/butt-butter-original.json"
assert_file_exists "$cache"
assert_json_field "$cache" ".product_slug" "butt-butter-original"
assert_json_field "$cache" ".reviews | length" "3"

# Case B: existing cache with review id=1 (old version). Incoming wins, 3 total.
_PAGE_CALLS=0
echo '{"product_slug":"butt-butter-original","judgeme_product_id":"12345","last_fetched":"2026-03-01T00:00:00Z","reviews":[{"id":1,"title":"old title","rating":3}]}' > "$cache"
fetch_reviews "butt-butter-original" "12345"
assert_json_field "$cache" ".reviews | length" "3"
assert_json_field "$cache" '.reviews | map(select(.id==1))[0].title' "Excellent"

rm -rf "$tmpdir"

# --- Case C: _http_get returns nonzero (HTTP failure) -> exit 1, cache preserved ---
tmpdir_c="$(mktemp -d)"
export CACHE_DIR="$tmpdir_c"
pre_cache_c="$tmpdir_c/reviews/butt-butter-original.json"
mkdir -p "$(dirname "$pre_cache_c")"
echo '{"product_slug":"butt-butter-original","judgeme_product_id":"12345","last_fetched":"2026-04-01T00:00:00Z","reviews":[{"id":99,"title":"PRE"}]}' > "$pre_cache_c"

_http_get() { echo "transient failure"; return 1; }
rc=0
fetch_reviews "butt-butter-original" "12345" 2>/dev/null || rc=$?
assert_eq "1" "$rc" "fetch_reviews should exit 1 on HTTP failure"
assert_json_field "$pre_cache_c" '.reviews[0].id' "99" "existing cache preserved on HTTP failure"
assert_json_field "$pre_cache_c" '.reviews[0].title' "PRE"
rm -rf "$tmpdir_c"

# --- Case D: response is non-JSON -> exit 1, cache preserved ---
tmpdir_d="$(mktemp -d)"
export CACHE_DIR="$tmpdir_d"
pre_cache_d="$tmpdir_d/reviews/butt-butter-original.json"
mkdir -p "$(dirname "$pre_cache_d")"
echo '{"product_slug":"butt-butter-original","judgeme_product_id":"12345","last_fetched":"2026-04-01T00:00:00Z","reviews":[{"id":99,"title":"PRE"}]}' > "$pre_cache_d"

_http_get() { echo "<html>500 server error</html>"; }
rc=0
fetch_reviews "butt-butter-original" "12345" 2>/dev/null || rc=$?
assert_eq "1" "$rc" "fetch_reviews should exit 1 on non-JSON response"
assert_json_field "$pre_cache_d" '.reviews[0].id' "99" "existing cache preserved on non-JSON response"
rm -rf "$tmpdir_d"

# --- Case E: empty result set (zero reviews) -> exit 0, cache written with no reviews ---
tmpdir_e="$(mktemp -d)"
export CACHE_DIR="$tmpdir_e"
_http_get() {
  case "$1" in
    judgeme_page) echo '{"reviews":[],"current_page":1,"per_page":50,"total":0}' ;;
    *) echo "unexpected" >&2; return 1 ;;
  esac
}
rc=0
fetch_reviews "empty-product" "99999" || rc=$?
assert_eq "0" "$rc" "empty result should exit 0"
assert_file_exists "$tmpdir_e/reviews/empty-product.json"
assert_json_field "$tmpdir_e/reviews/empty-product.json" ".reviews | length" "0"
rm -rf "$tmpdir_e"

# --- Case F: pagination cap (>100 pages) -> exit 1 ---
tmpdir_f="$(mktemp -d)"
export CACHE_DIR="$tmpdir_f"
# Always return a full "there's more" page so neither break condition fires
# until the 100-page safety cap. Items == per_page (2), total=999 keeps going.
_http_get() {
  case "$1" in
    judgeme_page) printf '{"reviews":[{"id":%d},{"id":%d}],"current_page":1,"per_page":2,"total":999}' "$RANDOM" "$RANDOM" ;;
    *) echo "unexpected" >&2; return 1 ;;
  esac
}
rc=0
fetch_reviews "runaway-product" "88888" 2>/dev/null || rc=$?
assert_eq "1" "$rc" "pagination cap should exit 1"
rm -rf "$tmpdir_f"

# --- Case G: fresh cache (<24h) -> fetch skipped, no HTTP call, cache untouched ---
tmpdir_g="$(mktemp -d)"
export CACHE_DIR="$tmpdir_g"
pre_cache_g="$tmpdir_g/reviews/butt-butter-original.json"
mkdir -p "$(dirname "$pre_cache_g")"
fresh_iso=$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)
printf '{"product_slug":"butt-butter-original","judgeme_product_id":"12345","last_fetched":"%s","reviews":[{"id":77,"title":"FRESH"}]}' "$fresh_iso" > "$pre_cache_g"
pre_mtime_g="$(stat -f %m "$pre_cache_g" 2>/dev/null || stat -c %Y "$pre_cache_g")"
_http_get() { echo "FAIL: _http_get called despite fresh cache" >&2; return 99; }
rc=0
fetch_reviews "butt-butter-original" "12345" 2>/dev/null || rc=$?
assert_eq "0" "$rc" "fresh cache should skip cleanly with exit 0"
assert_json_field "$pre_cache_g" '.reviews[0].title' "FRESH" "cache content untouched"
post_mtime_g="$(stat -f %m "$pre_cache_g" 2>/dev/null || stat -c %Y "$pre_cache_g")"
assert_eq "$pre_mtime_g" "$post_mtime_g" "cache file mtime unchanged on fresh-skip"
rm -rf "$tmpdir_g"

# --- Case H: fresh cache + --force -> fetch proceeds ---
tmpdir_h="$(mktemp -d)"
export CACHE_DIR="$tmpdir_h"
pre_cache_h="$tmpdir_h/reviews/butt-butter-original.json"
mkdir -p "$(dirname "$pre_cache_h")"
printf '{"product_slug":"butt-butter-original","judgeme_product_id":"12345","last_fetched":"%s","reviews":[{"id":77,"title":"FRESH"}]}' "$fresh_iso" > "$pre_cache_h"
# Restore a single-page fixture stub.
_PAGE_CALLS=0
_http_get() {
  case "$1" in
    judgeme_page)
      _PAGE_CALLS=$((_PAGE_CALLS + 1))
      if [[ $_PAGE_CALLS -eq 1 ]]; then
        cat fixtures/judgeme_response_page1.json
      else
        cat fixtures/judgeme_response_page2.json
      fi ;;
    *) echo "unexpected: $1" >&2; return 1 ;;
  esac
}
fetch_reviews "butt-butter-original" "12345" --force
# Merged: pre-existing id=77 + 3 from fixtures = 4.
assert_json_field "$pre_cache_h" ".reviews | length" "4" "--force bypasses freshness guard"
rm -rf "$tmpdir_h"

echo "OK"
