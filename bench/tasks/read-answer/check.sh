#!/usr/bin/env bash
# check.sh - the total revenue of sales.csv is 100.
set -u

if [ ! -f answer.txt ]; then
  echo "check: answer.txt does not exist" >&2
  exit 1
fi

value="$(tr -d '[:space:]' < answer.txt)"
if [ "$value" != "100" ]; then
  echo "check: expected 100, got '$value'" >&2
  exit 1
fi

exit 0
