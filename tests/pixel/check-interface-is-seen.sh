#!/usr/bin/env bash
# check-interface-is-seen.sh — a picture of the real interface.
#
# The interface is drawn in a terminal by Emacs itself, under a virtual frame
# server, and the screen is photographed with ImageMagick.  The check asserts
# that the picture of the interface holds more than one colour, that it
# differs from the picture of an empty buffer (the pixels come from the
# interface), and that the journal and the approval view are not the same
# screen.
#
# Nothing is compared against a stored picture: a stored picture fails on
# every machine whose fonts differ, and a check that fails for that reason
# teaches nobody anything.
#
# It needs a frame server, a terminal emulator, ImageMagick and Emacs:
#   YEAH_XVFB    path to Xvfb        (default: from PATH)
#   YEAH_XTERM   path to xterm       (default: from PATH)
#   YEAH_MAGICK  path to magick      (default: from PATH)
#   EMACS        path to Emacs       (default: emacs from PATH)

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" || exit 2

say() { printf 'check-interface-is-seen: %s\n' "$*"; }
blocked() { say "$*"; exit 2; }
failed() { say "$*"; exit 1; }

tool() {
  # Print the path of TOOL, honouring the override in the second argument.
  if [ -n "${2:-}" ] && [ -x "$2" ]; then
    printf '%s' "$2"
    return 0
  fi
  command -v "$1" 2>/dev/null
}

xvfb="$(tool Xvfb "${YEAH_XVFB:-}")" || blocked "Xvfb is not on PATH: it is the frame server the picture is taken from"
xterm="$(tool xterm "${YEAH_XTERM:-}")" || blocked "xterm is not on PATH: the interface is drawn in a terminal"
emacs_bin="${EMACS:-$(tool emacs "")}"
if [ -z "$emacs_bin" ] || [ ! -x "$emacs_bin" ]; then
  emacs_bin="$HOME/.nix-profile/bin/emacs"
fi
[ -x "$emacs_bin" ] || blocked "emacs is not on PATH and EMACS is not set"

if magick_bin="$(tool magick "${YEAH_MAGICK:-}")"; then
  capture() { "$magick_bin" import -window root -silent "$1"; }
  colours() { "$magick_bin" identify -format '%k' "$1"; }
  difference() { "$magick_bin" compare -metric AE "$1" "$2" null: 2>&1 | awk 'NR==1 {print $1}'; }
elif import_bin="$(tool import "${YEAH_MAGICK:-}")" &&
     identify_bin="$(tool identify "${YEAH_MAGICK:-}")" &&
     compare_bin="$(tool compare "${YEAH_MAGICK:-}")"; then
  capture() { "$import_bin" -window root -silent "$1"; }
  colours() { "$identify_bin" -format '%k' "$1"; }
  difference() { "$compare_bin" -metric AE "$1" "$2" null: 2>&1 | awk 'NR==1 {print $1}'; }
else
  blocked "ImageMagick is not on PATH: it photographs the screen and compares two pictures"
fi

artifacts="$root/tests/artifacts"
mkdir -p "$artifacts" || blocked "tests/artifacts cannot be created"
work="$(mktemp -d)" || blocked "a temporary directory cannot be created"

xvfb_pid=""
xterm_pid=""
cleanup() {
  [ -n "$xterm_pid" ] && kill -- "-$xterm_pid" 2>/dev/null
  [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# A display nobody uses: the socket of a dead server may still be there.
display=""
for candidate in 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85; do
  if [ ! -e "/tmp/.X11-unix/X$candidate" ]; then
    display=":$candidate"
    break
  fi
done
[ -n "$display" ] || blocked "no free display for the frame server"

"$xvfb" "$display" -screen 0 1280x800x24 -ac -nolisten tcp > "$work/xvfb.log" 2>&1 &
xvfb_pid=$!
for _ in $(seq 1 50); do
  kill -0 "$xvfb_pid" 2>/dev/null || blocked "the frame server did not start: $(tail -2 "$work/xvfb.log")"
  [ -e "/tmp/.X11-unix/X${display#:}" ] && break
  sleep 0.2
done
sleep 1

export DISPLAY="$display"
export XAUTHORITY="${XAUTHORITY:-/dev/null}"

take_picture() {
  # Take the picture of VIEW and write it to FILE.
  view="$1"
  file="$2"
  marker="$work/$view.ready"
  rm -f "$marker"
  YEAH_PIXEL_VIEW="$view" \
  YEAH_PIXEL_READY="$marker" \
  YEAH_PIXEL_HOLD=25 \
  setsid "$xterm" -geometry 110x36 -fa Monospace \
    -e "$emacs_bin" -nw -Q -L lib -L . -l tests/pixel/render-interface.el \
    > "$work/xterm-$view.log" 2>&1 &
  xterm_pid=$!
  for _ in $(seq 1 100); do
    [ -e "$marker" ] && break
    sleep 0.2
  done
  if [ ! -e "$marker" ]; then
    say "the view $view was never drawn: $(tail -3 "$work/xterm-$view.log")"
    return 1
  fi
  capture "$file" || return 1
  kill -- "-$xterm_pid" 2>/dev/null
  wait "$xterm_pid" 2>/dev/null
  xterm_pid=""
  return 0
}

journal="$artifacts/journal.png"
empty="$artifacts/empty.png"
approval="$artifacts/approval.png"

take_picture journal "$journal" || failed "the journal could not be photographed"
take_picture empty "$empty" || failed "the empty screen could not be photographed"
take_picture approval "$approval" || failed "the approval view could not be photographed"

for file in "$journal" "$empty" "$approval"; do
  [ -s "$file" ] || failed "the picture $file is empty"
done

count="$(colours "$journal")"
case "$count" in
  ''|*[!0-9]*) failed "the picture of the interface could not be read" ;;
esac
[ "$count" -gt 3 ] || failed "the picture of the interface holds $count colours: the screen is blank"

changed="$(difference "$journal" "$empty")"
case "$changed" in
  ''|*[!0-9]*) failed "the pictures could not be compared" ;;
esac
# The interface paints a screen full of text, not a heading: a renderer that
# draws nothing but its title must not pass this.
[ "$changed" -gt 2000 ] || failed "the interface does not change the screen: $changed pixels differ"

changed="$(difference "$journal" "$approval")"
case "$changed" in
  ''|*[!0-9]*) failed "the pictures could not be compared" ;;
esac
[ "$changed" -gt 150 ] || failed "the journal and the approval view look the same: $changed pixels differ"

say "the interface is on the screen: $count colours, $changed pixels between the journal and the approval view"
say "pictures: $artifacts"
exit 0
