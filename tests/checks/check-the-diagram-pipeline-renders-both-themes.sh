#!/usr/bin/env bash
# check-the-diagram-pipeline-renders-both-themes.sh — canary for the claim
# `the-diagram-pipeline-renders-both-themes`.
#
# The claim promises five things, and every one of them is measured here:
#
#   1. the pipeline finds PlantUML by itself: every step of the chain of the
#      search works alone — the variable of the environment, the command on
#      PATH, the binary of ~/.nix-profile/bin, the glob of the store of nix —
#      and not only the step that this machine happens to carry; and the chain
#      of the search lives in one place in `scripts/`: the pipeline reads it
#      from `scripts/lib/tools.sh`, calls it, and writes no step of the
#      search of a tool by itself; no other script of `scripts/` defines the
#      chain or carries a copy of its body, and a copy of the body that is
#      rewritten in other words is not seen — the searches of the checks
#      themselves are their own, by design;
#   2. the pipeline answers 3 when the instrument is not there at all;
#   3. every diagram of the tree is drawn in both themes: two pictures for
#      every diagram, and every picture comes from the whole of its own
#      source — every state of the source and every arrow of it is in the
#      picture, and a picture drawn from a part of a source is not a picture
#      of that source;
#   4. the pictures come from the skins of the site, and the colours of the
#      pictures are the tokens of the site — read from site/styles.css, and
#      not written here;
#   5. the pipeline answers 1 when PlantUML fails, and answers 1 too when
#      PlantUML writes no picture at all.
#
# The tree of the repository is never written: every run of the pipeline
# happens in a temporary tree, and the trap of this script removes it.
#
# The fixture carries the kernel: the pipeline writes the diagram of the
# state machine out of the code before it draws anything, and a tree
# without a kernel cannot be drawn at all.  Emacs is named with an
# absolute path, because the PATH of a hermetic run holds the shim of this
# check and nothing else.
#
# The search for PlantUML of this script is a chain of its own: the check
# must not lean on the code that it checks.  The promise of the claim is
# about the scripts of the tree and not about the checks: the checks carry
# their own search on purpose, and a check that leaned on the chain of the
# pipeline would prove nothing about the pipeline.
#
# The words of the report of the pipeline are not measured: the number of the
# pictures and the number of the diagrams are read from the tree, and a
# wording is not a promise.
#
# Exit codes: 0 — the promise holds; 1 — the pipeline broke its promise;
# 2 — the tree is not where we think; 3 — PlantUML is not on this machine.

set -u

failures=0
fail() {
  echo "diagrams: $1" >&2
  failures=1
}

# The check cannot answer: the tree is not where we think, or the tree of the
# check cannot be made.  The answer of a check that cannot answer is 2, and
# it says why.
blocked() {
  echo "diagrams: $1" >&2
  exit 2
}

cd "$(dirname "$0")/../.." || blocked "the tree of the repository is not where we think"
[ -d lib ] || blocked "lib/ is not there: the tree of the repository is not where we think"
[ -f scripts/dev ] || blocked "scripts/dev is not there: the tree of the repository is not where we think"
[ -f scripts/lib/tools.sh ] || blocked "scripts/lib/tools.sh is not there: the tree of the repository is not where we think"
[ -f site/styles.css ] || blocked "site/styles.css is not there: the tree of the repository is not where we think"

REPO="$(pwd)"

# The kernel of the fixture: the pipeline writes the diagram of the state
# machine out of the code before it draws anything, and a tree without a
# kernel cannot be drawn at all.  The three modules of the machine are the
# ones the diagram is written out of.
fixture_kernel() {
  local dir="$1" module
  mkdir -p "$dir/lib" || blocked "cannot make the tree of the check"
  for module in yeah-state.el yeah-loop.el yeah-state-diagram.el; do
    cp "$REPO/lib/$module" "$dir/lib/" || blocked "cannot make the tree of the check"
  done
}

# --- 0. the tools of the hermetic runs -----------------------------------------

tmp="$(mktemp -d "${TMPDIR:-/tmp}/yeah-diagram-pipeline.XXXXXX")" || blocked "cannot make the temporary tree of the check"
shim="$tmp/hermetic-bin"

