#!/usr/bin/env bash
# check-the-dev-gate-asks-the-method-for-changed-claims.sh — the fast gate
# asks the method for the partial run.
#
# The development loop pays for the claims it touched, not for the whole
# standing specification: scripts/gate --changed passes --changed to the
# run of the method, scripts/dev gate-fast is that gate, a killed changed
# run is answered rather than restarted, and every line of the fast gate
# carries the time it arrived.  The check proves all of that with a
# stand-in for the method that records what it was asked.
#
# Exit codes: 0 — the changed gate asks for the changed claims; 1 — it does
# not; 2 — bad input.

set -u
cd "$(dirname "$0")/../.." || exit 2
[ -x scripts/gate ] || exit 2
[ -x scripts/dev ] || exit 2
command -v awk >/dev/null 2>&1 || exit 2

work="$(mktemp -d "${TMPDIR:-/tmp}/yeah-gate-fast-check-XXXXXX")" || exit 2
trap 'rm -rf "$work"' EXIT INT TERM

# The stand-in for the method records its arguments, the command line of
# the runner that asked for it, and answers green.
make_green_mathc() {
  cat > "$work/mathc" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "stand-in mathc: $*"
printf '%s\n' "args: $*" >> "$(dirname "$0")/calls"
printf '%s\n' "parent: $(tr '\0' ' ' < /proc/$PPID/cmdline 2>/dev/null)" >> "$(dirname "$0")/calls"
exit 0
EOF
  chmod +x "$work/mathc"
}

# The stand-in that dies on the run: a killed changed run must be answered,
# not started again.
make_killed_mathc() {
  cat > "$work/mathc" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "stand-in mathc: $*"
printf '%s\n' "args: $*" >> "$(dirname "$0")/calls"
case "$*" in
  *run*) kill -9 $$ ;;
esac
exit 0
EOF
  chmod +x "$work/mathc"
}

fail=0

# The changed gate asks the method for run --changed, bounded by five
# minutes, and answers green when the method answers green.
make_green_mathc
: > "$work/calls"
MATHC="$work/mathc" scripts/gate --changed > "$work/changed.out" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "gate-fast: the changed gate answered $rc, the answer of a green stand-in is 0" >&2
  cat "$work/changed.out" >&2
  fail=1
fi
if ! grep -q 'args: --root \. run --changed' "$work/calls"; then
  echo "gate-fast: the changed gate did not ask the method for the changed run" >&2
  cat "$work/calls" >&2
  fail=1
fi
if ! grep -q 'parent: .* --limit 300 ' "$work/calls"; then
  echo "gate-fast: the changed gate did not bound its attempt to five minutes" >&2
  cat "$work/calls" >&2
  fail=1
fi

# The full gate stays the full gate: no --changed in what it asks for.
: > "$work/calls"
MATHC="$work/mathc" scripts/gate > "$work/full.out" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "gate-fast: the full gate answered $rc, the answer of a green stand-in is 0" >&2
  cat "$work/full.out" >&2
  fail=1
fi
if grep -q -- '--changed' "$work/calls"; then
  echo "gate-fast: the full gate asked the method for the changed run" >&2
  cat "$work/calls" >&2
  fail=1
fi

# scripts/dev gate-fast is the changed gate, and its output says when every
# line arrived.
: > "$work/calls"
MATHC="$work/mathc" scripts/dev gate-fast > "$work/wrapper.out" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "gate-fast: scripts/dev gate-fast answered $rc, the answer of a green stand-in is 0" >&2
  cat "$work/wrapper.out" >&2
  fail=1
fi
if ! grep -q 'args: --root \. run --changed' "$work/calls"; then
  echo "gate-fast: scripts/dev gate-fast did not ask the method for the changed run" >&2
  cat "$work/calls" >&2
  fail=1
fi
if ! grep -q '\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] ' "$work/wrapper.out"; then
  echo "gate-fast: the output of the wrapper carries no time of the day" >&2
  cat "$work/wrapper.out" >&2
  fail=1
fi

# A killed changed run is answered, not restarted: one attempt is the
# default of the changed gate.
make_killed_mathc
: > "$work/calls"
MATHC="$work/mathc" scripts/gate --changed > "$work/killed.out" 2>&1
rc=$?
if [ "$rc" -ne 3 ]; then
  echo "gate-fast: a killed changed run answered $rc, the third answer is 3" >&2
  cat "$work/killed.out" >&2
  fail=1
fi
if ! grep -q 'the attempts ran out' "$work/killed.out"; then
  echo "gate-fast: a killed changed run was not named as the attempts running out" >&2
  cat "$work/killed.out" >&2
  fail=1
fi
runs="$(grep -c 'args: --root \. run' "$work/calls" || true)"
if [ "$runs" != 1 ]; then
  echo "gate-fast: the killed changed run was started $runs time(s), the changed gate starts it once" >&2
  cat "$work/calls" >&2
  fail=1
fi

exit "$fail"
