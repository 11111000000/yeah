#!/usr/bin/env bash
# check-the-state-diagram-comes-from-the-code.sh — canary for the claim
# `the-state-diagram-comes-from-the-code'.
#
# The claim promises that the diagram of the state machine is not a drawing
# but a reading of the code, and every part of that promise is measured
# here:
#
#   1. the file of the diagram in the repository is the file the code
#      writes: the generator runs in a temporary copy of the kernel, and
#      its bytes are compared with the bytes of the repository — the copy
#      is the point, a check that compares the file of the repository with
#      itself cannot fail;
#   2. the generator reads the table of the transitions: a cell added to
#      the table of the copy brings a new arrow into the diagram;
#   3. the generator reads the list of the states: a state added to the
#      list of the copy comes into the diagram;
#   4. the pipeline of the diagrams writes the source out of the code and
#      draws both themes of it;
#   5. the diagram covers the machine: every cell of the table is an arrow
#      of the diagram and the arrow says what the cell says, and the states
#      of the machine and no others — the numbers are read out of the code
#      and are not written here;
#   6. a tree without a kernel cannot generate the diagram, and the answer
#      of that is 3 and not 0;
#   7. the pipeline of the diagrams in a tree without a kernel ends with the
#      answer of the generation that failed and draws nothing;
#   8. the tree of the repository is never written: every run happens in a
#      temporary tree, and the trap of this script removes it;
#   9. the comparison tells a cell that the table of the machine names twice
#      from a cell that the diagram does not carry: a table that says the
#      same thing twice is a machine that says one thing about one event
#      twice, and not a generator that does not read the table.
#
# The search for the tools of this script is a search of its own: the check
# must not lean on the code that it checks.
#
# The words of the report are not measured: the numbers of the cells and of
# the states are read out of the code, and a wording is not a promise.
#
# Exit codes: 0 — the promise holds; 1 — the diagram and the code drifted
# apart; 2 — the tree is not where we think; 3 — Emacs or PlantUML is not
# on this machine.

set -u

failures=0
# The counter of the readings of the machine: every tree of the check is
# read into a tree of its own.
machine_counter=0
fail() {
  echo "state-diagram: $1" >&2
  failures=1
}

# The check cannot answer: the tree is not where we think, or the tree of the
# check cannot be made.  The answer of a check that cannot answer is 2, and
# it says why.
blocked() {
  echo "state-diagram: $1" >&2
  exit 2
}

cd "$(dirname "$0")/../.." || blocked "the tree of the repository is not where we think"
[ -d lib ] || blocked "lib/ is not there: the tree of the repository is not where we think"
[ -f scripts/dev ] || blocked "scripts/dev is not there: the tree of the repository is not where we think"
[ -f lib/yeah-state.el ] || blocked "lib/yeah-state.el is not there: the tree of the repository is not where we think"
[ -f lib/yeah-loop.el ] || blocked "lib/yeah-loop.el is not there: the tree of the repository is not where we think"
[ -f lib/yeah-state-diagram.el ] || blocked "lib/yeah-state-diagram.el is not there: the tree of the repository is not where we think"
[ -d site/diagrams ] || blocked "site/diagrams is not there: the tree of the repository is not where we think"
[ -f site/diagrams/state-machine.puml ] || blocked "site/diagrams/state-machine.puml is not there: the tree of the repository is not where we think"
[ -f site/diagrams/palette-light.puml ] || blocked "site/diagrams/palette-light.puml is not there: the tree of the repository is not where we think"
[ -f site/diagrams/palette-dark.puml ] || blocked "site/diagrams/palette-dark.puml is not there: the tree of the repository is not where we think"

REPO="$(pwd)"

# --- 0. the tools of this machine ---------------------------------------------

