#!/usr/bin/env bash
# Minimal assertion helpers for shell tests. Source this in each test_*.sh.
# Exits nonzero on first failure; test files use `set -euo pipefail`.

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${msg:-assertion}" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    return 1
  fi
}

assert_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "FAIL: expected file to exist: $path" >&2
    return 1
  fi
}

assert_json_field() {
  local file="$1"
  local jq_expr="$2"
  local expected="$3"
  local actual
  actual="$(jq -r "$jq_expr" "$file")"
  assert_eq "$expected" "$actual" "json field $jq_expr in $file"
}
