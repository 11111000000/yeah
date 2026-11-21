#!/usr/bin/env bash
# check-the-tree-of-the-processes-survives-a-vanished-process.sh — canary for
# the claim `the-tree-of-the-processes-survives-a-vanished-process'.
#
# The gap: the tree of the processes is read from /proc, and a process can
# exit while the tree is read.  The scan of the tree was one awk over the
# glob /proc/[0-9]*/stat, and awk stops at a file it cannot open: one
# process that exited in the middle of the scan cut the list of the
# descendants short, and stop_tree killed the part of the tree it was
# given and left the rest of it behind.  The message of awk was hidden,
# and the list was cut all the same.
#
# The second defect is in the same code: the fields of the stat file were
# read after the FIRST closing parenthesis, so a process whose name holds
# a parenthesis was read as a process whose parent is a letter, and its
# children were not found.  The comment of the file promised the last
# parenthesis, and the code read the first.
#
# This check reads the code of the tree in a temporary tree and hands the
# scan a tree of processes of its own — a tree of fake stat files, with a
# file that is gone and a file that cannot be read in it:
#
#   1. the scan reads the root it was given: the children of the fixture
#      are found;
#   2. the scan goes on at the file that is gone: the children that come
#      after it are found, and the file that is gone is not complained
#      about — a process that exited is not an error;
#   3. the fields are read after the last closing parenthesis: the child
#      whose name holds a parenthesis is found;
#   4. the file that is there and holds no line is named: the reader
#      does not know, and it says so;
#   5. the descendants are the deepest first;
#   6. the group of a process is read after the last parenthesis as well,
#      and the group of a process that is gone is nothing;
#   7. the group of the shell that reads the tree is never signalled, and
#      the group of a process that leads a group of its own is;
#   8. the tree of the repository is never written.
#
# The stands of the kinds of the defect are apart: the break of one kind
# is caught by the stand of that kind, and the words of the refusal name
# the true subject of the refusal and not "an error".
#
# Exit codes: 0 — the promise holds; 1 — it does not; 2 — the tree is not
# where we think, or a tool of the check is missing.

set -u

failures=0
fail() {
  echo "tree-scan: $1" >&2
  failures=1
}
blocked() {
  echo "tree-scan: $1" >&2
  exit 2
}

cd "$(dirname "$0")/../.." || blocked "the tree of the repository is not where we think"
[ -d lib ] || blocked "lib/ is not there: the tree of the repository is not where we think"
[ -f scripts/lib/tree.sh ] || blocked "scripts/lib/tree.sh is not there: the tree of the repository is not where we think"
REPO="$(pwd)"

# --- the temporary tree of the check -----------------------------------------

tmp="$(mktemp -d "${TMPDIR:-/tmp}/yeah-tree-scan.XXXXXX")" || blocked "cannot make the temporary tree of the check"