# The tools of this script are found by this script: the check must not
# lean on the code that it checks.
find_tool_here() {
  local var="$1" cmd="$2" glob="${3:-}"
  local candidate="${!var:-}"
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    printf '%s' "$candidate"
    return 0
  fi
  candidate="$(command -v "$cmd" 2>/dev/null || true)"
  if [ -n "$candidate" ]; then
    printf '%s' "$candidate"
    return 0
  fi
  if [ -x "${HOME:-}/.nix-profile/bin/$cmd" ]; then
    printf '%s' "${HOME}/.nix-profile/bin/$cmd"
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

find_emacs_here() {
  find_tool_here EMACS emacs "${NIX_STORE_DIR:-/nix/store}"/*emacs*/bin/emacs
}

find_plantuml_here() {
  find_tool_here PLANTUML plantuml "${NIX_STORE_DIR:-/nix/store}"/*plantuml*/bin/plantuml
}

# The rm of the agent moves a directory to the trash: the tree of this check
# must be gone, and not in the trash.  The shim of the tree holds the rm of
# the system, and it is the rm of the system that removes the tree.
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

# --- 1. the temporary trees of the check --------------------------------------

tmp="$(mktemp -d "${TMPDIR:-/tmp}/yeah-state-diagram.XXXXXX")" || blocked "cannot make the temporary tree of the check"
shim="$tmp/hermetic-bin"
mkdir -p "$shim" || blocked "cannot make the tree of the check"
system_rm="$(system_tool rm || true)"
if [ -n "$system_rm" ]; then
  ln -sf "$system_rm" "$shim/rm" || blocked "cannot make the tree of the check"
fi

cleanup() {
  if [ -x "$shim/rm" ]; then
    "$shim/rm" -rf "$tmp" 2>/dev/null || true
  else
    rm -rf "$tmp" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# The tree of the repository before the check: the check writes nothing into
# it, and the listing says so.
repo_sources_before="$(cd "$REPO/site/diagrams" && LC_ALL=C ls -A | LC_ALL=C sort | tr '\n' ' ')"
repo_pictures_before="$(cd "$REPO/site/assets/diagrams" && LC_ALL=C ls -A | LC_ALL=C sort | tr '\n' ' ')"

# A tree of our own with the kernel of the repository in it: the generation
# and the pipeline happen there and not in the tree of the repository.
make_tree() {
  local dir="$1"
  mkdir -p "$dir/lib" "$dir/scripts" "$dir/site/diagrams" || blocked "cannot make the tree of the check"
  cp "$REPO"/lib/*.el "$dir/lib/" || blocked "cannot make the tree of the check"
  cp -R "$REPO/scripts/." "$dir/scripts/" || blocked "cannot make the tree of the check"
}

# The generator of the tree, and its answer.
run_generator() {
  local dir="$1" log="$2"
  (
    cd "$dir" || blocked "cannot enter the tree of the run"
    EMACS="$emacs_bin" bash scripts/dev state-diagram
  ) >"$log" 2>&1
}

# The names of the states of a diagram: the label of the state, or its
# identifier when the name of the state is one PlantUML reads as it is.
diagram_states() {
  sed -n 's/^state "\([^"]*\)".*/\1/p; s/^state \([A-Za-z][A-Za-z0-9_]*\)$/\1/p' "$1"
}

# The machine of the kernel, read out of the code of a tree: the names of the
# states and the cells of the table of the transitions.  The numbers of this
# check are the numbers of the code, and they are not written here.
#
# The states are written one per line into $stem.states, the cells of the
# table as FROM LABEL TO into $stem.cells, and the raw words of the reading
# into $stem.raw.
read_machine() {
  local lib="$1" stem="$2"
  "$emacs_bin" -Q --batch -L "$lib" --eval \
    '(progn (require (quote yeah-state)) (require (quote yeah-loop))
             (dolist (state yeah-state-list) (princ (format "state %s\n" state)))
             (dolist (cell yeah-loop--raw-transitions)
               (princ (format "cell %s\t%s\t%s\n"
                              (nth 0 cell) (nth 1 cell) (nthcdr 2 cell)))))' \
    2>/dev/null >"$stem.raw" || true
  sed -n 's/^state //p' "$stem.raw" >"$stem.states"
  sed -n 's/^cell //p' "$stem.raw" >"$stem.cells"
}

# The comparison of the cells of the table and the arrows of the diagram.
# The program is written here and not taken from the tree: the check must
# not lean on the code that it checks.
#
# The first file holds the cells of the table, one per line, as FROM LABEL TO;
# the second file is the diagram of the state machine.  Every line of the
# output is a defect, and its first field is the kind of it:
#
#   absent  — the cell is not in the diagram at all;
#   leads   — the arrow of the cell is there and its ends are not the ends
#             of the cell;
#   label   — the arrow of the cell is there and its label is not the label
#             of the cell;
#   count   — the diagram has another number of arrows than the table has
#             cells;
#   twice   — the table of the machine names the same cell more than once and
#             the diagram carries fewer arrows for that cell than the table
#             names cells;
#   twice-arrow
#           — the diagram carries the same arrow more than once and the cell
#             of the table has no arrow of its own.
#
# The identifier of a state is its letters, its digits and its underscore:
# PlantUML reads no other name as an identifier, and a name with a dash in it
# is carried by the diagram under an identifier of its own.
cat >"$tmp/compare-cells.awk" <<'AWK'
BEGIN { FS = "[ \t]+" }

function ident(text) { gsub(/[^A-Za-z0-9_]/, "_", text); return text }

function report_absent(i) {
  printf "absent\t%s\t%s\t%s\n", c_from[i], c_label[i], c_to[i]
}

function report_leads(i, j) {
  printf "leads\t%s\t%s\t%s\t%s --> %s : %s\n",
    c_from[i], c_label[i], c_to[i], a_src[j], a_tgt[j], a_lbl[j]
}

function report_label(i, j) {
  printf "label\t%s\t%s\t%s\t%s --> %s : %s\n",
    c_from[i], c_label[i], c_to[i], a_src[j], a_tgt[j], a_lbl[j]
}

# The table of the machine names the same cell more than once, and the
# diagram carries fewer arrows for that cell than the table names cells.
function report_twice(i) {
  printf "twice\t%s\t%s\t%s\t%d\t%d\n",
    c_from[i], c_label[i], c_to[i], c_same[i], c_arrows[i]
}

# The diagram carries the same arrow more than once, and the cell of the
# table has no arrow of its own.
function report_twice_arrow(i, j) {
  printf "twice-arrow\t%s\t%s\t%s\t%s --> %s : %s\t%d\n",
    c_from[i], c_label[i], c_to[i], a_src[j], a_tgt[j], a_lbl[j], a_same[j]
}

FILENAME == cells_file {
  cells++
  c_from[cells] = $1
  c_label[cells] = $2
  c_to[cells] = $3
  c_idfrom[cells] = ident($1)
  c_idto[cells] = ident($3)
  next
}

{
  if (!match($0, / --> /)) next
  src = substr($0, 1, RSTART - 1)
  rest = substr($0, RSTART + 5)
  if (!match(rest, / : /)) next
  tgt = substr(rest, 1, RSTART - 1)
  lbl = substr(rest, RSTART + 3)
  arrows++
  a_src[arrows] = src
  a_tgt[arrows] = tgt
  a_lbl[arrows] = lbl
}

END {
  if (arrows != cells)
    printf "count\t%d\t%d\n", arrows, cells

  # The cells of the table that say the same thing, and the arrows of the
  # diagram that say the same thing.  A cell that the table names twice is
  # not a cell that the diagram does not carry: the table of the machine
  # says one thing about one event twice, and the diagram carries one
  # arrow for one cell.
  for (i = 1; i <= cells; i++) {
    c_same[i] = 1
    c_arrows[i] = 0
    for (k = 1; k <= cells; k++)
      if (k != i && c_from[k] == c_from[i] && c_label[k] == c_label[i] && c_to[k] == c_to[i])
        c_same[i]++
    for (j = 1; j <= arrows; j++)
      if (a_src[j] == c_idfrom[i] && a_tgt[j] == c_idto[i] && a_lbl[j] == c_label[i])
        c_arrows[i]++
  }
  for (j = 1; j <= arrows; j++) {
    a_same[j] = 1
    for (k = 1; k <= arrows; k++)
      if (k != j && a_src[k] == a_src[j] && a_tgt[k] == a_tgt[j] && a_lbl[k] == a_lbl[j])
        a_same[j]++
  }
  # The first arrow that the diagram carries more than once.
  repeated = 0
  for (j = 1; j <= arrows; j++)
    if (a_same[j] > 1) { repeated = j; break }

  # The cells that the diagram draws as they are.
  for (i = 1; i <= cells; i++)
    for (j = 1; j <= arrows; j++)
      if (!taken[j] && a_src[j] == c_idfrom[i] && a_tgt[j] == c_idto[i] && a_lbl[j] == c_label[i]) {
        taken[j] = 1
        drawn[i] = 1
        break
      }

  for (i = 1; i <= cells; i++) {
    if (drawn[i]) continue
    # The same source and the same label: the arrow is the arrow of the
    # cell and it leads somewhere else.
    j = 0
    for (k = 1; k <= arrows; k++)
      if (!taken[k] && a_src[k] == c_idfrom[i] && a_lbl[k] == c_label[i]) { j = k; break }
    if (j) { taken[j] = 1; report_leads(i, j); continue }
    # The same label: the cell is in the diagram and the ends of its arrow
    # are not the ends of the cell.
    j = 0
    for (k = 1; k <= arrows; k++)
      if (!taken[k] && a_lbl[k] == c_label[i]) { j = k; break }
    if (j) { taken[j] = 1; report_leads(i, j); continue }
    # The same source: the cell is in the diagram and the label of its
    # arrow is not the label of the cell.  The diagram carries that arrow
    # more than once: the cell has no arrow of its own, and the diagram
    # repeats the arrow of another cell.
    j = 0
    for (k = 1; k <= arrows; k++)
      if (!taken[k] && a_src[k] == c_idfrom[i]) { j = k; break }
    if (j) {
      taken[j] = 1
      if (a_same[j] > 1) report_twice_arrow(i, j)
      else report_label(i, j)
      continue
    }
    # The table of the machine names the same cell more than once, and the
    # diagram carries fewer arrows for that cell than the table names
    # cells: the cell is not an absent cell, it is a cell of a table that
    # says the same thing twice.
    if (c_same[i] > 1 && c_arrows[i] < c_same[i]) { report_twice(i); continue }
    # The arrow of the cell in the order of the table: the cell is in the
    # diagram and neither its ends nor its label are its own.
    if (arrows == cells && !taken[i]) {
      taken[i] = 1
      if (a_same[i] > 1) report_twice_arrow(i, i)
      else report_label(i, i)
      continue
    }
    # The diagram carries the same arrow more than once: the cell is not
    # in the diagram, and the diagram repeats the arrow of another cell.
    if (repeated) { report_twice_arrow(i, repeated); continue }
    report_absent(i)
  }
}
AWK

# Every cell of the table of the transitions is an arrow of the diagram, and
# the arrow says what the cell says.  The cells are read out of the code of
# the tree and the arrows out of the diagram of that tree.
#
# The kinds of the defect are told apart: a cell that is not in the diagram
# at all (the generator does not read the table), a cell that is in the
# diagram but leads somewhere else (the generator reads the table and writes
# the cell wrong), a cell that the table of the machine names twice (the
# machine says one thing about one event twice) and an arrow that the
# diagram carries more than once (the diagram repeats an arrow).
#
# The mode is "fail": a defect is a failure of the check.  The mode is
# "print": the defects are printed and the check decides what to do with
# them -- the control of the cell that the table names twice reads them.
compare_cells() {
  local lib="$1" diagram="$2" tag="$3" mode="${4:-fail}"
  local reported=0 compare_rc=0 stem kind from label to actual extra message
  machine_counter=$((machine_counter + 1))
  stem="$tmp/compare-$machine_counter"
  read_machine "$lib" "$stem"
  if [ ! -s "$stem.raw" ]; then
    fail "$tag: the machine of the kernel could not be read out of the code"
    return 1
  fi
  if [ ! -s "$diagram" ]; then
    fail "$tag: the diagram of the machine is missing or empty"
    return 1
  fi
  LC_ALL=C awk -v cells_file="$stem.cells" -f "$tmp/compare-cells.awk" \
    "$stem.cells" "$diagram" >"$stem.problems"
  compare_rc=$?
  if [ "$compare_rc" -ne 0 ]; then
    fail "$tag: the comparison of the cells of the table and the arrows of the diagram did not finish (the answer is $compare_rc): nothing was compared"
    return 1
  fi
  if [ ! -s "$stem.cells" ]; then
    fail "$tag: the table of the transitions has no cells to compare"
    return 1
  fi
  while IFS=$'\t' read -r kind from label to actual extra; do
    reported=$((reported + 1))
    message="$(problem_message "$tag" "$kind" "$from" "$label" "$to" "$actual" "$extra")"
    if [ "$mode" = fail ]; then
      if [ "$reported" -gt 5 ]; then
        continue
      fi
      fail "$message"
    else
      printf '%s\n' "$message"
    fi
  done <"$stem.problems"
  if [ "$mode" = fail ] && [ "$reported" -gt 5 ]; then
    fail "$tag: and $((reported - 5)) more cells of the table are not arrows of the diagram"
  fi
}

# The message of a defect of the comparison: the kind of the defect says
# what is wrong, and the words say it in one sentence.  A cell that the
# table of the machine names twice is not an absent cell: the generator
# reads the table, and the table says the same thing twice.
problem_message() {
  local tag="$1" kind="$2" from="$3" label="$4" to="$5" actual="$6" extra="$7"
  case "$kind" in
    absent)
      printf '%s\n' "$tag: the generator does not read the table: the cell ($from $label $to) is not in the diagram";;
    leads)
      printf '%s\n' "$tag: the generator reads the table but leads the cell elsewhere: the cell ($from $label $to) is drawn as ($actual)";;
    label)
      printf '%s\n' "$tag: the generator reads the table but leads the cell elsewhere: the cell ($from $label $to) is drawn as ($actual) and the label of the arrow is not the label of the cell";;
    count)
      printf '%s\n' "$tag: the diagram has $from arrows and the table of the transitions has $label cells";;
    twice)
      printf '%s\n' "$tag: the table of the machine names the same cell more than once: the cell ($from $label $to) is named $actual times and the diagram carries $(plural "$extra" arrow) for it, so the diagram does not carry every cell of the table";;
    twice-arrow)
      printf '%s\n' "$tag: the diagram carries the same arrow more than once: the arrow ($actual) is drawn $extra times and the cell ($from $label $to) is not in the diagram";;
  esac
}

