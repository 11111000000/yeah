# The design of the Yeah site

The site is a GNU Emacs frame. This document says why, what the evidence was,
and what was decided — so that a later change can be made against reasons and
not against taste.

It was written on 2026-11-17, when the site was redrawn, and rewritten the same
day after the design was measured against the source of Emacs 30.2. The
previous design was a dark, "hacker" page: a plum-and-black palette,
monospace everywhere, a fake terminal header. It was competent and it was not
about Emacs.

The site is three files and a set of assets: `site/index.html`,
`site/styles.css`, `site/script.js`, `site/assets/`. `site/README.md` says how
to run and publish it.

## The question

What does a real Emacs look like, and what does that look like say about the
project? The answer had to come from Emacs itself — not from memory, and not
from a picture of somebody's dotfiles.

## The evidence

Emacs 30.2 was installed on this machine and was asked, rather than guessed.
The sources of the very same version were read as well, and the values that a
face resolves to were measured out of photographs of real frames.

```sh
E=/nix/store/bgfi11nshqcyrc6ppyrr6b4dq61a31wk-emacs-30.2/bin/emacs
$E -Q --batch --eval '(lookup-key global-map (kbd "C-x b"))'
```

### The face palette

The face specifications were read out of `lisp/faces.el` and `lisp/font-lock.el`
of `emacs-30.2`; the photographs of the real frame were decoded pixel by pixel
and sampled. The two agree, which is what makes them trustworthy.

| Part | Face | How known | Value |
|---|---|---|---|
| Mode line of the frame | `mode-line` | specified **and** sampled | black on `#bfbfbf` = grey75, with the released-button box |
| Mode line of an inactive window | `mode-line-inactive` | specified | grey20 on grey90 (`#e6e6e6`) |
| Header line | `header-line` | specified | grey20 on grey90 |
| Tab bar | `tab-bar` | specified | black on grey85 (`#d9d9d9`), inherits `variable-pitch` |
| Fringe | `fringe` | specified | grey95 (`#f2f2f2`) |
| Buffer | `default` | sampled | `#ffffff` on `#000000` |
| Menu bar and toolbar | window system | sampled | `#f6f5f4` |
| Scrollbar | window system | sampled | `#cecece` |

The mode line is worth one line of its own, because it is the part everybody
remembers wrong. The face is

```elisp
(defface mode-line
  '((t :box (:line-width -1 :style released-button)
      :background "grey75" :foreground "black"))
  "Mode line face.")
```

— **black on grey75**, not grey75 on black. The photograph of the running
GNU Emacs 30.2 agrees, row by row: the band of the mode line is `#bfbfbf`,
the glyphs inside it are `#000000`, the top edge of the box is `#e6e6e6` and
its bottom edge is `#737373` — the shadow of a released button.

The same band was sampled in photographs of GNU Emacs 25 and of GNU Emacs 27.1
on GNOME: `#bfbfbf` in all three. The mode line of a stock Emacs has been
grey75 under a black text for a long time, and the site follows it.

The font-lock faces were taken the same way: comments are Firebrick
(`#b22222`), strings VioletRed4 (`#8b2252`), keywords Purple (`#a020f0`),
builtins dark slate blue (`#483d8b`), function names Blue1 (`#0000ff`),
variables sienna (`#a0522d`), types ForestGreen (`#228b22`), constants dark
cyan (`#008b8b`). `link` is RoyalBlue3 (`#4169e1`) and underlined.

### The menu bar of Emacs 30.2

The menu bar of the real thing is **File, Edit, Options, Buffers, Tools,
Help**. That was established three times over, independently:

1. The installed Emacs was asked for its own menu bar:
   `(lookup-key global-map [menu-bar])` answers `Help File Edit Options
   Buffers Tools`.
2. The bindings were read out of `lisp/menu-bar.el` of `emacs-30.2`.
3. The photograph of the running GNU Emacs 30.2 was read by eye.

The menu bar of Emacs 28 and 29 had a **View** and a **Go** menu. Emacs 30
removed both: the commands of View live under **Options** (Search, Go To,
Replace, Incremental Search, Show/Hide), and the buffers live under
**Buffers**. The site took the menu bar of 30.2 and dropped the old ones
instead of keeping them as anachronisms.

The Buffers menu of Emacs lists the buffers of the frame and then the commands
that work on them; `lisp/menu-bar.el` names them:

