#!/usr/bin/env bash
# check-site-diagrams-current.sh — canary for the claim
# `the-diagram-on-the-site-is-current`.
#
# The claim promises that the pictures of the site are the pictures of the
# sources of the site: every diagram of the tree of `site/diagrams/' is
# drawn again, in both of its themes, and the picture that the render
# writes is compared with the picture that the site publishes in
# `site/assets/diagrams/'.
#
# The promise is measured in five parts:
#
#   1. the tree of the sources is walked whole: a diagram in a
#      subdirectory of `site/diagrams/' is a diagram of the tree, and the
#      two pictures of it keep the subdirectory in front of their name;
#   2. every diagram is drawn in both of its themes, with the skin of the
#      theme inside the diagram — a skin outside of `@startuml' is an
#      error of PlantUML, and a picture drawn without the skin of its
#      theme is not the picture of the site;
#   3. the comparison is a comparison of the picture and not of the bytes:
#      the two pictures are put into one canonical form first, and the
#      canonical form keeps the content of a picture and drops its noise
#      (the normalization is written out below);
#   4. the source of the diagram of the state machine is written out of
#      the code before anything is drawn: the picture of the site is
#      compared with the picture of the code, and not only with the
#      picture of the file that the code wrote once;
#   5. the comparison tells the noise of a picture from the content of it:
#      a picture that differs from another one by the order of its
#      attributes and by its whitespace is the same picture, and a picture
#      that differs by a colour, by a text or by the number of its
#      elements is a different picture.  A comparison that cannot tell
#      the two apart proves nothing, and the check says so.
#
# The normalization.  Both pictures are put into one canonical form
# before they are compared, and the canonical form is a line per tag and
# a line per text of the picture:
#
#   * the declaration of the file and every comment of it are dropped:
#     the `<!--SRC=[...]-->' of PlantUML is the metadata of the render
#     (the hash of the source that was drawn) and not a part of the
#     picture;
#   * the attributes of every tag are sorted by their names and are
#     written as `name="value"': the order in which the render wrote them
#     is not a part of the picture;
#   * the runs of whitespace of every value and of every text become one
#     space, and the ends of them are cut: the line breaks and the
#     indentation of the file are not a part of the picture;
#   * everything else is kept as it is: the name of every tag, the order
#     of the tags, the colours, the texts and the geometry.  A picture
#     that differs by any of these is a different picture.
#
# The tree of the repository is never written: the sources are copied into
# a temporary tree, the source of the state machine is written into that
# copy, the pictures are drawn into it, and the trap of this script
# removes it.
#
# The search for the instruments is the chain of the pipeline
# (`scripts/lib/tools.sh') and not a search of its own: a copy of the
# chain in two scripts is a copy that drifts apart, and the copy that
# drifts apart is the one that answers "the tool is not here" when the
# tool is.
#
# Exit codes: 0 — the pictures of the site are the pictures of their
# sources; 1 — a picture is not the picture of its source, or it is not
# there at all; 2 — the inputs are wrong (the tree of the sources is not
# there, or a source has no `@startuml'); 3 — the instrument is not on
# this machine, or it cannot draw (PlantUML, or Emacs for the source of
# the state machine).

set -u
LC_ALL=C
export LC_ALL

cd "$(dirname "$0")/../.." || exit 2

# --- 0. the inputs ----------------------------------------------------------

for needed in site/diagrams site/assets/diagrams; do
  [ -d "$needed" ] || {
    echo "site-diagrams: $needed is not there: the tree of the repository is not where we think" >&2
    exit 2
  }
done
for needed in \
  site/diagrams/palette-light.puml \
  site/diagrams/palette-dark.puml \
  site/diagrams/palette-light.d2 \
  site/diagrams/palette-dark.d2 \
  scripts/lib/tools.sh \
  lib/yeah-state.el \
  lib/yeah-loop.el \
  lib/yeah-state-diagram.el; do
  [ -f "$needed" ] || {
    echo "site-diagrams: $needed is not there: the tree of the repository is not where we think" >&2
    exit 2
  }
done

# --- 1. the instruments -----------------------------------------------------

# The chain of the search is the chain of the pipeline: `scripts/lib/tools.sh'
# is read and its function is called.  The home of the person is named
# before the chain is called: the chain reads it, and a check that stops
# on an unset variable of the environment is not a check.
HOME="${HOME:-/nonexistent}"
# shellcheck source=scripts/lib/tools.sh
. scripts/lib/tools.sh

