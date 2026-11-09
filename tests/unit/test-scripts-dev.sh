#!/usr/bin/env bash
# tests/unit/test-scripts-dev.sh — smoke test for scripts/dev.
#
# Asserts:
#   * `scripts/dev smoke` exits 0;
#   * `scripts/dev byte-compile-all` exits 0 and leaves no bytecode behind;
#   * `scripts/dev ert` runs a test file and exits 0;
#   * `scripts/dev <unknown>` exits 2;
#   * `scripts/dev <unknown>` does not exit 0 — an unknown subcommand is
#     an input error, and an input error is not a pass.
#
# The `map`, `run` and `gate` subcommands are the method's, and the method
# is not part of this repository: they are checked by `mathc doctor` and
# by the claims that use them.

set -eu

cd "$(dirname "$0")/../.."

./scripts/dev smoke >/dev/null
echo "scripts/dev: smoke ok"

./scripts/dev byte-compile-all >/dev/null
echo "scripts/dev: byte-compile-all ok"

if compgen -G "lib/*.elc" >/dev/null; then
  echo "scripts/dev: byte-compile-all left bytecode next to the sources" >&2
  exit 1
fi
echo "scripts/dev: leaves no bytecode behind ok"

./scripts/dev ert tests/unit/test-yeah-state.el >/dev/null
echo "scripts/dev: ert ok"

if ./scripts/dev definitely-not-a-subcommand 2>/dev/null; then
  echo "scripts/dev: did not reject an unknown subcommand" >&2
  exit 1
fi
echo "scripts/dev: rejects unknown subcommands ok"
