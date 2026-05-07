#!/usr/bin/env bash
# Shared helpers for fetch scripts. Source, do not execute.
# All functions: nonzero exit on error.

# load_env PATH
#   Read KEY=VALUE lines from PATH and export them. Ignores blank lines and
#   lines starting with # (comments must be full-line, not inline).
#   Tolerates:
#     - files without a trailing newline
#     - whitespace around = (e.g., "KEY = value")
#     - CRLF line endings
#   Not shell-safe for values with unescaped special chars — use JSON-ish
#   values, not arbitrary shell snippets.
load_env() {
  local path="$1"
  [[ -f "$path" ]] || { echo "load_env: missing $path" >&2; return 1; }
  local key value
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    # Trim leading/trailing whitespace from key; strip CR and leading space from value.
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value%$'\r'}"
    value="${value#"${value%%[![:space:]]*}"}"
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    export "$key=$value"
  done < "$path"
}

# atomic_write PATH CONTENT
#   Write CONTENT to a sibling .tmp file, then mv to PATH. Ensures partial
#   writes cannot corrupt the target. Caller is responsible for directory
#   creation.
atomic_write() {
  local path="$1"
  local content="$2"
  local tmp="${path}.tmp"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$content" > "$tmp"
  mv "$tmp" "$path"
}

# merge_by_key KEY EXISTING_JSON INCOMING_JSON
#   Merge two JSON arrays, deduping on KEY. Incoming wins on conflict.
#   Stdout: merged JSON array.
merge_by_key() {
  local key="$1"
  local existing="$2"
  local incoming="$3"
  jq -n \
    --arg key "$key" \
    --argjson existing "$existing" \
    --argjson incoming "$incoming" \
    '($existing + $incoming) | group_by(.[$key]) | map(.[-1])'
}

# cache_fresh PATH JQ_FIELD MAX_AGE_SECONDS
#   Return 0 if PATH exists, JQ_FIELD yields a parseable ISO-8601 UTC
#   timestamp, and that timestamp is within MAX_AGE_SECONDS of now.
#   Return 1 otherwise (missing file, missing/unparseable field, or stale).
#   Used by fetch scripts to short-circuit when the cache is fresh enough
#   to skip a network refresh.
cache_fresh() {
  local path="$1"
  local field="$2"
  local max_age="$3"
  [[ -f "$path" ]] || return 1
  local ts
  ts="$(jq -r "$field // \"\"" "$path" 2>/dev/null)" || return 1
  [[ -n "$ts" && "$ts" != "null" ]] || return 1
  local ts_epoch now_epoch
  ts_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null \
           || date -u -d "$ts" +%s 2>/dev/null)" || return 1
  now_epoch="$(date -u +%s)"
  (( now_epoch - ts_epoch < max_age ))
}