plantuml_bin="$(find_tool PLANTUML plantuml "${NIX_STORE_DIR:-/nix/store}/*plantuml*/bin/plantuml")" || {
  echo "site-diagrams: PlantUML is not on this machine (the environment, the PATH, ~/.nix-profile, the store of nix): the pictures were not drawn" >&2
  exit 3
}
d2_bin="$(find_tool D2 d2 "${NIX_STORE_DIR:-/nix/store}/*d2-*/bin/d2")" || {
  echo "site-diagrams: D2 is not on this machine (the environment, the PATH, ~/.nix-profile, the store of nix): the pictures were not drawn" >&2
  exit 3
}
emacs_bin="$(find_tool EMACS emacs "${NIX_STORE_DIR:-/nix/store}/*emacs*/bin/emacs")" || {
  echo "site-diagrams: Emacs is not on this machine (the environment, the PATH, ~/.nix-profile, the store of nix): the source of the state machine cannot be written out of the code" >&2
  exit 3
}

# --- 2. the temporary tree --------------------------------------------------

tmp="$(mktemp -d "${TMPDIR:-/tmp}/yeah-site-diagrams.XXXXXX")" || {
  echo "site-diagrams: cannot make the temporary tree of the check" >&2
  exit 2
}

# The rm of the agent moves a directory to the trash: the tree of this check
# must be gone, and not in the trash.  The rm of the system removes it.
system_rm() {
  local found dir
  found="$(command -v rm 2>/dev/null || true)"
  case "$found" in
    */shims/*)
      for dir in /usr/bin /bin /run/current-system/sw/bin; do
        if [ -x "$dir/rm" ]; then
          printf '%s' "$dir/rm"
          return 0
        fi
      done
      ;;
  esac
  [ -n "$found" ] || return 1
  printf '%s' "$found"
}
rm_bin="$(system_rm || true)"
[ -n "$rm_bin" ] || rm_bin=rm

cleanup() {
  "$rm_bin" -rf "$tmp" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$tmp/site" "$tmp/lib" "$tmp/wrap" "$tmp/render" || {
  echo "site-diagrams: cannot make the temporary tree of the check" >&2
  exit 2
}

# --- 3. the canonical form of a picture --------------------------------------

cat >"$tmp/canon-svg.awk" <<'AWK'
# canon-svg.awk — the canonical form of a picture of PlantUML.
#
# The canonical form is a line per tag and a line per text of the picture.
# The noise of the picture is dropped (the declaration and the comments of
# the file, the order of the attributes of a tag, the whitespace of the
# values and of the texts), and the content of it is kept (the names of
# the tags, the order of the tags, the colours, the texts, the geometry).

{ body = body $0 "\n" }

# The end of a tag: the `>' that closes it and that is not inside a value.
function tag_end(s,   i, c, q, n) {
  n = length(s)
  q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") {
      if (c == q) q = ""
      continue
    }
    if (c == "\"" || c == "'") { q = c; continue }
    if (c == ">") return i
  }
  return 0
}

# The whitespace of a value or of a text: one space in the middle and
# nothing at the ends.
function canon_ws(s) {
  gsub(/[ \t\r\n]+/, " ", s)
  sub(/^ +/, "", s)
  sub(/ +$/, "", s)
  return s
}

# A tag with its attributes sorted by their names.  The name of a tag that
# closes another one keeps its slash: `</text>' and `</rect>' are two tags
# and not one.
function canon_tag(tag,   rest, name, closing, key, val, n, i, j, out) {
  sub(/>$/, "", tag)
  rest = tag
  sub(/^</, "", rest)
  closing = 0
  if (substr(rest, 1, 1) == "/") {
    closing = 1
    rest = substr(rest, 2)
  }
  if (match(rest, /^[A-Za-z_:][-A-Za-z0-9_:.]*/)) {
    name = substr(rest, RSTART, RLENGTH)
  } else {
    name = ""
  }
  rest = substr(rest, length(name) + 1)
  n = 0
  while (match(rest, /[A-Za-z_:][-A-Za-z0-9_:.]*[ \t\r\n]*=[ \t\r\n]*"[^"]*"/)) {
    key = substr(rest, RSTART, RLENGTH)
    sub(/[ \t\r\n]*=[ \t\r\n]*"[^"]*"/, "", key)
    val = substr(rest, RSTART, RLENGTH)
    sub(/^[^=]*=[ \t\r\n]*"/, "", val)
    sub(/"$/, "", val)
    n++
    attrs[n] = key
    values[n] = canon_ws(val)
    rest = substr(rest, RSTART + RLENGTH)
  }
  # The order of the attributes is not a part of the picture.
  for (i = 2; i <= n; i++) {
    key = attrs[i]
    val = values[i]
    j = i - 1
    while (j >= 1 && attrs[j] > key) {
      attrs[j + 1] = attrs[j]
      values[j + 1] = values[j]
      j--
    }
    attrs[j + 1] = key
    values[j + 1] = val
  }
  out = (closing ? "</" : "<") name
  for (i = 1; i <= n; i++) {
    out = out " " attrs[i] "=\"" values[i] "\""
  }
  if (rest ~ /\/[ \t\r\n]*$/) out = out "/"
  return out ">"
}

END {
  s = body
  out = ""
  while (length(s) > 0) {
    lt = index(s, "<")
    if (lt == 0) {
      t = canon_ws(s)
      if (t != "") out = out t "\n"
      break
    }
    if (lt > 1) {
      t = canon_ws(substr(s, 1, lt - 1))
      if (t != "") out = out t "\n"
    }
    # A comment is the metadata of the render and not a part of the
    # picture: the `<!--SRC=[...]-->' of PlantUML is dropped with it.
    if (substr(s, lt, 4) == "<!--") {
      e = index(s, "-->")
      if (e == 0) break
      s = substr(s, e + 3)
      continue
    }
    # The declaration of the file is not a part of the picture.
    if (substr(s, lt, 2) == "<?") {
      e = index(s, "?>")
      if (e == 0) break
      s = substr(s, e + 2)
      continue
    }
    e = tag_end(substr(s, lt))
    if (e == 0) {
      t = canon_ws(s)
      if (t != "") out = out t "\n"
      break
    }
    out = out canon_tag(substr(s, lt, e)) "\n"
    s = substr(s, lt + e)
  }
  printf "%s", out
}
AWK

cat >"$tmp/variant-svg.awk" <<'AWK'
# variant-svg.awk — a variant of a picture of PlantUML.
#
# The modes:
#   noise   — the same picture with the order of the attributes of every
#             tag turned about and with the whitespace of the file
#             changed: the picture is the same and the bytes are not;
#   colour  — the same picture with the first colour of it changed;
#   text    — the same picture with the first text of it changed;
#   element — the same picture without its first element.

{ body = body $0 "\n" }

function tag_end(s,   i, c, q, n) {
  n = length(s)
  q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") {
      if (c == q) q = ""
      continue
    }
    if (c == "\"" || c == "'") { q = c; continue }
    if (c == ">") return i
  }
  return 0
}

