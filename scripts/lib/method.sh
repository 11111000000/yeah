#!/usr/bin/env bash
# scripts/lib/method.sh — the place of the method.
#
# This file is read, not run: the scripts that call the method read it and
# call its function.  The method is one binary, and the way to find it is
# one thing: a copy of the search in two scripts is two copies that drift
# apart, and the copy that drifts is the one that runs the gate of the
# project with no method at all.
#
# The functions:
#   find_mathc — the path of the method binary, or nothing when there is
#                none.  MATHC names it; else it is `mathc' on PATH; else
#                the binary of the user in ~/.local/bin.

find_mathc() {
  if [ -n "${MATHC:-}" ]; then
    printf '%s' "${MATHC}"
    return 0
  fi
  if command -v mathc >/dev/null 2>&1; then
    command -v mathc
    return 0
  fi
  if [ -x "$HOME/.local/bin/mathc" ]; then
    printf '%s' "$HOME/.local/bin/mathc"
    return 0
  fi
  return 1
}
