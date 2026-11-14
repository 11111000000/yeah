# PLAN — the road to Yeah 1.0

> **Status: execution plan, not current capability.** The target and its
> rationale are in `docs/ARCHITECTURE.md`; binding engineering rules are in
> `docs/ENGINEERING.md`. The machine-checked present is `spec.json` and
> `./scripts/dev map`.
>
> This plan introduces eight **stages**. Existing `waves/wave-01.json` …
> `wave-14.json` remain the historical math-coding units until corresponding
> new claims/waves are added. A stage is not considered closed here: closure
> requires the specification and its evidence to agree.

## 1. Current baseline

Verified on 2026-11-14 in the `feat/emacs-ux-v3` integration branch:

- all 53 Elisp files under `lib/` byte-compile without warnings;
- 319/319 ERT unit tests pass;
- all 46 canaries pass when run directly (`./scripts/dev check tests/checks/*`);
- the installed math-coding v5 tool runs the standing specification: all 55
  claims hold, and every negative control changes its scoped subject and
  makes the verifier fail with an assertion;
- live provider behavior remains verified on 2026-11-12: the live coding task
  (MiniMax-M3.1-Flash) reads the project, edits the file with a guarded edit,
  saves it, and the test of the project passes, and the interactive UI
  path (journal, cancel, quit, restart, resume, recover) works against a
  live provider.  The clean-Emacs install path is network-tested against the
  published repository (`tests/live/live-clean-install.el`).

The code contains a working kernel and a working wire, but not yet a usable
product:

- the stdio wire server answers one request at a time: a cancel that
  arrives while a prompt runs is read after that prompt settles.  The
  socket transport (`lib/yeah-wire-socket.el`) does not have this limit —
  a cancel arrives while the prompt is still running;
- the emacsclient bridge was checked against a live Emacs server (a real
  daemon) by `tests/checks/check-bridge-live-server.el`, but not yet against
  a person's Emacs in day-to-day use;
- concurrent sessions in one Emacs are isolated per run context: sessions,
  permissions, cancellation, budgets and the advertised tools are the run's
  own, and two sessions in one Emacs are checked for cross-talk;
- the PTC whitelist was experimentally bypassed with a permitted higher-order
  function and a quoted `delete-file` symbol. It is not a safe boundary.

## 2. Stage map and dependencies

```text
0. Honesty and safety
   └─> 1. Coding tools
         └─> 2. Context and compaction
               └─> 3. Human control
                     └─> 4. Installable interactive product  [PUBLIC ALPHA]
                           └─> 5. ACP/MCP wire
                                 └─> 6. Placements
                                       └─> 7. Delegation and ecosystem

Benchmarks and documentation run continuously; 1.0 requires stages 0–7 and
release gates from §11.
```

ACP and service mode come after the interactive slice deliberately: they
must transport a working kernel, not conceal missing execution behind
protocol handlers.  Minimal Emacs-native UI and installation come before
them because they validate the actual user experience.

**Primary deployment path (decided 2026-11-12).**  The practical main use
of Yeah is the service placement: a dedicated Emacs process runs the
harness, because the person's editing Emacs is single-threaded and an
in-editor agent would block editing.  The editor reaches the harness
through the emacsclient bridge; external clients and orchestrators (an
ACP client such as agent-shell, or an orchestrator such as Paseo) speak
ACP or MCP to the same service.  The attached `M-x yeah` placement
remains the demo, development and fallback path.

This decision does not reorder the stages; it re-prices their exit
criteria.  A cancel that preempts a running prompt on the wire, a bridge
verified against a live Emacs server, concurrent sessions in one service
Emacs and bounded CPU work inside the agent process are release-relevant
items of stages 5 and 6, not post-alpha extras.

## 3. Stage 0 — honesty, compatibility and safety

### Intent

Remove known false assurances and protect the kernel before it grows.

### Work items

**0.1 Repair the gptel boundary.** **Status: implemented on 2026-11-10.**
The adapter now validates pinned gptel 0.9.9.5/0.9.9.6 contracts, passes
private backend/model/tools/system options without global hooks, disables
ambient editor context, normalizes failures and usage, and returns gptel's
FSM. All 110 ERT tests pass and a no-network dry-run against real gptel
0.9.9.6 succeeds. No live provider request was made.

- Remove registration and documentation of nonexistent/unsupported hooks,
  including `gptel-fsm-handlers` on the current gptel contract.
- Make requests privately configured; do not mutate global gptel settings.
- Normalize text, reasoning, tool calls, errors and usage at the boundary.
- Add an explicit supported-version/contract check.
- Files: `lib/yeah-gptel.el`, `lib/yeah-turn.el`, gptel unit/canary tests,
  `tests/live/live-model-call.el`.

**0.2 Quarantine PTC.** **Status: implemented on 2026-11-10.**
`yeah-codes-eval` is disabled by default, refuses before reading forms while
disabled, and is documented as an experiment rather than a sandbox. The
confirmed `mapcar` bypass and the analogous `sort` predicate bypass are
regression-tested and rejected by removing uncontrolled higher-order calls
from the restricted core. This closes the demonstrated exploits without
claiming general isolation.

