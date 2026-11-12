# AGENTS.md — the entry point to this repository

> **Yeah** means **Y-combinator, Emacs Agent Harness**. The harness itself is
> Emacs Lisp; Emacs is not merely a client to an external agent. The model is
> reached through gptel, effects go through the tool registry and permission
> system, and session history is append-only JSONL.
>
> The long-term Y metaphor means bounded recursive delegation, runtime
> self-inspection and a fixed point where Yeah can develop and verify Yeah.
> These are goals, not assertions about today's prototype.
>
> This repository is governed by **math-coding**: `spec.json` holds claims,
> `waves/*.json` holds the work units and evidence comes from checks.
> Version 4 of the tool is frozen and version 5 is being developed, so the
> frozen `map`/`run`/`gate` commands are not to be run: byte compilation, ERT
> and the direct canaries are the current evidence.
> `docs/PLAN.md` defines the current target sequence; do not mistake an old
> wave number or a green module row for a working end-to-end feature.

## Read first, in this order

1. `README.md` — actual current status and explicit limitations.
2. `docs/ARCHITECTURE.md` — the normative target: purpose, ten decisions,
   contracts, security, placements and non-goals.
3. `docs/PLAN.md` — the detailed eight-stage execution plan and release gates.
4. `docs/ENGINEERING.md` — binding dependency, infrastructure, library,
   process, security, testing and packaging practices.
5. `spec.json` — the standing machine-checked specification.
6. `waves/*.json` — existing math-coding units, with intent, check, promise
   and objection.
7. `ELISP_BEST_PRACTICES.md` — kernel Elisp conventions; §11 is the trap log.
8. `lib/yeah-*.el` — the implementation, one feature per file.

If two sources contradict each other, report the contradiction in the open
work item. Never resolve it by silently making documentation more optimistic.

## Current warnings for every agent

- This is a kernel prototype, not a usable coding product.
- Stage 7 is implemented offline: an agent preset is a file (a Markdown or
  Org header and a body), and a child runs for real in its own session with
  only the tools it was granted. Parallel children, the cheaper child
  model, the Org projection and the fixed-point demonstration are not
  implemented yet.
- Stage 6 is implemented offline: the run context owns the session, the
  transport, the answerer and the rules of one run, and the three
  placements — attached, service, batch — write the same events for the
  same task. The bridge to the buffers of an attached Emacs is off until
  the operator turns it on, and it was checked against a stub program,
  never against a live Emacs server.
- Stage 5 is implemented offline: the ACP agent and the MCP server speak
  newline JSON-RPC over stdio, the `emacs__*` handlers are real, and the MCP
  client imports foreign tools. Two limits are not hidden — the stdio server
  answers one request at a time (a cancel cannot preempt a running prompt),
  and no third-party client or live provider has driven either server.
- REPL still contains placeholders. Do not build new public behavior on
  top of it while its stage's prerequisites are unmet.
- Stage 4 is implemented offline: `M-x yeah`, journal commands, doctor and a
  package-vc bootstrap exist.  Bootstrap and live-provider interactive work
  are not yet verified, so the public alpha gate remains open.
- Stage 3 is implemented offline: persistent pending FIFO, frozen inputs,
  steering at batch boundaries, cancellation, nudges and deadlines have
  integration tests, including synchronous callback races. The journey of a
  person — ask, steer, quit, restart, withdraw, recover, cancel — is checked
  end to end with a fake model.
- Stage 2 is implemented offline: usage calibration, asynchronous compaction,
  pruning events and corrupt-tail recovery are covered by unit/canary tests.
  The compatibility `yeah-context-summarize` never waits; real providers use
  the asynchronous API. Live-provider acceptance remains unverified.
- Stage 1 is implemented offline: coding tools, tick editing, async jobs,
  output artifacts and Emacs introspection pass their unit and end-to-end
  checks. Live-provider acceptance has not been verified.
- Stage 0.5 is implemented: module comments match current behavior and no
  longer reference nonexistent decisions/Tier/ROADMAP documents. Stage 0.4
  awaits math-coding v5; do not run frozen v4 commands.
- Stage 0.3 is implemented: tool failures are bounded, model-facing results
  are strings, and duplicate async callbacks cannot settle a call twice.
- Stage 0.2 is implemented: PTC is disabled by default and the demonstrated
  higher-order-function bypasses have regression tests. It remains an
  experimental restricted evaluator, never a sandbox for untrusted code.
- Stage 0.1 is implemented: gptel requests use a private, version-checked
  adapter without global hooks. Recheck compatibility whenever gptel changes;
  supported pinned versions are declared in `lib/yeah-gptel.el`.
