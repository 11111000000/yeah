# Yeah — the site

The static site for Yeah, published by GitHub Pages from this directory.
There is no build step, framework or runtime dependency: `index.html`,
`styles.css`, `script.js` and the checked-in assets are the whole site.

## Preview

```sh
cd site && python3 -m http.server 8000
# then open http://127.0.0.1:8000/
```

Any static server works. The page is readable with JavaScript disabled.
JavaScript only adds the behaviour of the frame: the menus, the tab bar, the
minibuffer, the incremental search, the live mode line and the theme. It does
not reveal or generate content.

## Publication

`.github/workflows/pages.yml` deploys `site/` on every push to `main` that
touches `site/` or the workflow itself. The published address is
`https://11111000000.github.io/yeah/`.

To publish it by hand instead, point GitHub Pages at the `main` branch and
`/site` folder in the repository settings.

## The preview of the site

The title of the page and the title of the social card are the name of the
thing: **Yeah, Emacs Agent Harness**. Yeah reads as Y, E-macs, A-gent,
H-arness — a recursive acronym. The Y-combinator is not the expansion of the
name; it belongs to the sentence that explains the Y (`;; The Y is the
Y-combinator.`), and it is there that it lives.

The card (`assets/og.png`) is fetched by the social platforms from its URL,
and they cache it there. The `og:image` and `twitter:image` therefore carry an
absolute URL with a version query (`?v=2`): **when the card changes, render
the PNG again and bump the query**, otherwise the old picture keeps being
served.

## Design: the default frame of GNU Emacs

The page is not a page styled to look like Emacs; it is a frame, with the
anatomy a stock Emacs 30.2 has:

| Part of the page | Part of Emacs |
|---|---|
| the menu bar with File/Edit/Options/Buffers/Tools/Help | the menu bar of Emacs 30.2 |
| the strip of tabs above the text | the tab bar (Tab Bar mode) |
| the grey line under the tab bar | the header line |
| the white area with the text | the buffer of a window |
| the narrow strip at the left of the text | the fringe |
| the grey75 bar at the bottom of the screen | the mode line of the frame |
| the line under it | the echo area, with the minibuffer in it |
| the grey bar under each section | the mode line of an inactive window |

The menu bar is the one of Emacs 30.2: `File`, `Edit`, `Options`, `Buffers`,
`Tools`, `Help`. The View and Go menus of Emacs 28 are gone — in 30 their
commands live under Options, and the buffers live under Buffers, which lists
the twelve buffers of the frame and then `Next Buffer`, `Previous Buffer` and
`Select Named Buffer…`.

The tab bar is a mode that a stock Emacs leaves off; the site turns it on. A
tab of Emacs is a *window configuration* and its label is the buffer of the
window that is selected in it, so one tab per window is the honest reading
of it.

The echo area is the window of the frame in which the message and the
minibuffer live, and its cursor stands where the text ends — right after
`M-x yeah` while the frame rests, and after what was typed while the
minibuffer is open. In Emacs the echo area *is* the minibuffer window of the
frame, and the cursor of a window stands at its point; the site had parked the
cursor at the far right of the row, which is not what Emacs does.

**The light theme is the default**, because a stock Emacs is light: a white
buffer, a grey75 mode line, a grey85 tab bar. The dark theme of the site is
`modus-vivendi`, the dark theme Emacs 30 ships, and it is offered in the Options
menu and in the button at the right of the menu bar. The choice is remembered.

Every colour is a face of Emacs 30.2; the reasoning and the measurements are in
[`../docs/SITE-DESIGN.md`](../docs/SITE-DESIGN.md).

Sections use hard rules and fixed-pitch rhythm rather than cards, shadows,
rounded pills or gradients. The architecture is ASCII; the roadmap uses Org
status markers; status is presented through the language of `yeah-doctor`.

The session on the first screen is explicitly labelled **illustrative**. It is
not represented as a live connection or a browser-based Emacs.

### The keys the frame answers

