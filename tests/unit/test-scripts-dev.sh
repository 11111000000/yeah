#!/usr/bin/env bash
# scripts/dev self-check — verify that scripts/dev is a Bash script
# that returns 0 on `smoke` and 1+ on a not-yet-implemented
# subcommand. This is the script-level smoke test that the
# bootstrap gate relies on.
set -eu

cd "$(dirname "$0")/../.."

./scripts/dev smoke >/dev/null

if ./scripts/dev validate >/dev/null 2>&1; then
  echo "scripts/dev validate unexpectedly returned 0" >&2
  exit 1
fi
if ./scripts/dev nonexistent 2>/dev/null; then
  echo "scripts/dev did not reject an unknown subcommand" >&2
  exit 1
fi

echo "scripts/dev: smoke ok"
