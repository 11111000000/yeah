#!/usr/bin/env bash
# check-the-plugin-steers-the-running-turn.sh — canary for the claim
# `the-plugin-steers-the-turn-instead-of-replacing-it`.
#
# The gap: the orchestrator can send a message to a running agent without
# replacing the turn — that is steering, and it is a capability the provider
# declares (`prompt.steer`).  The ACP adapter of the orchestrator's library
# does not know the capability: it interrupts the running turn and starts a new
# one.  That is a replacement, not steering.
#
# This check runs the plugin's own code against the real kernel:
#
#   1. the plugin declares the steering capability, both in the connection and
#      in the session it opens;
#   2. a request with `delivery: "steer"' reaches the kernel as
#      `session/steer', naming the session of the kernel and the text;
#   3. the running turn is not interrupted: the kernel never sees
#      `session/cancel', and the adapter never sees the steering request;
#   4. the orchestrator is told that the turn is the same turn: the plugin
#      answers with the identifier of the turn that is running.
#
# The kernel is REAL, the model is a fake: the turn does not end, because the
# transport does not answer.  A running turn is the condition of steering.
#
# Exit codes: 0 — the plugin steered the running turn; 1 — it did not;
# 2 — the tree is not where we think, or the tools are missing.

set -u

cd "$(dirname "$0")/../.." || exit 2
[ -d lib ] || exit 2
[ -d plugin/yeah-provider ] || exit 2

failures=0
fail() {
  echo "steer: $1" >&2
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
    echo "steer: no Emacs on this host" >&2
    exit 2
  fi
fi

node_bin="$(command -v node 2>/dev/null || true)"
if [ -z "$node_bin" ]; then
  echo "steer: no node on this host" >&2
  exit 2
fi

# The plugin is TypeScript, and the check runs it as it is written: node
# strips the types itself since 22.6, and the resolver of the check adds the
# extension to the relative imports.
node_major="$("$node_bin" -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "$node_major" -lt 22 ]; then
  echo "steer: node 22 or newer is needed to run the plugin's TypeScript" >&2
  exit 2
fi

# --- the wiring ------------------------------------------------------------
#
# The behaviour is proved by the run below; these are the wirings that make
# the behaviour reachable: the connector wraps the wire, and the connection
# announces the steering capability.

grep -q 'yeahSteerWire(' plugin/yeah-provider/index.server.ts ||
  fail "the connector does not wrap the wire for steering"
grep -q 'yeahSteerConnection(' plugin/yeah-provider/index.server.ts ||
  fail "the connection is not wrapped for steering"
grep -q 'STEER_CAPABILITY' plugin/yeah-provider/server/steer.ts ||
  fail "the steering capability is not named in the plugin"
grep -q 'session/steer' plugin/yeah-provider/server/steer.ts ||
  fail "the plugin does not translate steering into session/steer"

# --- the run ---------------------------------------------------------------

run_dir="$(mktemp -d 2>/dev/null)" || exit 2
export XDG_RUNTIME_DIR="$run_dir"
name="check-steer-$$"

report="$(mktemp 2>/dev/null)" || exit 2

"$node_bin" --disable-warning=MODULE_TYPELESS_PACKAGE_JSON \
  --import ./tests/support/yeah-ts-resolve.mjs \
  ./tests/support/yeah-steer-driver.ts \
  "$name" "$emacs_bin" "$PWD/lib" "$PWD" >"$report" 2>/tmp/yeah-steer-check.err
driver_rc=$?

if [ "$driver_rc" -ne 0 ]; then
  echo "steer: the plugin did not steer the running turn:" >&2
  sed -n '1,20p' /tmp/yeah-steer-check.err >&2
  failures=1
fi

field() {
  sed -n "s/.*\"$1\":\([^,}]*\).*/\1/p" "$report" | head -1
}

# The steering request reached the kernel.
if [ "$(field steerReachedCore)" != "true" ]; then
  fail "the kernel did not receive the steering"
fi

# The kernel was told the session of the kernel and the text of the steering.
if ! grep -q '"steerParams":{"sessionId":"session-' "$report"; then
  fail "the kernel did not receive the session of the kernel"
fi
if ! grep -q '"prompt":"остановись на файле X"' "$report"; then
  fail "the kernel did not receive the text of the steering"
fi

# The running turn was not replaced by the steering.
if [ "$(field turnInterrupted)" != "false" ]; then
  fail "the steering interrupted the running turn"
fi
if [ "$(field adapterSawSteer)" != "false" ]; then
  fail "the steering request reached the adapter that replaces the turn"
fi

# The orchestrator was told that the turn is the same turn.
if [ "$(field reportedTurn)" != '"acp:m-1"' ]; then
  fail "the plugin did not report the identifier of the running turn"
fi
if [ "$(field steerFailed)" != "false" ]; then
  fail "the plugin refused the steering: $(field steerError)"
fi

# The capability was declared, both in the connection and in the session.
if [ "$(field steerCapability)" != "true" ]; then
  fail "the connection does not declare the steering capability"
fi
if [ "$(field sessionAnnouncedSteer)" != "true" ]; then
  fail "the session does not declare the steering capability"
fi

rm -f "$report" /tmp/yeah-steer-check.err
rm -rf "$run_dir"

if [ "$failures" -ne 0 ]; then
  exit 1
fi
exit 0
