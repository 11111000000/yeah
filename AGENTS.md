# AGENTS.md — the entry point to this repository

> **Yeah** means **Yeah, Emacs Agent Harness**: a recursive acronym, the
> **Y** is the Y-combinator. The harness itself is
> Emacs Lisp; Emacs is not merely a client to an external agent. The model is
> reached through gptel, effects go through the tool registry and permission
> system, and session history is append-only JSONL.
>
> The long-term Y metaphor means bounded recursive delegation, runtime
> self-inspection and a fixed point where Yeah can develop and verify Yeah.
> These are goals, not assertions about today's prototype.
>
> This repository is governed by **math-coding v5**: `spec.json` holds the
> standing specification (`schema_version: 5`) and the claims, `waves/*.json`
> holds the historical work units, and evidence comes from checks bound by
> `mathc run`.  Version 4 is frozen and archived at `waves/spec-v4.json`;
> its evidence is not current.
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
  only the tools it was granted. The fixed-point demonstration passes with
  a live model: a child repairs a Yeah canary and the canary passes
  afterwards (tests/live/live-fixed-point.el, one child). Parallel
  children, the cheaper child model and the Org projection are not
  implemented yet.
- Stage 6 is implemented offline: the run context owns the session, the
  transport, the answerer and the rules of one run, and the three
  placements — attached, service, batch — write the same events for the
  same task. The bridge to the buffers of an attached Emacs is off until
  the operator turns it on; it is checked against a live Emacs server
  (a real daemon) by tests/checks/check-bridge-live-server.el.
- Stage 5 is implemented offline: the ACP agent and the MCP server speak
  newline JSON-RPC over stdio and over a local socket, the `emacs__*`
  handlers are real, and the MCP client imports foreign tools. The wire is
  now driven by a third-party client (xenodium/acp.el) with a fake model;
  the service path with a live provider is covered by
  tests/live/live-service-path.el;
  what is still not proven is a real editor against a live provider.  Two
  limits are not hidden — the stdio server answers one request at a time
  (a blocking stdin read stops the event loop, so a cancel cannot preempt
  a running prompt there; the socket transport can), and a live provider
  has not driven the MCP server.
- REPL still contains placeholders. Do not build new public behavior on
  top of it while its stage's prerequisites are unmet.
- Stage 4 is implemented offline and verified against a live provider:
  `M-x yeah`, journal commands, the Org export, doctor and a package-vc
  bootstrap exist.  A real model (MiniMax-M3.1-Flash) finishes the Stage 1 coding
  task, and the interactive path works against a live provider.  The
  clean-Emacs install path is network-tested against the published
  repository (tests/live/live-clean-install.el): the public alpha gate is
  closed and v0.1.0 is the public alpha.
- Stage 3 is implemented offline: the Plan and Build permission profiles,
  a persistent pending FIFO, frozen inputs,
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
  is implemented: the project migrated to math-coding v5; `mathc run`, `map`
  and `gate` work with the installed v5 binary.
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

Yeah is an Emacs Lisp agent harness: the harness runs in a dedicated Emacs process (the service placement); the model goes through gptel, every tool goes through the registry and the permission system, the session log stays append-only, and the editor reaches it through the bridge or an ACP/MCP client

43 claim(s).

```sh
mathc run
```

Every verb: mathc help mathc init mathc goal mathc add mathc run mathc map mathc next mathc context mathc waive mathc record mathc install mathc doctor mathc adopt mathc import-adr mathc import-junit mathc authorize mathc re-evaluate mathc review-source mathc mcp
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
