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

Verified on 2026-11-15 on `main` (the numbers of 2026-11-14 in the integration
branch were 319/319, 46 and 55):

- all 53 Elisp files under `lib/` byte-compile without warnings;
- 358/358 ERT unit tests pass;
- all 53 canaries pass when run directly (`./scripts/dev check tests/checks/*`);
- the installed math-coding v5 tool runs the standing specification: all 74
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
   published repository (v0.2.0 carries the Emacs-native interface);
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

## 15. What the UX wave left open

The Emacs-native interface merged on 2026-11-14 (v0.2.0).  A critical look at
the result, checked against the code, leaves five things that the release
papered over.

### 15.1 The `unfinished' event is written and never shown — **done on 2026-11-14**

The turn writes an `unfinished' event when a supervised run spends its
nudge budget without the model finishing (the vocabulary declares it, the
turn writes it).  `lib/yeah-ui.el' has no branch for it: the record falls
into the generic block, and the run keeps the state of its last narration.
The person sees a transcript that simply stops.  The point of the event is
that the person sees it.

**Work:** a branch for `unfinished' in the view model — its own block, its
own state in the status line (`unfinished', not `running' and not
`completed'), and the reason in the text.  A unit test that a run which
ends without the effect shows `unfinished' and never `completed'.  A claim
`unfinished-is-visible' with a control that removes the branch.

**Done on 2026-11-14:** the view says `unfinished', the journal shows the
reason, the service path no longer calls a refusal a finish, and the
claim `unfinished-is-visible' has a control that bites.

### 15.2 Eight new modules, three claims — **done on 2026-11-14**

`lib/yeah-faces.el`, `lib/yeah-journal.el`, `lib/yeah-markdown.el`,
`lib/yeah-compose.el`, `lib/yeah-diff.el`, `lib/yeah-approval-ui.el',
`lib/yeah-doctor-ui.el' and `lib/yeah-session-list.el' are 1745 lines of
new surface.  Three claims cover them (correlation, reading position, one
journal for both paths).  The composer, the diff preview, the approval
view, the doctor and the session list have no claim of their own.

**Work:** one claim per surface that a person can reach, each with a
verifier and a control that bites: the composer (a multiline answer
becomes one prompt), the diff preview (an edit shows what it would
change), the session list (a session is found and opened), the doctor
(it reports what it checked).

**Done on 2026-11-14:** five claims were added with controls that bite —
`compose-sends-one-prompt-with-its-context',
`diff-previews-a-change-without-touching-the-file',
`doctor-ui-reports-checks-without-leaking-secrets',
`session-list-shows-and-opens-a-project-session' and
`markdown-fontifies-only-face-properties'.  The claim of the approval
surface was wider than its own verifier: a new test now asks both paths
and fails when one of them stops asking in the view.

### 15.3 The approval view is an orphan — **done on 2026-11-14**

`lib/yeah-approval-ui.el' is required by nobody.  The question of the
permission is asked in `lib/yeah-service-ui.el' (the wire path) and in the
smaller prompts of the attached path, so the product has two places that
answer the same question.

**Work:** decide, then do one of the two: wire the approval view into
both paths and drop the duplicates, or delete the module and keep the
prompts.  The recommendation is to wire it: it is written and tested, and
the plan of the interface already asks for one approval surface.

**Done on 2026-11-14:** the view was wired into both paths — the
attached path and the service path now open it, the one-key prompts are
gone, and the person answers there: once, always for this resource, or
reject.  The wire may answer `allow-always'.

### 15.4 The archived kernel work — **done on 2026-11-14**

`ux/archive-async-approval' holds work that is not in `main': safe reads
that run without a question, an approval that is answered asynchronously,
and a decision that is remembered.  It was written against the snapshot
before the wire permissions and the split of the batch dispatch, so it
cannot be merged as it is.

**Work:** rebase it onto the current kernel, resolve the conflict in
`lib/yeah-turn.el' by design (the preparation of a batch now has six
functions), and keep the parts that earn their place: a safe read needs no
question, and the wire answer may remember the decision.  The wire
answer of the client has `allow-once' and `reject-once' today; `always'
is what a person wants when they answer the same question twice.

**Done on 2026-11-14:** the work was brought over by hand — the safe read
answers itself with a reason (in the profile of a run and over the wire
alike), an answer of `always' becomes a rule of the run or of the session,
and the turn carries the reply of the person so that the journal shows it.
The claims `safe-reads-need-no-question' and
`always-is-remembered-for-the-session' hold.

### 15.5 Supervision believes the model

The nudge names the call and the run says it did not finish, but the run
still ends when the model says so.  A model that insists on talking can
still end the run with the work undone; the harness knows which tools ran
and could check the effect instead of the promise.

**Work:** a decision that belongs to a person: does a run need a criterion
of success (a check that must pass) before it may end?  If yes, the run
context grows a completion check, and `finish' is only one way to satisfy
it.

### 15.6 Smaller things that are true

- The live paths are outside the map: six files under `tests/live' and the
  fixtures are uncovered, so the green verdict of 58 claims does not speak
  for them.  They are run by hand, and the result belongs in the README.
- The socket transport has a TCP family, and the editor still asks for a
  Unix socket; on a platform without Unix sockets the service placement
  cannot start.  The family is a choice, not a constant.
- "One shared journal" is true; "one shared control" is not: the service
  path still has no replay of an old session and no parity of the pending
  input, the steering and the recovery.  The wording should say which is
  which.
- `M-x yeah' still opens the attached placement, and the decision that it
  should default to the service waits for that parity (Section 13).

### Exit criteria

- every surface a person can reach has a claim whose control bites;
- a run that ends without the effect says so where the person looks;
- the question of the permission is asked in one place;
- the README, the site and `docs/PLAN.md' say the same thing about what is
  shared and what is not.


## 16. The work after v0.3.0

v0.3.0 (2026-11-14) carries the Emacs-native interface and the permissions
the kernel asks about: a read that changes nothing is not asked about, an
answer of `always' is remembered, the question of the permission is asked
in one place, and a run that ended without the effect says so.  67 claims
hold, 331 ERT tests and 47 canaries pass, and both live paths pass with a
real model.

What follows is the distance to a product a person may keep using, and the
distance to measuring the parity the vision asks for.

**What has landed since (2026-11-15).**  16.1, 16.2, 16.3 and 16.4 are
implemented; the register of 16.5 and the apparatus of 16.7 are built; 16.6 is
done — the interface is photographed under a virtual frame server — and 16.8
is done.  The pilot of 16.7 is measured on three tasks with a live provider
and a second harness; the difference it found is a defect of one turn, and
the threshold is still a decision of the owner.  The wave is
`waves/wave-21.json', the review that started it is
`docs/REVIEW-2026-11-15.md', and the map holds 74 claims; 358 ERT tests and 53
canaries pass.  The review of the session that carried the wave, and the plan of
the work that follows it, are in `docs/PLAN-NEXT.md'.  The picture of the
interface is the wave `waves/wave-22.json'.

### 16.1 The answerer that answers later — **done on 2026-11-15**

The archived branch `ux/archive-async-approval' still holds one piece that
is not in `main': an answerer may be asynchronous.  The kernel asks a
question and gets the answer whenever it arrives; the request is journaled
*before* the question is asked, so a person (or another program) that
answers later still finds the request in the log; the adapter that takes
either shape of answerer is bounded and settles once.

**Work:** bring the two-argument answerer and the resolve-adapter over
(`yeah-approval-async', `yeah-approval-resolve'), make the request carry
the tool-call id and the normalized arguments, and journal the request
before the decision.  A claim `an-answer-may-come-later' with a control
that answers twice or answers after the run ended.

**What landed:** `yeah-approval-async' and `yeah-approval-resolve' are in
`lib/yeah-approval.el'; the prepare path of `lib/yeah-turn.el' writes the
`tool-request' and the `permission-request' before the answerer is asked, and
the answer settles the question exactly once — a second answer, an answer
after the run ended and a question that is not answered in time are all
refused with a reason.  Claim `an-answer-may-come-later' with the canary
`tests/checks/check-approval-answers-later.el'.

### 16.2 The service path with the whole control — **done on 2026-11-15**

The journal is shared by both paths; the control is not.  The attached
path asks, steers, cancels, withdraws a steering and recovers a pending
input; the service path asks and cancels.  The service has no replay of an
earlier session either.

**Work:** the wire grows the commands the person has: `session/steer',
`session/withdraw', `session/recover', and a `session/load' that replays
the journal into the editor's view.  The pending queue is a projection of
the journal events (`input-queued', `input-taken', `input-recovered', `input-withdrawn'),
not a second state.  Every command gets a claim and a canary.

