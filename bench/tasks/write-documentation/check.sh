#!/usr/bin/env bash
# check.sh - money.md must document both functions.
set -u

if [ ! -f money.md ]; then
  echo "check: money.md does not exist" >&2
  exit 1
fi

for name in money-add money-zero-p; do
  if ! grep -qx "## $name" money.md; then
    echo "check: money.md has no section '## $name'" >&2
    exit 1
  fi
  if ! grep -q "^Signature:.*$name" money.md; then
    echo "check: money.md has no Signature line for $name" >&2
    exit 1
  fi
done

summaries="$(grep -c '^Summary:' money.md || true)"
if [ "$summaries" -lt 2 ]; then
  echo "check: money.md needs a Summary line for each function" >&2
  exit 1
fi

exit 0
