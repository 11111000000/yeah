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
#   5. the diagram covers the machine: as many arrows as the table has
#      cells, and the states of the machine and no others — the numbers
#      are read out of the code and are not written here;
#   6. a tree without a kernel cannot generate the diagram, and the answer
#      of that is 3 and not 0;
#   7. the tree of the repository is never written: every run happens in a
#      temporary tree, and the trap of this script removes it.
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

# The arrows of a diagram: the cells of the table.  The arrow of the start
# of the machine carries no label and is not a cell.
diagram_arrows() {
  grep -c '^[^ ]* --> [^ ]* : ' "$1"
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
  elif ! grep -q "^idle --> deciding : $cell_label$" "$cell_dir/site/diagrams/state-machine.puml"; then
    fail "the diagram of the changed table has no arrow of the new cell: the generator does not read the table"
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

# The machine of the kernel, read out of the code: the number of the
# states, the number of the cells and the names of the states.  The
# numbers are not written here.  The code is read out of the copy of the
# kernel of the check, and not out of the tree of the repository: a stale
# .elc of the tree would be the machine of yesterday.
machine_facts="$("$emacs_bin" -Q --batch -L "$gen_dir/lib" --eval \
  '(progn (require (quote yeah-state)) (require (quote yeah-loop))
         (princ (format "%d %d %s"
                        (length yeah-state-list)
                        (length yeah-loop--raw-transitions)
                        (mapconcat (lambda (s) (symbol-name s)) yeah-state-list " "))))' \
  2>/dev/null)"
if [ -z "$machine_facts" ]; then
  fail "the machine of the kernel could not be read out of the code"
else
  machine_states_count="$(printf '%s' "$machine_facts" | awk '{print $1}')"
  machine_cells_count="$(printf '%s' "$machine_facts" | awk '{print $2}')"
  machine_state_names="$(printf '%s' "$machine_facts" | cut -d' ' -f3-)"

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
    diagram_arrows_count="$(diagram_arrows "$diagram_file")"
    if [ "$diagram_arrows_count" != "$machine_cells_count" ]; then
      fail "the diagram has $diagram_arrows_count arrows and the table of the transitions has $machine_cells_count cells"
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
