#!/usr/bin/env bash
# storage.sh — simple file storage on Clever Cloud Cellar (S3-compatible).
#
# Usage:
#   storage.sh put LOCAL_PATH [REMOTE_KEY]   upload, print public HTTPS URL
#   storage.sh url REMOTE_KEY                print public HTTPS URL (no upload)
#   storage.sh ls [PREFIX]                   list keys (optionally under PREFIX)
#   storage.sh rm REMOTE_KEY                 delete one key
#   storage.sh get REMOTE_KEY [LOCAL_PATH]   download (default: basename in cwd)
#
# Reads from .env at the repo root (one level above scripts/):
#   CELLAR_ADDON_HOST       e.g. cellar-c2.services.clever-cloud.com
#   CELLAR_ADDON_KEY_ID     S3 access key id
#   CELLAR_ADDON_KEY_SECRET S3 secret access key
#   CELLAR_BUCKET           target bucket name
#
# Key derivation when REMOTE_KEY is omitted on `put`:
#   - LOCAL_PATH starting with "output/" → strip the prefix.
#     output/2026-05-08-foo/frames/01.png → 2026-05-08-foo/frames/01.png
#   - otherwise → uploads/<basename>.
#
# Bucket bootstrap (run once, by hand, after creating the Cellar add-on):
#   aws --endpoint-url "https://$CELLAR_ADDON_HOST" s3api create-bucket \
#       --bucket "$CELLAR_BUCKET"
#
#   # Make every uploaded object publicly readable via a bucket policy:
#   cat > /tmp/policy.json <<JSON
#   {
#     "Version": "2012-10-17",
#     "Statement": [{
#       "Sid": "PublicRead",
#       "Effect": "Allow",
#       "Principal": "*",
#       "Action": "s3:GetObject",
#       "Resource": "arn:aws:s3:::$CELLAR_BUCKET/*"
#     }]
#   }
#   JSON
#   aws --endpoint-url "https://$CELLAR_ADDON_HOST" s3api put-bucket-policy \
#       --bucket "$CELLAR_BUCKET" --policy file:///tmp/policy.json
#
# Exit codes:
#   0 success
#   1 usage / missing env / missing dependency
#   2 upstream API failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() { sed -n '2,46p' "$0" >&2; exit 1; }
help()  { sed -n '2,46p' "$0"; exit 0; }

if [[ $# -lt 1 ]]; then usage; fi

case "$1" in
  -h|--help|help) help;;
esac

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

: "${CELLAR_ADDON_HOST:?CELLAR_ADDON_HOST not set (see .env.example)}"
: "${CELLAR_ADDON_KEY_ID:?CELLAR_ADDON_KEY_ID not set}"
: "${CELLAR_ADDON_KEY_SECRET:?CELLAR_ADDON_KEY_SECRET not set}"
: "${CELLAR_BUCKET:?CELLAR_BUCKET not set}"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found. Install with: brew install awscli" >&2
  exit 1
fi

export AWS_ACCESS_KEY_ID="$CELLAR_ADDON_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$CELLAR_ADDON_KEY_SECRET"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

ENDPOINT="https://$CELLAR_ADDON_HOST"
PUBLIC_BASE="https://$CELLAR_BUCKET.$CELLAR_ADDON_HOST"

derive_key() {
  local local_path="$1"
  if [[ "$local_path" == output/* ]]; then
    printf '%s\n' "${local_path#output/}"
  else
    printf '%s\n' "uploads/$(basename "$local_path")"
  fi
}

local_md5() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$1" | awk '{print $1}'
  else
    md5 -q "$1"
  fi
}

local_size() { wc -c < "$1" | tr -d ' '; }

# Print "<size> <etag>" if the key exists, empty string otherwise.
remote_size_etag() {
  local key="$1"
  aws --endpoint-url "$ENDPOINT" s3api head-object \
      --bucket "$CELLAR_BUCKET" --key "$key" \
      --query '[ContentLength, ETag]' --output text 2>/dev/null \
    | tr -d '"'
}

cmd="$1"; shift

case "$cmd" in
  put)
    [[ $# -ge 1 ]] || usage
    local_path="$1"
    [[ -f "$local_path" ]] || { echo "no such file: $local_path" >&2; exit 1; }
    if [[ $# -ge 2 ]]; then key="$2"; else key="$(derive_key "$local_path")"; fi

    lsize="$(local_size "$local_path")"
    lmd5="$(local_md5 "$local_path")"
    remote="$(remote_size_etag "$key")"
    if [[ -n "$remote" ]]; then
      rsize="$(printf '%s\n' "$remote" | awk '{print $1}')"
      retag="$(printf '%s\n' "$remote" | awk '{print $2}')"
      if [[ "$rsize" == "$lsize" && "$retag" == "$lmd5" ]]; then
        echo "skip: $key already up to date" >&2
        printf '%s/%s\n' "$PUBLIC_BASE" "$key"
        exit 0
      fi
    fi

    mime="$(file --mime-type -b "$local_path")"
    aws --endpoint-url "$ENDPOINT" s3api put-object \
        --bucket "$CELLAR_BUCKET" --key "$key" \
        --body "$local_path" --content-type "$mime" \
        --acl public-read >/dev/null || exit 2
    printf '%s/%s\n' "$PUBLIC_BASE" "$key"
    ;;
  url)
    [[ $# -ge 1 ]] || usage
    printf '%s/%s\n' "$PUBLIC_BASE" "$1"
    ;;
  ls)
    prefix="${1:-}"
    if [[ -n "$prefix" ]]; then
      aws --endpoint-url "$ENDPOINT" s3api list-objects-v2 \
          --bucket "$CELLAR_BUCKET" --prefix "$prefix" \
          --query 'Contents[].Key' --output text 2>/dev/null \
        | tr '\t' '\n' | sed '/^None$/d;/^$/d'
    else
      aws --endpoint-url "$ENDPOINT" s3api list-objects-v2 \
          --bucket "$CELLAR_BUCKET" \
          --query 'Contents[].Key' --output text 2>/dev/null \
        | tr '\t' '\n' | sed '/^None$/d;/^$/d'
    fi
    ;;
  rm)
    [[ $# -ge 1 ]] || usage
    aws --endpoint-url "$ENDPOINT" s3api delete-object \
        --bucket "$CELLAR_BUCKET" --key "$1" >/dev/null || exit 2
    ;;
  get)
    [[ $# -ge 1 ]] || usage
    key="$1"
    if [[ $# -ge 2 ]]; then dest="$2"; else dest="$(basename "$key")"; fi
    aws --endpoint-url "$ENDPOINT" s3api get-object \
        --bucket "$CELLAR_BUCKET" --key "$key" "$dest" >/dev/null || exit 2
    printf '%s\n' "$dest"
    ;;
  *)
    echo "unknown command: $cmd" >&2
    usage
    ;;
esac