- A `holds` claim proves its stated check only, not overall product readiness.

## The commands

```sh
./scripts/dev help                  # the list of subcommands
./scripts/dev byte-compile-all      # kernel compiles clean, with no warnings
./scripts/dev ert tests/unit/*.el   # unit tests
./scripts/dev check tests/checks/*  # canaries bound to claims
./scripts/dev map                   # claims, states and uncovered surface
./scripts/dev run                   # execute checks and bind evidence
./scripts/dev gate                  # run, then map; exit code is the verdict
# Opt-in real model call; credentials come from the environment:
emacs -Q --batch -L lib -l tests/live/live-model-call.el
```

`scripts/dev` needs Emacs on `PATH` (or `EMACS`). Method commands also need a
compatible math-coding binary on `PATH` or in `MATHC`. A CLI/version mismatch
is blocked tooling, not a successful check.

Exit codes are: `0` pass, `1` fail, `2` blocked/input error and `3` unknown.
Unknown is never pass.

## The method

Start with the map when the compatible method binary is available:

```sh
./scripts/dev map
```

A claim has a scope, requirement, falsifier, register and **control**. The
control breaks the subject and must make the check fail by a real assertion,
not merely by making the test unreadable or crashing Emacs. A claim whose
control has not bitten is not established.

Two rules are not negotiable:

- **A check that cannot fail is a comment.**
- **Unknown is not pass.**

A placeholder that returns success is also a failed implementation. Public
scenarios must be tested end to end, not inferred from the presence of a
function or module.

<!-- math-coding:begin -->
## math-coding in this project

This block is written by `mathc install` and by nothing else.
Everything outside it belongs to the project and is never touched.
Re-run `mathc install` after the specification changes;
`mathc doctor` says whether this block is current.

### The aim

Yeah is an Emacs Lisp agent harness: the user's Emacs session is itself the runtime of the agent; every call to the model goes through gptel, every tool goes through the registry and the permission system, and the session log stays append-only

Stated by p.b.kosov@yandex.ru, over lib/, tests/, scripts/, schemas/, docs/, AGENTS.md, README.md, ELISP_BEST_PRACTICES.md.

### The next step

```sh
mathc --root . next
```

### What is declared

28 claim(s): 22 holds, 6 not established.

The full list, and what is not covered: `mathc --root . map`.

### If you are an agent here

```sh
mathc map      # what is claimed, what is known, what is not covered
mathc run      # run the checks, bind every proof to the content it ran against
mathc route    # what needs a person, and why
mathc next     # the next work, one item
mathc add ID "SUBJECT" SCOPE "WHAT WOULD REFUTE IT" fact \
   --requirement verifier:CMD --control CMD
```

The control is the command that breaks the subject and must fail with it:
a check that cannot fail proves nothing.

For an agent the machine surface is cheaper: `mathc --root . mcp` speaks
JSON-RPC and returns the next step with every method.

Every verb: mathc - · mathc init · mathc goal · mathc add · mathc accept · mathc control · mathc budget · mathc map · mathc route · mathc run · mathc record · mathc next · mathc wave · mathc close · mathc draft · mathc install · mathc mcp · mathc propose · mathc doctor.
<!-- math-coding:end -->

## Working rules

- Follow the stage order in `docs/PLAN.md`; do not start ACP, placements or
  sub-agents ahead of their prerequisites.
- Every new claim needs a control shown to bite. Every feature needs an
  observable end-to-end check appropriate to its layer.
- `lib/` is Elisp only. No C, Rust or shell scripts inside the kernel.
- One feature per file; `(require 'yeah-x)` loads `lib/yeah-x.el`.
- Public symbols use `yeah-`; internal helpers use `yeah--` or the module's
  established internal prefix.
- Domain errors are `user-error` or structured tool errors, not false success.
- Use `let` for request-local dynamic configuration of special variables;
  use `setq` only for intended global/session mutation. See ELISP §11.1.
- Subprocesses use `make-process`, never blocking `shell-command` in tools.
- Interactive execution never waits by spinning the event loop.
- Run context, permissions and sessions must not leak through new global
  mutable state.
- No telemetry, secret logging, global default keybindings or global gptel
  mutation.
- Development-only Nix/mathc/research clones never become runtime dependencies.

The detailed rationale and additional rules are in `docs/ENGINEERING.md` and
`ELISP_BEST_PRACTICES.md`. Update documentation whenever behavior changes;
update `AGENTS.md` if the documented workflow itself changes.
