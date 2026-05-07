#!/usr/bin/env bash
# Run every test_*.sh in this directory. Exit 1 if any test fails.
set -uo pipefail

cd "$(dirname "$0")"
pass=0
fail=0
for t in test_*.sh; do
  echo "=== $t ==="
  if bash "$t"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "--- $t FAILED ---"
  fi
done
echo
echo "Summary: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
