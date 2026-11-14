# Yeah — Emacs Agent Harness

> **Status: v0.1.0, the public alpha; a kernel, not yet a complete product.**
> Read `docs/PLAN.md` for the current baseline and the road to a public
> alpha. `spec.json` and `./scripts/dev map` are the machine-checked source
> of truth; documentation never substitutes for that evidence.

> **Website:** <https://11111000000.github.io/yeah/> — the static site in
> `site/`, published by GitHub Pages on every push that touches it.

**Yeah** is an Emacs Lisp agent harness: the agent executes inside Emacs,
not inside a separate agent process with Emacs acting as a client. The model
is reached through **gptel**; tools are permissioned Elisp functions; session
history is an **append-only JSONL journal**.

The primary deployment is a **service Emacs**: a dedicated Emacs process runs
the harness, because the editor Emacs is single-threaded and an in-editor
agent would block editing. The editor joins through the explicitly approved
emacsclient bridge; external clients and orchestrators speak ACP or MCP to
the same service Emacs. `M-x yeah` inside the user's own Emacs remains the
demo, development and fallback path.

The name is a recursive acronym — **Yeah**, Emacs Agent Harness — and the
**Y** stands for the Y-combinator, which expresses the long-term design:
bounded recursive delegation, self-inspection and a fixed point at which Yeah
can help develop and verify Yeah itself.

## Why Emacs

Emacs is not just an API surface: it is an environment people have already
invested in — decades of community packages, years of a person's own
configuration, and workflows built to fit their hands. A shell-only agent
starts from files and process output; Yeah is designed to start from that
inheritance. The harness is meant to turn the accumulated experience of the
environment into a better working experience than a harness that begins
from nothing.

The mechanism is direct access to the actual programming environment:

- live buffers, including unsaved edits;
- Emacs documentation, source and introspection (the user's own functions
  included);
- buffer-native edits with modification-tick checks and native undo;
- Flymake/Eglot diagnostics from the person's own LSP setup, and project.el
  for the session's project;
- reproducible Elisp checks through byte compilation and ERT;
- emacsclient as an explicit bridge between attached and service runtimes.

Magit, Org and TRAMP as agent capabilities are part of the target, not of
the verified present.

The service placement isolates the **thread**, not the **culture**: the
editing Emacs never waits for a long turn, while the model configuration,
the standing permissions and (through the bridge) the live buffers remain
the person's own.

The target is a complete harness competitive with opencode and pi, with
additional Emacs-native capabilities. That parity is a goal to measure, not a
feature already claimed.

## Placements

The same harness runs in three placements; all three write the same events
for the same task.

- **Service (primary).** A dedicated Emacs process owns the harness. The
  user's editor reaches it through the emacsclient bridge; external clients
  and orchestrators (agent-shell, Paseo) speak ACP or MCP to the same
  service Emacs. This is the deployment the product is aimed at, because the
  editing Emacs is single-threaded and an in-editor agent would block
  editing.
- **Attached (demo, development, fallback).** `M-x yeah` runs the harness
  inside the user's own Emacs. Useful for demos, development and light
  tasks; not the primary path, because a long agent turn shares the editor's
  single thread.
- **Batch (CI and benchmarks).** The harness runs headless for scripted
  checks and measurements, with no editor attached.

## What exists today

The repository contains 53 focused Elisp modules implementing pieces of the
kernel and its Emacs-native interface:

- a defined run state machine and model-turn orchestration;
- a typed tool registry and last-match permission rules;
- shared/exclusive scheduling with once-only settlement and structured tool
  failure handling;
- built-in file, guarded edit/write, async process/job, output artifact,
  introspection, Elisp-check, diagnostics, todo and git tools;
- an append-only JSONL session store and typed event vocabulary;
- event-derived view models and session projections;
- undo boundaries, retries/timeouts, calibrated context and asynchronous
  compaction with pruning events and corrupt-tail recovery;
- queued human control with persistent pending inputs, steering, cancellation,
  completion nudges, whole-run deadlines and retry backoff, and the Plan
  and Build permission profiles;
