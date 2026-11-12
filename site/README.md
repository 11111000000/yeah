# Yeah — the site

The static site for Yeah, published by GitHub Pages from this directory.
No build step, no framework, no dependencies: `index.html`, `styles.css`,
`script.js` and two SVG assets are the whole site.

## Preview

```sh
cd site && python3 -m http.server 8000
# then open http://127.0.0.1:8000/
```

Any static server works. The page is readable with JavaScript disabled — the
reveal animation is an enhancement guarded by a `js` class on `<html>`.

## Publication

`.github/workflows/pages.yml` builds and deploys `site/` on every push to
`main` that touches `site/` or the workflow itself. The published address is
`https://11111000000.github.io/yeah/`.

To publish it by hand instead, the repository settings have to point GitHub
Pages at the `main` branch with the `/site` folder as the publishing source.

## The design tokens

Every colour is a colour of the **standard Emacs theme**: the names come from
the colour table Emacs itself ships (`x-colors` in Emacs 30.2), and the values
are the RGB values Emacs resolves for those names. Nothing else was
invented — no hex from a palette generator, no gradient, no shadow colour
outside the list.

| Token            | Emacs colour name | Value     | Used for                    |
|------------------|-------------------|-----------|-----------------------------|
| `--c-white`      | white             | `#ffffff` | page background             |
| `--c-black`      | black             | `#000000` | text, footer background      |
| `--c-dimgray`    | DimGray           | `#696969` | secondary text              |
| `--c-grey30`     | grey30            | `#4d4d4d` | labels inside diagrams      |
| `--c-grey50`     | grey50            | `#7f7f7f` | muted marks, arrows         |
| `--c-grey85`     | grey85            | `#d9d9d9` | rules, borders               |
| `--c-grey90`     | grey90            | `#e6e6e6` | soft rules                  |
| `--c-grey93`     | grey93            | `#ededed` | reserved                    |
| `--c-grey96`     | grey96            | `#f5f5f5` | code blocks, soft surfaces   |
| `--c-aliceblue`  | alice blue        | `#f0f8ff` | tinted sections             |
| `--c-lavender`   | lavender          | `#e6e6fa` | diagram emphasis            |
| `--c-lavenderblush` | lavender blush | `#fff0f5` | journal emphasis            |
| `--c-thistle`    | thistle           | `#d8bfd8` | accent-soft, marker         |
| `--c-plum`       | plum              | `#dda0dd` | reserved                    |
| `--c-violetred4` | VioletRed4        | `#8b2252` | the accent                  |
| `--c-darkslateblue` | dark slate blue | `#483d8b` | secondary accent            |
| `--c-slateblue`  | SlateBlue         | `#6a5acd` | focus ring                  |

The semantic aliases (`--bg`, `--fg`, `--rule`, `--accent`, …) sit on top of
them, so a future dark theme only has to remap the aliases.

### Typography

The brief asked for the fonts to follow the same standard. Emacs has two
faces that matter: the fixed-pitch face and the variable-pitch one. The site
mirrors that pair:

- `--font-display` — the headline face. The stack starts with Optima and
  Futura, so the display face follows the geometric grotesque used by IMAX
  posters wherever those fonts are installed, and falls back to the system
  sans elsewhere.
- `--font-prose` — Charter / Iowan Old Style / Georgia: the variable-pitch
  reading face.
- `--font-mono` — the fixed-pitch face, used for code, labels and metadata,
  exactly like the `fixed-pitch` face in Emacs.

No web font is downloaded: the site loads no external resource at all.

## The logo

The mark in `assets/logo.svg` is deliberately simple: a **Y** whose arms end
in two filled nodes — the inputs — and whose junction is a closed loop — the
self-reference, the fixed point. The stem below the loop is the recursion.
It is drawn with the accent colour and nothing else, so it survives being
printed, inverted or scaled to a favicon.

The next iteration, which is not yet decided, is the **e-max** direction:
an *e* for Emacs and *Max* for the model, drawn as a cybernetic mark — a
loop feeding itself, an agent inside its own harness. Three sketches are
worth trying, in this order:

1. **The loop-e** — a lowercase `e` drawn as a single closed path that
   returns to its own starting point, so the crossbar of the `e` is the
   harness and the loop is the agent.
2. **The x-node** — `e` and `x` as two terminal nodes of a signal path,
   with the model as the node that reads the path rather than the one that
   writes it.
3. **The recursive mark** — the current `Y`, but with the junction loop
   replaced by a smaller `e`, so the Y-combinator and the agent share one
   glyph.

Keep them all inside the same rules as the current mark: one colour, thin
strokes, no gradients, legible at 16 pixels.

## Content discipline

The text on the site is taken from the repository's own documents and states
the product at the level the evidence supports. Where the repository is not
finished, the site says so in the **Status** section. When the numbers
change, the site changes with them — the ERT and canary counts in the
status block are copied from the last local run, not from memory.