```elisp
(defvar menu-bar-buffers-menu-command-entries
  '((next-buffer "Next Buffer")
    (previous-buffer "Previous Buffer")
    ("Select Named Buffer…" switch-to-buffer)
    ("List All Buffers" list-buffers)))
```

The site has the same shape: the twelve buffers of the frame, a separator, and
then `Next Buffer`, `Previous Buffer` and `Select Named Buffer…`.

### The tab bar is a mode, and a tab is a window configuration

Two facts about the tab bar are easy to get wrong and were wrong on the site
at first.

- **It is off by default.** A stock Emacs 30.2 answers `tab-bar-mode` with
  `nil`; `tab-bar-mode` is a minor mode with `:global t` and no `:init-value
  t`. The site turns it on — that is a decision of the site, not a property of
  Emacs.
- **A tab is a window configuration, not a buffer.** `lisp/tab-bar.el` says so
  in the docstring of the mode ("buttons that you can click to switch the
  frame between different window configurations"), and the label of a tab comes
  from `tab-bar-tab-name-function`, whose default is `tab-bar-tab-name-current`
  — the name of the buffer of the *selected window* of that configuration.

So a tab that shows the name of a buffer names the buffer of the window that
is selected in it. The site has one window per tab, which makes the reading
exact rather than approximate.

The `+` at the end of the strip is the button of Emacs (`tab-bar-new-button`,
whose label is `" + "`), and in Emacs it records one more window configuration.
The site cannot record a window configuration, so its `+` opens the Buffers
menu instead — the path by which a new buffer is really chosen. This is a
departure from Emacs, and it is named as one here and in the code.

### The prompts and the keys

The prompts are the ones of Emacs, not invented ones. The bindings were read
from the running Emacs (`lookup-key`), the prompts out of the sources.

| Key | Command | Prompt |
|---|---|---|
| `M-x` | `execute-extended-command` | `M-x `; a name that is not a command is refused with `‘nope’ is not a valid command name` |
| `C-s` | `isearch-forward` | `I-search: `, `failing I-search: `, and `1/4 I-search: ` when the count is on |
| `C-x b` | `switch-to-buffer` | `Switch to buffer: ` |
| `C-x 2` | `split-window-below` | — |
| `C-x C-f` | `find-file` | `Find file: ` |

`lisp/simple.el` holds the prompt `M-x ` of the extended command and the
refusal of a name that is not a command:
`(unless (commandp function) (error "`%s' is not a valid command name"))`.
The installed Emacs was asked for the wording of that error and answered
`‘nope’ is not a valid command name`; the message about a void function
belongs to the Elisp reader, not to `M-x`.
`lisp/isearch.el`
holds the prompt of the incremental search — `isearch-message-prefix` builds
`"I-search: "` and `"failing "`, and `lazy-count-prefix-format` is `"%s/%s "`,
which puts the number of the match and the number of the matches in front of
the prompt. `isearch-lazy-count` is `nil` by default and `isearch-lazy-highlight`
is `t`; the site shows the count anyway, because a count is what makes the
search legible on a page.

`lisp/window.el` holds the prompt of `switch-to-buffer`, and its capitalisation
is part of it: `"Switch to buffer: "`, with a small **b**. The site had
`Switch to Buffer: ` and was corrected.

The command that `C-x 2` is bound to is `split-window-below`; `split-window`
is the function underneath it, which takes an argument. The site had
`split-window` in its minibuffer and was corrected.

### The echo area is a window, not a row

The bottom row of the frame is not a terminal line with a cursor parked at the
end of it. In Emacs it is a **window of the frame** — the minibuffer window —
and the message is drawn in that window. `src/xdisp.c` says so in
`echo_area_display`:

```c
  mini_window = FRAME_MINIBUF_WINDOW (sf);
  ...
  if (!NILP (echo_area_buffer[0]) || minibuf_level == 0)
    {
      echo_area_window = mini_window;
      window_height_changed_p = display_echo_area (w);
```

The same file says that while the mini-window is selected, the echo area does
not show through it (`src/xdisp.c`, in `redisplay_internal`):

```c
	  && minibuf_level == 0
	  /* If the mini-window is currently selected, this means the
	     echo-area doesn't show through.  */
	  && !MINI_WINDOW_P (XWINDOW (selected_window)))
```

So the row belongs to the minibuffer while it reads, and to the message when
it does not. And `src/window.c` gives the window itself: `minibuffer-window`
returns "the minibuffer window for frame FRAME".

A window has a point, and Emacs shows the cursor in the selected window, at
that point. The point of the minibuffer is at the end of the text that was
typed, so the cursor stands **right after the text** — after `M-x `, after
`Switch to buffer: ` — and never at the far end of the row. The row is as wide
as the frame; the cursor is not.

The site had the input grow to fill the row and the block cursor pushed to the
far right of it. That is the drawing of a terminal line, and it is not what
Emacs does.

One thing the site does on its own: a stock Emacs leaves the area empty
between messages, and the area of the site rests on the command the frame is
ready for — `M-x yeah` — so that the reader sees where the frame stands and
so that the cursor has a place to stand. The prompt of the minibuffer (`M-x `)
comes back as soon as a command is asked for. That departure is named in
§ *The decisions*.

### Two facts that settled the direction

1. **There is no default theme file.** `custom-enabled-themes` is `nil` in a
   stock Emacs. The base faces *are* the default appearance, and that
   appearance is light: a white buffer, a grey mode line, a grey tab bar.
   The "Emacs look" that people remember is the light one.
2. **The dark theme Emacs ships is `modus-vivendi`,** and it is a real theme
   with a real palette: background black, mode line `#505050`, inactive mode
   line `#2d2d2d`, tab bar `#313131`, fringe `#1e1e1e`, link `#79a8ff`,
   keyword `#b6a0ff`, comment `#989898`.

So the site has both, and the light one is the default. A visitor who knows
Emacs sees the stock frame; a visitor who prefers dark gets `modus-vivendi`
from the Options menu, and the choice is remembered.

## What Emacs's design actually is

Reading the sources and looking at the photographs together gives a picture of
Emacs that the old site did not have.

**The frame is a machine of parts, not a page.** A real Emacs frame is a menu
bar, a tab bar of window configurations, a header line, one or more windows, a
mode line and an echo area. Each part has its own face and its own height. The
parts are not decoration around the text; they are the interface, and each of
them has a job. The site is built the same way: the parts are separate
elements with separate faces, and the text is inside them.

**Only the selected window is loud.** `mode-line` is black on grey75 with a
released-button box; `mode-line-inactive` is grey20 on grey90 and carries no
box. The frame shows one loud mode line and as many quiet ones as there are
other windows. The site has exactly one loud mode line — the one at the
bottom of the screen — and every section below it has the quiet variant.

**The mode line does not scroll away.** It is the one part of the frame that
is always in the same place, and it always says where you are: the position
in the buffer, the name of the buffer, the major mode, the time. The site
keeps it pinned to the bottom of the screen and lets it say the truth: the
section under the reader is the buffer, its mode is the mode, and the
position and the line number follow the scroll.

**Colour is a language, and it is sparse.** Emacs colours syntax, not
decoration: a comment is one colour, a keyword another, and the prose around
them is the default black. The site uses colour the same way — the `is` in
the heading is Purple because it is a keyword, a `;;` line is Firebrick
because it is a comment, and nothing else is coloured unless it means
something. A status is never carried by colour alone.

**Emacs has two typographic families.** The chrome and the code are
fixed-pitch; the prose of the Info manual and the welcome screen is
variable-pitch. `tab-bar` even inherits `variable-pitch` explicitly. The
site uses the same rule: fixed-pitch for the frame, the code and the labels;
proportional for the text the reader reads.

**The keyboard is the interface.** `M-x` opens the minibuffer, `C-s` searches,
`C-x b` switches buffers, `C-x 2` splits the frame. A frame that answers
these keys is a frame, whatever it is made of.

**The parts of Emacs that are modes are modes on the site too.** The tab bar
is off in a stock Emacs and on here; the minibuffer is a mode that comes and
goes with the commands that need it; the echo area carries the line of the
frame while the minibuffer is closed and the prompt of the minibuffer while
it is open. A website that draws all of these at once, always, would look
like a picture of Emacs rather than like Emacs.

**The cursor stands where the text ends.** The echo area of Emacs is a window
of the frame, and the cursor of a window stands at its point — at the end of
the text, not at the end of the row. The site keeps that rule: the cursor
waits right after `M-x yeah`, and when the minibuffer is open it stands at the
end of what was typed.

## The decisions

1. **The page is a frame, not a page styled like one.** There is no fake
   window chrome; the browser provides that. The frame begins at the menu bar
   and ends at the echo area.
2. **Light is the default** (§ *Two facts that settled the direction*).
3. **The menu bar is the one of Emacs 30.2:** File, Edit, Options, Buffers,
   Tools, Help — with the mnemonics of the real ones. The Buffers menu lists
   the buffers of the frame and the three commands that work on them.
4. **The tab bar is a mode the site turns on,** and a tab is a window
   configuration labelled by the buffer of its selected window. The site has
   one window per tab, so the reading of the label is exact.
5. **The `+` of the tab bar opens the Buffers menu,** because a website cannot
   record a window configuration and a tab that opens nothing would be a lie.
   The departure is deliberate and is named here and in the code.
6. **`C-x b` prompts,** with `Switch to buffer: ` and a completion on `Tab`,
   the way `switch-to-buffer` does; the Buffers menu is the clickable path.
7. **The bottom mode line is live; the mode lines of the sections are not.**
   They show the buffer and the mode of their window, in the quiet variant.
8. **The minibuffer is real.** It knows ten commands, completes with `Tab`,
   and refuses an unknown name the way Emacs refuses it:
   `‘nope’ is not a valid command name`.
9. **The incremental search is real.** `C-s` marks the matches, scrolls to
   the current one, and counts them with the format of Emacs:
   `1/4 I-search: `.
10. **The dark theme is `modus-vivendi`,** with its own palette, not an
    inversion of the light one. The choice lives in `localStorage` and
    survives a reload.
11. **The mode line is black on grey75,** with the released-button box — the
    face of Emacs 30.2 and the measured colour of three photographs.
12. **The mark is the Y that is the Y-combinator,** drawn as the lambda of
    Emacs Lisp. It is used as a mask, so it takes the colour of a keyword in
    whichever theme is in force.
13. **The prose has a colour of its own** (`--face-prose`): grey20 in the
    light theme, `fg-dim` in the dark one. The `shadow` face is grey50 and
    fails the 4.5:1 contrast on white; `shadow` is for shadows, not for
    text.
14. **The preview of the site says the name of the thing: `Yeah, Emacs
    Agent Harness`.** Yeah reads as Y, E-macs, A-gent, H-arness — a
    recursive acronym. The expansion of the name is the name; the
    Y-combinator is not the expansion and stays in the sentence that
    explains the Y. The title of the page, the title of the card and the
    card itself all carry that name, and the card carries the reading of
    it: `Y · E-macs · A-gent · H-arness — and the Y is the Y-combinator.`
    The image of the card is named by an absolute URL with a version
    query, because the social platforms cache a picture by its URL: when
    the card changes, the PNG is rendered again and the query is bumped.
15. **The cursor of the echo area stands where the text ends.** The echo
    area of Emacs is the minibuffer window of the frame (`src/xdisp.c`),
    and the cursor of a window stands at its point — after the text, not at
    the end of the row. The site had the cursor at the far right of the
    row; it waits right after `M-x yeah` now, and after the text that was
    typed when the minibuffer is open. The frame rests on the command it
    is ready for (`M-x yeah`); a stock Emacs leaves the area empty between
    messages, and that departure of the site is named here.
16. **The pictures of the architecture are diagrams, not ASCII.** The layer
    picture of the site is drawn as a diagram: the sources are PlantUML files
    and D2 files under `site/diagrams/`, the pictures are in
    `site/assets/diagrams/`, one
    picture for the light theme and one for the dark theme of the frame, and
    the ASCII figure that stood in the architecture section is gone. The engine
    is chosen per picture (the decision of the owner of 23 November): PlantUML
    draws the pictures of a process in the classic notation of UML, and D2 draws
    the pictures of a structure as bands. The tool is a tool of the author, not a
    dependency of the site: the site ships
    the pictures, and the page is readable with JavaScript disabled and
    without the tool. The colours of a diagram are the tokens of the frame —
    the background of a node is the background of a buffer, the arrow is the
    colour of the prose — and the accents come from the scale of font-lock.
    Colour never carries the meaning alone: the shape, the line and the name
    carry it too, every diagram has a caption, and every picture has a text
    alternative for a reader who does not see it. The palette, the tool and
    the placement are in `docs/SITE-DIAGRAMS-PLAN.md`.

## The verification

The design was checked in a real browser, not by reading the CSS. Chromium was
driven over the DevTools protocol against the site served from disk, and the
checks were: the anatomy of the frame, the menus and their contents and the
painted box of an open menu, the tab bar and its selection, the scroll spy, the
mode line, the minibuffer, the geometry of the echo area — where the cursor
has to start exactly where the text ends —, the buffer prompt with its
completion, the incremental search with its count, the keys, the themes and
their persistence, the layout at 420 and 1440 pixels, the console, the failed
requests, the focus ring and the contrast of every text role. The screenshots
were read back and looked at.

Seventeen defects were found and fixed: fifteen of them by the checks, and
two by a reader who looked at the site.

**The first round, six:**

- The scroll spy compared the id of a window with the target of a tab. The
  first tab aims at `#top` and the window is `#scratch`, so no tab was ever
  selected and the mode line of the frame named the wrong buffer. Tabs now
  name their buffer, and the mapping is checked in both directions.
- The tab that was selected called `scrollIntoView`, which moved the page as
  well and cancelled the scroll the reader was watching: a jump from the Go
  menu stopped after a few hundred pixels. Only the strip of tabs moves now.
- The same jump did not happen at all when the item was in a menu: the menu
  closed under the click, the browser found the link hidden, and it did not
  scroll. The menu now moves the frame itself.
- At the bottom of the page the last window could not reach the top of the
  viewport and was never selected.
- The prose was grey50 on white: 4.0:1, below the 4.5:1 of WCAG AA. It is
  grey20 now: 12.6:1.
- The mode line of the frame was wider than the frame, because the class
  that was meant to constrain it was never defined.

**The second round, nine, all of them found by reading the sources of Emacs
30.2 against the site, and by asking the installed Emacs for the answers:**

- **Every dropdown menu was invisible.** The menu bar carried
  `overflow-x: auto`, which computes to `overflow-y: auto` as well, and the
  dropdown was `position: absolute` inside the 29-pixel-high bar: it was
  clipped away and never painted. The menus worked when the script drove
  them, which is exactly how a check can pass and a reader can see nothing.
  The dropdown is `position: fixed` now and the script places it under its
  title; the check measures the box of the menu against the chrome of the
  frame, and the screenshot of the open menu was read back and looked at.
- **The menu bar was the one of Emacs 28 and 29** — File, Edit, View, Go,
  Search, Tools, Help — and not the one of 30.2. It was replaced by the six
  menus of the current frame, and the commands of View moved under Options
  and the buffers under Buffers.
- **The tab bar was called the list of open buffers.** It is the list of
  window configurations, labelled by the buffer of their selected window, and
  the mode is off by default in Emacs. Both the text of the site and the
  description of the strip were corrected.
- **The prompt of the incremental search said "Search".** The real one is
  `I-search: `, with `failing ` in front when nothing is found and the count
  of the matches in front of the prompt when the count is on.
- **`C-x b` opened a menu instead of prompting,** and `C-x 2` hid the chrome
  of the frame instead of showing the split. The keys were bound to the
  wrong commands.
- **The prose said the mode line was grey75 on black.** The face of Emacs
  30.2 and the pixels of three photographs say the opposite: black on grey75.
  The CSS was right and the prose was wrong.
- **The prompt of `switch-to-buffer` was "Switch to Buffer: ",** with a
  capital B. The source of Emacs 30.2 says `"Switch to buffer: "`.
- **The command bound to `C-x 2` was called `split-window`.** The command is
  `split-window-below`; `split-window` is the function beneath it, which
  takes an argument.
- **The refusal of an unknown command was the message of the Elisp reader.**
  The site said `Symbol's function definition is void: nope`, which is what
  the reader says when it is asked to evaluate a symbol that does not exist.
  `M-x` says something else: `lisp/simple.el` checks the name with
  `(unless (commandp function) (error "`%s' is not a valid command name"))`,
  and the installed Emacs 30.2 was asked for the exact wording:
  `‘nope’ is not a valid command name`. The site says that now.

**The third round, one, and it was not found by a check but by a reader:**

- **The preview of the site did not carry the name of the thing.** The title
  of the page and the title of the card said only `Yeah — The agent is
  Emacs`, so a card of the site said nothing about the name it is a card
  of. Worse, the card a reader sent showed an expansion the name never
  had: `Yeah — Y-combinator, Emacs Agent Harness`. That text is from the
  deploy of the 11th of November; the 12th already corrected it
  (`238073f`, "the name was expanded as 'Y-combinator, Emacs Agent
  Harness', which lost the recursion the name actually has"), and the
  redesign dropped the name from the title altogether. The social
  platforms cache a preview by its URL, so the wrong card outlived the
  deploy that fixed the text. The name is a recursive acronym — Yeah,
  Emacs Agent Harness — and the title, the card and the card's picture
  say it now, with the reading of it: `Y · E-macs · A-gent · H-arness —
  and the Y is the Y-combinator.` The picture of the card is named by an
  absolute URL with a version query, so that a new card is a new picture.

**The fourth round, one, and it was found by a reader as well:**

- **The cursor of the minibuffer blinked at the far end of the row,** a whole
  screen away from the text it belonged to. The echo area of Emacs is the
  minibuffer window of the frame, and the cursor of a window stands at its
  point — at the end of the text. The site drew the row like a terminal line:
  the input grew to fill it and the block cursor was pushed to its right end.
  The idle line was the placeholder of the input, and a placeholder cannot
  carry a cursor — it is a real element of the frame now, and the prompt, the
  command line and the cursor are one group. The cursor waits right after
  `M-x yeah`, and when the minibuffer is open the real caret of the browser
  stands at the end of what was typed.

## What is still open

- The icons of the window system are not drawn. The menu bar of a real
  Emacs on a desktop carries the icon of the frame; the site does not.
- The scroll bar of the frame is styled with CSS, not drawn.
- The page is checked in Chromium. It is written to the standards, and the
  layout rules are plain CSS, but no other browser was driven.
- The `+` of the tab bar does not record a window configuration. The Buffers
  menu takes its place, and the deviation is deliberate (§ *The decisions*).
- The mode line reports the scroll of the page as the position in the buffer.
  There is no point in a web page, so the line number and the percentage are
  the honest approximation of what Emacs shows.
- The diagrams of the site are drawn by the author with PlantUML and are
  shipped as pictures. A picture that goes out of date is not redrawn by the
  site itself; the check that keeps the pictures and the sources together
  lives in the repository, not in the page.

## The sources

Everything below was read, in this order, for this design.

**The installed Emacs 30.2, asked for its own answers:**

```sh
E=/nix/store/bgfi11nshqcyrc6ppyrr6b4dq61a31wk-emacs-30.2/bin/emacs
$E -Q --batch --eval '(lookup-key global-map [menu-bar])'
$E -Q --batch --eval '(dolist (v (list (quote tab-bar-mode) (quote custom-enabled-themes))) ...)'
$E -Q --batch --eval '(dolist (k (list "M-x" "C-s" "C-x b" "C-x 2" "C-x C-f")) ...)'
```

**The sources of the same version** — a sparse clone of the tag `emacs-30.2`
of the Emacs mirror (`lisp`, `etc/themes`, `src`):

- `lisp/faces.el` — the faces `mode-line`, `mode-line-inactive`,
  `header-line`, `tab-bar`, `fringe`.
- `lisp/font-lock.el` — the faces of the syntax.
- `lisp/tab-bar.el` — `tab-bar-mode`, `tab-bar-tab-name-function`,
  `tab-bar-tab-name-current`, `tab-bar-format-add-tab`,
  `tab-bar-new-button`.
- `lisp/menu-bar.el` — the bindings of the menu bar and
  `menu-bar-buffers-menu-command-entries`.
- `lisp/window.el` — `switch-to-buffer` and its prompt, `read-buffer-to-switch`,
  `next-buffer`, `previous-buffer`, `split-window-below`.
- `lisp/isearch.el` — `isearch-message-prefix`, `lazy-count-prefix-format`,
  `isearch-lazy-count`, `isearch-lazy-highlight`.
- `lisp/simple.el` — the prompt `M-x ` of the extended command.
- `lisp/minibuffer.el` — the minibuffer and its completion.
- `lisp/frame.el` — "multi-frame management independent of window systems".
- `src/keyboard.c` — `menu_bar_items` and `menu-bar-final-items`.
- `src/window.c` — `minibuffer-window`.
- `src/xdisp.c` — `echo_area_display`, `display_echo_area` and the line that
  says the echo area does not show through a selected mini-window.
- `etc/themes/modus-vivendi-theme.el` — the palette of the dark theme.

**The photographs of real frames,** decoded and sampled pixel by pixel:
`GNU Emacs 30.2.png`, `Screenshot of GNU Emacs 27.1 on GNOME.png` and
`GNU Emacs 25.png` from Wikimedia Commons.
