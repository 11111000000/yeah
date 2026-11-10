#!/usr/bin/env bash
# check-gptel-hooks-live-in-one-module.sh — no global gptel integration hooks.
#
# Yeah configures each gptel request privately.  A global gptel hook in any
# kernel module is a forbidden second integration path and can also affect
# the user's unrelated gptel sessions.  The historical filename is retained
# until the frozen math-coding v4 specification is migrated.
#
# Exit codes: 0 — no global gptel hooks; 1 — a hook was found; 2 — bad input.

set -u
cd "$(dirname "$0")/../.." || exit 2
[ -d lib ] || exit 2

if grep -nE '\((add-hook|remove-hook)[[:space:]]+.*gptel-' lib/*.el; then
  echo "global gptel hooks are forbidden; pass request options privately" >&2
  exit 1
fi

exit 0
