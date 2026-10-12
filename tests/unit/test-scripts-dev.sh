#!/usr/bin/env bash
# tests/unit/test-scripts-dev.sh — smoke test for scripts/dev.
#
# Asserts:
#   * `scripts/dev smoke` exits 0;
#   * `scripts/dev validate` exits 0 (when the tree is valid);
#   * `scripts/dev byte-compile-all` exits 0;
#   * `scripts/dev <unknown>` exits 2.

set -eu

cd "$(dirname "$0")/../.."

./scripts/dev smoke >/dev/null
echo "scripts/dev: smoke ok"

./scripts/dev validate >/dev/null
echo "scripts/dev: validate ok"

./scripts/dev byte-compile-all >/dev/null
echo "scripts/dev: byte-compile-all ok"

if ./scripts/dev definitely-not-a-subcommand 2>/dev/null; then
  echo "scripts/dev: did not reject an unknown subcommand" >&2
  exit 1
fi
echo "scripts/dev: rejects unknown subcommands ok"

if ./scripts/dev edit-loop-detect 2>/dev/null; then
  echo "scripts/dev: edit-loop-detect unexpectedly succeeded" >&2
  exit 1
fi
echo "scripts/dev: edit-loop-detect is correctly blocked"