# The rm of the agent moves a directory to the trash: the tree of this
# check must be gone, and not in the trash.  The shim of the tree holds
# the rm of the system, and it is the rm of the system that removes the
# tree.
system_tool() {
  local tool="$1" found dir
  found="$(command -v "$tool" 2>/dev/null || true)"
  case "$found" in
    */shims/*)
      for dir in /usr/bin /bin /run/current-system/sw/bin; do
        if [ -x "$dir/$tool" ]; then
          printf '%s' "$dir/$tool"
          return 0
        fi
      done
      ;;
  esac
  [ -n "$found" ] || return 1
  printf '%s' "$found"
}

system_rm="$(system_tool rm || true)"
cleanup() {
  if [ -n "$system_rm" ]; then
    "$system_rm" -rf "$tmp" 2>/dev/null || true
  else
    rm -rf "$tmp" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# The tree of the repository before the check: the check writes nothing
# into it, and the listing says so.
repo_before="$(cd "$REPO" && find . -path ./.git -prune -o -print | LC_ALL=C sort | md5sum)"

# --- the code under test -----------------------------------------------------

# The tree under test is a copy in the temporary tree of the check: the
# check reads the code of the repository and runs the copy, and the tree
# of the repository is never written.
tree="$tmp/lib/tree.sh"
mkdir -p "$tmp/lib" || blocked "cannot make the tree of the check"
cp "$REPO/scripts/lib/tree.sh" "$tree" || blocked "cannot copy the tree under test"

# The tree under test is read here as well: the stand of the groups needs
# the functions of the tree in the shell of the check.
. "$tree"

# The runner of the check: it reads the tree under test and asks it for
# the descendants of a pid.  The root of the tree of the processes is
# PROC_ROOT, and the fixture is the root of this run.
runner="$tmp/run-descendants.sh"
cat > "$runner" <<'RUNNER' || blocked "cannot make the tree of the check"
#!/usr/bin/env bash
set -u
. "$1" || exit 2
descendants "$2"
RUNNER

# The runner of the group of a process.
group_runner="$tmp/run-group.sh"
cat > "$group_runner" <<'RUNNER' || blocked "cannot make the tree of the check"
#!/usr/bin/env bash
set -u
. "$1" || exit 2
process_group "$2"
RUNNER

# --- the tree of processes of the check --------------------------------------

fixture="$tmp/proc"
mkdir -p "$fixture" || blocked "cannot make the tree of the check"

# A stat file of a process: the pid, the name, the state, the parent,
# the group, the session, and the rest of the fields.
make_stat() {
  local pid="$1" comm="$2" ppid="$3"
  mkdir -p "$fixture/$pid" || blocked "cannot make the tree of the check"
  printf '%s (%s) S %s %s %s 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n' \
    "$pid" "$comm" "$ppid" "$pid" "$pid" > "$fixture/$pid/stat" ||
    blocked "cannot make the tree of the check"
}

make_stat 100 root 1                # the parent of the tree of the check
make_stat 101 before 100            # a child of 100, before the file that is gone
# 102 — the stat file that is gone: a link to nothing
mkdir -p "$fixture/102" || blocked "cannot make the tree of the check"
ln -s /nonexistent-target-xyz "$fixture/102/stat" || blocked "cannot make the tree of the check"
make_stat 103 after 100             # a child of 100, after the file that is gone
make_stat 104 deep 103              # a child of 103
make_stat 105 'weird) name' 103     # a child of 103 whose name holds a parenthesis
# 106 — the stat file that is there and holds no line: a directory
mkdir -p "$fixture/106/stat" || blocked "cannot make the tree of the check"
make_stat 107 last 100              # a child of 100, after the file that holds no line

# The words of a list of pids, separated by a space.
words() {
  printf '%s' "$1" | tr ' \n' '  ' | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//'
}

# --- the scan of the fixture -------------------------------------------------

scan_err="$tmp/scan.err"
scan_out=""
run_scan() {
  scan_err="$tmp/scan.err"
  scan_out="$(PROC_ROOT="$fixture" bash "$runner" "$tree" 100 2>"$scan_err")"
}
run_scan

found_order="$(words "$scan_out")"
found_pid() {
  case " $found_order " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# --- 1. the scan reads the root it was given ---------------------------------

# The children of 100 in the fixture are 101, 103, 104, 105 and 107.
# The child 101 is before the file that is gone and the child 103 is
# after it, so a scan that stops at the file that is gone is told from a
# scan that read another tree.

root_read=1
if ! found_pid 101; then
  fail "the scan of the tree of the processes did not read the root it was given: $fixture — the children of 100 that are in the tree were not found: 101 103 104 105 107"
  root_read=0
fi

# --- 2. the scan goes on at the file that is gone ---------------------------

# The children that come after the file that is gone are found.  The file
# that is gone is not complained about: a process that exited while the
# tree was read is not an error, and the reader has nothing to say about
# it.

if [ "$root_read" -eq 1 ]; then
  missing=""
  for pid in 101 103 104 105 107; do
    found_pid "$pid" || missing="$missing $pid"
  done
  if [ -n "$missing" ]; then
    if ! found_pid 103; then
      fail "the scan of the tree of the processes stopped at the file that is gone: $fixture/102/stat — the children after it were not found:$missing"
    elif ! found_pid 105; then
      fail "the scan of the tree of the processes did not find the child whose name holds a parenthesis: $fixture/105/stat — the children that were not found:$missing"
    else
      fail "the scan of the tree of the processes did not find the children of 100 that are in the tree: $fixture — the children that were not found:$missing"
    fi
  fi
fi

# --- 3. the file that holds no line is named --------------------------------

# The file that is there and holds no line is another thing than the file
# that is gone: the reader does not know, and it says so.  The name of
# the file is in the words of the complaint.

if [ "$root_read" -eq 1 ]; then
  if ! grep -q -F "$fixture/106/stat" "$scan_err"; then
    fail "the scan of the tree of the processes did not name the stat file it cannot read: $fixture/106/stat"
  fi
  if grep -q -F "$fixture/102/stat" "$scan_err"; then
    fail "the scan of the tree of the processes complained about the stat file that is gone: $fixture/102/stat — a process that exited is not an error"
  fi
fi

# --- 4. the descendants are the deepest first -------------------------------

# The order of the promise is the deepest first: the children of 103 come
# before 103, and 103 comes before 107.

if [ "$root_read" -eq 1 ]; then
  expected_order=""
  for pid in 101 104 105 103 107; do
    found_pid "$pid" && expected_order="$expected_order $pid"
  done
  expected_order="$(words "$expected_order")"
  if [ "$found_order" != "$expected_order" ]; then
    fail "the descendants of 100 are not the deepest first: [$found_order] and not [$expected_order]"
  fi
fi

# --- 5. the group of a process is read after the last parenthesis ------------

# The group of a process whose name holds a parenthesis is the group of
# the process: the fields of the stat line are read after the last
# closing parenthesis here too.  The group of a process that is gone is
# nothing: there is no group, and the caller that stops a tree does not
# signal a group that is not there.

group_of() {
  PROC_ROOT="$fixture" bash "$group_runner" "$tree" "$1" 2>/dev/null
}

group_105="$(group_of 105)"
if [ "$group_105" != "105" ]; then
  fail "the group of the process whose name holds a parenthesis is not the group of the process: [$group_105] and not [105]"
fi
group_gone="$(group_of 999)"
if [ -n "$group_gone" ]; then
  fail "the group of a process that is gone is not nothing: [$group_gone]"
fi

# --- 6. the group of the shell that reads the tree is never signalled -------

# The check reads the tree under test in a shell of its own, in a group
# of its own: the shell leads that group, and that group is the group
# that must never be signalled.  The check asks the tree to signal it,
# and the shell must survive it.  A tree that cannot be stopped is not a
# tree that is stopped.
#
# setsid gives the shell a group of its own; without it the stand cannot
# be measured, and the check says so.

if command -v setsid >/dev/null 2>&1; then
  group_err="$tmp/group.err"
  group_answer="$(setsid bash -c '
    set -u
    . "$1" || exit 2
    group="$(process_group $$)"
    own="$own_group"
    kill_group $$ KILL
    printf "%s %s %s\n" "$$" "$group" "$own"
  ' _ "$tree" 2>"$group_err")"
  group_rc=$?
  group_words="$(words "$group_answer")"
  if [ "$group_rc" -ne 0 ] || [ -z "$group_words" ]; then
    fail "the group of the shell that reads the tree was signalled: the shell did not survive the signal of its own group: [$(words "$(cat "$group_err")")]"
  else
    set -- $group_words
    if [ "$1" != "$2" ] || [ "$2" != "$3" ]; then
      fail "the group of the shell that reads the tree is not the group that is never signalled: the pid is $1, the group is $2, and the group of the shell is $3"
    fi
  fi
else
  echo "tree-scan: setsid is not on this host: the group of the shell that reads the tree is not measured" >&2
fi

# --- 7. a group of its own is signalled -------------------------------------

# The guard of the group of this shell must not stop the tree: a process
# that leads a group of its own is signalled, and it goes.

child=""
{ set -m; sleep 30 & child=$!; disown "$child" 2>/dev/null || true; set +m; } 2>/dev/null
# The child leads a group of its own: the job control of the shell gave
# it one.  The job is disowned: the words of the death of a job are the
# noise of the shell and not the words of the check.
kill_group "$child" KILL 2>/dev/null || true
sleep 0.2
if kill -0 "$child" 2>/dev/null; then
  fail "the group of a process that leads a group of its own was not signalled: $child"
  kill -KILL "$child" 2>/dev/null || true
fi

# --- 8. the tree of the repository is not written ----------------------------

repo_after="$(cd "$REPO" && find . -path ./.git -prune -o -print | LC_ALL=C sort | md5sum)"
if [ "$repo_after" != "$repo_before" ]; then
  fail "the check wrote into the tree of the repository: [$repo_after] and not [$repo_before]"
fi

# --- the end -----------------------------------------------------------------

cleanup
trap - EXIT
if [ -e "$tmp" ]; then
  echo "tree-scan: the temporary tree of the check is still there: $tmp" >&2
  exit 1
fi
exit "$failures"
