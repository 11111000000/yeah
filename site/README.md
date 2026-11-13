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
JavaScript only enables copy buttons, clipboard feedback and current-section
navigation; it does not reveal or generate content.

## Publication

`.github/workflows/pages.yml` deploys `site/` on every push to `main` that
touches `site/` or the workflow itself. The published address is
`https://11111000000.github.io/yeah/`.

To publish it by hand instead, point GitHub Pages at the `main` branch and
`/site` folder in the repository settings.

## Design: an Emacs frame, not a product template

The page has the anatomy of a dark Emacs frame: menu and system bars, named
buffers, a session example, a minibuffer, a light mode line and an echo area.
Sections use hard rules and fixed-pitch rhythm rather than cards, shadows,
rounded pills or gradients. The architecture is ASCII; the roadmap uses Org
status markers; status is presented through the language of `yeah-doctor`.

The session on the first screen is explicitly labelled **illustrative**. It is
not represented as a live connection or a browser-based Emacs. Typing effects,
fake prompts and global keyboard capture are deliberately absent.

### Typography

`--font-fixed` is the only font stack. It uses locally available fixed-pitch
fonts, matching Emacs' `fixed-pitch` face without downloading a web font.
Body copy, headings, labels and code share the same family; scale, weight and
colour establish hierarchy instead of a separate corporate display face.

### Colour tokens

Every colour value comes from the standard Emacs/X11 colour table. Semantic
aliases correspond to familiar faces and states rather than to marketing
surfaces.

| Role | Emacs colour name | Value |
|---|---|---|
| Deep background, echo area | black | `#000000` |
| Default buffer background | grey10 | `#1a1a1a` |
| Raised/menu background | grey15 | `#262626` |
| Selected background | grey20 | `#333333` |
| Rules | grey25 / grey35 | `#404040` / `#595959` |
| Comments, dim text | grey60 | `#999999` |
| Secondary text | grey65 / grey75 | `#a6a6a6` / `#bfbfbf` |
| Default foreground | grey90 | `#e6e6e6` |
| Keywords, Y mark | plum / thistle | `#dda0dd` / `#d8bfd8` |
| Types, links | light blue | `#add8e6` |
| Builtins, ASCII diagram | light steel blue | `#b0c4de` |
| Strings, success | pale green | `#98fb98` |
| Warnings, open work | khaki | `#f0e68c` |
| Errors, non-goals | salmon | `#fa8072` |
| Focus | aquamarine | `#7fffd4` |
| Text selection | dark slate blue | `#483d8b` |

Bright colours mark syntax and state. Status never depends on colour alone:
`PASS`/`OPEN`, `DONE`/`NEXT` and `+`/`!` carry the same information in text.
Focus indicators remain visible, and reduced-motion users get a static cursor.

## Assets

- `assets/logo.svg` — the Y: two inputs, a self-reference loop and recursion.
  The parenthesized `(yeah)` wordmark is HTML around this mark.
- `assets/favicon.svg` — the same mark between parentheses on a dark buffer.
- `assets/og.svg` — editable 1200×630 source for social preview.
- `assets/og.png` — checked-in rendered preview used by the metadata. No SVG
  renderer is needed to publish the site.

## Content discipline

The text comes from the repository's own documents and states the product at
the level its evidence supports. The public alpha gate and protocol limits stay
visible. Where the repository is unfinished, the site says so in **Status**.
When test counts change, update the site from an actual local run, not from
memory; a website claim is not itself evidence.