- Mark the current PTC implementation experimental and keep it off public
  execution paths.
- Add the confirmed higher-order-function/quoted-symbol exploit as an
  adversarial regression test.
- Correct the claim so it no longer asserts a safe general sandbox. Decide
  separately whether a restricted interpreter is worth retaining.
- Files: `lib/yeah-codes.el`, `tests/checks/check-ptc-sandbox-restricts.el`,
  `spec.json`, security documentation.

**0.3 Add execution failure canaries (U1–U4).** **Status: implemented on
2026-11-10.** The scheduler now has a per-call once-only guard, catches sync
and async handler failures, normalizes nil/non-string results, and preserves
call order. The turn logs structured failures and always gives the model a
string. Five scheduler ERT cases and an end-to-end U1–U4 canary pass; the
full suite has 118 ERT tests.

- U1: malformed tool args become a structured tool failure, not a stuck FSM.
- U2: a handler exception fails pending work and lets the batch settle.
- U3: a duplicate async callback cannot produce a second result or advance
  the state twice; first result wins.
- U4: nil/non-string tool results are normalized before logging/provider
  serialization.
- Files: `lib/yeah-turn.el`, `lib/yeah-scheduler.el`, `lib/yeah-tools.el`,
  `tests/checks/`.

**0.4 Make the evidence toolchain reliable.** **Status: migrated to v5 on
2026-11-12.** The installed `mathc` is v5, and the project specification is
re-stated in it (`spec.json`, `schema_version: 5`): the aim is the
service-first placement, and the focused claim set covers compilation, the
unit suite, the wire (stdio, socket cancel, third-party client), the live
bridge, concurrent sessions, responsiveness and the product install — each
with a control shown to bite by `mathc run`.  The v4 specification is
archived at `waves/spec-v4.json`; the v4 map/run/gate evidence is frozen
and is not current.  `mathc install` writes the AGENTS.md block.

- Pin a compatible mathc build or adjust `scripts/dev` to its supported CLI.
- Ensure map/gate exit codes distinguish pass, fail, blocked and unknown.
- Keep unit and canary execution independent of mathc availability.
- Files: `scripts/dev`, CI/development documentation.

**0.5 Reconcile source and documentation.** **Status: implemented on
2026-11-10.** Kernel comments no longer reference nonexistent `decisions/`,
ROADMAP or Tier milestones; FSM documentation describes current states;
placeholders explicitly identify themselves; stale dynamic-binding guidance
was corrected; README reports the current 118-test baseline.

- Remove stale Tier/ROADMAP/nonexistent `decisions/` references and incorrect
  state counts in comments.
- Ensure every placeholder is named as such and no public README table calls
  a placeholder operational.
- Record D1–D10 as accepted target decisions in ARCHITECTURE.

### Required claims and controls

- `turn-survives-malformed-tool-args`: control injects non-plist args; the
  check must observe a bounded failure, not hang.
- `turn-settles-after-handler-exception`: control makes a handler signal;
  every call must reach one terminal result.
- `turn-first-result-wins`: control invokes a continuation twice; exactly one
  `tool-end` and one state settlement are allowed.
- `tool-result-is-provider-safe`: control returns nil; outgoing content must
  be a valid string/error representation.
- `no-dead-gptel-hook-contract`: control points at an unsupported gptel
  contract; startup/request must fail explicitly.
- `ptc-is-not-a-public-security-boundary`: control exposes PTC publicly or
  weakens its guard; the release check must fail.

### Exit criteria

All four execution failure classes have biting tests; no unsupported gptel
hook is registered; PTC is not presented as safe; the standard test commands
pass; map/gate either works with the pinned tool or is honestly blocked.

## 4. Stage 1 — a useful coding tool set

### Intent

Complete real coding tasks through the existing registry and permissions.

**Status: implemented offline on 2026-11-10.** The registry now includes
Read/Glob/Grep, tick-guarded Edit/Write, async Bash with maximum and idle
timeouts, job controls, output artifacts, Introspect, Buffer Read, Elisp Check
and Flymake diagnostics. Structured results retain truncation/artifact
metadata. The end-to-end coding canary passes, and process output no longer
includes Emacs sentinel noise. Live-provider acceptance remains unverified;
this is not yet a claim of model-driven task completion.

### Work items

**1.1 Complete the common tool result.** Structured success/error content,
truncation metadata, artifact references and bounded serialization.

**1.2 Implement file discovery and reading.**

- Read honors byte/character/line semantics chosen in its schema, including
  offset and limit.
- Glob and Grep are git-aware where available, bounded and project-rooted.
- Paths are canonicalized before permission evaluation.

**1.3 Implement guarded Edit and Write.**

- Reads return `buffer-chars-modified-tick` where a buffer is involved.
- Edit requires expected old text/ranges and tick; stale input is rejected.
- Validate all replacements first; apply bottom-up; one logical undo step.
- Saving is separate from editing; user changes are not discarded.
- Write uses clear create/overwrite semantics and approval.
- Files: `lib/yeah-tools.el`, `lib/yeah-undo.el`, new focused tool modules
  only if the single-feature rule requires them.

**1.4 Implement Bash and jobs.**

