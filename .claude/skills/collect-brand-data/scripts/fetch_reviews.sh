#!/usr/bin/env bash
# Fetch reviews for one product from JudgeMe, paginate, merge into
# brand/reviews/<slug>.json by review id.
#
# Public:  fetch_reviews <product_slug> <judgeme_product_id> [--force]
#          --force (or FORCE_REFRESH=1) bypasses the 24h freshness guard.
# Env:     JUDGEME_API_KEY, JUDGEME_SHOP_DOMAIN, CACHE_DIR (default: ./brand),
#          CACHE_FRESH_SECONDS (default: 86400 — cache age under which we skip)
# Exit:    0 on success or skip (fresh cache); nonzero on unrecoverable error.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

: "${CACHE_DIR:=./brand}"
: "${CACHE_FRESH_SECONDS:=86400}"
: "${JUDGEME_PER_PAGE:=50}"

# _http_get TAG URL -> prints JSON page
_http_get() {
  local tag="$1"; shift
  local url="$1"
  curl -sS "$url"
}

fetch_reviews() {
  # Parse --force out of positional args; support FORCE_REFRESH=1 env too.
  local force="${FORCE_REFRESH:-0}"
  local pos=()
  local a
  for a in "$@"; do
    case "$a" in
      --force) force=1 ;;
      *) pos+=("$a") ;;
    esac
  done
  set -- "${pos[@]}"

  local slug="$1"
  local product_id="$2"
  local cache_file="$CACHE_DIR/reviews/$slug.json"
  mkdir -p "$(dirname "$cache_file")"

  # Freshness guard: skip if last_fetched is within CACHE_FRESH_SECONDS
  # (default 24h). Bypass with --force or FORCE_REFRESH=1.
  if (( ! force )) && cache_fresh "$cache_file" ".last_fetched" "$CACHE_FRESH_SECONDS"; then
    echo "fetch_reviews: $slug cache fresh (<${CACHE_FRESH_SECONDS}s), skipping. Use --force to refresh." >&2
    return 0
  fi

  # Read last_fetched from existing cache for incremental fetch.
  local since=""
  local existing_reviews='[]'
  if [[ -f "$cache_file" ]]; then
    since="$(jq -r '.last_fetched // ""' "$cache_file")"
    existing_reviews="$(jq '.reviews' "$cache_file")"
  fi

  # Paginate until we've seen every review.
  local page=1 per_page="$JUDGEME_PER_PAGE"
  local collected='[]'
  local _resp_tmp
  _resp_tmp="$(mktemp)"
  while :; do
    local url="https://judge.me/api/v1/reviews?api_token=${JUDGEME_API_KEY:-}&shop_domain=${JUDGEME_SHOP_DOMAIN:-}&product_id=$product_id&page=$page&per_page=$per_page"
    [[ -n "$since" ]] && url="$url&updated_at_min=$since"
    # Call _http_get, checking both HTTP-level and JSON-level success before
    # we touch the cache. A silent overwrite with {"reviews": []} on transient
    # failure would destroy the incremental-fetch state (last_fetched), so we
    # must fail loudly instead.
    if ! _http_get judgeme_page "$url" > "$_resp_tmp"; then
      rm -f "$_resp_tmp"
      echo "fetch_reviews: HTTP error for $slug page $page" >&2
      return 1
    fi
    if ! jq empty "$_resp_tmp" 2>/dev/null; then
      rm -f "$_resp_tmp"
      echo "fetch_reviews: invalid JSON from JudgeMe for $slug page $page" >&2
      return 1
    fi
    local page_reviews
    page_reviews="$(jq '.reviews' "$_resp_tmp")"
    local page_count
    page_count="$(jq 'length' <<< "$page_reviews")"
    collected="$(jq -n --argjson a "$collected" --argjson b "$page_reviews" '$a + $b')"
    local total
    total="$(jq -r '.total' "$_resp_tmp")"
    local seen
    seen="$(jq 'length' <<< "$collected")"
    # JudgeMe returns total=null for some shops, so we also stop when the
    # page came back with fewer than per_page items (last page).
    if (( page_count == 0 )) || (( page_count < per_page )); then
      break
    fi
    if [[ "$total" != "null" ]] && (( seen >= total )); then
      break
    fi
    page=$((page + 1))
    # Safety: never loop more than 100 pages.
    (( page > 100 )) && { rm -f "$_resp_tmp"; echo "fetch_reviews: pagination runaway for $slug" >&2; return 1; }
  done
  rm -f "$_resp_tmp"

  # Merge with existing cache, dedup by id.
  local merged
  merged="$(merge_by_key "id" "$existing_reviews" "$collected")"
  local final
  final="$(jq -n \
    --arg slug "$slug" \
    --arg product_id "$product_id" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson reviews "$merged" \
    '{product_slug:$slug, judgeme_product_id:$product_id, last_fetched:$ts, reviews:$reviews}')"
  atomic_write "$cache_file" "$final"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  [[ -f .env ]] && load_env .env
  fetch_reviews "$@"
fi