# The attributes of a tag, in the order in which they stand.
function attrs_of(tag,   rest, key, val, n) {
  sub(/>$/, "", tag)
  rest = substr(tag, 2)
  n = 0
  while (match(rest, /[A-Za-z_:][-A-Za-z0-9_:.]*[ \t\r\n]*=[ \t\r\n]*"[^"]*"/)) {
    key = substr(rest, RSTART, RLENGTH)
    sub(/[ \t\r\n]*=[ \t\r\n]*"[^"]*"/, "", key)
    val = substr(rest, RSTART, RLENGTH)
    sub(/^[^=]*=[ \t\r\n]*"/, "", val)
    sub(/"$/, "", val)
    n++
    attrs[n] = key
    values[n] = val
    rest = substr(rest, RSTART + RLENGTH)
  }
  return n
}

BEGIN {
  # The body of the picture is read in the rules above; the modes work on
  # it in the END, where it is whole.
}

END {
  if (mode == "colour") {
    if (match(body, /#[0-9A-Fa-f]{6}/)) {
      printf "%s", substr(body, 1, RSTART - 1) "#123456" substr(body, RSTART + RLENGTH)
    } else if (match(body, /#[0-9A-Fa-f]{3}/)) {
      printf "%s", substr(body, 1, RSTART - 1) "#123" substr(body, RSTART + RLENGTH)
    } else {
      printf "%s", body
    }
    exit
  }
  if (mode == "text") {
    # The first text that is not empty is changed.
    if (match(body, />[^<>]+</)) {
      inner = substr(body, RSTART + 1, RLENGTH - 2)
      printf "%s", substr(body, 1, RSTART) inner " (changed)" substr(body, RSTART + RLENGTH - 1)
    } else {
      printf "%s", body
    }
    exit
  }
  if (mode == "element") {
    # The first element that closes itself is dropped.
    if (match(body, /<[A-Za-z_:][-A-Za-z0-9_:.]*[^<>]*\/>/)) {
      printf "%s", substr(body, 1, RSTART - 1) substr(body, RSTART + RLENGTH)
    } else {
      printf "%s", body
    }
    exit
  }
  if (mode != "noise") {
    printf "%s", body
    exit
  }
  s = body
  out = ""
  while (length(s) > 0) {
    lt = index(s, "<")
    if (lt == 0) {
      out = out " " s " "
      break
    }
    if (lt > 1) out = out " " substr(s, 1, lt - 1) " "
    if (substr(s, lt, 4) == "<!--") {
      e = index(s, "-->")
      if (e == 0) break
      s = substr(s, e + 3)
      continue
    }
    e = tag_end(substr(s, lt))
    if (e == 0) break
    tag = substr(s, lt, e)
    n = attrs_of(tag)
    tagname = substr(tag, 2)
    closing = 0
    if (substr(tagname, 1, 1) == "/") {
      closing = 1
      tagname = substr(tagname, 2)
    }
    if (match(tagname, /^[A-Za-z_:][-A-Za-z0-9_:.]*/)) {
      tagname = substr(tagname, RSTART, RLENGTH)
    } else {
      tagname = ""
    }
    out = out "\n  <" (closing ? "/" : "") tagname
    for (i = n; i >= 1; i--) out = out " " attrs[i] "=\"" values[i] "\""
    if (tag ~ /\/>[ \t\r\n]*$/) out = out "/"
    out = out ">\n"
    s = substr(s, lt + e)
  }
  printf "%s", out
}
AWK

canon() {
  awk -f "$tmp/canon-svg.awk" "$1"
}

# The number of the lines in which two canonical forms differ.
diff_lines() {
  diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'
}

# --- 4. the source of the state machine -------------------------------------

# The sources of the pictures are copied into the temporary tree: the tree
# of the repository is never written.
cp -R site/diagrams "$tmp/site/diagrams" || {
  echo "site-diagrams: cannot copy the tree of the sources" >&2
  exit 2
}

# The three modules of the machine are the ones the diagram is written out
# of, and they are copied as well: the generator runs in the copy and
# reads the code of the copy.
for module in yeah-state.el yeah-loop.el yeah-state-diagram.el; do
  cp "lib/$module" "$tmp/lib/" || {
    echo "site-diagrams: cannot copy the kernel of the machine" >&2
    exit 2
  }
done

# The source of the diagram of the state machine is written out of the code
# into the copy of the tree: the picture of the site is compared with the
# picture of the code, and not only with the picture of the file that the
# code wrote once.
"$emacs_bin" -Q --batch -L "$tmp/lib" -l yeah-state-diagram \
  --eval '(yeah-state-diagram-print)' >"$tmp/site/diagrams/state-machine.puml" \
  2>"$tmp/emacs.log" || {
  echo "site-diagrams: the source of the state machine cannot be written out of the code: the picture of it was not measured" >&2
  sed -n '1,8p' "$tmp/emacs.log" >&2
  exit 3
}
if [ ! -s "$tmp/site/diagrams/state-machine.puml" ]; then
  echo "site-diagrams: the source of the state machine was written empty: the picture of it was not measured" >&2
  sed -n '1,8p' "$tmp/emacs.log" >&2
  exit 3
fi

# --- 5. the walk of the tree and the comparison -----------------------------

failures=0
diagrams=0
pictures=0
index=0

find "$tmp/site/diagrams" -type f -name '*.puml' | LC_ALL=C sort >"$tmp/sources" || {
  echo "site-diagrams: cannot read the tree of the sources" >&2
  exit 2
}

while IFS= read -r src; do
  [ -f "$src" ] || continue
  rel="${src#$tmp/site/diagrams/}"
  name="${rel%.puml}"
  base="$(basename "$rel" .puml)"
  # The skins of the themes are not diagrams of the site, and they are
  # skipped wherever they stand.
  case "$base" in
    palette-*) continue ;;
  esac
  # The source of the site, named as the reader of the site names it.
  site_src="site/diagrams/$rel"
  index=$((index + 1))
  if ! grep -q '^[[:space:]]*@startuml' "$src"; then
    echo "site-diagrams: $site_src has no @startuml line: the inputs are wrong" >&2
    exit 2
  fi
  for theme in light dark; do
    # The skin of the theme goes inside the diagram: a skin outside of
    # @startuml is an error of PlantUML.
    flat="$(printf '%s' "$name" | tr '/' '-')"
    wrapper="$tmp/wrap/$flat-$theme.puml"
    sed "/^[[:space:]]*@startuml/r $tmp/site/diagrams/palette-$theme.puml" "$src" >"$wrapper" || {
      echo "site-diagrams: cannot make the source of $site_src ($theme)" >&2
      exit 2
    }
    # Every source is drawn in a directory of its own: the pictures of two
    # sources do not lie on top of each other.
    out="$tmp/render/$index-$theme"
    mkdir -p "$out" || {
      echo "site-diagrams: cannot make the directory of the render" >&2
      exit 2
    }
    if ! "$plantuml_bin" -tsvg -o "$out" "$wrapper" >"$tmp/plantuml.log" 2>&1; then
      echo "site-diagrams: PlantUML cannot draw $site_src ($theme): the pictures were not drawn" >&2
      sed -n '1,8p' "$tmp/plantuml.log" >&2
      exit 3
    fi
    picture="$out/$flat-$theme.svg"
    if [ ! -s "$picture" ]; then
      # A diagram that names itself (`@startuml name') makes PlantUML
      # write the picture under the name of the diagram and not under the
      # name of the file.
      written=()
      for candidate in "$out"/*.svg; do
        [ -f "$candidate" ] || continue
        written+=("$candidate")
      done
      if [ "${#written[@]}" -eq 1 ]; then
        picture="${written[0]}"
      fi
    fi
    if [ ! -s "$picture" ]; then
      echo "site-diagrams: PlantUML wrote no picture for $site_src ($theme): the pictures were not drawn" >&2
      sed -n '1,8p' "$tmp/plantuml.log" >&2
      exit 3
    fi
    if grep -q 'Syntax Error' "$picture"; then
      echo "site-diagrams: the picture of $site_src ($theme) is an error of PlantUML" >&2
      failures=1
      continue
    fi
    # The picture of the site keeps the shape of the tree of the sources:
    # a picture in a subdirectory keeps the subdirectory in front of it.
    target="site/assets/diagrams/$name-$theme.svg"
    if [ ! -s "$target" ]; then
      echo "site-diagrams: the picture \`$target' is missing: it is not the picture of \`$site_src'" >&2
      failures=1
      continue
    fi
    canon "$picture" >"$tmp/canon-rendered" || {
      echo "site-diagrams: cannot read the picture of $site_src ($theme)" >&2
      exit 2
    }
    canon "$target" >"$tmp/canon-site" || {
      echo "site-diagrams: cannot read the picture $target" >&2
      exit 2
    }
    if ! cmp -s "$tmp/canon-rendered" "$tmp/canon-site"; then
      echo "site-diagrams: the picture \`$target' is not the picture of \`$site_src': it differs" >&2
      diff "$tmp/canon-rendered" "$tmp/canon-site" 2>/dev/null | sed -n '1,6p' >&2
      failures=1
      continue
    fi
    pictures=$((pictures + 1))
  done
  diagrams=$((diagrams + 1))
done <"$tmp/sources"

# The pictures of the diagrams of D2.  The render of D2 is
# deterministic: two renders of one source are one picture, byte for byte.
# The comparison is therefore the comparison of the bytes, and the
# normalization of the pictures of PlantUML does not touch it.
find "$tmp/site/diagrams" -type f -name '*.d2' | LC_ALL=C sort >"$tmp/sources-d2" || {
  echo "site-diagrams: cannot read the tree of the sources of D2" >&2
  exit 2
}

while IFS= read -r src; do
  [ -f "$src" ] || continue
  rel="${src#$tmp/site/diagrams/}"
  name="${rel%.d2}"
  base="$(basename "$rel" .d2)"
  case "$base" in
    palette-*) continue ;;
  esac
  site_src="site/diagrams/$rel"
  index=$((index + 1))
  for theme in light dark; do
    flat="$(printf '%s' "$name" | tr '/' '-')"
    # The palette of the theme goes before the picture: D2 reads the
    # variables and the styles of the theme before the shapes.
    wrapper="$tmp/wrap/$flat-$theme.d2"
    cat "$tmp/site/diagrams/palette-$theme.d2" "$src" >"$wrapper" || {
      echo "site-diagrams: cannot make the source of $site_src ($theme)" >&2
      exit 2
    }
    out="$tmp/render/$index-$theme"
    mkdir -p "$out" || {
      echo "site-diagrams: cannot make the directory of the render" >&2
      exit 2
    }
    picture="$out/$flat-$theme.svg"
    font_bin="$(find_dejavu_mono || true)"
    if [ -z "$font_bin" ]; then
      echo "site-diagrams: the font of the site (DejaVu Sans Mono) is not on this machine: the pictures of D2 would stand in another font" >&2
      exit 3
    fi
    if ! "$d2_bin" --font-regular="$font_bin" "$wrapper" "$picture" >"$tmp/d2.log" 2>&1; then
      echo "site-diagrams: D2 cannot draw $site_src ($theme): the pictures were not drawn" >&2
      sed -n '1,8p' "$tmp/d2.log" >&2
      exit 3
    fi
    if [ ! -s "$picture" ]; then
      echo "site-diagrams: D2 wrote no picture for $site_src ($theme): the pictures were not drawn" >&2
      sed -n '1,8p' "$tmp/d2.log" >&2
      exit 3
    fi
    target="site/assets/diagrams/$name-$theme.svg"
    if [ ! -s "$target" ]; then
      echo "site-diagrams: the picture \`$target` is missing: it is not the picture of \`$site_src`" >&2
      failures=1
      continue
    fi
    if ! cmp -s "$picture" "$target"; then
      echo "site-diagrams: the picture \`$target` is not the picture of \`$site_src`: it differs" >&2
      diff "$picture" "$target" 2>/dev/null | sed -n '1,6p' >&2
      failures=1
      continue
    fi
    pictures=$((pictures + 1))
  done
  diagrams=$((diagrams + 1))
done <"$tmp/sources-d2"

# --- 6. the stand of the normalization ---------------------------------------

# The normalization must drop the noise of a picture and must keep its
# content.  A comparison that cannot tell the two apart measures nothing,
# and the check says so instead of passing.
stand_picture="$tmp/render/1-light"
stand_source=""
for candidate in "$stand_picture"/*.svg; do
  [ -f "$candidate" ] || continue
  stand_source="$candidate"
  break
done
if [ -z "$stand_source" ]; then
  echo "site-diagrams: there is no picture to stand the normalization on: the normalization was not measured" >&2
  exit 3
fi

canon "$stand_source" >"$tmp/canon-stand"
noise_lines=0
colour_lines=0
text_lines=0
element_lines=0

awk -v mode=noise -f "$tmp/variant-svg.awk" "$stand_source" >"$tmp/stand-noise"
canon "$tmp/stand-noise" >"$tmp/canon-noise"
noise_lines="$(diff_lines "$tmp/canon-stand" "$tmp/canon-noise")"

awk -v mode=colour -f "$tmp/variant-svg.awk" "$stand_source" >"$tmp/stand-colour"
canon "$tmp/stand-colour" >"$tmp/canon-colour"
colour_lines="$(diff_lines "$tmp/canon-stand" "$tmp/canon-colour")"

awk -v mode=text -f "$tmp/variant-svg.awk" "$stand_source" >"$tmp/stand-text"
canon "$tmp/stand-text" >"$tmp/canon-text"
text_lines="$(diff_lines "$tmp/canon-stand" "$tmp/canon-text")"

awk -v mode=element -f "$tmp/variant-svg.awk" "$stand_source" >"$tmp/stand-element"
canon "$tmp/stand-element" >"$tmp/canon-element"
element_lines="$(diff_lines "$tmp/canon-stand" "$tmp/canon-element")"

if [ "$noise_lines" -ne 0 ]; then
  echo "site-diagrams: the normalization keeps the noise of a picture: the noise of a picture differs in $noise_lines line(s) and must differ in none" >&2
  failures=1
fi
if [ "$colour_lines" -eq 0 ]; then
  echo "site-diagrams: the normalization drops the colour of a picture: a picture with another colour is the same picture for it" >&2
  failures=1
fi
if [ "$text_lines" -eq 0 ]; then
  echo "site-diagrams: the normalization drops the text of a picture: a picture with another text is the same picture for it" >&2
  failures=1
fi
if [ "$element_lines" -eq 0 ]; then
  echo "site-diagrams: the normalization drops the elements of a picture: a picture with one element less is the same picture for it" >&2
  failures=1
fi

# --- 7. the verdict ---------------------------------------------------------

echo "site-diagrams: $diagrams diagram(s), $pictures picture(s) of $((diagrams * 2)) compared with the pictures of the site"
echo "site-diagrams: the normalization: the noise differs in $noise_lines line(s), the colour in $colour_lines, the text in $text_lines, the element in $element_lines"

if [ "$failures" -ne 0 ]; then
  exit 1
fi
exit 0