- `make-process`, explicit shell/argv semantics, UTF-8, working directory,
  idle and maximum timeouts, cancellation and bounded output.
- Long jobs expose start/status/read/cancel instead of blocking a turn.

**1.5 Add output artifacts.** Oversized output is stored under private data
 directories with `0700`/`0600`; model results carry an excerpt and reference.

**1.6 Add Emacs-native tools.**

- Introspect: describe/apropos/source lookup with bounded results.
- Buffer read for live named buffers.
- Elisp check: read/check-parens/byte-compile/ERT as appropriate.
- Diagnostics: Eglot/Flymake when available, with explicit unavailable states.

### Required checks

- wrong argument shapes and workspace escapes are refused;
- stale tick and nonunique old text never mutate a buffer;
- a no-op edit does not add undo history;
- duplicate process callbacks settle once;
- output limits produce an artifact, not unbounded context;
- live coding scenario: read a small project, reproduce a failing test, edit
  it, rerun the test and return a reviewable diff.

### Exit criteria

The live scenario works with at least one pinned real provider through gptel.
A control that bypasses tick validation or path checks makes the relevant
canary fail. No tool returns placeholder success.

## 5. Stage 2 — context, usage and asynchronous compaction

### Intent

Long tasks remain responsive, bounded and recoverable.

**Status: implemented offline on 2026-11-10.** Token estimates are CJK-aware
and calibrated by real usage, usage is logged, and overflow drives asynchronous
compaction through the run FSM.  Empty/failed summaries do not commit.  Pruning
is a pure projection with a journal event, compaction/pruning are in the event
vocabulary, and malformed JSONL tails produce explicit recovery metadata and a
warning without rewriting history.  A timer-delayed compaction canary passes;
no live provider outage test has been performed.

### Work items

**2.1 Introduce model capabilities and budgets.** Context window, reserve,
output limits and per-run token/time/cost budgets are explicit configuration,
not universal constants.

**2.2 Calibrate token estimates.** Separate provider usage from estimates;
include system prompt and tool schemas; account for CJK; calibrate
`actual/estimated` within a bounded range.

**2.3 Make compaction asynchronous.** Overflow enters `compacting`; a model
callback emits success/failure; no `accept-process-output` wait loop. Empty,
cancelled or failed summaries do not replace the projection.

**2.4 Use a durable summary contract.** The prompt preserves goals, progress,
mistakes/dead ends, decisions, files, constraints and next steps. Repeated
compaction uses the previous summary and retained suffix correctly.

**2.5 Unify pruning and compaction with the event vocabulary.** Sources stay
append-only; pruned state is represented by events/projection rules, not
unlogged mutation.

**2.6 Recovery and scale.** Detect partial JSONL tails, rebuild projections
from the journal and measure full-log scans before introducing a derived
index.

### Exit criteria

A session beyond its context budget compacts without blocking interactive
Emacs; restart produces the same projection; original records remain;
provider outage leaves the previous projection intact; the UI shows what
happened.

## 6. Stage 3 — human control and robust runs

### Intent

A person can guide, interrupt and recover work without hidden state.

**Status: implemented offline on 2026-11-11.** `yeah-control` queues frozen
inputs in a persistent bounded FIFO (8 entries/256 KiB), starts the next ask
after completion/cancel, and recovers only explicitly.  Steering is logged and
delivered at batch boundaries.  Cancellation marks the run terminal before
stopping managed processes, so late callbacks are ignored.  Visible nudges,
whole-run deadlines, retry backoff and read-only-aware doom-loop detection are
implemented.  Synchronous and asynchronous race cases have ERT coverage.

**The journey of a person is checked end to end** (2026-11-12), with a fake
model and without a network: ask, watch the work, steer, quit, restart, look
at what is left, withdraw what is not wanted, recover what is, and cancel a
run that must stop.  Two rules were fixed by that check: a steering belongs
to one run, so a run that ends without delivering it withdraws the steering
and writes the withdrawal into the journal; and a steering is not a task, so
it is never started on its own.