# The rm of the agent moves a directory to the trash: the tree of this check
# must be gone, and not in the trash.  The shim of the tree holds the rm of
# the system, and it is the rm of the system that removes the tree.
cleanup() {
  if [ -x "$shim/rm" ]; then
    "$shim/rm" -rf "$tmp" 2>/dev/null || true
  else
    rm -rf "$tmp" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# The tools of the hermetic run are the tools of the system: the wrappers of
# the agent are not used (a wrapper of rm moves a directory to the trash, and
# the trap of the pipeline must delete and not archive).
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

mkdir -p "$shim" || blocked "cannot make the tree of the check"
for tool in bash dirname basename mktemp mkdir sed grep cat mv rm; do
  tool_path="$(system_tool "$tool" || true)"
  if [ -n "$tool_path" ]; then
    ln -sf "$tool_path" "$shim/$tool" || blocked "cannot make the tree of the check"
  fi
done

# The tool of the hermetic run is a path that cannot be run.  The directories
# that hold an executable plantuml leave the PATH, or the pipeline finds the
# instrument anyway.
plantuml_dirs=()
path_dirs=()
IFS=':' read -r -a path_dirs <<<"${PATH:-}"
for dir in "${path_dirs[@]+"${path_dirs[@]}"}"; do
  [ -n "$dir" ] || continue
  if [ -x "$dir/plantuml" ]; then
    plantuml_dirs+=("$dir")
  fi
done
if [ -x "${HOME:-}/.nix-profile/bin/plantuml" ]; then
  plantuml_dirs+=("${HOME:-}/.nix-profile/bin")
fi
store_root="${NIX_STORE_DIR:-/nix/store}"
for candidate in "$store_root"/*plantuml*/bin/plantuml; do
  if [ -x "$candidate" ]; then
    plantuml_dirs+=("$(dirname "$candidate")")
  fi
done

# Emacs is the instrument of the generation of the diagram of the state
# machine, and the pipeline draws that diagram with it.  The search of
# Emacs is a chain of its own, like the search of PlantUML: the check must
# not lean on the code that it checks.  The answer of a run is the path of
# Emacs and not the name of it, because the PATH of a hermetic run holds
# the shim of this check and nothing else.
emacs_bin=""
if [ -n "${EMACS:-}" ] && [ -x "${EMACS}" ]; then
  emacs_bin="$EMACS"
elif command -v emacs >/dev/null 2>&1; then
  emacs_bin="$(command -v emacs)"
elif [ -x "${HOME:-}/.nix-profile/bin/emacs" ]; then
  emacs_bin="${HOME}/.nix-profile/bin/emacs"
else
  for candidate in "$store_root"/*emacs*/bin/emacs; do
    if [ -x "$candidate" ]; then
      emacs_bin="$candidate"
      break
    fi
  done
fi

stripped_path=""
for dir in "${path_dirs[@]+"${path_dirs[@]}"}"; do
  [ -n "$dir" ] || continue
  skip=0
  for bad in "${plantuml_dirs[@]+"${plantuml_dirs[@]}"}"; do
    if [ "$bad" = "$dir" ]; then
      skip=1
      break
    fi
  done
  if [ "$skip" -eq 0 ]; then
    stripped_path="${stripped_path:+$stripped_path:}$dir"
  fi
done
if [ -z "$stripped_path" ]; then
  stripped_path="/usr/bin:/bin"
fi

mkdir -p "$tmp/home-empty" "$tmp/store-empty" || blocked "cannot make the tree of the check"

# --- 1. the chain of the search lives in one place -----------------------------

# The text says where the chain lives; the runs of the section 5 say that the
# pipeline uses that chain.  A copy of the chain in two scripts is a copy
# that drifts apart, and the copy that drifts is the one that answers "the
# tool is not here" when the tool is.
chain_file="scripts/lib/tools.sh"
if ! grep -q '^find_tool()' "$chain_file"; then
  fail "$chain_file does not define find_tool: the search of the pipeline has no one place to live"
fi

# The pipeline reads the chain from the place where it lives.  The line that
# reads it is a line of code: a comment that names the file is a mention of
# the file and not a reading of it.  A check that takes a mention for a
# reading takes a pipeline with no chain at all for a pipeline with one.
if ! grep -qE '^[[:space:]]*(\.|source)[[:space:]]+.*lib/tools\.sh' scripts/dev; then
  fail "scripts/dev does not read $chain_file: the pipeline does not use the chain of the search"
fi

# The pipeline calls the function of the chain: the search of the pipeline is
# the search of the chain and not a search of its own.
if ! grep -qE '^[[:space:]]*find_tool[[:space:]]' scripts/dev; then
  fail "scripts/dev does not call find_tool: the pipeline does not use the chain of the search"
fi

# The pipeline writes no step of the search of a tool by itself.  The steps
# of the chain are the steps of one search, and a search that the pipeline
# writes is a second place where the chain lives — a copy that is rewritten
# and not copied, and a copy that drifts apart is the one that answers "the
# tool is not here" when the tool is.
#
# The probe is a probe of the code and not a probe of the wording: the steps
# are words of code — the command on the PATH, the type of the shell, the
# binary of the user in the profile, the store of nix — and a copy of the
# chain that is written in other words carries them too.
#
# The mentions are not steps: a comment is a word about the code, the help
# of the wrapper is a text and not code, and the calls of find_tool are the
# chain itself.
cat >"$tmp/code-of.awk" <<'AWK'
# code-of.awk — the code of a shell file.
#
#   * a whole-line comment is a word about the code, and not code;
#   * the body of a here-document is a text, and not code;
#   * with strip_calls=1 the calls of find_tool are taken out: the call is
#     the chain itself, and not a search of a second place.
#
# The two runs of this program (with and without the calls) hold the same
# number of lines, and the line of one is the line of the other.
in_heredoc {
  if ($0 ~ "^[[:space:]]*" delim "[[:space:]]*$") in_heredoc = 0
  next
}
{
  line = $0
  stripped = line
  sub(/^[[:space:]]+/, "", stripped)
  if (stripped == "" || stripped ~ /^#/) next
  if (line ~ /<<</) next
  if (match(line, /[[:space:]]<<-?[[:space:]]*/)) {
    pre = substr(line, 1, RSTART - 1)
    rest = substr(line, RSTART + RLENGTH)
    if (pre !~ /["']/ && match(rest, /^["']?[A-Za-z_][A-Za-z0-9_]*["']?/)) {
      delim = substr(rest, 1, RLENGTH)
      gsub(/["']/, "", delim)
      if (substr(rest, RLENGTH + 1) ~ /^[[:space:]]*$/) {
        in_heredoc = 1
        next
      }
    }
  }
  if (strip_calls) {
    gsub(/find_tool([^A-Za-z0-9_][^;|&#]*)?/, "", line)
  }
  print line
}
AWK

pipeline_code="$tmp/pipeline-code"
pipeline_code_whole="$tmp/pipeline-code-whole"
awk -f "$tmp/code-of.awk" -v strip_calls=1 scripts/dev >"$pipeline_code" || blocked "cannot read the code of the pipeline"
awk -f "$tmp/code-of.awk" -v strip_calls=0 scripts/dev >"$pipeline_code_whole" || blocked "cannot read the code of the pipeline"

# The words of the steps: the command on the PATH, the type of the shell,
# the binary of the user in the profile and the store of nix.
steps_of_a_search='command[[:space:]]+-[vV]|type[[:space:]]+-[Pp]|which[[:space:]]+(emacs|plantuml|mathc)|\.nix-profile/bin|NIX_STORE_DIR|bin/(plantuml|emacs)'
own_steps="$(grep -oE "$steps_of_a_search" "$pipeline_code" 2>/dev/null | LC_ALL=C sort -u | tr '\n' ' ')"
if [ -n "$own_steps" ]; then
  own_line="$(grep -nE "$steps_of_a_search" "$pipeline_code" 2>/dev/null | head -n 1 | cut -d: -f1)"
  own_where="$(sed -n "${own_line}p" "$pipeline_code_whole" | sed 's/^[[:space:]]*//')"
  fail "scripts/dev writes a step of the search of a tool by itself [$own_steps] — the line: $own_where: the chain of the search lives in one place ($chain_file) and not in two"
fi

# The chain is defined in one place and under one name: no other file of the
# scripts defines find_tool.
chain_copies="$(grep -rl '^find_tool()' scripts/ 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')"
if [ "$chain_copies" != "$chain_file " ]; then
  fail "the chain of the search is defined in [$chain_copies] and not in one place: $chain_file"
fi

# The body of the chain of the search: the lines of the function without its
# head and without its tail, and without the whitespace that is not a
# meaning.  The name of the function is not a part of the body: a copy of the
# body under another name is a copy of the body, and the name of the copy
# does not tell it apart from the chain.
chain_body="$tmp/chain-body"
sed -n '/^[[:space:]]*find_tool[[:space:]]*()[[:space:]]*{/,/^[[:space:]]*}/p' "$chain_file" \
  | sed '1d;$d' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
  | grep -v '^$' >"$chain_body"
if [ ! -s "$chain_body" ]; then
  fail "the body of the chain of the search cannot be read in $chain_file: a copy of the chain cannot be looked for"
fi

# Every file of the scripts, in the order of the names.
script_files="$tmp/script-files"
grep -rl '' scripts/ 2>/dev/null | LC_ALL=C sort >"$script_files"

while read -r file; do
  [ -n "$file" ] || continue
  [ "$file" = "$chain_file" ] && continue

  # The lines of the file as the body of the chain is read: without the
  # whitespace that is not a meaning, and without the comments, which are
  # words about the code and not the code.
  normalized="$tmp/normalized-file"
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$file" | grep -v '^$' | grep -v '^#' >"$normalized"

  # The body of the chain is in this file: the copy of the body is a copy of
  # the search, and the copy of the search is the copy that drifts apart.
  if awk '
        FNR == NR { body[++nb] = $0; next }
        { line[++nf] = $0 }
        END {
          for (s = 1; s + nb - 1 <= nf; s++) {
            same = 1
            for (i = 1; i <= nb; i++) {
              if (line[s + i - 1] != body[i]) { same = 0; break }
            }
            if (same) { found = 1; break }
          }
          exit (found ? 0 : 1)
        }
      ' "$chain_body" "$normalized"; then
    fail "the body of the chain of the search is copied in $file: the chain lives in one place ($chain_file) and not in two"
    continue
  fi

  # The steps of the search are in this file: the probe of the command on the
  # PATH and the probe of the binary of the user in the profile are the steps
  # of the search of a tool, and a file that carries them searches for a tool
  # by itself.
  if grep -q 'command -v' "$normalized" && grep -qE '\-x[^#]*\.nix-profile/bin/' "$normalized"; then
    fail "the steps of the chain of the search are in $file: the chain lives in one place ($chain_file) and not in two"
  fi
done <"$script_files"

# --- 2. the skins of the repository are bound to the tokens of the site --------

light_palette="site/diagrams/palette-light.puml"
dark_palette="site/diagrams/palette-dark.puml"
site_css="site/styles.css"

if [ ! -f "$light_palette" ]; then
  fail "the palette of the light theme is missing: $light_palette"
fi
if [ ! -f "$dark_palette" ]; then
  fail "the palette of the dark theme is missing: $dark_palette"
fi

# A palette that is not there is a broken promise of the pipeline and not a
# machine that cannot answer: the verdict of the check is 1 and not 2.
if [ ! -f "$light_palette" ] || [ ! -f "$dark_palette" ]; then
  exit 1
fi

# The value of a token of a block of the CSS of the site.  The block is named
# by the head of it (`:root {` for the light theme, `[data-theme="dark"] {`
# for the dark one), the token by the name of the variable of the CSS.
css_token() {
  awk -v marker="$1" -v token="$2" '
    index($0, marker) == 1 { inside = 1 }
    inside && $0 ~ ("^[[:space:]]*" token "[[:space:]]*:") {
      value = $0
      sub(/^[^:]*:[[:space:]]*/, "", value)
      sub(/;.*$/, "", value)
      sub(/\/\*.*$/, "", value)
      gsub(/[[:space:]]/, "", value)
      print tolower(value)
      exit
    }
    inside && $0 ~ /^[[:space:]]*}/ { inside = 0 }
  ' "$site_css"
}

# The value of a property of a palette.
palette_value() {
  awk -v prop="$2" '
    $1 == "skinparam" && $2 == prop { print $3; exit }
  ' "$1"
}

lower() {
  printf '%s' "$1" | tr 'A-F' 'a-f'
}

# PlantUML reads one property per line: `skinparam name value` is three
# fields, and the value may be quoted and hold spaces
# (`skinparam defaultFontName "DejaVu Sans Mono"` is three fields too).
skinparam_offenders() {
  awk '
    /^[[:space:]]*skinparam[[:space:]]/ {
      rest = $0
      sub(/^[[:space:]]*skinparam[[:space:]]+/, "", rest)
      name = ""
      value = ""
      if (match(rest, /^[^[:space:]]+/)) {
        name = substr(rest, 1, RLENGTH)
        value = substr(rest, RLENGTH + 1)
        sub(/^[[:space:]]+/, "", value)
      }
      if (match(value, /^"[^"]*"/)) {
        tail = substr(value, RLENGTH + 1)
        gsub(/[[:space:]]/, "", tail)
        fields = (name == "" || tail != "") ? 4 : 3
      } else if (value == "") {
        fields = 2
      } else {
        n = split(value, words, /[[:space:]]+/)
        fields = (n == 1) ? 3 : 4
      }
      if (fields != 3) {
        printf "line %d has %d fields and not three: %s\n", FNR, fields, $0
      }
    }
  ' "$1"
}

for palette in "$light_palette" "$dark_palette"; do
  offenders="$(skinparam_offenders "$palette")"
  if [ -n "$offenders" ]; then
    fail "the palette $palette has a skinparam line that PlantUML cannot read: $offenders"
  fi
  if grep -q '@startuml' "$palette"; then
    fail "the palette $palette has an @startuml line: the skin of a theme goes inside a diagram, not around it"
  fi
done

# The palette of a theme is bound to the tokens of that theme: the property
# of the skin carries the value of the token of the CSS of the site.  The
# numbers of the colours are not written here: a number that drifts from the
# CSS is a colour of its own and not a token of the site.
bind_palette() {
  local palette="$1" block="$2" theme="$3"
  local prop token want got
  while read -r prop token; do
    [ -n "$prop" ] || continue
    want="$(css_token "$block" "$token")"
    got="$(palette_value "$palette" "$prop")"
    if [ -z "$want" ]; then
      fail "the token $token is not in the block $block of $site_css"
      continue
    fi
    if [ -z "$got" ]; then
      fail "the palette of the $theme theme has no property $prop"
      continue
    fi
    if [ "$(lower "$got")" != "$want" ]; then
      fail "the $prop of the palette of the $theme theme is $got and the token $token of the site is $want"
    fi
  done <<'PAIRS'
backgroundColor --face-default-bg
defaultFontColor --face-default-fg
packageBackgroundColor --face-fringe-bg
StateBorderColor --face-divider
ArrowColor --face-prose
PAIRS
}

bind_palette "$light_palette" ':root {' light
bind_palette "$dark_palette" '[data-theme="dark"] {' dark

# Every colour of a palette is a colour of the site: a palette does not
# invent a colour of its own.  This is about the palettes of the repository:
# the copies of the skins inside the fixture carry a marker of their own.
for palette in "$light_palette" "$dark_palette"; do
  for hex in $(grep -oiE '#[0-9a-f]{6}' "$palette" | tr 'A-F' 'a-f' | LC_ALL=C sort -u); do
    if ! grep -qiF -- "$hex" "$site_css"; then
      fail "the palette $palette carries the colour $hex and the site does not know it"
    fi
  done
done

# The palette of a theme does not carry the colours of the other theme.
for theme in light dark; do
  if [ "$theme" = light ]; then
    palette="$light_palette"
    other_block='[data-theme="dark"] {'
  else
    palette="$dark_palette"
    other_block=':root {'
  fi
  for token in --face-fringe-bg --face-divider --face-prose; do
    other="$(css_token "$other_block" "$token")"
    if [ -n "$other" ] && grep -qiF -- "$other" "$palette"; then
      fail "the palette of the $theme theme carries the colour $other of the token $token of the other theme"
    fi
  done
done

# --- 3. the instrument of this machine -----------------------------------------

# Emacs draws the source of the diagram of the state machine out of the
# code, and the pipeline draws that source.  A machine without Emacs cannot
# run the pipeline at all, and the answer of the check is then 3.
if [ -z "$emacs_bin" ]; then
  echo "diagrams: Emacs is not on this machine (the environment, the PATH, ~/.nix-profile, the store of nix): the pipeline was not measured" >&2
  if [ "$failures" -ne 0 ]; then
    exit 1
  fi
  exit 3
fi

# The chain of this script is a chain of its own: the pipeline must not be
# leaned on to find the instrument that draws the pictures.
plantuml_bin=""
if [ -n "${PLANTUML:-}" ] && [ -x "$PLANTUML" ]; then
  plantuml_bin="$PLANTUML"
elif command -v plantuml >/dev/null 2>&1; then
  plantuml_bin="$(command -v plantuml)"
elif [ -x "${HOME:-}/.nix-profile/bin/plantuml" ]; then
  plantuml_bin="${HOME:-}/.nix-profile/bin/plantuml"
else
  for candidate in "$store_root"/*plantuml*/bin/plantuml; do
    if [ -x "$candidate" ]; then
      plantuml_bin="$candidate"
      break
    fi
  done
fi

if [ -z "$plantuml_bin" ]; then
  echo "diagrams: PlantUML is not on this machine (the environment, the PATH, ~/.nix-profile, the store of nix): the drawing of the themes was not measured" >&2
  if [ "$failures" -ne 0 ]; then
    exit 1
  fi
  exit 3
fi

# --- 4. the runs of the pipeline ------------------------------------------------

# A run of the pipeline of the diagrams in a tree of our own.  The report is
# written to a log and is not read: the exit code and the tree are the
# promise, and a wording is not a promise.
#
# Emacs is named with its path: the pipeline writes the diagram of the state
# machine out of the code before it draws anything, and the PATH of a
# hermetic run holds the shim of this check and nothing else.
run_pipeline() {
  local dir="$1" log="$2"
  shift 2
  (
    cd "$dir" || blocked "cannot enter the tree of the run"
    env "$@" "EMACS=$emacs_bin" bash "$REPO/scripts/dev" diagrams
  ) >"$log" 2>&1
}

# The environment of a hermetic run: no home, no store of nix, and the tools
# of the shim.  Only the step of the chain that the run names can find the
# instrument.
base_env=( "HOME=$tmp/home-empty" "NIX_STORE_DIR=$tmp/store-empty" )

# A tree of one diagram, for a run of the chain of the search.
chain_fixture() {
  local dir="$1"
  mkdir -p "$dir/site/diagrams" || blocked "cannot make the tree of the check"
  cp "$light_palette" "$dark_palette" "$dir/site/diagrams/" || blocked "cannot make the tree of the check"
  fixture_kernel "$dir"
  cat >"$dir/site/diagrams/probe.puml" <<'PUML'
@startuml
state "probe-of-the-chain" as probe
probe --> probe : tick
@enduml
PUML
}

# The pictures a tree of diagrams must hold: two for every diagram of the
# tree of the sources, and nothing else.  The list is read from the tree of
# the sources, so it says two times the number of the diagrams without
# saying the number.  The diagram of the state machine is in that tree
# after the run: the pipeline writes it out of the code before it draws
# anything.
expected_pictures_of() {
  local dir="$1" src name
  for src in "$dir"/site/diagrams/*.puml; do
    [ -f "$src" ] || continue
    name="$(basename "$src" .puml)"
    case "$name" in
      palette-*) continue ;;
    esac
    printf '%s-dark.svg\n%s-light.svg\n' "$name" "$name"
  done | LC_ALL=C sort | tr '\n' ' '
}

# The pictures of a run of the chain: two for every diagram of the tree of
# the fixture, and nothing else.
assert_chain_pictures() {
  local dir="$1" step="$2"
  local pictures expected
  if [ ! -d "$dir/site/assets/diagrams" ]; then
    fail "the step $step of the chain of the search drew no picture at all"
    return
  fi
  expected="$(expected_pictures_of "$dir")"
  pictures="$(cd "$dir/site/assets/diagrams" && LC_ALL=C ls -A | LC_ALL=C sort | tr '\n' ' ')"
  if [ "$pictures" != "$expected" ]; then
    fail "the step $step of the chain of the search drew [$pictures] and not the two pictures of every diagram of the tree: $expected"
  fi
}

# --- 5. every step of the chain of the search works alone ----------------------

# (a) the step of the environment: PLANTUML names the instrument, and
# nowhere else can be found.
env_dir="$tmp/chain-env"
chain_fixture "$env_dir"
run_pipeline "$env_dir" "$tmp/chain-env.log" \
  "PLANTUML=$plantuml_bin" \
  "${base_env[@]}" \
  "PATH=$shim:$stripped_path"
chain_rc=$?
if [ "$chain_rc" -ne 0 ]; then
  fail "the step of the environment of the chain of the search answered $chain_rc and not 0"
  sed -n '1,8p' "$tmp/chain-env.log" >&2
else
  assert_chain_pictures "$env_dir" "of the environment"
fi

# (b) the step of the PATH: the command is on the PATH, and the environment
# does not name it.
path_dir="$tmp/chain-path"
mkdir -p "$tmp/path-bin" || blocked "cannot make the tree of the check"
ln -sf "$plantuml_bin" "$tmp/path-bin/plantuml" || blocked "cannot make the tree of the check"
chain_fixture "$path_dir"
run_pipeline "$path_dir" "$tmp/chain-path.log" \
  -u PLANTUML \
  "${base_env[@]}" \
  "PATH=$shim:$tmp/path-bin:$stripped_path"
chain_rc=$?
if [ "$chain_rc" -ne 0 ]; then
  fail "the step of the PATH of the chain of the search answered $chain_rc and not 0"
  sed -n '1,8p' "$tmp/chain-path.log" >&2
else
  assert_chain_pictures "$path_dir" "of the PATH"
fi

# (c) the step of the profile: the binary of the user in ~/.nix-profile/bin.
profile_dir="$tmp/chain-profile"
mkdir -p "$tmp/home-profile/.nix-profile/bin" || blocked "cannot make the tree of the check"
ln -sf "$plantuml_bin" "$tmp/home-profile/.nix-profile/bin/plantuml" || blocked "cannot make the tree of the check"
chain_fixture "$profile_dir"
run_pipeline "$profile_dir" "$tmp/chain-profile.log" \
  -u PLANTUML \
  "HOME=$tmp/home-profile" \
  "NIX_STORE_DIR=$tmp/store-empty" \
  "PATH=$shim:$stripped_path"
chain_rc=$?
if [ "$chain_rc" -ne 0 ]; then
  fail "the step of the profile of the chain of the search answered $chain_rc and not 0"
  sed -n '1,8p' "$tmp/chain-profile.log" >&2
else
  assert_chain_pictures "$profile_dir" "of the profile"
fi

# (d) the step of the store: the glob of the store of nix, which the caller
# names.
store_dir="$tmp/chain-store"
mkdir -p "$tmp/store/plantuml-1.2025.10/bin" || blocked "cannot make the tree of the check"
ln -sf "$plantuml_bin" "$tmp/store/plantuml-1.2025.10/bin/plantuml" || blocked "cannot make the tree of the check"
chain_fixture "$store_dir"
run_pipeline "$store_dir" "$tmp/chain-store.log" \
  -u PLANTUML \
  "HOME=$tmp/home-empty" \
  "NIX_STORE_DIR=$tmp/store" \
  "PATH=$shim:$stripped_path"
chain_rc=$?
if [ "$chain_rc" -ne 0 ]; then
  fail "the step of the store of the chain of the search answered $chain_rc and not 0"
  sed -n '1,8p' "$tmp/chain-store.log" >&2
else
  assert_chain_pictures "$store_dir" "of the store"
fi

# --- 6. the instrument is not there: the answer is 3, not 0 --------------------

missing_dir="$tmp/chain-missing"
chain_fixture "$missing_dir"
run_pipeline "$missing_dir" "$tmp/chain-missing.log" \
  "PLANTUML=$tmp/no-such-plantuml" \
  "${base_env[@]}" \
  "PATH=$shim:$stripped_path"
missing_rc=$?
if [ "$missing_rc" -ne 3 ]; then
  fail "the pipeline answered $missing_rc where PlantUML is not there and the answer must be 3"
  sed -n '1,8p' "$tmp/chain-missing.log" >&2
elif ! grep -qi 'plantuml' "$tmp/chain-missing.log"; then
  fail "the pipeline answered 3 but said nothing about plantuml on its stderr"
fi

# --- 7. the contract of the wrapper --------------------------------------------

unknown_log="$tmp/unknown.log"
bash "$REPO/scripts/dev" no-such-subcommand >"$unknown_log" 2>&1
unknown_rc=$?
if [ "$unknown_rc" -ne 2 ]; then
  fail "the wrapper answered $unknown_rc to an unknown subcommand and the answer must be 2"
fi

args_log="$tmp/args.log"
(
  cd "$tmp" || blocked "cannot enter the tree of the check"
  bash "$REPO/scripts/dev" diagrams probe.puml
) >"$args_log" 2>&1
args_rc=$?
if [ "$args_rc" -ne 2 ]; then
  fail "the pipeline answered $args_rc to an argument and the answer must be 2"
fi

# --- 8. every diagram, in both themes ------------------------------------------

main_dir="$tmp/main"
mkdir -p "$main_dir/site/diagrams" || blocked "cannot make the tree of the check"
cp "$light_palette" "$main_dir/site/diagrams/palette-light.puml" || blocked "cannot make the tree of the check"
cp "$dark_palette" "$main_dir/site/diagrams/palette-dark.puml" || blocked "cannot make the tree of the check"
fixture_kernel "$main_dir"

# The marker of the skin: a font name that is in the copy of the skin of the
# fixture and in no code of the pipeline.  A picture carries the font of the
# skin it was drawn with, so a pipeline that draws with a skin of its own
# leaves no marker in the picture.
skin_marker="YeahWave83MarkerFont"
printf 'skinparam defaultFontName "%s"\n' "$skin_marker" >>"$main_dir/site/diagrams/palette-light.puml"
printf 'skinparam defaultFontName "%s"\n' "$skin_marker" >>"$main_dir/site/diagrams/palette-dark.puml"

# Two diagrams with names of their own.  Every diagram carries a label that
# is in no other diagram: the label tells the picture of a diagram from the
# picture of the other diagram.
cat >"$main_dir/site/diagrams/alpha.puml" <<'PUML'
@startuml
state "label-of-alpha-only" as alpha
state "second-of-alpha" as alpha2
alpha --> alpha2 : tick
@enduml
PUML
cat >"$main_dir/site/diagrams/beta.puml" <<'PUML'
@startuml
state "label-of-beta-only" as beta
state "second-of-beta" as beta2
beta --> beta2 : tick
@enduml
PUML

# The label of a diagram: the text of the first state of the diagram.  A
# state of the diagram of the state machine carries its name as it is
# (`state idle'), and not in quotes.
diagram_label() {
  sed -n 's/^[[:space:]]*state[[:space:]]*"\([^"]*\)".*/\1/p; s/^[[:space:]]*state[[:space:]]*\([A-Za-z][A-Za-z0-9_]*\)[ \t]*$/\1/p' "$1" | head -n 1
}

# The labels of a source: the text of every state of it and the text of every
# arrow of it.  A picture that is drawn from its own source carries all of
# them: a picture that is drawn from a part of its source carries the part
# and not the whole, and such a picture is the picture of another diagram.
source_labels() {
  sed -n \
    -e 's/^[[:space:]]*state[[:space:]]*"\([^"]*\)".*/\1/p' \
    -e 's/^[[:space:]]*state[[:space:]]*\([A-Za-z][A-Za-z0-9_]*\)[ \t]*$/\1/p' \
    -e 's/^[^:]*-->[^:]*:[[:space:]]*\(.*\)$/\1/p' \
    "$1"
}

# The texts of a picture: the words that PlantUML wrote in it, one word per
# line.  A label of a source that is not among them is a label the picture
# does not carry, and the picture was not drawn from that source.
picture_texts() {
  tr '\n' ' ' <"$1" \
    | sed 's/<text[^>]*>/\n/g; s|</text>|\n|g' \
    | sed 's/<[^>]*>//g' \
    | sed 's/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#39;/'"'"'/g; s/&amp;/\&/g' \
    | grep -v '^[[:space:]]*$'
}

sources_before="$(cd "$main_dir/site/diagrams" && LC_ALL=C ls -A | LC_ALL=C sort | tr '\n' ' ')"

run_pipeline "$main_dir" "$tmp/main.log" \
  "PLANTUML=$plantuml_bin" \
  "${base_env[@]}" \
  "PATH=$shim:$stripped_path"
main_rc=$?
if [ "$main_rc" -ne 0 ]; then
  fail "the pipeline answered $main_rc where both themes of every diagram must be drawn and the answer must be 0"
  sed -n '1,8p' "$tmp/main.log" >&2
fi

# The tree of the sources keeps the sources of the fixture and the diagram
# that the pipeline wrote out of the code, and nothing else: the pipeline
# must not leave a file of its own next to them.
sources_after="$(cd "$main_dir/site/diagrams" && LC_ALL=C ls -A | LC_ALL=C sort | tr '\n' ' ')"
expected_sources="$(printf '%s\n' $sources_before state-machine.puml | LC_ALL=C sort | tr '\n' ' ')"
if [ "$sources_after" != "$expected_sources" ]; then
  fail "the tree of the sources holds [$sources_after] and not [$expected_sources]"
fi

# The diagrams of the tree, with their labels, and the pictures the tree must
# hold: two for every diagram, and nothing else.  The list is read from the
# tree of the sources, so it says two times the number of the diagrams
# without saying the number.  The tree of the sources is read after the run:
# the diagram of the state machine is in it, for the pipeline wrote it out
# of the code.
labels_file="$tmp/labels"
all_labels_file="$tmp/all-labels"
expected_file="$tmp/expected-pictures"
: >"$labels_file"
: >"$all_labels_file"
: >"$expected_file"
for src in "$main_dir"/site/diagrams/*.puml; do
  [ -f "$src" ] || continue
  name="$(basename "$src" .puml)"
  case "$name" in
    palette-*) continue ;;
  esac
  label="$(diagram_label "$src")"
  if [ -z "$label" ]; then
    fail "the diagram $name carries no label: the picture of it cannot be told from the picture of another diagram"
    continue
  fi
  printf '%s %s\n' "$name" "$label" >>"$labels_file"
  printf '%s %s\n' "$name" "$label" >>"$all_labels_file"
  # Every label of the source, and not only the first one: the picture of the
  # diagram is drawn from the whole of its source.
  source_labels "$src" | while read -r one_label; do
    [ -n "$one_label" ] || continue
    printf '%s %s\n' "$name" "$one_label" >>"$all_labels_file"
  done
  printf '%s-dark.svg\n%s-light.svg\n' "$name" "$name" >>"$expected_file"
done
expected_pictures="$(LC_ALL=C sort "$expected_file" | tr '\n' ' ')"

if [ ! -d "$main_dir/site/assets/diagrams" ]; then
  fail "the pipeline wrote no tree of pictures: site/assets/diagrams does not exist"
else
  pictures="$(cd "$main_dir/site/assets/diagrams" && LC_ALL=C ls -A | LC_ALL=C sort | tr '\n' ' ')"
  if [ "$pictures" != "$expected_pictures" ]; then
    fail "the pipeline drew [$pictures] and not two pictures for every diagram: $expected_pictures"
  fi
fi

# The colours of the pictures are the tokens of the site.  The tokens are
# read from the CSS of the site: a change of a token that the skin follows
# is not a failure of the pipeline.
light_background="$(css_token ':root {' --face-default-bg)"
dark_background="$(css_token '[data-theme="dark"] {' --face-default-bg)"
light_border="$(css_token ':root {' --face-divider)"
dark_border="$(css_token '[data-theme="dark"] {' --face-divider)"

while read -r name label; do
  for theme in light dark; do
    picture="$main_dir/site/assets/diagrams/$name-$theme.svg"
    if [ ! -s "$picture" ]; then
      fail "the picture of $name ($theme) is missing or empty"
      continue
    fi
    # The picture comes from its own source.
    if ! grep -qF -- "$label" "$picture"; then
      fail "the picture of $name ($theme) does not carry the label $label of its own source"
    fi
    # The picture comes from the whole of its own source: every state of the
    # source and every arrow of it is a text of the picture.  A picture that
    # is drawn from a part of its source is the picture of another diagram,
    # and the marker of its own label does not tell the two apart.
    texts="$(picture_texts "$picture")"
    while read -r src_name src_label; do
      [ "$src_name" = "$name" ] || continue
      if ! printf '%s\n' "$texts" | grep -qxF -- "$src_label"; then
        fail "the picture of $name ($theme) does not carry the label $src_label of its own source: the picture was drawn from a part of its source"
      fi
    done <"$all_labels_file"
    # ... and from no other source.
    while read -r other_name other_label; do
      [ "$other_name" != "$name" ] || continue
      if grep -qF -- "$other_label" "$picture"; then
        fail "the picture of $name ($theme) carries the label $other_label of the diagram $other_name"
      fi
    done <"$labels_file"
    # The picture comes from the skin of the file: the marker of the copy of
    # the skin of the fixture is in the picture.
    if ! grep -qF -- "$skin_marker" "$picture"; then
      fail "the picture of $name ($theme) does not carry the marker $skin_marker of the skin of the fixture: the picture was not drawn with the skin of the file"
    fi
    # The colours of the picture are the tokens of the site.
    if [ "$theme" = light ]; then
      background="$light_background"
      border="$light_border"
    else
      background="$dark_background"
      border="$dark_border"
    fi
    if [ -z "$background" ] || [ -z "$border" ]; then
      fail "the tokens of the site are not in $site_css: the colours of the pictures cannot be measured"
      continue
    fi
    if ! grep -qiF -- "background:$background" "$picture"; then
      fail "the picture of $name ($theme) does not carry the background $background of the site"
    fi
    if ! grep -qiF -- "stroke:$border" "$picture"; then
      fail "the picture of $name ($theme) does not carry the border $border of the site"
    fi
  done
  # The two themes of a diagram are two pictures and not one picture twice.
  light_picture="$main_dir/site/assets/diagrams/$name-light.svg"
  dark_picture="$main_dir/site/assets/diagrams/$name-dark.svg"
  if [ -s "$light_picture" ] && [ -s "$dark_picture" ]; then
    if cmp -s "$light_picture" "$dark_picture"; then
      fail "the light picture of $name and the dark picture of $name are the same picture"
    fi
  fi
done <"$labels_file"

# --- 9. the failures answer 1, not 0 -------------------------------------------

# A diagram that PlantUML cannot read: the pipeline must answer 1.
broken_dir="$tmp/broken"
mkdir -p "$broken_dir/site/diagrams" || blocked "cannot make the tree of the check"
fixture_kernel "$broken_dir"
cp "$light_palette" "$dark_palette" "$broken_dir/site/diagrams/" || blocked "cannot make the tree of the check"
cat >"$broken_dir/site/diagrams/broken.puml" <<'PUML'
@startuml
state "broken" as broken
broken --> > : this is not a diagram
@enduml
PUML
run_pipeline "$broken_dir" "$tmp/broken.log" \
  "PLANTUML=$plantuml_bin" \
  "${base_env[@]}" \
  "PATH=$shim:$stripped_path"
broken_rc=$?
if [ "$broken_rc" -ne 1 ]; then
  fail "the pipeline answered $broken_rc where PlantUML cannot read the diagram and the answer must be 1"
  sed -n '1,8p' "$tmp/broken.log" >&2
fi

# A PlantUML that writes no picture: the pipeline must answer 1.
fake_plantuml="$tmp/fake-plantuml"
printf '#!/bin/sh\nexit 0\n' >"$fake_plantuml" || blocked "cannot make the tree of the check"
chmod +x "$fake_plantuml" || blocked "cannot make the tree of the check"
quiet_dir="$tmp/quiet"
mkdir -p "$quiet_dir/site/diagrams" || blocked "cannot make the tree of the check"
fixture_kernel "$quiet_dir"
cp "$light_palette" "$dark_palette" "$quiet_dir/site/diagrams/" || blocked "cannot make the tree of the check"
cat >"$quiet_dir/site/diagrams/quiet.puml" <<'PUML'
@startuml
state "quiet" as quiet
@enduml
PUML
run_pipeline "$quiet_dir" "$tmp/quiet.log" \
  "PLANTUML=$fake_plantuml" \
  "${base_env[@]}" \
  "PATH=$shim:$stripped_path"
quiet_rc=$?
if [ "$quiet_rc" -ne 1 ]; then
  fail "the pipeline answered $quiet_rc where PlantUML writes no picture and the answer must be 1"
  sed -n '1,8p' "$tmp/quiet.log" >&2
fi

# A PlantUML that writes a picture that is an error of PlantUML, and answers
# 0: the third branch of the failure of the pipeline.  PlantUML itself
# answers 200 on a diagram it cannot read, so this branch needs a picture
# that is an error and a tool that is satisfied.
error_plantuml="$tmp/error-plantuml"
cat >"$error_plantuml" <<'FAKE'
#!/bin/sh
# A PlantUML that writes a picture that is an error of PlantUML, and answers 0.
out=""
src=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) src="$1"; shift ;;
  esac
done
name="${src##*/}"
name="${name%.puml}"
printf '<svg>Syntax Error</svg>\n' >"$out/$name.svg"
exit 0
FAKE
chmod +x "$error_plantuml" || blocked "cannot make the tree of the check"
error_dir="$tmp/error"
mkdir -p "$error_dir/site/diagrams" || blocked "cannot make the tree of the check"
fixture_kernel "$error_dir"
cp "$light_palette" "$dark_palette" "$error_dir/site/diagrams/" || blocked "cannot make the tree of the check"
cat >"$error_dir/site/diagrams/error.puml" <<'PUML'
@startuml
state "error" as error
@enduml
PUML
run_pipeline "$error_dir" "$tmp/error.log" \
  "PLANTUML=$error_plantuml" \
  "${base_env[@]}" \
  "PATH=$shim:$stripped_path"
error_rc=$?
if [ "$error_rc" -ne 1 ]; then
  fail "the pipeline answered $error_rc where the picture is an error of PlantUML and the answer must be 1"
  sed -n '1,8p' "$tmp/error.log" >&2
fi

# --- the end -------------------------------------------------------------------

cleanup
trap - EXIT
exit "$failures"
