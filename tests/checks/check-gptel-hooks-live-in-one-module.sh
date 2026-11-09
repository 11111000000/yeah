#!/usr/bin/env bash
# check-gptel-hooks-live-in-one-module.sh — canary for the gptel surface.
#
# The gptel hooks are the only place where Yeah talks to the transport, and
# they are registered in exactly one module. A second module that touches a
# hook variable is a second integration point, and a second integration
# point is a second truth about how the transport is driven.
#
# Exit codes: 0 — one module; 1 — more than one.

set -u

cd "$(dirname "$0")/../.." || exit 2
[ -d lib ] || exit 2

foreign="$(grep -lE 'gptel-(prompt-transform|pre-tool-call)-functions|gptel-fsm-handlers' \
             lib/*.el 2>/dev/null | grep -v 'lib/yeah-gptel.el' || true)"

if [ -n "$foreign" ]; then
  echo "these modules mention a gptel hook: $foreign" >&2
  exit 1
fi

exit 0
