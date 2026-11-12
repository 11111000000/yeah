# Yeah — Emacs Agent Harness

> **Status: v0.1.0-alpha; a kernel prototype, not yet a usable product.**
> Read `docs/PLAN.md` for the current baseline and the road to a public
> alpha. `spec.json` and `./scripts/dev map` are the machine-checked source
> of truth; documentation never substitutes for that evidence.

> **Website:** <https://11111000000.github.io/yeah/> — the static site in
> `site/`, published by GitHub Pages on every push that touches it.

**Yeah** is an Emacs Lisp agent harness: the agent executes inside Emacs,
not inside a separate agent process with Emacs acting as a client. The model
is reached through **gptel**; tools are permissioned Elisp functions; session
history is an **append-only JSONL journal**.

The name is a recursive acronym — **Yeah**, Emacs Agent Harness — and the
**Y** stands for the Y-combinator, which expresses the long-term design:
bounded recursive delegation, self-inspection and a fixed point at which Yeah
can help develop and verify Yeah itself.

## Why Emacs

A shell-only agent sees files and process output. Yeah is designed to see the
actual programming environment:

- live buffers, including unsaved edits;
- Emacs documentation, source and introspection;
- buffer-native edits with modification-tick checks and native undo;
- Eglot/Flymake diagnostics, Magit, Org, project.el and TRAMP;
- reproducible Elisp checks through byte compilation and ERT;
- emacsclient as an explicit bridge between attached and service runtimes.

The target is a complete harness competitive with opencode and pi, with
additional Emacs-native capabilities. That parity is a goal to measure, not a
feature already claimed.

## What exists today

The repository contains 38 focused Elisp modules implementing pieces of the
kernel:

- a defined run state machine and model-turn orchestration;
- a typed tool registry and last-match permission rules;
- shared/exclusive scheduling with once-only settlement and structured tool
  failure handling;
- built-in file, guarded edit/write, async process/job, output artifact,
  introspection, Elisp-check and diagnostics tools;
- an append-only JSONL session store and typed event vocabulary;
- event-derived view models and session projections;
- undo boundaries, retries/timeouts, calibrated context and asynchronous
  compaction with pruning events and corrupt-tail recovery;
- queued human control with persistent pending inputs, steering, cancellation,
  completion nudges, whole-run deadlines and retry backoff, and the Plan
  and Build permission profiles;
- an interactive journal mode with `M-x yeah`, ask/steer/cancel/recover,
  withdrawal, diff review, Org export and `M-x yeah-doctor`;
- an ACP v1 agent over newline JSON-RPC on stdio, with real sessions, journal
  updates, streaming tool calls and cancellation;
- an MCP server publishing the read-only `emacs__*` surface, and an MCP client
  that imports the tools of a foreign server under a namespaced name;
- a run context that owns the session, the transport, the answerer and the
  rules of one run, and three placements: attached, service and batch;
- an emacsclient bridge to the live buffers of an attached Emacs, approved
  separately and off by default;
- agent presets read from files, and a delegation that runs a child for
  real: its own session, its own permissions, its own journal.

After Stage 7, byte compilation is clean and 240 ERT unit tests pass.
Direct canaries cover transport, scheduling, tool failures, real coding,
asynchronous compaction, product installation entry points, the wire
(real Emacs processes serving ACP and MCP over stdio), the placements
(the same task in three real processes, compared event by event) and the
journey of a person (ask, steer, quit, restart, withdraw, recover, cancel).  Frozen
math-coding v4 map/run/gate results are not treated as current evidence.
A real model (MiniMax-M2.7) finishes the Stage 1 coding task, and the
interactive path works against a live provider: the journal mode, the cancel,
the quit and the restart, the resume of the session, and the recovery of a
pending input.  The clean-Emacs install path is the only part of the alpha
release gate that is not yet network-tested.

## What is not finished

Do not infer a working product from the presence of a module:

- the stdio server answers one request at a time: a cancel that arrives while
  a prompt is running is read after that prompt reaches a terminal state;
- the ACP agent and the MCP server have never been driven by a third-party
  client or editor, and no live provider was involved in the wire checks;
