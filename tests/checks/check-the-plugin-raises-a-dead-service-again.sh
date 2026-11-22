#!/usr/bin/env bash
# check-the-plugin-raises-a-dead-service-again.sh — canary for the claim
# `a-dead-service-does-not-pass-for-a-live-connection`.
#
# The gap: the plugin of the orchestrator keeps one Emacs for every agent, and
# the sessions come to it over a Unix socket.  The plugin holds a REFERENCE to
# that service and reuses it for the next agent — a reference, not a proof.
# The core dies (a signal, the OOM-killer of the host, a crash), the reference
# stays, and the next agent comes to a socket nobody listens on.
#
# The live run of 2026-11-22 hit exactly that: the core of the service was
# gone by 20:38 UTC, and the orchestrator wrote "ACP connection closed" 32
# times in an hour — every attempt of an agent to reach the core failed the
# same way, until the plugin was reloaded by hand.
#
# This check runs the plugin's own code against the real kernel:
#
#   1. the plugin raises the kernel through `ensureService' and holds it;
#   2. the kernel dies on the spot — SIGKILL, the socket file stays;
#   3. the plugin is given the DEAD service as the cached one and asked for a
#      connection: it must ask the socket whether anyone listens on it, raise
#      the service again, and answer the agent from the new kernel.
#
# The model is a FAKE: the turn ends with the `finish' tool, so no network and
# no key are needed.
#
# Exit codes: 0 — the plugin did not trust the dead service; 1 — it did;
# 2 — the tree is not where we think, or the tools are missing.

set -u

cd "$(dirname "$0")/../.." || exit 2
[ -d lib ] || exit 2
[ -d plugin/yeah-provider ] || exit 2

failures=0
fail() {
  echo "dead-service: $1" >&2
  failures=1
}

# --- the tools -------------------------------------------------------------

emacs_bin="${EMACS:-}"
if [ -z "$emacs_bin" ]; then
  if command -v emacs >/dev/null 2>&1; then
    emacs_bin="$(command -v emacs)"
  elif [ -x "$HOME/.nix-profile/bin/emacs" ]; then
    emacs_bin="$HOME/.nix-profile/bin/emacs"
  else
    echo "dead-service: no Emacs on this host" >&2
    exit 2
  fi
fi

node_bin="$(command -v node 2>/dev/null || true)"
if [ -z "$node_bin" ]; then
  echo "dead-service: no node on this host" >&2
  exit 2
fi

node_major="$("$node_bin" -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "$node_major" -lt 22 ]; then
  echo "dead-service: node 22 or newer is needed to run the plugin's TypeScript" >&2
  exit 2
fi

# --- the wiring ------------------------------------------------------------
#
# The behaviour is proved by the run below; this is the wiring that makes it
# reachable: the liveness of the CACHED service is asked of the socket itself.

grep -q 'serviceListens(' plugin/yeah-provider/server/transport.ts ||
  fail "the plugin does not ask the socket whether anyone listens on it"
grep -q 'serviceListens(cached.socketPath)' plugin/yeah-provider/server/transport.ts ||
  fail "the plugin does not ask the socket about the service it holds"

# --- the run ---------------------------------------------------------------

run_dir="$(mktemp -d 2>/dev/null)" || exit 2
export XDG_RUNTIME_DIR="$run_dir"
name="deadsvc-$$"

report="$(mktemp 2>/dev/null)" || exit 2

"$node_bin" --disable-warning=MODULE_TYPELESS_PACKAGE_JSON \
  --import ./tests/support/yeah-ts-resolve.mjs \
  ./tests/support/yeah-cached-service-driver.ts \
  "$name" "$emacs_bin" "$PWD/lib" "$PWD" >"$report" 2>/tmp/yeah-dead-service-check.err
driver_rc=$?

if [ "$driver_rc" -ne 0 ]; then
  echo "dead-service: the plugin trusted the dead service of its cache:" >&2
  sed -n '1,20p' /tmp/yeah-dead-service-check.err >&2
  failures=1
fi

if ! grep -q '"cachedServiceReplaced":true' "$report"; then
  fail "the plugin believed the service it holds, and raised nothing"
fi

if ! grep -q '"answered":true' "$report"; then
  fail "the next agent did not get an answer from the new core"
fi

rm -f "$report" /tmp/yeah-dead-service-check.err
rm -rf "$run_dir"

if [ "$failures" -ne 0 ]; then
  exit 1
fi
exit 0
