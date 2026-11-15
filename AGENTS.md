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
- The parity with other harnesses was piloted on 2026-11-15, and the
  difference the pilot found was a defect of the turn, not a difference of
  quality: after the results of the tool calls arrive, the model may answer
  with an empty message, and the turn took that as the end of the work and
  stopped without the effect (docs/LIVE-EVIDENCE.md, "The pilot of the
  parity").  The defect is fixed (the claim
  `an-empty-answer-does-not-end-the-run'), and the pilot on the fixed turn
  moved one task of three; the nudge now carries the state of the work
  (the claim `a-silence-nudge-carries-the-state-of-the-work'), because the
  provider goes silent after every batch of tool results and the model was
  answering the nudge by starting the work over.  With that, Yeah passes
  two tasks of three and pi passes three.  The third task failed in the
  tools: the `read` of a file nobody has edited yet returns no tick, and
  the `edit` refused the tick the model guessed as stale although the file
  has not changed; wave 26 makes a guessed tick ignored rather than
  refused (the claim
  `a-guessed-tick-does-not-refuse-an-unchanged-file'), and that task of the
  pilot passes now.  The provider was overloaded for hours (HTTP 529 to both
  harnesses), so the pilot of 15:02 measured one task of three and two
  blocked runs: the runner records a run the provider stopped as **blocked**,
  neither a pass nor a failure (the claim
  `a-provider-failure-is-not-a-failure-of-the-agent').  The pilot of 15:39, on
  the code of wave 28, measured two tasks of three — Yeah passed both of them
  and pi passed all three — and the third was blocked, because the transport
  to the provider died.  The parity of that run is not measured either.  The
  pilot of 17:06, on the code of waves 30+31, measured one task of three for
  Yeah and two of three for pi: all three runs of Yeah ended `unfinished`,
  because the provider goes silent, and the one task that failed in the tools
  failed on the **version token** of the file — the model copied 58 of the 64
  characters of the digest and the edit refused the edit of a file that had
  not changed (docs/LIVE-EVIDENCE.md, "The pilot that measured the copy of the
  version token").  The threshold of the parity is a decision of the owner
  (docs/PLAN.md §13), and nobody may quote the pilot as a verdict about
  parity.
- A decision that arrives while the tools of the previous decision are still
  running no longer breaks the run: the turn keeps the calls, runs them when
  the running batch has settled, and gives the model the results of every
  batch together (wave 28, the claims
  `a-decision-that-arrives-while-the-tools-run-does-not-break-the-run' and
  `the-same-tool-call-does-not-run-twice').  The live checks of 15:38 hold
  no transition error at all.  The live coding task still fails, and it fails
  for another reason: the model of the provider answers with an empty message
  and the run ends with the record "unfinished" — the work is not done, and
  the run says so.
- The read of a file shows the file on disk, but the tick it hands out
  belongs to the buffer that visits the file: when Emacs holds unsaved
  changes of that file, the model sees the disk and the edit applies to the
  buffer.  Wave 29 refuses that case when the model presents the version of
  the read, but the path that presents only a tick keeps the old behaviour,
  and the write tool overwrites a whole file and takes no version at all.
  Both are open in docs/PLAN-NEXT.md.
- Every read now hands the model the version of the file as well: the digest
  of its bytes (lib/yeah-version.el). The edit checks that version and is
  refused when the file changed after the read, so an edit never lands on a
  file the model did not read; it is also refused when Emacs holds unsaved
  changes of the file, because a read of the disk cannot show them. A
  version that no read handed out is ignored, like a tick that no read handed
  out. docs/ARCHITECTURE.md §D5 was amended, not weakened: it names the
  version as the second form of the state a read returns.
- A decision that repeats a call that is already running is dropped, and the
  drop is now in the journal: the event `tool-dropped` carries the tool, the
  reason and the arguments, so a reader of the log tells a repeated decision
  from a decision that never came (wave 30). The model is not told that its
  repetition was refused, because a tool that runs twice would repeat its
  side effect; the identity of a call is still the tool and its arguments.
  docs/ARCHITECTURE.md §D1 was amended, not weakened: the vocabulary it
  names now includes dropped calls.
- The checks read the journals through one reader
  (`tests/support/yeah-journal-files.el`), and that reader skips the lock
  files of Emacs (`.#`) next to a journal and survives a journal that
  vanishes between the scan and the read. A check that crashes on the
  filesystem does not fail on its assertion, and the method reads a crashed
  verifier as an error and not as a proven control (wave 31).
- Stage 7 is implemented offline: an agent preset is a file (a Markdown or
  Org header and a body), and a child runs for real in its own session with
  only the tools it was granted. The fixed-point demonstration passes with
  a live model: a child repairs a Yeah canary and the canary passes
  afterwards (tests/live/live-fixed-point.el, one child). Parallel
  children and the cheaper child model are not implemented yet; an Org
  preset header and the Org export of a session are (lib/yeah-agent.el,
  lib/yeah-org.el).
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
  closed; v0.2.0 carries the Emacs-native interface.
- The interface is seen, not only described: `tests/pixel/` draws the journal
  and the approval view in Emacs itself under a virtual frame server and
  photographs the screen; `./scripts/dev pixel` compares the pictures with
  each other and with the same buffer without the interface.  It needs a
  frame server, a terminal emulator and ImageMagick but no provider key, so
  it lives outside the map — like the live checks — and is registered in
  `docs/LIVE-EVIDENCE.md`.  A stored golden picture is still open.
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

74 claim(s).

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
