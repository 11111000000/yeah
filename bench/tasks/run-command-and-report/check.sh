#!/usr/bin/env bash
# check.sh - output.txt must carry the output of the original compute.sh.
set -u

if [ ! -f output.txt ]; then
  echo "check: output.txt does not exist" >&2
  exit 1
fi

if ! grep -F -q 'sum=$((sum + number))' compute.sh; then
  echo "check: compute.sh was changed; the report must come from running it" >&2
  exit 1
fi

value="$(tr -d '[:space:]' < output.txt)"
if [ "$value" != "sum=15" ]; then
  echo "check: expected sum=15, got '$value'" >&2
  exit 1
fi

exit 0
