# Yeah — Y-combinator, Emacs Agent Harness

> **Status: v0.1.0-alpha; a kernel prototype, not yet a usable product.**
> Read `docs/PLAN.md` for the current baseline and the road to a public
> alpha. `spec.json` and `./scripts/dev map` are the machine-checked source
> of truth; documentation never substitutes for that evidence.

**Yeah** is an Emacs Lisp agent harness: the agent executes inside Emacs,
not inside a separate agent process with Emacs acting as a client. The model
is reached through **gptel**; tools are permissioned Elisp functions; session
history is an **append-only JSONL journal**.

The **Y** stands for the Y-combinator and expresses the long-term design:
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

The repository contains 21 focused Elisp modules implementing pieces of the
kernel:

- a defined run state machine and model-turn orchestration;
- a typed tool registry and last-match permission rules;
- shared/exclusive scheduling with once-only settlement and structured tool
  failure handling;
- an append-only JSONL session store and typed event vocabulary;
- event-derived view models and session projections;
- undo boundaries, retries/timeouts and context/compaction primitives;
- initial ACP/EMCP data structures and test fakes.

After Stage 0.3, byte compilation is clean and 118 ERT unit tests pass.
Direct canaries cover transport, scheduling and tool failures.  Frozen
math-coding v4 map/run/gate results are not treated as current evidence.

## What is not finished

Do not infer a working product from the presence of a module:

- the REPL currently echoes a stub;
- ACP prompt/cancel, MCP handlers and sub-agent execution are incomplete;
- the built-in coding tool set is not implemented beyond a limited reader;
- compaction is not yet fully asynchronous or integrated into the run;
- global state and incomplete event correlation still limit concurrent runs;
- PTC is disabled by default and remains **experimental, not a security
  boundary**; its demonstrated higher-order-function bypasses are covered by
  regression tests, but no general isolation is claimed;
- there is no supported one-step user installation yet.

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

A real provider test exists separately and requires environment credentials:

```sh
emacs -Q --batch -L lib -l tests/live/live-model-call.el
```

No key belongs in the repository, session log or documentation.

## Research

Reference clones of current Emacs agent projects are kept outside the source
tree in `../emacs-agents-research/`. The useful architectural findings are
summarized in `docs/ARCHITECTURE.md` §12. They are not runtime dependencies.

## Author

- **Petr Kosov** <p.b.kosov@yandex.ru>

## License

- **Apache-2.0** (see `LICENSE`, `NOTICE`)
