#!/usr/bin/env bash
# scripts/lib/tree.sh — the tree of processes, and the way to stop it.
#
# This file is read, not run: the scripts that own a tree of processes
# (scripts/dev-timeout, scripts/live-pilot, scripts/gate) read it and
# call its functions.  The knowledge of /proc lives here, once: a copy
# of it in three scripts is three copies that drift apart, and the copy
# that drifts is the one that leaves a server behind.
#
# The functions:
#   now_ms                — the time in milliseconds
#   process_group PID     — the group of the process PID, or nothing
#   descendants PID       — the descendants of PID, the deepest first
#   kill_group PID SIGNAL — the signal to the group of PID
#   stop_tree PID SIGNAL  — the signal to the process and to its tree
#   stop_now PID          — the signal a timer sends: SIGTERM
#   own_group             — the group of this shell; it is never signalled
#
# The group of this shell is remembered once, when this file is read.
# The group of the shell that reads the file is never signalled: a
# mistake here would kill the gate that runs the check.

now_ms() {
  printf '%s' "$(( $(date +%s%N) / 1000000 ))"
}

# The process group of the process PID, or nothing when the process is gone.
process_group() {
  awk '{ i = index($0, ")"); if (i == 0) next
         rest = substr($0, i + 2); split(rest, f, " ")
         print f[3] }' "/proc/$1/stat" 2>/dev/null
}

# The descendants of PID, the deepest first.
#
# The name of a process may hold spaces and parentheses, so the fields of
# /proc/PID/stat are read after the last closing parenthesis: what is left
# is the state, the parent, the group, the session, and the rest.
descendants() {
  local parent="$1" child
  while read -r child; do
    [ -n "$child" ] || continue
    descendants "$child"
    printf '%s\n' "$child"
  done <<CHILDREN
$(awk -v p="$parent" '
  FNR == 1 { split(FILENAME, parts, "/"); pid = parts[3] }
  { i = index($0, ")"); if (i == 0) next
    rest = substr($0, i + 2); split(rest, f, " ")
    if (f[2] + 0 == p + 0) print pid }' /proc/[0-9]*/stat 2>/dev/null)
CHILDREN
}

own_group="$(process_group $$)"

# Signal the group of PID, but only when PID leads a group of its own.
# The group of this shell is never signalled: a mistake here would kill
# the gate that runs the check.
kill_group() {
  local pid="$1" signal="$2" group
  group="$(process_group "$pid")"
  if [ -n "$group" ] && [ "$group" = "$pid" ] && [ "$group" != "$own_group" ]; then
    kill -"$signal" "-$group" 2>/dev/null || true
  fi
}

# Stop the process PID and everything it started.
stop_tree() {
  local pid="$1" signal="$2" child
  for child in $(descendants "$pid"); do
    kill_group "$child" "$signal"
    kill -"$signal" "$child" 2>/dev/null || true
  done
  kill_group "$pid" "$signal"
  kill -"$signal" "$pid" 2>/dev/null || true
}

# Stop the process PID the way a timer stops it.
stop_now() {
  stop_tree "$1" TERM
}
