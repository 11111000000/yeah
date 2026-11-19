#!/usr/bin/env bash
# check-the-plugin-does-not-trust-a-dead-socket.sh — canary for the claim
# `a-dead-socket-does-not-pass-for-a-live-service`.
#
# The gap: the plugin of the orchestrator keeps one Emacs for every agent, and
# the sessions come to it over a Unix socket.  The plugin decided that a
# service is alive by the presence of its socket FILE.  The file outlives the
# process: a service that dies leaves its socket behind, and the next agent
# then comes to a socket nobody listens on — and gets no kernel at all.
#
# The live run of 2026-11-19 hit exactly that: the kernel was killed by the
# OOM-killer, the socket stayed, and the next agent could not connect.
#
# This check runs the plugin's own code against the real kernel:
#
#   1. the plugin raises the kernel through `ensureService' and talks to it;
#   2. the kernel dies on the spot — SIGKILL, the socket file stays;
#   3. the plugin does not believe the dead socket: it raises the service
#      again, and the next agent gets an answer from the new kernel.
#
# The model is a FAKE: the turn ends with the `finish' tool, so no network and
# no key are needed.
#
# Exit codes: 0 — the plugin did not trust the dead socket; 1 — it did;
# 2 — the tree is not where we think, or the tools are missing.

set -u

cd "$(dirname "$0")/../.." || exit 2
[ -d lib ] || exit 2
[ -d plugin/yeah-provider ] || exit 2

failures=0
fail() {
  echo "dead-socket: $1" >&2
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
    echo "dead-socket: no Emacs on this host" >&2
    exit 2
  fi
fi

node_bin="$(command -v node 2>/dev/null || true)"
if [ -z "$node_bin" ]; then
  echo "dead-socket: no node on this host" >&2
  exit 2
fi

node_major="$("$node_bin" -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "$node_major" -lt 22 ]; then
  echo "dead-socket: node 22 or newer is needed to run the plugin's TypeScript" >&2
  exit 2
fi

# --- the wiring ------------------------------------------------------------
#
# The behaviour is proved by the run below; this is the wiring that makes it
# reachable: the liveness of the service is asked of the socket itself.

grep -q 'serviceListens(' plugin/yeah-provider/server/service.ts ||
  fail "the plugin does not ask the socket whether anyone listens on it"
grep -q 'await serviceListens(socketPath)' plugin/yeah-provider/server/service.ts ||
  fail "the plugin does not ask the socket before it believes it"

# --- the run ---------------------------------------------------------------

run_dir="$(mktemp -d 2>/dev/null)" || exit 2
export XDG_RUNTIME_DIR="$run_dir"
name="dead-$$"

report="$(mktemp 2>/dev/null)" || exit 2

"$node_bin" --disable-warning=MODULE_TYPELESS_PACKAGE_JSON \
  --import ./tests/support/yeah-ts-resolve.mjs \
  ./tests/support/yeah-dead-socket-driver.ts \
  "$name" "$emacs_bin" "$PWD/lib" "$PWD" >"$report" 2>/tmp/yeah-dead-socket-check.err
driver_rc=$?

if [ "$driver_rc" -ne 0 ]; then
  echo "dead-socket: the plugin trusted a dead socket:" >&2
  sed -n '1,20p' /tmp/yeah-dead-socket-check.err >&2
  failures=1
fi

if ! grep -q '"deadSocketRaised":true' "$report"; then
  fail "the plugin believed the socket of a dead service"
fi

if ! grep -q '"answered":true' "$report"; then
  fail "the next agent did not get an answer from the new core"
fi

rm -f "$report" /tmp/yeah-dead-socket-check.err
rm -rf "$run_dir"

if [ "$failures" -ne 0 ]; then
  exit 1
fi
exit 0
