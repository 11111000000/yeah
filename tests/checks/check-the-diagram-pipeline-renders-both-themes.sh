#!/usr/bin/env bash
# check-the-diagram-pipeline-renders-both-themes.sh — canary for the claim
# `the-diagram-pipeline-renders-both-themes`.
#
# The pipeline of the diagrams must find PlantUML by itself, answer 3 when
# the instrument is not there, and draw every diagram in both themes.
# The fixture is a temporary tree: the tree of the repository is never written.
# The search for PlantUML here is independent: not scripts/lib/tools.sh.
#
# Exit codes: 0 — both themes were drawn; 1 — the pipeline broke its promise;
# 2 — the tree is not where we think; 3 — PlantUML is not on this machine.

set -u

cd "$(dirname "$0")/../.." || exit 2
[ -d lib ] || exit 2
[ -f scripts/dev ] || exit 2

REPO="$(pwd)"

failures=0
fail() {
  echo "diagrams: $1" >&2
  failures=1
}

# --- 1. the palettes carry the colours of the site -----------------------------

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

if [ ! -f "$site_css" ]; then
  echo "diagrams: $site_css is not there: the colours of the palettes cannot be bound to the site" >&2
  exit 2
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
  if [ ! -f "$palette" ]; then
    continue
  fi
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
# invent a colour of its own.
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

# --- 2. the fixture: a temporary tree with the palettes and one probe ----------

tmp="$(mktemp -d "${TMPDIR:-/tmp}/yeah-diagram-pipeline.XXXXXX")" || exit 2
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

fixture="$tmp/fixture"
mkdir -p "$fixture/site/diagrams" || exit 2
cp "$light_palette" "$dark_palette" "$fixture/site/diagrams/" || exit 2
cat >"$fixture/site/diagrams/probe.puml" <<'PUML'
@startuml
state "deciding" as deciding
state "post-decide" as post
deciding --> post : tick
@enduml
PUML

# --- 3. the instrument is not there: the answer is 3, not 0 --------------------

# The tool of the hermetic run is a path that cannot be run.
# The directories that hold an executable plantuml leave the PATH, or the
# pipeline finds the instrument anyway.
plantuml_dirs=()
path_dirs=()
IFS=':' read -r -a path_dirs <<<"${PATH:-}"
for dir in "${path_dirs[@]+"${path_dirs[@]}"}"; do
  [ -n "$dir" ] || continue
  if [ -x "$dir/plantuml" ]; then
    plantuml_dirs+=("$dir")
  fi
done
if [ -x "$HOME/.nix-profile/bin/plantuml" ]; then
  plantuml_dirs+=("$HOME/.nix-profile/bin")
fi
store_dir="${NIX_STORE_DIR:-/nix/store}"
for candidate in "$store_dir"/*plantuml*/bin/plantuml; do
  if [ -x "$candidate" ]; then
    plantuml_dirs+=("$(dirname "$candidate")")
  fi
done

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

# The tools the pipeline runs are here, so that the PATH of the hermetic run
# can lose the directory of plantuml even when plantuml sits next to dirname
# (the wrappers of the agent are not used: a wrapper of rm moves a directory
# to the trash, and the trap of the pipeline must delete and not archive).
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

shim="$tmp/hermetic-bin"
mkdir -p "$shim" || exit 2
for tool in bash dirname mktemp mkdir sed grep cat mv rm; do
  tool_path="$(system_tool "$tool" || true)"
  if [ -n "$tool_path" ]; then
    ln -sf "$tool_path" "$shim/$tool" || exit 2
  fi
done

mkdir -p "$tmp/home-empty" "$tmp/store-empty" || exit 2
hermetic_log="$tmp/hermetic.log"
(
  cd "$fixture" || exit 2
  env PLANTUML="$tmp/no-such-plantuml" \
    HOME="$tmp/home-empty" \
    NIX_STORE_DIR="$tmp/store-empty" \
    PATH="$shim:$stripped_path" \
    bash "$REPO/scripts/dev" diagrams
) >"$hermetic_log" 2>&1
hermetic_rc=$?

if [ "$hermetic_rc" -ne 3 ]; then
  fail "the pipeline answered $hermetic_rc where PlantUML is not there and the answer must be 3"
  sed -n '1,8p' "$hermetic_log" >&2
elif ! grep -qi 'plantuml' "$hermetic_log"; then
  fail "the pipeline answered 3 but said nothing about plantuml on its stderr"
fi

# --- 4. the contract of the wrapper --------------------------------------------