# The number and the word: one arrow, two arrows.
plural() {
  if [ "$1" -eq 1 ]; then
    printf '%s %s' "$1" "$2"
  else
    printf '%s %ss' "$1" "$2"
  fi
}

emacs_bin="$(find_emacs_here)" || {
  echo "state-diagram: Emacs is not on this machine (the environment, the PATH, ~/.nix-profile, the store of nix): the diagram of the state machine was not measured" >&2
  exit 3
}

# --- 2. the file of the repository is the file the code writes ----------------

gen_dir="$tmp/gen"
make_tree "$gen_dir"
run_generator "$gen_dir" "$tmp/gen.log"
gen_rc=$?
if [ "$gen_rc" -ne 0 ]; then
  fail "the generation of the diagram answered $gen_rc and not 0"
  sed -n '1,8p' "$tmp/gen.log" >&2
else
  generated="$gen_dir/site/diagrams/state-machine.puml"
  if [ ! -s "$generated" ]; then
    fail "the generation of the diagram wrote no file"
  elif ! cmp -s "$generated" "$REPO/site/diagrams/state-machine.puml"; then
    fail "the diagram of the repository is not the diagram that the code writes: the table of the transitions changed and the diagram was not written again"
    if command -v diff >/dev/null 2>&1; then
      diff "$REPO/site/diagrams/state-machine.puml" "$generated" | sed -n '1,12p' >&2
    fi
  fi
