#!/usr/bin/env bash
# Fetch a handle's recent Instagram posts via Bright Data snapshot API,
# merge into brand/instagram/<handle>.json by post_id.
#
# Public:  fetch_instagram <handle> [<dataset_id>] [--force]
#          If <dataset_id> is omitted, falls back to $BRIGHTDATA_DATASET_ID.
#          --force (or FORCE_REFRESH=1) bypasses the 24h freshness guard.
# Env:     BRIGHTDATA_API_KEY, BRIGHTDATA_DATASET_ID (optional positional fallback),
#          CACHE_DIR (default: ./brand),
#          CACHE_FRESH_SECONDS (default: 86400 — cache age under which we skip)
# Exit:    0 on success or skip (fresh cache), 1 on unrecoverable error.
#          On snapshot timeout the script exits 2 and leaves the cache intact.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

: "${CACHE_DIR:=./brand}"
: "${CACHE_FRESH_SECONDS:=86400}"

# --- HTTP layer (overridable in tests) ---

# _http_post TAG URL [curl args...]
_http_post() {
  local tag="$1"; shift
  local url="$1"; shift
  curl -sS -X POST "$url" \
    -H "Authorization: Bearer $BRIGHTDATA_API_KEY" \
    -H "Content-Type: application/json" \
    "$@"
}

# _http_get_status SNAPSHOT_ID -> prints one of: running|ready|failed
_http_get_status() {
  local snapshot_id="$1"
  curl -sS \
    -H "Authorization: Bearer $BRIGHTDATA_API_KEY" \
    "https://api.brightdata.com/datasets/v3/progress/$snapshot_id" \
    | jq -r '.status'
}

# _http_get TAG SNAPSHOT_ID -> prints JSON array of posts
_http_get() {
  local tag="$1"; shift
  local snapshot_id="$1"
  curl -sS \
    -H "Authorization: Bearer $BRIGHTDATA_API_KEY" \
    "https://api.brightdata.com/datasets/v3/snapshot/$snapshot_id?format=json"
}

# --- Business logic ---

fetch_instagram() {
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

  local handle="$1"
  local dataset_id="${2:-${BRIGHTDATA_DATASET_ID:-}}"
  [[ -n "$dataset_id" ]] || {
    echo "fetch_instagram: dataset_id required (pass as 2nd arg or set BRIGHTDATA_DATASET_ID in .env)" >&2
    return 1
  }
  local cache_file="$CACHE_DIR/instagram/$handle.json"
  mkdir -p "$(dirname "$cache_file")"

  # Freshness guard: skip the fetch if last_fetched is within CACHE_FRESH_SECONDS
  # (default 24h). Prevents redundant paid snapshots when the cache is recent.
  # Bypass with --force or FORCE_REFRESH=1.
  if (( ! force )) && cache_fresh "$cache_file" ".last_fetched" "$CACHE_FRESH_SECONDS"; then
    echo "fetch_instagram: $handle cache fresh (<${CACHE_FRESH_SECONDS}s), skipping. Use --force to refresh." >&2
    return 0
  fi

  # 1. Trigger snapshot via the "discover new posts by profile URL" flow.
  #    Body shape is {"input": [{url, start_date?}]}, not a bare array.
  #
  #    start_date policy:
  #      - If cache has a last_fetched timestamp, incremental fetch from
  #        that date (Bright Data's US format MM-DD-YYYY).
  #      - Otherwise, omit start_date entirely — Bright Data returns every
  #        post from the account's origin. This is the first-fetch /
  #        backfill case. To force a full re-scrape later, delete the
  #        cache file and re-run.
  local start_date=""
  if [[ -f "$cache_file" ]]; then
    local last_fetched_iso
    # Truncate ISO 8601 timestamp to YYYY-MM-DD (first 10 chars).
    last_fetched_iso="$(jq -r '.last_fetched // ""' "$cache_file" | cut -c1-10)"
    if [[ -n "$last_fetched_iso" ]]; then
      start_date="${last_fetched_iso:5:2}-${last_fetched_iso:8:2}-${last_fetched_iso:0:4}"
    fi
  fi

  local input_obj
  if [[ -n "$start_date" ]]; then
    input_obj=$(jq -n \
      --arg url "https://www.instagram.com/$handle/" \
      --arg start_date "$start_date" \
      '{url: $url, start_date: $start_date}')
  else
    input_obj=$(jq -n \
      --arg url "https://www.instagram.com/$handle/" \
      '{url: $url}')
  fi
  local trigger_body
  trigger_body=$(jq -n --argjson input "$input_obj" '{input: [$input]}')

  local trigger_resp
  trigger_resp="$(_http_post brightdata_trigger \
    "https://api.brightdata.com/datasets/v3/trigger?dataset_id=$dataset_id&notify=false&include_errors=true&type=discover_new&discover_by=url" \
    --data "$trigger_body")"
  local snapshot_id
  snapshot_id="$(echo "$trigger_resp" | jq -r '.snapshot_id')"
  [[ -n "$snapshot_id" && "$snapshot_id" != "null" ]] \
    || { echo "fetch_instagram: no snapshot_id in response: $trigger_resp" >&2; return 1; }

  # 2. Poll up to ~8 min (20 attempts with 3s -> 30s backoff).
  local attempts=0 max_attempts=20 delay=3 status
  while (( attempts < max_attempts )); do
    status="$(_http_get_status "$snapshot_id")"
    case "$status" in
      ready) break ;;
      failed) echo "fetch_instagram: snapshot failed for $handle" >&2; return 1 ;;
      *) sleep "$delay"; delay=$((delay < 30 ? delay + 3 : 30)) ;;
    esac
    attempts=$((attempts + 1))
  done
  [[ "$status" == "ready" ]] || {
    echo "fetch_instagram: timeout waiting for snapshot $snapshot_id" >&2
    return 2
  }

  # 3. Download.
  local incoming
  incoming="$(_http_get brightdata_download "$snapshot_id")"

  # 3b. Drop videos and reels — carousels are built from images, so only
  #     image/carousel posts feed the inspiration pool. Checks every plausible
  #     media-type field Bright Data might emit; posts with none of those
  #     fields set are kept (fail-open).
  incoming="$(printf '%s' "$incoming" | jq '
    map(select(
      ([.media_type, .post_type, .content_type, .product_type]
       | map(. // "" | ascii_downcase)
       | any(test("video|reel"))
      ) | not
    ))
  ')"

  # 4. Merge into cache by post_id.
  local existing='[]'
  if [[ -f "$cache_file" ]]; then
    existing="$(jq '.posts' "$cache_file")"
  fi
  local merged
  merged="$(merge_by_key "post_id" "$existing" "$incoming")"
  local final
  final="$(jq -n \
    --arg handle "$handle" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson posts "$merged" \
    '{handle:$handle, last_fetched:$ts, posts:$posts}')"
  atomic_write "$cache_file" "$final"
}

# Allow running as a script: scripts/fetch_instagram.sh <handle> <dataset_id>
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  [[ -f .env ]] && load_env .env
  fetch_instagram "$@"
fi