**What landed:** the ACP session runs on the same controller as the attached
path (`lib/yeah-acp.el'), so the queue and its journal events are one truth;
the wire grew `session/steer', `session/withdraw', `session/recover' and a
`session/load' that replays the journal; the queue events reach the editor
as `session/update' notifications, and `lib/yeah-service-ui.el' projects them
and offers the same keys as the attached path.  Claims
`pending-queue-is-in-the-journal', `the-wire-carries-the-control' and
`the-service-carries-the-control'.

### 16.3 The service as the default entry — **done on 2026-11-15**

The decision of 2026-11-12 (`M-x yeah' defaults to the service placement)
waits for the parity of 16.2.  When it lands, `M-x yeah' spawns or
connects the service and drives it from the editor's buffer; the attached
placement stays as the development and fallback path, and the bridge stays
off until the operator turns it on.

**What landed:** `M-x yeah' opens the service placement and falls back to the
attached one, in the open, when the service cannot start; `yeah-attached'
opens the attached path by name.  Claim `yeah-opens-the-service'.

### 16.4 The platform without Unix sockets — **done on 2026-11-15**

The socket transport can serve a loopback TCP port, but the editor always
asks for a Unix socket, so the service placement cannot start where there
are none.

**Work:** the editor picks the family by platform and writes the port to a
file when it is not a socket path; a canary covers both families.

**What landed:** the family is chosen by the platform
(`lib/yeah-client.el'), the service publishes the port of a loopback TCP
socket in `<socket-path>.port' and removes the file when it stops, and the
Unix behaviour is unchanged.  Claim `the-editor-finds-the-service'.

### 16.5 Evidence that the method cannot hold — **the register is done on 2026-11-15**

The live paths need a provider, so no control can bite without one: the
six live tests and the UI fixtures stay outside the map, and the green
verdict of 74 claims does not speak for them.  Two ways out: a register of
evidence that has no claim, or a live environment the method can run in.
The first is ours to build; the second is infrastructure.

**What landed:** `docs/LIVE-EVIDENCE.md' says what each live check proves,
how to run it, when it was last recorded and what is still open; the README
points at it.  The live environment is still infrastructure, and nobody may
quote the green verdict of the map as if it covered these checks.

### 16.6 The picture with pixels — **done on 2026-11-15**

The structural smoke covers the terminal, the light and dark faces, the
Cyrillic text, the long output, the narrow header and the composer, but
no pixel of the real interface was ever looked at.

**Work:** a smoke under a virtual frame server, if one is available, that
renders the journal and the approval view and compares the picture with a
stored one.

**What landed:** `tests/pixel/` draws the journal and the approval view in
Emacs itself, in a terminal under a virtual frame server, and photographs
the screen with ImageMagick; `./scripts/dev pixel` compares the three
pictures with each other.  Nothing is compared with a stored picture: a
stored picture fails on every machine whose fonts differ, and a check that
fails for that reason teaches nobody anything.  What the comparison rules
out is a blank screen, a renderer that draws a heading and nothing else,
and an approval view that looks like the journal.  The check can fail: with
the renderer broken it fails with "the interface does not change the screen".

The check needs a frame server, a terminal emulator and ImageMagick, and no
provider key; it therefore lives outside the map, like the live checks, and
is registered in `docs/LIVE-EVIDENCE.md`.  A stored golden picture is still
open: it is a decision about the reference machine and its fonts, not a
technical obstacle.

### 16.7 The parity that is measured, not claimed — **the pilot is measured on 2026-11-15**

The vision asks for a harness competitive with opencode and pi, and the
documents say the parity is a goal to measure.

**Work:** a task set (ten tasks of the kind a person actually asks for:
read, edit, fix a failing test, write a file, answer a question) and a
runner that gives the same tasks to Yeah and to the other harnesses, with
the result recorded in the journal of the repository.  The acceptable
threshold is a decision of the owner (Section 13).

**What landed:** `bench/' holds the ten tasks, the manifest and the runner;
`./scripts/dev bench' proves that every task has a prompt and a check that
fails on an untouched workspace, and the runner records a harness that could
not run as `skipped' or `not-available', never as a pass.

**The pilot (2026-11-15).**  Three tasks — `read-answer',
`fix-failing-test', `write-new-file' — were given to Yeah and to pi with the
same provider, the same model (MiniMax-M2.7) and the same workspaces; the
result is in `bench/results/20261115T135915Z.jsonl' and in the register of
the live evidence.  pi passed all three; Yeah passed none of them.

That number is **not** a verdict about parity, and it must not be quoted as
one.  The threshold is a decision of the owner that has not been taken
(Section 13); three tasks are a sample, not a benchmark; and the difference
the pilot found is a defect of one turn, not a difference of quality between
the agents.  In every run of Yeah the model called the tools, the results of
the tools arrived, and the provider then answered with an **empty** message:
the turn took the empty answer as the end of the work and stopped without
the effect.  The live path of the kernel with the same key and the same
model passes (`tests/live/live-coding-task.el'), so the tools and the model
work; what does not work is the turn that has to notice that the model has
not advanced.

**The defect is fixed (2026-11-15, wave 24).**  The claim
`an-empty-answer-does-not-end-the-run` says that an answer which says
nothing is not a result: with supervision the model is nudged into the
action, the run writes the unfinished event when the budget of the nudges
is spent, and a run without supervision fails instead of ending as a
finished job.  Its control bites: with the silent-answer branch disabled
the two tests of the claim fail on real assertions.

**The pilot after the fix (2026-11-15).**  The same three tasks, the same
provider, the same model and the same workspaces
(`bench/results/20261115T142743Z.jsonl`): pi passed all three, Yeah passed
one — `write-new-file`.  The journals show that the provider answers with an
empty message after **every** batch of tool results, and that the model
answers the nudge by exploring again rather than by finishing the work.

**The nudge carries the state (2026-11-15, wave 25).**  The claim
`a-silence-nudge-carries-the-state-of-the-work' says that the nudge which
follows a silence names the tools the run already called and the results
they returned, and does not name an unused tool as the next call — a nudge
that says "call `read' now" after the model has read the file is what sent
the pilot round in circles.  Its control bites: with the state removed from
the nudge, the test of the claim fails and the other tests keep passing.

**The pilot after the nudge (2026-11-15).**  The same three tasks, the same
provider, the same model (`bench/results/20261115T144021Z.jsonl`): pi passed
all three, Yeah passed two — `read-answer` and `write-new-file`.  The third
fails in the tools, not in the turn: the `read` of a file nobody has edited
yet returns no tick, the model passes a plausible one, and the `edit`
refuses it as stale although the file has not changed.

**The pilot after the tick (2026-11-15, wave 26).**  The same three tasks
(`bench/results/20261115T150251Z.jsonl`): the task that the tick refused now
passes — `fix-failing-test` — and the two others were blocked by an overload
of the provider (HTTP 529).  pi passed all three.  The parity of that run is
not measured either: one task of three says that Yeah does what pi does on
it, and the two blocked tasks say nothing about either harness.

**The pilot after the turn learned to wait (2026-11-15, wave 28).**  The same
three tasks on the code of wave 28 (`bench/results/20261115T153957Z.jsonl`):
Yeah passed `read-answer` and `write-new-file`; `fix-failing-test` was
blocked, because the transport to the provider died ("Curl failed with exit
code 28"), so the run was not measured at all.  pi passed all three.  Two
tasks of three are measured for Yeah now, and both pass; the parity of the
run is still not measured, because the third task says nothing about either
harness.

**Open, for the next wave:** the threshold of the parity, which remains a
decision of the owner (Section 13).  The tick of a file — a model that has
no tick must not be punished for guessing one — is the subject of 16.9.

### 16.8 Housekeeping — **done on 2026-11-15**

- `ux/archive-async-approval' is deleted once 16.1 has landed and the
  archive holds nothing that `main' does not.
- `ux/archive-view-draft' is a stale snapshot of an earlier `main': it is
  reviewed the same way and deleted when it holds nothing that `main' does
  not.
- The evidence of the method is refreshed after the release commits, so
  the map is green rather than `outdated'.

**What landed:** both branches held nothing that `main' does not — the
asynchronous answerer and the two-phase prepare are in `main' now, the
session-rules owner of the archive is superseded by the rules of the session
in `lib/yeah-acp.el', and the rest is the older base of `lib/yeah-journal.el',
`lib/yeah-context.el' and `lib/yeah-ui.el'.  Both are deleted; their tips
stay reachable under the tags `archive/async-approval-2026-11-15' and
`archive/view-draft-2026-11-15'.

### 16.9 The tick that the model could not have read — **the tools are done on 2026-11-15 (wave 26)**

The third task of the pilot failed in the tools, and the journal says
which: the model edited a file with a tick it had not read, and the edit
was refused as stale although the file had not changed.  A tick is a
promise about the state the model saw, and only a buffer that visits the
file hands out a tick — the read of a file nobody has open returns none.
The number the model sends for such a file is a guess, and comparing a
guess with the counter of Emacs refuses an edit of an unchanged file.

The wave makes the guard compare only the ticks a read could have handed
out.  When no buffer visits the file, a guessed tick is ignored; when a
buffer visits it, the tick is compared as before and a stale tick is still
refused without a mutation.  The claim
`a-guessed-tick-does-not-refuse-an-unchanged-file' has a control that
bites: with the old comparison restored, the new test fails on a real
assertion and the other seven tests of the file keep passing.

**Open:** D5 promises that every read that can lead to an edit returns the
tick of the buffer, and the read of a file nobody has open returns no
tick, so the guard of such a file has nothing to compare.  The
contradiction is recorded in `docs/PLAN-NEXT.md' with the candidate of a
file version token that the edit can verify without a buffer; D5 stays the
target and is not weakened to fit the code.

### 16.10 A provider failure is not a failure of the agent — **done on 2026-11-15 (wave 27)**

The pilot of 14:55 reported Yeah 0/3 and pi 1/3 — and measured the provider:
HTTP 529 (the cluster was overloaded) answered both harnesses, and the runner
counted the runs as failures of the agents.  A pilot that reports a number
computed over an outage measures the day, not the parity.

The runner now reads the failure of the provider — from the journal of the run
for Yeah, from the output of the run for an external harness — and records
such a run as **blocked**: neither a pass nor a failure of the agent.  The
claim `a-provider-failure-is-not-a-failure-of-the-agent` has a control that
bites and that changes the subject and not the check: with the
classification of a blocked run turned into a failure, the self-check of the
task set fails with a real assertion.

### 16.11 A decision that arrives too early does not break the run — **done on 2026-11-15 (wave 28)**

The live check of 15:11 failed with two errors in the journal of the run:
`yeah-loop-tick: no transition from awaiting-tool on stream-end` and
`yeah-loop-tick: no transition from failed on tool-call`.  The run ended in
failed although the model was working.  The driver of the answer ticked the
machine as if every decision arrived while the machine was deciding; the
machine has no transition for a decision that arrives while the tools of the
previous decision are still running, and such a decision is ordinary: the
model asks for the next tool before the previous one has settled, and the
transport may deliver one decision twice.

The turn now keeps the calls that arrive too early and runs them when the
running batch has settled; the state of the machine stays `awaiting-tool'
until every batch has settled, and the model sees the results of all of them
together.  A call that is already running is not run again — a tool that runs
twice repeats its side effect.  The shape of the machine did not change: no
transition was added, and the counter of the transitions in
`tests/unit/test-yeah-loop.el' stays at 20.

Two claims carry the wave, and both have a control that bites and that
changes the subject and not the check.  With the state of the machine no
longer consulted, the decision that arrives too early is dispatched at once,
the machine ticks a transition it does not have, and the test of the wave
fails with a real assertion (the run ended in failed instead of completed)
while the other 26 tests of the file keep passing.  With the guard against
the repeated call removed, the probe of the second test runs twice and the
test fails on the count of the runs.

**Open:** the journal of a run says nothing about a decision that was dropped
as a duplicate, so a reader of the journal cannot tell it from a decision
that never came; the identity of the transport is not available to the
harness, and the wave compares the tool and its arguments instead.

### 16.12 An edit that lands on a file the model never read — **done on 2026-11-15 (wave 29)**

D5 promised that every read that can lead to an edit returns the state the
model saw, and wave 26 closed the half of that promise that a buffer can
carry: a tick exists only when a buffer visits the file.  A file that nobody
opened had no tick, so the read handed the model nothing to guard an edit
with, and the edit landed on whatever the file held at that moment.  The
contradiction was open work with a named candidate — a version token of the
file that the edit checks without a buffer — and wave 29 built it.

Every file has a version now: the digest of its bytes.  The read hands the
token out next to the tick, the model passes it to a later edit, and the edit
is refused when the file changed after the read; the refusal names the file
and reports the current version, so the model can reread and retry.  An edit
that presents a version is also refused when Emacs holds unsaved changes of
the file, because a read of the file on disk cannot show them.

The token is the digest of the bytes and not of a decoded text: the file with
the bytes `C3 A9` and the file with the single byte `E9` have two different
tokens, and the token of a file with CRLF is the digest of the file with CRLF.
The read and the edit compute the token by the same function of the same
bytes, so a guarded edit of an unchanged file is not refused by mistake.

D5 was amended and not weakened: it names the version as the second form of
the state that a read returns, and it says that a presented tick or version
that is no longer current is refused, while a state that no read handed out
is ignored.

The claim of the wave has a control that bites and that changes the subject
and not the check: with the comparison of the versions removed, the stale
edit is applied and the test fails on a real assertion, while the other ten
tests of the file keep passing.

**Open:** the read shows the file on disk while the tick of that read
describes the buffer that visits the file, so a model that presents only a
tick can still edit a buffer it never saw; the write tool overwrites a whole
file and takes no version, so a write can land on a file that changed.

### 16.13 A decision that was dropped as a repeat — **done on 2026-11-15 (wave 30)**

The journal is the source of truth of a run, and wave 28 made the turn ignore
a repeated tool call instead of running it twice.  The consequence of that
decision was invisible: the drop was written nowhere, so the log of a run in
which the model said the same thing twice looked exactly like the log of a run
in which the model said it once, and a reader of the log could not tell a
repeated decision from a decision that never came.

The drop is in the journal now.  The vocabulary of the journal gains the event
`tool-dropped', which carries the tool that was dropped, the reason it was
dropped ("the same call is already running") and the arguments of the dropped
call.  The arguments of a repeated call are the arguments of the call that
runs, and they are written in the form the request of that call was written,
so a reader of the journal matches the drop with the request it refuses.  The
event does not close the activity of the call that is still running, so the
person reading the journal sees the running tool and the refusal at the same
time.

The wave does not change the drop itself: the tool still runs once, and the
model is not told that its repetition was refused, because a tool that runs
twice would repeat its side effect.

D1 was amended and not weakened: the vocabulary it names now includes dropped
calls.

The claim of the wave has a control that bites and that changes the subject
and not the check: with the writing of the drop removed, the tool still runs
once and the run still ends, and the test fails on a real assertion because
the journal of the run holds no `tool-dropped' record, while the other 27
tests of the file keep passing.  The first form of the control was wrong and
was replaced: it made the guard of the drop unconditional, so the drop was
written every time and the check could not fail.

**Open:** the model is not told that its repetition was refused, so it may
repeat the call again; the identity of a call is still the tool and its
arguments, because the transport offers no identity of its own.

### 16.14 The checks read the journals and not the lock files next to them — **done on 2026-11-15 (wave 31)**

The verdict of the method on the code of wave 30 was `unknown', and the reason
was not the wave: the check of the standing permissions ended with exit 255.
Emacs aborted with `file-missing' instead of the check failing on its own
assertion, and the method reads a crashed verifier as an error and not as a
proven control, so the claim came out `inconclusive' while every other claim of
the run was `pass'.

The check read every file of the data home whose name ends in `.jsonl'.  Emacs
leaves the lock file of a journal next to the journal itself while a process
holds it open.  The lock file is not a journal: it carries no record, it exists
only while the file is held, and it disappears without a warning.  The check
caught one between the scan of the directory and the read of the file, and the
read of a file that was gone aborted Emacs.

The rule was known in the project and two of the checks followed it
(`tests/live/live-service-path.el' and
`tests/checks/check-client-disconnect-during-permission.el' skip the files whose
name starts with `.#'); the other checks did not.  There is one reader of the
journals now (`tests/support/yeah-journal-files.el'): it skips the lock files
and it survives a file that vanishes between the scan and the read, so that a
check fails on its assertion and not on the filesystem.

Measured: the lock file appeared in the scan of the check two to four times
per run on the code of wave 30 and not once on the code of wave 29 — the change
of wave 30, where the drop no longer closes the activity of the call that
still runs, keeps the client reading the journal while the service still holds
it.  With the reader of the journals the control of the claim of the standing
permissions ends with exit 1 and the assertion "the granted permission did not
reach the service", which is a real assertion and not a crash.

The wave changes the checks and not the product: nothing in `lib/' moves, and
the claim of the standing permissions keeps its meaning.  The reader has no
claim of its own: that claim was already in the specification, and what the
wave does is to make its control provable instead of crashed.

**Open:** a journal that is written while it is read can still be read
half-written; the wave does not make that race impossible, and the checks that
wait for an event wait until they find it.

### 16.15 A version token a model can copy back — **done on 2026-11-15 (wave 32)**

The pilot of 17:06 measured the copy of the version token, and it found a
defect that the unit tests could not see.  The model read `calc.el` and
received the token of the file, the digest of its bytes: 64 characters of
hex.  It presented a token of 58 characters — the same digest with six
characters lost in the middle — and the edit refused it, because a token
that is not the version of the file now is refused.  That refusal was right.

The file had not changed.  The sha256 of the file on disk was and remained
`fe26cedb46546a55777dfddb00efcb86c41135cb25811737952f8388e5b0e165`, the very
digest the read had handed out, and the token that the model presented was
`fe26cedb46546a55777dfddb06c41135cb25811737952f8388e5b0e165`.  The guard of
wave 29 did its work; the defect was in the token and in the diagnosis of the
refusal.  A token of 64 characters of hex is too many for a model to copy
back unchanged, and a refusal that says "the file changed since the read"
sends the model looking for a change that did not happen.

The token is short now: twelve characters of the digest, 48 bits, enough to
tell two states of a file apart.  The refusal of a token that does not match
names the token and not the file — "the file may be unchanged and the token
may have been copied wrong" — and it reports the current token of the file,
so that the model can retry with it, and the retry lands.  The description of
the edit tool and of the read tool say the same thing: copy the token as it
is.

D5 was amended and not weakened: it names the short token and the honest
refusal, and the promise of the guard — an edit never lands on a file the
model did not read — is kept.

The two claims of the wave have verifiers of their own and controls that
bite and that change the subject and not the check: with the whole digest
handed out again, exactly one test of `tests/unit/test-yeah-version.el` fails
(the length of the token) and the other two keep passing; with the old
sentence put back into the refusal, exactly one test of
`tests/unit/test-yeah-version-guard.el` fails.  The control of wave 29 still
bites on this code: it fails exactly one test of `tests/unit/test-yeah-edit.el`,
the test of the stale version, and the new tests are not in the file it reads.

**Open:** a model can still lose a character of twelve, and the harness
cannot make the model retry; the path that presents only a tick keeps the old
behaviour, and the write tool overwrites a whole file and takes no token.

### 16.16 An edit never lands on a file the model did not read — **done on 2026-11-15 (wave 33)**

The open work of §16.12 had two parts, and both were promises that D5 already
made and the code did not keep.

The first: D5 says that the agent "does not edit a file whose unsaved changes
in the editor a read cannot show", and the code refused that edit only when
the model presented a version.  A model that presented only a tick — the path
that wave 29 left open — could still land an edit on the buffer that holds
the unsaved changes of the person: the read showed the disk, the edit landed
on the buffer, and the changes of the person were overwritten with text the
model never read.  The refusal is now the answer of every edit, with a
version or without one.

The second: the write tool replaced a whole file and took no version, so a
write could land on a file that changed after the read of that file.  The
write takes the same short version token as the edit now, and a write that
replaces a file whose token does not match is refused with the current token,
so that the retry lands.

The order of the refusals is the order of their exactness: a stale version is
named first, a stale tick next, and the unsaved changes of the person when
nothing else is stale.  The meaning of the existing check of the stale tick
is unchanged, and the control of wave 29 still bites on this code: it fails
exactly one test of `tests/unit/test-yeah-edit.el`.

D5 was amended and not weakened: it says that the refusal of the unsaved
changes is the answer of every edit, and that the write of a whole file takes
the version too.

The two claims of the wave have verifiers of their own and controls that
bite and that change the subject and not the check: with the refusal of the
unsaved changes switched off, exactly one test of
`tests/unit/test-yeah-unsaved-guard.el` fails; with the version taken out of
the condition of the write, exactly one test of
`tests/unit/test-yeah-write-guard.el` fails and the test of the current
version keeps passing.

**Open:** the refusal does not tell whose changes the buffer holds, so with
`yeah-edit-save-after-edit` set to nil a second edit of the same file is
refused as well; a write of a file that Emacs holds unsaved changes of is
not refused, and the buffer of the person becomes stale.

### 16.17 An edit never runs the code of the project — **done on 2026-11-16 (wave 34)**

The open item of the table in `docs/PLAN-NEXT.md` §6: the edit tool opened
the file of the edit with `find-file-noselect` and nothing else, and Emacs
runs the local variables of a file and the directory-local variables of its
directory when it opens it.  That code belongs to the project, and the
project is untrusted input.

The two vectors are sharp.  A `mode:` entry of the local variables names a
function that Emacs calls when it sets the mode, and the name may be a
function of the project.  An `eval:` entry is Elisp that Emacs evaluates.
The directory-local file (`.dir-locals.el`) puts the same code into every
file of a directory, and the directory is chosen by the project, not by the
person.

The new module `lib/yeah-untrusted.el` opens a file with that machinery
neutralized: `enable-local-variables`, `enable-local-eval` and
`enable-dir-local-variables` are bound to nil for the opening, so neither
the local variables of the file nor the directory-local variables of its
directory are executed, whatever the configuration of that Emacs is.  The
edit tool opens the file of an edit through it.

What is left is the choice of Emacs: the major mode of the buffer comes
from the name of the file (`auto-mode-alist`), and that is Emacs' code, not
the code of the project.  The mode line of the file is part of the content
of the file, so it is ignored: a file whose mode differs from the mode of
its name comes up in the mode of its name.

§8 of `docs/ARCHITECTURE.md` was amended and not weakened: it now says that
the harness does not run the code of the project, and the price of that —
the mode line of the file is ignored — is named there and in the objection
of the wave.

The claim of the wave has a verifier of its own and a control that changes
the subject and not the check: with the guard switched off, exactly one
test of `tests/unit/test-yeah-untrusted.el` fails, and it fails on its
assertion that the mode of the file was not called.

**Open:** the buffer of the person shows the file in the mode of its name,
not in the mode that the file asks for, and the person has to set the mode
by hand; a file that the person opens by hand is still opened the way Emacs
opens it, and the harness does not change that.

### 16.18 A child agent runs on the preset that named it — **done on 2026-11-16 (wave 35)**

Stage 7 said that an agent preset is a file and that a child runs for real in
its own session with only the tools it was granted, and the fixed-point check
proved it with one child that a person wrote by hand.  But nothing in the
model-facing surface could ask for a child: the tool that hands a task to a
child did not exist, and the presets of the agents were files that only that
check read.  D8 named a sub-agent, and it did not name the way a parent model
reaches one.

The module `lib/yeah-delegate.el` closes that gap with two tools.  `delegate`
takes the name of an agent preset and a task; it starts a child in a session of
its own, through the machinery of the sub-agent, on the model of that preset,
with the tools of that preset, and with the system prompt of the preset: the
prelude of Yeah followed by the body of the preset.  Every tool outside the
preset is refused to the child, and the refusal is in the journal of the child.
`delegate-result` takes the id of a child and reports what became of it.

The parent is not held.  `delegate` answers at once with the id of the child —
the id of the session of that child — and the turn of the parent goes on while
the child works; the child answers on its own, later, and the journal of the
parent holds the `spawn` event and the `child-end` event.  The waiting is the
choice of the parent: it may ask for the result of the child when it wants it.

A delegation changes the world — a child of a plan would do the work that the
plan was supposed to forbid — so `delegate` is one of the tools that change the
world: the Plan profile denies it and the Build profile asks the person.  The
denial of the profile is what the journal of the run says, not the silence of an
absent person.

The wave has three claims, each with a verifier of its own and a control that
changes the subject of the claim and not the check.  With the model of the
preset taken away, exactly one test fails, and it fails on the model of the
child.  With the delegation made to wait for the child, exactly one test
fails, and it fails on the status of the children, which are done when the turn
of the parent is over.  With the delegation taken out of the tools that change
the world, exactly one test fails, and it fails on the reason of the refusal:
the Plan profile has no opinion about the delegation any more, and the run
refuses it because nobody answers, not because the profile forbids it.

**Open:** the id of a child is the id of its session, and the model has to copy
it into `delegate-result`; a copy that is wrong is refused by name, and the
model has to try again — the same trouble the version token of a read brought,
and it is not solved here.  The depth of the tree of the children is kept in a
table of the running Emacs and not in the journal, so a restart of the harness
forgets the depth of the children that are still running.  The tools of the
delegation are not in `yeah-builtins-specs` (the built-ins are the tools of the
kernel, and the delegation is a tool of the product), so a reader of that list
does not see them; the module registers them itself, the way the bridge does.

### 16.19 A delegation belongs to the run that asked for it — **done on 2026-11-16 (wave 36)**

The audit of wave 35 found a defect in the delegation, and the plan of wave 36
was wrong about one of its points.  The tool that delegates did not know the
journal of the run it belonged to: it remembered the sessions of the runs whose
calls were allowed and took the first of them.  Two runs that delegate at the
same time could give their children to each other, and a call that failed — a
`delegate-result` for a child that does not exist, a `delegate` with the wrong
number of arguments — left its session behind for the next delegation to take.
The defect was reproduced before it was fixed, and the test of this wave fails
on the code of wave 35 as well.

The fix is the thing the run already knows.  The run writes into a session, and
the turn holds that session; the turn binds it while it dispatches the call, and
the binding is over when the call is over (`lib/yeah-session.el`,
`lib/yeah-turn.el`).  A tool that acts on the world of the run reads the
session through `yeah-session-current` and writes into the journal of that
run.  A call that has no run has no journal: it is refused, and the refusal
names the truth instead of guessing.

The id of a child is short now.  The id of the session of a child is long — the
lineage of the sessions is in it — and a model that copies a long token loses a
character of it: the pilot of wave 35 copied 58 of the 64 characters of a
digest, and the edit of that file was refused.  The delegate tool answers with
a short id (`sub-1`, `sub-2`) that counts the children of the run, and the
model asks for the child by that id.  A wrong id is refused by name, and the
refusal names the children that do exist with their state, so that the model can
ask again.

A child has a time of its own.  The preset of an agent may name it (`timeout:
300`), and the default of the harness is 900 seconds; a child that ran out of
time is cancelled, and the parent is told that the child ran out of time.  A
child that never ends would keep the parent waiting for an answer that never
comes.

The wave has four claims, each with a verifier of its own and a control that
changes the subject of the claim and not the check.  With the delegate taking
the session of another run, exactly one test fails, and it fails on the spawn
that is in the wrong journal.  With the short id taken out of the lookup,
exactly one test fails, and it fails on the refused call of the model.  With
the children taken out of the refusal, exactly one test fails, and it fails on
the message.  With the time of the child taken away, exactly one test fails,
and it fails on the child that did not end.

**Open:** wave 37 closed the two points that were open here — the depth of the
tree of the children and the children of a run are in the journal now, and a
restart of the harness forgets neither.  What is still open: the tools of the
delegation are not in `yeah-builtins-specs` (the built-ins are the tools of the
kernel, and the delegation is a tool of the product), so a reader of that list
does not see them; the module registers them itself, the way the bridge does.
Several children in one turn of the parent work already — the audit proved it —
and the plan that said otherwise was wrong.

### 16.20 The tree of the children is in the journal — **done on 2026-11-16 (wave 37)**

The objection of wave 36 named what was still missing: the depth of the tree
of the children was kept in a table of the running Emacs and not in the
journal, so a restart of the harness forgot the children that still work and
the depth they stand at.

The tree belongs in the journal, and it is in two places.  The journal of the
run holds the short id of every child, the session of the child and the depth
of the child; the journal of the child holds where the child stands in the
tree — its parent, its depth and the id the model calls it by.  A harness that
starts again reads the tree from there.

What that buys is observable.  A child of a run is found after a restart by the
id that the model was given, and what became of it is told.  A child that the
journal holds no end of is not reported as a child that still works: the
restart ends the child as well, because the child runs in the same Emacs, and
the harness does not say that a child works when it does not.  And the depth of
a child is read from its own journal, so a child of depth one does not look
like a root after a restart: it is refused the delegation that would put the
grandchild at the depth two, when the agent of the child allows the depth one.

The wave has two claims, each with a verifier of its own and a control that
changes the subject of the claim and not the check.  With the children taken
out of the journal, exactly one test fails, and it fails on the refused call
of the model.  With the depth taken out of the journal, exactly one test
fails, and it fails on the delegation that was not refused.  Both tests fail
on the code of wave 36 as well: the defect was real, and the tests find it.

**Open:** a child that was running when the Emacs died is not brought back to
life: the journal says that the child was delegated and what became of it, and
the work of that child is lost, because nobody restarts it.  The tools of the
delegation are still not in `yeah-builtins-specs`.

### 16.21 The pilot names the shape of a run that did not finish — **done on 2026-11-16 (wave 38)**

The pilot of wave 37 measured a task of Yeah that failed, and the row of that
run in the results said only that the check exited 1.  The cause was in the
journal of the run and nowhere else: the record `unfinished` says that the
model answered with an empty message three times and that the run ended
without an effect.  A reader of the pilot saw a verdict and no cause.

Wave 38 makes the runner read that record and name the shape in the reason of
the row.  The reason of a run that did not finish begins with what the
journal of the run holds: the model answered with an empty message N times, or
it described its next step N times and called no tool.  The row still says
what the check said, and the two are read together.

The status of the row does not change, and that is deliberate.  Whether a run
that the provider silenced is a failure of the agent or a run that was never
measured is a decision of the owner (§17.2), and a runner that changed the
status would take that decision away.  The wave names the cause and leaves
the verdict alone.

The wave has one claim with a verifier of its own and a control that changes
the subject of the claim and not the check.  With the naming taken out of the
reason of the row, exactly one check fails, and it fails on the row that does
not name the shape.  The self-check of the bench still holds under that
control, so the two claims of the bench keep their evidence.  The check fails
on the code of wave 37 as well, with a message and not with a crash: the
runner of that code does not name the shape of a run that did not finish.

**Open:** the runner names the shape of a run of the Yeah harness, because
only that harness has a journal of Yeah; the row of the other harness says
what its own output says.  The shape is what the journal holds — the number of
the nudges, and whether the model answered with an empty message or described
its next step — and not why the model did it.

### 16.22 The kernel supervises a run by default — **done on 2026-11-16 (wave 39)**

The live run of the service path failed in a way that no offline check had caught:
the model was asked to write a file, it described its next step instead of taking
it, and the ACP route answered `end_turn` — the reason that says the work is
done.  Nothing had been done.  The cause was the default of the completion
supervision: `yeah-turn-default-max-nudges` was zero, so a run of the kernel was
not supervised at all and the branch that reports a run without an effect was
never reached.

Wave 39 changes the default to a positive budget (three — the number the live
coding task was measured with), so that a run of Yeah is supervised unless the
caller asks for no supervision at all.  The interactive path takes the same
number from the kernel now: `yeah-product-open` does not carry its own four.

The wave also changes the state of a run that spent its budget: such a run ends
in the state `failed`, and not in a state a reader of the wire would take for a
finished job.  The ACP route answers it with the stop reason `refusal`; the
batch placement exits with 1; a child of a delegation is marked failed.  The
journal of the run carries the record `unfinished` as before, and now the state
of the turn agrees with it.

The second part of the wave repairs the live stand of the transport.  The stand
stopped at the first line that arrived, and the empty string that a reasoning
model sends between its thinking and its answer was the absence of an answer: a
provider that had answered was reported as silent.  The stand now waits for a
terminal form, and the decision what counts as an answer lives in
`tests/support/yeah-live-answer.el`, where it is tested offline — a stand that
needs a key cannot be the test of its own decision.  Text with content and a
tool call are answers; the empty string, the streaming sentinel and the
reasoning are not.

**Open:** the budget of a child of a delegation is a separate default
(`yeah-subagent-max-nudges` is still zero), and the wave did not change it: a
child that never calls `finish` would then be marked failed, and the claims of
the delegation do not say that yet (§17.2).

### 16.23 The wire of Yeah speaks ACP — **done on 2026-11-16 (wave 40)**

The integration with Paseo exposed a defect of the wire that no offline check
had caught, because every offline check was written by the same hand as the
code and read the wire the way the code wrote it.  A client that validates
the wire refused every `session/update` of Yeah: the content of a chunk was an
array of content blocks where ACP says one block, and the events of the
pending queue (`input_queued`, `input_taken`, `input_recovered`,
`input_withdrawn`) travelled to every client although ACP has no such kinds.
The refusal was total — the text of the agent, the calls of its tools and the
state of its queue never reached the client, and the client saw a run without
a word.

Wave 40 repairs both shapes.

The content of a chunk is one content block.  The schema of the wire says so,
and the schema is the measure: `schemas/acp-v1.json` names the kinds of the
updates and the shape of their content, and the check reads the kinds from the
schema instead of repeating them.

The events of the queue are an extension of the wire and travel only where
they were asked for.  A client announces them in the `_meta` of its
capabilities at `initialize`, and a client that announces nothing is served
plain ACP.  The editor of Yeah announces them and sees the queue of the
session; the client of Paseo announces nothing and gets what ACP says.  The
name of the extension, the version of the protocol and the way the
announcement is read live in one file, `lib/yeah-acp-vocabulary.el`, which
both sides of Yeah require, so the two sides cannot drift apart.

The wave adds four claims: `the-wire-speaks-acp`,
`the-queue-events-travel-where-they-were-asked-for`,
`the-answer-of-the-agent-reaches-the-client` and
`a-tool-call-carries-its-input-and-its-output`.  Their controls were
run against the code of this wave and bit: the control of the first turns the
content of a chunk back into an array and the check fails on the assertion
that the chunk carries one block; the control of the second lets the queue
events travel to everybody and the check fails on the assertion that a client
which announced nothing received none; the control of the third renames the
kind of the finished run and the check fails on the assertion that the answer
of the agent reached the client; the control of the fourth takes the input of
the call away and the unit check fails on the assertion that the call carries
its arguments.

The second half of the wave answers the question the first half left open:
the shapes of the wire were right, and the text of the agent still did not
reach the client.  The reason was in the journal and not in the wire: the
model of the live task answered only with the call of the `finish` tool, and
the `finish` tool was not projected at all — the run ended, the journal
carried the summary of the run, and the client saw a `tool_call` without a
word of the answer in it.  A client that speaks ACP expects the words of the
agent as the message of the agent, so the summary of a finished run is
projected as `agent_message_chunk`.

The call of a tool carries what it was called with and what it returned:
`rawInput` holds the arguments and `rawOutput` holds the result.  The
journal holds the arguments in their printed form, because the journal is a
log of what happened and not a place for structured data, so the printed form
is read back into the values themselves — and, because the arguments come
from the model, the printed form is read as data and never as code: a form
that the reader of Emacs Lisp would evaluate is not read at all.

**Open:** the ACP method `session/set_mode` does not exist, the model of a
session cannot be changed over the wire, and the `mcpServers` of a session are
ignored (§17.1).  These are gaps of the surface, not of the wave.

The third part of the wave answers the question the second part left open.
The text of the agent reached the client — the live check in Paseo showed the
answer of the model in the timeline of the agent — and the words of it were
mojibake: `Emacs — это …` arrived as `Emacs Ð¼ ýÑ‚Ð¾ …`.  The journal of the
session held the right text, so the spoiling happened on the way out.

The cause was in the way the kernel writes to its standard output.  Emacs's
`json-serialize` returns a unibyte string whose bytes are UTF-8, and `princ`
of such a string does not write those bytes: Emacs reads every byte as a
character of Latin-1 and writes the characters back as UTF-8.  Every non-ASCII
answer was therefore written twice over, and a Russian agent looked like an
agent that wrote nonsense.  The wire of Yeah now writes the bytes of a message
as they are (`lib/yeah-wire.el`, `yeah-wire-print-line`), and both protocols
that write to a stream use it: ACP and MCP.

The wave adds a fifth claim: `the-text-on-the-wire-is-the-text-the-model-wrote`.
Its control removes the decoding and the check fails on the assertion that the
bytes of the answer are on the wire as they were written.  The check itself
(`tests/checks/check-wire-carries-the-text.el`) reads the bytes of a real
server process — not a character set, not a decoded string — because the
question is what a client reads from the wire.

**Open:** the working directory of a session (`cwd`) is still not applied to
the tools: in the live check the `bash` of the agent ran in the directory of
the process, not in the repository of the task (§17.1).

### 16.24 The harness lives — **done on 2026-11-17 (wave 45)**

The live test of Yeah against a real provider found four defects that no
offline check had seen.  Every offline check of the repository had been
written by the same hand as the code, and it read the tools of the harness
the way the code wrote them; the live test ran a real `bash` whose output
ended in a byte that is not text, a real provider that answered no summary,
and a real refusal that carried a whole conversation in it.

**The byte that killed the process.**  A `bash` tool whose output ends in a
byte that cannot be a part of a UTF-8 character — `tail -c 6000` cuts a
character of a file in half, and `printf '\262'` writes a byte that cannot
start one — took the whole Emacs process down: the refusal of JSON arrived
inside the sentinel of the process, where no handler of the turn stands, and
the run left no record of itself.  The exit code was 255 and the journal of
the run held neither the end of the tool nor the error.

The bytes arrive in two shapes, and the first version of the fix covered
only one of them.  A unibyte string holds bytes, and the bytes that are not
valid UTF-8 become the replacement character.  A multibyte string holds
characters, and the decoder of a process leaves the byte it refused *inside*
the string as a raw byte — a character whose code is at or above #x3FFF00.
That string is multibyte and is not text either, and JSON refuses it as
well.  The text of the harness is decided in one place now
(`lib/yeah-text.el`), and both shapes become the replacement character.
The check of the live path proves it end to end: a real child process runs
the real tool, the journal holds the record of the tool with the broken
byte replaced, and the process exits with the code 0.

**The journal never refuses a record.**  A record of a run can hold a value
that JSON cannot write.  The journal writes a stand-in that says so and
takes the records that follow: the journal is append-only, and a record
that cannot be written must not take the run down with it.

**An error of the harness does not escape into a sentinel.**  The answer of
an asynchronous tool arrives in the sentinel of its process, and the results
of a batch are recorded in the callback of the scheduler.  An error there
kills the Emacs process.  The scheduler turns such an error into a failed
tool, and the turn ends with a reason instead of dying.

**A run without a summary degrades.**  The context of a run overflows, and
the harness asks the model for a summary.  A provider that answers with an
empty message answers with no summary, and the run died of it, although the
summary is an economy and not a necessity.  The run now prunes the old
outputs of its tools, says in the journal that the summary did not arrive,
and goes on.  A second overflow without a summary ends the run, and then the
journal says why.

**The record of a failure is bounded.**  A provider that refused a request
hands the whole conversation of the run back inside the refusal: the record
of the failure of the second live run was 2.8 MB.  One record of the journal
is a record and not a transcript.  The reason that goes into the journal is
cut at two thousand characters, the fields that name the failure are kept,
and the place where the text was cut is said.

The wave adds five claims: `the-text-of-the-harness-is-always-text`,
`the-journal-never-refuses-a-record`,
`a-tool-that-returns-bytes-does-not-kill-the-harness`,
`a-run-degrades-when-the-summary-does-not-arrive` and
`the-record-of-a-failure-is-bounded`.  All five controls were run against
the code of this wave and bit, and each of them made its check fail by an
assertion of the check and not by a crash of Emacs.  The control of the
first removes the reading of the output of a tool; the control of the
second makes the journal raise instead of writing a stand-in; the control of
the third removes both readings of the broken bytes and the child process of
the check dies with the code 255, which is the live defect reproduced
offline; the control of the fourth makes the first failure of a summary end
the run; the control of the fifth removes the cut, and the record of the
failure holds 200031 characters.

The wave is numbered 45 and not 41: the waves 41 to 44 are the plan the
owner named on 2026-11-16 (§18), and that plan is not rewritten here.  The
wave was executed before them because the four waves of the plan need a
harness that lives to carry them.

**Open:** the working directory of a session (`cwd`) is still not applied to
the tools (§17.1), and the provider still answers a plan where an action
was asked for (docs/LIVE-EVIDENCE.md).

**The live coding run after this wave.**  The repaired harness was run
against a real provider with a real coding task: write a console calculator,
write its tests, run them, repair them if they fail, and finish through the
tool `finish`.  The model wrote the calculator (5 553 bytes), wrote its own
tests (4 699 bytes, fifteen where the task asked for eight), ran them, and
the run of the tests outside the harness says `OK` with the code 0.  The run
ended in the state `completed`, and the harness had to nudge the model three
times, because the provider answered with a plan where an action was asked
for.  The run is also the first live proof of the repair: one command of the
model (`head -c 3000` of the journal) cut a multibyte character in half, and
the journal of the run is valid UTF-8 from the first byte to the last.  Two
things the run did not do are written down in §17.1 and in
docs/LIVE-EVIDENCE.md: the model never called `finish` although the task
asked for it, and its last message announced a verification that never
happened ("All 15 tests pass.  Verifying the CLI end-to-end from a shell:"),
which the regexp of the plan does not recognise as a plan.

### 16.25 The noise of the provider does not end a run that works — **done on 2026-11-17 (wave 46)**

The live run of the wave 41 (the task of the owner, §18.1) was the first live
run of Yeah on the task of the owner, and it failed — but it failed for a reason
that the harness itself had made.  The journal of the run holds 17 calls of
tools: `read` eight times, `git_status` three times, `bash` three times, and
`glob`, `grep` and `todo_list` once each.  The model worked.  The provider
answered every batch of those results with an empty message, the harness read
that silence as the silence of a model that does not act, and the budget of the
nudges — eight — was spent on the noise of the provider.  The run ended in the
state `failed`, and its last record said:

> the model answered with an empty message 8 times and the run ended without an effect

Both halves of that sentence were false.  The run had an effect — seventeen
tools — and the model had not refused to act: it had acted, and the results
were in front of it.

**The budget of the nudges pays for the nudges that no effect answered.**  A
nudge that follows the silence of the provider *after* the tools of the model
have come back does not spend the budget: the model has acted
(`yeah-turn--acted-since-nudge-p` compares the calls of the run with the calls
it had when it last nudged).  A model that never acts still ends: the silence
that follows a silence spends the budget as before, and the run that spends it
says that it did not finish.  The deadline of the run and the deadline of the
request are untouched.

**The record of a run that did not finish is true.**  It names what the run did:
how many times the model answered with an empty message, how many times it
described its next step, and how many tools it called.  A run that called its
tools is no longer described as a run that ended without an effect
(`yeah-turn--unfinished-payload`).

The wave adds two claims:
`the-noise-of-the-provider-does-not-end-a-working-run` and
`the-record-of-a-run-that-did-not-finish-is-true`.  Both controls were run
against the code of this wave and bit, and each of them made the check fail by
an assertion of the check and not by a crash of Emacs.  The control of the
first makes the harness forget that the model acted, and the check fails on
three assertions: the run ended in the state `failed` instead of `completed`,
the journal holds an `unfinished` record, and the run was nudged twice instead
of more than twice — the live defect, reproduced offline and end to end.  The
control of the second makes every unfinished record claim that the run ended
without an effect, and the check fails on two assertions.

The wave is numbered 46 and not 42: the waves 41 to 44 are the plan of the
owner (§18), and that plan is not rewritten here.  The run that found this
defect was the run of the wave 41.

**The wave broke the control of an old claim, and the map of the method caught
it.**  The claim `nudge-only-for-plans` removed the condition
`(and (< (yeah-turn-nudges turn) (yeah-turn-max-nudges turn))' from
`lib/yeah-turn.el', and the wave replaced that condition with the count of the
nudges that were spent (`yeah-turn-nudge-spent').  The control of the claim
therefore changed nothing, the verifier of the claim passed with the subject
unchanged, and the claim went `inconclusive' — the verdict of the map was
`unknown' for that reason and for no other.  The control was written against
the code of the wave (it makes the condition of the spending branch
unreachable), and it bites again: four tests of `tests/unit/test-yeah-control.el'
fail on their own assertions.  An old control is a promise that the code it
names is still there, and a wave that renames a condition breaks that promise
without knowing it.

**Open:** the budget of the nudges is no longer a bound on the length of a run
(§17.1), and the working directory of a session (`cwd`) is still not applied to
the tools (§17.1).

### 16.26 The model is told what the run has done — **done on 2026-11-17 (wave 47)**

The live run of the wave 41 on the code of wave 46 (16:15 and 16:26) made 108
and 122 calls of tools and changed nothing in the repository: the model read
`AGENTS.md` six and seven times, read the claim of the wave 46 three and five
times, measured a race with experiments of its own in `/tmp`, and every answer
of the model was a plan ("I'll start by reading the repository rules").  The
reason is in the harness and not in the model.

**Every request of the harness starts a fresh conversation with the model.**
`yeah-turn--ask` hands the transport a prompt, and the prompt is all the model
is told.  The usage records of the third run show it plainly: the first
request of the run carried 4149 input tokens, and the last request, after 122
calls of tools, carried 919.  A conversation that grows with the work would
grow; this one does not grow at all.  The model is asked again and again with
nothing but the request, it cannot see what it has already done, and it starts
the task over.

The machinery of the context is not the cause: it exists, and it is not on the
road to the model.  `yeah-context-project` and `yeah-session-project` compute a
projection, the compaction and the pruning write their events into the
journal, and the projection itself never reaches a request.

**Every request now carries the transcript of the run.**  Before the prompt the
model is told what the run has done: the call it made, the result it got and
the answer it gave, and the words that keep the work where it is ("Do not
start the work over: continue from here.").  The transcript is a projection of
the journal, put together when the model is asked (`yeah-turn--transcript`), and
it is cut: twelve records of the run, and six hundred characters of the result
of a tool.  The first request of a run carries the request as it is, because a
run that has done nothing has nothing to tell.

**The transcript is a projection and not a second copy of the run.**  The
journal keeps the plain message it was written with; the projection is put
together on the way to the model.

The wave adds two claims: `the-model-is-told-what-the-run-has-done` and
`the-transcript-is-a-projection-and-not-a-second-copy-of-the-run`.  Both
controls were run against the code of this wave and bit, and each of them made
the check fail by an assertion of the check and not by a crash of Emacs.  The
control of the first takes the transcript out of the request, and the check
fails on four assertions; the control of the second writes the transcript into
the journal, and the check fails on one assertion.

**The check itself was wrong twice before it was right.**  The first version
collected the failures with the polarity reversed — `yeah-check--fail` reports
a failure when its argument is nil, and the checks handed it the negation of
the condition they wanted, so the check failed on a harness that worked and
would have passed on a harness that was broken.  The second version recorded
the prompts of the model into the parameter of the fake transport and not into
the variable of the caller, so the check saw an empty list of prompts and
could not tell a harness that asks the model from a harness that does not.
Both defects were found by reading the check against a direct reading of the
prompts in an Emacs that printed them.  A check that cannot fail is a comment,
and a check that fails when the harness is right is worse: it is a comment
that reads as a proof.

The wave also changed the code of the unit test of the control
(`tests/unit/test-yeah-control.el`): the prompt of a request now carries the
transcript, so the test looks for the prompt by its tail, which is the part
the harness does not change.

**The wave broke a check of the repository, and the map of the method caught
it.**  The check of the control of the wire
(`tests/checks/check-wire-control.el`) drives a server whose fake model answers
the prompt `again' and only that prompt, and it compared the prompt with
`(equal prompt "again")' — an exact comparison, which the transcript makes
false.  The prompt of the last request of that session therefore never
completed, and the check failed on its own assertion.  The fix was in the
check and not in the harness: the fake model now matches the prompt by its
tail.  A wave that changes the shape of the prompt breaks every check that
matched the prompt exactly, and the check has to be rewritten: the prompt of a
request is not a constant, and the part of it that the harness owns is the
tail.

**Open:** the transcript is not a context, and it is paid for again in every
request of a long run (§17.1); the projection of the context
(`lib/yeah-context.el`) is still not on the road to the model; the model of
the provider still answers with a plan instead of an action, and being told
what the run has done does not repair that shape (§17.1); the working
directory of a session (`cwd`) is still not applied to the tools (§17.1).

### 16.27 A request the provider dropped is asked again — **done on 2026-11-17 (wave 48)**

Three live runs of the wave 41 died the same way and for the same reason.  The
run of 16:15 died with `Curl failed with exit code 28` after 108 calls of
tools, the run of 16:26 with `Curl failed with exit code 16` after 122 calls,
and the run of 17:10 with `Curl failed with exit code 28` after 70 calls.
The transport to the provider died, and the harness took the death of the
transport for the end of the run: the work of the model was thrown away with
it, and the journal said that the run failed.

**The request never reached an answer.**  A provider that drops the
connection did not refuse the request: the words of the refusal and the words
of a dead transport are both "error", and the harness read them as the same
thing.  The wave tells them apart.

- A request that the provider dropped — the transport failed and there is no
  HTTP status — is asked again (`yeah-turn--retryable-p`,
  `yeah-turn--retry`).  The model is asked the same question, and the
  transcript of the run (wave 47) is in front of it, so the retry continues
  the work instead of starting it over.
- A provider that is busy (429, 500, 502, 503, 504, 529) did not answer
  either, and the request is asked again.
- A request that the provider refused (an HTTP status of the client, a
  refusal of the model) is an answer, and the run fails at once and says why.

The retry is bounded by a budget of its own (`yeah-turn-default-max-retries`,
two by default), and the budget is fresh again after every answer of the
provider.  A provider that drops every request therefore ends the run after
the budget is spent, with the reason in the journal.

**The status of the wire is read as a number.**  The transport of gptel
reports the HTTP status as a string (`"529"`, `"400"`), and a check of
`integerp` would never have seen a busy provider and never have told a
refusal from a request that was never answered (`yeah-turn--status-code`).

**The machine of the states does not move.**  The run was waiting for the
model and waits again: the retry is not a transition, the counter of the
twenty transitions of `lib/yeah-loop.el` is untouched, and the state of the
run is the state it had.

The journal holds the retry as a record of its own (`retry`, with the reason
the request was made again), and the transcript of the model names it in one
line (`[retry] the provider dropped the request: ...`).

The wave adds three claims: `a-dropped-request-is-asked-again`,
`a-refused-request-is-not-asked-again` and `the-retries-of-a-run-are-bounded`.
All three controls were run against the code of this wave and bit, and each
of them made the check fail by an assertion of the check and not by a crash
of Emacs: the first on twelve assertions, the second on two, the third on
four.

**The check itself was wrong twice before it was right, and the second
defect was a defect of the harness.**  The first version of the fake
provider played its script with `pop`, which changes the local variable of
the caller and not the list itself: the script repeated itself, the model was
asked the same request over and over, and the check measured a harness that
never stops — while the harness under test was a harness that did stop, so
the check failed on a harness that worked.  The second version read the
status of the wire as a number, which is the shape of no transport: in the
live harness a refusal of the provider would have been taken for a request
that was never answered and asked again.  The wave found that defect in the
harness while it was writing the check of the harness, and the check now
plays the real shape of the wire down to the string that carries the status.

**Open:** the retry repeats the whole request, so the tokens of the request
are paid for twice and a provider that is busy for a long time is asked again
and again until the budget is spent; a run that meets a provider that is down
still ends where it ended before, and the wave buys the runs that meet a
provider that dies once (§17.1); the shape of the provider that answers with
a plan instead of an action is not repaired by this wave (§17.1).

### 16.28 The compaction waits for the answer — **done on 2026-11-17 (wave 49)**

The live run of the wave 41 on the code of the waves 47 and 48 (the run of
2026-11-17 18:17, the journal `sessions/wave41e.jsonl`) died in the tools and
not in the provider.  The context of the run overflowed, the harness asked the
model for a summary of the conversation, and the provider that reasons answered
with its thinking first.  The compaction took the first piece for the answer:

- the record `compaction-failed` of id 2158 — the run degraded for nothing;
- the record `compaction` of id 2163 — the summary that came later committed a
  compaction and continued a run whose machine was in a state that has no such
  transition;
- the record `error` of id 2164 — `yeah-loop-tick: no transition from
  awaiting-tool on continue`, and three more errors after it.

**The compaction had to know what counts as an answer, and it could not know.**
The decision lived in a file of the tests (`tests/support/yeah-live-answer.el`),
where the kernel cannot reach it, and the compaction had its own idea of an
answer: a string that is not blank.  The thinking of a model is the road to the
answer, and the compaction took it for the end of the road.

The wave moves the decision into the kernel:

- `lib/yeah-answer.el` names the shapes of the provider (`none`, `empty`,
  `text`, `stream`, `reasoning`, `tool-call`, `tool-result`, `error`,
  `unknown`) and decides two things about them: what is an answer
  (`yeah-answer-answered-p`: text with content and a tool call) and what ends
  the request of the provider (`yeah-answer-end-p`: everything but the road to
  the answer).
- `yeah-context-summarize-async` waits for the answer of the provider and
  delivers the result of the request once.  A provider that thinks first and
  answers after its thinking gives the summary; a provider that ends the
  request without an answer gives no summary, and the run degrades and goes on
  as it did since wave 45.
- `yeah-compact-run-async` delivers the outcome of a compaction once.  A
  provider that answers the same request twice does not compact the context
  twice, and the second answer does not continue the run.
- The turn continues a run that the compaction answered only when the run is
  still compacting; a compaction that answers when the run has moved on leaves
  the summary in the journal and does not break the run.

`tests/support/yeah-live-answer.el` is a wrapper around the kernel now, and
the claim `the-live-stand-waits-for-an-answer` was amended and not rewritten:
its scope grows by `lib/yeah-answer.el` and its control moves with the
decision.

The wave adds two claims: `the-compaction-waits-for-an-answer` and
`the-outcome-of-a-compaction-arrives-once`.  Both controls were run against
the code of this wave and bit, and each of them made the check fail by an
assertion of the check and not by a crash of Emacs: the first on six
assertions, the second on three — among them the error of the live run,
`yeah-loop-tick: no transition from deciding on continue`.  The check was run
against the code of the wave before the wave as well, and it fails there on
seven assertions.

**Open:** the wait has no bound of its own, so a provider that thinks and then
says nothing leaves the run in the state `compacting` until the deadline of the
run cancels it; the turn waits for the answer of the model in the same way
(§17.1).  The decision of an answer is the decision of gptel, and a transport
that answers with shapes of its own ends the request without a summary.  The
compaction commits the first text that the provider sends, so a provider that
streams its answer in pieces gives a summary of its first piece; the harness
asks the model without streaming, and the wave does not change that.

### 16.29 Проверка провода решает свой вердикт по построению — **сделано 2026-11-18 (волна 50)**

Проверка провода была флаки, и причина была в самой проверке: `yeah-check--raw`
читала части провода через `nreverse`, который разворачивает список на месте и
оставляет переменную на ячейке, бывшей его головой.  Второе чтение провода
находило одну часть, а не провод, а проверка читает провод много раз (рукопожатие,
сессия, ответ агента и байты провода в конце), поэтому её вердикт зависел от
того, сколько раз она читала провод до этого.  Свидетельство, чей вердикт зависит
от порядка собственных чтений, нельзя прочитать.

Первая часть волны починила чтение: список читается, а не разворачивается на
месте, и строки режутся по байтам до декодирования.  Проверка даёт один и тот же
вердикт на двадцати прогонах подряд.  Вторая часть делает это claim'ом, а не
надеждой: новая проверка берёт контроль claim'а о тексте на проводе (декодирование
байтов UTF-8, взятых из провода) и гоняет проверку провода против него двадцать
раз подряд в копии репозитория.  Каждый из двадцати прогонов должен упасть на
утверждении самой проверки, и каждый должен упасть одинаково: один и тот же код
выхода и одни и те же слова.  Прогон, который вешает Emacs, прогон, который
проходит, и прогон, который падает по-другому, — все они проваливают новую
проверку.

Волна переносит ожидание проверки провода с равенства текста на конец хода:
равенство — это утверждение проверки, а не условие ожидания, а ожидание, которое
просит равенства, ждёт весь таймаут на каждом прогоне, который сломал контроль.
Из-за этой одной строки цикл из двадцати прогонов новой проверки стоит
одиннадцать секунд, а не десять минут.

Новая проверка: `tests/checks/check-wire-check-decides-its-verdict-by-construction.el`.
Новый claim: `the-wire-check-decides-its-verdict-by-construction`; его контроль
(момент часов в словах проверки) применён к копии дерева, и новая проверка падает
там с одним отказом: девятнадцать из двадцати прогонов решили не так, как первый.

**Open:** ожидание проверки провода — это ожидание с таймаутом в тридцать секунд:
сервер, который отвечает на prompt и никогда не пишет сообщение агента,
заставляет проверку сообщить об отказе после таймаута — вердикт верен, ожидание
долго.  Новая проверка гоняет проверку провода против одного контроля (контроля
claim'а о тексте на проводе) и ни против какого другого.  Вердикт прогона читается
из слов проверки (строк, начинающихся с `wire-text:`), и шум Emacs в вердикт не
входит.  Волна не чинит проверку моста: claim
`the-bridge-check-decides-the-race-by-construction` всё ещё не проверен, и карта
говорит об этом.  Весь набор проверок в этой сессии не гонялся: это десять минут
ожидания, а провайдер рвёт соединение, пока ждёшь.

### The order

16.1 first (it is small and it is the last piece of the kernel), then
16.2 and 16.3 together (the service becomes the default when the control
is whole), then 16.4 and 16.6 (the product works everywhere and is seen),
then 16.7 (the goal is measured), and 16.5 and 16.8 whenever.


### 16.30 The order of the work after the cycle of 2026-11-17

The cycle of 2026-11-17 closed with a green map: 122 claims, two consecutive
runs of the method that ended in `green`, and two waves of the plan of the
owner (41 and 50) that the harness carried out by itself.  This section is
the order of the work that follows.  It does not decide anything that §17.2
leaves to the owner.

1. **The leftovers of the cycle are committed.**  The paragraphs of §18.1, the
   live evidence of the two green runs, the state of the README and the
   warnings of `AGENTS.md` are one commit of documentation.  The claim of the
   owner is re-recorded after it, because the material of that claim is the
   plan itself.
2. **Wave 42 — the life cycle of the server and its spin** (§18.2).  It goes
   first because the process of the server outlived the agent nine times
   during the cycle of 2026-11-17 (each of them burning a part of a core), and
   because every wave below runs the server.
3. **Wave 43 — the surface of ACP that an orchestrator needs** (§18.3), in the
   order the plan names: the `cwd` of the session first (the tools of a
   session must work in the repository of the task), then the kind of a call
   and its named arguments, then `session/set_mode`, then the model of the
   session, then the `mcpServers` of the session.
4. **Wave 44 — parallel children in a live turn** (§18.4).
5. **The debts that the cycle of 2026-11-17 found in the harness itself.**
   They are repair waves of the same kind as 45 to 50, and their numbers
   continue the series:
   - **wave 51 — the journal of a run is protected from the run.**  The model
     of the run of wave 50 deleted its own journal (`rm -f
     sessions/wave50-1.jsonl').  The observation of a run must not be
     erasable by the run; the claim of the wave is that the journal of a live
     run survives the attempt of the run to delete it.
   - **wave 52 — the `cwd` of a session reaches the tools** if wave 43 does
     not carry it; §18.3 names it first for a reason, and a wave that is
     carried out twice is one wave too many.
   - The sender of the SIGTERM that killed three runs of the method is still
     unknown.  That is a defect of the method's own process, not of Yeah, and
     it does not take a wave of the harness; the way around it (a detached run
     under a watchdog) is in `docs/LIVE-EVIDENCE.md`.
6. **The pilot again** (§17.1): the same three tasks of the benchmark, on the
   code of the waves 46 to 50, because the last pilot measured the code of
   wave 38 and the failures it found were fixed afterwards.  It is a
   measurement and not a verdict; the threshold is the owner's (§13).

Every wave of this order is executed by the harness itself, in a live run on a
copy of the repository with a clean tree, and every wave carries a control
that bites.


### 16.31 Слова модели не завершают надзорный ход — **сделано 2026-11-18 (волна 53)**

Живой прогон волны 42 (2026-11-18 06:24–06:38, копия
`/home/az/Projects/yeah-selfdev-2`) нашёл дефект ядра, а не дефект задачи.  Обе
попытки прогона закончились строкой `final state: completed` — при том, что
работа не была сделана: 261 вызов инструмента в первой попытке и 142 во второй,
ни одного вызова `finish`, а последнее слово модели — обрывок фразы («Now the
ACP module itself:», «Now the dispatcher and the serve loop:»).  Прогон был
зачтён как успешный, и так он был записан в журнал.

Причина была в том, что **любой текстовый ответ модели завершал ход**.  В
ядре это было сделано как «результат, который подтверждает инструмент», но
проверка была `null (yeah-turn-tools-used turn)`: инструменты хода были, а
результата не было, — и слова модели принимались за конец работы.  Это прямо
противоречило claim'у `finish-is-the-only-completion-path`, который говорил, что
надзорный ход кончается вызовом `finish`, и claim'у `nudge-only-for-plans`,
который читал слова модели как конец хода: **два claim'а одной спецификации
противоречили друг другу, и код следовал более мягкому из них**.

Волна 53 разрешила противоречие в пользу строгого чтения: то же, что держат
комментарий в коде, `docs/ARCHITECTURE.md` §D7 и прелюдия модели
(`lib/yeah-gptel.el:42-51`) — надзорный ход кончается вызовом `finish`.
Конкретно:

* `yeah-turn--supervised-p` отвечает на вопрос «надзорный ли это ход», и
  надзорным считается ход с положительным бюджетом нуда.
* Текстовый ответ надзорного хода — **преждевременный**, даже когда
  инструменты хода уже отработали: модель описала результат словами и не
  вызвала `finish`.
* Нуда такого ответа (`yeah-turn--nudge-result-text`) просит вызвать `finish`
  и несёт состояние работы: что ход уже сделал и какие инструменты ещё не
  звал, — чтобы модель продолжила, а не начала задачу заново.
* Ход без надзора (бюджет нуда равен нулю) ведёт себя как раньше: там нудить
  некому, и слова модели кончают ход.
* Запись прогона, который не закончился, называет форму: «the model reported
  a result without calling `finish' N times» — рядом с «answered with an
  empty message» и «described its next step».

Новая проверка: `tests/checks/check-a-text-answer-does-not-end-a-supervised-run.el`
(надзорный ход → `failed` + запись `unfinished` + нет записи `finish`;
ненадзорный → `completed`).  Новый claim:
`a-text-answer-does-not-end-a-supervised-run`.  Тексты, область, фальсификатор
и контроль двух claim'ов пути завершения поправлены: контроль теперь снимает
надзор хода (`sed -i 's|(yeah-turn--supervised-p turn)|nil|' lib/yeah-turn.el`),
и он кусается — проверка падает на своём утверждении, а не на ошибке кода.

Волна тронула и чужие файлы, и это сказано здесь, а не спрятано: **двенадцать
проверок и шесть файлов юнитов выдавали результат через слова модели** — фиктивная
модель в них «заканчивала» ход разговором.  Теперь фиктивная модель кончает ход
вызовом `finish`, а проверки, чей предмет — не путь завершения (журнал, отложенное
разрешение, отказ инструмента), переведены на `max-nudges 0` с явным комментарием.
425 юнитов и весь набор проверок зелёные после этих правок.

**Open:** решение о том, какое чтение выигрывает, принадлежит владельцу
(§17.2).  Волна взяла строгое чтение; если владелец решит иначе, claim'ы
`finish-is-the-only-completion-path` и `nudge-only-for-plans` читаются заново.

### 16.32 Сервер заканчивается вместе с сессией клиента — **сделано 2026-11-18 (волна 42, часть A)**

Дефект: процесс ACP-сервера переживал агента.  Клиент, который держал трубу сервера
открытой после последнего хода, оставлял позади процесс Emacs, и закрывать его было
некому: протокол не давал способа сказать «я больше не приду».

Два источника противоречили друг другу, и противоречие записано, а не разрешено
молча:

* Живой прогон саморазработки (копия `/home/az/Projects/yeah-selfdev-2`, сессия
  `wave42-2`) реализовал конец сессии как **уведомление** `session/exit` — имя,
  которого нет в ACP.  Клиент, который его не знает, получает отказ `-32601`, и
  сервер живёт ровно как прежде, то есть дефект волны остаётся.
* План интеграции с оркестратором (`docs/PASEO-INTEGRATION-PLAN.md` §3.6) называет
  другой метод: `session/close` — тот, что Paseo действительно зовёт при закрытии
  сессии агента (`packages/plugin/src/server/acp-internal/connection.ts:690-698`), и
  ошибку ответа там глотают (`.catch(() => undefined)`).

Волна взяла метод ACP: `session/close`.  Ядро отвечает на запрос, отменяет ход
сессии, убирает сессию из реестра и её слушатель из списка событий.  Сервер над
stdio обслуживает одного клиента, поэтому конец его сессии — конец сервера: процесс
выходит из цикла, не дожидаясь, пока клиент закроет трубу.  Сервер над сокетом
обслуживает многих клиентов: конец сессии одного из них заканчивает эту сессию, а не
сервер, и закрытая сессия больше не отвечает на промпт.

Проверка `tests/checks/check-the-server-exits-when-the-session-is-over.el`: настоящий
процесс Emacs на stdio, ход с фиктивной моделью, `session/close` при открытой трубе
клиента — процесс обязан исчезнуть за десять секунд, а ответ на запрос обязан уйти
до остановки сервера.  Второй кейс той же проверки: сервер над сокетом продолжает
обслуживать клиентов и не отвечает на промпт закрытой сессии.  Claim:
`the-server-exits-when-the-session-is-over`.

Контроль claim'а (`sed -i 's/(setq yeah-acp--last-session-closed t)/(setq
yeah-acp--last-session-closed nil)/' lib/yeah-acp.el`) кусается: проверка падает на
своём утверждении («the server is still alive ten seconds after the end of its
session»), код 1.

Атрибуция: реализацию метода написала параллельная сессия интеграции с Paseo в общем
рабочем дереве; в волну она принята после того, как проверка волны прошла против неё
(4.3 с) и её контроль упал на собственном утверждении.  Живой прогон копии
(`wave42-2`) доказательством этой волны не является: контекст прогона переполнился
дважды, модель не написала сводки, и работа осталась в дереве копии.

**Open:** жизненный цикл с плагином Paseo эта проверка не доказывает (клиент проверки —
офлайновый, говорит тем же JSON-RPC по тем же двум транспортам); вторая половина
волны 42 — спин сервера при молчащем провайдере — это волна 54 со своим claim'ом.

### 16.33 Инструменты сессии работают в каталоге сессии — **сделано 2026-11-18 (волна 43, часть 1)**

Дефект: `cwd`, который клиент шлёт в `session/new`, записывался в журнал и в
замороженный вход прогона, а инструменты его не читали.  Относительный путь
инструмента считался от каталога процесса Emacs: в живой проверке `bash` агента
работал в каталоге установки CLI Paseo, а не в репозитории задачи.

Что изменилось: сессия несёт свой каталог, инструменты прогона отправляются внутри
привязки этого каталога, и относительный путь инструмента считается от него.
Привязка живёт в одном месте — `yeah-session-with` (`lib/yeah-session.el`) — и через
неё проходят все инструменты прогона, и синхронные, и асинхронные: обработчик
инструмента читает каталог процесса, пока привязка держится.  Каталог сессии —
это каталог и ребёнка делегации: ребёнок работает там же, где родитель.

Проверка `tests/checks/check-a-session-runs-in-its-own-directory.el`: настоящий
процесс ACP-сервера на stdio, сессия с `cwd` во временном каталоге с файлом,
фиктивная модель читает файл по относительному имени, и текст вызова на проводе несёт
содержимое файла.  Вердикт решён по построению: файл есть только в одном
каталоге, а сервер проверки работает в другом.  Claim:
`a-session-runs-in-its-own-directory`.

Контроль claim'а (`sed -i 's|(file-name-as-directory yeah-session--cwd)|default-directory|'
lib/yeah-session.el`) кусается: проверка падает на своём утверждении («the tool of the
session did not run in the directory of the session: it answered "yeah-files read: file
does not exist: …"»), код 1.

Проверка нашла три дефекта и себя до того, как что-то доказала, и все три записаны в
`waves/wave-43.json`: читатель провода терял сообщение, разрезанное трубой пополам;
он же разворачивал список сообщений на месте через `nreverse`; и поиск вызова
инструмента считал, что `cl-find-if` возвращает значение предиката — он возвращает
элемент, и идентификатор вызова был целой нотификацией, а сравнение нотификации со
строкой не находило ничего.  Модель проверки вынесена в отдельный файл
(`tests/support/yeah-session-cwd-model.el`): источник, который надо написать один раз
с правильным числом скобок, лучше не писать строкой.

**Open:** привязка `default-directory` — это глобаль Emacs, и плагин, который полагается
на неё во время работы инструментов прогона, видит каталог задачи; инструмент,
который читает каталог процесса позже — обратный вызов асинхронного инструмента, —
снова читает каталог процесса.  Проверка доказывает случай синхронного `read`;
случай `bash` из плана проходит через ту же привязку, но вторым проверкой не доказан.
Сессия, открытая без каталога (старый журнал), оставляет каталог процесса.


### 16.34 Вызов инструмента несёт свой род и именованные аргументы — **сделано 2026-11-18 (волна 43, часть 2)**

Дефект: `tool_call` на проводе называл инструмент и нёс, чем он вызван и что вернул,
но не нёс рода: клиент, который рисует вызов по роду — чтение, правка, шелл — видел
только имя инструмента, и плагину Paseo приходилось угадывать род по имени.
Аргументы вызова ехали позиционным списком, и клиент, который ищет именованные
поля, не находил ничего.

Что изменилось: инструмент объявляет свой род в реестре (`lib/yeah-tools.el`, новое
поле `:kind`), запись запроса вызова в журнале несёт род и аргументы под именами,
которые объявил инструмент, и провод несёт и то и другое.  Журнал остаётся
источником истины: провод — проекция записи запроса, и запись, написанная до того,
как ядро стало называть аргументы, едет по проводу так, как была написана: значения
по местам.  Имена аргументов — это имена, которые объявил инструмент, и они же
имена, которые получил модель: `path`, `old_str`, `new_str`, `command`.  Клиент
Paseo читает `filePath`, `oldString` и `newString` — это соглашение Paseo, а не
соглашение ядра, поэтому перевод имён лежит в плагине
(`plugin/yeah-provider/server/yeah.ts`): ядро шлёт то, что знает, а переходник — то,
что читает его клиент.

Проверки: `tests/checks/check-a-tool-call-carries-its-kind.el` и
`tests/checks/check-a-tool-call-carries-named-arguments.el`.  Настоящий процесс
ACP-сервера на stdio, сессия с каталогом во временном каталоге, фиктивная модель
читает файл, и обновление, объявившее вызов, несёт род и именованные аргументы.
Общая машина проверки вынесена в `tests/support/yeah-acp-tool-call.el`, фиктивная
модель — в `tests/support/yeah-tool-call-model.el`.  Claim'ы:
`a-tool-call-carries-its-kind` и `a-tool-call-carries-named-arguments`.

Контроли claim'ов кусаются: `sed -i 's|:kind kind|:kind nil|g' lib/yeah-acp.el` —
проверка падает с кодом 1 и своими словами; `sed -i 's|(yeah-acp--tool-arguments
fields)|(yeah-acp--tool-input (plist-get fields :args))|' lib/yeah-acp.el` — тоже
код 1 и свои слова: провод нёс `("marker.txt")` вместо объекта с именем `path`.

План интеграции (`docs/PASEO-INTEGRATION-PLAN.md` §3.3) говорил, что ядро объявляет
`filePath`, `oldString` и `newString`.  Инструмент правки объявляет `path`, `old_str`
и `new_str`, и менять их — значит менять схему, которую видит модель; текст плана
исправлен, перевод имён назван в нём.

**Open:** род, который инструмент не объявил, — это `other`, и клиент рисует такой
вызов как `other`; инструменты внешних серверов MCP приносят род со своей
спецификацией, а ядро берёт `other`, когда спецификация его не несёт.  Перевод имён
в плагине проверяется тестом трансформера, а не живым таймлайном Paseo.  Старые
записи журнала едут по проводу без рода и без имён.


### 16.35 Профиль прав сессии меняется по проводу — **сделано 2026-11-18 (волна 43, часть 3)**

Дефект: метода `session/set_mode` не было, и клиент, который спрашивал, получал
`-32601`.  Профиль прав сессии выбирался при старте процесса и не менялся на лету:
человек не мог сказать агенту «смотри, но не трогай», а клиент Paseo нечего было
показать — он берёт режимы из ответа `session/new` и переключает их через
`session/set_mode`.

Что изменилось: режимы сессии — это профили прав ядра (`plan` и `build`,
`lib/yeah-perm.el`), `session/new` публикует их вместе с тем режимом, в котором
сессия находится, `session/set_mode` меняет режим сессии, и режим решает раньше
всех: режим, который запрещает действие, отказывает в нём без вопроса клиенту.
Журнал остаётся источником истины: смена режима — запись сессии (`session-mode`),
а провод несёт её как уведомление `current_mode_update`, которое ACP называет;
сессия, открытая снова, остаётся в том режиме, в котором её оставили.

Проверка `tests/checks/check-a-session-changes-its-permission-profile-over-the-wire.el`:
настоящий сервис ACP на сокете, две сессии в двух каталогах, фиктивная модель зовёт
`write`.  Проверка требует, чтобы `session/new` опубликовал режимы, чтобы
`session/set_mode` был отвечен (и не ошибкой), чтобы клиент узнал о новом режиме,
чтобы в режиме `build` клиента спросили и инструмент сработал, и чтобы в режиме
`plan` клиента не спросили, инструмент объявили, а файл не появился.
Claim: `a-session-changes-its-permission-profile-over-the-wire`.

Контроль claim'а кусается: `sed -i 's|(yeah-acp--mode-denies-p mode request)|nil|'
lib/yeah-acp.el` — проверка падает с кодом 1 и своими словами: клиента спросили в
режиме `plan`, и файл всё равно записался.

Проверка идёт через сервис на сокете, а не через сервер на stdio: сервер на stdio
читает вход между запросами, и ответ клиента на вопрос о правах пришёл бы уже
после того, как прогон закончился.  Это ограничение stdio, а не дефект проверки:
живое развёртывание Yeah — сервис на сокете.

Общая машина провода вынесена в `tests/support/yeah-acp-wire.el`: сервер на stdio,
читатель сообщений и ожидание ответа нужны были трём проверкам.

**Open:** режим сессии — это профиль прав, а не режим работы агента в смысле ACP:
у клиента ACP режимы задаёт агент, и ядро объявляет ровно столько режимов,
сколько у него профилей.  Смена режима меняет решение о правах, а не набор
инструментов.  Проверка доказывает, что режим меняет решение о правах для `write`;
живого прогона с клиентом Paseo, который рисует переключатель режимов, эта волна
не проводила.

### 16.36 Модель сессии меняется по проводу — **сделано 2026-11-18 (волна 43, часть 4)**

Дефект: модель сессии не менялась по проводу.  Ни `session/set_model`, ни
`session/set_config_option` не было, и клиент, который спрашивал, получал `-32601`.
Модель выбиралась при старте процесса: плагин Paseo публиковал в каталоге одну
модель и сам отвечал на запрос о смене модели, если просили ту же самую, —
менять модель на лету было нечем, и ядро о такой возможности не знало.

Что изменилось: каталог моделей ядра (`lib/yeah-model.el`) — это то, что клиенту
предложить, и он состоит из моделей, которые *реально могут работать*: моделей
бэкенда gptel, который знает провайдер.  `session/new` и `session/load`
публикуют `configOptions` — массив, в котором опция модели имеет категорию
`model`, тип `select`, текущее значение и список значений; ACP требует массив, а
список объектов `json-serialize` не сериализует.  `session/set_config_option`
меняет модель сессии: модель, которой нет в каталоге, отвергается, журнал
называет новую модель записью `session-model`, провод несёт её уведомлением
`config_option_update`, а сессия, открытая снова, остаётся на той модели, на
которой её оставили.

Модель доходит до вызова модели без изменения контракта транспорта: транспорт
сервиса один на все сессии, и модель сессии связывается вокруг вызова этого
транспорта (`yeah-model--current`), а `yeah-gptel-request` берёт её, когда модель
не названа явно.  Это то же решение, что и с каталогом сессии (волна 43, часть 1):
рабочий каталог — это связывание `default-directory` вокруг вызова инструмента.

Плагин Paseo (`plugin/yeah-provider/`) перестал быть тем, кто меняет модель:
он регистрирует в бэкенде gptel все модели, которые знает (настройка `models`,
список через запятую), публикует их в каталоге провайдера и *не перехватывает*
смену модели — запрос уходит в ядро, и ядро решает, может ли сессия работать на
названной модели.

Проверка `tests/checks/check-a-session-changes-its-model-over-the-wire.el`:
настоящий сервис ACP на сокете, каталог из двух моделей, фиктивная модель
пишет в файл имя модели, на которой она работает.  Проверка требует, чтобы
`session/new` опубликовал опцию модели с её значениями и текущим значением,
чтобы `session/set_config_option` был отвечен (и не ошибкой) и назвал новую
модель, чтобы клиент узнал о смене, чтобы ход сессии пошёл на названную модель
(файл в каталоге сессии содержит её имя), чтобы сессия, открытая снова, осталась
на этой модели, и чтобы модель, которой нет в каталоге, отвергли.
Claim: `a-session-changes-its-model-over-the-wire`.

Контроль claim'а кусается: `sed -i 's|(yeah-model--current (yeah-acp--session-model
state))|(yeah-model--current nil)|' lib/yeah-acp.el` — проверка падает с кодом 1 и
своими словами: ход сессии пошёл не на ту модель.  Второй контроль (метод
`session/set_config_option` убран из диспетчера) падает с теми же словами и с
`-32601` в ответе.

Живой провод проверен отдельно, вне проверки: сервер, поднятый той же формой
запуска, что поднимает плагин, публикует `configOptions` с обеими моделями
бэкенда, меняет модель по `session/set_config_option` и отвергает неизвестную
модель с `-32602`.

**Open:** проверка доказывает, что модель доходит до вызова модели через
связывание вокруг транспорта, — но не то, что клиент Paseo рисует переключатель
моделей: живой прогон с клиентом в этой волне не проводился.  Модель ребёнка
делегации по-прежнему задаётся пресетом, а не сессией: пресет — это её
собственный выбор, и волна 44 его не меняет.

### 16.37 Серверы MCP сессии доходят до модели — **сделано 2026-11-18 (волна 43, часть 5)**

Дефект: массив `mcpServers` в `session/new` и в `session/load` проверялся и
выбрасывался.  Ядро убеждалось, что это массив, и забывало о нём: клиент,
который назвал сервер, получал сессию, модель которой не могла воспользоваться
ни одним инструментом этого сервера.

Что изменилось: новый модуль `lib/yeah-session-mcp.el` подключается к серверам,
которые назвал клиент, говорит рукопожатие MCP (`initialize`, затем `tools/list`)
и превращает инструменты этих серверов в обычные записи реестра ходов этой
сессии.  Говорится только stdio: агент объявляет в `initialize`, что говорит
stdio и больше ничего, а сервер другого транспорта отвергается поимённо, а не
подключается наполовину.  Сервер, который не ответил за
`yeah-session-mcp-timeout` (10 секунд), отвергает сессию: сессия не открывается
без инструментов, которых просил клиент.

Инструменты серверов живут в снимке реестра конкретного прогона
(`yeah-control--registry`), а не в общем реестре: инструменты одной сессии не
протекают в ходы другой.  В журнал пишутся только имена серверов — команда
сервера и его окружение могут держать секреты, а секрет никогда не попадает в
лог.  Окружение сервера задаётся программой `env` в командной строке:
`make-process` в Emacs 30 не знает `:environment`, а `process-environment` —
переменная, а не функция.

Инструменты доходят до модели через реестр прогона, и на этом пути нашёлся
дефект ядра: отложенное решение о правах (а маршрут ACP откладывает права на
каждый инструмент) исполняло инструмент **вне** связывания реестра, поэтому
инструмент сессии не находился и ход зависал.  Теперь `yeah-turn--run-or-refuse`
связывает реестр хода вокруг вызова инструмента.

Проверка `tests/checks/check-the-mcp-servers-of-a-session-reach-the-model.el`:
настоящий сервис ACP на сокете, сессия, которая называет MCP-сервер (маленький
сервер проверок, говорящий настоящий протокол по stdio,
`tests/support/yeah-mcp-server.el`), и фиктивная модель, которая находит свой
инструмент среди инструментов хода, зовёт его и пишет ответ в файл.  Проверка
требует, чтобы сессия была открыта (и не отвергнута), чтобы инструмент сервера
дошёл до модели, чтобы вызов модели дошёл до сервера (ответ сервера называет
текст, который дала модель), чтобы окружение, названное клиентом, дошло до
сервера, и чтобы провод нёс вызов инструмента сервера.
Claim: `the-mcp-servers-of-a-session-reach-the-model`.

Контроль claim'а кусается: `sed -i 's|(let ((tools (yeah-control-tools
control)))|(let ((tools nil))|' lib/yeah-control.el` — проверка падает с кодом 1
и своими словами: «the tool of the MCP server did not reach the model of the
session».

**Open:** проверка говорит о stdio.  Транспорты http и sse не поддержаны:
клиент, назвавший такой сервер, получает отказ поимённо.  Живой прогон с
клиентом Paseo в этой волне не проводился.


### 16.38 Спин сервера, когда провайдер молчит — **сделано 2026-11-18 (волна 54)**

**Дефект.**  Вторая половина волны 42 владельца (§18.2): сервер, который
ждёт ответа провайдера, жжёт ядро.  2026-11-16 процесс сервера был измерен
с 1 921 354 невольными переключениями контекста и шестью добровольными — он
не спал вовсе, 25–60 % ядра.

**Что сделано.**  Сначала измерение, и только потом код: дефект **не
воспроизводится** на коде 2026-11-18.  Три сценария, все — тики
`/proc/<pid>/stat` (метод, которым измеряли сам дефект, а не процент CPU из
`top`):

| Сценарий | Тики за 10 с | CPU | Доля ядра |
|---|---|---|---|
| Транспорт, который не отвечает никогда | 0 | 0.000 с | 0.0 % |
| Живой путь gptel+curl, соединение с провайдером висит | 4 | 0.040 с | 0.4 % |
| Живой путь gptel+curl, провайдер шлёт поток (keep-alive каждые 50 мс) и не отвечает | 6 | 0.060 с | 0.6 % |

Граница плана — 1 % ядра за десять секунд: все три сценария под ней.  Значит
волна **не удаляет петлю**: петли на коде 2026-11-18 нет.  Она делает границу
проверкой, чтобы петля, которая вернётся, не вернулась молча.

**Claim'ы.**
- `the-server-does-not-spin-when-the-provider-is-silent` — сервер, чей
  провайдер молчит, стоит меньше одного процента ядра за десять секунд
  (контроль возвращает петлю: измеренные тики превышают границу).

**Критерий выхода.**
1. Проверка проходит на дереве, и её контроль кусается утверждением самой
   проверки, а не падением Emacs.
2. Три измерения выше записаны в `docs/LIVE-EVIDENCE.md`.

**Что эта волна не делает.**  Она не добавляет счётчики, которые называет
план (итерации насоса провода и итерации запроса провайдера): счётчик, который
никто не читает, — это число в переменной, и имя счётчиков задаёт та волна,
которая меряет живой путь с ними.  Она не трогает жизнь сервера: это волна 42,
и сессию, которую ведёт другая сессия харнесса, эта волна не ведёт.

### 16.39 Сервер уходит вместе с владельцем, который его поднял — **сделано 2026-11-18 (волна 55)**

**Дефект.**  Сервер, поднятый владельцем, переживал владельца: владельца
убивали, а сервер оставался жить и держал сокет.  План починки от 2026-11-18
(шаг 3, строки 120–136) требует, чтобы сервер уходил вместе с тем, кто его
поднял.

**Что сделано.**  Жизнь сервера описана сокетом жизни: `lib/yeah-life.el` —
путь сокета, проверка живости владельца, принятие сокета жизни, создание и
закрытие.  Сервер (`lib/yeah-acp.el`, `yeah-acp-serve-socket`) в `unwind-protect`
следит за сокетом жизни владельца и уходит, когда владелец исчез; сокет
сервиса (`lib/yeah-service.el`) получает свой сокет жизни с именем
`service-NAME`; провод (`lib/yeah-wire-socket.el`) убирает файл сокета при
остановке.

**Claim'ы.**
- `the-server-does-not-outlive-its-owner` — сервер сервиса уходит, когда его
  владелец убит (контроль отнимает сторож у сервера, и проверка падает своим
  утверждением).

**Критерий выхода.**
1. Проверка проходит, её контроль кусается утверждением самой проверки.
2. Замер записан в `docs/LIVE-EVIDENCE.md`: сервер ушёл через 0.2 с после
   смерти владельца (граница плана — десять секунд), сокет сервиса и файл
   сокета жизни тоже исчезли.

**Что эта волна не делает.**  Она не отменяет жизнь сессии клиента (это волна
42) и не трогает провод провайдера.  Она не следит за владельцем извне: связь
жизни идёт через сокет, а не через опрос.

### 16.40 Проверка не оставляет сервер за собой — **сделано 2026-11-18 (волна 56)**

**Дефект.**  Проверка поднимала сервер на локальном сокете; если проверку
убивали, сервер оставался жить.  Проверка — это код, который сам может быть
убит, и оставлять после себя сервер нельзя.

**Что сделано.**  Жизнь наследуется через переменную окружения
`YEAH_LIFE_SOCKET`: `yeah-life-adopt-from-environment` и
`yeah-life-inherited-path` в `lib/yeah-life.el`; сервер проверки берёт свой
сокет жизни из окружения, если ему не дали свой (`lib/yeah-acp.el`), и уходит
сам, если владелец исчез до старта сервера.  `scripts/dev` даёт каждой
проверке `.el` свой сокет жизни; фикстура проверки живёт в `tests/support/`
(она не заканчивается сама, поэтому гейт не должен гонять её как проверку).

**Claim'ы.**
- `the-check-leaves-no-server-behind` — сервер проверки уходит, когда её
  владельца убили (контроль отнимает наследование жизни).

**Критерий выхода.**
1. Проверка проходит, её контроль кусается утверждением самой проверки:
   «the server of the check stayed behind after its owner was killed».
2. Сокет сервера ушёл вместе с сервером.

**Что эта волна не делает.**  Она не делает наследование жизни частью
контракта метода: это конвенция проекта, а не контракт.  Она не чинит
сервер, который поднял не проверка, а живой клиент, — это волна 55.

### 16.41 Проверка, которая зависла, не съедает гейт — **сделано 2026-11-18 (волна 57)**

**Дефект.**  Гейт исполнял проверки без предела: одна зависшая проверка
держала весь прогон.  Проверка
`check-a-tool-that-returns-bytes-does-not-kill-the-harness.el` шла 20 462 мс и
занимала почти весь простой свипа (2 мин 19.6 с на 79 проверок).

**Что сделано.**  `scripts/dev-timeout` — предел одной проверки
(`YEAH_CHECK_TIMEOUT`, по умолчанию 120 с), своя группа процессов,
TERM → три секунды → KILL, потомки гасятся через `/proc`, ловушки INT/TERM/EXIT;
ответ «остановлен по пределу» — код **3** (unknown, а не pass).  `scripts/dev`
переписан: коды 0/1/2/3 агрегируются, help переписан.  Медленная проверка
ускорена с 20 462 мс до 460 мс (в 44 раза).

**Claim'ы.**
- `the-gate-stops-a-check-that-hangs` — гейт останавливает проверку, которая
  зависла, и отвечает третьим ответом (контроль отнимает у таймера остановку).

**Критерий выхода.**
1. Проверка проходит (5.3 с), её контроль кусается утверждением самой проверки:
   «the check that hangs was not stopped», «the gate did not say that the
   check passed its limit».
2. Свип 79 проверок после правки — 2 мин 19.6 с → измерено ниже в
   `docs/LIVE-EVIDENCE.md`.

**Что эта волна не делает.**  Она не различает «завис» и «думает долго»:
предел один на проверку, и ответ после него — unknown, а не pass.  Она не
чинит провайдера, который не отвечает, — это волна 54.

### 16.42 Пилот, который прервали, не оставляет сервер — **сделано 2026-11-18 (волна 58)**

**Дефект.**  Пилот и гейт жили своей жизнью: прерванный или исчерпавший
время пилот оставлял сервер и своих потомков.

**Что сделано.**  `scripts/lib/tree.sh` — одна реализация дерева процессов
(`now_ms`, `process_group`, `descendants`, `own_group`, `kill_group`,
`stop_tree`, `stop_now`); `scripts/live-pilot` — раннер переднего плана: своя
группа, ловушка INT → 130 / TERM → 143 / EXIT, ожидание через `wait` без
опроса, предел 3300 с, ответ 3 по пределу, **одна точка остановки**
`signal_pilot()`.  `scripts/dev-timeout` переведён на `tree.sh`: второй
реализации дерева не появилось.

**Claim'ы.**
- `the-interrupted-pilot-leaves-no-server-behind` — прерванный пилот не
  оставляет сервер.
- `the-pilot-that-runs-out-of-time-leaves-no-server-behind` — пилот, исчерпав
  предел, не оставляет сервер и отвечает третьим ответом.

**Критерий выхода.**
1. Обе проверки проходят (4.1 с и 13.4 с), их контроли кусаются утверждениями
   самих проверок.
2. Пилот останавливает всё дерево, а не только процесс верхнего уровня.

**Что эта волна не делает.**  Она не относит файл сокета к своему claim'у:
файл сокета — это волна 56.  Она не отменяет предел: предел нужен, и ответ по
нему — unknown.

### 16.43 Гейт не требует watchdog — **сделано 2026-11-18 (волна 59)**

**Дефект.**  Гейт был обвязан watchdog'ом: отвязанный процесс, который читал
лог каждые пять секунд и начинал прогон заново, когда лог не двигался
(`setsid nohup`, `timeout 600 mathc map`, `grep` по `never-checked`, `sleep 5`
между попытками, `MAX_ATTEMPTS=6`, лог `/tmp/mathc-watchdog.log`).  Замер
2026-11-18: 147 команд `sleep` и сорок четыре минуты ожидания в день; после
остановки watchdog'а оставались копии прогона.  Это шаг 4 плана починки
(строки 140–160).

**Что сделано.**  `scripts/gate` — единый раннер гейта переднего плана: прогон
метода — его ребёнок, ожидание через `wait`, перезапуск убитого прогона делает
сам гейт, карта пишется всегда в конце, ни одной команды `sleep`.  Знание
«где метод» вынесено в `scripts/lib/method.sh` (`find_mathc`) — его читают и
гейт, и обёртка проекта.  `scripts/dev gate` делегирует `scripts/gate`:
обёртка не держит гейт своего.  Обвязка watchdog'ов удалена из
`yeah-site/artifacts` (`watchdog-mathc.sh`, `watchdog-selfdev.sh`,
`watchdog-selfdev-b.sh`, `watchdog-selfdev-w42.sh`), а `run-selfdev.sh` переведён
на раннер пилота репозитория (`scripts/live-pilot --limit 3300`).

**Claim'ы.**
- `a-gate-run-needs-no-watchdog` — прогон гейта не требует watchdog'а (пять
  контролей: перезапуск, ожидание, карта, отсутствие `sleep`, одна копия
  гейта).

**Критерий выхода.**
1. Проверка проходит (6.5 с), все пять её контролей кусаются утверждениями
   самой проверки.
2. В `scripts/gate` нет команды `sleep`, а в `scripts/dev` — своего гейта.

**Что эта волна не делает.**  Она не чинит дефект метода «убитый прогон
оставляет копии» — это кандидат **D10** в `math-coding` (линия `main`), лечится
он в методе, а не здесь.  Гейт, убитый извне SIGKILL, не ловит сигнал: прогон
остаётся жить до конца своего предела (измерено: процессы умерли сами через
63 с при пределе 60 с).  Это записано в `waves/wave-59.json` (`objection`),
а не спрятано.

### 16.44 Убитый прогон не оставляет копий — **сделано 2026-11-18 (волна 60)**

**Дефект.**  Метод работает во временном каталоге своего: `mathc-v5-<pid>-<n>`
(`adapter/io.ml:18-25`), и в него кладётся checkout проекта
(`adapter/isolated_run.ml`).  Каталог удаляется через `Fun.protect`, но убитый
процесс `finally` не выполняет: 48 копий, около гигабайта, остались от убитых
прогонов.  Это шаг 5 плана починки (строки 164–176).

**Что сделано.**  `scripts/lib/copies.sh` — `sweep_method_copies`: обход
`$TMPDIR/mathc-v5-*`, pid разбирается из имени, и копия снимается **только**
когда процесса с таким pid нет (`/proc/<pid>` отсутствует); копия живого
прогона не трогается.  Гейт зовёт свип перед записью карты, `scripts/dev run`
— после прогона.  Знание о копиях лежит в одном файле, а не в двух.

**Claim'ы.**
- `the-killed-run-leaves-no-copy-behind` — убитый прогон не оставляет копии,
  а копия живого прогона остаётся (два контроля: свип не зовётся гейтом; свип
  не различает живой и мёртвый прогон).

**Критерий выхода.**
1. Проверка проходит (6.6 с), оба контроля кусаются утверждениями самой
   проверки: «the copy of the run that was killed stayed behind» и «the copy
   of the living run was removed».
2. След доказательств не тронут: он лежит в `.math/trail.jsonl` проекта, а
   не в копии.

**Что эта волна не делает.**  Она не чинит дефект метода — кандидат **D10** в
`math-coding` (линия `main`), и там же регистрируется в лаборатории.  Свип
работает в конце прогона, а не в момент смерти процесса: копия умершего
прогона лежит до следующего прогона.  На машине без `/proc` свип не найдёт
живых прогонов — это отказ платформы, и он записан в `objection` волны.


### 16.45 Мёртвые контроли снова кусаются — **сделано 2026-11-18 (волна 61)**

**Дефект.**  Два контроля в `spec.json` перестали что-либо менять после волн
55 и 56, и оба claim'а стояли в карте как `Inconclusive` — не потому, что
свойства ложны, а потому, что отрицательный контроль не изменил ни одного
байта в scope (`reach = nothing`).  Метод поступил верно: `Inconclusive`, а не
зелёный.  Но правда о свойстве осталась неизвестной.

**Что сделано.**  Требования, falsifier'ы и проверки не тронуты — изменён
только способ внести отрицательный контроль:

- `the-check-leaves-no-server-behind` — `sed -i 's|(not (yeah-life-alive-p
  watch))|nil|g' lib/yeah-acp.el`.  Сервер перестаёт замечать, что его хозяин
  умер: он остаётся жив, а его сокет остаётся на диске — срабатывает ровно тот
  falsifier, который записан у claim'а.
- `service-lifecycle` — `sed -i 's|(yeah-acp-handle-message line)|nil|g'
  lib/yeah-acp.el`.  Сервис не отвечает на рукопожатие — срабатывает
  falsifier «the service does not answer».

Оба якоря лежат внутри scope своих claim'ов, поэтому `reach` считается как
`subject`.

**Почему контроли умерли.**  Первый искал `(yeah-acp-serve-socket %S %s)`,
а вызов после волны 55 стал `(yeah-acp-serve-socket %S %s nil 'local %S)`.
Второй искал `(let* ((life ...`, а в BRE `t*` — квантификатор: после `le`
ожидался пробел, а в тексте стояла звёздочка.

**Критерий выхода.**
1. Базовая линия зелёная: 904 мс и 865 мс, exit 0.
2. Оба контроля кусаются утверждениями самих проверок: 20768 мс — «the server
   of the check stayed behind after its owner was killed» и «the socket of the
   server stayed behind»; 10525 мс — «the service did not answer the
   handshake».

**Что эта волна не делает.**  Она не чинит дефект метода и не меняет свойства
кода — она возвращает claim'ам способ быть проверенными.  Контроль остаётся
sed'ом по строке кода и умрёт от следующей переименки; мёртвый контроль
метод видит сам (`reach = nothing` → `Inconclusive`), и это записано в
`objection` волны.


### 16.46 У непокрытого появляется хозяин — **сделано 2026-11-18 (волна 62)**

**Дефект.**  Карта показывала 40 файлов, которыми не владел ни один claim:
у пяти областей репозитория не было хозяина, и ни одна проверка не стояла на
их стороне.  Области: `tests/support` (14 файлов), `tests/live` (5),
`tests/pixel` (2), `site` (8) и `docs` вместе с `ELISP_BEST_PRACTICES.md` (11).
Claim'ы этих областей взяли предмет шире списка непокрытого: `site` вместе с
`VERSION`, `docs` вместе с `AGENTS.md` и `README.md`.  Claim без файлов —
свойство без предмета: его нельзя ни опровергнуть, ни починить, и карта
молчит о нём так же, как молчит о свойстве, которое никто не проверял.

**Что сделано.**  Пять claim'ов и пять проверок; после волны `mathc map`
показывает uncovered: 0 file(s).

- `the-support-fixtures-load` — каждая фикстура `tests/support` грузится в
  дочернем Emacs, по одному дитя на фикстуру и с пределом в десять секунд,
  поэтому висящая фикстура даёт имя и причину, а не молчание; три серверные
  фикстуры названы и проверены на присутствие, а не на загрузку.  Проверка
  не оставляет процессов.
- `the-live-tests-are-whole-files` — каждый живой тест читается до конца,
  скобки сверяются через `check-parens`, требуется заголовок и подвал.
  Ничего не пишется: репозиторий после проверки равен репозиторию до неё.
- `the-interface-is-seen` — пиксельная проверка рисует журнал и экран
  подтверждения в терминале под сервером кадров, фотографирует экран и
  находит интерфейс в снимке.
- `the-site-shows-the-current-version` — страница показывает одну версию, и
  это версия проекта; каждый локальный файл, на который страница указывает,
  лежит на диске.
- `the-documentation-points-at-files-that-exist` — каждое имя файла этого
  репозитория, которое называет документ, ведёт к файлу на диске, и каждый
  названный раздел — заголовок этого файла.

**Дефекты, которые волна нашла по пути.**  Четыре проверки были написаны и
переписаны, каждая по-своему:

1. Проверка живых тестов брала «копию» через `copy-file` с тем же путём, что
   и у источника: копия была самим исходником, `delete-file` стирал живой
   тест из репозитория, а проверка рапортовала об успехе.
2. Файл проверки фикстур не читался — не хватало двух закрывающих скобок.
3. Проверка сайта опиралась на `string-match-all`, которой в Emacs 30.2 нет:
   проверка не могла выполниться вовсе.
4. Проверка документации была обрезана.

**Диалект Emacs 30.2.**  Часть правок ушла на то, что предположения о
регулярках Emacs неверны: оператор «ноль-или-один» — голый `?`, а `\?` — это
литеральный вопросительный знак; `string-trim` в Emacs 30 принимает
регулярки во втором и третьем аргументах и внутри зовёт `string-match`,
стирая match-данные; `member` сравнивает строки через `eq`, а не через
`string=`; прототип `directory-files` в Emacs 30.2 — `(FULL MATCH NOSORT
COUNT)`, и потому `.`, `..` и скрытые имена попадали в список верхнего
уровня репозитория.  Из-за последнего базовая линия проверки документации
была красной: четыре живые ссылки на соседний исследовательский клон
(`../emacs-agents-research` в `docs/PLAN.md`, `docs/ENGINEERING.md`,
`docs/ARCHITECTURE.md` и `README.md`) считались путями этого репозитория.
Клон на машине есть, и ссылки верны — сломана была проверка, а не
документация.  Правило при этом не ослаблено: починены четыре битые ссылки
в `AGENTS.md`, `ELISP_BEST_PRACTICES.md` и `docs/PASEO-INTEGRATION.md`, а
проверка обязана доказать, что она вообще что-то нашла (счётчик найденных
имён), иначе она падает с фразой «no name of the documentation was
followed».

**Критерий выхода.**
1. Базовая линия зелёная у всех пяти claim'ов.
2. Все пять контролей кусаются: scope изменён, код контроля 0, код проверки
   после контроля 1, и падает проверка своим собственным утверждением.
3. `mathc map`: uncovered — 0 файлов.

**Что эта волна не делает.**  Она не говорит о том, как работает ядро: все
пять свойств — о том, что вспомогательное не развалилось.  `uncovered` не
влияет на вердикт карты — он влияет только на `next`, а вердикт остаётся
неизвестным до тех пор, пока владелец не запишет решение.  Три проверки из
пяти ломаются всякой переименованием — это цена свойств «дерево документации
цело», и она записана в `objection` волны.


### 16.47 Контроль кусается по своей причине — **сделано 2026-11-18 (волна 63)**

**Дефект.**  Волна 62 дала пять зелёных claim'ов, и один был зелёным нечестно.  Claim
`the-documentation-points-at-files-that-exist` опирался на контроль, который кусался не по
своей причине.  Проверка читала каталоги и считала путём репозитория всё, что начинается со
знакомого имени верхнего уровня, а изолированная копия, которую делает метод, не содержит ни
`bench/results/`, ни `tests/artifacts/`: git их игнорирует, и копия метода берёт только то, что
git знает (`git ls-files -z --cached --others --exclude-standard` — `adapter/isolated_run.ml` в
репозитории метода).  В рабочем дереве оба каталога есть, поэтому базовая линия проверки была
зелёной там и красной в копии, а контроль — подставить имя несуществующего файла в
`docs/PLAN.md` — ронял проверку и там, и там по другой причине: не из-за подставленного имени,
а из-за трёх других имён, которых в копии нет.  Reach у такого контроля `subject`, код после
контроля 1, и проверка падает — но не своим утверждением.  Контроль, который кусается не по
своей причине, не доказывает ничего: он доказывает, что проверка падает, и больше ничего.

**Что сделано.**  Правило проверки переписано: путь репозитория определяет git, а не обход
каталогов.

- Файлы репозитория — это то, что знает git: `git ls-files --cached --others
  --exclude-standard`.  Верхний уровень репозитория строится из этого списка, а не из
  листинга каталога, поэтому `.`, `..` и скрытые имена в него не попадают по определению.
- Игнорируемое имя — это вывод прогона, а не путь репозитория: об этом спрашивает git
  (`git check-ignore`).  Такое имя оставляется в покое, и проверка не ищет его на диске.
- Каждое имя спрашивается о двух формах — как написано и со слэшем на конце.  Правило
  `tests/artifacts/` совпадает только с именем, которое git знает как каталог, а в копии
  метода такого каталога нет; без второй формы копия отвечала бы на тот же вопрос иначе,
  чем рабочее дерево, — это и был дефект.
- Проверка по-прежнему обязана найти хотя бы одно имя: иначе она падает фразой «no name of
  the documentation was followed».

**Замерщик, который врал.**  Первый стенд замерщика копировал репозиторий через
`shutil.copytree` с `ignore_patterns("tests/artifacts")`, а `fnmatch` сравнивает basename,
поэтому игнорируемые каталоги попадали в копию: базовая линия была зелёной и контроль
«кусался» — 5 из 5.  Переписанный стенд повторяет рецепт метода дословно (`git clone
--no-hardlinks --no-checkout`, `git checkout --detach HEAD`, копия поверх всего, что
перечислил `git ls-files -z --cached --others --exclude-standard`, `git add -A -- .`), и при нём
из пяти claim'ов волны 62 четыре кусаются честно, а docs-claim не кусается вовсе: базовая
линия exit 1 с тремя чужими находками — `tests/artifacts` в `README.md` и
`docs/LIVE-EVIDENCE.md`, `bench/results` в `docs/PLAN-NEXT.md`.  После правки: базовая линия
exit 0 (497 мс), после контроля exit 1 (620 мс), scope изменён, код контроля 0, и падает
проверка своей находкой — «it names docs/there-is-no-such-file.md, and there is no such
file».  Живое дерево: exit 0, 435 мс.

**Диалект Emacs 30.2 и git.**  `delete-dups` в Emacs 30.2 принимает один аргумент, для
сравнения строк нужен `cl-remove-duplicates` с `:test #'string=`.  `git check-ignore --stdin`
ждёт EOF, а `process-send-string` его не посылает, — проверка зависала; пути передаются
аргументами.

**Критерий выхода.**

1. Базовая линия зелёная в изолированной копии репозитория.
2. Контроль кусается: scope изменён, код контроля 0, код проверки после контроля 1, и падает
   проверка своим собственным утверждением.
3. Четыре остальных claim'а волны 62 по-прежнему кусаются.

**Что эта волна не делает.**  Она не добавляет свойств и не чинит документацию: имена, на
которые указывает документация, верны — верна была проверка.  Свойства «дерево документации
цело» по-прежнему ломаются всякой переименованием, и это записано в `objection` волны 62.


## 17. What is left, and who decides it

The work of waves 24–38 is closed and bound to fresh evidence.  What follows is
everything that is still open, written down in one place, so that nobody has
to reconstruct it from the history of the sessions.  The first list is work an
agent may do; the second list is the work only the owner may decide, and no
agent may decide it silently (`docs/PLAN.md` §13).

### 17.1 The open work of the code

**The delegation (Stage 7, after wave 36).**

- Several children in one turn of the parent work already: the audit of wave 35
  proved it, and the plan that said otherwise was wrong.  What is not proven is
  a *live* turn of a parent with two children of a live provider.
- The model of the child is the model of the preset, and the preset names it;
  no child of a live provider has run yet on a model other than the model of
  its parent.
- The depth of the tree of the children and the children of a run are in the
  journal since wave 37: the journal of the run holds the short id, the
  session and the depth of every child, and the journal of the child holds
  where the child stands in the tree.  A restart of the harness finds the
  child of a run again and tells what became of it, and a child that the
  journal holds no end of is not reported as a child that still works.
- A child that was running when the Emacs died is not brought back to life: the
  journal says that the child was delegated and what became of it, and the
  work of that child is lost, because nobody restarts it.
- The live checks do not exercise the delegation: the benchmark gives its runs
  a fixed set of tools, and the delegation is not among them.  The live
  evidence of a child that works is the fixed point, and that is one child and
  one task.
- The tools of the delegation are not in `yeah-builtins-specs` (the built-ins
  are the tools of the kernel, and the delegation is a tool of the product),
  so a reader of that list does not see them.

**The turn, and what the provider and the model do.**

- A model can end its turn with a message that announces an action and call no
  tool ("I'll look at the current state of calc.el.").  The harness cannot tell
  a promise of an action from an answer: the completion nudge fires when the
  model is silent and not when the model talks without acting.  Since wave 39 a
  run of the kernel is supervised by default, so such a model is nudged into
  the action; a model that spends the budget without an effect ends the run as
  a failed run, and the ACP route answers `refusal` and not `end_turn`.
- The harness cannot tell the research from the work: a model that reads the
  whole repository, measures a race with experiments of its own and never
  changes a file makes calls of tools like any other model, and the nudge
  names the tools the run has not called yet — among them `edit` and `write`.
  Two live runs of the wave 41 (2026-11-17, 15:45 and 16:16) found that
  shape: 108 calls of tools, no change of the repository.  A guard that asks
  the model for the change after a number of calls of tools without one is
  open work; nothing in the harness does it yet.
- Since wave 47 the model is told what the run has done: every request of a run
  carries the transcript of the run before the prompt, and the transcript is a
  projection of the journal — the tail of the records of the run, cut at twelve
  records and six hundred characters of the result of a tool.  What it is not
  is a context: a long run pays for the tail of its own work in every
  request, and the projection of the context (`lib/yeah-context.el`), the
  compaction and the pruning are still not on the road to the model.  The
  transcript fixes the memory of the model and not the shape of the provider,
  which still answers with a plan instead of an action: the two live runs that
  found the defect of the transcript were made with a model of that shape, and
  the run on the code of wave 47 is the measurement that says whether the two
  together are enough.
- Since wave 48 a request that the provider dropped is asked again: the
  death of the transport is not the death of the run.  The retry is bounded
  (two by default), the journal holds it as a record of its own, and the
  model is asked the same question with the transcript of the run in front of
  it.  A request the provider refused is not asked again.  What the wave does
  not repair is the run that meets a provider that is down: such a run ends
  after the budget of the retries, where it ended before the wave.
- Since wave 49 the compaction of the context waits for the answer of the
  provider: the thinking of a model is the road to the answer and not the end
  of the request, and the outcome of a compaction is delivered once.  What the
  wave does not repair: the wait has no bound of its own, so a provider that
  thinks and then says nothing leaves the run in the state `compacting` until
  the deadline of the run cancels it, and the decision of an answer is the
  decision of the shapes of gptel, so a transport that answers with shapes of
  its own ends the request of a summary without a summary.
- A caller that wants the old behaviour of the kernel (a run that ends as soon
  as the model answers with text) must now say so with an explicit budget of
  zero.  The default changed for every caller at once.
- A message that reports a finished work **and** announces the next step at
  the same time is a plan in part, and the harness does not see that part:
  `yeah-turn-plan-regexp` matches "I'll", "I will", "Let me", "Next I",
  "I'm going to" and "I am going to", so "All 15 tests pass.  Verifying the
  CLI end-to-end from a shell:" reads as a result.  The live coding run of
  wave 45 ended that way: the model announced a verification it never
  performed, and the run was completed.  The task was already done there, so
  the gap cost nothing; a task whose *last* step is the announced one would
  end as a completed run with the step missing.
- A run that ends on a text answer is a completed run even when the task
  asked for the tool `finish`: the live coding run of wave 45 was told to
  finish through `finish` and never called it.  The state of a run is
  therefore not a proof that the instructions of the task were followed; the
  check of the task is the arbiter.  Whether the kernel should require
  `finish` is a decision of the owner (§17.2).
- The budget of a child of a delegation is a separate default and is still
  zero: a child that only talks still ends as a completed child.  Whether a
  child that never calls `finish` is a failed child is a decision of the owner
  (§17.2).
- The provider answers with an empty message after a batch of tool results,
  with the status of a success (HTTP 200, `answer=""`).  Since wave 46 such a
  silence does not spend the budget of the nudges when the model has acted: the
  noise of the provider is not the refusal of the model, and a run that works
  must not be ended by it.  A model that never acts still ends, and the record
  of a run that did not finish says what the run did.
- The budget of the nudges is no longer a bound on the length of a run: it pays
  for the nudges that no effect answered, and a model that acts and then says
  nothing is not charged for the silence (wave 46).  The deadline of the run and
  the deadline of the request still bound it; a caller who wants a bound on the
  length of a run must set a deadline.
- The provider is overloaded for hours: HTTP 529 to both harnesses, a plain
  model call that answers with nothing now and then, and a transport that
  times out ("Curl failed with exit code 28").  A run that the provider stops
  is blocked and not a failure of the agent.
- A run that the provider *silences* and a run that the provider *fails* are
  not told apart by the runner of the benchmark: the silence is not an error
  record of the journal, so the runner records it as a failure of the agent,
  and a run that was never measured counts against the agent.  The pilot of
  wave 36 and the pilot of wave 37 measured the third task of Yeah in that
  shape (the sum was computed, the file was never written).  Whether that
  shape is a failure of the agent or a run that was never measured is a
  decision of the owner (§17.2), because it changes the number of every
  pilot (docs/LIVE-EVIDENCE.md, "The live checks and the pilot after wave
  37").
- The reason of the row of such a run names the shape of it since wave 38:
  the model answered with an empty message N times, or it described its next
  step N times and called no tool.  The shape is what the journal of the run
  holds, and the verdict of the row is still the verdict.
- The outcome of a run does not describe the work that was done: a run of
  `fix-failing-test` ended in "failed" because the provider failed after the
  edit, while the check of the task passed.  The check of the benchmark is the
  arbiter.

**The product.**

- A real editor (an agent-shell, or a person's Emacs) against a live provider:
  not yet checked.  The ACP agent and the MCP server are driven by a
  third-party client with a fake model, and the service path itself is
  verified with a live provider.
- The service path has no mode changes of the attached path and no opening of
  an earlier session by name.
- The bridge to the buffers of an attached Emacs is verified against a live
  Emacs server (a real daemon), and not against a person's Emacs in day-to-day
  use.
- The stdio server answers one request at a time: a cancel that arrives while
  a prompt is running is read after that prompt reaches a terminal state.  The
  socket transport does not have this limit.
- The picture of the interface is compared with itself and with the same
  buffer without the interface, and not with a stored golden picture.
- PTC stays an experimental, off-by-default restricted evaluator, and not a
  security boundary.

**The ACP surface, as an orchestrator sees it.**  The gaps below were found by
the integration with Paseo (docs/PASEO-INTEGRATION.md) and are still open.

- The working directory of a session — the `cwd` of `session/new` — is recorded
  in the journal and in the frozen input of the run, but the tools do not read
  it: a relative path of a tool is counted from the working directory of the
  Emacs process and not from the directory of the session.  An orchestrator
  that asks for a run in a repository gets a run in the directory of the
  service.
- The method `session/set_mode` does not exist: the permission profile of a
  session cannot be changed over the wire, and a client that asks is answered
  with `-32601`.
- The model of a session cannot be changed over the wire: neither
  `session/set_model` nor `session/set_config_option` exists, so an
  orchestrator cannot choose the model of a run.
- The `mcpServers` of a session are ignored: the tools of an MCP server that a
  client names do not reach the model.
- The `tool_call` of the wire names the tool and carries what it was called
  with and what it returned (`rawInput` and `rawOutput`), but no `kind`: a
  client that renders the call of a tool by its kind — a read, an edit, a
  shell — sees the name of the tool and nothing else.  The arguments of a
  call are positional, so a client that looks for named fields (`path`,
  `oldText`, `query`) does not find them.
- The process of the server outlives the agent.  A client that keeps the pipe
  of the server open after the last turn leaves an Emacs process alive, and
  some of those processes burn half a core in a tight loop of userspace: one
  of them was measured with 1.9 million involuntary context switches and six
  voluntary ones, and it never slept.  The read loop of the server is not the
  cause: an idle server costs no CPU and leaves cleanly when its input ends,
  and a server that waits for a turn the model never answers costs about four
  per cent of a core.  The spin is therefore on the path of the live request
  of the provider, and the loop itself is not localized yet.  The client that
  leaves the process behind is the plugin that spawned it: nothing closes the
  pipe of the server when the session of the agent is over.

**The rest of the surface, found on 2026-11-18.**  The list above is the
surface as it was on 2026-11-16 and as the plan of the owner names it
(§18.3, wave 43).  A second reading of the code of 2026-11-18 added four gaps
that this list does not name, and one of them is not in the core at all:

- The route of ACP in Paseo refuses a steering message before it sends the
  prompt (`packages/plugin/src/server/acp.test.ts`: "refuses unsupported
  steering before sending an ACP prompt").  The kernel has `session/steer`, so
  the ability is there and the orchestrator does not reach it.  The repair is
  in the repository of Paseo, not in this one.
- The outcome of a run does not travel over the wire: `usage`, `nudge`,
  `unfinished` and `error` are in the journal and not in `session/update`, so
  an orchestrator sees the `stopReason` and nothing else.
- Every connection to the provider creates a real session for the sake of the
  catalog of the provider, and that session stays in the journal of the kernel
  having done nothing.
- The plugin of Paseo speaks to a fresh Emacs process per connection instead
  of the service of the kernel over its socket.  The socket is the transport
  that lets a cancellation preempt a running prompt, and the service is the
  primary placement of this harness (§7 of `docs/ARCHITECTURE.md`).

The reading itself, with the evidence for every gap, is
`docs/PASEO-INTEGRATION-PLAN.md`.  The plugin of Paseo lives in this
repository now, in `plugin/yeah-provider/` (decision of the owner,
2026-11-18); it was outside the repository and outside version control
before that, and the two facts are recorded in the revision 4 of
`docs/PASEO-INTEGRATION.md`.

**The measurement.**

- The pilot is three tasks.  The sample is small, and the numbers of the runs
  of waves 33, 34, 35, 36, 37 and 38 (2 of 3, 1 of 3, 2 of 3 and one blocked,
  2 of 3, 2 of 3) differ by the noise of the provider and of the model.
- The second harness is `pi` 1.1.0, which is checked in the environment;
  `opencode` is not installed here.
- One verifier of the standing specification is a race.  The check of
  `bridge-keeps-the-answer` reads the buffer of an attached Emacs a hundred
  and twenty times while a thread keeps the parent late, and it fails only
  when the answer is really lost.  Six runs of the evidence bound that claim
  on 2026-11-16: five bit, and one did not — the control reached the
  subject, the verifier after the control still passed, the claim came out
  `inconclusive`, and the map came out `unknown`.  A claim whose control does
  not always bite is not established: until the check of that race is
  deterministic, the verdict of the map can be `unknown` for a reason that has
  nothing to do with the code it names.  The claim itself is not weakened
  here, and nobody may quote it as established on the strength of the runs
  where the race happened.

### 17.2 The decisions of the owner

None of these may be decided by an agent.  Each of them is recorded with
`mathc record` when a person decides it, and not by an edit of the code.

**One of them was decided on 2026-11-16 (az): the priority of the next wave.**
It is recorded as the judgment claim
`the-owner-decided-the-order-of-the-next-waves` — a human review, bound to
the materials of this repository by `mathc record` — and the plan that the
decision refers to is §18.  The decisions that §18.5 names stay open: no
wave of that plan takes them, and no agent may take them either.

- The threshold of the parity, and the final set of the tasks of the benchmark
  (`docs/PLAN.md` §13).  Until the threshold is decided, the parity is not
  claimed anywhere, and the pilot stays a measurement.  **Open** (§18.5).
- Whether a run that the provider silenced is a failure of the agent or a run
  that was never measured.  The runner of the benchmark knows a run that the
  provider failed from the error records of the journal; the silence of the
  provider is not an error record, so such a run counts against the agent
  today.  The decision changes the number of every pilot, and the pilot of
  wave 36 measured a task of Yeah in that shape (docs/LIVE-EVIDENCE.md, "The
  live checks and the pilot after wave 36").  **Open** (§18.5).
- The second harness of the comparison, if it is not `pi`.
- The placement of the frame server for the pixel check.  The check is outside
  the map of the method: without a frame server it is blocked, and not a pass.
- The priority of the next wave: the parallel children of Stage 7, a wider
  pilot, a real editor against a live provider, or the gaps of the service
  path.  **Decided on 2026-11-16 (az):** the order is wave 41 (the
  deterministic verifier of the bridge), wave 42 (the process of the server),
  wave 43 (the surface of ACP for an orchestrator), wave 44 (parallel
  children in a live turn) — §18, recorded as the judgment claim
  `the-owner-decided-the-order-of-the-next-waves`.
- The minimum versions of Emacs and gptel, and the cycle of the releases.
- The policy of the unattended command and of the network.
- Whether a restricted evaluation deserves a design of its own process at all.
- The access of the service to the personal buffers of the person.
- The channels of the distribution and the signing of the packages.
- The compatibility with Apache-2.0 of every optional integration.
- The budget of the completion supervision of a child of a delegation.  The
  default of the kernel is positive since wave 39, and the default of the child
  is still zero: a child that only talks and never calls `finish` ends as a
  completed child today.  The wave did not change the default of the child,
  because the claims of the delegation (§17.1) do not say that a child that
  never finishes is a failed child, and a silent change of that meaning would
  make the claims of wave 35–37 untrue.  **Open** (§18.5).

### 17.3 The order, if the owner says nothing

The owner did say something about the next waves on 2026-11-16 (az), and that
order (§18) comes first.  What follows is the order of the rest, if the
owner says nothing about them either.

1. **The pilot again**, with a larger set of tasks, when the provider answers.
   The row of a run that did not finish names the shape of it since wave 38,
   so a reader of the pilot sees the cause of a failed check and not only its
   verdict.  Whether such a run is a failure of the agent or a run that was
   never measured is still the decision of the owner (§17.2), because it
   changes the number of every pilot.
2. **The pixel check**, when the owner names the place of the frame server.

Wave 38 closed the naming of the shape: the reason of the row of a run that
did not finish says what the journal of the run holds, and the verdict of the
row is not touched by that.

Wave 37 closed the depth of the tree: the children of a run and their depth are
in the journal now, and a restart of the harness finds the child of a run again
and tells what became of it.

Wave 36 was the plan above that said otherwise: it was to be the parallel
children of the delegation, and the audit proved that several children in one
turn of the parent work already.  Wave 36 was the defect that the audit found
instead — the delegation was written into the journal of another run — and with
it the short id of the child and the time of the child.

Re-opened when a person says so: the math-coding aim block in AGENTS.md is
written by `mathc install` and is not edited by hand.

## 18. The plan of the next waves

The owner named the order of the next waves on 2026-11-16 (az), after the
report on the readiness of Yeah for self-development and after the
integration with the orchestrator Paseo.  The decision is recorded by the
method as the judgment claim `the-owner-decided-the-order-of-the-next-waves`
(a human review, not a machine verifier), and this section is the plan that
the decision refers to.  The order is by the price of the defect: the wave
that makes the verdict of the method unreadable goes first, and the wave that
opens the path from a model to a working program goes last.

The order of the next waves, named by the owner on 2026-11-16: **wave 41, wave 42, wave 43, wave 44.**

They are: wave 41 (the deterministic verifier of the bridge), wave 42 (the
process of the server), wave 43 (the surface of ACP for an orchestrator), wave
44 (parallel children in a live turn).

One wave was executed before them: **wave 45** (2026-11-17), the repair of
the harness that the live test of the harness forced — a tool that returns
bytes that are not text took the whole Emacs process down, and the four
waves of this plan need a harness that lives to carry them (§16.24).  The
order named by the owner is unchanged: wave 41 is still the first of the
four.

Every wave below names the defect it removes, the claims it registers, the
control that has to bite, and the criteria that close it.  A wave that ends
without a control that bites is not a wave: it is a change of the code with
no evidence.

### 18.1 Wave 41 — the verifier of the bridge decides the race by construction

**The defect.**  One verifier of the standing specification is a race.  The
check of `bridge-keeps-the-answer` reads the buffer of an attached Emacs a
hundred and twenty times while a thread keeps the parent late, and it fails
only when the answer is really lost.  Six runs of the evidence on 2026-11-16:
five bit, one did not — the control reached the subject, the verifier after
the control still passed, the claim came out `inconclusive`, and the map came
out `unknown`.  The code was not the cause of that verdict; the evidence was.

**Why this wave is first.**  Every other wave of this plan ends with a run
of the method, and a run whose verdict depends on a race may say `unknown`
for a reason that has nothing to do with the code it names.  A map that says
`unknown` because of a race cannot be read.

**What changes.**  The check stops racing the subject and starts commanding
it: the loss of the answer becomes a condition that the check arranges — a
barrier the parent waits for, a hook the check owns — so that the same
input gives the same verdict every time.  The control of the claim becomes
the same arrangement with one step removed, and the check must then fail by
its own assertion.

**The claims.**
- `bridge-keeps-the-answer` — the existing claim, re-bound with a control
  that bites every time (register `fact`, requirement: the check of the
  bridge).
- `the-bridge-check-decides-the-race-by-construction` — a new claim: the
  check of the bridge gives the same verdict on ten consecutive runs of the
  control, and the control bites on each of them (register `fact`).

**The exit criteria.**
1. Ten consecutive runs of the control bite: every one of them fails by an
   assertion of the check, not by a crash of Emacs and not by a timeout.
2. Two consecutive runs of the method end in `green`, with no `inconclusive`
   claim and no `unknown` verdict.

**The estimate.**  Half a day to a day.  **What this wave does not fix.**  It
repairs the evidence, not the harness: nothing of the run itself changes.

**The execution (2026-11-17).**  The wave was carried out by the harness
itself: a live model (`MiniMax-M3.1-Flash`) worked on a copy of the repository
in a live run of Yeah, and the journals of the copy
(`sessions/wave41g.jsonl`, `sessions/wave41h.jsonl`) hold the run.  The model
wrote the check of the wave
(`tests/checks/check-bridge-check-decides-the-race-by-construction.el`) and
found three defects in it while it worked: the keys of a JSON object come as
symbols from Emacs 30 (so the control of the claim of the bridge was never
found and the check said "the claim of the bridge declares no control to
run"), `file-copy-file` does not create the directory of the target, and the
buffer of the words of a run was bound in a `let` that binds in parallel (the
filter of the process saw a void variable).  The model registered the new
claim in `spec.json` with a control that breaks the determinism of the check,
and it did not touch the claim of the bridge, whose control bit ten times of
ten.  The first run was killed by the machine after the changes were made and
verified; the second run picked the work up from the tree, checked the three
criteria of the exit and finished through the `finish` tool (the state of the
run was `completed`).  The evidence of the wave is in docs/LIVE-EVIDENCE.md,
the section "The self-development run that finished the wave 41".

**What the execution does not prove.**  The wave repairs the evidence of the
bridge; it does not repair the harness and it does not measure the parity of
the harnesses.  The second criterion of the exit (two consecutive runs of the
method that end in `green`) depends on the human review of the plan of the
owner being fresh at the time of the run: that review is a decision of the
owner and not a machine verifier (docs/PLAN.md 17.2), and any later edit of
this plan makes it stale again.  The runs, their verdicts and their dates are
in docs/LIVE-EVIDENCE.md.

### 18.2 Wave 42 — the server does not outlive the agent, and it does not spin

**The defect.**  Two defects of one life cycle.  The process of the ACP
server outlives the agent: a client that keeps the pipe of the server open
after the last turn leaves an Emacs process behind, and nothing closes it.
And some of those processes burn half a core in a tight loop of userspace:
one of them was measured with 1,921,354 involuntary context switches and six
voluntary ones — it never slept — at 25–60 % of a core.

**What is known and what is not.**  The read loop of the server is not the
cause: an idle server costs no CPU and leaves cleanly when its input ends,
and a server that waits for a turn the model never answers costs about four
per cent of a core.  The spin is therefore on the path of the live request of
the provider, and the loop itself is not localized yet: `ptrace` and `strace`
are not available in this environment ("Operation not permitted"), so the
localization has to be done by measurement — the ticks of `/proc/<pid>/stat`,
not the percentage of the CPU that `top` prints.

**What changes.**
1. *The life cycle.*  The server has a way to end that does not depend on the
   client closing the pipe: the session ends, and the process exits.  The
   plugin of Paseo (`yeah-provider`, outside this repository) closes the pipe
   of the server when the session of the agent is over; the kernel side gives
   it a way to say so.
2. *The spin.*  The loop on the path of the live request is localized by
   instrumentation — a counter of the iterations of the pump and of the
   request of the provider — measured the way the defect itself was measured.
   The loop that spins is then removed, and the bound becomes a check.

**The claims.**
- `the-server-exits-when-the-session-is-over` — the process of the server is
  gone after the session ends, even when the client keeps the pipe open
  (the control keeps the pipe open and ends the session: the check must
  fail).
- `the-server-does-not-spin-when-the-provider-is-silent` — a server whose
  provider went silent costs less than one per cent of a core over ten
  seconds (the control brings the busy loop back: the measured ticks must
  exceed the bound).

**The exit criteria.**
1. A server left behind by a finished session is gone within ten seconds.
2. The ticks of a silent server stay under the bound in ten consecutive
   measurements.
3. The live check of the plugin leaves no process behind.

**The estimate.**  One to two days.  **What this wave does not fix.**  A
transport that dies with "Curl failed with exit code 28" is the provider's
death, not the harness's.

### 18.3 Wave 43 — the surface of ACP that an orchestrator needs

**The defect.**  The integration with Paseo found four gaps of the surface,
and all of them point the same way: an orchestrator cannot put the agent
where the work is, cannot change what the agent may do, and cannot read what
the agent did.

1. The working directory of a session — the `cwd` of `session/new` — is
   recorded in the journal and in the frozen input of the run, but the tools
   do not read it: a relative path of a tool is counted from the directory of
   the Emacs process and not from the directory of the session.  In the live
   check the `bash` of the agent ran in the directory of the installation of
   the CLI of Paseo, not in the repository of the task.
2. The method `session/set_mode` does not exist: the permission profile of a
   session cannot be changed over the wire, and a client that asks is
   answered with `-32601`.
3. The model of a session cannot be changed over the wire: neither
   `session/set_model` nor `session/set_config_option` exists.
4. The `tool_call` of the wire names the tool and carries what it was called
   with and what it returned (`rawInput` and `rawOutput`, since wave 40), but
   no `kind`: a client that renders the call of a tool by its kind — a read,
   an edit, a shell — sees the name of the tool and nothing else.  The
   arguments of a call are positional, so a client that looks for named
   fields (`path`, `oldText`, `query`) does not find them.

**What changes.**  The gaps are closed in the order of what the live
integration needs today: the `cwd` first, because the agent must work in the
repository of the task; then the `kind` of the call and its named arguments,
because the client must be able to show what the agent did; then
`session/set_mode`; then the model of the session; then the `mcpServers` of
the session, whose tools do not reach the model today.

**The claims.**  Each gap is a claim of its own, and the name of the claim is
the name of the gap: `a-session-runs-in-its-own-directory`,
`a-tool-call-carries-its-kind`, `a-tool-call-carries-named-arguments`,
`a-session-changes-its-permission-profile-over-the-wire`,
`a-session-changes-its-model-over-the-wire`,
`the-mcp-servers-of-a-session-reach-the-model`.

**The exit criteria.**
1. The check of the `cwd` sends a session into a temporary directory, and the
   tool of that session sees the temporary directory and not the directory of
   the process.
2. The plugin of Paseo runs a turn in the repository of the task, and the
   timeline of the client shows the kind of the call of the tool.
3. The wire answers `session/set_mode` and no longer answers `-32601`.

**The estimate.**  Two to three days.  **What this wave does not fix.**  The
wire of Yeah is ACP plus the one extension that was announced
(`yeah.queueEvents`); this wave adds no method that ACP does not have.

### 18.4 Wave 44 — parallel children in a live turn

**The defect.**  Several children in one turn of the parent work already: the
audit of wave 35 proved it, and the plan that said otherwise was wrong.  What
is not proven is a *live* turn of a parent with two children of a live
provider.  No child of a live provider has run on a model other than the
model of its parent, and the live checks do not exercise the delegation at
all: the benchmark gives its runs a fixed set of tools, and the delegation is
not among them.

**What changes.**  The live check grows a second child in the same turn of
the parent, and the offline check with a fake model becomes the claim that
the map binds — the live check lives outside the map, because it needs a
provider.

**The claims.**
- `two-children-run-in-one-turn-of-the-parent` — the claim of the map, with a
  fake model: two delegations in one turn of the parent give two children,
  both alive, and the turn of the parent goes on (the control refuses the
  second delegation: the check must fail).
- `a-child-runs-on-the-model-of-its-preset` — the model of a child is the
  model of the preset, and not the model of its parent (the control names
  another model in the preset: the child must run on it).

**The exit criteria.**
1. The offline check passes and its control bites.
2. The live check with a real provider shows two children in one turn of the
   parent, and the tree of the children in the journal holds both.

**The estimate.**  One to two days, and a key of the provider for the live
part.  **What this wave does not fix.**  The budget of the completion
supervision of a child is zero today, and that is a decision of the owner
(§17.2), not a defect of this wave.

### 18.5 What this plan does not decide

Three decisions of the owner stay open, and no wave above takes them:
- the threshold of the parity, and the final set of the tasks of the benchmark
  (`docs/PLAN.md` §13): until it is decided, the parity is not claimed
  anywhere, and the pilot stays a measurement;
- whether a run that the provider silenced is a failure of the agent or a run
  that was never measured: it changes the number of every pilot;
- the budget of the completion supervision of a child of a delegation: the
  default of the kernel is positive since wave 39, the default of the child is
  still zero.

Two more items of the open work (§17.1) are not in the order above and stay
where they are: the pilot again, with a larger set of tasks, when the
provider answers; and the pixel check, which waits for the owner to name the
place of the frame server.

### 18.6 How this plan is measured

- One run of the method per wave, and a new run only for a new reason.
- Every new claim names its control before its check is written, and the
  control is shown to bite by an assertion of the check — not by a crash of
  Emacs and not by an unreadable test.
- The verdict of the map is the verdict of the wave: a wave that ends in
  `unknown` is not finished, whatever the code looks like.
- The live checks stay outside the map: they need a provider, and a check that
  cannot run without a key is `blocked`, not `pass`.
- A claim that the owner decides (a judgment) is recorded with
  `mathc record`, and never by an edit of the code.

---

## 19. План интеграции с оркестратором Paseo

**Что этот план решает.**  Yeah становится агентом оркестратора Paseo:
человек выбирает «Yeah» в Paseo и получает агента, который работает в
репозитории задачи, показывает оркестратору, что он делает, и уходит, когда
работа кончена.  Критерий готовности — восемь пунктов
`docs/PASEO-INTEGRATION-PLAN.md` §4.3; разбор разрывов — там же, §3.

**Порядок работ.**  Порядок владельца (§18) и порядок §16.30 не меняются;
этот раздел их не переписывает, а раскладывает по волнам и добавляет четыре
пункта, которых в плане владельца нет.

| Волна | Что | Claim'ы | Кто |
|---|---|---|---|
| 42 | Сервер не переживает агента: сессия кончилась — процесс ушёл | `the-server-exits-when-the-session-is-over` | параллельная сессия (`waves/wave-42.json`, расширение `session/exit`) |
| 54 | Спин: сервер с молчащим провайдером не жжёт ядро | `the-server-does-not-spin-when-the-provider-is-silent` | сделано 2026-11-18 (§16.38) |
| 43 | Поверхность ACP для оркестратора: `cwd`, род вызова и именованные аргументы, `session/set_mode`, модель, `mcpServers` | шесть claim'ов §18.3 | следующий |
| 44 | Дети параллельно в живом ходу | `two-children-run-in-one-turn-of-the-parent`, `a-child-runs-on-the-model-of-its-preset` | после 43 |
| 51 | Журнал прогона защищён от прогона | — | по §16.30 |
| 52 | `cwd` сессии доходит до инструментов, если волна 43 не доводит | — | условно |

Вне плана владельца (детали и места — `docs/PASEO-INTEGRATION-PLAN.md` §4.2):
- **P-A.**  Маршрут ACP в Paseo отказывает в steering'е
  (`packages/plugin/src/server/acp.test.ts:766`), хотя ядро умеет
  (`lib/yeah-acp.el`, `session/steer`).  Правка лежит в чужом репозитории
  (`/home/az/Projects/paseo`): решение владельца — апстрим PR или форк.
- **P-B.**  Исход прогона не виден оркестратору: по проводу идут восемь видов
  событий, а `usage`, `nudge`, `unfinished` и `error` — нет.  Механизм
  расширения уже есть (`yeah.queueEvents` в `_meta`).
- **P-C.**  Discovery создаёт настоящую сессию: каждый список моделей
  оставляет сессию в журнале.
- **P-D.**  Плагин поднимает свой Emacs на каждое соединение вместо
  сервисного по сокету.  Плагин живёт в этом репозитории
  (`plugin/yeah-provider/`), поэтому это теперь работа без чужого дерева.

**Находка сессии 2026-11-18, которая двигает план.**  `session/close` — не
выдумка: это метод ACP, и клиент Paseo его **уже вызывает**.  В SDK он
уехал как `unstable_closeSession` (`sendRequest("session/close")`), а клиент
оркестратора зовёт `closeSession()` при закрытии сессии агента
(`packages/plugin/src/server/acp-internal/connection.ts:690-698`) и глотает
ошибку (`.catch(() => undefined)`).  Ядро на `session/close` отвечает
`-32601` («Method not found») — так оно и было в разборе §3.6.

Это важно для порядка: расширение `session/exit` из волны 42 само по себе до
клиента Paseo не доходит — клиент шлёт `session/close`, а не `session/exit`.
Чтобы интеграция ожила, нужно одно из двух, и решение здесь не заменяет
собой решение владельца:

1. ядро отвечает и на `session/close` (метод ACP), и на `session/exit`
   (расширение) — две двери к одному действию; или
2. плагин переводит `session/close` клиента в `session/exit` ядра — тогда
   расширение остаётся единственным путём, а плагин решает, что значит
   «сессия кончилась» для его клиента.

Первый путь проще и честнее по протоколу: `session/close` — часть ACP, и
клиент, который его знает, не должен ждать расширения.

**Что остаётся за владельцем.**  Порог паритета и итоговый набор задач
бенчмарка (§13); «провайдер заsilenceл» — это провал агента или непомеренный
запуск (§17.2); бюджет надзора дочернего агента (§18.5); апстрим или форк
для P-A.