- `M-x` — the minibuffer, with the prompt `M-x `. It knows `yeah`,
  `yeah-doctor`, `open-file`, `find-file`, `switch-to-buffer`, `recenter`,
  `toggle-theme`, `split-window-below`, `toggle-frames` and `quit`; an unknown
  name is refused the way Emacs refuses it: `‘nope’ is not a valid command
  name`.
- `C-s` — incremental search in the buffer, with the prompt `I-search: ` and the
  count of the matches in front of it, `1/4 I-search: `. A search that finds
  nothing says `failing I-search: `. `Enter` keeps the match, `C-g` gives it up.
- `C-x b` — switch to buffer: the minibuffer asks `Switch to buffer: ` and
  `Tab` completes the name.
- `C-x 2` — split the frame: the two windows side by side. `C-x C-f` — find a
  file.

The keys work with the keyboard and with the mouse. Focus is always visible.

### Typography

Two families, as Emacs itself has: `--font-mono` (fixed-pitch) for the chrome,
the code and the labels, and `--font-proportional` (variable-pitch) for the
prose, the way the Info manual and the welcome screen set them. No web font is
downloaded. Scale, weight and colour establish the hierarchy.

### Colour tokens

Every colour value is the value of a face of Emacs 30.2. The light theme is
the default theme of a stock Emacs (the base faces, no theme loaded); the dark
theme is `modus-vivendi`.

| Role | Face | Light | Dark |
|---|---|---|---|
| Buffer background | `default` | `#ffffff` | `#000000` |
| Default text | `default` | `#000000` | `#ffffff` |
| Mode line of the frame | `mode-line` | `#bfbfbf` | `#505050` |
| Mode line of an inactive window | `mode-line-inactive` | `#e6e6e6` | `#2d2d2d` |
| Header line | `header-line` | `#e6e6e6` | `#1e1e1e` |
| Tab bar | `tab-bar` | `#d9d9d9` | `#313131` |
| Fringe | `fringe` | `#f2f2f2` | `#1e1e1e` |
| Prose | `mode-line-inactive` fg / `fg-dim` | `#333333` | `#989898` |
| Links | `link` | `#4169e1` | `#79a8ff` |
| Comments | `font-lock-comment-face` | `#b22222` | `#989898` |
| Keywords | `font-lock-keyword-face` | `#a020f0` | `#b6a0ff` |
| Builtins | `font-lock-builtin-face` | `#483d8b` | `#f78fe7` |
| Types | `font-lock-type-face` | `#228b22` | `#6ae4b9` |
| Errors | `error` | `#ff5f5f` | `#ff5f59` |
| Warnings | `warning` | `#ff8c00` | `#fec43f` |
| Success | `success` | `#228b22` | `#44bc44` |

Status never depends on colour alone: `PASS`/`OPEN`, `DONE`/`NEXT` and `+`/`!`
carry the same information in text. Focus indicators remain visible, the text
of the page keeps a contrast of at least 4.5:1 against its background, and
reduced-motion users get a static cursor.

## Assets

- `assets/logo.svg` — the mark: the Y that is the Y-combinator, drawn as the
  lambda of Emacs Lisp. The file is used as a mask, so the mark takes the
  colour of the face it stands for — a keyword is Purple in both themes.
  The parenthesized `(Yeah)` wordmark is HTML around this mark.
- `assets/favicon.svg` — the same mark on the white of a buffer, in the Purple
  of a keyword.
- `assets/og.svg` — editable 1200×630 source for the social preview.
- `assets/og.png` — the rendered preview used by the metadata. It is rendered
  from `og.svg`, so the two are the same picture; render it again whenever the
  SVG changes. No SVG renderer is needed to publish the site.

## Content discipline

The text comes from the repository's own documents and states the product at
the level its evidence supports. The public alpha gate and protocol limits stay
visible. Where the repository is unfinished, the site says so in **Status**.
When test counts change, update the site from an actual local run, not from
memory; a website claim is not itself evidence.
