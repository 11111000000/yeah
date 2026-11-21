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
#
# The root of the tree of the processes is /proc.  The variable
# PROC_ROOT names another root: a check hands the scan a tree of fake
# stat files and reads the processes of it, and not the processes of the
# host.  The variable is read at every call and not once at the reading
# of this file.
#
# The scan of the tree does not stop at a stat file that is gone.  A
# process that exits while the tree is read is not a reason to leave the
# rest of the tree unread: the rest of the tree is what holds the
# children that are still alive, and a scan that stops there stops the
# stop of a tree in the middle and leaves a server behind.  A stat file
# that is there and cannot be read is another thing: the name of the
# file is said, because the reader does not know and says so.

now_ms() {
  printf '%s' "$(( $(date +%s%N) / 1000000 ))"
}

# The stat file of the process PID, read into stat_line.
#
# The answer is 0 when the line was read, 1 when the file cannot be
# reached at all (the process is gone: there is nothing to say about
# it), and 2 when the file is there and cannot be read (the reader does
# not know, and it says so).
stat_line=""
stat_file=""
read_stat() {
  local pid="$1"
  stat_file="${PROC_ROOT:-/proc}/$pid/stat"
  stat_line=""
  IFS= read -r stat_line 2>/dev/null < "$stat_file" || true
  if [ -n "$stat_line" ]; then
    return 0
  fi
  # The line could not be read.  A file that cannot be reached at all is
  # a process that is gone: there is nothing to say about it.  A file
  # that is there and holds no line is another thing: the name of the
  # file is said, because the reader does not know and says so.
  if [ -e "$stat_file" ]; then
    echo "tree: the stat file of a process cannot be read: $stat_file" >&2
    return 2
  fi
  return 1
}

# The parent and the group of the process of the stat line LINE.
#
# The name of a process may hold spaces and parentheses of its own, so
# the fields of the stat line are read after the LAST closing
# parenthesis: what is left is the state, the parent, the group, the
# session, and the rest.
#
# The answer is in stat_parent and stat_group, and the function fails
# when the line is not a stat line.
stat_parent=""
stat_group=""
stat_fields_of() {
  local line="$1" words
  stat_parent=""
  stat_group=""
  case "$line" in
    *") "*) words="${line##*) }" ;;
    *) return 1 ;;
  esac
  # the words after the name: the state, the parent, the group, the
  # session, and the rest
  case "$words" in
    *" "*) words="${words#* }" ;;
    *) return 1 ;;
  esac
  case "$words" in
    *" "*) stat_parent="${words%% *}"; words="${words#* }" ;;
    *) return 1 ;;
  esac
  case "$words" in
    *" "*) stat_group="${words%% *}" ;;
    *) stat_group="$words" ;;
  esac
  [ -n "$stat_parent" ] && [ -n "$stat_group" ]
}

# The process group of the process PID, or nothing when the process is
# gone.
process_group() {
  read_stat "$1" || return 0
  stat_fields_of "$stat_line" || return 0
  printf '%s\n' "$stat_group"
}

# The tree of the processes, read once.
#
# The pids of the tree are in tree_order, in the order of the reading,
# and the children of every parent of the tree are in tree_children, in
# the order of the reading too.
#
# The scan reads the stat file of every process of the tree and it goes
# on at a file that is gone: the process exited while the tree was read
# and the children that are still alive are in the rest of the tree.
# The scan reads the tree once and not once per level of it: a scan per
# level reads the tree of the host as many times as the tree is deep,
# and the depth is not known.
declare -a tree_order=()
declare -A tree_children=()

scan_tree() {
  local root file pid
  root="${PROC_ROOT:-/proc}"
  tree_order=()
  tree_children=()
  for file in "$root"/[0-9]*/stat; do
    pid="${file%/*}"
    pid="${pid##*/}"
    case "$pid" in
      ''|*[!0-9]*) continue ;;
    esac
    read_stat "$pid" || continue
    if ! stat_fields_of "$stat_line"; then
      echo "tree: the stat file of a process holds no stat line: $stat_file" >&2
      continue
    fi
    case "$stat_parent" in
      ''|*[!0-9]*) continue ;;
    esac
    tree_order+=("$pid")
    tree_children["$stat_parent"]="${tree_children[$stat_parent]:-} $pid"
  done
}

# The descendants of the process PID in the tree that was read, the
# deepest first.
#
# The walk has a limit of the depth: a tree that holds a cycle does not
# make the walk endless.
descendants_of() {
  local parent="$1" depth="${2:-0}" child
  [ "$depth" -lt 64 ] || return 0
  # The children of the parent are the words of the list of them, and
  # the pids of the tree are numbers: the list is split into words and
  # not into names.
  for child in ${tree_children[$parent]:-}; do
    descendants_of "$child" "$((depth + 1))"
    printf '%s\n' "$child"
  done
}

# The descendants of PID, the deepest first.
descendants() {
  local parent="$1"
  case "$parent" in
    ''|*[!0-9]*) return 0 ;;
  esac
  scan_tree
  descendants_of "$parent"
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