fi

# --- 3. the generator reads the table of the transitions ----------------------

# A cell added to the table of the copy, and the counter of the table fixed:
# the module counts its cells when it loads, and a copy with a cell more and
# a counter of yesterday does not load at all.
cell_dir="$tmp/cell"
make_tree "$cell_dir"
cell_label="cell-of-the-check"
cell_file="$cell_dir/lib/yeah-loop.el"

cell_count="$(sed -n 's/^(unless (= \([0-9][0-9]*\) (length yeah-loop--raw-transitions)).*/\1/p' "$cell_file")"
if [ -z "$cell_count" ]; then
  fail "lib/yeah-loop.el does not count the cells of the table: the copy of the kernel cannot be changed"
else
  cell_count_new=$((cell_count + 1))
  sed -i "s/(unless (= $cell_count (length yeah-loop--raw-transitions)/(unless (= $cell_count_new (length yeah-loop--raw-transitions)/" "$cell_file"
  sed -i "s/expected $cell_count, got/expected $cell_count_new, got/" "$cell_file"
  awk -v label="$cell_label" '
    /^\(defconst yeah-loop--raw-transitions/ { in_table = 1 }
    in_table && !added && /\)\)[ \t]*$/ {
      print "     (idle             " label "      . deciding)"
      added = 1
      in_table = 0
    }
    { print }
  ' "$cell_file" >"$cell_file.new" || blocked "cannot make the tree of the check"
  mv "$cell_file.new" "$cell_file" || blocked "cannot make the tree of the check"
  if ! grep -q "$cell_label" "$cell_file"; then
    fail "the cell $cell_label did not come into the table of the copy of the kernel"
  fi
  run_generator "$cell_dir" "$tmp/cell.log"
  cell_rc=$?
  if [ "$cell_rc" -ne 0 ]; then
    fail "the generation of the diagram of the changed table answered $cell_rc and not 0"
    sed -n '1,8p' "$tmp/cell.log" >&2
  elif [ ! -s "$cell_dir/site/diagrams/state-machine.puml" ]; then
    fail "the generation of the diagram of the changed table wrote no file"
  else
    # Every cell of the changed table is an arrow of its diagram, and the
    # arrow of the new cell says what the new cell says.  The two kinds of
    # the defect are told apart: the new cell is not in the diagram at all
    # (the generator does not read the table), or it is there and it leads
    # somewhere else (the generator reads the table and writes the cell
    # wrong).
    compare_cells "$cell_dir/lib" "$cell_dir/site/diagrams/state-machine.puml" \
      "the diagram of the changed table"
  fi
