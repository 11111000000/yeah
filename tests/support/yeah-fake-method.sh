#!/usr/bin/env bash
# tests/support/yeah-fake-method.sh — a stand-in for the method.
#
# The gate of the project runs the method: `mathc --root . run' and
# `mathc --root . map'.  A check of the gate must not run the real method:
# a real run takes minutes, and it writes the evidence trail of the
# project.  This script answers like the method in the two ways the gate
# depends on.
#
# The first attempt of the run waits for ever, so that the check can kill
# it the way an unknown sender killed three runs of the method on
# 2026-11-18.  The second attempt ends the way a run ends, and the map is
# written after it.
#
# The files of the run live in the directory of YEAH_FAKE_METHOD_DIR:
#   attempts — one line per attempt of the run
#   map     — the map of the run
#
# Exit codes: 0 — the run ended; 2 — the usage is wrong.

set -u

dir="${YEAH_FAKE_METHOD_DIR:-}"
if [ -z "$dir" ]; then
  echo "tests/support/yeah-fake-method.sh: YEAH_FAKE_METHOD_DIR is not set" >&2
  exit 2
fi
mkdir -p "$dir"

command_name=""
for arg in "$@"; do
  case "$arg" in
    run) command_name="run" ;;
    map) command_name="map" ;;
  esac
done

case "$command_name" in
  run)
    attempt=1
    if [ -f "$dir/attempts" ]; then
      attempt=$(( $(wc -l < "$dir/attempts") + 1 ))
    fi
    printf 'run=%s pid=%s\n' "$attempt" "$$" >> "$dir/attempts"
    if [ "$attempt" -eq 1 ]; then
      # The first attempt waits for ever: the check kills it.  The wait
      # replaces this shell, so the process that waits is the process the
      # check knows, and killing it leaves nothing behind.
      exec sleep 300
    fi
    printf 'done=%s\n' "$attempt" >> "$dir/attempts"
    exit 0
    ;;
  map)
    printf 'map=complete\n' > "$dir/map"
    exit 0
    ;;
  *)
    echo "tests/support/yeah-fake-method.sh: unknown command: $*" >&2
    exit 2
    ;;
esac
