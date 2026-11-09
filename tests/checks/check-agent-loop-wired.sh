#!/usr/bin/env bash
# check-agent-loop-wired.sh — canary for the claim `the-agent-loop-is-wired`.
#
# The four pieces of the loop exist as separate modules: the tick, the
# permission system, the tool registry and the session log. What does not
# exist is the wiring between them: no module outside lib/yeah-loop.el calls
# yeah-loop-tick, and so on. This check asserts the wiring, by looking for
# a real call (an open paren, not a mention in a comment).
#
# It fails today. That is the point: it is the canary that turns "the
# modules exist" into "the loop runs", and it is the negative control of
# the claim it belongs to.
#
# Exit codes: 0 — wired; 1 — not wired; 2 — the tree is not where we think.

set -u

cd "$(dirname "$0")/../.." || exit 2
[ -d lib ] || exit 2

missing=0

check_call() {
  symbol="$1"
  owner="$2"
  foreign="$(grep -l -- "($symbol " lib/*.el 2>/dev/null | grep -v "lib/$owner" || true)"
  if [ -z "$foreign" ]; then
    echo "no module outside lib/$owner calls $symbol" >&2
    missing=1
  fi
}

check_call yeah-loop-tick      yeah-loop.el
check_call yeah-perm-evaluate  yeah-perm.el
check_call yeah-tools-call     yeah-tools.el
check_call yeah-session-append yeah-session.el

exit $missing