- completion supervision that tells the difference between a plan and a
  result: "I'll read the file" is nudged into the action (the nudge names
  the tools the run has not called yet), while "I fixed it, the test passes"
  ends the run; a run that is supervised ends through the `finish' tool,
  not through talk; and a model that answers while the harness is still
  waiting for a tool no longer breaks the state machine;
- a shared read-only journal for the attached and service placements: one
  event-derived view, incremental block updates that preserve the reading
  position, outline folding, semantic faces, optional `nerd-icons' with a
  permanent text fallback, and a separate multiline composer with bounded
  in-memory history and explicit file/buffer context;
- `M-x yeah' with ask/steer/cancel/recover, withdrawal, diff review, Org
  export and `M-x yeah-doctor';
- tested interaction components for read-only Edit/Write previews, an
  approval view, Doctor diagnostics and a session list;
- an ACP v1 agent over newline JSON-RPC on stdio, with real sessions, journal
  updates, streaming tool calls and cancellation — and over a local socket,
  where a cancel is handled while the prompt is still running;
- an MCP server publishing the read-only `emacs__*` surface, and an MCP client
  that imports the tools of a foreign server under a namespaced name;
- a run context that owns the session, the transport, the answerer and the
  rules of one run, and three placements: attached, service and batch;
- a service lifecycle: a dedicated Emacs is started, connected to and
  stopped as a service, serving ACP over a local socket in a user-private
  directory — and the editor side of it: an ACP client that connects,
  matches answers to requests, answers the service's permission requests
  (`session/request_permission') and sees the streamed updates; `M-x
  yeah-service' opens a buffer that drives such a service, the person
  grants that service its standing permissions when it starts, and what
  the rules do not name is asked of the person over the wire; with
  `yeah-service-init-file' the service starts clean and loads only that
  file (the gptel configuration) instead of the person's full init;
- an emacsclient bridge to the live buffers of an attached Emacs, approved
  separately and off by default;
- agent presets read from files, and a delegation that runs a child for
  real: its own session, its own permissions, its own journal.

After Stage 7, byte compilation is clean and 319 ERT unit tests pass, and
the fixed-point demonstration is verified with a real model.
Direct canaries cover transport, scheduling, tool failures, real coding,
asynchronous compaction, product installation entry points, the wire
(real Emacs processes serving ACP and MCP over stdio, and ACP over a local
socket, where a cancel preempts a running prompt), the placements
(the same task in three real processes, compared event by event), the
journey of a person (ask, steer, quit, restart, withdraw, recover, cancel),
and the shared attached/service journal.  The math-coding v5 map/run/gate
result is green for all 55 declared claims, each with a negative control
shown to bite.
A real model (MiniMax-M3.1-Flash) finishes the Stage 1 coding task, and the
interactive path works against a live provider: the journal mode, the cancel,
the quit and the restart, the resume of the session, and the recovery of a
pending input.  The interactive path was re-checked on 2026-11-14 after the
Emacs-native UX wave: the whole scenario (fix the file, cancel, quit,
restart, recover) passes with MiniMax-M2.7, and the service path passes with
MiniMax-M3.1-Flash.  One honest difference: a model that narrates its next
step instead of acting is nudged into the action by the completion nudge —
that nudge carries MiniMax-M2.7 through, but MiniMax-M3.1-Flash keeps
narrating on the larger task and the run ends without the effect.  The fixed point passes with a live model too: a child agent
repairs a Yeah canary and the canary passes afterwards.  The clean-Emacs
install path is network-tested against the published repository by
`tests/live/live-clean-install.el`, which closes the public alpha gate.

## What is not finished

Do not infer a working product from the presence of a module:

- the stdio wire server answers one request at a time: a cancel that arrives
  while a prompt is running is read after that prompt reaches a terminal
  state.  The socket transport (`lib/yeah-wire-socket.el`) does not have
  this limit — a cancel is handled while the prompt is still running;
- `M-x yeah' still opens the attached placement.  The service placement has
  the same journal and composer, but switching the default entry point is
  deliberately deferred until session replay, steering, pending-input
  recovery and mode changes have the same service/attached behaviour;
- the service journal receives the live ACP stream, but `session/load' does
  not yet replay an earlier session into it, and the service path does not
  yet expose the attached path's pending queue, steering, withdrawal and
  recovery commands;
- the shared approval/diff components are implemented and tested, but the
  attached and service paths still use their smaller prompt surfaces rather
  than one wired approval view.  The service preview is a read-only text
  diff, not the full `diff-mode' surface;
- `nerd-icons' is optional decoration only.  Without it, without multiple
  fonts, or with `yeah-icons' set to `never', every label remains readable
  text; no icon package is required;
- the ACP agent and the MCP server are driven by a third-party client
  (xenodium/acp.el) with a fake model, and the service path itself is
  verified with a live provider (`tests/live/live-service-path.el`: a clean
  service Emacs, a real model, a write approved over the wire — one earlier
  attempt failed at the provider, an intermittent refusal); a real editor
  (agent-shell) against a live provider is still open;
- the bridge to the buffers of an attached Emacs is verified against a live
  Emacs server (a real daemon), but not yet against a person's Emacs in
  day-to-day use;
- the fixed-point demonstration is verified with a real model: a child of
  Yeah repairs a Yeah canary (with retries, because a multi-step repair is
  not always reliable on the first attempt);
- concurrent sessions in one Emacs are isolated per run context (sessions,
  permissions, cancellation, budgets and advertised tools are the run's own),
  checked for cross-talk;
- PTC is disabled by default and remains **experimental, not a security
  boundary**; its demonstrated higher-order-function bypasses are covered by
  regression tests, but no general isolation is claimed;
- bootstrap installation is network-tested in a clean Emacs HOME against
  the published repository (`tests/live/live-clean-install.el`).  The
  bootstrap installs gptel pinned to the supported revision — the current
  MELPA snapshot of gptel does not byte-compile cleanly on a clean Emacs.
  The interactive UI path is verified against a live provider.

The design also removes any assumption that a gptel hook is real merely
because a unit test names it: the adapter must be checked against pinned,
actual gptel contracts.

## Architecture and plan

Read in this order:

0. `docs/VISION.md` — why Yeah exists: the environment people invested
   themselves in, surviving the era of agents as a participant;
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
(package-vc-install
 '(yeah :url "https://github.com/11111000000/yeah.git" :lisp-dir "lib"))
```

Then configure the gptel backend/model and key through your normal Emacs
mechanism, run `M-x yeah-doctor`, and start with `M-x yeah`.

A clean-Emacs bootstrap is also provided:

```sh
emacs -Q --batch -l install/yeah-bootstrap.el
```

It installs gptel from MELPA when needed and Yeah through package-vc.  The
path is network-tested by `tests/live/live-clean-install.el` against the
published repository; it does not run in CI, so report any bootstrap
failure.

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
YEAH_TEST_KEY=... YEAH_TEST_MODEL=MiniMax-M3.1-Flash EMACS=... \
  emacs -Q --batch -L /path/to/gptel -L lib -l tests/live/live-model-call.el
YEAH_TEST_KEY=... YEAH_TEST_MODEL=MiniMax-M3.1-Flash EMACS=... \
  emacs -Q --batch -L /path/to/gptel -L lib -l tests/live/live-coding-task.el
YEAH_TEST_KEY=... YEAH_TEST_MODEL=MiniMax-M3.1-Flash EMACS=... \
  emacs -Q --batch -L /path/to/gptel -L lib -l tests/live/live-fixed-point.el
```

`YEAH_TEST_KEY` is the provider key, `YEAH_TEST_HOST` and `YEAH_TEST_MODEL`
choose the endpoint and the model, and `EMACS` names the Emacs that runs the
project's own tests.  No key belongs in this repository, in a session log
or in the documentation; keep the credentials in the environment (a private
file outside the checkout is enough).

The second one runs a real coding task against a real provider: the harness
reads the project, edits the file with a guarded edit, saves it, and the
project's test passes.  The third one is the fixed point: a child agent
repairs a Yeah canary, and the canary passes afterwards.  The model's
reasoning is kept in the conversation by
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