fi

# --- 4. the generator reads the list of the states ----------------------------

# A state added to the list of the copy, and its metadata added with it: the
# module refuses to load a state it knows no metadata of.
state_dir="$tmp/state"
make_tree "$state_dir"
state_name="state-of-the-check"
state_file="$state_dir/lib/yeah-state.el"

awk -v state="$state_name" '
  /^\(defconst yeah-state-list/ { in_list = 1 }
  in_list && !added && /^[ \t]*[A-Za-z][A-Za-z0-9_-]*\)[ \t]*$/ {
    print "    " state
    added = 1
    in_list = 0
  }
  { print }
' "$state_file" >"$state_file.new" || blocked "cannot make the tree of the check"
mv "$state_file.new" "$state_file" || blocked "cannot make the tree of the check"

awk -v meta="  (puthash '$state_name'         '(:category :happy  :terminal nil) yeah-state--table)" '
  /^  \(puthash / && !added { print; print meta; added = 1; next }
  { print }
' "$state_file" >"$state_file.new" || blocked "cannot make the tree of the check"
mv "$state_file.new" "$state_file" || blocked "cannot make the tree of the check"

if ! grep -q "^    $state_name$" "$state_file"; then
  fail "the state $state_name did not come into the list of the copy of the kernel"
fi
run_generator "$state_dir" "$tmp/state.log"
state_rc=$?
if [ "$state_rc" -ne 0 ]; then
  fail "the generation of the diagram of the changed list of the states answered $state_rc and not 0"
  sed -n '1,8p' "$tmp/state.log" >&2
elif ! grep -q "$state_name" "$state_dir/site/diagrams/state-machine.puml"; then
  fail "the diagram of the changed list of the states has no $state_name: the generator does not read the list of the states"
fi

# --- 5. the diagram covers the machine ----------------------------------------

# The machine of the kernel, read out of the code: the names of the states
# and the cells of the table of the transitions.  The numbers are not written
# here.  The code is read out of the copy of the kernel of the check, and not
# out of the tree of the repository: a stale .elc of the tree would be the
# machine of yesterday.
machine_stem="$tmp/machine"
read_machine "$gen_dir/lib" "$machine_stem"
if [ ! -s "$machine_stem.raw" ]; then
  fail "the machine of the kernel could not be read out of the code"
else
  machine_states_count="$(wc -l <"$machine_stem.states" | tr -d ' ')"
  machine_state_names="$(tr '\n' ' ' <"$machine_stem.states")"

  diagram_file="$gen_dir/site/diagrams/state-machine.puml"
  if [ -s "$diagram_file" ]; then
    diagram_state_names="$(diagram_states "$diagram_file" | LC_ALL=C sort | tr '\n' ' ')"
    machine_state_names_sorted="$(printf '%s\n' $machine_state_names | LC_ALL=C sort | tr '\n' ' ')"
    if [ "$diagram_state_names" != "$machine_state_names_sorted" ]; then
      fail "the states of the diagram are [$diagram_state_names] and the states of the machine are [$machine_state_names_sorted]"
    fi
    diagram_states_count="$(diagram_states "$diagram_file" | wc -l | tr -d ' ')"
    if [ "$diagram_states_count" != "$machine_states_count" ]; then
      fail "the diagram has $diagram_states_count states and the machine has $machine_states_count"
    fi
    # Every cell of the table is an arrow of the diagram, and the arrow says
    # what the cell says: the count of the arrows is not the proof of that,
    # and the cells are compared one by one.
    compare_cells "$gen_dir/lib" "$diagram_file" "the diagram of the machine"
  fi
fi

# --- 5b. a cell that the table names twice is not an absent cell --------------

# The table of the machine names the same cell twice and the diagram carries
# one arrow for the two: the comparison must name the duplicate and must not
# call the cell an absent one.  The generator draws one arrow for every cell
# of the table, so the diagram of a table that names the same cell twice
# carries that arrow twice; a cell that the table names twice and the
# diagram carries once is a cell that the diagram does not carry, and the
# comparison says so with its own words.
#
# The tree of this control is a copy of the kernel whose table names the same
# cell twice, and the diagram of the repository is the diagram of the table
# without that cell twice: the diagram carries one arrow for the two cells of
# the table.  The comparison of that tree is read here, and it must name the
# duplicate and not an absent cell.  The diagram of the repository is the
# diagram here on purpose: the control must read the comparison and not the
# health of the generator.
dup_dir="$tmp/duplicate"
make_tree "$dup_dir"
dup_file="$dup_dir/lib/yeah-loop.el"

dup_count="$(sed -n 's/^(unless (= \([0-9][0-9]*\) (length yeah-loop--raw-transitions)).*/\1/p' "$dup_file")"
if [ -z "$dup_count" ]; then
  fail "lib/yeah-loop.el does not count the cells of the table: the copy of the kernel cannot be changed"
else
  dup_count_new=$((dup_count + 1))
  sed -i "s/(unless (= $dup_count (length yeah-loop--raw-transitions)/(unless (= $dup_count_new (length yeah-loop--raw-transitions)/" "$dup_file"
  sed -i "s/expected $dup_count, got/expected $dup_count_new, got/" "$dup_file"
  # The same cell of the table, once more: the table says one thing about
  # one event twice.
  awk '
    /\(deciding[ \t]+stream-end[ \t]+\. post-decide\)/ && !added { print; added = 1 }
    { print }
  ' "$dup_file" >"$dup_file.new" || blocked "cannot make the tree of the check"
  mv "$dup_file.new" "$dup_file" || blocked "cannot make the tree of the check"
  dup_rows="$(grep -cE '\(deciding[[:space:]]+stream-end[[:space:]]+\. post-decide\)' "$dup_file" || true)"
  if [ "$dup_rows" -ne 2 ]; then
    fail "the table of the copy does not name the same cell twice: the copy of the kernel cannot be changed"
  else
    dup_messages="$(compare_cells "$dup_dir/lib" "$REPO/site/diagrams/state-machine.puml" \
      "the cell that the table of the machine names twice" print)"
    if ! printf '%s\n' "$dup_messages" | grep -q "names the same cell more than once"; then
      fail "the comparison of the cells does not tell a duplicate from an absent cell: the cell that the table of the machine names twice must be named as a duplicate"
      printf '%s\n' "$dup_messages" | sed -n '1,5p' >&2
    fi
    if printf '%s\n' "$dup_messages" | grep -q "does not read the table: the cell (deciding stream-end post-decide)"; then
      fail "the comparison of the cells calls the cell that the table of the machine names twice an absent cell: a table that says the same thing twice is a machine that says one thing about one event twice"
      printf '%s\n' "$dup_messages" | sed -n '1,5p' >&2
    fi
  fi
fi

# --- 6. the pipeline writes the source and draws both themes ------------------

pipe_dir="$tmp/pipeline"
make_tree "$pipe_dir"
cp "$REPO/site/diagrams/palette-light.puml" "$REPO/site/diagrams/palette-dark.puml" \
  "$pipe_dir/site/diagrams/" || blocked "cannot make the tree of the check"

plantuml_bin="$(find_plantuml_here)" || {
  echo "state-diagram: PlantUML is not on this machine (the environment, the PATH, ~/.nix-profile, the store of nix): the themes of the diagram were not measured" >&2
  if [ "$failures" -ne 0 ]; then
    exit 1
  fi
  exit 3
}

(
  cd "$pipe_dir" || blocked "cannot enter the tree of the run"
  EMACS="$emacs_bin" PLANTUML="$plantuml_bin" bash scripts/dev diagrams
) >"$tmp/pipeline.log" 2>&1
pipeline_rc=$?
if [ "$pipeline_rc" -ne 0 ]; then
  fail "the pipeline of the diagrams answered $pipeline_rc and not 0"
  sed -n '1,8p' "$tmp/pipeline.log" >&2
fi

if [ ! -s "$pipe_dir/site/diagrams/state-machine.puml" ]; then
  fail "the pipeline wrote no source of the diagram of the state machine"
fi

for theme in light dark; do
  picture="$pipe_dir/site/assets/diagrams/state-machine-$theme.svg"
  if [ ! -s "$picture" ]; then
    fail "the picture of the state machine ($theme) is missing or empty"
    continue
  fi
  if grep -q 'Syntax Error' "$picture"; then
    fail "the picture of the state machine ($theme) is an error of PlantUML"
  fi
done

# --- 7. a tree without a kernel cannot generate the diagram --------------------

bare_dir="$tmp/bare"
mkdir -p "$bare_dir/lib" "$bare_dir/scripts" "$bare_dir/site/diagrams" || blocked "cannot make the tree of the check"
cp -R "$REPO/scripts/." "$bare_dir/scripts/" || blocked "cannot make the tree of the check"
(
  cd "$bare_dir" || blocked "cannot enter the tree of the run"
  EMACS="$emacs_bin" bash scripts/dev state-diagram
) >"$tmp/bare.log" 2>&1
bare_rc=$?
if [ "$bare_rc" -ne 3 ]; then
  fail "the generation answered $bare_rc in a tree without a kernel and the answer must be 3"
  sed -n '1,4p' "$tmp/bare.log" >&2
fi

# --- 7b. the pipeline of the diagrams in a tree without a kernel ---------------

# The pipeline of the diagrams ends with the answer of the generation that
# failed, and it draws nothing when the generation failed: the sources of an
# earlier run are in the tree here, and they are the sources of yesterday
# without a kernel to write the sources of today.
bare_pipe_dir="$tmp/bare-pipeline"
mkdir -p "$bare_pipe_dir/lib" "$bare_pipe_dir/scripts" "$bare_pipe_dir/site/diagrams" || blocked "cannot make the tree of the check"
cp -R "$REPO/scripts/." "$bare_pipe_dir/scripts/" || blocked "cannot make the tree of the check"
cp "$REPO"/site/diagrams/*.puml "$bare_pipe_dir/site/diagrams/" || blocked "cannot make the tree of the check"
(
  cd "$bare_pipe_dir" || blocked "cannot enter the tree of the run"
  EMACS="$emacs_bin" PLANTUML="$plantuml_bin" bash scripts/dev diagrams
) >"$tmp/bare-pipeline.log" 2>&1
bare_pipe_rc=$?
# The pictures that the pipeline drew, wherever in the tree they are: the
# promise is that nothing is drawn, and not that nothing is drawn in one
# directory.
bare_pipe_pictures="$(find "$bare_pipe_dir" -type f -name '*.svg' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$bare_pipe_rc" -ne 3 ]; then
  fail "the pipeline of the diagrams answered $bare_pipe_rc in a tree without a kernel and the answer must be 3: the answer of the generation that failed is the answer of the pipeline"
  sed -n '1,4p' "$tmp/bare-pipeline.log" >&2
fi
if [ "$bare_pipe_pictures" -ne 0 ]; then
  if [ "$bare_pipe_rc" -eq 3 ]; then
    fail "the pipeline of the diagrams answered 3 and drew $bare_pipe_pictures picture(s) in a tree without a kernel: nothing must be drawn when the generation failed"
  else
    fail "the pipeline of the diagrams drew $bare_pipe_pictures picture(s) in a tree without a kernel although the generation failed (the answer was $bare_pipe_rc): nothing must be drawn when the generation failed"
  fi
fi

# --- 8. the tree of the repository is not written ----------------------------

repo_sources_after="$(cd "$REPO/site/diagrams" && LC_ALL=C ls -A | LC_ALL=C sort | tr '\n' ' ')"
if [ "$repo_sources_after" != "$repo_sources_before" ]; then
  fail "the check wrote into the tree of the repository: [$repo_sources_after] and not [$repo_sources_before]"
fi
repo_pictures_after="$(cd "$REPO/site/assets/diagrams" && LC_ALL=C ls -A | LC_ALL=C sort | tr '\n' ' ')"
if [ "$repo_pictures_after" != "$repo_pictures_before" ]; then
  fail "the check drew into the tree of the repository: [$repo_pictures_after] and not [$repo_pictures_before]"
fi

# --- the end -------------------------------------------------------------------

cleanup
trap - EXIT
if [ -e "$tmp" ]; then
  echo "state-diagram: the temporary tree of the check is still there: $tmp" >&2
  exit 1
fi
exit "$failures"
