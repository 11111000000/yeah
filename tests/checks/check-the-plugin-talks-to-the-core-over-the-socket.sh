#!/usr/bin/env bash
# check-the-plugin-talks-to-the-core-over-the-socket.sh — canary for the claim
# `the-plugin-talks-to-the-core-over-a-socket`.
#
# The gap: the plugin of the orchestrator raises its own Emacs for every
# connection, and a request that arrives during a turn is read only after the
# turn has settled.  The service placement is the other way round: one Emacs
# lives, sessions come to it over a Unix socket, and the next agent comes to
# the same Emacs.
#
# This check runs the plugin's own code against the real kernel:
#
#   1. the plugin raises the kernel through `ensureService' and talks to it
#      through `yeahTransport' — the handshake, a session and a turn are
#      answered by the kernel;
#   2. the second agent comes to the same kernel and does not raise a second
#      one;
#   3. the socket the plugin computes is the socket the kernel names
#      (`yeah-service-socket-path'), so a service raised from Emacs and a
#      service raised from the plugin do not take each other's place;
#   4. the placement is a choice, and the default is still one Emacs per
#      connection.
#
# The model is a FAKE: the turn ends with the `finish' tool, so no network and
# no key are needed.
#
# Exit codes: 0 — the plugin talked to the core over the socket; 1 — it did
# not; 2 — the tree is not where we think, or the tools are missing.

set -u

cd "$(dirname "$0")/../.." || exit 2
[ -d lib ] || exit 2
[ -d plugin/yeah-provider ] || exit 2

failures=0
fail() {
  echo "service: $1" >&2
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
    echo "service: no Emacs on this host" >&2
    exit 2
  fi
fi

node_bin="$(command -v node 2>/dev/null || true)"
if [ -z "$node_bin" ]; then
  echo "service: no node on this host" >&2
  exit 2
fi

# The plugin is TypeScript, and the check runs it as it is written: node
# strips the types itself since 22.6, and the resolver of the check adds the
# extension to the relative imports.
node_major="$("$node_bin" -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "$node_major" -lt 22 ]; then
  echo "service: node 22 or newer is needed to run the plugin's TypeScript" >&2
  exit 2
fi

# --- the wiring ------------------------------------------------------------
#
# The behaviour is proved by the run below; these are the wirings that make
# the behaviour reachable: the connector goes through the transport, the
# service branch talks to a socket, and the default placement did not change.

grep -q 'yeahTransport(' plugin/yeah-provider/index.server.ts ||
  fail "the connector does not go through the transport"
grep -q 'acpServiceStream(' plugin/yeah-provider/server/transport.ts ||
  fail "the service branch of the transport does not talk to a socket"
grep -q 'serviceMode' plugin/yeah-provider/shared/settings.ts ||
  fail "the placement is not a setting of the plugin"
grep -q 'default("spawn")' plugin/yeah-provider/shared/settings.ts ||
  fail "the default placement is not one Emacs per connection"

# --- the run ---------------------------------------------------------------

run_dir="$(mktemp -d 2>/dev/null)" || exit 2
export XDG_RUNTIME_DIR="$run_dir"
name="check-$$"

report="$(mktemp 2>/dev/null)" || exit 2

"$node_bin" --disable-warning=MODULE_TYPELESS_PACKAGE_JSON \
  --import ./tests/support/yeah-ts-resolve.mjs \
  ./tests/support/yeah-service-driver.ts \
  "$name" "$emacs_bin" "$PWD/lib" "$PWD" >"$report" 2>/tmp/yeah-service-check.err
driver_rc=$?

if [ "$driver_rc" -ne 0 ]; then
  echo "service: the plugin did not talk to the core over the socket:" >&2
  sed -n '1,20p' /tmp/yeah-service-check.err >&2
  failures=1
fi

# The socket the plugin uses must be the socket the kernel names: a service
# raised from Emacs and a service raised from the plugin do not take each
# other's place.
kernel_socket="$("$emacs_bin" -Q --batch -L lib -l yeah-service \
  --eval "(princ (yeah-service-socket-path \"$name\"))" 2>/dev/null || true)"
plugin_socket="$(sed -n 's/.*"socket":"\([^"]*\)".*/\1/p' "$report" | head -1)"
if [ -z "$plugin_socket" ]; then
  fail "the plugin did not report the socket of the core"
elif [ -n "$kernel_socket" ] && [ "$kernel_socket" != "$plugin_socket" ]; then
  fail "the plugin and the kernel name different sockets: $plugin_socket and $kernel_socket"
fi

# The report must say that the second agent came to the same core.
if ! grep -q '"sameCore":true' "$report"; then
  fail "the second agent did not come to the same core"
fi

rm -f "$report" /tmp/yeah-service-check.err
rm -rf "$run_dir"

if [ "$failures" -ne 0 ]; then
  exit 1
fi
exit 0