**Completion supervision tells a plan from a result** (2026-11-12, found by
running the live coding task against a real model).  A model that answered
"I will read the file next" was taken for a finished run; the run stopped
with nothing done.  Now an answer that only announces the next step is a
plan: the run nudges it into the action, and the nudge names the tools the
run has not called yet ("you have not called these tools yet: edit, write,
…  call one of them now").  An answer that reports what was done ("I fixed
it, the test passes") is a result and ends the run — unless no tool backs
it, which means the run has not touched anything yet and is nudged too.
Supervision is off by default; a run asks for it with a non-zero nudge
budget.  With that, the live coding task passes repeatedly and the fixed
point — a child agent repairing a Yeah canary — passes with a real model.

**A supervised run ends through `finish'** (2026-11-13).  A text answer is
not a completion: when the run is supervised, the model ends the run by
calling the `finish' tool with a summary, and the `finish' call is the only
path to `completed'.  Without supervision the contract stays: a text answer
ends the run.  A result no tool backs is nudged, so the model cannot claim
to have done work it did not do.

**A late answer no longer breaks the machine** (2026-11-12).  With a
streaming provider the model sometimes answers while the harness is still
waiting for a tool; the state machine had no transition for that and the
run failed with "no transition from awaiting-tool on stream-end".  The
answer now waits for the tools to settle and ends the run then.  A late
TOOL CALL is different: it is a protocol violation the machine refuses —
the tests of the subagent flow depend on that strictness, and it is
documented here rather than silently tolerated.

### Work items

**3.1 Freeze accepted input.** Backend, model, instructions and editor context
are captured at submission and retained through queues/continuations.

**3.2 Steering.** Deliver clarification at tool-batch boundaries; record it;
define behavior when the run finishes before delivery.

**3.3 Pending input.** Bounded FIFO (initial target: 8 entries and 256 KiB),
persisted safely, never auto-executed after restart, with explicit
edit/withdraw/recover operations.

**3.4 Cancellation.** Propagate to requests, managed processes and callbacks;
late results cannot mutate the run; report possible side effects honestly.

**3.5 Completion supervision.** At most a small configurable number of visible
nudges after apparent completion; reset on real progress; stop on dead
buffers, budgets or terminal states.

**3.6 Runtime guards.** Transient retry with backoff, whole-run deadline,
doom-loop detection that permits legitimate repeated reads, and structured
terminal reasons.

**3.7 Permission profiles (implemented on 2026-11-12).** The session runs
under a profile: `plan' refuses the tools that change the world before
anyone is asked, `build' asks the person for them, and the profile decides
nothing else. A profile is a mode of work, not a policy of the person: the
persistent ruleset is never changed by it.

### Exit criteria

The integration scenario “start → steer → cancel → restart Emacs → inspect
partial results → deliberately recover input” works. No late callback changes
a terminal run; no hidden infinite nudge/retry loop exists.

## 7. Stage 4 — installable interactive product (public alpha)

### Intent

A person can install and use Yeah without reading source or developer docs.

**Status: implemented offline on 2026-11-11, verified against a live
provider on 2026-11-12; the public alpha gate closed on 2026-11-13.**
`tests/live/live-clean-install.el` installed the published repository in a
clean Emacs HOME, so the last network-dependent item of the gate is
verified. `yeah.el` declares package
requirements and exposes `M-x yeah`, `M-x yeah-ask` and `M-x yeah-doctor`.
The journal buffer renders events from the journal, supports ask/steer/
cancel/recover/withdraw/diff and refreshes without blocking.  Sessions and
pending input use private project-scoped data directories.  `install/
yeah-bootstrap.el` documents the clean-Emacs package-vc path; it installs
gptel pinned to the supported revision (the current MELPA snapshot of
gptel does not byte-compile cleanly on a clean Emacs) and Yeah with
`:lisp-dir "lib"`.  The path is network-tested in a clean Emacs HOME
against a local clone by `tests/live/live-clean-install.el`; the
published-repository variant closes the gate once the layout fix is
pushed.

### Work items

**4.1 Product entry.** Add the package header/autoloads and `M-x yeah` with
project/session selection and first-run backend setup using gptel and
auth-source.

**4.2 Journal UI.** Streamed transcript, tool calls/results, folds, reasoning
visibility, pending approvals, diffs, cost, errors and cancellation. Build the
view only from journal projections. Use magit-section/transient/
tabulated-list optionally and preserve the user's completion framework.

**4.3 Approval and review.** once/always/reject with scope; diff before writes;
Plan/Build permission profiles; clear indication of side effects.

**4.4 Installation and configuration.** One init snippet through
package-vc-install or an equivalent supported path; one clean-Emacs bootstrap
path; XDG-compatible data/config locations; no mathc/Nix runtime dependency.

**4.5 Operability and documentation.** `M-x yeah-doctor`, concise quick start,
current limitations, privacy/security guidance and troubleshooting.

**4.6 The session as an Org file (implemented on 2026-11-12).** The journal is
written for the machine; `M-x yeah-export` writes the same truth for the
person: one heading per event, the fields of the event as properties, and the
text of the event in a block that Org cannot mistake for syntax. The export
is a projection — nothing is lost from the journal, nothing is added to it.

### Alpha release gate

On a clean supported Emacs, one documented installation action and backend
configuration lead to the Stage 1 coding task in the interactive UI. The user
can approve, steer, cancel, inspect the diff, quit, restart and resume. No
credentials appear in logs. Unit/canary/integration suites pass.

**Partly verified on 2026-11-12:** the coding task itself is verified
against a real provider (MiniMax-M3.1-Flash), and the interactive UI path is
verified against a live provider (journal, cancel, quit, restart, resume,
recover).  The clean-Emacs install path is not network-tested yet.

## 8. Stage 5 — ACP and MCP wire

### Intent

Expose the working kernel to programs without creating a second agent.

**Status: implemented offline on 2026-11-12.** `lib/yeah-wire.el` carries the
newline-delimited JSON-RPC framing shared by both protocols. `lib/yeah-acp.el`
speaks ACP v1: `initialize`, `session/new`, `session/load`, `session/prompt`
(answered with a stop reason), `session/cancel` (a notification) and
`session/update` notifications fed by the journal events. Sessions are real
Yeah sessions, so the journal semantics are the same as in interactive use.
`lib/yeah-mcp.el` serves the `emacs__*` surface over stdio with real
handlers, and `lib/yeah-mcp-client.el` connects to a foreign server, lists its
tools and imports them into the registry as `mcp--<server>--<tool>`, where the
ordinary permission rules apply. The published MCP surface is read-only by
default; widening it is an explicit operator decision
(`yeah-emcp-publish-extra-tools`). A canary starts real Emacs processes and
exchanges JSON-RPC lines with both servers.

**Two limitations are not hidden.** The stdio server answers one request at
a time, because a blocking stdin read stops the event loop of Emacs — a
cancel that arrives during a prompt is read after that prompt settles.
That limit is the reason the socket transport exists: on
`lib/yeah-wire-socket.el` a connection is a process, the data arrives in a
filter and the event loop keeps running, so a cancel is handled while the
prompt is still running.  And no third-party client or editor has driven
either server yet; the wire checks use Yeah's own processes.

### Work items

- JSON-RPC stdio framing using the project's chosen `jsonrpc` adapter;
- real ACP initialize/new/prompt/update/cancel/load behavior against the
  current protocol schema;
- MCP server with actual registry handlers, argument validation and bounded
  results;
- MCP client with namespaced imported tools and independent permission rules;
- backpressure, malformed-message handling, shutdown and cancellation;
- **concurrent requests on the wire, or at minimum a cancel that preempts
  a running prompt.**  On the primary deployment path (§2) a cancel that
  waits for the prompt's terminal state is a broken user experience, not
  a minor limitation.  **Implemented on 2026-11-12 via the socket
  transport:** `lib/yeah-wire-socket.el` serves connections as processes,
  so the event loop keeps running while the server waits and a
  `session/cancel' that arrives during a running prompt is handled while
  that prompt is still running; `tests/checks/check-wire-cancel-preempts.el'
  drives a real prompt over the socket, cancels it mid-run, observes the
  cancelled stop reason and the journal event, and proves the server still
  answers afterwards.  The stdio transport keeps its documented limit: a
  blocking stdin read stops the event loop, and a reader thread does not
  help (a thread blocked in `read-string' holds the interpreter lock);
- **a third-party client driving the wire end to end.**  **Partly
  implemented on 2026-11-12:** `tests/checks/check-acp-third-party-client.el'
  drives the ACP server with xenodium/acp.el — a client that is not Yeah —
  through the handshake, session creation, a prompt with streamed updates
  and the end_turn stop reason.  This found and fixed a real defect: a turn
  that finished synchronously was registered as active after its completion,
  so the stdio loop never settled the prompt.  What remains open is the
  stronger criterion below: a real ACP editor (agent-shell) against a live
  provider;
- protocol redaction and trust documentation.

Use `../emacs-agents-research/acp.el/` and the ACP specification as references,
not as runtime dependencies.

### Exit criteria

A real ACP editor completes the Stage 1 scenario, including streaming and
cancel. An external MCP client lists and calls explicitly published Emacs
capabilities. The same canonical journal semantics hold as in interactive use.

The first is **partly closed**: the third-party client acp.el drives the
wire end to end with a fake model; a real editor and a live provider are
still open.  The second criterion is **open**: it needs an external MCP
client.

## 9. Stage 6 — attached, service and batch placements

### Intent

One kernel, three operational forms, no hidden global run state.

**Status: implemented offline on 2026-11-12.** `lib/yeah-run.el` is the run
context: the session, the transport, the answerer, the rules, the budget and
the deadline of one run, and the rules of a run are its own — two runs in one
Emacs do not share one truth. `lib/yeah-perm.el` gained `yeah-perm-effect`
(the query without the signal) and `yeah-perm-rules-append` (a ruleset of the
run's own). `lib/yeah-placement.el` holds the three placements: attached (in
the Emacs of the person, who may answer), service (in an Emacs of its own,
where nobody answers) and batch (one task, a headless allowlist, an exit
code). A child placement receives its task on the command line, because the
environment of a person is not something a placement may change. The canary
runs the same scripted task in three real processes and compares the
canonical projection of the three journals: the same events, in the same
order, with the identifiers and the timestamps left out.
`lib/yeah-bridge.el` is the one capability a service placement does not have
by default: it reaches the live buffers of an attached Emacs through
`emacsclient`, and its tools enter the registry only when the operator asks
for them, under their own names, so the permission system approves them
separately.  `lib/yeah-service.el` is the service lifecycle: a dedicated
Emacs is started, connected to and stopped as a service, and a prompt over
its socket is answered and written to its journal
(`tests/checks/check-service-lifecycle.el`).  A headless service cannot
ask the person for permission, so the editor grants it standing
permissions when it starts the service: the plan profile denies the tools
that change the world, and the `allow' profile grants edit, write and
bash (`tests/checks/check-service-permissions.el`).  `lib/yeah-client.el`
is the editor side of that path: an ACP client that connects to the
service, matches answers to requests and hands the session/update stream
to the caller (`tests/checks/check-client-drives-service.el`).
`lib/yeah-service-ui.el` is the product wiring: `M-x yeah-service' starts
or connects to a service that inherits the user's configuration, and a
buffer drives it — the question, the streamed answer and the stop reason
are rendered (`tests/checks/check-service-ui.el`).

**One limit is stated, not hidden.** The service placement reaches the
person's buffers only through the bridge, and the bridge is off until the
operator turns it on: the check proves the bridge tools are absent from the
registry until they are asked for.  The bridge itself is verified against a
live Emacs server by `tests/checks/check-bridge-live-server.el` (a real
daemon, a live buffer read including an edit made after the first read, an
evaluation, the unavailable-server case, and the registry round trip).  The
channel question is answered there: `emacsclient --eval` request/answer is
sufficient for what the bridge does today; a persistent connection would
only matter for streaming live buffer state, which the bridge does not do.

### Work items

- Move session registry, policy, cancellation and configuration into run
  contexts;
- attached placement with nonblocking interactive behavior;
- service placement in a dedicated Emacs with lifecycle management;
- batch entry for CI/benchmarks with explicit headless allowlists;
- emacsclient bridge to a person's buffers as a separately approved tool;
- **the bridge verified against a live Emacs server.**  **Implemented on
  2026-11-12:** `tests/checks/check-bridge-live-server.el` starts a real
  daemon, reads a live buffer (including an edit made after the first
  read), evaluates in it, reports an absent server instead of hanging,
  and proves the bridge tools stay out of the registry until the operator
  asks for them.  The channel question is answered: `emacsclient --eval'
  request/answer is sufficient for what the bridge does today; a
  persistent connection would only matter for streaming live buffer state,
  which the bridge does not do;
- **concurrent sessions in one service Emacs.**  **Implemented on
  2026-11-12:** `tests/checks/check-concurrent-sessions.el` runs two
  sessions at once in one Emacs on two run contexts whose fake transports
  wait on timers, so the runs interleave; the journals are compared for
  cross-talk, both runs reach a terminal state, and cancelling one run
  leaves the other to finish.  The control — two runs sharing one session
  — makes the check report the cross-talk, so the check is real.  The tool
  registry is the run's own: a run starts from a snapshot and a tool one
  run registers is not advertised to another run (proven by
  `tests/checks/check-run-registries.el`).  Sessions, permissions,
  cancellation, budgets and tools are the run context's own;
- **bounded CPU work inside the agent Emacs.**  **Implemented on
  2026-11-12:** measured first — JSON encoding of a large tool result is
  one C call (23 ms for 5 MiB), a journal projection over 1000 events is
  1 ms, and the only real hotspot was token estimation: a per-character
  Lisp walk took 3.1 s for 10 MiB.  It is now counted with `how-many' (C
  speed): 10 MiB of Latin text is 0.05 s and the estimate is unchanged
  for every input the unit tests name.  CJK-heavy text is still
  per-match, but a 10 MiB CJK context is far past the compaction budget,
  so the realistic worst case is bounded.  `tests/checks/
  check-runtime-stays-responsive.el' proves a 100 ms timer fires on time
  while a 10 MiB estimate runs, and it fails against the per-character
  implementation (the timer fires 3.4 s late);
- canonical event comparison across placements, excluding timestamps/random
  ids and explicitly transport-specific metadata.

### Exit criteria

The same scripted task produces equivalent semantic events in all three
placements. Service cannot access attached buffers without the bridge
capability. Batch returns a useful exit code and durable journal.

The first two are **closed by the check**; the third is **partly open**: the
bridge is checked against a live Emacs server (a real daemon), not only a
stub, and the channel question is answered — but a real person's Emacs in
day-to-day use has not yet been served this way.

## 10. Stage 7 — declarative delegation and ecosystem

### Intent

Implement the Y in Yeah: bounded, inspectable recursive work.

**Status: implemented offline on 2026-11-12.** `lib/yeah-agent.el` reads an
agent preset from a file: a header with a name, a description, a model, the
tools it may use and a depth, and a body that is the prompt. Both the
Markdown header (`---` … `---`) and the Org header (`#+NAME:` …) are
understood. Listing the presets reads the headers only; the body is read
when a preset is used. `lib/yeah-subagent.el` is no longer a stub: a child
runs a real turn in its own session, with its own context and its own
permissions, and a tool it was not granted is refused by the rules of the
child — the refusal is in the child journal, where the parent can read it.
The lineage is in the names (`<parent>.sub-<n>`), the parent is told what
happened (`spawn` and `child-end` events in the parent journal), the depth
is bounded, and a child can be cancelled together with everything it
spawned.

**Not yet done:** the fixed-point demonstration (Yeah diagnoses and repairs
a Yeah canary), Org TODO projection and session export, parallel
independent children, and the cheaper child model. The preset carries a
model name, but nothing selects it yet.

### Work items

- Markdown/Org agent presets with name, description, model, tools and prompt;
- agentskills.io-compatible discovery and progressive loading;
- child run contexts with restricted tools, depth and shared budgets;
- parent/child event lineage and child summaries backed by inspectable events;
- optional cheaper child model and parallel independent children;
- Org TODO plan projection and Org session export;
- fixed-point demonstration: Yeah diagnoses and repairs a Yeah canary, runs
  tests, reviews the diff and prepares a Magit commit under approval.

### Exit criteria

A parent can delegate two independent tasks, inspect their actual work,
cancel the subtree and recover within budget. A child cannot exceed its
granted capabilities or spawn beyond its declared depth.

**Verified on 2026-11-12:** two children run at the same time, the parent is
told what they did, a child may only use the tools it was granted, and a
spawn past the depth limit is refused.  The fixed-point demonstration is
verified with a real model (with retries).

The capabilities and the depth are **closed by the tests**: a child may only
use what it was granted, and a spawn past the depth limit is refused. The
two independent tasks, the cancellation of a whole subtree and the recovery
within budget are **partly open**: the cancellation of a child is tested,
the cancellation of a subtree and the budget of a parent are not.

## 11. Continuous quality and 1.0 release gates

### Benchmark suites

1. **General coding:** identical initial repositories, tasks, model and
   budgets for Yeah/opencode/pi; score verified task success, time, tokens,
   cost and human interventions.  Yeah runs the benchmark in its primary
   deployment — a service Emacs driven through ACP — because that is the
   configuration the comparison claims parity for.
2. **Emacs-native:** live buffers, Eglot, Magit, Org and introspection tasks;
   these test the architectural advantage, not just parity.
3. **Robustness:** long sessions, network failures, duplicate callbacks,
   malformed data, cancellation, crash/restart and output floods.
4. **Fixed point:** the Yeah-on-Yeah canary repair with a reviewable result.

### 1.0 requires

- stages 0–7 closed by current claims and controls;
- clean installation and the interactive vertical slice passing on every
  supported Emacs/gptel combination;
- the primary deployment path (§2) working end to end: a service Emacs
  driven through ACP by a third-party client, with a preempting cancel,
  concurrent sessions and a live bridge to the person's attached Emacs;
- no known security-boundary bypass or public placeholder path;
- durable recovery and cancellation integration tests passing;
- benchmark results published with methodology, including losses;
- README limitations, security/privacy guide, architecture, engineering
  guidance and user documentation current;
- package checks clean and a versioned release with migration policy.

## 12. Immediate execution order

Stages 0–7 are implemented offline.  Under the primary-deployment decision
(§2) the remaining distance to a usable product closes in this order:

1. ~~close the public alpha gate~~ **done on 2026-11-13**: the layout fix
   is pushed and `tests/live/live-clean-install.el` passes against the
   published repository (v0.1.0 is the public alpha);
2. ~~a cancel that preempts a running prompt~~ **done on 2026-11-12**:
   the socket transport serves connections concurrently and a cancel
   arrives while the prompt is running; stdio keeps its documented limit
   (Stage 5);
3. ~~a third-party ACP client driving the wire end to end~~ **partly done
   on 2026-11-12**: acp.el drives the wire end to end with a fake model
   (and the check found a real defect); a real editor against a live
   provider is open (Stage 5). **The service path itself passed with a
   live model on 2026-11-13** (tests/live/live-service-path.el: clean
   service, wire-approved write, file created; one intermittent
   provider-side refusal recorded);
4. ~~the bridge verified against a live Emacs server~~ **done on
   2026-11-12** (a real daemon; the channel question is answered) (Stage 6);
5. ~~concurrent sessions in one service Emacs~~ **done on 2026-11-12**:
   two sessions in one Emacs are checked for cross-talk, and cancellation
   of one run leaves the other (Stage 6);
6. ~~bounded CPU work inside the agent Emacs~~ **done on 2026-11-12**:
   measured first; the only hotspot was token estimation, now counted at
   C speed, and a canary proves the event loop stays responsive (Stage 6);
7. ~~the math-coding v5 migration~~ **done on 2026-11-12**: the standing
   specification is v5, the focused claims hold with controls that bite,
   and map/run/gate work with the installed v5 binary (Stage 0.4).

Each implementation commit should be small enough to review and should
include its tests, control and documentation update.

## 13. Decisions still requiring product ownership

These are not implementation details for an agent to decide silently:

- exact minimum Emacs/gptel versions and release cadence;
- default unattended capabilities and command/network policy;
- whether restricted evaluation deserves a separate process design at all;
- service-mode access to personal buffers;
- package distribution channels (MELPA/ELPA/bootstrap) and signing;
- final benchmark task set and acceptable parity threshold;
- whether Apache-2.0 remains compatible with every optional integration.

Decided on 2026-11-12:

- **`M-x yeah` defaults to the service placement**: it spawns or connects to
  a service Emacs and reaches it through the bridge, so the editor never
  shares a thread with a long turn.  The attached placement remains the
  demo and development path.  The installation flow gains a
  service-startup path.
- The bridge stays **off by default** until the operator turns it on (a
  capability, not a convenience).
- The alpha distribution stays **bootstrap-first** (package-vc, pinned
  gptel); MELPA comes later, when the API settles.
- PTC stays an **experimental, off-by-default** restricted evaluator with
  no new investment; no separate-process sandbox is designed now.

## 14. Integration with the parallel Emacs UX work

### State of the parallel work (as of 2026-11-14)

The parallel work has been consolidated into one integration branch:

| branch | worktree | state | content |
|---|---|---|---|
| `feat/emacs-ux-v3` | `yeah-emacs-ux-v3` | **active integration line** | current `main`, semantic faces, stable event correlation, the pure view model, the shared journal and composer, the attached driver, the service driver, and repaired evidence controls |
| `ux/service-driver` | `yeah-ux-service-driver` | **committed reference** | the service-through-journal change merged into the integration line |
| older `feat/emacs-ux*` and `ux/*` branches | their worktrees | **superseded reference** | earlier pre-UX-base attempts; retained until their owners approve cleanup |

`main` remains untouched.  The integration branch is green with 319 ERT
tests, 46 direct canaries and a math-coding v5 verdict of green for all 55
declared claims.  Three UX claims were added with controls independently
shown to change their subject and fail their verifier by assertion.

### The decisions this integration needs

**14.1 Evidence repair came first.**  Four stale controls now mutate the
subject they claim to cover: an explicit `allow-once' is the only wire
answer that permits an effect, a finished tool is rendered as finished, the
independent ACP client is found outside the isolated checkout, and an
`always' approval is stored as a rule.  A fifth repair made the git canary
wait for the final output callback before reading `git log'.  The controls
that previously reached nothing now bite; a direct verifier failure is
distinct from a blocked or unreadable check.

**14.2 One canonical event and view model.**  New events carry explicit
run, turn, tool-call and parent ids.  `yeah-ui-view` correlates parallel
same-name calls and their approvals by stable id and marks ambiguous legacy
records unknown instead of guessing.  The model-facing and person-facing
paths therefore read one truth.

**14.3 One journal and one composer.**  `lib/yeah-journal.el` owns the
read-only, outline-structured transcript and its incremental updates.  It
preserves the reader's point and window position, replaces only the block
that changed, and exposes a header derived from the same view.  Semantic
faces inherit the active theme; `nerd-icons' is optional decoration and
every state keeps readable text.  `lib/yeah-compose.el` owns the separate
multiline prompt buffer, bounded history and explicit context.

**14.4 Attached and service use that journal.**  `lib/yeah-product.el` is
the attached driver; `lib/yeah-service-ui.el` projects the ACP stream into
the same records and uses the same journal and composer.  The local
duplicate of the user's prompt is gone, tool calls keep the same
`toolCallId` from start to completion, the service prompt callback keeps
its buffer-local state, and a service permission question is visible in
the journal before its answer is sent.  A canary drives the attached path
with a fake model and the service path through a real Emacs process and a
real client connection, then compares the two transcripts.

**14.5 The three UX claims are explicit.**  `ux-correlates-tools-by-stable-id`
covers stable correlation; `ux-journal-preserves-reading-and-text` covers
incremental reading position and textual fallback; and
`ux-attached-and-service-share-the-journal` covers the two placements.
Each has a verifier and a control that reaches its scoped subject.

**14.6 Optional presentation packages stay optional.**  `nerd-icons' is
loaded only when available and displayable; its absence is not an error.
`markdown-mode' is an optional fontifier and plain text remains a complete
baseline.  `transient' is bundled with the supported Emacs and supplies the
journal menu; it introduces no package-install requirement of its own.

**14.7 The division of labour is now explicit.**  `yeah-journal.el` owns the
transcript and navigation, `yeah-ui.el` owns the pure projection,
`yeah-product.el` owns attached actions, `yeah-service-ui.el` owns the
service connection and maps its protocol replies into the journal, and
`yeah-compose.el` owns prompt composition.  `yeah-approval-ui.el` and
`yeah-diff.el` own the standalone approval and preview surfaces.  The last
two are not yet the single wired question for both placements: attached and
service still use their smaller prompts.  That gap is explicit rather than
hidden behind a second transcript.

**14.7a Supervision is model-dependent.**  The live interactive path was
re-checked on 2026-11-14 after the UX wave.  With MiniMax-M2.7 the whole
scenario passes: the model fixes the file, the run is cancelled, the
session survives a quit and a restart, and a pending input is recovered.
With MiniMax-M3.1-Flash the same scenario ends with the file unfixed: the
model answers with a plan, the completion nudge is sent, the model narrates
again, and the run ends without the effect.  The nudge is therefore a
prompt, not a guarantee; the next step is a second-stage nudge that names
the exact call to make, or a decision to require an explicit action before
the run may end.

**14.8 The remaining product work is parity, not decoration.**  `M-x yeah'
still opens the attached placement.  Before service becomes the default,
the service path needs session replay, steering, pending-input
withdrawal/recovery and mode parity.  The shared approval view and full
`diff-mode' preview must replace the smaller prompts.  After the owner
merges the integration line, the live attached and service paths must run
again with provider credentials, followed by the published-repository clean
install.  Superseded worktrees are removed only after their content is
confirmed present in the merged line.

### Exit criteria for this section

- the integration branch byte-compiles cleanly; all 319 ERT tests and all 46
  direct canaries pass;
- `mathc run` is green, every declared control bites, and the three UX
  claims hold;
- attached and service show the same question, answer and terminal state in
  one read-only journal;
- the clean install against the published repository passes after the
  owner merges the line;
- the live interactive and service paths pass with a real model when
  credentials are available;
- the service-default switch waits for session/queue/mode parity and the
  one shared approval view is wired.

Re-opened when a person says so: the math-coding aim block in AGENTS.md is
written by `mathc install` and is not edited by hand.