- the bridge to the buffers of an attached Emacs was checked against a stub
  program, never against a live Emacs server;
- the delegation runs one child at a time: parallel children, a cheaper
  child model, the Org projection and the fixed-point demonstration are not
  implemented yet;
- global state and incomplete event correlation still limit concurrent runs;
- PTC is disabled by default and remains **experimental, not a security
  boundary**; its demonstrated higher-order-function bypasses are covered by
  regression tests, but no general isolation is claimed;
- bootstrap installation exists but has not been network-tested on a clean
  machine; the interactive UI path is verified against a live provider, and
  the clean-Emacs install path is the only part of the alpha release gate
  that is not yet network-tested.

The design also removes any assumption that a gptel hook is real merely
because a unit test names it: the adapter must be checked against pinned,
actual gptel contracts.

## Architecture and plan

Read in this order:

1. `docs/ARCHITECTURE.md` — the purpose, ten design decisions, component
   contracts, security model and non-goals;
2. `docs/PLAN.md` — eight detailed stages from the present prototype to 1.0,
   with work items, controls and exit criteria;
3. `docs/ENGINEERING.md` — dependency policy, infrastructure, libraries,
   process/buffer safety, testing and definition of done;
4. `ELISP_BEST_PRACTICES.md` — Elisp conventions and the trap log;
5. `spec.json` and `waves/*.json` — current machine-readable claims and
   historical work units.

The immediate sequence is:

```text
honesty and safety → coding tools → context/compaction → human control
→ installable interactive product → ACP/MCP → placements → delegation
```

The public alpha gate is a clean-Emacs installation followed by a real coding
task with approval, diff review, steering, cancellation and restart/resume.

## Installation

On Emacs 30.2 with `package-vc`:

```elisp
(require 'package-vc)
(package-vc-install "https://github.com/11111000000/yeah.git" nil nil 'yeah)
```

Then configure the gptel backend/model and key through your normal Emacs
mechanism, run `M-x yeah-doctor`, and start with `M-x yeah`.

A clean-Emacs bootstrap is also provided:

```sh
emacs -Q --batch -l install/yeah-bootstrap.el
```

It installs gptel from MELPA when needed and Yeah through package-vc.  This
path is intentionally not network-tested in CI; report any bootstrap failure
before treating installation as supported.

## Development commands

```sh
./scripts/dev help                  # subcommands
./scripts/dev byte-compile-all      # clean kernel compilation, no warnings
./scripts/dev ert tests/unit/*.el   # unit tests
./scripts/dev check tests/checks/*  # canaries bound to claims
./scripts/dev map                   # claims, states and uncovered surface
./scripts/dev run                   # execute checks and bind evidence
./scripts/dev gate                  # run, then map; exit code is the verdict
```

`scripts/dev` needs Emacs on `PATH` (or `EMACS`). Map/run/gate also need a
compatible math-coding binary on `PATH` or in `MATHC`. If the installed tool
does not support the CLI used by the script, the result is blocked — not pass.

Real provider tests exist separately and require environment credentials:

```sh
YEAH_TEST_KEY=... YEAH_TEST_MODEL=MiniMax-M2.7 \
  emacs -Q --batch -L /path/to/gptel -L lib -l tests/live/live-model-call.el
YEAH_TEST_KEY=... YEAH_TEST_MODEL=MiniMax-M2.7 \
  emacs -Q --batch -L /path/to/gptel -L lib -l tests/live/live-coding-task.el
```

The second one runs a real coding task against a real provider: the harness
reads the project, edits the file with a guarded edit, saves it, and the
project's test passes.  The model's reasoning is kept in the conversation by
default (`yeah-gptel-include-reasoning`), and named arguments and JSON
booleans are normalized at the tool boundary.

No key belongs in the repository, session log or documentation.

## Research

Reference clones of current Emacs agent projects are kept outside the source
tree in `../emacs-agents-research/`. The useful architectural findings are
summarized in `docs/ARCHITECTURE.md` §12. They are not runtime dependencies.

## Author

- **Petr Kosov** <p.b.kosov@yandex.ru>

## License

- **Apache-2.0** (see `LICENSE`, `NOTICE`)