unknown_log="$tmp/unknown.log"
bash "$REPO/scripts/dev" no-such-subcommand >"$unknown_log" 2>&1
unknown_rc=$?
if [ "$unknown_rc" -ne 2 ]; then
  fail "the wrapper answered $unknown_rc to an unknown subcommand and the answer must be 2"
fi

args_log="$tmp/args.log"
(
  cd "$fixture" || exit 2
  bash "$REPO/scripts/dev" diagrams probe.puml
) >"$args_log" 2>&1
args_rc=$?
if [ "$args_rc" -ne 2 ]; then
  fail "the pipeline answered $args_rc to an argument and the answer must be 2"
fi

# --- 5. both themes are drawn --------------------------------------------------

# The search for PlantUML here is a chain of its own: the check must not lean
# on the code that it checks.
plantuml_bin=""
if [ -n "${PLANTUML:-}" ] && [ -x "$PLANTUML" ]; then
  plantuml_bin="$PLANTUML"
elif command -v plantuml >/dev/null 2>&1; then
  plantuml_bin="$(command -v plantuml)"
elif [ -x "$HOME/.nix-profile/bin/plantuml" ]; then
  plantuml_bin="$HOME/.nix-profile/bin/plantuml"
else
  for candidate in "$store_dir"/*plantuml*/bin/plantuml; do
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

render_log="$tmp/render.log"
(
  cd "$fixture" || exit 2
  bash "$REPO/scripts/dev" diagrams
) >"$render_log" 2>&1
render_rc=$?
if [ "$render_rc" -ne 0 ]; then
  fail "the pipeline answered $render_rc where the probe of both themes must be drawn and the answer must be 0"
  sed -n '1,8p' "$render_log" >&2
fi
# The wording of the report is not the promise; the count of the pictures is.
if ! grep -qiE '(rendered|drew|written|wrote)[^0-9]*(2|two)[^0-9]*(picture|image|svg)' "$render_log"; then
  fail "the pipeline did not report that it drew two pictures of the probe: $(sed -n '1,3p' "$render_log")"
fi
if ! grep -qiE '(of|for)[^0-9]*(1|one)[^0-9]*diagram' "$render_log"; then
  fail "the pipeline did not report that it drew one diagram: $(sed -n '1,3p' "$render_log")"
fi

light_picture="$fixture/site/assets/diagrams/probe-light.svg"
dark_picture="$fixture/site/assets/diagrams/probe-dark.svg"

if [ ! -s "$light_picture" ]; then
  fail "the light picture of the probe is missing or empty"
fi
if [ ! -s "$dark_picture" ]; then
  fail "the dark picture of the probe is missing or empty"
fi

if [ -s "$light_picture" ] && [ -s "$dark_picture" ]; then
  if cmp -s "$light_picture" "$dark_picture"; then
    fail "the light picture of the probe and the dark picture of the probe are the same picture"
  fi
  if ! grep -qF 'background:#FFFFFF' "$light_picture"; then
    fail "the light picture of the probe does not carry the background #FFFFFF of the site"
  fi
  if ! grep -qF '#999999' "$light_picture"; then
    fail "the light picture of the probe does not carry the border #999999 of the site"
  fi
  if ! grep -qF 'background:#000000' "$dark_picture"; then
    fail "the dark picture of the probe does not carry the background #000000 of the site"
  fi
  if ! grep -qF '#646464' "$dark_picture"; then
    fail "the dark picture of the probe does not carry the border #646464 of the site"
  fi
fi

# The tree of the diagrams keeps the palettes and the probe, and nothing else:
# the pipeline must not leave a file of its own next to the sources.
sources="$(cd "$fixture/site/diagrams" && LC_ALL=C ls -A | LC_ALL=C sort | tr '\n' ' ')"
if [ "$sources" != "palette-dark.puml palette-light.puml probe.puml " ]; then
  fail "the tree of the diagrams kept something that is not a palette and not the probe: $sources"
fi

if [ ! -d "$fixture/site/assets/diagrams" ]; then
  fail "the pipeline wrote no tree of pictures: site/assets/diagrams does not exist"
else
  pictures="$(cd "$fixture/site/assets/diagrams" && LC_ALL=C ls -A | LC_ALL=C sort | tr '\n' ' ')"
  if [ "$pictures" != "probe-dark.svg probe-light.svg " ]; then
    fail "the tree of the pictures kept something that is not a picture of the probe: $pictures"
  fi
fi

# --- the end -------------------------------------------------------------------

cleanup
trap - EXIT
exit "$failures"
