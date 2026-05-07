#!/usr/bin/env bash
# generate_image.sh — generate one image via OpenAI gpt-image-2 and save as PNG.
#
# Usage:
#   generate_image.sh [--ref PATH]... [--no-crop] OUTPUT_PATH PROMPT [SIZE]
#
# When one or more `--ref PATH` flags are passed, the script calls
# POST /v1/images/edits with each PATH attached as a multipart `image[]`
# field, letting the model treat them as reference images. Without any
# --ref flag it falls back to POST /v1/images/generations (text-to-image).
#
# SIZE defaults to 1024x1536 (portrait). Valid values per the gpt-image-2 API:
#   1024x1024, 1024x1536, 1536x1024, auto
#
# By default the saved PNG is center-cropped to 9:16 (TikTok / Reels / Shorts).
# Pass --no-crop to keep the model's native size — required for character
# sheets, packshots, or any landscape output.
#
# Reads OPENAI_API_KEY from the environment. Caller must `source .env` first
# or export the key.
#
# Exit codes:
#   0 — image written
#   1 — bad arguments or OPENAI_API_KEY missing
#   2 — API call failed (body included on stderr)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../.claude/skills/collect-brand-data/scripts/lib.sh
if [[ -f "$SCRIPT_DIR/../.claude/skills/collect-brand-data/scripts/lib.sh" ]]; then
  source "$SCRIPT_DIR/../.claude/skills/collect-brand-data/scripts/lib.sh"
fi

usage() {
  echo "Usage: $0 [--ref PATH]... [--no-crop] OUTPUT_PATH PROMPT [SIZE]" >&2
  exit 1
}

refs=()
crop=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      [[ $# -ge 2 ]] || usage
      refs+=("$2")
      shift 2
      ;;
    --no-crop)
      crop=0
      shift
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      usage
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -lt 2 ]] && usage

output="$1"
prompt="$2"
size="${3:-1024x1536}"

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "generate_image.sh: OPENAI_API_KEY not set" >&2
  exit 1
fi

if (( ${#refs[@]} > 0 )); then
  for r in "${refs[@]}"; do
    if [[ ! -f "$r" ]]; then
      echo "generate_image.sh: reference image not found: $r" >&2
      exit 1
    fi
  done
fi

mkdir -p "$(dirname "$output")"

# Prefer gpt-image-2 (newer, higher fidelity). Automatically fall back to
# gpt-image-1 when the account is not yet verified for gpt-image-2
# (OpenAI returns HTTP 403 with "must be verified" for ungated orgs).
model="${OPENAI_IMAGE_MODEL:-gpt-image-2}"
tmp_body="$(mktemp)"
trap 'rm -f "$tmp_body"' EXIT

quality="${OPENAI_IMAGE_QUALITY:-low}"

call_generations() {
  local m="$1"
  local payload
  payload="$(jq -n \
    --arg model "$m" \
    --arg prompt "$prompt" \
    --arg size "$size" \
    --arg quality "$quality" \
    '{model:$model, prompt:$prompt, size:$size, quality:$quality, n:1}')"
  curl -sS -o "$tmp_body" -w '%{http_code}' \
    https://api.openai.com/v1/images/generations \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload"
}

call_edits() {
  local m="$1"
  local -a args=(
    -sS -o "$tmp_body" -w '%{http_code}'
    https://api.openai.com/v1/images/edits
    -H "Authorization: Bearer $OPENAI_API_KEY"
    -F "model=$m"
    -F "prompt=$prompt"
    -F "size=$size"
    -F "quality=$quality"
    -F "n=1"
  )
  local r
  for r in "${refs[@]}"; do
    args+=( -F "image[]=@$r" )
  done
  curl "${args[@]}"
}

call_api() {
  if (( ${#refs[@]} > 0 )); then
    call_edits "$1"
  else
    call_generations "$1"
  fi
}

http_code="$(call_api "$model")" || {
    echo "generate_image.sh: curl failed" >&2
    cat "$tmp_body" >&2
    exit 2
  }

if [[ "$http_code" == "403" && "$model" == "gpt-image-2" ]] && \
   grep -q "must be verified" "$tmp_body"; then
  echo "generate_image.sh: gpt-image-2 gated on this org; falling back to gpt-image-1" >&2
  model="gpt-image-1"
  http_code="$(call_api "$model")" || { cat "$tmp_body" >&2; exit 2; }
fi

if [[ "$http_code" != "200" ]]; then
  echo "generate_image.sh: HTTP $http_code (model=$model)" >&2
  cat "$tmp_body" >&2
  exit 2
fi

b64="$(jq -r '.data[0].b64_json // empty' "$tmp_body")"
if [[ -n "$b64" ]]; then
  echo "$b64" | base64 -d > "$output"
else
  # Some API variants return a URL instead of base64. Fall back to download.
  url="$(jq -r '.data[0].url // empty' "$tmp_body")"
  if [[ -n "$url" ]]; then
    curl -sSL "$url" -o "$output"
  else
    echo "generate_image.sh: no b64_json or url in response" >&2
    cat "$tmp_body" >&2
    exit 2
  fi
fi

# Post-process: center-crop to 9:16 so the saved PNG matches the UGC
# vertical aspect (TikTok / Reels / Shorts, e.g. 1080×1920). gpt-image-2
# has no native 9:16 size — the closest is 1024×1536 (portrait 2:3) — so
# we crop horizontally to 864×1536. Skip silently if sips is unavailable
# (non-macOS host) or dimensions read fails.
crop_to_9_16() {
  local file="$1"
  command -v sips >/dev/null 2>&1 || return 0
  local w h
  w="$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
  h="$(sips -g pixelHeight "$file" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
  [[ -z "$w" || -z "$h" ]] && return 0
  local target_w target_h="$h"
  target_w=$(( h * 9 / 16 ))
  if (( target_w > w )); then
    target_h=$(( w * 16 / 9 ))
    target_w="$w"
  fi
  if (( target_w == w && target_h == h )); then
    return 0
  fi
  sips -c "$target_h" "$target_w" "$file" >/dev/null 2>&1 || true
}

if (( crop == 1 )); then
  crop_to_9_16 "$output"
fi

echo "$output"
