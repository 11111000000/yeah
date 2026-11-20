#!/usr/bin/env bash
# scripts/lib/tools.sh — the place of the search for a tool.
#
# This file is read, not run: the scripts that call a tool read it and call
# its function.  The search for a tool is one thing and it lives in one
# place: a copy of the search in two scripts is a copy that drifts apart,
# and the copy that drifts is the one that answers "the tool is not here"
# when the tool is.
#
# The steps of the search are the same for every tool:
#   1. the variable of the environment (EMACS, PLANTUML) — the answer of the
#      person who runs the script;
#   2. the command on PATH;
#   3. the binary of the user in ~/.nix-profile/bin;
#   4. the store of nix — only when the caller names the glob.  The store is
#      the last step: a path in it is host-specific, and the store holds many
#      versions of the same tool.  The first match of the shell is taken, so
#      the choice is the same on every run of the machine.
#
# The store of nix is $NIX_STORE_DIR when the environment names it, and
# /nix/store otherwise.

find_tool() {
  local var="$1" cmd="$2" glob="${3:-}"
  local candidate="${!var:-}"
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    printf '%s' "$candidate"
    return 0
  fi
  if command -v "$cmd" >/dev/null 2>&1; then
    command -v "$cmd"
    return 0
  fi
  if [ -x "$HOME/.nix-profile/bin/$cmd" ]; then
    printf '%s' "$HOME/.nix-profile/bin/$cmd"
    return 0
  fi
  if [ -n "$glob" ]; then
    for candidate in $glob; do
      if [ -x "$candidate" ]; then
        printf '%s' "$candidate"
        return 0
      fi
    done
  fi
  return 1
}
