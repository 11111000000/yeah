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


### 16.48 Журналы, которые называет документация, лежат в репозитории — **сделано 2026-11-19 (волна 64)**

**Дефект.**  Слияние `origin/main` в `main` (коммит f975b80, 2026-11-19) вскрыло ошибку
документации, которая молчала четыре года.  Документация называет журналы живых прогонов
(`sessions/calc.jsonl`, `sessions/wave41g.jsonl`, `sessions/wave41h.jsonl`,
`sessions/wave42-1.jsonl`), а в этом репозитории их не было: они лежали в копиях, на которых
шли прогоны.  До слияния каталога `sessions/` в репозитории не было вовсе — `origin/main` завёл
его коммитом d162d3c, — и правило проверки «имя называет путь репозитория, когда его первая
часть — сущность верхнего уровня» не считало `sessions/calc.jsonl` именем репозитория: имя не
указывало ни на что, и проверка молчала.  Слияние принесло из `origin/main` пять журналов
(`sessions/wave41.jsonl`, `sessions/wave41b.jsonl`, `sessions/wave41c.jsonl`,
`sessions/wave41d.jsonl`, `sessions/wave41e.jsonl` — 5 295 312 байт), `sessions/` стал
каталогом репозитория, и правило начало требовать того, что документация давно обещала:
названный журнал должен лежать в репозитории.

**Что сказал гейт.**  Гейт №6 (2026-11-19, 02:29:33Z, отдельная сессия, 13 мин 44 с,
`GATE_EXIT=1`) — первый полный гейт после слияния.  Карта красная: 143 claim'а, 142 holds,
один `refuted`, `uncovered: 0`, и единственный не-зелёный claim —
`the-documentation-points-at-files-that-exist`.  Проверка отработала за 378 мс и дала шесть
имён на пяти строках: четыре в `docs/LIVE-EVIDENCE.md` (строки 930, 1250, 1251 и 1356 — на
момент гейта) и два в одной строке `docs/PLAN.md` (строка 3468 — на момент гейта).
Проверка падала по своей собственной причине: имя не ведёт ни к одному файлу репозитория.
Молчала не проверка, а документация: четыре года имя указывало в пустоту, и у правила не было
основания спросить.

**Что сделано.**  Журналы положены в репозиторий туда, куда их уже клала документация и куда
их положил `origin/main` для пяти других: в `sessions/`.

- `sessions/calc.jsonl` — 91 348 байт, 118 записей: ровно то, что написано в
  `docs/LIVE-EVIDENCE.md` строкой 930 («118 records, 91 348 bytes»).
- `sessions/wave41g.jsonl` — 641 365 байт, 501 запись.
- `sessions/wave41h.jsonl` — 665 833 байт, 578 записей.
- `sessions/wave42-1.jsonl` — 2 981 451 байт, 2464 записи: ровно то, что написано в
  `docs/LIVE-EVIDENCE.md` строкой 1356 («2464 records»).

Числа записей совпали с документацией до записи, а не после: журналы те самые, что описаны.
Все четыре взяты из копий, на которых шли прогоны (`yeah-live-2`, `yeah-selfdev-1`,
`yeah-selfdev-2`), и ни в одной ветке репозитория их не было.  Поиск по обычным формам
ключей (`sk-…`, `api_key=`, `Bearer …`, `eyJ…`, `AKIA…`) в четырёх файлах ничего не нашёл.

**Побочная находка: проверка ловит и сокращённый вид.**  Первая редакция этого раздела
называла журнал сокращённо — многоточием в конце пути, — и проверка сказала «it names
sessions/..., and there is no such file».  И это её собственная причина, а не дефект: три
точки входят в класс допустимых символов имени, поэтому такое сокращение читается как
буквальный путь, которого нет, — в отличие от звёздочки и вопросительного знака, которые
проверка отбрасывает как шаблоны.  Документация называет каталог `sessions/`.  Находка
полезна тем, что она показывает границу правила дословно: сокращать путь многоточием в
документации нельзя.

**Почему не переписать документацию.**  Это первое возражение, и оно кажется очевидным: не
тащить 4.3 МБ вывода прогонов в репозиторий, а убрать из документации имена, которые ни на
что не ведут.  Ответ: репозиторий уже хранит журналы живых прогонов под тем же правилом —
пять файлов на 5.3 МБ пришли из `origin/main`, — и документация называет их в форме пути
репозитория с самого первого живого прогона.  Имя `sessions/calc.jsonl` стоит рядом со
словами «journal of the session», а `sessions/wave42-1.jsonl` — рядом со словами «its
journal», и читатель идёт по этому имени.  Переписать документацию — значит выбросить ссылку
на прогон, ради которого документация и написана, и сделать вид, что прогона не было; в
волне 63 такой ход уже был отклонён как искажение записей журнала.

**Критерий выхода.**

1. Базовая линия зелёная: проверка `the-documentation-points-at-files-that-exist` проходит на
   живом дереве и в изолированной копии репозитория.
2. Контроль кусается: scope изменён, код контроля 0, код проверки после контроля 1, и падает
   проверка своим собственным утверждением.
3. Ни один claim не имеет `sessions/` в scope, поэтому появление файлов не обесценивает
   материал ни одного claim'а.

**Что эта волна не делает.**  Она не добавляет свойств и не переписывает документацию: имена,
на которые указывает документация, верны — верна была документация.  Свойства «дерево
документации цело» по-прежнему ломаются всякой переименованием, и это записано в `objection`
волны 62.


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

### 16.49 Провод говорит, чем закончился прогон — **сделано 2026-11-19 (волна 65)**

**Дефект.**  Оркестратор видел, что прогон закончился, и не видел, чем он
закончился.  Ядро пишет в журнал всё, что нужно человеку: потраченные токены,
подталкивание, которое вытолкнуло модель в действие, прогон, кончившийся без
эффекта, и ошибку, которая остановила прогон, — а по проводу шли восемь видов
событий, и среди них не было ни одного из этих.  Оркестратор получал
`stopReason` и слова агента, и прогон без эффекта выглядел как прогон, который
закончился.

Это пункт P-B плана интеграции (`docs/PASEO-INTEGRATION-PLAN.md` §3.8, §4.2) —
вне плана владельца (§18), поэтому номер волны взят следующим свободным, а
владелец может переименовать.

**Что сделано.**  Ядро проецирует исход прогона тем же приёмом, каким уже
проецируются события очереди: клиент просит об этом в `_meta` своих возможностей
при `initialize` — `yeah.runOutcome`, рядом с `yeah.queueEvents`.

- Токены едут как `usage_update`: это вид ACP, и оркестратор считает их сам
  (`packages/plugin/src/server/acp-internal/connection.ts`, `usage_update`).
- `nudge`, `unfinished` и `error` едут как уведомление `yeah/outcome`: это не
  метод ACP, и его переводит плагин в vendor-обновление через
  `notification`-трансформер (`AcpVendorUpdate`).
- Клиент, который ничего не просил, не получает ничего: словарь Yeah едет
  только туда, куда его позвали.

**Побочная находка: схема провода отстала от кода.**  Волны 42 и 43 добавили в
провод `session/close`, `session/set_mode`, `session/set_config_option`,
`current_mode_update` и `config_option_update` — и не тронули `schemas/acp-v1.json`,
хотя схема и есть «мерило провода» (`tests/checks/check-wire-speaks-acp.el`).
Волна привела схему в соответствие и объявила в ней то, что добавила сама.
Противоречие записано здесь, а не разрешено молча.

**Критерий выхода.**
1. Проверка проходит, а её контроль кусается утверждением самой проверки.
2. Claim'а зарегистрирован, и карта его держит.

**Чего волна не доказала.**  Проверка доказывает сторону ядра.  Перевод плагина
доказан тестами плагина, а появление исхода прогона в таймлайне Paseo не
наблюдалось: живой маршрут через UI не прогонялся.  Размер контекста в
`usage_update` — это бюджет ядра, а не окно провайдера: ядро не знает окна
провайдера и не гадает.

**Контроль.**  `sed -i 's|(yeah-acp--send-outcome state type fields)|nil|' lib/yeah-acp.el` —
в копии дерева проверка кончилась кодом 1 и своими словами: «the wire carried
no nudge: the client that asked for the outcome was not told: nil».

---

### 16.50 Серверы MCP сессии говорят по HTTP — **сделано 2026-11-19 (волна 66)**

**Дефект.**  Ни один агент Yeah не мог запуститься внутри оркестратора Paseo, и
причина была в транспорте MCP, а не в модели, не в инструментах и не в проводе
ACP.  Ядро говорило только stdio (волна 43, часть 5), а Paseo называет свой
собственный MCP-сервер по HTTP: оркестратор отдаёт агенту сервер вида
`{type: http, url: http://127.0.0.1:6767/mcp/agents?callerAgentId=…, headers:
[{name: Authorization, value: Bearer …}]}`
(`packages/plugin/src/server/acp-internal/connection.ts`, `toAcpMcpServers`;
`packages/server/src/server/agent/runtime-mcp-config.ts`,
`withRuntimePaseoMcpServer`).  На такое имя ядро отвечало отказом поимённо —
«Yeah speaks stdio only» — и сессия закрывалась до первого токена.

Живой прогон 2026-11-19 через UI Paseo умер ровно на этой строке: `Error: Failed
to create agent: the MCP server paseo speaks http; Yeah speaks stdio only`.

**Что сделано.**  Транспорт MCP — свойство агента, а не плагина, поэтому чинится
в ядре.

- Новый модуль `lib/yeah-mcp-http.el`: минимальный асинхронный клиент HTTP/1.1 на
  `make-network-process`.  Сокет читается бинарным (`:coding 'binary`), потому что
  размеры чанков HTTP измеряются в байтах; текст декодируется в одном месте через
  `lib/yeah-text.el`, и байт, который не текст, не может убить процесс (волна 45).
- Разбирается голова ответа (статус, заголовки, `content-length`,
  `transfer-encoding: chunked`), декодируются чанки, читаются события
  server-sent events MCP, каждое сообщение JSON-RPC уходит клиенту, а сокет
  закрывается после сообщения с `id` — сервер MCP поверх HTTP из SDK оркестратора
  не хранит состояние, и его поток сам не кончается.
- Заголовки `Mcp-Session-Id` и `MCP-Protocol-Version` поддержаны, поэтому сервер
  с состоянием работает тоже.
- Транспорт `sse` отвергается поимённо («Yeah speaks stdio and http only»),
  `https` — тоже («Yeah speaks http only»): TLS в Emacs-сокете нет.
- Ядро объявляет это в рукопожатии ACP: `mcpCapabilities: {http: true, sse: false}`.

**Критерий выхода.**
1. Проверка проходит, а её контроль кусается утверждением самой проверки.
2. Claim'а зарегистрирован, и карта его держит.

**Что доказано.**  Проверка поднимает настоящий ACP-сервис на сокете, открывает
сессию с MCP-сервером по HTTP (сервер проверки — форма сервера Paseo: без
состояния, ответ приходит потоком событий MCP поверх HTTP) и доказывает четыре
вещи на проводе: сессия отвечена и не отказана; инструменты сервера доходят до
модели, и модель зовёт один из них; вызов модели доходит до сервера; заголовок,
который назвал клиент, доходит до сервера.

**Чего волна не доказала.**  Живой маршрут через UI Paseo после этой волны не
наблюдался — это отдельная проверка (§16.51 не существует; маршрут открыт в §19).
Транспорт — HTTP/1.1 и без TLS.  Клиент закрывает сокет после ответа с `id`:
это верно для stateless-сервера и неверно для сервера, который шлёт уведомления
после ответа; такой сервер требует живой сессии по `Mcp-Session-Id`, заголовок
ядро держит и шлёт, но проверка такой случай не покрывает.  Статус HTTP ядро не
переводит: 401 оркестратора (нет capability-токена или он неверен) — это отказ
транспорта, и волна не делает вид, что ядро починит токен, которого ему не дали.

**Контроль.**  `sed -i 's|(yeah-mcp-http--events client)|nil|' lib/yeah-mcp-http.el` —
в копии дерева проверка кончилась кодом 1 и своими словами: «the wire refused the
session with an MCP server over HTTP: … did not answer the handshake in 10
seconds» и «the model of the session did not use the tool of the server».  Путь
stdio не сдвинулся: `check-the-mcp-servers-of-a-session-reach-the-model.el` зелёный.

---

### 16.51 Проба каталога не оставляет пустых сессий — **сделано 2026-11-19 (волна 67)**

**Дефект.**  Журнал проекта был полон сессий, которых не было.  Оркестратор
читает каталог моделей и режимов через настоящую сессию: `discover()` в маршруте
ACP вызывает `session/new` и **не закрывает** открытую сессию
(`packages/plugin/src/server/acp-internal/connection.ts`, `discover`), а ядро писало
файл сессии в момент её открытия — файл с одной строкой-заголовком и больше ни
чем.  Каждый список моделей, каждая диагностика и каждый прогон оставляли ещё
один такой файл: в данных пользователя к 19 ноября лежало больше сотни файлов
по одной записи, и именно в том месте, где человек ищет правду о прогоне.

**Что сделано.**  Файл сессии появляется, когда сессия пишет первую запись, а не
когда её открывают.

- Заголовок остаётся первой строкой файла, идентификаторы остаются
  монотонными, журнал остаётся append-only — просто сессия, которая ничего не
  сделала, не оставляет файла вовсе.
- Переключатель `yeah-session-journal-from-the-start` (по умолчанию выключен)
  возвращает прежнее поведение: человек, который хочет видеть сессию в списке
  сессий проекта до того, как она что-то сделала, включает его сам.  Этот
  переключатель — и есть то, что поворачивает контроль claim'а.
- Сессия, которая ничего не писала, не попадает в список сессий проекта, но ядро
  её знает: `session/load` отвечает на неё (файла нет — переигрывать нечего,
  `replayed` равен 0).  Отказ остаётся для сессии, о которой процесс не знает
  ничего: `unknown ACP session`.  Прежняя формулировка волны («сессия, которой
  не было, не возобновляется») оказалась неверной: сессия, которой не было на
  диске, жива в процессе, и волна это говорит прямо.

**Побочная правка.**  Юнит-тест `yeah-session-open-creates-empty-log` закреплял
старое поведение («открытие сессии создаёт файл с заголовком»).  Он **поправлен,
а не удалён**: теперь он говорит, что открытие не пишет файл и что файл
появляется с заголовком при первой записи сессии.  Это изменение контракта
ядра, и оно названо здесь.

**Критерий выхода.**
1. Проверка проходит, а её контроль кусается утверждением самой проверки.
2. Claim'а зарегистрирован, и карта его держит.

**Что доказано.**  Проверка поднимает настоящий ACP-сервис на сокете, открывает
сессию так, как открывает её оркестратор (проба: без промпта, без прогона), и
доказывает три вещи: проба не оставила в журнале проекта ни одного файла
сессии; сессия этого процесса загружается без файла (`session/load` отвечает,
`replayed` равен 0) и загрузка тоже не оставляет файла; сессия, о которой
процесс не знает ничего, отказана; сессия, которая делала работу, оставила
журнал, чья первая строка — заголовок.

**Чего волна не доказала.**  Проверка доказывает поведение ядра.  Старые файлы
волна не убирает: журнал append-only, и волна не удаляет записи — их убирает
человек.  Два процесса, пишущие в журнал одной сессии одновременно, — это
гонка, которую ядро не разбирает и на которую не претендует.

**Контроль.**  Два контроля, оба в копиях дерева, оба кусаются утверждением
самой проверки.

1. `sed -i 's|(defcustom yeah-session-journal-from-the-start nil|(defcustom yeah-session-journal-from-the-start t|' lib/yeah-session.el` —
   проверка кончилась кодом 1 и своими словами: «the probe of the catalog left
   1 session file(s) in the journal: …».
2. Возврат прежнего отказа в `session/load` (условие только по файлу, без
   `gethash` от `yeah-acp--sessions`) — проверка кончилась кодом 1 и своими
   словами: «the session of this process was not loaded: (:result nil :error
   (:code -32602 :message "unknown ACP session: session-1-…"))».

### 16.52 Гейт волн 65–67 — **вердикт `unknown` по одной причине, и она не в коде**

**Что показал гейт 2026-11-19 (06:31 UTC).**  `./scripts/dev gate` на дереве с
волнами 65–67: 145 claim'ов из 146 держат (`current`), один — нет:
`the-owner-decided-the-order-of-the-next-waves` — `outdated (materials changed)`.
Причина не в коде: claim типа `acceptance` с требованием `kind: review,
spec: owner` закрывает человек, а его область (`docs/PLAN.md`) изменилась —
этими же волнами в §16.49–§16.51 добавлены разделы.  Порядок волн, названный
владельцем, не тронут: строка §18 «wave 41, wave 42, wave 43, wave 44» осталась
как была.

Чтобы закрыть его, владелец записывает своё решение одной командой:

```bash
mathc record the-owner-decided-the-order-of-the-next-waves owner --by WHO --outcome OUTCOME
```

**Повторный прогон.**  После правок документации (этот раздел и ревизия 5
плана интеграции) `mathc run` на том же дереве (19 ноября, 06:36–06:52 UTC)
пересчитал доказательства и дал тот же вердикт: 145 claim'ов из 146 держат,
`uncovered: 0 file(s)`, не держит только claim владельца.  `scripts/dev gate`
на этом дереве кончается кодом 3 (`unknown`) — по той же и единственной
причине.

**Что ещё в карте.**  `uncovered: 0 file(s)` — ни один файл репозитория не
остался без claim'а.  Отрицательные контроли волн 65–67 кусаются утверждением
самих проверок («run-outcome: the wire carried no unfinished…»,
«session-mcp-http: the session with an MCP server over HTTP was not answered with
a session id»), и падения в логе гейта — их голос, а не дефекты.

**Чего гейт не сказал.**  Гейт говорит о коде и доказательствах; он не говорит,
что оркестратор показывает это человеку (§16.49, §7 плана интеграции).

---

### 16.53 Волна 68 — журнал больше не теряет запись, в которой есть список

**Что нашёл живой прогон.**  Живой прогон через оркестратор 19 ноября оставил
в журнале проекта запись-заглушку: `{"type":"input-queued","id":1,
"unserializable":true,…}` — сама запись исчезла, и заглушка сообщала только то,
что журнал не смог её записать.  Заглушек было три, по одной на каждый живой
прогон, в котором сессия называла MCP-серверы.

**Причина — не в оркестраторе.**  Замороженная конфигурация сессии ACP хранит
*имена* своих MCP-серверов (только имена: команда сервера и его окружение могут
содержать секреты, а секрет в журнал не пишется), а имена — это список.
`json-serialize` в Emacs 30 пишет список как объект или отказывается, и запись
о поставленном в очередь вводе — та, что называет `cwd` сессии и её серверы, —
оказалась неписаемой.  Починка в ядре, а не в плагине: дефект принадлежит
журналу любой сессии, и плагин — не единственный автор замороженной
конфигурации.

**Что изменилось.**  Журнал пишет список как массив.  Остальные поля записи
сохраняются, читатель JSON-массива отдаёт вектор — то же правило, которому уже
подчиняются задачи события `todo` (`lib/yeah-todo.el`).  Заглушка остаётся тем,
чем была: значение, которое JSON не может вместить вовсе (символ, cons не из
пар), по-прежнему пишется заглушкой, и журнал берёт следующие записи (claim
`the-journal-never-refuses-a-record`, волна 45).  Claim волны:
`the-journal-writes-a-list-as-an-array`.

**Контроль, который кусается.**  `sed -i 's|((and (consp value) (proper-list-p
value))|((and nil (consp value) (proper-list-p value))|' lib/yeah-session.el` в
копии дерева: проверка кончается кодом 1 и **своими** словами — «journal-list:
the journal wrote a stand-in instead of the record that holds a list» и ещё
шестью своими утверждениями; чистое дерево — код 0.

**Живое доказательство.**  Прогон 19 ноября 2026, 07:40 UTC, через
оркестратор назвал два MCP-сервера, и журнал его сессии
(`session-1-c7dd0e.jsonl`) держит запись о вводе в очереди целиком:
`"frozen":{…,"mcp-servers":["paseo","shared-browser"]}` — без заглушки.  Сессия
прогона, который был до волны (`session-1-530ba2.jsonl`), заглушку всё ещё
держит: журнал не переписывает написанное, и волна этого не меняет.

**Чего волна не делает.**  Она не чистит старые журналы (у журнала нет операции
переписать запись) и не меняет форму alist — он и до волны писался объектом с
буквальными именами пар.  Правило журнала теперь сказано в одном месте:
`yeah-session--json-value` в `lib/yeah-session.el`.

---

### 16.55 Ответ `session/prompt` несёт расход хода — **сделано 2026-11-19 (волна 69)**

**Дефект.**  Оркестратор считал токены прогона opencode и не считал токены прогона
Yeah: он берёт их из поля `usage` ответа на `session/prompt`
(`packages/server/src/server/agent/providers/acp-agent.ts`), а ответ Yeah нёс
`stopReason` и больше ничего.  Обработчик уведомления `usage_update` у оркестратора
пуст (`void update;`), так что через уведомление расход тоже не проходит.  Ядро знало
токены: провайдер сообщает их (`lib/yeah-gptel.el` кладёт их в info ответа как
`:yeah-usage`), ход пишет их в журнал событием `usage`, и журнал сессии их держит, —
но на провод они не выходили.

**Что изменилось.**  Ответ на `session/prompt` несёт `usage` своего хода:
`totalTokens`, `inputTokens`, `outputTokens` — ровно то, что сообщил провайдер
(`yeah-acp--usage-of-turn` в `lib/yeah-acp.el`).  Это расход хода, а не расход
сессии: записи `usage` прогона делят `run_id` этого прогона, а прогон — это один
промпт.  Провайдер, который ничего не сообщил, не получает поля вовсе: у ядра нет
токенизатора провайдера, и оно не оценивает счёт (`yeah-context-usage` держит оценку
контекста — это бюджет ядра, а не счёт провайдера).  Поле — поле ACP (`Usage` в схеме
протокола, помечено самим протоколом как нестабильное), и схема репозитория теперь
называет его (`schemas/acp-v1.json`: свойство `usage` в `PromptResponse` и новое
определение `Usage`).

Починка в ядре, а не в плагине: плагин переводит то, что не ACP (исход прогона,
волна 65), а токены — ACP.

**Проверка.**  `tests/checks/check-the-prompt-response-carries-the-usage-of-the-turn.el`
доказывает на проводе три вещи: ответ несёт токены, которые сообщил провайдер;
второй промпт сессии несёт свои токены, а не сумму двух прогонов (1300, а не 2500);
провайдер, который ничего не сообщил, не даёт поля.  Claim волны:
`the-prompt-response-carries-the-usage-of-the-turn`.  Проверка проходит (exit 0,
около полутора секунд); фейковая модель — `tests/support/yeah-session-usage-model.el`
(обычный режим, `quiet` — без info, `thinking` — сначала reasoning).

**Контроли, которые кусаются.**  Два контроля прогнаны в копиях дерева
(`/tmp/yeah-ctl-69a`, `/tmp/yeah-ctl-69b`), и оба упали exit 1 **своими** словами:
(A) `(when usage (list :usage usage))` → `(when usage nil)` — «the answer to the
prompt carried no usage: the client that counts the tokens of a turn had nothing to
count», «the first prompt of the session…», «the second prompt of the session…»;
(B) убрано условие `(equal (plist-get record :run_id) run-id)` — «the second prompt
of the session: it reported the tokens of the session and not the tokens of its turn:
… 2500 is not 1300».  Чистое дерево после этого — exit 0.

**Живой прогон.**  Запрос уходит в Yeah через Paseo и агент отвечает: прогон
`22094ccb-8ca1-490a-b8a6-c7f02fb1255e` закончился `completed`/`idle` примерно за
11 секунд.  `LastUsage` в оркестраторе **не появился**: SDK-соединение плагина
(`@getpaseo/plugin` 0.15.2, `runAcpProvider`) выбрасывает поле `usage` из ответа
`session/prompt`, и хука на этот ответ у `AcpTransformer` нет.  Правка маршрута
usage лежит вне этого репозитория (подробности — `docs/LIVE-EVIDENCE.md`).

**Чего волна не доказала.**  Ничего о том, что расход дойдёт до интерфейса
оркестратора: маршрут SDK его теряет, и починить его здесь нечем.  Волна не меняет
`usage_update` — это размер контекста, а не стоимость хода, — и не переписывает уже
написанный журнал.

---

### 16.56 Журнал держит расход одного запроса один раз — **сделано 2026-11-19 (волна 70)**

**Дефект, который нашёл живой прогон.**  Журнал сессии живого прогона 19 ноября
(`session-1-606d27.jsonl`) держал две записи `usage` одного и того же запроса с
одинаковыми числами — 13775 входных и 528 выходных, дважды.  Первый запрос того
прогона (модель, которая не думала) держал одну запись.  Причина — на стыке
транспорта и ядра: gptel зовёт callback запроса и с `(cons 'reasoning …)`, и с
финальным ответом, и в оба раза приходит один и тот же `info`, — а ядро писало
расход запроса для каждой формы, которая его несла.  Модель, которая думала, была
заплачена дважды, и стоимость прогона, которую показывает оркестратор, была вдвое
больше стоимости прогона.

**Что изменилось.**  Расход запроса пишется один раз.  Дорога к ответу —
`reasoning` модели, результат инструмента, который отработал, и сентинел конца
потока — это не второй запрос: `yeah-answer-road-p` (`lib/yeah-answer.el`) называет
эти формы, и запись события `usage` в `lib/yeah-turn.el` стоит под guard
`(not (yeah-answer-road-p answer))`.  Решение живёт в том модуле, который уже
владеет решением «что считается ответом» (волна 49), и ход спрашивает его, а не
решает сам.

**Проверка.**  `tests/checks/check-the-journal-holds-the-usage-of-a-request-once.el`
доказывает три вещи: журнал держит одну запись `usage` запроса, запись несёт токены
провайдера, ответ несёт их один раз.  Claim волны:
`the-journal-holds-the-usage-of-a-request-once`.  Проверка проходит (exit 0,
около секунды).

**Контроль, который кусается.**  В копии дерева (`/tmp/yeah-ctl-70a`) guard убран —
проверка упала exit 1 **своими** словами: «the journal holds 2 record(s) of the usage
of one request: the tokens of the request were written twice», «the answer carried the
wrong input tokens: 2400 is not 1200», «the answer carried the wrong output tokens:
68 is not 34».

**Чего волна не делает.**  Она не переписывает журнал проекта: записи, которые были
записаны дважды, остаются там, а журнал — append-only.  Она не трогает `usage_update`
(размер контекста, а не стоимость хода) и не выдумывает токены запроса, который
кончился ошибкой и не принёс ответа: их провайдер не сообщал.

**Честное состояние гейта.**  Последний полный `mathc run` (07:20–07:50 UTC) был
убит таймаутом, поэтому claim'ы волн 68, 69 и 70 ещё не `current`: нужен один
чистый прогон на стабильном дереве (лимит ≥ 3600 s, во время прогона дерево не
править).  `mathc map` даёт вердикт `unknown` (exit 3) с честной единственной
причиной: claim `the-owner-decided-the-order-of-the-next-waves` (kind: review,
spec: owner) закрывает человек, а не агент.  Это решение владельца — агент не
принимает его молча и не обходит.

### 16.57 Оркестратор видит расход хода — **сделано 2026-11-19 (волна 71)**

**Дефект, который нашёл живой прогон.**  Живой прогон 19 ноября через Paseo
(`paseo run --provider yeah`) доказал, что цель интеграции достигнута: запрос
уходит в ядро, агент отвечает, прогон завершается за секунды.  Тот же прогон
показал разрыв, который офлайн-проверки видеть не могли: `paseo inspect` показывал
`LastUsage  InputTokens: 0, OutputTokens: 0`, а у агента opencode счётчик не
пуст.  Причина нашлась в маршруте оркестратора и **не** в ядре: соединение
оркестратора (`@getpaseo/plugin` 0.15.2, `runAcpProvider`) берёт из ответа на
`session/prompt` один `stopReason` и выбрасывает остальное — хука на этот ответ у
`AcpTransformer` нет, — поэтому поле `usage` из ответа волны 69 до счётчика не
доходило.  Второй путь тоже не доходил: перевод `usage_update` → `session.usage` в
SDK оставляет `contextWindowUsedTokens`, `contextWindowMaxTokens` и
`totalCostUsd`, а оркестратор считает `inputTokens`, `outputTokens` и
`cachedInputTokens`.

**Что изменилось.**  Токены хода идут путём, который принадлежит этому
репозиторию.  Ядро шлёт их уведомлением `yeah/usage` — методом Yeah, а не
методом ACP, — тем клиентам, которые попросили их в `_meta` возможностей
(`yeah.usage`), так же, как исход прогона едет по `yeah/outcome` (волна 65).
Плагин оркестратора объявляет этот метод в запросе `initialize` (там же, где он
уже объявлял `yeah.runOutcome`) и переводит уведомление в событие провайдера
`session.usage` — единственное событие, которое оркестратор переносит в счётчик
агента.  Реестр сессий нужен для одной вещи: уведомление ядра приходит без
указания сессии, а сессию называет контекст соединения, и расход должен уехать в
свою сессию, а не в чужую.

Расход собирается из двух частей, и оркестратор обрабатывает их в порядке
своём: обновление контекста ACP идёт через полосу уведомлений, а уведомление
произвольного метода обрабатывается сразу.  Поэтому плагин не отдаёт расход по
частям, а **дополняет** одну часть другой: кто бы ни пришёл последним, в счётчике
стоят и токены хода, и размер окна.  Первый живой прогон после починки это
показал: счётчик стоял в нуле, потому что обновление контекста пришло последним
и затерло токены.

**Проверка.**  `tests/checks/check-the-orchestrator-sees-the-usage-of-the-turn.el`
доказывает три вещи на проводе настоящего сервиса ACP: клиент, объявивший
`yeah.usage`, получает токены хода (1200 входных и 34 выходных — то, что
сообщил провайдер); уведомление называет свою сессию; клиент, не объявивший
ничего, не получает ничего.  Claim волны:
`the-orchestrator-sees-the-usage-of-the-turn`.  Проверка проходит (exit 0, около
секунды).

**Контроли, которые кусаются.**  В копии дерева (`/tmp/yeah-ctl-71a`) вызов
`yeah-acp--send-usage-of-turn` убран — проверка упала exit 1 **своими** словами:
«the wire carried no usage of a turn: the client that counts the tokens of a turn
had nothing to count» и «the usage did not name its session».  Сторона плагина
проверена так же: вызов `registry.report` убран из перевода уведомления — два
теста плагина упали по своим утверждениям («перевод уведомления кладёт расход в
свою сессию» и «расход хода доезжает до оркестратора после открытия сессии»).

**Живое доказательство.**  Агент `e1cdf9b6-9269-4bea-8602-2ddf1564f482` (прогон
«usage wave 71b», 19 ноября 2026): `paseo inspect` показывает
`LastUsage  InputTokens: 12960, OutputTokens: 99, CachedTokens: 0, CostUsd: $0.00`.
Прогон перед ним показывал `InputTokens: 0, OutputTokens: 0`.

**Чего волна не делает.**  Она не чинит маршрут самого оркестратора: ответ на
`session/prompt` и дальше теряет `usage` по дороге к счётчику, и ответ волны 69
остаётся путём для клиента, который говорит с ACP напрямую.  Она не оценивает
стоимость прогона: цену токенов знает провайдер, а ядро прогон не оценивает.  Она
не выдумывает токены провайдера, который ничего не сообщил: уведомление уходит
тогда и только тогда, когда провайдер сообщил их.

---

### 16.58 Плагин говорит с ядром по сокету — **сделано 2026-11-19 (волна 72)**

**Дефект.**  Плагин оркестратора поднимал свой Emacs на каждое соединение:
агент пришёл — Emacs стартовал, агент ушёл — Emacs ушёл.  Просто, но дорого:
бэкенд модели настраивается каждый раз.  И у этого есть жёсткая граница: по
stdio ядро читает следующий запрос только после того, как ход устоялся, —
поэтому запрос, пришедший посреди хода, ждёт конца хода.  Ядро уже говорит ACP
по Unix-сокету (`yeah-acp-serve-socket`), и это тот путь, на котором запрос
посреди хода читается и обрабатывается, пока ход идёт.

**Что изменилось.**  Плагин умеет говорить с живым ядром по этому сокету
вместо подъёма процесса на соединение.  Размещение — настройка плагина
(`serviceMode`), и умолчание прежнее: `spawn`, свой Emacs на соединение, —
так что поведение хоста, который ничего не выбрал, не меняется.  Имя сервиса
(`serviceName`, по умолчанию `paseo`) — это имя его сокета: сервисы с разным
именем не мешают друг другу.

Новые модули плагина не тянут за собой библиотеку оркестратора: словарь ACP
и `yeahInitializeRequest` живут в `shared/vocabulary.ts`, запуск ядра — в
`server/launch.ts` (`YeahLaunch`, `ENV`, `CORE_SETUP`, `LAUNCH_FORM`,
`SERVICE_FORM`, `launchEnv`, `acpCommand`, `serviceCommand`), свой кадр
JSON-RPC по строкам поверх сокета — в `server/ndjson.ts`, сервис — в
`server/service.ts` (`serviceDirectory`, `serviceSocketPath`,
`serviceLifeSocketPath`, `ensureService`, `acpServiceStream`), выбор
размещения — в `server/transport.ts` (`yeahTransport`).  Коннектор в
`index.server.ts` идёт через `yeahTransport`, сервис — один на плагин
(`let service`), и он закрывается, когда плагин уходит.

Путь сокета — тот же, что у ядра: и каталог, и имя файла
(`yeah-service-<имя>.sock`), поэтому сервис, поднятый из Emacs, и сервис,
поднятый из плагина, не выдают друг друга.  Жизнь сервиса привязана к жизни
хозяина: плагин слушает сокет жизни (`yeah-life-<тег>-<pid>.sock`) и закрывает
сервис, когда уходит.

**Проверка.**  `tests/checks/check-the-plugin-talks-to-the-core-over-the-socket.sh`
гоняет код плагина против настоящего ядра: плагин поднимает ядро через
`ensureService` и говорит с ним через `yeahTransport`; ядро отвечает на
рукопожатие, открывает сессию и заканчивает ход; второй агент приходит к
тому же ядру и не поднимает второй; сокет, который вычисляет плагин, — тот
же, что называет ядро (`yeah-service-socket-path`); умолчание размещения —
по-прежнему свой Emacs на соединение.  Модель фейковая: ход кончается
инструментом `finish`, поэтому ни сети, ни ключа не нужно.  Claim волны:
`the-plugin-talks-to-the-core-over-a-socket`.  Проверка проходит (exit 0,
около двух секунд).  Опорные файлы: `tests/support/yeah-service-driver.ts`,
`tests/support/yeah-ts-resolve.mjs`, `tests/support/yeah-ts-hooks.mjs`.
Проверке не нужны ни зависимости плагина, ни сеть: она гоняет TypeScript
плагина через снятие типов самим node и через резолвер проверки, — поэтому
чистая копия дерева без `node_modules` проходит тоже (exit 0).

**Контроль, который кусается.**  В копии дерева вызов
`acpServiceStream(service.socketPath)` заменён на
`acpServiceStream("/nonexistent/yeah-core.sock")` — проверка упала exit 1
**своими** словами: «the plugin did not talk to the core over the socket»,
«the plugin did not report the socket of the core», «the second agent did not
come to the same core».  Чистое дерево после этого — exit 0.

Два дефекта нашлись, пока писалась проверка, и оба починены: закрытие сокета
жизни ждало соединений ядра, а ядро ждало сокет, — deadlock, разорванный
разрывом соединений первым; и драйвер проверки оставлял соединения агентов
открытыми, из-за чего процесс не кончался.

**Чего волна не доказала.**  Она не доказала настоящую команду сервиса
(`SERVICE_FORM`): ей нужны gptel и ключ провайдера, а проверка поднимает ядро
своей командой и фейковой моделью.  Живого прогона через Paseo после этой
волны не было: размещение сервиса — решение владельца
(`docs/PASEO-INTEGRATION-PLAN.md` §5.3), и эксплуатационная модель сервиса не
выбрана.  Волна не делает запрос, пришедший посреди хода, быстрее: ядро это
уже умеет по сокету, а проверка этой волны доказывает, что плагин достаёт до
этого ядра, — не то, что ход направляют (это волна 73).  И у плагина теперь
две реализации провода: процессный путь кадрирует сообщения SDK протокола, а
сокетный — сам (`server/ndjson.ts`); сокетный путь доказан против настоящего
ядра, процессный — тестами плагина, которые были и до волны.

---

### 16.59 Плагин направляет уточнение в идущий ход — **сделано 2026-11-19 (волна 73)**

**Дефект.**  Оркестратор умеет послать агенту сообщение, не заменяя ход: это
steering, и провайдер объявляет его возможностью `prompt.steer`.  Адаптер ACP
библиотеки оркестратора этой возможности не знает: он объявляет четыре, и
`prompt.steer` среди них нет, — а запрос с `delivery: "steer"` до ядра не
доходит вовсе: адаптер обрывает идущий ход и начинает новый.  Это замена хода,
а не steering, и оркестратор отказывает в таком запросе, когда провайдер не
объявил возможность («Provider does not support prompt.steer»).

**Что изменилось.**  Плагин объявляет возможность — в соединении и в сессии,
которую открывает, — и переводит такой запрос в `session/steer` ядра, а ядро
это уже умеет (`lib/yeah-acp.el`, `yeah-acp-session-steer`; ответ — `{inputId}`;
управление steering'ом — `lib/yeah-control.el`, `yeah-control-steer`).  До
адаптера запрос не доходит, поэтому идущий ход не прерывается, а оркестратору
отвечают тем же идентификатором хода, который идёт (`acp:<clientMessageId>`), —
это он и проверяет.

Два факта нужны для перевода, и оба берутся с провода: идентификатор сессии
ядра (оркестратор знает только свой) и идентификатор идущего хода.  Первый
берётся из ответа ядра на `session/new`, а какой сессии оркестратора он
принадлежит — из метки, которую плагин кладёт в параметры открытия сессии
(`yeah.session` в `providerOptions`): адаптер переносит её в `_meta` запроса
`session/new` без изменений.  Второй берётся из событий адаптера: ход,
который начался, — это ход, который идёт.

Новый модуль — `plugin/yeah-provider/server/steer.ts` (`yeahSteerWire`,
`yeahSteerConnection`, `yeahSteerRegistry`, `STEER_CAPABILITY`, `STEER_MARKER`).
Возможность объявляется только тогда, когда оркестратор её предложил:
соединение, которое выбрало непредложенную возможность, оркестратор вовсе не
принимает, — поэтому старый хост сохраняет свой отказ.

**Проверка.**  `tests/checks/check-the-plugin-steers-the-running-turn.sh` с
драйвером `tests/support/yeah-steer-driver.ts` гоняет код плагина против
настоящего ядра.  Ядро настоящее, модель фейковая: ход не кончается, потому
что транспорт не отвечает, — а не кончающийся ход и есть условие steering'а.
Проверка доказывает: ядро получило `session/steer` со своим идентификатором
сессии и с текстом уточнения; ядро НЕ получило `session/cancel`; адаптер не
видел запрос steering'а; соединение и сессия объявили `prompt.steer`; плагин
отчитался тем же идентификатором хода (`acp:m-1`).  Claim волны:
`the-plugin-steers-the-turn-instead-of-replacing-it`.  Проверка проходит
(exit 0, около двух секунд).  Проверке не нужны ни зависимости плагина, ни сеть:
модуль steering'а не несёт зависимости библиотеки оркестратора, — поэтому
чистая копия дерева без `node_modules` проходит тоже (exit 0).  Тесты плагина:
67, из них семь новых.

**Контроль, который кусается.**  В копии дерева `prompt.delivery === "steer"`
заменено на `prompt.delivery === "never"` — проверка упала exit 1 **своими**
словами: «the kernel did not receive the steering», «the steering request
reached the adapter that replaces the turn», «the plugin did not report the
identifier of the running turn».  Чистое дерево после этого — exit 0.

**Живое доказательство.**  Прогон 19 ноября 2026 через настоящего оркестратора
(агент `31f7a281-710b-4ca2-b24c-bec81a77b2c3`, провайдер
`yeah/MiniMax-M3.1-Flash`, режим `plan`, размещение сервисное,
`serviceMode: service`): Emacs слушал `/tmp/yeah-1001/yeah-service-paseo.sock`
через `yeah-acp-serve-socket`, а сессия оркестратора
`671e7f82-ca06-4068-bd1f-bdfa38eb4224` говорила с сессией ядра
`session-19-6b544`.

Хронология: 15:37:38 — ход начался (`input-taken`, `input_kind` «ask»);
15:38:04 — запрос оркестратора с `delivery: steer` перехвачен плагином,
переведён в `session/steer` ядра с его собственным идентификатором сессии и
текстом уточнения, ядро ответило (в журнале плагина нет строки об отказе);
15:38:07 — ядро взяло уточнение в идущий ход: запись `input-taken` с
`input_kind` «steering» и событие «steering» с текстом уточнения; 15:38:10 —
после уточнения модель сразу закончила ход инструментом `finish` и ответила
кратко («Прочитал README.md, первые 300 строк docs/PLAN.md и AGENTS.md;
подсчитал заголовки ### 16.N в docs/PLAN.md поиском по регулярке
^### 16\.[0-9]+: их 58 … Три последних: 16.57 …»).  Ход не был прерван и не
заменён: идентификатор хода остался
`acp:eb285023-4851-487b-9692-b47619fa6076`.

Где смотреть: журнал ядра
`~/.local/share/yeah/yeah/projects/<hash>/sessions/session-19-6b544.jsonl` —
записи `input-queued` (`input_kind` «steering»), `input-taken`
(`input_kind` «steering») и `steering` (payload = уточнение).  Разбор прогона и
то, чего он не доказал, — `docs/LIVE-EVIDENCE.md`, «The live run of the steering
through the orchestrator».

**Чего волна не доказала.**  Она не меняет адаптер библиотеки оркестратора:
он по-прежнему заменяет ход, когда ему дают steering-запрос, — плагин
объявляет возможность и переводит запрос сам.  Живое доказательство через
настоящего оркестратора теперь есть: прогон 19 ноября 2026 в сервисном
размещении (ниже и в `docs/LIVE-EVIDENCE.md`).  Она не доказывает, что
уточнение доходит до модели посреди хода: ядро отвечает на `session/steer`
идентификатором поставленного ввода, и модель берёт его после текущей партии
инструментов, — это собственное правило ядра для steering'а.  По stdio
steering не своевременен: над трубой ядро читает следующий запрос только
после того, как ход устоялся, поэтому уточнение читается поздно и становится
обычным вопросом; сервисное размещение волны 72 — то, что делает запрос
посреди хода прочитанным, пока ход идёт, и проверка этой волны идёт именно в
этом размещении.  Steering не работает для агента, который не Yeah:
`session/steer` — собственный метод ядра, расширение ACP, и провайдер другого
рода отвечает на него по-своему.  Способ, которым плагин узнаёт сессию ядра,
зависит от адаптера библиотеки: он перекладывает параметры провайдера в
`_meta` запроса `session/new` без изменений, и метка едет вместе с ними; когда
этот перенос исчезнет, steering откажется себе словами «the core does not know
this session» — отказ честный, и неверную сессию он не направит.  Решение
владельца не тронуто: предлагать ли `prompt.steer` плагину — дело
оркестратора, а плагин отвечает на то, что ему предложили.

---

### 16.60 Мёртвый сокет не проходит за живой сервис — **сделано 2026-11-19 (волна 74)**

**Дефект.**  Сервисное размещение (волна 72) держит один Emacs на всех агентов
оркестратора, и сессии приходят к нему по Unix-сокету.  Плагин решал, что сервис
жив, по наличию ФАЙЛА сокета, — а файл переживает процесс.  19 ноября 2026 в
15:34:15 ядро убил OOM-killer хоста (SIGKILL), сокет остался на диске, и следующий
агент пришёл к сокету без ядра за ним: оркестратор отвечал «ACP connection
closed», и плагин пришлось перезагружать вручную.  Дефект нашёл живой прогон
пакета, а не проверка: ни одна офлайн-проверка его не видела.

**Что изменилось.**  Живость сервиса спрашивается у самого сокета: новая функция
`serviceListens(socketPath, timeoutMs)` в `plugin/yeah-provider/server/service.ts`
соединяется с сокетом (кто-то слушает — сервис жив) и сразу рвёт соединение.  В
`ensureService` сокет, который никто не слушает, снимается, и сервис поднимается
заново, — иначе следующий агент не придёт ни к какому ядру.

**Проверка.**  `tests/checks/check-the-plugin-does-not-trust-a-dead-socket.sh` с
драйвером `tests/support/yeah-dead-socket-driver.ts` гоняет код плагина против
настоящего ядра: плагин поднимает ядро через `ensureService` и говорит с ним,
ядро убивают на живом месте (SIGKILL, файл сокета остаётся), и требуется, чтобы
плагин не поверил мёртвому сокету: сервис поднят заново, и следующий агент
получает ответ от нового ядра.  Модель поддельная: ход кончается инструментом
`finish`, поэтому ни сети, ни ключа не нужно.  Claim волны:
`a-dead-socket-does-not-pass-for-a-live-service`.  Проверка проходит (exit 0,
около секунды).  Тесты плагина: 68, из них один новый; прежний тест «живой сервис
не поднимается второй раз» кодировал дефект (файл сокета вместо слушателя) и
теперь слушает по-настоящему.

**Контроль, который кусается.**  В копии дерева
`if (await serviceListens(socketPath))` заменено на `if (true)` — проверка упала
exit 1 **своими** словами: «the plugin trusted a dead socket», «the plugin
believed the socket of a dead service», «the next agent did not get an answer
from the new core».  Чистое дерево после этого — exit 0.

**Чего волна не доказала.**  Сервис не переживает смерть ядра: волна делает так,
что плагин замечает смерть и поднимает сервис заново, а агент, который говорил с
умершим ядром, теряется вместе с ним.  Причина смерти не устранена: ядро убил
OOM-killer после того, как контекст прогона вырос за окно модели (103385 токенов
при окне 60000), — это отдельный вопрос.  Проба стоит одного соединения, которое
сразу рвётся, и доказывает только, что кто-то слушает.  Умолчание размещения
прежнее — `spawn`, свой Emacs на соединение.

### 16.61 Два зарегистрированных контроля, которые никогда не кусались — **сделано 2026-11-19**

**Дефект.**  Пересчёт пакета волн 65–74 закончился вердиктом `unknown`: карта
метода не смогла вычислить вердикт, потому что два claim'а остались
`inconclusive`.  Ни один из них не был кодом пакета — оба claim'а стояли в
реестре с контролем, который не мог кусаться вовсе.

* `the-prompt-response-carries-the-usage-of-the-turn` (волна 69): контроль был
  записан как
  `sed -i 's|(when usage (list :usage usage))))))))))|(when usage nil)))))))))' lib/yeah-acp.el`.
  В выражении `s` не хватало **третьего** `|` — закрывающего разделителя
  команды: разделители стояли после `s` и между шаблоном и заменой, а
  завершающего не было.  `sed` отвечал
  `sed: -e expression #1, char 67: unterminated 's' command`, файл не менялся
  совсем, в доказательстве `control_reach` = `nothing`, и claim не был
  установлен.
* `a-tool-that-returns-bytes-does-not-kill-the-harness` (волна 45): контроль
  убирал `(json-serialize (yeah-text-value-valid copy))`, но в коде вызов давно
  обёрнут в `yeah-session--json-value`:
  `(json-serialize (yeah-session--json-value (yeah-text-value-valid copy)))`.
  Вторая часть `sed` не попадала в текст, первая (удаление строки
  `(setq content (yeah-text-valid content))`) попадала, поэтому subject менялся
  (`control_reach` = `subject`), но проверка проходила: второе чтение байтов
  оставалось на месте, и контроль не кусался.

**Починка.**  Оба контроля переписаны так, чтобы они означали то же, что
значили вручную (заметки волн 45 и 69), и чтобы они исполнялись:

* usage: `sed -i 's|(when usage (list :usage usage))))))))))|(when usage nil)))))))))|' lib/yeah-acp.el`
  — добавлен закрывающий `|`.  Скобки сбалансированы: в оригинале две
  открывающие и десять закрывающих, в замене одна и девять, так что файл
  компилируется и после контроля.
* bytes: `sed -i -e '/yeah-text-valid content/d' -e 's|(yeah-text-value-valid copy)|copy|' lib/yeah-result.el lib/yeah-session.el`
  — убираются **оба** чтения: и результат инструмента, и запись журнала.

**Доказательство, что контроли кусаются.**  Оба контроля прогнаны на копии
дерева, и оба упали кодом 1 **своими** словами: usage — «the answer to the
prompt carried no usage: the client that counts the tokens of a turn had
nothing to count», «the first prompt of the session: the usage carried the
wrong input tokens: nil is not 1200», «the second prompt of the session: … nil
is not 1300»; bytes — «the broken byte did not become the replacement
character», «the journal holds no record of the tool».  Чистое дерево после
этого — код 0 у обеих проверок.  Пересчёт 19 ноября 2026 (16:23–16:37 UTC):
оба claim'а получили `pass` и `negative control proven`, в карте оба стоят
`holds (current)`, `inconclusive` в карте больше нет ни одного.

**Следствие для метода.**  Claim, чей контроль кусается не всегда, не
установлен (§18.1).  Значит, до 19 ноября 2026 оба claim'а стояли в карте как
неустановленные, хотя их код и их проверки были верны: виновата была
регистрация, а не починка.  Починка механическая, и она делает метод строже,
а не мягче: два claim'а вышли из `inconclusive` только потому, что их
контроли теперь действительно ломают предмет.

**Чего починка не делает.**  Она не пересчитывает историю: доказательства до
19 ноября 2026 остаются в `.math/v5/evidence.jsonl` как есть.  Она не чинит
код: код обоих claim'ов не менялся — менялась только регистрация контроля.
Она не отменяет открытых вопросов волн 45 и 69 (смерть ядра от OOM, профиль
без человека).

### 16.62 Claim, опровергнутый один раз под нагрузкой хоста — **открыто 2026-11-19**

**Что случилось.**  Тот же пересчёт 19 ноября 2026 (16:23–16:37 UTC) опроверг
claim `the-pilot-that-runs-out-of-time-leaves-no-server-behind` (волна 52,
`scripts/live-pilot`): проверка упала кодом 1 со своим словом «limit: the
server of the pilot stayed behind after the limit passed (pid 7457)».  Вердикт
карты стал `red`, и карта назвала следующее действие: «the claim
the-pilot-that-runs-out-of-time-leaves-no-server-behind is refuted».

**Что известно.**  Claim проходил 11 раз из 11 до этого прогона (доказательства
в `.math/v5/evidence.jsonl`, с 02:42 до 16:14 UTC 19 ноября).  Проверка ждёт
смерти сервера пилота **пятнадцать секунд** — это срок в стенном времени, а не
свойство процесса.  Во время прогона проверка заняла 28,4 секунды против 13,4
секунды обычно, и хост в этот момент упирался в память: подкачка держала 4,7
GiB, zram был заполнен на 3,4 из 3,9 GiB (приоритет 100).  Вне прогона
проверка проходит: два прогона подряд (13,4 с) и два прогона под нагрузкой
из четырёх занятых ядер (13,8 с) — все кодом 0.

**Чего это не доказывает.**  Ни «свойство держится», ни «свойство нарушено»:
причина не установлена.  Это может быть и отказ пути завершения сервера под
нагрузкой, и слишком жёсткий срок ожидания на перегруженном хосте.  Метод не
различает эти два случая: он записал `refuted`.

**Что предлагается.**  Отдельная волна, чтобы проверка не зависела от скорости
хоста: либо срок ожидания измеряется в состояниях процесса (`/proc`), а не в
секундах, либо ожидание продлевается до фактического завершения с явным
пределом.  Порядок волн — решение владельца (§18, §19.1), поэтому волна не
заведена: заведен открытый пункт.  До неё карта метода стоит в `red` по
внепакетному claim'у, и это состояние честно записано, а не спрятано.

**Порядок взят владельцем 2026-11-19** («ок, делай и коммить»): волна 75,
§16.63.  Пункт остаётся в списке открытых не потому, что владелец молчал, а
потому, что решение пришло позже.

### 16.63 Проверка пилота меряет процесс, а не часы — **сделано 2026-11-19 (волна 75)**

**Что было не так.**  Проверка `the-pilot-that-runs-out-of-time-leaves-no-server-behind`
ждала, пока сервер пилота **исчезнет из `/proc`**, пятнадцатью секундами
стенного времени.  Под нагрузкой хоста этого не хватало, и проверка объявила
claim опровергнутым (§16.62).

**Что показало измерение.**  Сервер пилота умирает **сразу**, когда проходит
предел: состояние его процесса в `/proc/<pid>/stat` меняется с `S` на `Z`, и
запись уходит из `/proc` в пределах десятой доли секунды.  Задерживается не
сервер, а его труп: зомби ждёт, пока его переберёт init хоста.  Init хоста —
не предмет этого claim'а.  Проверка же считала «жив» любой, у кого есть
запись в `/proc`, — то есть считала труп живым и ждала перебора, которого не
ждает ни один другой claim этого репозитория.

**Починка.**  Проверка читает **состояние** процесса и считает зомби мёртвым:
зомби не жжёт CPU, никому не отвечает и не держит клиента.  Пятнадцать секунд
остались границей ожидания, но перестали быть мерой смерти.  Формулировки
claim'а пошли за мерой: текст — «сервер пилота мёртв в пределах пятнадцати
секунд после предела», опровергатель — «сервер пилота всё ещё работает через
пятнадцать секунд после предела».  Изменение меры — это изменение claim'а, и
оно записано здесь и в `waves/wave-75.json`.

**Доказательство.**  Проверка проходит на чистом дереве (13,3 с) и под четырьмя
занятыми ядрами (13,7 с) — кодом 0.  Контроль claim'а применён к копии
дерева и **кусается**: раннеру велено не останавливать дерево пилота, и
проверка кончилась кодом 1 **своими** словами — «the server of the pilot was
still alive fifteen seconds after the limit passed (pid 6531, state "S")»,
«the runner of the pilot did not stop when the limit passed», «the runner of
the pilot answered 0 when the limit passed, the third answer is 3».

**Чего волна не делает.**  Она не заставляет сервер пилота быстрее уходить из
`/proc`: труп перебирает init хоста, и на хосте с подкачкой перебор занимает
минуту.  Claim и не про это: он про сервер, который **остаётся живым** и держит
сокет в ожидании клиента, который не придёт, — а это и есть состояние
процесса.  Проверка, которая требовала бы, чтобы труп убрали, измеряла бы
свойство init'а хоста, а не своего предмета.  Хост, который опроверг claim
(подкачка, zram заполнен на 3,4 из 3,9 GiB), не был воспроизведён: волна не
утверждает, что опровержение исчезло, — она утверждает, что мера больше не
зависит от скорости хоста.

### 16.64 Гейт после волны 75 — **вердикт `unknown` по одной причине, и она не в коде**

**Что прогонялось.**  Гейт 19 ноября 2026 (18:29–18:44 UTC), `./scripts/gate
--limit 3000`: прогон метода целиком и карта после него.  Предел поднят с
1800 до 3000 секунд потому, что прогон волн 65–67 19 ноября был убит этим
пределом (SIGTERM на 1800-й секунде, `RUN_EXIT=143`), и карта после него
показала четыре claim'а, которые не связаны: один `never-checked`, два
`outdated` и один `inconclusive`.  Гейт ждёт прогона, а не смотрит в его
лог: этот прогон читается один раз, после того как он закончился.

**Что вышло.**  152 claim'а из 153 — `holds (current)`, `inconclusive` нет ни
одного, `refuted` нет ни одного, `uncovered: 0 file(s)`.  Claim
`the-pilot-that-runs-out-of-time-leaves-no-server-behind`, который пересчёт
16:23–16:37 опроверг, после волны 75 стоит `holds (current)`.  Claim'ы пакета
65–74 — все `holds (current)`.

**Что осталось не-current.**  Один claim:
`the-owner-decided-the-order-of-the-next-waves` — `outdated (materials
changed)`.  Это claim о **решении человека**: его областью является
`docs/PLAN.md`, а этот документ менялся волнами 65–75, и поэтому его
доказательство устарело.  Проверка его не может заменить: требование claim'а —
`kind: review, spec: owner`, и метод не вправе записать решение владельца за
него.  Карта называет следующее действие само:

```
mathc record the-owner-decided-the-order-of-the-next-waves owner --by WHO --outcome OUTCOME
```

**Почему вердикт `unknown`, а не `green`.**  Метод не различает «всё доказано»
и «всё доказано, кроме одного пункта, который решает человек»: он различает
только `pass` и не-`pass`.  Claim, который ждёт человека, честно делает вердикт
не-`green`, и это не дефект карты, а её предмет.  Порог паритета, классификация
прогона, который провайдер замолчал, и бюджет надзора дочернего агента (§17.2,
§18.5) остаются за владельцем, и они записаны там, а не здесь.

**Чего этот параграф не делает.**  Он меняет материалы claim'а о документации
(`the-documentation-points-at-files-that-exist`, область — весь каталог
`docs/`), и после этой правки его доказательство устареет точно так же, как
устарело доказательство claim'а владельца.  Следующий прогон пересчитает его;
этот абзац — обычная правка документации, а не новый предмет метода.

**Что сделал владелец.**  19 ноября 2026 владелец записал своё решение о
порядке волн:

```
mathc record the-owner-decided-the-order-of-the-next-waves owner --by az --outcome pass
```

Запись легла в трейл доказательств, и карта после неё стала `green`:
**153 claim'а из 153 — `holds (current)`**, `inconclusive` нет, `refuted` нет,
`uncovered: 0`, код выхода карты 0, и следующее действие карты называет
само: «nothing to do — declared evidence is current and the tree is covered».

**Что это означает для метода.**  Claim о решении владельца — единственный в
репозитории, у которого требование не проверка, а **человеческий суд**
(`kind: review, spec: owner`): его область — `docs/PLAN.md`, а этот документ
меняется каждым волновым абзацем, поэтому любая правка документации делает
доказательство устаревшим, и метод не может закрыть это сам.  Отсюда порядок,
который стоит знать: **запись владельца идёт последней** — после всех правок
документации, иначе она устареет снова.  Запись от 19 ноября 2026 сделана
после правок этого абзаца.

**Чего зелёная карта не говорит.**  Она говорит, что все 153 утверждения
репозитория доказаны тем, чем они доказаны: 152 — проверками с кусающимися
контролями, одно — решением человека.  Она не говорит, что продукт готов:
живые прогоны оркестратора Paseo были 15:26–15:38, а ограничения волны 52
(журнал, который может стереть сам прогон) и §17.1 остаются открытыми.

### 16.65 Режим без человека и корзина вместо удаления — **сделано 2026-11-19 (волна 76)**

**Решение владельца.**  Два решения, оба от 19 ноября 2026:

1. «В Paseo мне постоянно приходится соглашаться на выполнение команд Bash —
   нужен режим, в котором я могу выбрать "всегда разрешать"».
2. «Удаление с подкаталогами запрещено и заменяется специальным скриптом,
   который всегда перемещает в некую корзину».

Второе решение — половина первого: режим, в котором всё разрешено, безопасен
лишь настолько, насколько безопасны инструменты.  Поэтому они сделаны
вместе, и поэтому рядом стоит третий вопрос: что ещё нужно для безопасности
агента (разбор — `docs/AGENT-SAFETY.md`).

**Что изменилось в ядре.**

* Профиль `auto` (`lib/yeah-perm.el`): правило «\*» на действие и на ресурс
  означает «всё».  Список профилей — `("plan" "build" "auto")`, и он же
  список режимов, которые ядро публикует по проводу.
* Эффект `allow` профиля теперь уважают оба пути, которые решают: провод
  ACP (`yeah-acp--session-answerer`) и прикреплённый путь
  (`yeah-approval-profile-decision`).  До этого `allow` был мёртвым: профиль
  умел только запрещать или спрашивать, а режим без человека не знал, что
  спросить некому.
* Корзина агента (`lib/yeah-trash.el`): XDG-корзина пользователя, свой
  формат — `.trashinfo`; путь переносится и возвращается; инструмент
  `delete` агента.
* Страж оболочки (`lib/yeah-shell-guard.el`): `rm` в оболочке агента — это
  скрипт, который перемещает в корзину (ловит `rm -rf`, `rm -fr`,
  `find -exec rm`, `xargs rm`), а команды, разрушающие на месте, отвергаются
  поимённо: `sudo`, `/bin/rm`, `find -delete`, `shred`, `unlink`, `truncate`,
  `dd of=/dev/…`, `mkfs`, `fdisk`, `parted`, `git clean`, вилка-бомба.
* `git_commit` и `delete` добавлены в список мутирующих инструментов: в
  профиле `plan` коммит и удаление теперь запрещены, а не просто
  спрашиваются.

**Доказательство.**  Две проверки, обе с кусающимися контролями:

* `check-a-session-may-work-without-a-person.el`: настоящий сервис ACP на
  сокете, режим `auto`, фиктивная модель зовёт `bash` — клиента **не
  спрашивают**, команда выполняется.  Контроль (`((eq (yeah-acp--mode-effect
  mode request) 'allow)` → `(nil`) заставляет проверку упасть своими словами:
  «the client was asked about a permission in the auto mode».
* `check-a-delete-goes-to-the-trash.el`: `rm -rf` агента уводит дерево в
  корзину (с содержимым), дерево возвращается, `delete` работает так же, а
  `/bin/rm`, `find -delete` и `shred` отвергаются.  Контроль (убрать шимы из
  PATH) заставляет проверку упасть своими словами: «the tree is not in the
  trash after the rm of the agent».

**Живой прогон в оркестраторе** (19 ноября 2026, 00:14): `paseo run
--provider yeah --mode auto` — каталог режимов провайдера показывает
`Plan, Build, Auto`, а журнал сессии содержит `session-mode: auto` и решение
`the auto mode allows mcp--paseo--list_hosts without a question`.
Оркестратор спросил у человека про **ноль** команд.

**Чего волна не делает.**  Она не делает агента безопасным: страж оболочки —
список форм, а не песочница; границы рабочего каталога нет; секреты в
журнале не маскируются; делегация в режиме `auto` разрешена.  Полный разбор
и порядок предложенных волн — `docs/AGENT-SAFETY.md`, §2 и §4.  Правки
`docs/ARCHITECTURE.md` §8 и D9 называют эти долги, а не прячут их.

**Гейт волны 76** (20 ноября 2026, 00:34–00:49 UTC): 154 claim'а из 155 —
`holds (current)`, оба новых — с `negative control proven`, `inconclusive`
нет, `refuted` нет, `uncovered: 0`.  Единственный не-current — тот же
claim о решении владельца: его область `docs/PLAN.md`, а документ менялся
этим абзацем, и решение человека закрывает его (команда — в §16.64).

### 16.66 Прогон ждёт в состоянии, таблица и рантайм говорят одно — **сделано 2026-11-20 (волна 77)**

**Решение владельца.**  20 ноября 2026 — вариант **A1**: состояния ожидания
входят в машину состояний, а не уходят из неё (A0 в
`docs/ARCHITECTURE-CATCHUP-PLAN.md`, §A).  Обоснование: `docs/PLAN.md` уже
знает про пробел «a child that was running when the Emacs died is not brought
back to life — the work of that child is lost»; состояние ожидания — то, что
отличает «прогон ждёт человека» от «прогон завис».

**Что изменилось в ядре.**

* Таблица машины (`lib/yeah-loop.el`) переписана по реальным путям рантайма:
  20 ячеек → 31.  Мёртвые ячейки убраны (`tick-resume`, `ask-user`), а живые
  перенесены на настоящий путь: `permission-ask` ведёт из `awaiting-tool` в
  `awaiting-user-permission`, `answer` и `timeout` возвращают прогон в
  `awaiting-tool`.
* Добавлены ячейки ожидания: `nudge` (`post-decide → deciding`),
  `rate-blocked` (`deciding → blocked-on-rate`), `rate-relief`
  (`blocked-on-rate → deciding`).
* Терминальные события — веер: `error` и `interrupt` выходят из всех восьми
  нетерминальных состояний.  Правило «:any» не вводилось: таблица остаётся
  единым контрактом без второго языка, и генератор схем (волна D1) читает её
  без особых случаев.
* Рантайм ходит по таблице, а не мимо неё (`lib/yeah-turn.el`): состояние
  меняется только через `yeah-turn--tick`, а `yeah-turn--set-state` пишет
  состояние в историю прогона.  Умерший параметр `terminal-state` у
  `yeah-turn--mark-done` убран: состояние приходит из таблицы и ниоткуда.
* Нужд больше не врёт: раньше прогон тикал `no-tool-calls` (→ `completed`) и
  прямым `setf` переводил себя в `deciding`, то есть в истории прогона было
  ложное `completed`.  Теперь тик `nudge` ведёт `post-decide → deciding`, и
  ложного `completed` в истории нет.
* Отказ по таймауту несёт флаг `:timeout t` (`lib/yeah-approval.el`), и
  рантайм различает «человек ответил» и «человек не ответил».

**Что удалено.**  Состояние `awaiting-user-input` убрано из машины: 12
состояний → 11.  Ни одно событие рантайма не вводило его — правообладатель
ядра не имеет механизма «модель спрашивает человека».  Состояние вернётся
вместе с этим механизмом, а не останется пустым именем в списке.

**Доказательство.**  Проверка `tests/checks/check-a-run-waits-in-a-state.el`:
прогон, чей вопрос ждёт человека, стоит в `awaiting-user-permission` и
выходит из него по ответу; прогон, чей провайдер был занят, проходит через
`blocked-on-rate` и идёт дальше; и каждое движение рантайма — ячейка таблицы.
Два кусающихся контроля на копии дерева: убрать тик `permission-ask` —
проверка падает своими словами («the run that waits for the person is in
awaiting-tool, not in the state of a run that waits»); убрать тик
`rate-blocked` — тоже своими словами.  Юнит-тесты машины: 32; весь
юнит-набор: 458; 97 проверок репозитория проходят.

**Отклонения от утверждённого плана.**  Два, и ни одно не меняет поведение
прогона:

1. `awaiting-user-input` удалено, а не введено в машину (см. «Что удалено»).
2. `timeout` ведёт в `awaiting-tool`, а не в `failed`.  Код отказывает в
   инструменте по таймауту и продолжает прогон; менять эту семантику в волне о
   состояниях — значит менять поведение прогона, а не таблицу.  План
   `docs/ARCHITECTURE-CATCHUP-PLAN.md` §A приведён под эти два отклонения.

**Чего волна не делает.**  Состояние прогона не пишется в журнал: прогон,
который ждал человека, когда Emacs умер, всё ещё теряется.  Обратная сторона
таблицы не закрыта: ячейка, которую рантайм не берёт, всё ещё возможна — это
волна A3.  Интерфейс не показывает состояние ожидания: `lib/yeah-faces.el` его
знает, а место, которое показывает его человеку, — отдельная волна.

### 16.67 Два зарегистрированных контроля, которые не кусались — **сделано 2026-11-20**

**Дефект.**  Гейт волны 77 закончился вердиктом `unknown`: 154 claim'а из 156
получили `pass`, а два остались `inconclusive`.  Ни один из них не был кодом
волны — оба стояли в реестре с контролем, который не мог кусаться.

* `a-run-that-did-not-finish-is-not-a-success` (волна 39): `control_reach` =
  `nothing`.  Контроль искал вызов `(yeah-turn--mark-done turn 'failed)`, а
  волна 77 убрала его: у `yeah-turn--mark-done` больше нет параметра
  `terminal-state`, состояние приходит из таблицы машины.  `sed` не нашёл
  текста, файл не изменился вовсе, и контроль ничего не сломал.
* `a-delete-goes-to-the-trash` (волна 76): `control_reach` = `subject`.
  Контроль менял предмет, а проверка проходила всё равно.

**Починка.**  Оба контроля переписаны так, чтобы они означали то же, что
значили вручную, и чтобы они исполнялись:

* «прогон без эффекта»:
  `sed -i "s|(yeah-turn--tick turn 'error)$|(yeah-turn--tick turn 'no-tool-calls)|" lib/yeah-turn.el`
  — якорь `$` выбирает строку 1057 (ветка «бюджет нудов исчерпан»), а не строку
  326: там после `error` идут три закрывающие скобки.
* «удаление в корзину»:
  `sed -i 's|gio trash --|false gio trash --|' lib/yeah-shell-guard.el`
  — команда, которой guard отдаёт удаление, перестаёт работать.

**Доказательство, что контроли кусаются.**  Оба прогнаны на копии дерева, и
оба упали кодом 1 **своими** словами: «the run ended in completed, not failed:
the run looks done», «the wire answered "end_turn", not refusal: the run looks
done» — и «the tree is not in the trash after the rm of the agent», «the tree
is still in its place after the rm of the agent», «the trash does not name the
tree that was thrown away», «the tree in the trash lost what was in it».  Чистое
дерево после этого — код 0 у обеих проверок.  Гейт 20 ноября 2026 после
починки подтвердил оба: «negative control proven».

**Находка об окружении, а не о коде.**  Старый контроль claim'а о корзине
снимал экспорт PATH, который guard Yeah делает для своих команд, — и ожидал,
что `rm` станет обычным `rm`.  На этой машине в PATH лежит шим
`/home/az/.minimax/shims/rm` (MiniMax Code; шим сам складывает файлы в
XDG-корзину).  Шим перехватывает `rm` раньше, чем доходит дело до guard'а
Yeah, поэтому снятие экспорта ничего не меняло: контроль менял предмет, но
предмет менялся не тем способом, который имел в виду.  Код
`lib/yeah-shell-guard.el` и `lib/yeah-trash.el` волной 77 не менялся, и
починка их не трогает.  Новый контроль бьёт по тому месту, где правда:
команда, которой guard отдаёт удаление, не работает.

**Открытая находка (не в объёме волны).**  Внутренний контроль claim'а
`the-bridge-check-decides-the-race-by-construction` (волна 41) не кусается
устойчиво: прогон race-проверки даёт «the run N of the control ended with the
code 0: the control did not bite by an assertion» — bridge-проверка после
контроля проходит, а не падает.  Сам claim в карте стоит `holds (current)`,
и гейт даёт ему `pass`: claim оценивается по **своему** контролю
(`sed -i 's/(defvar yeah-check--hold-the-answer t/(defvar yeah-check--hold-the-answer nil/'`),
а он меняет проверку детерминизма, а не проверку моста.  Находка записана и
не закрыта: она про другой claim и про другой предмет, и закрывать её волной
77 — значит чинить чужую волну.

**Чего починка не делает.**  Она не пересчитывает историю: доказательства до
20 ноября 2026 остаются в `.math/v5/evidence.jsonl` как есть.  Она не чинит
код: код обоих claim'ов не менялся — менялась только регистрация контролей.
Она не закрывает находку о внутреннем контроле claim'а о детерминизме моста.

### 16.68 Гейт после волны 77 — **вердикт `unknown` по одной причине, и она не в коде**

**Что прогонялось.**  Гейт 20 ноября 2026: `./scripts/dev run` — то есть
`mathc --root . run`, полный пересчёт метода.  Для каждого claim'а метод
исполняет его проверку, его отрицательный контроль и ту же проверку после
контроля; 156 claim'ов, 50 минут (журнал доказательств: 09:13–10:04 UTC).

**Что вышло.**  156 claim'ов из 156 — 155 `holds (current)` и один `outdated
(materials changed)`: claim о решении владельца.  `inconclusive` нет ни одного,
`refuted` нет ни одного, `uncovered: 0 file(s)`.  Оба починенных контроля
(см. §16.67) гейт подтвердил: «negative control proven» — починка доказана на
волне, а не только на копии дерева.

**Почему вердикт `unknown`, а не `green`.**  Тот же предмет, что и в §16.64:
claim, который ждёт человека, честно делает вердикт не-`green`.  Метод
различает `pass` и не-`pass` и не различает «всё доказано» и «всё доказано,
кроме одного пункта, который решает человек».

**Что сделал владелец.**  20 ноября 2026 владелец назвал третий порядок волн —
догоняющий план: A0 (решение о состояниях ожидания), затем A1 или A2, затем
A3, затем D, затем E (`docs/ARCHITECTURE-CATCHUP-PLAN.md`, §1 и §4).  Волна 77
— первая часть этого плана (A1).  Текст claim'а о решении владельца расширен
третьим решением, а область claim'а — теперь оба документа, где решения
записаны: `docs/PLAN.md` и `docs/ARCHITECTURE-CATCHUP-PLAN.md`.

**Запись решения.**  Запись идёт последней — после всех правок документации,
иначе она устареет снова (урок §16.64):

```
mathc record the-owner-decided-the-order-of-the-next-waves owner --by az --outcome pass
```

**Что это означает для метода.**  Claim о решении владельца — единственный в
репозитории, у которого требование не проверка, а **человеческий суд**
(`kind: review, spec: owner`).  Область claim'а — два документа, один из
которых меняет каждая волна, поэтому любая правка документации делает
доказательство устаревшим, и метод не может закрыть это сам.  Отсюда порядок,
который стоит знать: правка документации → пересчёт → запись владельца →
карта.

**Чего зелёная карта не говорит.**  Она говорит, что все 156 утверждений
репозитория доказаны тем, чем они доказаны: 155 — проверками с кусающимися
контролями, одно — решением человека.  Она не говорит, что продукт готов:
состояние прогона не пишется в журнал (§16.66), обратная сторона таблицы не
закрыта (волна A3), а интерфейс не показывает состояние ожидания.

**Чего этот параграф не делает.**  Он не закрывает находку о внутреннем
контроле claim'а о детерминизме моста (§16.67) и не чинит шим `rm` в PATH
хоста (там же).  Он не вводит состояние прогона в журнал — это отдельная
волна.  И он не объявляет гейт зелёным: зелёной карту делает запись
владельца, а она впереди.

### 16.69 Проверка «каждая ячейка таблицы проходима» — **сделано 2026-11-20 (волна 78)**

**Решение владельца.**  20 ноября 2026 — порядок волн догоняющего плана: A0,
затем A1 или A2, затем A3, затем D, затем E.  A1 сделан волной 77 (§16.66),
следующей по этому порядку идёт A3.

**Что изменилось.**  Код ядра не менялся: таблица машины после волны 77 уже
честна — у каждой её метки есть место в рантайме, где прогон берёт этот ход.
Волна 78 добавляет проверку, которая говорит об этом вслух и следит за этим.

* `tests/checks/check-every-transition-of-the-table-is-taken.el` читает
  источники ядра ридером Emacs, находит вызовы `yeah-turn--tick` и метку
  каждого из них, и утверждает, что у каждой метки таблицы есть такое место.
* Вторая часть проверки обходит таблицу от первого состояния и утверждает,
  что каждое состояние машины достижимо через ячейки таблицы.
* Проверка статическая намеренно: она отвечает про всё ядро сразу и отвечает
  одинаково дважды.  Динамическая проверка потребовала бы прогона, который
  берёт каждый ход таблицы, а такого прогона не бывает: прогон, не
  встретивший занятого провайдера, никогда не берёт `rate-blocked`, а прогон,
  который не вырос, никогда не берёт `budget-overflow`.

**Claim:** `every-transition-of-the-table-is-taken`.

**Доказательство.**  Контроль (убрать вызов `yeah-turn--tick` для `tool-end`)
на копии дерева: проверка падает кодом 1 **своими** словами — «the table of
the machine names 1 move(s) that the runtime does not take: (tool-end)».
Чистое дерево — код 0.  Измерение волны: у таблицы семнадцать меток и
одиннадцать состояний, каждая метка взята в `lib/`, каждое состояние
достижимо от первого.

**Чего волна не делает.**

1. Она не говорит, что прогон берёт каждый ход таблицы: такого прогона не
   бывает, и проверка об этом не врёт — она говорит, что у каждого хода
   есть место в рантайме.
2. Состояние прогона по-прежнему не пишется в журнал (§16.66): прогон,
   ждавший человека при падении Emacs, всё ещё теряется.
3. Обратная сторона таблицы: проверка говорит, что каждое состояние
   достижимо через ячейки, а не что рантайм приходит в него на каждом пути.
4. Код ядра не тронут: волна 78 не меняла ни одной строки в `lib/`.

---

### 16.70 Вид инструмента: неизвестный вид отвергается, а не подменяется — **сделано 2026-11-20 (волна 79)**

**Решение владельца.**  Порядок волн догоняющего плана (§16.69): после A3 идут
волны, независимые от A, — трек B (контракт инструмента) и трек C (области
согласования); волны D (схемы) ждут решения владельца по PlantUML.  По
графу зависимостей плана (§4) B и C независимы от A и могут идти параллельно,
а D — после A–C.  Волна 79 — первая волна трека B.

**Что изменилось.**  `lib/yeah-tools.el`:

* `yeah-tools--kinds` (десять видов) поднят в начало модуля; рядом новая
  функция `yeah-tools-kind-known-p` — «вид известен словарю».
* `yeah-tools-register` **отвергает** инструмент, чей объявленный `:kind` вне
  словаря: сигнал `user-error`, в сообщении названы и инструмент, и вид.
* `yeah-tools-kind` (вид для провода) считается через ту же функцию — словарь
  имеет одно место.
* docstring регистрации перечисляет все десять видов (было пять) и говорит,
  что инструмент с видом вне словаря отвергается.

**Claim:** `a-tool-kind-is-in-the-vocabulary`.

**Проверка.**  `tests/checks/check-a-tool-kind-is-in-the-vocabulary.el`
утверждает четыре вещи: каждый объявленный встроенным инструментом вид —
в словаре (по сырым спецификациям, а не по результату `yeah-tools-kind`, иначе
подмена замаскировала бы дефект); инструмент с видом вне словаря
отвергается, и сообщение называет инструмент и вид; инструмент без вида
по-прежнему принимается и по-прежнему едет на проводе как `other`; docstring
регистрации называет каждый вид словаря.

**Доказательство.**  Контроль claim'а ломает страж, а не объявление:
`(not (yeah-tools-kind-known-p kind))` становится `nil` — и проверка падает
кодом 1 **своими** словами (инструмент с неизвестным видом был принят).
Контроль бьёт только по своему предмету: `check-a-tool-call-carries-its-kind.el`
и `tests/unit/test-yeah-tools.el` под ним остаются зелёными, потому что
мутация трогает страж словаря, а не объявление встроенного инструмента.
(Раньше предлагалась мутация объявления — она роняет две чужие проверки; это
и было поймано дискриминатором.)

**Находка, которую волна закрыла: постановка B4 была неверна.**  План утверждал,
что `lib/yeah-emacs.el:88` объявляет `:kind "source"` — вне словаря.  Проверено
чтением кода и живым Emacs: строка 88 — это поле метаданных результата
инструмента `introspect` (третий аргумент `yeah-result-from-output`,
`lib/yeah-result.el:86`), а сам инструмент объявляет `:kind "search"`
(`lib/yeah-emacs.el:193`).  Ни один инструмент `lib/` не объявляет вид вне
словаря, так что «чужого вида» не было — был **дефект тишины**: регистрация
принимала любой вид, а `yeah-tools-kind` молча подменял неизвестный на
`other`.  Постановка исправлена в `docs/ARCHITECTURE-CATCHUP-PLAN.md` §B и в
`docs/SITE-DIAGRAMS-PLAN.md` §B′.  Словарь — соглашение ядра, а не
перечисление протокола: `schemas/acp-v1.json:241–244` объявляет вид простой
строкой.

**Измерение волны.**  Словарь — десять видов; встроенных инструментов
двадцать один, из них шесть не объявляют вид вовсе (это законно, вид `other`).

**Чего волна не делает.**

1. Она не пополняет словарь: решение, становится ли `source` (вид результата
   `introspect`) видом вызова, — за владельцем.
2. Она не меняет вид инструмента, который вида не объявляет: он едет как
   `other`, и это остаётся.
3. Словарь не зафиксирован в схеме протокола: `schemas/acp-v1.json` объявляет
   вид строкой без перечисления.  Добавление `enum` в схему — отдельное
   решение.
4. Утверждение проверки о docstring — утверждение о комментарии; оно падает,
   когда комментарий устаревает, но код ядра от него не зависит.

### 16.71 Пакет волн 76–80: что в пакете, что измерено и что нет
**Что это за пакет.**  Порядок работы — §19.1: пакет — это код, проверки,
кусающиеся контроли, документация и **один** пересчёт метода; полный гейт —
после пакета; живой прогон — один на пакет.  Первым пакетом после решения
владельца были волны 65–71 (§19.1), а гейт после волны 75 (§16.64) закрыл
пакет интеграции с Paseo (по журналу слияний — волны 65–75).  Этот пакет —
следующий после них: волны 76–80.
**Что в пакете.**
| Волна | Что | Claim'ы | Запись |
|---|---|---|---|
| 76 | Режим без человека и корзина вместо удаления | `a-session-may-work-without-a-person`, `a-delete-goes-to-the-trash` | §16.65 |
| 77 | A1 догоняющего плана: состояния ожидания входят в машину состояний | `a-run-waits-in-a-state` | §16.66 |
| 78 | A3: каждая ячейка таблицы проходима рантаймом | `every-transition-of-the-table-is-taken` | §16.69 |
| 79 | B4: вид инструмента в словаре или отказ поимённо | `a-tool-kind-is-in-the-vocabulary` | §16.70 |
| 80 | Каждая ячейка — ход рантайма | `every-transition-of-the-table-is-taken` (amended) | §16.72 |
**Что измерено 20 ноября 2026.**  Проверки четырёх волн пакета проходят на
дереве пакета: `check-a-session-may-work-without-a-person.el` (2243 мс),
`check-a-run-waits-in-a-state.el` (922 мс),
`check-every-transition-of-the-table-is-taken.el` (4 656 мс — после волны 80; до неё было 528 мс),
`check-a-tool-kind-is-in-the-vocabulary.el` (693 мс).  Живой вызов настоящей
модели через транспорт ядра — HTTP 200, ответ пришёл вызовом инструмента,
код выхода 0 (`docs/LIVE-EVIDENCE.md`, «The package of waves 76 to 79»).
**Что не измерено — и это не мелочь.**
1. **Пересчёт пакета не прогонялся.**  Гейт после волны 77 (20 ноября 2026,
   09:13–10:04 UTC, §16.68) прошёл до волн 78, 79 и 80; карты пакета ещё нет,
   и вердикт пакета не может быть назван.
2. **Живой прогон пакета не было.**  Правило §19.1: один живой прогон на пакет
   с коротким промптом.  Последний живой прогон через оркестратор — 19 ноября
   2026 (волны 72 и 73).
3. **Критерии готовности §4.3 плана интеграции не наблюдались в интерфейсе
   Paseo:** для этого нужен живой прогон и наблюдающий человек.
4. **Волна 80 сделана** 20 ноября 2026 (§16.72) — после этой записи; гейт пакета
   после неё ещё не прогонялся, и это пункт 1 выше.
**Что сделала документация пакета (20 ноября 2026).**  Записи `AGENTS.md` о
волнах 77, 78 и 79 и о порядке догоняющего плана; настройка `profile`
плагина (`build`, `plan`, `auto`) описана в `plugin/yeah-provider/README.md` и
`plugin/yeah-provider/OVERVIEW.md`; в §19 добавлена строка волны 76; план
интеграции (§3.4, §3.11) приведён под третий режим и под разницу между
профилем процесса и режимом сессии; статус догоняющего плана
(`docs/ARCHITECTURE-CATCHUP-PLAN.md`) — A1, A3 и B4 сделаны.
**Что нашлось при разборе и осталось открытым.**
* Документация плагина расходилась с ядром: список «что ограничено по проводу»
  называл мёртвыми два разрыва, которые закрыла волна 43 (части 1 и 2, 18
  ноября 2026) — рабочий каталог сессии и именованные аргументы вызова.
  Исправлено в `plugin/yeah-provider/README.md` и `OVERVIEW.md`.
* Устаревший docstring в коде: `yeah-acp--mode-effect` (`lib/yeah-acp.el:133`)
  говорит, что «`plan' запрещает инструменты, меняющие мир, а любой другой
  профиль оставляет вопрос человеку».  Это было верно до волны 76; профиль
  `auto` разрешает без вопроса (проверено на дереве: правила профиля `auto`
  дают `allow`).  Правка кода — дело волны, а не этого параграфа.
* Профиль процесса и режим сессии — разные вещи: настройка `profile` плагина
  наполняет постоянные правила процесса, а по проводу ACP решает режим
  сессии.  Постоянное разрешение вопрос не снимает, поэтому `profile: "auto"`
  сам по себе прогона без вопросов не даёт — режим `auto` включает клиент
  (`docs/PASEO-INTEGRATION-PLAN.md` §3.11).

### 16.72 Каждая ячейка таблицы — ход рантайма — **сделано 2026-11-20 (волна 80)**

**Что это за волна.**  Дискриминатор, проверивший волны 78 и 79, нашёл в волне
78 три существенных расхождения между обещанием и доказательством (D1, D2, D3) и
две мелочи (D4, D5).  Волна 80 закрывает их **без переименования claim'а**: имя
волны, id claim'а и имя проверки обещали покрытие ячейки, и волна 80 сделала
доказательство таким, каким было обещание.  Прецедент — §16.28 (claim
`the-live-stand-waits-for-an-answer' был поправлен «amended and not rewritten»).

**Находка D1 — обещание про метку, доказательство про ячейку.**  Проверка волны 78
покрывала метку.  Дискриминатор заменил ячейку `(compacting error . failed)' на
`(compacting interrupt . interrupted)': машина больше не могла увести прогон из
`compacting' в `failed' по метке `error', а проверка оставалась зелёной.

**Что изменилось в `tests/checks/check-every-transition-of-the-table-is-taken.el`.**

1. **Проверка говорит про ячейку.**  Для каждой ячейки таблицы сказано, что
   машина делает этот ход: `yeah-loop-tick' из состояния `FROM' меткой `LABEL'
   отвечает состоянием `TO' и ничем иным (иначе — «the machine refuses the
   move»).  Для метки с одной ячейкой покрытие следует из самого взятия метки:
   взяв метку, рантайм не может пойти в другую ячейку.  Для веера (`error',
   `interrupt') сказано, что веер накрывает ровно те состояния, в которых может
   жить прогон, кончается в одном состоянии и что страж места тика не
   разрешает состояние, на которое у веера нет ребра.
2. **Мёртвый код больше не выдаёт себя за живой (D2).**  Проверка строит граф
   достижимости ядра: корень — автозагрузочная кука, ссылка из `tests/' или
   `scripts/', ссылка из формы верхнего уровня `lib/'; дальше — обход по
   вызовам.  Место тика считается живым, только если его определение
   достижимо.  Обход заходит внутрь аргументов вызова (тело `let' — тоже вызов
   рантайма) и обходит пару с точкой по частям; имена собираются в таблицу, а
   не в список, который терял бы добавленное.
3. **Метка читается из позиции метки и больше ниоткуда (D3).**  Метка — третий
   элемент вызова `(yeah-turn--tick TURN LABEL)'; закавыченный символ в другом
   аргументе больше не выдаётся за ход машины.

**Claim:** `every-transition-of-the-table-is-taken` — **amended, not rewritten**:
id прежний, текст переведён на смысл ячейки, добавлено требование
`./scripts/dev ert tests/unit/test-yeah-loop.el` (юнит-тест пинит все 31 ячейку
таблицы вручную — это второй источник истины о таблице), `falsifier` переписан
под ячейку, `control` перенесён на мутацию таблицы.

**Доказательство (контроли, все на копии дерева, 2026-11-20).**

| Контроль | Что сделано | Что сказала проверка |
|---|---|---|
| Таблица | `(compacting       error         . failed)` → `(compacting       interrupt     . interrupted)` | «the table of the machine names 1 fan(s) the runtime does not keep», код 1 |
| Мёртвый код | вызов `yeah-turn--retry' переименован — определение стало недостижимым | «1 move(s) that the runtime does not take: (rate-blocked)» и «1 cell(s) the runtime never walks: ((deciding rate-blocked . blocked-on-rate))», код 1 |
| Позиция метки | закавыченный `rate-blocked' перенесён в другой аргумент вызова | то же, что во втором контроле, код 1 |
| Прежний контроль волны 78 | тик `tool-end' убран | «1 move(s) that the runtime does not take: (tool-end)», код 1 |

**Измерение волны.**  Ячеек в таблице — 31, меток — 17, состояний — 11.  Мест
тика в рантайме — 23, и все 23 живые.  Определений ядра — 911, корней
живости — 77, живых определений — 776.  Проверка идёт 4.6 с.  Полный набор
проверок (105 файлов: 99 `.el` и 6 `.sh`) и юнит-тесты — зелёные.

**D4 и D5 — мелочи, закрытые здесь же.**  Ссылка `lib/yeah-tools.el:104–133' как
диапазон описания спецификации инструмента устарела после волны 79 (описание
спецификации — `:120–153'); исправлена в `docs/ARCHITECTURE-CATCHUP-PLAN.md' и
`docs/SITE-DIAGRAMS-PLAN.md'.  В `waves/wave-78.json' число юнит-тестов было
«четыреста пятьдесят восемь» — на самом деле 460 (460 форм `ert-deftest');
исправлено.

**Чего волна не делает.**

1. Она не переименовывает claim: id остался прежним, а форма доказательства
   догнала обещание.
2. Она не говорит, что прогон берёт каждую ячейку: такого прогона нет (прогон,
   который не встретил занятого провайдера, не берёт `rate-blocked').
3. Она не доказывает место назначения ячейки против второго источника: это делает
   юнит-тест `tests/unit/test-yeah-loop.el', который пинит 31 ячейку руками.
4. Она не закрывает долг состояния прогона (§16.66) и не делает живую сторону
   таблицы полной: достижимость говорит «достижимо», а не «достигается на
   каждом пути».

---

### 16.73 Пайплайн схем находит инструмент сам и рисует обе темы — **сделано 2026-11-20 (волна 81)**

**Что это за волна.**  Первая волна догоняющего плана на треке D (волна D0,
`docs/ARCHITECTURE-CATCHUP-PLAN.md`): сайт Yeah статический, а схемы архитектуры
были рисунком, который никто не мог перерисовать.  Скрипта, который превращает
исходник схемы в картинку, не было — смена машины состояний не меняла ничего
на сайте, и картинка тихо гнила.  Волна даёт сайту этот скрипт и две шкурки
тем.

**Что изменилось.**

1. **Подкоманда `scripts/dev diagrams`.**  Она рисует каждую схему из
   `site/diagrams/` в `site/assets/diagrams/` — по две картинки на схему,
   светлую и тёмную.  Файлы `palette-*` шкурками считаются, диаграммами — нет.
   Имена картинок — правило, а не список: `site/diagrams/<имя>.puml` даёт
   `<имя>-light.svg` и `<имя>-dark.svg`.
2. **Цепочка поиска инструмента живёт в одном месте** — `scripts/lib/tools.sh`,
   функция `find_tool`.  Шаги одинаковы для всех инструментов: переменная
   окружения → команда в `PATH` → бинарник пользователя в `~/.nix-profile/bin` →
   стор nix, если вызывающий назвал glob.  **Исключение, названное волной 83
   (F7):** у `mathc` своя копия поиска — `find_mathc` в `scripts/lib/method.sh`;
   она ищет бинарник метода и шага в сторе не делает.  Шаг со стором есть **только** у
   PlantUML: в сторе лежит много версий Emacs, и выбор версии Emacs не должен
   быть случайным, поэтому `find_emacs` останавливается на трёх шагах.  Находка
   догоняющего плана («либо описать реальную цепочку, либо добавить шаг») закрыта
   обоими способами сразу.
3. **Код 3 — «инструмента нет».**  Пайплайн отвечает кодом 3, когда PlantUML не
   найден; «инструмент не установлен» никогда не читается как «схема в порядке».
   Тот же код, что и у проверок метода для машины, которая не может ответить.
4. **Шкурка темы — файл сам по себе**, `site/diagrams/palette-light.puml` и
   `palette-dark.puml`: по 23 строки `skinparam`, пять различных цветов в
   каждой.  Цвета шкурок — **токены сайта** из `site/styles.css`:
   `--face-default-bg`, `--face-default-fg`, `--face-fringe-bg`,
   `--face-divider`, `--face-prose`.
5. **Исходник схемы остаётся файлом схемы.**  Шкурка подставляется внутрь
   `@startuml`, поэтому исходники читаемы и не зависят друг от друга.

**Claim:** `the-diagram-pipeline-renders-both-themes` — новый, с требованием
`./scripts/dev check tests/checks/check-the-diagram-pipeline-renders-both-themes.sh`
и с контролем `sed -i 's|for theme in light dark; do|for theme in light; do|' scripts/dev`.

**Доказательство (контроли, все на копии дерева, 2026-11-20).**

| Контроль | Что сделано | Что сказала проверка |
|---|---|---|
| Одна тема (контроль claim'а) | в цикле тем осталась только светлая | «the pipeline did not report that it drew two pictures», «the dark picture of the probe is missing or empty», код 1 |
| Инструмента нет совсем | имя в `PATH` и glob в сторе испорчены | «the pipeline answered 3 where the probe of both themes must be drawn», код 1 |
| Код 3 стал кодом 0 | ветка «инструмента нет» отвечает 0 | «the pipeline answered 0 where PlantUML is not there and the answer must be 3», код 1 |
| Тёмной шкурки нет | `palette-dark.puml` удалена | «the palette of the dark theme is missing», код **1** (а не 2: это нарушенное обещание, а не машина, которая не может ответить) |
| Чужой цвет | `StateBorderColor #123456` | «the StateBorderColor of the palette … is #123456 and the token --face-divider of the site is #999999», код 1 |
| Цвет уплыл | `backgroundColor #FEFEFE` вместо `#ffffff` | «the backgroundColor of the palette … is #FEFEFE and the token --face-default-bg of the site is #ffffff», код 1 |
| Слова отчёта изменились | «rendered … picture(s) of … diagram(s)» → «drew … image(s) for … scheme(s)» | код **0** — проверка не зависит от формулировки |

Последний контроль — контроль второго рода: он ломает не обещание, а связь
проверки с формулировкой, и она обязана выжить.  Первые три правки проверки
(палитра отсутствует → вердикт 1; свободная формулировка в отчёте; связка
палитр с `site/styles.css` по именам токенов) сделаны после первого прогона
контролей — так нашёл их прогон.

**Измерение волны.**  В каждой шкурке 23 строки `skinparam` и пять различных
цветов; каждый цвет обеих шкурок — цвет `site/styles.css`.  Проверка — 13.6 kB,
идёт 2.6 с.  Полный набор проверок (105 файлов: 99 `.el` и 6 `.sh`) и юнит-тесты — зелёные.

**Чего волна не делает.**

1. Она не рисует ни одной схемы: первая схема (машина состояний, порождённая
   кодом) — волна D1, остальные семь — волна D2.  Каталог картинок
   `site/assets/diagrams/` в репозитории создан (пока в нём только `.gitkeep`:
   картинок ещё нет, а пустой каталог git не хранит) — иначе документация
   называла бы путь, в котором ничего нет, и проверка
   `the-documentation-points-at-files-that-exist` была бы права.  Проверка рисует
   **прокладную** схему в отдельном временном дереве, поэтому дерево
   репозитория проверка не трогает.
2. Пайплайн — инструмент **автора**, а не шаг сборки сайта: на публикацию
   уезжают готовые SVG, и сайт без PlantUML не сломан.
3. Шаг со стором — host-specific; первый матч оболочки берётся, так что выбор
   на одной машине один и тот же.
4. Она не доказывает, что схема архитектуры — хорошая схема: это глаз автора,
   а не проверка.

**Поправка дискриминатора волны 81 (20 ноября 2026).**  Дискриминатор,
проверивший волну 81, нашёл восемь расхождений между обещанием и
доказательством и вынес вердикт: **код волны честен, доказательство — нет**.
Пайплайн работает, но проверка доказывает меньше, чем claim обещает, и местами
падает на корректной реализации.  Пять находок важны: ни один шаг цепочки
поиска не доказан (F1); «каждая схема» не измерена — в фикстуре одна (F2); код 1
при падении PlantUML не измерен (F3); картинка привязана к **числам**, а не к
токенам, из-за чего проверка падает на смене значения токена в
`site/styles.css` и проходит зелёной пайплайн, вшивающий шкурку в код (F4);
проверка зависит от формулировки отчёта, и контроль «слова отчёта изменились»
проходит случайно (F5).  Три мелочи: «99 файлов» вместо 105 (F6), «цепочка
поиска живёт в одном месте» буквально неверно — у `mathc` своя копия (F7), и
`.gitkeep` не был перечислен в `touches` волны (F8).  **Починка — волна 83**
(план — `docs/ARCHITECTURE-CATCHUP-PLAN.md` §D0); до неё claim'а
`the-diagram-pipeline-renders-both-themes` обещает больше, чем доказывает, и
опираться на него как на доказательство нельзя.  **Код при этом менять не
нужно** — чинится доказательство.

---

### 16.74 Доказательство таблицы читает состояние места и сверяет веер с рантаймом — **сделано 2026-11-20 (волна 82)**

**Что это за волна.**  Починка доказательства трека A (волна A3,
`docs/ARCHITECTURE-CATCHUP-PLAN.md` §A3).  Дискриминатор волны 80 нашёл шесть
дефектов доказательства: три критичных (D6, D7, D8), два важных (D9, D10) и
одну мелочь (D11).  **Код волны 80 честен** — таблица машины и рантайм не
трогались: чинится доказательство, и чинит его тот же файл
`tests/checks/check-every-transition-of-the-table-is-taken.el` (было 582 строки и
25 527 байт, стало 793 строки и 35 675 байт).  Прецедент — §16.28: claim
правится «amended and not rewritten», id прежний.

**Находка D6 (критичная) — состояние места не читалось вовсе.**  Две ветви,
которые читают состояние прогона, брали аргументы формы как `(cdr (cdr form))`,
а аргументы формы — это `(cdr form)`.  Ветви `eq` и `memq` были мёртвым кодом:
сравнение искалось на месте самого состояния, ничего не находилось, и состояние
места не читалось **никогда**.  Следствие было прямым: любая ячейка свидетельствовалась
любым местом своей метки, а рантайм, берущий ход `deciding` из `post-decide`,
проходил проверку зелёной.

**Находка D7 (критичная) — веер сверялся «таблица ↔ таблица».**  Теперь веер
сверяется **с рантаймом**: покрытие веера — это объединение состояний, которые
допускают гварды живых мест с этой меткой.  Таблица ⊆ покрытие («рантайм не
сужает веер»), и обратное ловится проверкой мест (состояние места ⊆ множества
`FROM` этой метки).  Веер кончается в одном состоянии.

**Находка D8 (критичная) — «живой» значило «достижим из теста».**  Теперь
живость — это живость **рантайма**: корень графа — автозагрузочная кука **или**
ссылка из формы верхнего уровня `lib/`; дальше — обход по вызовам.  Определение,
которое зовёт только `tests/` или `scripts/`, мертво для рантайма, и ход в таком
месте — не ход рантайма.  Ключевое: это **другое** свойство, а не переименование
того же самого, — контроль K5 ниже это показывает (см. таблицу).

**Находка D9 (важная) — падение вместо вердикта.**  `(apply #'cl-intersection sets)`
с одним списком даёт `wrong-number-of-arguments`.  Теперь `cl-union` и
`cl-intersection` зовутся только при двух и более наборах, а весь прогон стоит в
`condition-case`: «the check could not read the kernel: …», код 1.

**Находка D10 (важная) — две проверки из пяти не добавляли доказательства.**
Дубликат «каждая ячейка пройдена» убран; вместо него таблица проверяется на
well-formed (состояния ячейки — состояния машины, метка — символ, машина делает
ровно этот ход).

**Claim:** `every-transition-of-the-table-is-taken` — **amended, not rewritten**:
id прежний, текст переведён на смысл, который проверка действительно доказывает;
`falsifier` переписан под новые отказы.

**Что гейт пакета нашёл в самой волне (20 ноября 2026).**  Гейт пакета волн
82–83 вернул код 3, и карта показала `every-transition-of-the-table-is-taken`
как **inconclusive**: требование `./scripts/dev ert tests/unit/test-yeah-loop.el`
не было ни провалено, ни подтверждено.  Причина — **контроль claim'а, который
перенесли с мутации таблицы на мутацию рантайма**: юнит-тест читает
`lib/yeah-loop.el`, а мутация трогала `lib/yeah-turn.el`, и после контроля
юнит-тест оставался зелёным — контроль **не достигал** предмета этого
требования.  Метод это видит и говорит «inconclusive» вместо «pass»; это ровно
та работа, ради которой он заведён.  Контроль возвращён к составному: он ломает
и таблицу (`(compacting error . failed)` → `(compacting interrupt . interrupted)`),
и рантайм (тик `user-prompt` переносится из состояния `idle` в состояние
`deciding`).  Составной контроль проверен на копии дерева: проверка падает с
кодом 1 («the runtime takes 1 move(s) the machine does not have»), юнит-тест
падает с кодом 1 (два теста).  Первая часть ломает таблицу (предмет юнит-теста),
вторая — связь «ячейка ↔ `FROM`» в рантайме (предмет проверки): контроль
достигает обоих требований и проверяет обе половины доказательства.

**Доказательство (контроли, все на копии дерева, 2026-11-20).**  Восемь
контролей сделаны **родителем независимо от отчёта писателя**; семь — писателем.
Все шестнадцать дали запрошенный вердикт.

| Контроль | Что сделано | Что сказала проверка |
|---|---|---|
| Честный код | ничего | код 0; «31 cell(s), 17 label(s), 11 state(s); 23 place(s) of a tick in the kernel, 23 of them live» |
| Ход из чужого состояния (D6) | тик `user-prompt` перенесён из `idle` в `deciding` (`lib/yeah-turn.el:1385`) | «the runtime takes the move from another state» для ячейки `(idle user-prompt . deciding)` и «the place stands in a state the machine has no move from», код 1 |
| Веер сужен (D7) | страж места `error` в `lib/yeah-turn.el:320` сужен до `deciding` | «the runtime narrows the fan (deciding)», код 1 |
| Ячейка без места | тик `nudge` убран из рантайма | «the runtime does not take the move» для ячейки `(post-decide nudge . deciding)`, код 1 |
| Живость (D8) | тот же тик перенесён в определение `lib/`, которое зовёт **только тест** | «the runtime does not take the move» — место мертво для рантайма, код 1 |
| Живость (D8), обратная сторона | то же определение с кукой `;;;###autoload` | код **0** — кука делает определение корнем рантайма |
| Регресс D6 | чтение состояния возвращено к `(cdr (cdr form))` | код 0, **но доказательство пустеет**: 29 слабых ячеек вместо 16 — правка несущая и измеримая |
| Падение — вердикт (D9) | исключение внутри проверки | «the check could not read the kernel: …», код 1 |

**Измерение волны.**  Ячеек — 31, меток — 17, состояний — 11.  Мест тика в ядре —
23, и все 23 живые для рантайма.  **Сильных ячеек — 15, слабых — 16:** слабая
ячейка та, чьё место стоит под стражем, который **ничего не говорит о
состоянии**; она доказывается одной таблицей, и проверка перечисляет такие
ячейки поимённо, чтобы читатель видел, на чём стоит доказательство.  Усилить их
может только рантайм (`lib/yeah-turn.el` — файл автора волны 80).  Единственный
веер, состояний которого рантайм не называет, — `interrupt`; проверка говорит и
это.  Проверка идёт 4.1 с.

**Попутно исправлены скрытые баги того же файла** (без них проверка просто не
запускалась): `cond` в Emacs 30 — C-спецформа, голое `else` не принимается;
`multiple-value-bind` в Emacs 30.2 нет — функция состояния возвращает plist;
обход не переступал точечную пару `(utf-8 . utf-8)`; хвост `pcase` брал субъект
за клаузу; `plist-put` мутирует и возвращает новый список.

**Находка D11 (мелочь)** — устаревшие числа «12/20» и пример `tick-resume` —
закрыта волной 81.

**Чего волна не делает.**

1. Она не говорит, что прогон берёт каждую ячейку: такого прогона нет (прогон,
   который не встретил занятого провайдера, не берёт `rate-blocked'; прогон,
   который не вырос, не берёт `budget-overflow').  Проверка **статическая**
   сознательно: она отвечает о всём ядре сразу и отвечает одинаково дважды.
2. Она не измеряет живость **для тестов** — это свойство тестов, а не рантайма.
3. Она не делает 16 слабых ячеек сильными: это может сделать только рантайм.
4. Она не трогает код ядра: таблица машины и рантайм были честны.
### 16.75 Доказательство пайплайна меряет каждый шаг цепочки и каждую схему — **сделано 2026-11-20 (волна 83)**

**Что это за волна.**  Починка доказательства трека D (волна D0,
`docs/ARCHITECTURE-CATCHUP-PLAN.md` §D0).  Дискриминатор волны 81 нашёл восемь
расхождений (пять важных, три мелочи) и вынес вердикт: **код волны честен,
доказательство — нет**.  Пайплайн работает, но проверка доказывает меньше, чем
claim обещает, и местами падает на корректной реализации.  **Код пайплайна,
шкурки и сайт волна 83 не трогает** — чинится доказательство, и чинит его тот
же файл `tests/checks/check-the-diagram-pipeline-renders-both-themes.sh` (было
410 строк и 13.6 kB, стало 736 строк и 27.5 kB).

**Находка F1 — ни один шаг цепочки поиска не был доказан.**  Проверка искала
PlantUML **своей** цепочкой (это правильно), и потому шаги `find_tool` не были
измерены ни положительно, ни отрицательно: сломанный шаг молча заменялся
следующим.  Теперь в фикстуре **четыре прогона**, по одному на шаг — переменная
окружения, команда в `PATH`, бинарник в `~/.nix-profile/bin`, glob стора nix, —
и в каждом прогоне доступен **ровно один** шаг; каждый обязан кончиться кодом 0
и двумя картинками.  Цепочка меряется и как текст: `find_tool` определён
**ровно в одном** файле `scripts/`, и `scripts/dev` его читает.

**Находка F2 — «каждую схему» не измерено.**  Теперь в фикстуре две схемы с
разными именами, список ожидаемых картинок **выводится из дерева** (это и есть
`2·N` без вписанного числа), и картинка обязана нести **метку своего** исходника
и не метку чужой.

**Находка F3 — код 1 не измерен.**  Три разные поломки измерены по отдельности:
битая схема (PlantUML падает), подставной PlantUML, который ничего не пишет, и
подставной PlantUML, который пишет картинку с `Syntax Error`.  Каждая должна
ответить кодом 1.

**Находка F4 — картинка привязана к числам, а не к токенам.**  Ожидаемые цвета
теперь **читаются из `site/styles.css`** по именам токенов, и в проверке не
осталось ни одного hex-литерала ожидания.  Шкурка копии в фикстуре несёт
**маркер** (`skinparam defaultFontName "YeahWave83MarkerFont"`), которого нет в
коде пайплайна, — так «картинка нарисована шкуркой из файла» становится
доказуемым, а пайплайн, вшивающий шкурку в код, падает.

**Находка F5 — проверка зависела от формулировки отчёта.**  Оба grep'а по
формулировке **удалены**: число картинок и число схем меряется по дереву, а
слова отчёта читаются только для диагностики при падении.

**Claim:** `the-diagram-pipeline-renders-both-themes` — **amended, not rewritten**:
id прежний, текст говорит, что **каждый** шаг цепочки работает сам по себе и что
пайплайн отвечает кодом 1 при падении PlantUML; `falsifier` переписан под новые
отказы; `control` прежний (в цикле тем теряется тёмная).

**Доказательство (контроли, все на копии дерева, 2026-11-20).**  Семь контролей
сделаны писателем волны, **восемь — родителем, независимо от отчёта писателя**.
Все пятнадцать дали запрошенный вердикт.

| Контроль | Что сделано | Что сказала проверка |
|---|---|---|
| Честный код | ничего | код 0, 12 с (было 2.6 с) |
| Формулировка отчёта (F5) | строка отчёта переписана как угодно | код **0** — проверка не зависит от слов |
| Токен сменился, шкурка последовала (F4) | `--face-divider: #999999` → `#8a8a8a`, шкурка следом | код **0** — привязка по имени токена, смена значения не дефект |
| Шкурка уплыла (F4) | `StateBorderColor #123456` | «the StateBorderColor of the palette of the light theme is #123456 and the token --face-divider of the site is #999999», код 1 |
| Тёмной шкурки нет | `palette-dark.puml` удалена | «the palette of the dark theme is missing», код **1** (а не 2) |
| Тема потеряна (контроль claim'а) | `for theme in light dark` → `light` | «the step of the environment of the chain of the search drew [probe-light.svg ] and not the two pictures of the probe», код 1 |
| PlantUML упал (F3) | падающая ветвь отвечает 0 | «the pipeline answered 0 where PlantUML cannot read the diagram and the answer must be 1», код 1 |
| Только первая схема (F2) | `break` после первой схемы | «the pipeline drew [alpha-dark.svg alpha-light.svg ] and not two pictures for every diagram» и «the picture of beta (light) is missing or empty», код 1 |
| Шаг `PATH` цепочки убран (F1) | ветвь `command -v` удалена | «the step of the PATH of the chain of the search answered 3 and not 0», код 1 |
| Шаг окружения убран (F1) | ветвь переменной окружения удалена | «the step of the environment of the chain of the search answered 3 and not 0», код 1 |
| Шкурка вшита в код (F4) | пайплайн пишет свою шкурку вместо чтения файла | «the picture of alpha (light) does not carry the marker YeahWave83MarkerFont of the skin of the fixture», код 1 |
| Цепочка скопирована (F1) | копия `tools.sh` во втором файле `scripts/` | «the chain of the search is defined in [scripts/lib/tools-copy.sh scripts/lib/tools.sh] and not in one place», код 1 |
| `scripts/dev` не читает цепочку | строка подключения удалена | «the pipeline does not use the chain of the search», код 1 |
| Чистота дерева | — | временных деревьев не осталось: 0 |

**Измерение волны.**  Проверка — 736 строк и 27.5 kB, идёт 12 с.  В фикстуре две
схемы дерева и четыре прогона цепочки.  Проверок у метода **105**: 99 `.el` и
6 `.sh` (F6 — число «99 файлов» исправлено в §16.72 и §16.73).

**Мелочи F7 и F8 закрыты здесь же.**  F7: «цепочка поиска живёт в одном месте»
буквально неверно — у `mathc` своя копия поиска (`find_mathc` в
`scripts/lib/method.sh`: она ищет бинарник метода и шага в сторе не делает).
Исключение названо в документах.  F8: файл `.gitkeep` в каталоге
`site/assets/diagrams/` добавлен в `touches` волны 81.

**Чего волна не делает.**

1. Она не рисует ни одной схемы сайта: первая схема (машина состояний,
   порождённая кодом) — волна D1, остальные семь — волна D2.
2. Она не проверяет, что опубликованная картинка свежая — это волна D4.
3. Пайплайн — инструмент **автора**, а не шаг сборки сайта: на публикацию уезжают
   готовые SVG, и сайт без PlantUML не сломан.
4. Шаг со стором — host-specific; первый матч оболочки берётся, так что выбор
   на одной машине один и тот же.

### 16.76 Схема машины состояний порождается кодом — **сделано 2026-11-20 (волна 84)**

**Что это за волна.**  Волна D1 трека D (`docs/ARCHITECTURE-CATCHUP-PLAN.md` §D1).
Машина ядра — это таблица в коде: состояния живут в `yeah-state-list`, ячейки — в
`yeah-loop--raw-transitions`.  **Схема машины состояний больше не рисуется руками:**
она **порождается кодом**, и разойтись с таблицей по построению не может — таблица
изменилась, схема стала другой.

**Что сделано.**

1. **Генератор** (`lib/yeah-state-diagram.el`, 100 строк): читает `yeah-state-list`
   и `yeah-loop--raw-transitions` и говорит исходник PlantUML.  Исходник — функция
   кода и **ничего больше**: ни даты, ни хеша, ни своего порядка; тот же код даёт
   те же байты.  Начальное состояние машины — то, из которого приходит первая ячейка
   таблицы.  Два состояния, которые PlantUML не различает, — ошибка генератора, а
   не молчание: диаграмма, которая врёт, не диаграмма.
2. **Подкоманда** `scripts/dev state-diagram` и **общий** вызов генерации: пайплайн
   `scripts/dev diagrams` генерирует исходник **до** того, как что-либо рисует.
   Генерация, которая упала, кончает пайплайн его собственным ответом, и **ничего не
   рисуется**.
3. **Исходник закоммичен** (`site/diagrams/state-machine.puml`, 46 строк): 11
   состояний и 31 стрелка, начало `[*] --> idle`.
4. **Проверка claim'а** (`tests/checks/check-the-state-diagram-comes-from-the-code.sh`,
   397 строк, 16.7 kB, 3.5 с) меряет каждую часть обещания: файл репозитория против
   файла, который пишет **копия ядра**; ячейка, добавленная в таблицу копии;
   состояние, добавленное в список состояний копии; полнота схемы (числа
   **читаются из кода** и не вписаны в проверку); две темы картинки; дерево без
   ядра; и то, что дерево репозитория проверка не пишет.

**Claim:** `the-state-diagram-comes-from-the-code` — **новый** (не амендит): обещание
волны 83 о пайплайне не тронуто — пайплайн рисует каждую схему дерева в обеих темах,
как и раньше, а схем в дереве стало на одну больше.

**Доказательство (контроли, все на копии дерева, 2026-11-20).**  Восемь контролей
сделаны писателем волны, **семь — родителем, независимо от отчёта писателя**.  Все
пятнадцать дали запрошенный вердикт.

| Контроль | Что сделано | Что сказала проверка |
|---|---|---|
| Честный код | ничего | код 0, 3 с |
| Контроль claim'а | ячейка `(deciding stream-end . post-decide)` → `(deciding stream-end . accumulating)`, схема не перегенерирована | «the diagram of the repository is not the diagram that the code writes: the table of the transitions changed and the diagram was not written again», код 1 |
| Схема правлена руками | стрелка переписана в `site/diagrams/state-machine.puml` | тот же вердикт о расхождении, код 1 |
| Генератор слеп к таблице | `(dolist (cell nil)`, исходник репозитория подогнан под него | «the diagram of the changed table has no arrow of the new cell: the generator does not read the table», код 1 |
| Тёмная шкурка сломана | `palette-dark.puml` испорчена | пайплайн проверки ответил не 0, код 1 |
| Генерация без файла | генератор печатает пустоту | код 1 — проверка называет это |
| Дерево без ядра | `lib/yeah-state-diagram.el` отсутствует | код **3** и причина названа |
| Проверка волны 83 на дереве волны 84 | — | код 0; её собственный контроль (в цикле тем теряется тёмная) кусается, код 1 |

**Измерение волны.**  Модуль — 100 строк и 4.4 kB.  Проверка — 397 строк и 16.7 kB,
3.5 с.  Схема: 11 состояний, 31 стрелка, 17 меток (`interrupt` × 8, `error` × 8) —
те же числа, что у таблицы машины.  Пайплайн рисует 2 картинки одной схемы.
Проверок у метода — **106**: 99 `.el` и 7 `.sh` (в волне 83 было 105: 99 и 6).

**Расхождения с планом — названы, а не спрятаны.**  План §D1 обещал формат
`state post-decide`; **PlantUML 1.2025.10 не читает дефис в идентификаторе** —
имя с дефисом сохраняет свой текст как подпись (`state "post-decide" as
post_decide`), а концы стрелок говорят производный идентификатор.  Имена машины в
картинке — как есть.  `@startuml state-machine` даёт картинке имя диаграммы, а не
файла, — пайплайн научился находить написанную картинку и давать ей имя темы.
`scripts/dev diagrams` теперь **требует ядро** (генерация до рендера): дерево без
ядра отвечает 3 и ничего не рисует.  Пайплайн пишет сгенерированный исходник в
дерево, из которого рисует, — утверждение волны 83 «дерево исходников хранит только
исходники» переписано.

**Чего волна не делает.**

1. Она не рисует ни одной картинки сайта: SVG не коммитятся, это волны D3 и D4.
2. Она не вставляет схему в страницы сайта — волна D3.
3. Она не проверяет, что опубликованная картинка свежая, — волна D4.
4. Она не рисует остальные семь схем сайта (план §D2, §8
   `docs/SITE-DIAGRAMS-PLAN.md`): здесь только машина состояний, и та — порождённая
   кодом.

### 16.77 Доказательство пайплайна меряет цепочку поиска и **всё** исходника — **сделано 2026-11-20 (волна 86)**

**Что это за волна.**  Вторая починка доказательства трека D (волна D0).
Дискриминатор пакета волн 82–83 нашёл две ложно-зелёные точки в проверке волны 83:
**F12** («цепочка поиска живёт в одном месте» не измерялась) и **F17** («картинка
нарисована из своего исходника» измерялась только меткой).  **Код пайплайна,
шкурки и сайт волна 86 не трогает** — чинится доказательство, и чинит его тот же
файл `tests/checks/check-the-diagram-pipeline-renders-both-themes.sh` (было
821 строка и 31 259 байт, стало 940 строк и 36 910 байт).

**Находка F12 — «цепочка живёт в одном месте» удовлетворялось комментарием.**
Проба искала в `scripts/dev` **любое упоминание** файла цепочки — и комментарий
`# shellcheck source=scripts/lib/tools.sh` её удовлетворял: удаление строки
подключения оставляло проверку зелёной.  Кроме того, копия тела цепочки под
**другим именем** не ловилась вовсе: `grep -rl '^find_tool()'` находит только
второе определение **с тем же именем**.  Теперь проверка ищет **строку подключения**
(`^[[:space:]]*(\.|source)[[:space:]]+.*lib/tools\.sh`) и **вызов** цепочки, а тело
цепочки извлекается из `scripts/lib/tools.sh` и ищется в каждом другом файле
`scripts/` — **по телу, а не по имени** (нечувствительно к пробелам и комментариям),
плюс отдельно ищутся **шаги** поиска (`command -v` **и** проба `~/.nix-profile/bin`).

**Находка F17 — картинка из «куска» своего исходника проходила.**  Проверка требовала,
чтобы картинка несла **метку** своего исходника, и этого хватало: обёртка, собранная
из **урезанного** исходника, давала картинку без второй вершины — и проверка
отвечала кодом 0.  Теперь для каждой картинки и каждой темы сверяются **все метки
исходника** (состояния и стрелки) с **текстами** картинки SVG.

**Claim:** `the-diagram-pipeline-renders-both-themes` — **amended, not rewritten**:
id прежний; текст говорит, что цепочка поиска живёт в одном месте и что каждая
картинка нарисована из **всего** своего исходника; `falsifier` переписан под новые
отказы; `control` прежний.

**Доказательство (контроли, все на копии дерева, 2026-11-20).**  Семь контролей
сделаны писателем волны, **пять — родителем, независимо от отчёта писателя**.  Все
двенадцать дали запрошенный вердикт.

| Контроль | Что сделано | Что сказала проверка |
|---|---|---|
| Честный код | ничего | код 0, 28 с |
| Подключение цепочки убрано (F12) | строка `. "$script_dir/lib/tools.sh"` удалена, комментарий оставлен | «scripts/dev does not read scripts/lib/tools.sh: the pipeline does not use the chain of the search», код 1 |
| Копия тела цепочки под другим именем (F12) | копия `tools.sh` в `scripts/lib/` под именем `find_tool_of_the_copy` | «the body of the chain of the search is copied in scripts/lib/tools-copy.sh: the chain lives in one place (scripts/lib/tools.sh) and not in two», код 1 |
| Исходник урезан (F17) | обёртка собирается из исходника **без** строк `second-of-` | «the picture of alpha (light) does not carry the label second-of-alpha of its own source: the picture was drawn from a part of its source» (и ещё три картинки), код 1 |
| Цепочка не подключена, тело скопировано в `scripts/dev` | строка подключения удалена, тело вставлено в `scripts/dev` | три сообщения разом: «does not read», «defined in [scripts/dev scripts/lib/tools.sh]», «the body of the chain of the search is copied in scripts/dev», код 1 |
| Контроль claim'а (прежний) | `for theme in light dark` → `light` | «the pipeline drew [alpha-light.svg beta-light.svg state-machine-light.svg ] and not two pictures for every diagram», код 1 |

**Ложно-зелёные точки измерены, а не заявлены.**  **Старая** проверка (из `HEAD` до
волны 86) на копии тела цепочки отвечает кодом **0** (молча), и на урезанном
исходнике — тоже кодом **0** (молча).  С новой проверкой обе точки падают кодом 1.

**Писатель измерил ещё одну вещь и назвал её.**  **Буквальный** текст контроля
дискриминатора по F17 — `"$src" | sed "/second-of-/d" >"$wrapper"` — **вообще не
урезает исходник**: оболочка читает `"$src"` как команду к исполнению, а не как файл.
Проверка и там падает, но на рантайме, а не на содержимом исходника.  Мутация,
которая действительно режет исходник, приведена выше.

**Измерение волны.**  Проверка — 940 строк и 36.9 kB, идёт 28 с.  Регрессии: проверка
волны 84 — код 0, `./scripts/dev byte-compile-all` — код 0, `./scripts/dev ert
tests/unit/*.el` — **458/458**.

**Чего волна не делает.**

1. Она не ищет копию цепочки **вне** `scripts/` — область поиска прежняя.
2. Копия, которая **переписана**, а не скопирована, уходит от поиска по телу; её ловит
   только поиск шагов, и то если она сохранила оба шага.
3. Подключение, спрятавшее путь за переменной, не опознаётся как чтение
   `scripts/lib/tools.sh`.
4. Мерка «весь исходник» — это мерка **присутствия**: картинка, нарисованная из
   **надмножества** исходника, ею не видна.

### 16.78 Доказательство таблицы читает состояние места, живость места и покрытие веера — **сделано 2026-11-20 (волна 85)**

**Что это за волна.**  Вторая починка доказательства трека A (волна A3).
Дискриминатор пакета волн 82–83 нашёл девять находок, из которых **шесть** касаются
доказательства таблицы (F9–F14).  **Код ядра волна 85 не трогает** — чинится
доказательство, и чинит его тот же файл
`tests/checks/check-every-transition-of-the-table-is-taken.el` (было 793 строки и
35 675 байт, стало 1102 строки и 51 445 байт).

**Главная находка — проверка ячеек не могла дать отказ никогда.**  `yeah-check--fail`
стоял **внутри** `dolist (cell …)`, а `dolist` всегда возвращает `nil`: проверка
ячеек отвечала «да» на что угодно.  Плюс `unless` стоял внутри внутреннего `dolist`
по местам, и решение принималось по **первому** месту, а не по всем.  Отсюда —
и ложно-зелёные контроли дискриминатора, и «22 повтора трассировки на одной ячейке».
Вердикт вынесен из цикла, а свидетель ячейки читается по **всем** местам её метки.

**Находка F9 — свидетелем ячейки был мёртвый или молчаливый место.**  Теперь
свидетельствует только **живое** место — то, что рантайм выполняет; место, которое
достигает лишь имя, тест или скрипт, мертво и **не свидетельствует ничего**.  Смерть
и молчание — разные вещи: **живое** место, не называющее состояние, свидетельствует
ячейку **слабо**, и это измерение, а не отказ.

**Находка F10 — имя считали вызовом.**  `(function f)` и `'f` — имена, а не вызовы;
определение, достигаемое только именем, мертво для рантайма.  Имя в первом аргументе
`funcall` и `apply` — **вызов**: рантайм зовёт значение там.

**Находка F11 — состояние читалось только из прямого стража.**  Состояние теперь
берётся и из **цепочки предыдущих ходов** в той же ветви (у каждой метки единственный
`TO`), и состояние, **связанное локальной переменной**, читается тоже.

**Находка F13 — веер судился при неполном покрытии.**  Обвинить рантайм в сужении
веера можно только тогда, когда покрытие веера **прочитано целиком**; иначе
проверка, не прочитавшая состояние, обвиняла в сужении, которого не видела.
Покрытие веера `interrupt` рантайм **не заявляет**, и проверка называет этот веер
как не заявленный, а не обвиняет рантайм.

**Находка F14 — отчёт не называл чисел.**  Теперь отчёт печатает: сколько мест
называют состояние и сколько не называют, сколько меток не имеют места с названным
состоянием, сколько вееров имеют **полное** покрытие, и перечисляет все списки
поимённо — с файлом и строкой.

**Claim:** `every-transition-of-the-table-is-taken` — **amended, not rewritten**: id
прежний; текст говорит, что свидетель ячейки — **живое** место, что состояние
читается из стража и из цепочки ходов, что место без названного состояния **названо**
проверкой, и что веер судится только при полном заявленном покрытии — веер
`interrupt`, покрытие которого рантайм не заявляет, назван в обещании;
`falsifier` переписан под новые отказы; `control` прежний.

**Доказательство (контроли, все на копии дерева, 2026-11-20).**  Девять контролей
сделаны писателем волны, **шесть — родителем, независимо от отчёта писателя**.  Все
пятнадцать дали запрошенный вердикт.

| Контроль | Что сделано | Что сказала проверка |
|---|---|---|
| Честный код | ничего | код 0, 3 с |
| Ход, которого нет в машине | `budget-ok` → `tool-end` (`lib/yeah-turn.el:880`) | «the runtime takes 3 move(s) the machine does not have», код 1 |
| Место, достигаемое только именем (F10) | тик `nudge` перенесён в определение, названное лишь `defconst` | «1 cell(s) the runtime does not take: ((post-decide nudge . deciding) …)», код 1 |
| Состояние через локальную переменную (F11) | страж переписан через `let` | тот же отказ и «the place stands in a state the machine has no move from», код 1 |
| Веер сужен (F13) | веер `error` сужен | «(error :the-runtime-narrows-the-fan (idle))», код 1 |
| Мёртвое место | тик `nudge` в определение, которое зовёт только имя | «1 cell(s) the runtime does not take: ((post-decide nudge . deciding) …)», код 1 |
| Падение — вердикт | исключение внутри проверки | «the check could not read the kernel: Wrong type argument: listp, 1», код 1 |
| Регресс D6 | чтение состояния возвращено к `(cdr (cdr form)` | код 0, **но доказательство пустеет**: 25 слабых ячеек вместо 15 |
| Отчёт с числами | — | код 0, числа и поимённые списки на месте |
| Контроль claim'а | `sed` меняет **две** ячейки таблицы | код 1, три находки |

**Родитель нашёл ложно-зелёную точку посреди работы и назвал причину.**  Контроль
«тик `nudge` в месте, мёртвом для рантайма» проходил зелёным: причина была не в
правиле свидетеля, а в **вакуумности самой проверки ячеек** — вердикт стоял внутри
цикла по местам, и мёртвое место, не называющее состояние, засчитывалось как слабый
свидетель.  Писатель починил **правило свидетеля**, а не симптом.

**Измерение волны.**  Проверка — 1102 строки и 51.4 kB, идёт 2.96 с.  Ячеек — 31,
меток — 17, состояний — 11.  Мест тика в ядре — 23, и все 23 живые для рантайма.
**14 из 23** мест называют состояние прогона, **9 не называют**; **8 из 17** меток не
имеют места с названным состоянием; **15 из 31** ячеек опираются на место, не
называющее состояние; **16 из 31** ячеек доказаны состоянием места.  Покрытие
заявлено полностью у **1 из 2** вееров; у `interrupt` — нет, и проверка говорит
какой.  Юнит-тесты таблицы — 23/23.

**Чего волна не делает.**

1. Она не делает 9 мест называющими состояние — это может сделать только рантайм.
2. Она не судит веер, покрытие которого рантайм не заявил: такой веер **назван**, а не
   обвинён.
3. Живость статична: определение, достигаемое только через вычисленное значение,
   мертво для проверки.
4. Состояние, вычисленное рантаймом вызовом функции, не читается — такое место не
   называет состояние.
5. Она не доказывает достижимость **в рантайме**: проверка доказывает достижимость
   от корня.

### 16.79 Доказательство схемы меряет пайплайн и концы каждой стрелки — **сделано 2026-11-20 (волна 87)**

**Что это за волна.**  Вторая починка доказательства трека D (волна D1).
Дискриминатор пакета волн 84–86 нашёл две находки, касающиеся доказательства схемы
(F18, F21).  **Код ядра и пайплайна волна 87 не трогает** — чинится доказательство, тем
же файлом `tests/checks/check-the-state-diagram-comes-from-the-code.sh` (было 397 строк,
стало 607).

**Находка F18 — пайплайн проглатывал упавшую генерацию.**  Проверка гоняла в дереве
без ядра только **подкоманду** `scripts/dev state-diagram` и ждала кода 3; **пайплайн**
`scripts/dev diagrams` там не гонял никто.  Мутация, делающая вызов генератора в
пайплайне условным, давала код **0** и рисовала картинки — обе проверки (84 и 86) были
зелёными.  Две разные точки вызова: `scripts/dev:398` (пайплайн) и `scripts/dev:487`
(подкоманда); мутация трогала первую.  Теперь гоняется **сам пайплайн** в дереве без
`lib/yeah-state-diagram.el`, и требуются код **3** и **ноль нарисованных картинок**
(считаются все `*.svg` дерева).  Три ответа названы по-разному: «ответил и это не 3»,
«ответил 3 и нарисовал», «нарисовал, хотя генерация упала».

**Находка F21 — проверка падала не тем предметом.**  Сверка ячеек с стрелками была
сверкой **чисел** и одной добавленной ячейки, поэтому генератор, который читает таблицу,
но ведёт каждую ячейку не туда, проходил; а при падении проверка говорила ложное:
«the generator does not read the table» — стрелка была, просто с чужими концами.  Теперь
**каждая** ячейка сверяется со своей стрелкой по концам (`from --> to : label`),
идентификатор состояния вычисляет **сама проверка** (PlantUML не читает дефис в
идентификаторе: `post-decide` → `post_decide`), и три случая названы по-разному:
ячейки нет в схеме (генератор не читает таблицу), ячейка нарисована в другом месте
(генератор читает таблицу, но ведёт ячейку не туда), метка стрелки не та.  Сторож: если
сравнение не отработало — это падение («nothing was compared»), а не тихий успех.

**Claim:** `the-state-diagram-comes-from-the-code` — **amended, not rewritten**: id
прежний; текст говорит, что каждая ячейка — стрелка схемы **со своими концами** и что
пайплайн в дереве без ядра отвечает кодом 3 и не рисует ничего; `falsifier` переписан
под новые отказы; `control` прежний.

**Доказательство (контроли, все на копии дерева, 2026-11-20).**  Десять контролей
сделаны писателем волны, **пять — родителем, независимо от отчёта писателя**.  Все
пятнадцать дали запрошенный вердикт.

| Контроль | Что сделано | Что сказала проверка |
|---|---|---|
| Честный код | ничего | код 0, 3.9 с |
| Пайплайн глотает генерацию (F18) | вызов в пайплайне сделан условным | «the pipeline of the diagrams answered 0 in a tree without a kernel and the answer must be 3», «drew 2 picture(s) … although the generation failed (the answer was 0)», код 1 |
| То же, другая форма (F18) | `( generate_state_diagram ) \|\| true` | те же два текста, код 1 |
| Генератор ведёт ячейку не туда (F21) | цель стрелки у следующей ячейки, схема перегенерирована | «the generator reads the table but leads the cell elsewhere: the cell (idle user-prompt deciding) is drawn as (idle --> post_decide : user-prompt)» — слов «does not read the table» в ответе **нет**, код 1 |
| Контроль claim'а | `sed` меняет ячейку таблицы | «the diagram of the repository is not the diagram that the code writes: the table of the transitions changed and the diagram was not written again», код 1 |

**Измерение волны.**  Ячеек таблицы — 31, стрелок схемы — 31 (и `[*] --> idle`, не
ячейка), состояний — 11.  Все числа читаются из кода, ни одно не вписано в проверку.
Сверка идёт дважды: 31 ячейка дерева репозитория и 32 ячейки копии с добавленной.

**Чего волна не делает.**

1. Она не смотрит на картинки сайта — это волны D3 и D4.
2. Правило идентификатора PlantUML написано **дважды** — в генераторе и в проверке —
   намеренно, чтобы изменение правила генератором было замечено; плата — дублирование.
3. Пайплайн меряется в случае «нет ядра» (ответ 3); другой провал генерации (ответ 1)
   в пайплайне не меряется.
4. Порядок стрелок не обещан и не меряется: сверка идёт по содержанию, и перестановка
   стрелок проверку не роняет.

### 16.80 Место, которое рантайм не выполняет, не свидетельствует ничего — **сделано 2026-11-20 (волна 88)**

**Что это за волна.**  Третья починка доказательства трека A (волна A3).
Дискриминатор пакета волн 84–86 нашёл две находки, касающиеся доказательства таблицы
(F19, F20).  **Код ядра волна 88 не трогает** — чинится доказательство, тем же файлом
`tests/checks/check-every-transition-of-the-table-is-taken.el` (было 1102 строки и
51 445 байт, стало 1279 строк и 61 282 байта).

**Находка F19 — место без определения считалось живым.**  Обход верхнеуровневых форм
`lib/` даёт такому месту имя `nil`, а правило живости читала имя `nil` как «место,
которое рантайм выполняет».  Тик внутри лямбды `defconst`, которую никто не зовёт, —
не ход рантайма, но он засчитывался свидетелем ячейки `(post-decide nudge . deciding)`,
а рантайм этот ход не берёт вообще.  Теперь такое место **мёртвое** для рантайма,
отчёт называет эти места **отдельным классом** («вне определения ядра», «в определении,
которое рантайм не выполняет»), а ячейка, чьё единственное место — такое, называется
вместе с местами, берущими её метку.

**Находка F20 — место с непрочитываемой меткой выпадало из всех вердиктов.**  Оно не
свидетельствовало ни одной ячейке, не сверялось ни с одним состоянием и **ломало
цепочку ходов соседей**: веер `error` терял полное покрытие и переставал судиться, —
рантайм брал ход `no-such-move`, которого в машине нет, а проверка отвечала кодом **0**,
и отчёт молча говорил меньше, чем раньше.  Теперь такое место — **дефект сам по себе**:
проверка называет его по файлу и строке («the runtime takes 1 move(s) the check cannot
read») и отвечает кодом 1.

**Отчёт сверяется с числами, которые измерены прежде.**  Измерение, которое стало
меньше, не проходит как то же самое: доказательство, которое опирается на меньшее, —
слабее, и проверка говорит об этом вместо молчания («the check measured the table
differently than it measured it before»).

**Claim:** `every-transition-of-the-table-is-taken` — **amended, not rewritten**: id
прежний; текст говорит, что живое место — это место определения, которое рантайм
выполняет, и что место, метку которого прочитать нельзя, — дефект сам по себе;
`falsifier` переписан под новые отказы; `control` прежний.

**Доказательство (контроли, все на копии дерева, 2026-11-20).**  Девять контролей
сделаны писателем волны, **четыре — родителем, независимо от отчёта писателя**.  Все
тринадцать дали запрошенный вердикт.

| Контроль | Что сделано | Что сказала проверка |
|---|---|---|
| Честный код | ничего | код 0, 2.9 с, все числа как прежде |
| Тик в лямбде константы (F19) | тик `nudge` перенесён в `defconst`, который никто не зовёт | «the table of the machine names 1 cell(s) the runtime does not take: (((post-decide nudge . deciding) … :the-places-that-take-the-label ((nil (nudge) \"lib/yeah-turn.el:1481\"))))» и «measured differently … (:places-without-a-definition :expected 0 :measured 1)», код 1 |
| Метка не читается (F20) | `(yeah-turn--tick turn (symbol-name \"no-such-move\"))` | «the runtime takes 1 move(s) the check cannot read» с файлом и строкой, код 1 |
| Контроль claim'а | две `sed` — таблица и страж | четыре находки проверки, код 1 |

**Измерение волны (пересчитано писателем и родителем).**  Ячеек — 31, меток — 17,
состояний — 11.  Мест тика — 23, все живые; мест **вне определения** — **0**, мест **в
мёртвом определении** — **0**.  **14 из 23** мест называют состояние, **9 не называют**;
**8 из 17** меток без места с названным состоянием; **15 из 31** ячеек опираются на
место, не называющее состояние.  Вееров — 2: у `error` покрытие заявлено полностью, у
`interrupt` — нет.

**Чего волна не делает.**

1. **Числа отчёта прибиты к ядру от 2026-11-20.**  Число меняется, когда ядро меняют
   нарочно, и константа меняется тогда, а не раньше; плата за «деградация замера не
   проходит молча» — волна, меняющая `lib/`, обязана поменять и константу проверки,
   и до тех пор проверка говорит «measured differently».
2. Тик, взятый через `funcall`/`apply`, местом не считается: такое место невидимо, и
   проверка даёт **ложный отказ** («рантайм не берёт ход»), а не ложную зелень.
3. Живость статична: место в живой определении, которое рантайм фактически не
   выполняет, считается живым.

### 16.81 Цепочка поиска ловится по поведению, а обещание говорит, что меряется — **сделано 2026-11-20 (волна 89)**

**Что это за волна.**  Третья починка доказательства трека D (волна D0).
Дискриминатор пакета волн 84–86 нашёл одну находку (F22): **класс побега был назван
ещё в objection волны 86**, но **текст claim'а и его falsifier были сильнее доказательства**.
**Код пайплайна волна 89 не трогает** — чинится доказательство, тем же файлом
`tests/checks/check-the-diagram-pipeline-renders-both-themes.sh` (было 940 строк и
36 910 байт, стало 1015 строк и 40 561 байт).

**Находка F22 — цепочка доказывалась по написанию.**  Проба искала **дословную** копию
тела цепочки в других скриптах `scripts/` и пару шагов `command -v` + `-x …
.nix-profile/bin/` в другом файле.  Копия цепочки, **переписанная** в других словах
(свой `type -P`, свой `-f` для профиля), проходила, и пайплайн отвечал 0 там, где
должен был ответить 1.

**Что сделано.**  Проверка смотрит на **код пайплайна**: из `scripts/dev` вынимается
комментарии, тело heredoc'а (текст помощи) и вызовы `find_tool`, а в остатке запрещены
слова шагов поиска (`command -v`, `type -P`, `which`, профиль пользователя, стор Nix,
бинарник инструмента).  Найдено — «scripts/dev writes a step of the search of a tool by
itself […] — the chain of the search lives in one place (scripts/lib/tools.sh) and not
in two», код 1.  Старые текстовые пробы (строка подключения, вызов `find_tool`, одно
определение, дословная копия тела) **сохранены**.

**Обещание приведено к тому, что меряется.**  Текст claim'а теперь говорит: цепочка
живёт в одном месте **в `scripts/`**, `scripts/dev` читает её, зовёт её и **не пишет
шаг поиска сам**, другой скрипт `scripts/` не определяет цепочку и не несёт копию её
тела, **копия, переписанная в других словах, не видна**, а **поиск в самих проверках —
свой, по замыслу**: дерево несёт собственный поиск в
`tests/checks/check-the-state-diagram-comes-from-the-code.sh`, и обещание говорит об
этом прямо, а не говорит «никакой другой скрипт дерева».

**Claim:** `the-diagram-pipeline-renders-both-themes` — **amended, not rewritten**: id
прежний; текст переписан в части о цепочке; `falsifier` переписан под новый отказ;
`control` прежний.

**Доказательство (контроли, все на копии дерева, 2026-11-20).**  Семь контролей
сделаны писателем волны, **три — родителем, независимо от отчёта писателя**.  Все десять
дали запрошенный вердикт.

| Контроль | Что сделано | Что сказала проверка |
|---|---|---|
| Честный код | ничего | код 0, 26 с |
| Свой поиск в `find_plantuml` (F22) | тело функции переписано на `type -P` и `-f` | «scripts/dev writes a step of the search of a tool by itself [.nix-profile/bin NIX_STORE_DIR bin/plantuml type -P]», код 1 |
| Контроль claim'а | `for theme in light dark` → `light` | «the pipeline drew [alpha-light.svg beta-light.svg state-machine-light.svg ] and not two pictures for every diagram», код 1 |
| **Старая** проверка волны 86 на той же мутации | ничего | **код 0** — ложно-зелёное место, о котором находка |

**Чего волна не делает.**

1. Новая проба читает **слова кода**, а не трассировку рантайма: шаг, собранный на лету
   (`c=comm; $c -v plantuml`), не виден.
2. Копия цепочки в **другом скрипте `scripts/`**, которая прячет свои шаги в своём файле
   и зовётся без глоба, проходит — тот же класс побега, что назван в objection волны 86.
3. Подключение цепочки за переменной по-прежнему не узнаётся — открыто в objection
   волны 86; рантайм-пробы прикрывают это лишь отчасти.
4. Поиск, который повторяет все четыре шага цепочки, считается нарушением: проверка
   отличает его от цепочки по написанию, а не по доказательству.

### 16.82 Имя в позиции имени — не вызов, а тик в данных — не место — **сделано 2026-11-20 (волна 90)**

**Что это за волна.**  Четвёртая починка доказательства трека A (волна A3).
Дискриминатор пакета волн 87–89 нашёл одну находку (F23), и **ревью волны нашло рядом с
ней ещё три класса побега того же семейства**.  **Код ядра волна 90 не трогает** — чинится
доказательство, тем же файлом
`tests/checks/check-every-transition-of-the-table-is-taken.el` (было 1279 строк и
61 282 байта, стало 1602 строки и 78 326 байт).

**Находка F23 — имя в кавычечном списке считалось вызовом.**  Обход вызовов заходил в
операнды `quote`, и голова кавычечного списка становилась вызовом: определение, которое
называл **только** кавычечный список, становилось корнем рантайма, а ход внутри него —
ходом рантайма.  Доктрина проверки говорит обратное (имя — не вызов), а код обхода говорил
иначе.

**Три класса того же семейства, найденные рядом.**

1. **Имя в списке имён** — имена связываний `let`, переменная спека `dolist`, паттерн
   `pcase`, типы обработчиков `condition-case` — это имена, а не код: рантайм их читает и
   не выполняет.
2. **Тик в кавычечной форме** — рантайм не выполняет кавычечную форму, значит такой тик не
   свидетельствует ничего; единственный код `backquote` — раскомментированные части.
3. **Имя типа и имена слотов** — описание `cl-defstruct` есть список имён; имя
   производного режима — тоже имя.

**Что сделано.**  Обход **не заходит в данные**: операнды `quote` — имена, дизайнатор
`function` — имя, параметры `lambda` — имена, тело `lambda` — код (где бы оно ни стояло,
в том числе под `function`).  Список имён — имена: значения связываний, коллекция спека,
предмет `pcase`, тела клауз и обработчиков — код, и обход в них заходит.  Имя типа, имена
опций и имена слотов `cl-defstruct` — имена, значение слота — код; устаревший `defstruct`
читается так же.  Имя режима и имя его родителя — имена, значение ключевого слова — код,
тело режима — код.  Первый аргумент `funcall`/`apply` **остаётся вызовом** (рантайм зовёт
значение там).

**Обещание приведено к тому, что меряется.**  Текст claim'а теперь говорит: обход читает
имя как имя, а не как вызов, и тик в данных — не место рантайма.

**Claim:** `every-transition-of-the-table-is-taken` — **amended, not rewritten**: id прежний;
текст дополнен частью об именах и данных; `falsifier` дополнен двумя новыми отказами;
`control` прежний.

**Доказательство (контроли, все на копии дерева, 2026-11-20).**  Три контроля сделаны
писателем волны, **девять — родителем, независимо от отчёта писателя**.  Все двенадцать
дали запрошенный вердикт.

| Контроль | Что сделано | Что сказала проверка | Код |
|---|---|---|---|
| Честное дерево | ничего | 23 места, 23 живых, 14 называют состояние, 9 нет, 15 ячеек на безгласном месте | 0 |
| F23: тик спрятан в определение, названное **только** в кавычечном списке | тик `nudge` убран из живой функции | «the table of the machine names 1 cell(s) the runtime does not take: ((post-decide nudge . deciding) …)» | 1 |
| Регрессия: тот же помощник, но его **зовут** | вызов по имени | тихо | 0 |
| Регрессия: `funcall` с кавычечным именем | `(funcall 'name turn)` | тихо (первый аргумент `funcall` — вызов по доктрине) | 0 |
| Имя только в связываниях `let` | имя в списке связываний | «…does not take…» | 1 |
| Контроль claim'а | таблица и страж изменены | «…» | 1 |
| **Тик в кавычечной форме в живой функции** (родитель) | `(setq x '(yeah-turn--tick turn 'nudge))` | тихо, числа прежние (23/23) | 0 |
| **Имя типа в `cl-defstruct`** (родитель) | структура называет имя, которое никто не зовёт | «…»: `:places-of-a-dead-definition :expected 0 :measured 1` | 1 |
| **Имя режима в `define-derived-mode`** (родитель) | то же | то же | 1 |

**Чего волна не делает.**

1. Обход читает **позиции, которые он знает**, а позиция, которую он не знает, читается
   как вызов.  Сегодня таких позиций в ядре нет, и они названы в файле проверки: ключи
   клауз `case` — данные, имена связываний `destructuring-bind` и `multiple-value-bind` —
   имена, спецификатор `cl-defmethod` — данные, строка документации `cl-defgeneric` —
   данные.  Ядро, которое заведёт такую позицию, заставит обход её выучить.
2. Первый аргумент `funcall`/`apply` — вызов **по доктрине проверки**, а не по коду
   рантайма: вызов, собранный на лету (`(funcall (intern name))`), не виден.
3. Числа отчёта прибиты к ядру от 2026-11-20: волна, меняющая `lib/`, обязана поменять и
   константу проверки.

### 16.83 Цепочка поиска доказывается поведением пайплайна, а не его написанием — **сделано 2026-11-20 (волна 91)**

**Что это за волна.**  Четвёртая починка доказательства трека D (волна D0).
Дискриминатор пакета волн 87–89 нашёл две находки (F24, F25): и обе — про то, что
доказательство было слабее обещания. **Код пайплайна волна 91 не трогает** — чинится
доказательство, тем же файлом
`tests/checks/check-the-diagram-pipeline-renders-both-themes.sh` (было 1015 строк и
40 561 байт, стало 1165 строк и 47 941 байт).

**Находка F24 — «цепочка в одном месте» проверялась словарём.**  Проба искала пять групп
слов (команда на PATH, тип шелла, бинарник пользователя в профиле, стор Nix, бинарник
инструмента).  Шаг поиска, написанный другими словами, не был виден.

**Находка F25 — две пробы «копии цепочки» были литеральными.**  Голова цепочки читалась
как `find_tool()` без пробела (`find_tool ()` — та же функция), а пара шагов профиля — как
`-x … .nix-profile/bin/` с обоими маркерами на одной строке.  Полная вторая цепочка,
перекрывающая общую, проходила.

**Что сделано.**  (1) Голова цепочки читается с пробелом и без пробела; определение
цепочки ищется во всех файлах `scripts/`.  (2) Шаги ищутся по **всему** файлу, а не по
одной строке, и по **коду** файла (комментарии и тела heredoc'ов вырезаны).  (3) **Главное
— новая поведенческая проба (деко):** копия дерева, у которой цепочка выдаёт подставной
инструмент — PlantUML, пишущий картинку со своей меткой, и Emacs, пишущий метку и зовущий
Emacs машины.  Пайплайн рисует в этой копии: пайплайн, берущий инструмент **из цепочки**,
рисует картинки дека, а пайплайн, ищущий инструмент **сам**, рисует картинки машины и не
оставляет метки никакой.  Проверка требует метку в каждой картинке копии и метку Emacs'а
цепочки; если дек не встал в цепочку, проверка говорит, что измерить не может, и не
притворяется.

**Обещание приведено к тому, что меряется.**  Текст claim'а теперь говорит: цепочка
доказывается **поведением** пайплайна (копия дерева с деком), а словарные пробы — дополнение.

**Claim:** `the-diagram-pipeline-renders-both-themes` — **amended, not rewritten**: id
прежний; текст дополнен частью о поведенческой пробе; `falsifier` дополнен новым отказом
(«пайплайн берёт инструмент не из цепочки»); `control` прежний.

**Доказательство (контроли, все на копии дерева, 2026-11-20).**  Пять контролей сделаны
писателем волны, **четыре — родителем, независимо от отчёта писателя**.  Все девять дали
запрошенный вердикт.

| Контроль | Что сделано | Что сказала проверка | Код |
|---|---|---|---|
| Честное дерево | ничего | тихо | 0, 24–26 с |
| Вторая цепочка, перекрывающая общую (F25) | голова с пробелом, шаг профиля разбит на две строки, подключение **после** `tools.sh` | «the chain of the search is defined in […] and not in one place» | 1 |
| Своя цепочка в другом скрипте `scripts/` (F24) | свой скрипт `plantuml.sh` в каталоге `scripts/lib/` + подключение | «the steps of the chain of the search are in scripts/lib/plantuml.sh» | 1 |
| **Свой поиск PlantUML в `scripts/dev`** (родитель) | обход `$PATH` своими словами, словарь его не видит | «the pipeline answered 3 in the tree where the chain of the search hands out the decoy of the instrument: the pipeline does not take the instrument from the chain» | 1 |
| Мутация, которую **старая** проверка не видит (родитель) | вторая цепочка: голова с пробелом и `type -p` вместо `command -v` | **старая** проверка волны 89 — **код 0**, новая — «the chain of the search is defined in [scripts/lib/plantuml.sh scripts/lib/tools.sh ]» | 0 / 1 |
| Контроль claim'а | `for theme in light dark` → `light` | «the pipeline drew […] and not two pictures for every diagram» | 1 |

**Чего волна не делает.**

1. Дек доказывает, что **пайплайн этой копии** берёт инструмент из цепочки: часть
   пайплайна, которая ищет инструмент сама, видна, а часть, которая ищет сама и рисует
   картинку, которой в копии нет, — нет.
2. Проба читает **слова кода**, а не трассировку рантайма: шаг, собранный на лету
   (`c=comm; $c -v plantuml`), не виден.
3. Дек стоит прогона пайплайна: проверка стала длиннее и медленнее (47.9 kB, 24–26 с).
4. Копия цепочки в **другом скрипте `scripts/`**, которая прячет свои шаги и не затеняет
   цепочку, по-прежнему не видна текстовыми пробами; обещание claim'а теперь говорит, что
   цепочка доказывается поведением, а текстовые пробы — дополнение.

### 16.84 Дубликат ячейки назван дубликатом, а не отсутствующей ячейкой — **сделано 2026-11-20 (волна 92)**

**Что это за волна.**  Третья починка доказательства трека D (волна D1).
Дискриминатор пакета волн 87–89 нашёл одну находку (F26).  **Код ядра и генератора волна
92 не трогает** — чинится доказательство, тем же файлом
`tests/checks/check-the-state-diagram-comes-from-the-code.sh` (+180 строк, −25).

**Находка F26 — сверка объявляла дубликат ячейки «absent».**  Таблица машины называла одну
ячейку дважды, схема несла одну стрелку на две ячейки, и сверка сваливалась в
`report_absent` — проверка отвечала ложным предметом «the generator does not read the
table», хотя генератор таблицу читал, а таблица говорила одно и то же про одно событие
дважды.  Ложный отказ с ложным предметом хуже отсутствия отказа: он отправляет читателя
к генератору, а дефект в таблице.

**Что сделано.**  Сверка считает: сколько раз таблица называет ту же ячейку (`c_same`),
сколько стрелок схема несёт для неё (`c_arrows`), сколько раз схема повторяет стрелку
(`a_same`).  У дефекта появились **свои предметы**: `twice` (таблица называет одну ячейку
больше одного раза, а схема несёт для неё меньше стрелок, чем таблица называет ячеек) и
`twice-arrow` (схема несёт одну стрелку больше одного раза, а у ячейки таблицы своей
стрелки нет).  Предметы волны 87 (`absent`, `leads`, `label`) остались там, где они
истинны.  **[Правка 2026-11-21, волна 95:]** эти имена после волны 95 не те: `leads` стал
`label`, а `label` стал `wrong-label` — случаи те же, слова другие.  Слова сообщений собраны в одном месте (`problem_message`), а сверка умеет
**читаться**, а не только судить (режим `print`) — это нужно самому контролю волны.
**Проверка доказывает это на себе:** копия ядра, в таблице которой одна ячейка названа
дважды, сверяется с диаграммой репозитория (диаграмма репозитория — нарочно: контроль
читает сверку, а не здоровье генератора), и сверка обязана назвать дубликат и не должна
назвать ячейку отсутствующей.

**Claim:** `the-state-diagram-comes-from-the-code` — **amended, not rewritten**: id
прежний; текст дополнен фразой «ячейка, которую таблица называет дважды, называется
дубликатом, а не отсутствующей ячейкой»; `falsifier` дополнен новым отказом; `control`
прежний.

**Доказательство (контроли, все на копии дерева, 2026-11-20).**  Семь контролей сделаны
писателем волны, **пять — родителем, независимо от отчёта писателя**.  Все двенадцать дали
запрошенный вердикт.

| Контроль | Что сделано | Что сказала проверка | Код |
|---|---|---|---|
| Честное дерево | ничего | тихо | 0, 3.3 с |
| **Юнит-контроль сверки** (родитель) | файл ячеек с двумя одинаковыми ячейками + схема с одной стрелкой | было `count 1 2` + `absent idle user-prompt deciding`; стало `count 1 2` + `twice idle user-prompt deciding 2 1` | — |
| **Старая сверка внутри новой проверки** (родитель) | программа сверки волны 87 вместо новой | «the comparison of the cells does not tell a duplicate from an absent cell» и «…calls the cell … an absent cell» | 1 |
| Сторож самой проверки (писатель) | ветка `report_twice` возвращена к `report_absent` | те же два отказа | 1 |
| Контроль claim'а | таблица изменена, схема не перегенерирована | «the diagram of the repository is not the diagram that the code writes» | 1 |
| F21 волны 87 (родитель) | генератор ведёт ячейку не туда | «the generator reads the table but leads the cell elsewhere» — **не** «does not read the table» | 1 |
| Дубликат в таблице (писатель) | юнит-тест машины на таблице с дубликатом | `FAILED yeah-loop-no-label-is-declared-twice-for-one-state` | 1 |

**Чего волна не делает.**

1. **Проверка схемы не запрещает сам дубликат в таблице.**  Таблица, которая называет
   ячейку дважды, и схема, которая несёт эту стрелку дважды, здесь зелёные: генератор
   рисует по одной стрелке на ячейку, и такая схема — верная отрисовка такой таблицы.
   Дубликат запрещён там, где он и есть: у машины есть своя юнит-проверка
   (`yeah-loop-no-label-is-declared-twice-for-one-state`), а рантайм берёт первое
   совпадение, так что вторая строка — мёртвый груз.  Волна говорит, где класс закрыт, и не
   притворяется, что закрывает его дважды.
2. Новый предмет — новая вещь для чтения: когда схема повторяет стрелку, ячейка, которой
   в схеме нет, называется `twice-arrow`, а не «генератор не читает таблицу»; сообщение
   истинно в обеих половинах, но читателю надо посмотреть и на повторённую стрелку.
3. Сверка идёт по содержанию, а не по порядку: порядок стрелок не измеряется
   (возражение (c) волны 87).  Возражения (a) и (b) волны 87 (правило идентификатора
   PlantUML написано дважды; пайплайн в дереве без ядра меряется только в случае «нет
   ядра») тоже остаются.

### 16.85 Обход знает позиции каждой формы, а неизвестная форма — дефект сам по себе — **сделано 2026-11-21 (волна 93)**

**Что это за волна.**  Пятая починка доказательства трека A (волна A3).  Дискриминатор пакета
волн 87–89 нашёл находку **F27** (высокая), а ревью волны 90 нашло рядом с ней ещё классы
того же семейства.  **Код ядра волна 93 не трогает** — чинится доказательство, тем же файлом
`tests/checks/check-every-transition-of-the-table-is-taken.el` (1602→2364 строки,
78 326→115 617 байт, +877/−115).

**Находка F27 — обход читал имя в позиции данных как вызов, и класс «имя в позиции, где
стоит имя» не был закрыт.**  Объявление волны 90 (objection (a)) говорило: «the kernel
holds no such position today» — и это было **неверно**: ядро держит 55 `when-let`/`if-let`/
`*when-let` и 3 `cl-labels`, которых нет в закрытом списке из пяти позиций.  Побег был
**ложно-зелёным**: на дереве, где рантайм больше **не берёт** ход `idle --user-prompt-->
deciding`, проверка отвечала **0**.  Тот же отчёт назвал две позиции из пяти неверно: у
`cl-defmethod` читается как вызов **имя переменной** спецификатора, а не «спецификатор», у
`cl-defgeneric` — **имена аргументов**, а не «doc string»; и проба писателя на 39 случаях,
на которую ссылалась note волны 90, **в репозитории отсутствовала** — её нельзя было
перезапустить.

**Что сделано.**

1. **Обход знает позиции каждой формы, которую встречает.**  Таблица
   `yeah-check--positions-of-the-known-forms` — **74 записи, 20 видов позиций**.  Спецформы
   Emacs (**22**) читаются **из самого Emacs** (`special-form-p`), макросы ядра (**3**:
   `yeah-session-with`, `yeah-tools-with-registry`, `yeah-todo-with-session`) — **из файлов
   ядра**, а формы, встреченные обходом (**55**), — **из самого обхода**.  Таблица
   **измеряется** против ядра, а не утверждается: три проверки
   (`every-special-form-of-emacs-is-known`, `every-macro-of-the-kernel-is-known`,
   `every-form-the-walk-met-is-known`) требуют, чтобы каждая форма, которую встречает
   обход, была в таблице.
2. **Неизвестная макрос или спецформа — дефект сам по себе.**  Проверка называет её **по
   файлу и строке** и отвечает кодом 1 (образец волны 88): «the table of the positions does
   not know 1 macro(s) of the kernel: ((:the-table-does-not-know-this-macro :macro
   yeah-turn--unknown-form-of-the-walk :at "lib/yeah-turn.el:1480"))».
3. **Локальная функция, которую никто не зовёт, — мёртвый код.**  Обход входит в тело
   локальной функции (`cl-labels`, `cl-flet`) только если её имя **стоит в коде формы**:
   вызов, вызов из соседней локальной функции или имя как значение, которое рантайм зовёт.
   Имя, которое не стоит нигде, — имя функции, которую рантайм никогда не зовёт, и её тело
   — не место рантайма.
4. **Имя в данных — данные.**  Правило локальных функций спрашивает ровно тот же вопрос,
   что и глобальный обход: **зовёт ли рантайм это имя?**  Кодовая позиция — вызов; значение,
   которое рантайм зовёт (`funcall`, `apply`, `#'`) — вызов; имя в цитате, которое никто не
   зовёт, — данные.

**Проба в дереве.**  `yeah-check--probe-cases` (**49 случаев**) и `yeah-check--probe-tick-cases`
(**12 форм**) держат обход с обеих сторон правила: тик в теле локальной функции, которую
рантайм зовёт, — место; тик в теле локальной функции, которую никто не зовёт, — не место;
имя в цитате — данные; `funcall` и десигнатор — вызов.

**Числа ожидания не тронуты и не подогнаны.**  31 ячейка, 17 меток, 11 состояний; 23 места,
23 живых, 14 называют состояние, 9 не называют, 15 ячеек на глухом месте, 2 фана; живых
определений **558**.  Измерение совпадает с измерением на `main` от 2026-11-20.

**Claim:** `every-transition-of-the-table-is-taken` — **amended, not rewritten**: id прежний;
текст дополнен правилом (обход знает позиции каждой формы, а форма, которую он не знает, —
дефект сам по себе; локальная функция, которую никто не зовёт, — мёртвый код; имя в данных
— данные); `falsifier` дополнен новыми отказами; `control` прежний.

**Доказательство (контроли, все на копии дерева, 2026-11-21).**  Пять контролей сделаны
писателем волны, **девять — родителем, независимо от отчёта писателя**.  Все дали
запрошенный вердикт.

| Контроль | Что сделано | Что сказала проверка | Код |
|---|---|---|---|
| Честное дерево | ничего | тихо; числа прежние (23/23, 14/9, 15, 2) | 0 |
| **C93b — побег `when-let`** (родитель) | живой тик перенесён в определение, которое никто не зовёт; имя — в позицию `when-let` | «the table of the machine names 1 cell(s) the runtime does not take» | 1 |
| **C93c — контроль к C93b** (родитель) | та же мутация, но позиция имени = `nil` | то же | 1 |
| **C93d — побег `cl-labels`** (родитель) | локальная функция, которую никто не зовёт | то же | 1 |
| **C93e — побег `destructuring-bind`** (родитель) | имя в списке имён | то же | 1 |
| **C93f — побег `cl-defgeneric`** (родитель) | имя в строке документации | то же | 1 |
| **C93g — неизвестная макрос в ядре** (родитель) | макрос, которой обход не знает | «the table of the positions does not know 1 macro(s) of the kernel» | 1 |
| **C93h — контроль claim'а** (родитель) | таблица и место изменены | «the table of the machine names 1 cell(s) the runtime does not take» | 1 |
| **C93i — имя в цитате** (родитель) | локальная функция, имя которой стоит только в цитате | то же | 1 (**до починки — 0**, ложно-зелёный) |

**Чего волна не делает.**

1. **Асимметрия, которую волна не трогает.**  Глобальный обход читает десигнатор `#'foo` как
   имя (значит, глобальное определение, достижимое только через `#'`, мертво), а локальное
   правило считает `#'witness` вызовом.  Это **консервативная сторона** (ложных отказов не
   даёт), и глобальная семантика не менялась — потому числа ожидания и не сдвинулись.
2. **Имя, вычисленное в рантайме.**  Локальная функция, чьё имя вычисляется
   (`(funcall (intern "witness"))`), читается как незваная — ложный отказ в этом углу.  В
   ядре 3 `cl-labels`, и все три зовутся по имени.
3. **Правило относится к `cl-labels`/`cl-flet`.**  Другие области (значения функций в
   `pcase-let*`, тела `cl-defmethod`) живут по-старому.
4. **Проба на 39 случаев, на которую ссылалась волна 90, не возникает заново.**  Проба волны
   93 лежит в дереве (`yeah-check--probe-cases`, `yeah-check--probe-tick-cases`) и её можно
   перезапустить.

### 16.86 Дек инструмента видит копию цепочки, которая разрешается в его окружении — **сделано 2026-11-21 (волна 94)**

**Что это за волна.**  Вторая починка доказательства трека D (волна D0).  Дискриминатор пакета
волн 90–92 нашёл одну находку, которая касается этого доказательства (F28).  **Код пайплайна
волна 94 не трогает** — чинится доказательство, тем же файлом
`tests/checks/check-the-diagram-pipeline-renders-both-themes.sh` (1165→1341 строку,
47 941→56 997 байт, +225/−49).

**Находка F28 — дек был слеп к копии цепочки, разрешающей инструмент по профилю.**  Дек-запуск
жил в герметичном окружении (домашний каталог пуст, стор Nix пуст), поэтому разрешались только
шаг переменной окружения и шаг `PATH`; копия цепочки, которая ищет инструмент в профиле
пользователя, молча откатывалась на цепочку репозитория, пайплайн брал инструмент из этой
копии, а проверка отвечала 0 — доказательство, зелёное на дереве, чей пайплайн делает не то,
что говорит claim.

**Что сделано.**  Дек-запуск получил **живое окружение**: домашний каталог с профилем, стор Nix
со стором, `PLANTUML` и `EMACS`, `PATH` — так что разрешаются все четыре шага цепочки поиска
(переменная окружения, команда на `PATH`, бинарь профиля пользователя, глоб стора), и
разрешаются они все на инструмент машины, а не на дек; цепочка копии — единственное, что
выдаёт дек.  Пофайловая текстовая проба теперь отказывает на **любом** шаге поиска в **любом**
файле `scripts/` — прежде она требовала **пару** шагов (PATH и профиль), и копия волны F28,
которая использовала только шаг профиля, проходила.  **[Правка 2026-11-21, дискриминатор волн
94–95:]** читать все файлы `scripts/` пофайловая проба умела и раньше — с волны 91; изменилось
не то, что она читает, а то, что она ищет.  Проба «второй цепочки» (функция с двумя и более
видами шагов под любым именем) **дублирующая**: два вида включают хотя бы один, а
пофайловая проба его уже видит, — поэтому проба второй цепочки не может сработать одна и
добавляет не достижение, а вторую строку отказа о том же дефекте.  Требование метки стало
функцией `decoy_marked_picture`, которая обязана уметь падать и **считает, сколько раз её
спрашивали**: требование, о котором никогда не спросили, теперь замечено, а не молча
выполнено.

**Claim:** `the-diagram-pipeline-renders-both-themes` — **amended, not rewritten**: id прежний;
текст дополнен границей пробы («дек видит копию, которая разрешает инструмент в окружении
дека, и не видит копию, которая разрешает инструмент в месте, которого в окружении дека
нет»); `falsifier` дополнен новым отказом — про дек в окружении, где копия не может разрешить
инструмент; `control` прежний.

**Доказательство (контроли, все на копии дерева, 2026-11-21).**  Восемь контролей сделаны
**родителем, независимо от отчёта писателя**, и прогнаны **дважды** — на смешанном HEAD и на
финальном, — с одинаковым результатом: 0 провалов.

| Контроль | Что сделано | Что сказала проверка | Код |
|---|---|---|---|
| Честное дерево (C94a) | ничего | тихо | 0 |
| Копия цепочки с шагом окружения (C94b) | копия спрашивается раньше цепочки репозитория | «the pictures of the tree of the decoy do not carry the mark of the decoy» + «the pipeline writes a step of the search of a tool by itself» | 1 |
| **F28 (C94c)** | копия цепочки с шагом профиля, спрошенная первой | то же | 1 |
| Копия с шагом стора (C94d) | то же, шаг глоба стора | то же | 1 |
| **Замаскированная копия (C94e)** | имя профиля собрано на лету — текстовые пробы молчат | дек поймал копию один | 1 |
| **Копия, что не разрешается (C94f)** | копия ищет инструмент в месте, которого в окружении дека нет | тихо — граница пробы названа правдиво | 0 |
| Контроль claim'а (C94g) | картинка темы удалена | «the pipeline drew […] and not two pictures for every diagram» | 1 |
| Требование не спрашивается (C94h) | требование метки никогда не спрашивается | «the requirement of the mark of the decoy was asked about 0 pictures» | 1 |

**Чего волна не делает.**

1. **Дек доказывает, что пайплайн *этой копии* берёт инструмент из цепочки**, а не что каждая
   часть пайплайна ищет его одинаково: часть, которая ищет инструмент сама и рисует картинку
   не из копии, деком не видна.
2. **Текстовые пробы читают код файлов `scripts/`, а не след прогона**: шаг, собранный на лету
   (`c=comm; $c -v plantuml`), ими не увиден — это названо.
3. Дек стоит прогона пайплайна, поэтому проверка медленнее: файл проверки 1341 строка и
   57.0 kB (у волны 91 было 1165 строк и 47.9 kB), прогон **около 30 секунд на этом хосте**
   (27–29 с измерено в четырёх прогонах, 37.7 с под нагрузкой) при лимите `scripts/dev` в
   120 с.  **[Правка 2026-11-21, дискриминатор волн 94–95:]** диапазон «24–26 секунд» был
   заявлен и не воспроизводится; число машинозависимое и не факт о коде.
4. **Граница поведенческой пробы — не та, что была у волны 91.**  Волна 91 назвала её словами
   «поведенческая проба видит копию только если копия затеняет цепочку», и эти слова были
   ложны: копия, которая затеняет цепочку *и разрешает* инструмент, не была видна — это
   показал дискриминатор пакета 90–92.  Формулировка волны 94: дек видит копию, которая
   разрешается в окружении дека, и не видит копию, которая разрешает инструмент в месте,
   которого в окружении дека нет.

### 16.87 Ячейка, которой схема не несёт, — отсутствующая, а не «ведёт в другое место» — **сделано 2026-11-21 (волна 95)**

**Что это за волна.**  Четвёртая починка доказательства трека D (волна D1).  Дискриминатор
пакета волн 90–92 нашёл одну находку, которая касается этого доказательства (F29).  **Код ядра
и генератора волна 95 не трогает** — чинится доказательство, тем же файлом
`tests/checks/check-the-state-diagram-comes-from-the-code.sh` (762→884 строки,
33 462→40 164 байт, +174/−52).

**Находка F29 — сверка объявляла отсутствующую ячейку «ведённой в другое место».**  Ячейка
`(post-decide nudge . deciding)` в схеме отсутствует вовсе — ни одна стрелка не несёт её
метку, — а сверка свалилась в ветку угадывания по порядку таблицы и ответила: «the generator
reads the table but leads the cell elsewhere: the cell (post-decide nudge deciding) is drawn as
(idle --> deciding : weird)».  Отказ с предметом, которого нет, отправляет читателя к
генератору, а дефект в схеме.

**Что сделано.**  Классификация сверки переписана **по содержанию**, а не по порядку: ветка
угадывания по порядку удалена, и каждый вид дефекта получил свой предмет — `absent` (нет
стрелки с меткой ячейки), `label` (та же метка — другие концы), `wrong-label` (те же концы —
другая метка), `twice` (таблица называет ячейку дважды), `twice-arrow` (схема повторяет
стрелку), `count` (число стрелок и число ячеек разошлось) и **новый** `extra-arrow` (лишняя
стрелка, которой таблица не называет).  Переименования волны 87 отражены в артефактах: её
`leads` стал `label`, её `label` стал `wrong-label`.  Новая секция 5c — четыре «стенда»
сверки на маленьких таблицах: сверка проверяется сама, а не только на дереве репозитория.

**Claim:** `the-state-diagram-comes-from-the-code` — **amended, not rewritten**: id прежний;
текст дополнен фразой «ячейка, которой схема не несёт, названа отсутствующей, а не ведомой в
другое место»; `falsifier` дополнен новым отказом; `control` прежний.

**Доказательство (контроли, все на копии дерева, 2026-11-21).**  Контроли сделаны
**родителем, независимо от отчёта писателя**; 0 провалов.

| Контроль | Что сделано | Что сказала сверка | Код |
|---|---|---|---|
| Честное дерево (C95a) | ничего | тихо | 0 |
| **Стенд сверки (C95b)** | настоящая стрелка заменена посторонней | `absent post-decide nudge deciding` + `extra-arrow idle --> deciding : weird`; слов «leads the cell elsewhere» нет | — |
| Тот же стенд, другие случаи | 30 стрелок против 31 ячейки / таблица называет ячейку дважды / концы есть, метка другая / лишняя стрелка | `absent` / `twice` (не `absent`) / `wrong-label` / `extra-arrow` | — |
| **Самопроверка 5b жива (C95c)** | вызов `report_twice` сломан | проверка упала по своему отказу | 1 |
| Контроль claim'а (C95d) | таблица изменена, схема не перегенерирована | «the diagram of the repository is not the diagram that the code writes» | 1 |
| **Сверка никогда не говорит absent (C95e)** | ветка `absent` сломана | стенды упали: «does not name the defect» | 1 |
| **Тексты отказа правдивы (C95f)** | сверка извлечена из файла проверки и прогнана на таблицах своего вида | класс и предмет отказа совпадают во всех шести случаях | 0 |

**Чего волна не делает.**

1. **Проверка схемы не запрещает сам дубликат в таблице.**  Таблица, которая называет ячейку
   дважды, и схема, которая несёт эту стрелку дважды, здесь зелёные: генератор рисует по
   одной стрелке на ячейку, и такая схема — верная отрисовка такой таблицы.  Дубликат запрещён
   там, где он и есть: у машины есть своя юнит-проверка
   (`yeah-loop-no-label-is-declared-twice-for-one-state`), а рантайм берёт первое совпадение,
   так что вторая строка — мёртвый груз.  Волна говорит, где класс закрыт, и не притворяется,
   что закрывает его дважды.
2. **Новый вид дефекта — новая вещь для чтения:** когда схема повторяет стрелку, ячейка,
   которой в схеме нет, называется `twice-arrow`, а не «генератор не читает таблицу»; сообщение
   истинно в обеих половинах, но читателю надо посмотреть и на повторённую стрелку.
3. Сверка идёт по содержанию, а не по порядку: порядок стрелок не измеряется (возражение (c)
   волны 87).  Возражения (a) и (b) волны 87 (правило идентификатора PlantUML написано
   дважды; пайплайн в дереве без ядра меряется только в случае «нет ядра») тоже остаются.

### 16.88 Отказ называет истинный предмет, а правило «отсутствующей ячейки» — то, что написано в claim'е — **сделано 2026-11-21 (волна 96)**

**Что это за волна.**  Пятая починка доказательства трека D (волна D1).  Дискриминатор волн
94–95 нашёл две находки, которые касаются этого доказательства (F30 — средняя, F31 — низкая).
**Код ядра и генератора волна 96 не трогает** — чинится доказательство, тем же файлом
`tests/checks/check-the-state-diagram-comes-from-the-code.sh` (884→1050 строк,
40 164→50 745 байт, +232/−66).  Ветка волны держит четыре коммита.

**Находка F30 — стенд дубликата называл свою фикстуру, а не дерево.**  Стенд 5b строил копию
ядра с задвоенной ячейкой и сравнивал схему этой копии со схемой репозитория; на дереве,
которое уже называет ячейку дважды, копия называла её трижды, и стенд отказывал с «the table
of the copy does not name the same cell twice: the copy of the kernel cannot be changed» —
предметом отказа была фикстура стенда, а не измеряемое дерево.  **Ложный отказ с ложным
предметом хуже отсутствия отказа.**  Теперь стенд строит схему сравнения из схемы репозитория
с одной копией стрелки ячейки минус: он доказывает дубликат на любом дереве, и дерево,
которое говорит об одном событии дважды, дефектом доказательства не является.

**Находка F31 — правило «отсутствующей ячейки» было новее текста claim'а.**  Метка ячейки
искалась только среди стрелок, которых не claimила ни одна ячейка таблицы, поэтому ячейка,
чью метку схема несёт на концах чужих стрелок, называлась отсутствующей — хотя её метка в
схеме есть.  Теперь метка ищется **во всех** стрелках схемы: `absent` — метки ячейки нет
нигде, `label` — метка есть на чужих концах.  Вид `twice` по-прежнему отличается раньше
`label`, и порядок видов не зависит от порядка таблицы.

**Противоречие двух документов — зафиксировано, а не решено молча.**  Intent волны 95, §16.87
и правило в файле проверки определяют `absent` **по метке** («нет стрелки с меткой ячейки»);
формулировка в шапке файла проверки и в тексте claim'а была двусмысленной — её уточнила волна
96.  Claim в `spec.json` говорил «ячейка, которую схема не несёт вовсе» — фраза, которую можно
прочесть двумя способами, и код волны 95 не держал буквального её прочтения (метка `error`
лежит на 8 ячейках таблицы и на 8 стрелках схемы; ячейка `(idle error failed)` называлась
отсутствующей, хотя её метку несли чужие стрелки).  **Прочтение выбрано родителем
2026-11-21 и записано здесь и в артефакте волны:** правило волны 95 (по метке).  Это не
решение владельца из §17.2 — владелец может его отменить.

**Claim:** `the-state-diagram-comes-from-the-code` — **amended, not rewritten** (дата аменда
2026-11-21): id прежний, `scope`, `requirements` и `control` прежние; текст дополнен вторым
правилом («ячейка, чью метку схема несёт на концах чужих стрелок, названа ведомой в другое
место, а не отсутствующей»); `falsifier` дополнен **вторым** отказом («ячейка, чью метку
схема несёт на концах чужих стрелок, названа отсутствующей») — это ровно дефект волны 95, и
falsifier, который не может назвать дефект собственной волны, доказательство не держит.

**Доказательство (контроли, все на копиях дерева, 2026-11-21).**  Восемь контролей сделаны
писателем волны, четыре — **родителем, независимо от отчёта писателя**; 0 провалов.

| Контроль | Что сделано | Что сказала проверка | Код |
|---|---|---|---|
| Честное дерево (C96a) | ничего | тихо | 0 |
| **Задвоенная ячейка и задвоенная стрелка (C96b)** | документ обещает зелёный вердикт | тихо | 0 |
| **Задвоенная ячейка без задвоенной стрелки (C96c)** | F30 | «the table of the machine names the same cell more than once: the cell (deciding stream-end post-decide) is named 2 times…» | 1 |
| **Метка ячейки на чужих концах (C96d)** | F31: удалена стрелка `idle --> failed : error` | «the label of the cell is in the diagram and not on the ends of the cell: … the diagram carries the label of the cell on 7 arrows and the table of the machine names 8 cells with that label» | 1 |

**Чего волна не делает.**

1. **Проверка по-прежнему не запрещает сам дубликат в таблице машины:** дерево, задваивающее
   **другую** ячейку, зелёное.  Дубликат запрещён там, где он и есть, — юнит-проверкой
   `yeah-loop-no-label-is-declared-twice-for-one-state` (`tests/unit/test-yeah-loop.el`).
2. Сверка идёт по содержанию, а не по порядку: порядок стрелок не измеряется (возражение (c)
   волны 87 остаётся).
3. Картинки сайта — волны D3 и D4; сверка сравнивает ячейки таблицы со стрелками схемы.
4. **Замер:** файл проверки — 1050 строк и 50 745 байт (волна 95: 884 строки и 40 164 байта);
   стендов сверки семь (волна 95: четыре); числа машины в проверке не написаны, а читаются
   из кода: 31 ячейка, 17 меток, 11 состояний, 31 стрелка, 11 состояний схемы; метка
   `error` — на 8 ячейках таблицы и на 8 стрелках схемы.

---

### 16.89 Картина слоёв называет код, который её реализует, и проверка идёт по каждому имени — **сделано 2026-11-21 (волна 97)**

**Что это за волна.**  Первая волна второй части плана — часть II (волны схем, §D трека
догоняющего плана): картина слоёв ядра нарисована в нотации компонентов вместо ASCII.
**Код ядра волна 97 не трогает.**  Два новых файла:
`site/diagrams/core-layers.puml` (69 строк) и
`tests/checks/check-the-layer-diagram-points-at-files-that-exist.el` (247 строк у писателя,
251 после усиления родителя).

**Картина — та же, что на сайте.**  ASCII-рисунок `site/index.html:482–506` и нормативный
аналог `docs/ARCHITECTURE.md:501–523` заменены компонентной схемой: драйверы (человек,
ACP-клиенты, MCP-клиенты, batch, wire) сходятся к Session API и Run Controller, контроллер
ведёт адаптер модели, реестр инструментов и политику, планировщик исполняет то, что можно,
всё случившееся пишется в один append-only JSONL-журнал, проекции читают журнал.  Четыре
пакета (`drivers`, `core`, `journal`, `projections`), 15 блоков, 17 стрелок сплошных и 2
пунктирных, **64 ссылки `file:line`** (на день волны 97; после волны 98 — **65**, см. §16.90),
каждая — на определение (**на снимке волны 97**: 52 `defun`, 5 `defconst`,
5 `cl-defun`, 2 `cl-defstruct`).

**Источник написан рукой, а не порождён кодом.**  `docs/SITE-DIAGRAMS-PLAN.md:277–280`
называет кодо-порождённой только машину состояний; остальные схемы пишутся рукой, со
ссылками на модули и строки.

**Полнота.**  В `lib/` 66 модулей (**снимок волны 97**): **64 названы** картиной, **2 — в списке исключений** с
причиной (`lib/yeah-codes.el` — экспериментальный и не включён в цикл агента;
`lib/yeah-state-diagram.el` — генератор схемы состояний, инструмент автора, а не компонент
харнесса во время работы).

**Что измеряет проверка.**  Четыре вещи: (1) каждая ссылка `file:line` указывает на файл
репозитория, на строку этого файла и на строку **с определением**; путь за пределы
репозитория отвергается; (2) каждый модуль `lib/` либо назван картиной, либо перечислен в
`note` с причиной; (3) `note` не называет несуществующий модуль, не называет модуль без
причины и не называет модуль, который картина уже назвала; (4) каждый блок называет хотя бы
один файл, и все четыре слоя на месте.  Коды выхода: 0 — имена на месте, 1 — имя не на
месте, 2 — дерево не там, где проверка думает.

**Родитель усилил проверку 2026-11-21 — и нашёл дыру.**  Проверка писателя требовала, чтобы
строка несла **код**, а тело функции несёт код: волна, которая сдвинет строку в ядре,
оставит картину указывающей в пустоту, и проверка промолчит.  Ссылка должна называть
**определение**.  Контроль, ломающий эту дыру, измерен **до** починки и **не упал** (код 0 на
картине, что называет строку 64 `lib/yeah-context.el` — тело `let`), и упал **после**
(код 1: «the diagram names lib/yeah-context.el:64, and that line carries no definition»).

**Противоречие двух источников — зафиксировано, а не решено молча.**  Разведка родителя
утверждала, что проверка рендера рисует **каждый** `.puml` репозитория и подхватит новую
схему сама; писатель измерил, что это не так: проверка строит **свои** фикстурные деревья
(`probe.puml`, `alpha.puml`, `beta.puml`) и рисует их.  **Прав писатель.**  Значит **ничего в
гейте не рисует новую картину**, и рендер доказан прогоном пайплайна вручную (код 0 на
честной картине, код 1 на сломанной).  Проверка «картина сайта актуальна» — волна D4, её
ещё нет.

**Ещё одно расхождение с постановкой — записано.**  Постановка родителя называла **три**
пакета; писатель сделал **четыре**, потому что в картине сайта есть слой журнала между
планировщиком и проекциями.  Писатель пошёл за картиной, а не за постановкой.

**Claim:** `the-layer-diagram-points-at-files-that-exist` — новый, в `spec.json`; усиление
родителя в тексте claim'а, а не во втором обещании.

**Доказательство (контроли, все на копиях дерева, 2026-11-21).**  Восемь контролей: четыре
сделаны писателем, четыре — **родителем, независимо от отчёта писателя**; 0 провалов.

| Контроль | Что сделано | Что сказала проверка | Код |
|---|---|---|---|
| **Модуль убран из картины (C97a)** | `lib/yeah-trash.el` убран и не внесён в `note` | «the module lib/yeah-trash.el is neither named by the diagram nor listed in the note of the modules the picture does not name» | 1 |
| **Ссылка на несуществующую строку (C97b)** | `lib/yeah.el:37` → `lib/yeah.el:99999` | «the diagram names lib/yeah.el:99999, and the file has 81 line(s)» | 1 |
| **Новый модуль в `lib/` (C97c)** | появился ещё один модуль в `lib/` | «the module lib/yeah-new-module.el is neither named by the diagram nor listed in the note…» | 1 |
| **Ссылка на строку без определения (C97e)** | `lib/yeah-context.el:60` → `:64` | «the diagram names lib/yeah-context.el:64, and that line carries no definition» | 1 |
| **Блок без ссылки (C97f)** | блок `Wire` без файлов | «the block Wire of the picture names no file» (+2 о модулях) | 1 |
| **Модуль назван дважды (C97g)** | `lib/yeah-tools.el` и в картине, и в `note` | «the module lib/yeah-tools.el is named by the diagram and listed in the note as a module the picture does not name» | 1 |
| Честное дерево (C97d, C97h) | ничего | тихо | 0 |

**Чего волна не делает.**

1. **Смысл раскладки — суждение, а не измерение:** проверка держит, что имя — это файл, строка
   и определение; она не держит, что блок `Tool registry` — это блок, которому принадлежит
   реестр.
2. **Стрелки не измеряются вовсе.**
3. **Картины на сайте ещё нет** — вставка в `site/index.html` и стиль — волна D3.
4. **Ничего в гейте не рисует картину** (см. противоречие выше); проверка актуальности
   картины — волна D4.
5. **Замер:** файл картины — 69 строк; файл проверки — 247 строк у писателя и 251 после
   усиления; ссылок — 64 и модулей `lib/` — 66, из них 64 названы и 2 исключены с причиной
   (**снимок волны 97**).

---

### 16.90 Инструмент объявляет свой риск, а правило спрашивает по объявлению — **сделано 2026-11-21 (волна 98)**

**Что это за волна.**  Первая волна трека B (волна B1 догоняющего плана,
`docs/ARCHITECTURE-CATCHUP-PLAN.md` §B1): поле `:risk` в объявлении инструмента, и список
«меняющих мир» переезжает из рукописного перечня имён в объявления самих инструментов.
**Ядро тронуто, ядро и правило.**  Один новый модуль (`lib/yeah-risk.el`, 113 строк, 4 799 байт),
двенадцать правок в модулях ядра, один новый файл проверки
(`tests/checks/check-a-tool-declares-its-own-risk.el`, 1129 строк, 49 546 байт) и пять новых
юнит-тестов (`tests/unit/test-yeah-perm.el` +47, `tests/unit/test-yeah-tools.el` +44).

**Словарь риска — четыре вида.**  `("read" "write" "execute" "destroy")` — «смотрит», «пишет»,
«выполняет», «уничтожает».  Инструмент, который не объявил риск, имеет риск, который **не
известен**, а неизвестный риск меняет мир: правило спрашивает, и отсутствие объявления никогда
не делает правило мягче.  Инструмент, объявивший риск вне словаря, **отвергается по имени** при
регистрации.

**Поздняя связь вместо цикла `require`.**  Реестр инструментов требует модулей, которые требуют
правила прав, а правило прав спрашивает по объявлениям, которые живут в реестре.  Модуль
`lib/yeah-risk.el` знает только словарь и вопрос «меняет ли этот инструмент мир»; источник
объявлений ставит ему реестр (`yeah-risk--install-source`), и цикла не возникает: модуль,
требующий оба конца, не загрузился бы вовсе.

**Что измеряет проверка — шесть утверждений, и шестое родительское.**  Проверка **не берёт**
множество «меняющих мир» из константы: она **меряет** его, проходя по вызовам обработчика каждого
инструмента (маленький интерпретатор форм Elisp: он связывает параметры и локальные переменные,
помнит, какой процесс запустил сам инструмент, и отличает текст, который дал модель, от текста,
который дало ядро).  (1) Каждый инструмент ядра объявляет риск словаря.  (2) Регистрация
отвергает риск вне словаря и принимает инструмент без объявления.  (3) Объявление согласовано с
обработчиком: множество измеренных совпадает с множеством объявивших.  (4) Категория, которую
называет объявление, — одна из найденных измерением.  (5) Правило спрашивает по объявлению:
профили называют ровно измеренные инструменты **среди тех, что держит реестр**; проба с риском `read` не названа, проба с `write` —
названа, проба без объявления — названа.  (6) **Действие, которое не называет ни одно правило,
спрашивается, а не разрешается**: дефолт правила — `ask`, и проверка это утверждает.  Пятый
пункт — родительское усиление волны: без него снимок профиля (профиль вычисляется один раз, а
инструмент могут зарегистрировать позже) опирался бы на дефолт, который никто не проверял.

**Что изменилось в поведении — и это названо, а не спрятано.**  Профиль `plan` теперь запрещает
на два инструмента больше: `todo_add` и `todo_update`.  Раньше (список имён вручную) они не были
в перечне и **спрашивались**; теперь объявляют риск `write` (пишут в журнал прогона) и
запрещаются.  Это следствие обещания волны: правило спрашивает по объявлению, объявление
измерено, и перечень, который никто не поддерживал (инструменты задач появились раньше, чем волна
76 дописала в него `git_commit` и `delete`, а сами задачи в него не попали), заменён измерением.
**Решение родителя от 2026-11-21, владелец может отменить:** список задач — память самого
прогона, а не мир человека, но сайт сам говорит «Plan for read-oriented work» (`site/index.html:632`),
и запрет виден, а не тих: отказ приходит с текстом, а режим `build` — в одном шаге.  Запрет
*объявления* `todo_add` как `write` честен: инструмент пишет.

**Мёртвый контроль чужого claim'а.**  Контроль claim'а `the-plan-profile-denies-a-delegation`
был `sed -i 's|"bash" "job-cancel" "delegate"|"bash" "job-cancel"|' lib/yeah-perm.el` — а
перечня имён в `lib/yeah-perm.el` после волны 98 нет: контроль менял **ничего** и проверка
проходила.  Это класс F38 (страж, который не срабатывает никогда).  Контроль **перенесён** на
новое объявление: `sed -i 's|:risk "write"|:risk "read"|' lib/yeah-delegate.el` — делегация
перестаёт запрещаться, юнит-тест `tests/unit/test-yeah-delegate-plan-profile.el` падает (проверено
родителем, код 1), текст, `falsifier`, `scope`, `requirements` и `id` claim'а прежние.

**Картина волны 97 пришлось перепривязать — и это сделала усиленная проверка.**  Волна 98
сдвинула строки `lib/`, и три имени картины (`site/diagrams/core-layers.puml`) уехали со своих
определений (`lib/yeah-perm.el:62→68`, `lib/yeah-tools.el:118→119`, `lib/yeah-delegate.el:428→430`),
а новый модуль `lib/yeah-risk.el` не был назван.  Проверка волны 97 сказала об этом сама
(родительское усиление от 2026-11-21: ссылка должна указывать на строку **с определением**) —
без усиления сдвиг прошёл бы молча.  Родитель сверил все 64 ссылки снимком «до» (снимок — коммит `5c12b65`): **61 не
двинулись, 3 уехали и перепривязаны, и ни одна сигнатура не изменилась** — уехавшие три
(`lib/yeah-perm.el`, `lib/yeah-tools.el`, `lib/yeah-delegate.el`) указывают на то же
определение с побайтово тем же текстом формы.  Ссылок стало **65** (**снимок волны 98**; у
картины появился `lib/yeah-risk.el:94`).

**Что осталось за B1 — названо, а не спрятано.**  `lib/yeah-approval.el:74-94` по-прежнему
держит собственный рукописный перечень безопасных чтений
(`yeah-approval-safe-read-actions`, 9 имён): инструменты, объявившие `read`, но не попавшие в
этот перечень (`todo_list`, `delegate-result`, `git_status`, `git_diff`), в прикреплённом пути
по-прежнему спрашиваются.  Это тот же класс расхождения, что и перечень мутирующих, и это
следующий шаг B1; claim волны 98 про этот перечень не говорит (его `scope` — профиль прав, а не
путь одобрения).

**Claim:** `a-tool-declares-its-own-risk` — **новый** (не амендит): обещание волны, falsifier
перечисляет все шесть классов расхождения, `control` — мутация объявления меняющего мир
инструмента (`sed -i '0,/:risk "write"/{s/:risk "write"/:risk "read"/}' lib/yeah-edit.el`),
проверено родителем: проверка падает с кодом 1 и называет инструмент.

**Доказательство (контроли родителя, все на копии дерева, 2026-11-21).**

| Контроль | Что сделано | Что сказала проверка |
|---|---|---|
| C98a | риск вне словаря: `:risk "read"` → `:risk "source"` в `lib/yeah-files.el` | «the risk "source", which is not in the vocabulary of the kernel», код 1 |
| C98b | объявление снято: строка `:risk "read"` убрана | «the tool "read" declares no risk», код 1 |
| C98c | читающий инструмент объявил `write` | «its handler changes nothing: it reaches nothing», код 1 |
| C98d | меняющий мир инструмент объявил `read` | «the tool "edit" changes the world -- its handler reaches ("write") -- but it declares the risk "read"», код 1 |
| C98e | честное дерево | код 0 |

Прогон: `./scripts/dev check tests/checks/check-a-tool-declares-its-own-risk.el` — код 0;
`./scripts/dev ert tests/unit/*.el` — 458 тестов, 458 результатов как ожидалось.

**Живая сверка 2026-11-21.**  Прогон через оркестратор Paseo на дереве пакета
(`28b8780`) показал новую тропу правила вживую: модель вызвала `todo_add`,
профиль `build` **спросил** (вопрос о разрешении на проводе: `todo_add on
проверка маршрута`), ответ человека (`allow`, один раз) дал инструменту право,
задача была создана, `finish` завершил прогон.  Тот же прогон показал и остаток
B1: `read` объявляет риск `read` и был разрешён **без** вопроса — рукописным
перечнем безопасных чтений (`lib/yeah-approval.el:74`), — а `finish` ядро не
спрашивает вовсе (`lib/yeah-turn.el:386`).  Запись и её журнал:
`docs/LIVE-EVIDENCE.md`, «The live run of the package of the waves 97 to 99».
Чего прогон не доказал: ни одной другой модели, ни профиля `plan`, и ни того,
что модель послушается промпта — она прочитала `README.md`, хотя ей сказали
больше ничего не делать.

### 16.91 Отказ называет числа, которые он измерил, а стенд стрелки доказывает редукцию, которую обещает — **сделано 2026-11-21 (волна 99)**

**Что это за волна.**  Шестая починка доказательства трека D (волна D1).  Дискриминатор пакета
волн 93–96 нашёл две находки, которые касаются этого доказательства (F37 — средняя, F38 — низкая).
**Код ядра и генератора волна 99 не трогает** — чинится доказательство, тем же файлом
`tests/checks/check-the-state-diagram-comes-from-the-code.sh` (1050→1109 строк,
50 745→53 997 байт, +67/−8).

**Находка F37 — отказ называл не те числа.**  Строка вида `absent` пишется как
`absent\tfrom\tlabel\tto\tdrawn_count\tcells` — шесть полей, — а читатель брал пятое поле за число
ячеек таблицы, а шестое за запасное.  Поэтому сообщение о дефекте звучало «which carries 31 of the
 cells of the table»: число ячеек таблицы было пустым, а на его месте стоял счётчик нарисованных
ячеек.  Вторая ветка — «the generator does not read the table» — спрашивала, что шестое поле равно
нулю, чего не бывает **никогда**: её страж стоял в файле и не срабатывал ни разу.  Теперь условие
читает поле со счётчиком нарисованных ячеек, а сообщение говорит «which carries $actual of the
$extra cells of the table».

**Находка F38 — стенд стрелки не мог сработать.**  Функция, печатающая стрелку стенда, писала
метку на месте цели, а цель на месте метки: `deciding --> stream-end : post_decide` вместо
`deciding --> post_decide : stream-end` (так пишет `site/diagrams/state-machine.puml:16`).  Счётчик
стрелок с такой меткой был всегда нулём, условие «больше одной» не было истинно **никогда**, а блок,
убирающий копию стрелки, и его страж не приходили **никогда**.  Теперь концы стрелки печатаются на
своих местах, редукция вынесена в функцию `reduce_arrow`, и **редукция измеряется**: стенд строит
схему с двумя копиями стрелки, гоняет редукцию и держит, что результат несёт копию меньше.

**Починка доказана, а не только написана.**  Добавлены **два новых стенда** — «the number of the
cells that the diagram carries» (диаграмма несёт часть таблицы) и «the diagram that carries no cell
of the table» (диаграмма не несёт ни одной ячейки: ровно тот случай, который охраняет страж
отказа) — и замер редукции.  Стендов сверки стало **девять** (у волны 96 было семь).  Стенды
написаны в файле проверки и читают ядро вслепую: они меряют сверку, а не машину.

**Claim:** `the-state-diagram-comes-from-the-code` — **не амендится и не переписывается**
(2026-11-21): прежние `id`, `text`, `falsifier`, `scope`, `requirements` и `control`.  Claim не
говорит о числах отказа; починка возвращает доказательству то, что примечание (3) волны 96 и
§16.88 уже обещали.  Claim, который амендится на каждый дефект собственного доказательства, не
меряет ничего.

**Доказательство (контроли, все на копиях дерева, 2026-11-21, сделаны родителем).**  0 провалов.

| Контроль | Что сделано | Что сказала проверка | Код |
|---|---|---|---|
| **Откат починки F37 (C99a)** | ветка `absent` читает поля не так, как их пишет | «the message of the defect does not say 'carries 1 of the 2 cells of the table'» и «the message of the defect does not say 'the generator does not read the table'» | 1 |
| **Откат починки F38 (C99b)** | метка и цель стрелки стенда переставлены | «the diagram of the stand with one copy of the arrow of the cell … carries it 0 times and the stand of the reduction needs a diagram that carries it twice» | 1 |
| Зарегистрированный контроль claim'а (C99c) | таблица машины изменена, схема — нет | «the diagram of the repository is not the diagram that the code writes» | 1 |
| Честное дерево (C99d) | ничего | тихо | 0 |

**Чего волна не делает.**

1. **Починка не расширяет то, что проверка запрещает:** виды дефекта, их порядок и слова каждого
   отказа прежние; меняются только число, которое называет отказ, и достижимость стража
   отсутствующей ячейки.
2. Стенды волны измеряют сверку, а не машину: стенд, который падает, не говорит, что машина
   сломана.
3. Замер редукции измеряет редукцию стенда, а не редукцию генератора: генератор пишет стрелку
   ячейки так, как её называет таблица машины, а доказательством дубликата остаётся стенд волны
   96, который сравнивает схему репозитория со схемой копии ядра.
4. **Находка F36 была поднята родителем и отозвана родителем:** провал юнит-теста
   `yeah-context-estimate-is-cjk-aware` в логе гейта был укусом отрицательного контроля claim'а
   `unit-tests-pass`, а не дефектом дерева; записка родителя — в записи пакета.  Побочный вывод
   F36 стал пунктом 7 §19.1: лог гейта читается по трём меткам, и строка «after negative control»
   — это укус контроля, а не провал.
5. **Замер:** файл проверки — 1109 строк и 53 997 байт (волна 96: 1050 строк и 50 745 байт);
   стендов сверки девять (волна 96: семь), и у редукции стрелки есть замер свой.

### 16.92 Читатель процесса решает, а не падает на файловой системе — **сделано 2026-11-21 (волна 100)**

**Что это за волна.**  Ремонт доказательной обвязки проекта.  **Код ядра волна 100 не трогает** —
ни одного файла `lib/`, ни одного файла сайта.  Волну вызвал гейт пакета волн 97–99: он прочитал
падение одной проверки как опровержение claim'а, который на самом деле держится.

**Что случилось.**  Гейт пакета 97–99 (2026-11-21) закончился кодом 1.  В логе (`/tmp/w97-99-gate.log`)
163 метки `mathc:`: **162** — укус отрицательного контроля (ожидаемая форма), **ровно одна** — форма
провала положительного прогона, красная:
`mathc: ./scripts/dev check tests/checks/check-a-pilot-that-runs-out-of-time-leaves-no-server.el exited 1`.
Меток формы 3 (провал постановки контроля) в логе нет ни одной.  Проверка, запущенная **по одной**,
проходит: гонка видна под нагрузкой гейта, а не в одиночном прогоне.

**Дефект был гонкой файловой системы, а не дефектом claim'а.**  Проверка искала файл состояния
процесса (`file-exists-p`) и читала его после (`insert-file-contents`); процесс сервера умирал между
поиском и чтением, чтение падало с `file-missing`, Emacs прерывался.  Метод читает рухнувший
верификатор как **ошибку**, а не как доказанный контроль (волна 31), — и гейт назвал опровержением то,
что не опровергнуто.  Ложный отказ с ложным предметом хуже отсутствия отказа.

**Починка — читатель, который решает.**  Чтение состояния и тиков процесса живёт в одном месте,
модуль поддержки проверок `yeah-proc.el` (`tests/support/`, 92 строки, 4 143 байта; волной 101
переехал в ядро): файл **не ищется перед чтением** (существование
файла не обещание, что он ещё там), ловится **только** ошибка файла (`file-missing` — её подвид), а
читатель, который глотает всякую ошибку, — читатель, который ничего не решает; процесс, которого нет,
отвечает `nil`, и `nil` — не число ноль.  PID, который не называет процесса (nil, строка, ноль,
отрицательное число, дробное), отвечает `nil` и **не** поднимает ошибку формата.  Две проверки,
которые читали процесс, читают его через этого читателя: `check-a-pilot-that-runs-out-of-time-leaves-no-server.el`
(223→213 строк, 10 749→10 337 байт) и `check-the-server-does-not-spin-when-the-provider-is-silent.el`
(186→189 строк, 8 356→8 673 байта).  **Сервер, которого нет, — это называемый отказ, а не измерение
нулевых тиков:** проверка тихого сервера больше не читает тики отсутствующего процесса как ноль.

**Доказательство починки.**  Новая проверка
`check-a-check-that-reads-a-gone-process-decides-and-does-not-crash.el` (260 строк, 12 405 байт) держит
**семь утверждений**, и каждое из них может упасть: состояние и тики ушедшего процесса — `nil` и без
ошибки; состояние живого процесса — буква; тики живого процесса — число; **тики читателя — это тики
процесса**; читатель отвечает `nil` на PID, который не называет процесса; ни одна проверка
`tests/checks/` не читает stat-файл процесса сама.  Пятое утверждение держит четвёртое честным: читатель,
отвечающий нулём на любой процесс, проходит «тики — это число», и проверка тихого сервера становится
вакуумной (разница нулей не превышает границу).  Поэтому проверка читает файл **своего** процесса сама,
без читателя, и сверяет.  Сверка — **скобка**, а не равенство: тики процесса не убывают (замер на
этом хосте: 0 уменьшений на 2 000 чтениях), поэтому ответ читателя обязан лежать между чтением проверки
«до» и чтением «после» — точное сравнение, которое часы не делают флакующим.

**Claim.**  Новый: `a-check-that-reads-a-gone-process-decides-and-does-not-crash`.  Claim'ы пакета
97–99 **не тронуты**.  У двух claim'ов, чьё доказательство переехало в поддержку
(`the-server-does-not-spin-when-the-provider-is-silent`,
`the-pilot-that-runs-out-of-time-leaves-no-server-behind`), прежние `id`, `text`, `falsifier`,
`requirements` и `control`, а **scope** вырос на один файл: читатель процесса живёт там теперь.

**Доказательство (контроли родителя, все на копиях дерева, 2026-11-21).**  0 провалов.

| Контроль | Что сделано | Что сказала проверка | Код |
|---|---|---|---|
| Честное дерево (C100a) | ничего | тихо | 0 |
| Две переехавшие проверки (C100b) | ничего | тихо | 0 |
| PID, который не называет процесс (C100c) | прямой вызов читателя с `nil` и с ушедшим PID | `nil` и без ошибки | 0 |
| **Укус: читатель, который поднимает (C100d)** | снят `condition-case` | «the state of a process that is gone raised an error: (file-missing …)» | 1 |
| **Укус: читатель, который слеп (C100e)** | читатель отвечает `nil` на всё | «the state of this process is nil and not a letter» | 1 |
| **Укус: тики, которые всегда ноль (C100f)** | `(+ utime stime)` → `0` | «the ticks of the reader (0) are not the ticks of the process …» | 1 |
| **Укус: сервера нет (C100g)** | сервер съеден перед окном измерения | «the server of the check is not running: …» — названный отказ | 1 |
| Один читатель stat-файла (C100h) | ничего | обе переехавшие проверки идут через поддержку и сами stat-файл не читают | 0 |

**Честно о двух контролях, что сначала были неправы.**  C100d в первый раз менял **условие** обработчика
вместо того, чтобы снять защиту (ошибка файла ловилась как прежде, проверка проходила — контроль не
мерял ничего), а C100g искал одно из двух имён отсутствия сервера, тогда как прогон дал другое (оба
называют одно и то же).  **Код был прав в обоих случаях.**  Исправленные контроли — те, что
зарегистрированы; зарегистрированный контроль claim'а измерен на копии дерева: мутация обработчика
`file-error` заставляет проверку сказать «the state of a process that is gone raised an error» и
ответить кодом 1.

**Чего волна не делает.**  Разведка класса дефекта по всему репозиторию (только чтение, 2026-11-21,
отчёт — в записи пакета) нашла **42 места** класса и назвала **19** опасными (9 высоких, 10 средних).
Три главных: **шесть других проверок** читают «процесс жив» по существованию каталога `/proc/<pid>` —
на зомби это тоже верно, поэтому они могут опровергнуть claim, который держится; **`scripts/lib/tree.sh:46-50`** —
awk по глобу stat-файлов умирает на исчезнувшем файле и обрывает список потомков, а `stop_tree` не убивает
часть дерева; **`lib/yeah-client.el:62-64`** — файл порта удаляется остановкой сервиса, клиент падает там,
где докстринг обещает nil.  Это волны 101 и дальше — волна 100 чинит то, что нашёл гейт пакета, и не
больше.  Находка F39 (проекция интерфейса пишет ответ `allow-always` как отказ) — **вне пакета** и ждёт
C1: обе касаются одной записи решения о разрешении.

**Замер:** поддержка — 92 строки и 4 143 байта; новая проверка — 260 строк и 12 405 байт; семь
утверждений; укус зарегистрированного контроля claim'а измерен отдельно (код 1).

### 16.93 Правило жизни спрашивается в одном месте, а зомби — мёртв — **сделано 2026-11-21 (волна 101)**

**Что это за волна.**  Ответ на разведку класса дефекта (2026-11-21, §16.92): читатель дерева
процессов переезжает из поддержки проверок **в ядро**, и ядро получает **правило жизни процесса**.
Это первая из трёх волн, которыми закрывается класс; две другие — 102 и 103.

**Что было дефектом.**  Шесть проверок `tests/checks/` спрашивали «жив ли процесс» по **существованию
каталога** `/proc/<pid>`.  На зомби это тоже верно (зомби мёртв и ждёт, пока его заберут), поэтому
проверка могла **опровергнуть claim, который держится**.  Правило жизни было размазано по файлам:
у каждой проверки своя формулировка «жив», и формулировка, которая отвечает «жив» по каталогу, стоила
дороже, чем та, что спрашивает состояние.

**Починка — правило в ядре, а не список имён.**  Модуль поддержки проверок `yeah-proc.el`
(`tests/support/`, 92 строки, 4 143 байта) стал `lib/yeah-proc.el` (127 строк, 5 961 байт): чтение
состояния и тиков живёт в ядре,
поддержка проверок удалена.  Новая функция `yeah-proc-alive-p` отвечает на вопрос о жизни **состоянием**:
`S` и `R` — жив, **`Z` (зомби) — мёртв**, любая другая буква — не бежит, состояние `nil` — процесса нет,
и его нет на свете.  `lib/yeah-life.el` потерял свою `yeah-life--owner-alive-p`; оба её вызова спрашивают
`(yeah-proc-alive-p (yeah-proc-state pid))`.  **Два следствия — и в этом смысл волны:** сокет
**зомби-владельца** теперь вычищается (сокет зомби не должен мешать сервису начаться), и
`yeah-life-adopt` больше не отказывается зомби-владельцу, как живому.  Шесть проверок спрашивают
состояние вместо каталога; три проверки волн 100 и 101 читают процесс через модуль ядра.  Картина
`site/diagrams/core-layers.puml` называет `lib/yeah-proc.el:69` — **полнота картины часть её обещания**.

**Имя по конвенции, а не по постановке.**  `ELISP_BEST_PRACTICES.md` §2 (правило §2.1 раздела):
символ, который может быть вызван из другого модуля, пишется **с одним дефисом**.  Читатель ядра
зовут и `lib/yeah-life.el`, и проверки — значит `yeah-proc--state`, `yeah-proc--ticks`, `yeah-proc--alive-p` переименованы в
`yeah-proc-state`, `yeah-proc-ticks`, `yeah-proc-alive-p` (коммит `8a22cf3`); `yeah-proc--stat-text` и
`yeah-proc--number` остались внутренними.  **Писатель волны не разрешил расхождение молча** — он его
сообщил; решение принял **родитель** 2026-11-21 (правило вне §17.2, владелец может отменить):
конвенция проекта побеждает формулировку постановки.

**Доказательство волны.**  Новая проверка `tests/checks/check-a-process-that-is-dead-is-dead-everywhere.el`
(296 строк, 14 035 байта) держит четыре части: правило отвечает по букве состояния; **стенд** сравнивает
новое правило со старым на одном предмете (старое — `file-directory-p` по каталогу — говорит «жив» на
зомби, новое говорит «мёртв», а на живом процессе оба говорят «жив», то есть живое не сломано);
правило **не размазано** (ни один другой файл репозитория не определяет правило жизни, а файл, который
спрашивает правило, спрашивает и состояние); чтения ядра по-прежнему решают (состояние живого процесса —
одна буква).  **Зомби стенда — это буква `Z`, а не живой зомби:** ребёнок, завершившийся сразу, reap'нут
до открытия окна проверки, а доказательство, зависящее от этой гонки, — доказательство, которое не может
упасть.

**Claim.**  Новый: `a-process-that-is-dead-is-dead-everywhere`.  Claim волны 100
(`a-check-that-reads-a-gone-process-decides-and-does-not-crash`) **амендится, а не переписывается**: прежние
`id`, `falsifier`, `requirements` и `kind`; **текст** называет новое место читателя, **scope** — новый
файл, **control** идёт за файлом, который переехал (прецедент волны 61: scope растёт вместе с кодом).
У двух других claim'ов (`the-server-does-not-spin-when-the-provider-is-silent`,
`the-pilot-that-runs-out-of-time-leaves-no-server-behind`) изменился только **scope**: они читают процесс
через читателя, а читатель теперь в ядре.

**Доказательство (контроли родителя, все на копиях дерева, 2026-11-21).**  0 провалов, девять контролей.

| Контроль | Что сделано | Что сказала проверка | Код |
|---|---|---|---|
| Честное дерево (C101a) | ничего | тихо | 0 |
| Проверка волны 100 на честном дереве (C101b) | ничего | тихо | 0 |
| Правило жизни прямым вызовом (C101c) | `yeah-proc-alive-p` на пяти состояниях | `zombie=dead gone=dead live=alive nil=dead bad=dead` | 0 |
| **Укус: правило, которое считает живым всё (C101d)** | `(or (string= state "S")` → `(or t` | «the rule says alive for the state "Z", and it must say dead» | 1 |
| **Укус: проверка возвращается к каталогу (C101e)** | `yeah-proc-state` → `file-directory-p` | «asks whether the path of a process exists: the state of the process decides» | 1 |
| **Укус: читатель, который поднимает (C101f)** | снят `condition-case` | «the state of a process that is gone raised an error» | 1 |
| Отсутствующий процесс — `nil`, а не 0 (C101g) | прямой вызов читателя | `state=nil ticks=nil` | 0 |
| Поддержка удалена, модуль в ядре, картина его называет (C101h) | ничего | `lib/yeah-proc.el` есть, в `tests/support/` модуля `yeah-proc.el` нет, картина называет | 0 |
| Один читатель stat-файла (C101i) | ничего | stat-файл читает только проверка волны 100 (она читает его намеренно, ради независимой сверки) | 0 |

**Честно о контролях, что сначала были неправы.**  Первый прогон родительского скрипта объявил **три**
провала (C101c, C101g, C101h), и **код был прав в обоих случаях**: измеренные факты совпали с
ожиданием («зомби мёртв, отсутствующий мёртв, живой жив»; «`state=nil ticks=nil`»; поддержка удалена,
модуль назван), а неправ был **сам скрипт** — он передавал в свою функцию отчёта лишний аргумент, и код
сравнивался с текстом.  Исправленный скрипт перепрогнан целиком; зарегистрированные контроли — те,
что дали код 1 **своим** отказом.

**Чего волна не делает.**  Класс дефекта **не закрыт**: разведка нашла 42 места, назвала 19 опасными;
эта волна закрывает семь (шесть проверок и правило ядра).  `scripts/lib/tree.sh:46-50` (awk по глобу
stat-файлов умирает на исчезнувшем файле и **обрывает список потомков**, а `stop_tree` не убивает часть
дерева) — **волна 102**; `lib/yeah-client.el:62-64` (файл порта удаляется остановкой сервиса, клиент
падает там, где докстринг обещает `nil`) — **волна 103**.  Находка F39 (проекция интерфейса пишет ответ
`allow-always` как отказ) — **вне этой волны** и ждёт C1: обе касаются одной записи решения о разрешении.

**Замер:** модуль ядра — 127 строк и 5 961 байт; новая проверка — 296 строк и 14 035 байта; шесть
проверок переведены на правило ядра; поддержка удалена; одно переименование по §2.1 (коммит `8a22cf3`).

### 16.94 Дерево процессов переживает исчезнувший процесс — **сделано 2026-11-21 (волна 102)**

**Что это за волна.**  Второе из трёх мест, названных разведкой класса дефекта (2026-11-21,
§16.92).  Дерево процессов читается в оболочке, в `scripts/lib/tree.sh`, и читают его три
скрипта, которые владеют деревом (`scripts/dev-timeout:56`, `scripts/live-pilot:85`,
`scripts/gate:98`).

**Что было дефектом.**  Скан дерева был **одним awk** по глобу `/proc/[0-9]*/stat`, а awk
останавливается на файле, который не может открыть: один процесс, вышедший посреди скана,
**обрывал список потомков**, и `stop_tree` убивал ту часть дерева, которую ему дали, а
остальное оставлял стоять — сервер, который продолжает жить после того, как его остановили.
Сообщение awk было спрятано (`2>/dev/null`), и список обрывался всё равно.  Второй дефект — в
том же коде: поля stat-файла читались по **первой** закрывающей скобке (`index($0, ")")`),
поэтому процесс, в имени которого есть скобка, читался как процесс, у которого родитель — буква,
и его потомки не находились; **комментарий файла обещал последнюю скобку, а код читал первую**.
Третий дефект — слепота: ответ awk на файл, который не открылся, и на файл, который не
прочитался, был один и тот же.

**Починка — скан, который решает.**  Скан читает stat-файл каждого процесса и **идёт дальше**
на файле, которого нет (процесс вышел — это не ошибка и не жалоба); файл, который **есть**, но
не держит строки, — **называется** (читатель не знает и говорит об этом); поля читаются по
**последней** закрывающей скобке; дерево читается **один раз**, а не по разу на уровень
рекурсии.  `process_group` читает те же поля тем же читателем — группа процесса, в имени
которого есть скобка, это его группа; ответ для процесса, которого нет, остался **пустым**, и
это поведение волна не меняла.

**Шов для доказательства.**  Корень дерева процессов — переменная `PROC_ROOT` (читается при
**каждом** вызове), поэтому скану можно дать **своё** дерево: проверка строит фикстуру из
фальшивых stat-файлов и воспроизводит дефект **детерминированно**, а не ждёт гонку.

**Доказательство волны.**  Новая проверка
`tests/checks/check-the-tree-of-the-processes-survives-a-vanished-process.sh` (343 строки) держит
**восемь стендов**: скан читает данный ему корень; идёт дальше на файле, которого нет, и
находит потомков после него; поля читаются по последней скобке; файл, который есть и не
прочитывается, **называется**; потомки — глубже первых; группа процесса, который исчез, —
пустая; группа оболочки, что читает дерево, не сигналится, а группа процесса, который сам
ведёт группу, — сигналится; дерево репозитория не пишется.

**Claim.**  Новый: `the-tree-of-the-processes-survives-a-vanished-process`.  Ни один claim пакета
не амендится.  Писатель предложил **ещё два** claim'а из той же проверки (поля по последней
скобке; имя файла, который не прочитывается) — они **не зарегистрированы**: claim, который не
просили, не claim, а falsifier этого claim'а называет оба случая и без них.

**Доказательство (контроли родителя, на копиях дерева, 2026-11-21).**  Три контроля, 0 провалов.

| Контроль | Что сделано | Что сказала проверка | Код |
|---|---|---|---|
| Честное дерево (C102a) | ничего | тихо | 0 |
| Старое дерево (C102b) | новая проверка на `tree.sh` **до** починки | «the scan of the tree of the processes did not read the root it was given» — старое дерево не умеет работать с чужим корнем | 1 |
| **Укус: скан, который останавливается на исчезнувшем файле (C102c)** | `\|\| continue` → `\|\| break` | «the scan of the tree of the processes stopped at the file that is gone: …/proc/102/stat — the children after it were not found: 103 104 105 107» | 1 |

**Дефект старого кода измерен, а не угадан.**  Старый awk прогнан на фикстуре из четырёх
stat-файлов, третий — висячая ссылка: ребёнок **до** исчезнувшего файла напечатан, ребёнок
**после** — **потерян**, код awk 2; без `2>/dev/null` сообщение было `fatal: cannot open file`.
Pid старого awk брался из `parts[3]` пути, а это pid только когда корень — ровно `/proc`: на
корне из трёх уровней старый код печатал имя каталога фикстуры как pid (измерено:
`pid seen by the old code: w102old3-3168`).

**Чего волна не делает.**  Класс дефекта **не закрыт**: закрыто второе из трёх главных мест;
остальные названы в волнах 100 и 101.  Пайплайн диаграмм один раз не измерен: он работал дольше
120 секунд и был остановлен с ответом 3 (unknown), и **то же самое случилось на неизменённом
`main`** — хост был под нагрузкой около двадцати на четырёх CPU; прогон назван, а не зачтён как
успех.

**Замер:** `scripts/lib/tree.sh` — 81 строка и 2 947 байт → 205 строк и 6 942 байта; новая
проверка — 343 строки; 8 стендов; 3 родительских контроля, 0 провалов.

### 16.95 Читатель порта сервиса отвечает nil, а не падает на файловой системе — **сделано 2026-11-21 (волна 103)**

**Что это за волна.**  Третье из трёх мест, названных разведкой класса дефекта
(2026-11-21, §16.92).  Разведка нашла 42 места класса и назвала 19 опасными; волны 101,
102 и 103 закрывают три главных.

**Что было дефектом.**  Сервис публикует номер порта в файле рядом с сокетом
(`lib/yeah-service.el:105-108`) и **удаляет** этот файл при остановке (`:228-230`).  Читатель
порта (`lib/yeah-client.el:59-69`) спрашивал `file-readable-p` и **потом** читал: файл мог
исчезнуть между вопросом и чтением, чтение падало с `file-missing`, и падение уносило с
собой клиента — он падал на файловой системе там, где докстринг обещал ждать сервиса,
которого ещё нет.  Ошибка файла не ловилась вовсе, а `condition-case` вызывающего
(`lib/yeah-client.el:86-99`) накрывает `make-network-process` и **не** накрывает чтение порта.

**Починка — читатель решает.**  Читатель файла порта ловит **только** `file-error` и отвечает
`nil`: ровно то, что обещает докстринг и чего ждёт вызывающий.  Четыре вида недоступности
порта — это `file-error` (измерено на Emacs 30.2: `file-missing` и `permission-denied` — его
подвиды, чтение каталога даёт `file-error`), поэтому одного обработчика достаточно и обработчик
`error` не нужен.  **Читатель не слепой:** ошибка, которая не является ошибкой файла,
поднимается насквозь, и это проверяет стенд 8.

**Доказательство волны.**  Новая проверка
`tests/checks/check-the-client-reads-the-port-of-a-service-that-is-gone.el` (295 строк,
14 835 байт) держит **11 стендов**.  Среди них — стенд, который читает файл порта сервиса,
**останавливающегося в момент чтения** (исчезновение делает проверка, а не ждёт гонку), и
стенд «читатель прячет ошибку файла и ничего больше».  Стенд 7 читает опубликованный порт и
получает **его**, а не `nil`: читатель, отвечающий `nil` на всё, починку бы прошёл и ничего бы
не решал.

**Claim.**  Новый: `the-client-reads-the-port-of-a-service-that-is-gone`.  Ни один claim пакета
не амендится.  В scope — читатель и его проверка; `lib/yeah-service.el` **не** в scope: он не
менялся, проверка использует его как источник настоящего удаления файла.

**Доказательство (контроли родителя, на копиях дерева, 2026-11-21).**  Три контроля, 0 провалов.

| Контроль | Что сделано | Что сказала проверка | Код |
|---|---|---|---|
| Честное дерево (C103a) | ничего | тихо | 0 |
| Старое дерево (C103b) | новая проверка на коде **до** починки | три отказа **своими** утверждениями | 1 |
| **Укус: читатель, который прячет отказ чтения (C103c)** | обработчик поднимает вместо `nil` | три названных отказа: «the client died on the file where it promised to wait», «the port file that is a directory raised an error», «the port of a service that stopped while the client read it raised an error» | 1 |

**Честно о контроле, который сначала был неправ.**  Первая мутация C103c была на одну закрывающую
скобку короче: **файл не распарсился**, и проверка «упала» с ошибкой разбора, а не своим
утверждением.  Ложный отказ с ложным предметом хуже отсутствия отказа — мутация исправлена и
перепрогнана целиком; зарегистрирован тот контроль, который отказывает **своими** утверждениями.

**Чего волна не делает.**  Класс дефекта **не закрыт**: закрыта одна из трёх главных частей, а
остальные места класса по-прежнему названы в волнах 100 и 101.  Предпроверка `file-readable-p`
**осталась** — и это названо: клиент опрашивает файл каждые 50 мс, пока ждёт сервис, — но
обещание проверки больше не используется, чтение под `condition-case`, и стенд 2 устойчив к
любой из двух форм починки.  Провод и поверхности интерфейса не тронуты.

**Замер:** `lib/yeah-client.el` — 234 строки и 9 790 байт → 241 строка и 10 223 байта; новая
проверка — 295 строк и 14 835 байт; 11 стендов; 14 зелёных прогонов писателя; 3 родительских
контроля, 0 провалов.

### 16.96 Дискриминатор пакета 97–100: PASS и пять находок — **2026-11-21**

**Что это.**  Независимый проверяющий (агент-дискриминатор) прошёл пакет волн 97–100 на
коммите `1175f91` (ветка `main`, дерево не менялось: `git diff 1175f91` пуст).  **Вердикт:
PASS.**  Пакет держит то, что обещает: все четыре зарегистрированных контроля claim'ов падают
по своему отказу (код 1) с правдивым текстом, честное дерево зелёное по всем четырём проверкам,
карта метода зелёная и без непокрытых материалов, а починка доказательства волны 99 **доказана**,
а не только написана.  Отчёт: `/tmp/discriminator-97-99-report.md` (19 контролей).

**Замечание о нумерации.**  Брифинг велел нумеровать находки с F39, но F39 уже занят в записях
проекта (проекция интерфейса пишет ответ `allow-always` как отказ — вне пакета 97–100, ждёт C1).
Поэтому находки идут **с F40**, чтобы не завести два разных F39.  Это замечание к брифингу, а не к
пакету.

**F40 (средняя) — обещание claim'а B1 сильнее, чем его меряет код.**  Claim
`a-tool-declares-its-own-risk` обещает «профили называют ровно измеренные инструменты», а его
falsifier — «профиль, который **пропускает** инструмент, найденный измерением».  Измерение обходит
обработчики **25** инструментов ядра и находит **10** меняющих мир: `edit, write, bash,
job-cancel, todo_add, todo_update, git_commit, delete, delegate, bridge__eval`.  Профиль `plan` в
собственном контексте проверки называет **9**: `bridge__eval` не зарегистрирован в реестре (его
регистрирует только `yeah-bridge-register`, `lib/yeah-bridge.el:254`), и проверка выбрасывает его
из сравнения фильтром по реестру.  **Буквально клауза falsifier'а выполнена, и проверка её не
видит.**  Что смягчает: (1) суть обещания («правило спрашивает по объявлению») измерена целиком —
смена объявления меняет профиль, а пробы с риском `read` и без объявления ведут себя по-разному;
(2) опасная для безопасности суть измерена **без** сужения — если объявить `bridge__eval` риском
`read`, проверка падает с кодом 1 («the tool "bridge__eval" changes the world -- its handler reaches
("execute") -- but it declares the risk "read"»); (3) поведение безопасно: инструмент, не названный
профилем, спрашивается (дефолт `ask` измерен и ломается при `allow`); (4) причина сужения сказана в
комментарии внутри измерения 5, но противоречит шапке проверки и записи волны.  **Починка:**
сузить формулировку claim'а и записи до «инструменты, которые измерение нашло **среди тех, что
держит реестр**» — либо сравнивать измеренное множество с объединением «профиль + зарегистрированные
после снимка» и называть разницу.  **Решение родителя (2026-11-21, правило вне §17.2, владелец может
отменить):** claim амендится (текст + falsifier, `id`/`requirements`/`control` прежние), шапка
проверки приводится в согласие с измерением, и **волна 104** несёт эту починку.  Сузить обещание
нельзя «по-тихому»: либо обещание измеряется целиком, либо оно говорит ровно то, что измерено.

**F41 (низкая) — числа волны 97 описывают прошлое как настоящее.**  `AGENTS.md:1470` («`lib/` holds
66 modules, 64 are named»), `docs/PLAN.md:6265` («В `lib/` 66 модулей: **64 названы** картиной»),
`docs/PLAN.md:6323`, `waves/wave-97.json` intent («and 64 such names are there») и разбивка
определений («52 `defun`, 5 `defconst`, 5 `cl-defun`, 2 `cl-defstruct»»).  Измерено на `1175f91`:
ссылок `file:line` — **65**, модулей в `lib/` — **67**, названы **65**, исключены **2**,
определения — **53 `defun`, 5 `defconst`, 5 `cl-defun`, 2 `cl-defstruct`** (65).  Число ссылок в
этих же местах помечено как историческое, а числа модулей — нет.  **Починка:** пометить числа
модулей так же, как числа ссылок, и обновить разбивку определений на 53 `defun` (или пометить её как
историческую).  **Волна 104.**

**F42 (низкая) — запись о сверке 64 ссылок даёт чисел, которых нет в дереве.**  `docs/PLAN.md:6387-6389`,
`AGENTS.md:1512-1513`, `waves/wave-98.json` note (7): «59 did not move, 2 moved on the same
definition (the signature changed) and 3 left».  Измерено (диаграмма волны 97 `5c12b65` против
`1175f91`, сравнение по **имени определения** и по тексту формы): **61** из 64 ссылок удерживают то
же определение на той же строке; **3** сдвинулись (`lib/yeah-delegate.el` 428→430,
`lib/yeah-perm.el` 62→68, `lib/yeah-tools.el` 118→119) и каждая указывает на то же определение с
**побайтово тем же** текстом; **0** из 64 определений изменили сигнатуру.  Существенная часть
утверждения (все ссылки указывают на то же определение; три уехавшие перепривязаны) — **правда** и
подтверждена независимо; неверны только счёт и скобка про сигнатуру.  **Починка:** написать «61 не
двинулись, 3 уехали и перепривязаны» и убрать скобку про изменившуюся сигнатуру.  **Волна 104.**

**F43 (низкая) — falsifier claim'а волны 100 буквально нарушен самой проверкой, а страж — список
из двух имён.**  Falsifier'а гласит «a check of `tests/checks/` reads the stat file of a process by
itself», а проверка, которая его доказывает, читает `/proc/<pid>/stat` своего процесса напрямую
(`tests/checks/check-a-check-that-reads-a-gone-process-decides-and-does-not-crash.el:125`).  Сторож
(утверждение 7) проверяет только два названных файла (`yeah-check--readers`, строки 78-81), а не
весь `tests/checks/`: третья проверка, прочитавшая `/proc/<pid>/stat`, была бы незамечена.  Что
смягчает: исключение раскрыто в комментарии самой проверки (строки 61-64), читается собственный файл
процесса (гонки нет), и сегодня ни одна другая проверка в `tests/checks/` stat-файл процесса не
читает (проверено поиском по `/proc/`: остальные обращаются к `/proc/self/exe` и к каталогу
`/proc/<pid>`).  **Починка:** расширить утверждение 7 на поиск по `tests/checks/` (с явным
исключением доказывающей проверки) либо вынести прямое чтение в поддержку проверок
(`tests/support/`) как именованный «сырой» читатель.  **Волна 105.**

**F44 (низкая) — ветка отказа `yeah-perm--mutating-tools` прячет настоящую причину.**  `lib/yeah-risk.el:73-77`
(`(condition-case nil (require 'yeah-tools) (error nil))`), `lib/yeah-perm.el:112-114`: причина, по
которой ветка срабатывает, теряется — с намеренно сломанным `lib/yeah-result.el` профиль отказывается
словами «yeah-perm: the risks of the tools are not known: the registry of the tools is not loaded»,
и синтаксической ошибки настоящей причины в сообщении нет.  Само поведение верное и безопасное
(правило отказывается, а не разрешает; дефолт остаётся `ask` — проверено).  **Починка:** сохранять
пойманную ошибку и упоминать её в отказе.  **Волна 105.**

**Чего дискриминатор не смог проверить — названо, а не списано.**  (1) **Полный гейт
`./scripts/dev run`** (16–20 мин) не запускался: хост под нагрузкой (load 32 при 4 CPU, ~1 ГБ
свободной RAM), параллельно работают другие агенты.  Вместо него проверен **уже состоявшийся** гейт
пакета: лог `/tmp/w97-100-gate.log` (164 метки `mathc:`, все формы 2), `mathc map` (green, uncovered 0),
`mathc re-evaluate` (`{"needs_re_evaluation": []}`), плюс отдельно все четыре проверки пакета и все
зарегистрированные контроли.  (2) Полный набор юнит-тестов (`./scripts/dev ert tests/unit/*.el`, 458
тестов) целиком не запускался — только нужный для контроля claim'а делегации.  (3)
`./scripts/dev byte-compile-all` отдельно не запускался — косвенно проверено тем, что все проверки
пакета грузят `lib/` и проходят.  (4) Живой маршрут через настоящего провайдера не перезапускался:
вместо этого сверена запись `docs/LIVE-EVIDENCE.md` с **настоящим журналом прогона** на диске
(27 записей) — совпадение полное; происхождение самого прогона вне репозитория.  (5) Смысл раскладки
и стрелки картины не измеряется и измеряться не может — пакет это признаёт; проверено только, что
это **сказано**, а не выдаётся за измеренное.  (6) Измерение «0 decreases in 2 000 readings» волны
100 — авторское; дискриминатор повторил его на 500 чтениях (0 убываний), исходные 2 000 не
воспроизводил.  (7) Рукописный перечень безопасных чтений (`lib/yeah-approval.el:74-94`) сам пакет
объявляет незакрытым и вне scope claim'а.  (8) Класс гонки в шести проверках, в `tree.sh` и в
`yeah-client.el` признан волной 100 как следующие волны — **они и есть волны 101, 102 и 103**,
слитые в `main` 2026-11-21 (docs/PLAN.md §16.93–§16.95).

**Что из этого меняет порядок.**  Находки не отменяют ни одну волну пакета: обещания волн 97–100
**верны**, а находки — о том, как записи и один claim сформулированы, и о двух дефектах кода вне
пакета.  Волны 104 и 105 ставятся в очередь после волны C1: **104** — правда записей и обещания
claim'а B1 (F40, F41, F42), **105** — страж falsifier'а и причина отказа (F43, F44).  Записи
о находках ведутся здесь и не молчат: расхождение кода и документа — **находка**, а не повод
сделать документ оптимистичнее.

---

### 16.97 Девять мест документации называли модуль, которого нет — **найдено гейтом 2026-11-21 (волна 101)**

**Что это.**  Гейт пакета волн 101–103 закончился кодом 1 с **единственной** красной линией:
`mathc: ./scripts/dev check tests/checks/check-the-documentation-points-at-files-that-exist.el exited 1`.
Остальные метки журнала — форма 2 (§19.1 п. 7), **формы 3 не было ни одной**: ни один контроль
не сломался и ни один отказ не был отказом «для вида».  Проверка сделала ровно то, что обещает:
**девять** мест документации называли то, чего нет — семь путей удалённого модуля и два раздела,
которых нет среди заголовков.

**F45 (средняя) — волна, которая переносит модуль, оставляет документы, которые называют старое
место.**  Волна 101 перенесла читателя процесса из поддержки проверок в ядро (`lib/yeah-proc.el`)
и удалила модуль поддержки.  **Семь** мест продолжали называть путь,
которого нет: каталог `tests/support/` существует, а модуля `yeah-proc.el` в нём уже нет.
Называли его: запись волны 100 и запись волны 101 в `AGENTS.md`, §16.92 и §16.93 в
`docs/PLAN.md` (включая таблицу родительских контролей C101h), §16.96 в `docs/PLAN.md` (починка
F43) и граф «Класс дефекта» в `docs/ARCHITECTURE-CATCHUP-PLAN.md`.  Ещё **два** места называли
раздел §2.1 файла `ELISP_BEST_PRACTICES.md`: §2.1 — **абзац** внутри заголовка `## §2. Naming`, а
не заголовок, а проверка обещает, что названный раздел есть заголовком.  Имя в документации —
обещание читателю; имя, которое ведёт в тупик, хуже отсутствия имени.  **Дефект не в проверке,
а в волне 101:** объявление волны обязано было поправить и объявление.

**Починка — девять мест переписаны, обещания проверки не ослаблены.**  Модуль назван по имени
(`yeah-proc.el`) и по месту, которое есть (`tests/support/` — каталог существует), а §2.1 назван
словами внутри заголовка `§2` («правило §2.1 раздела»).  Проверка по-прежнему требует, чтобы
имя вело в файл, который есть, а раздел был заголовком: обещание не тронуто, **текст приведён
в соответствие с ним**, а не наоборот.

**Перепрогон гейта после починки (2026-11-21).**  Журнал `/tmp/w101-103-gate2.log`: **167** меток,
**все 167 — форма 2** (укус: проверка падает под своим отрицательным контролем), **формы 1 нет ни
одной** (красной линии нет) и **формы 3 нет ни одной** (отказ «для вида» не случился).  Код выхода
гейта — **3** (`unknown/vacant/uncomputable`): на момент прогона свидетельство решения владельца
было устаревшим, потому что дерево сдвинулось починкой документации.  После записи решения
владельца (`mathc record the-owner-decided-the-order-of-the-next-waves owner --by az --outcome pass`)
карта даёт **verdict: green**, **uncovered: 0**, а `mathc next` отвечает «nothing to do — declared
evidence is current and the tree is covered»; `mathc re-evaluate` — `{"needs_re_evaluation": []}`.

**Правило на будущее (решение родителя, 2026-11-21; правило вне §17.2, владелец может отменить).**
Волна, которая переносит или удаляет файл, прогоняет
`tests/checks/check-the-documentation-points-at-files-that-exist.el` **до** гейта своего пакета и
поправляет каждое место, которое называет старое имя.  Проверка — страж, гейт — место, где страж
кусает; **красная линия гейта — это дефект волны, а не дефект проверки.**

### 16.98 Ответ несёт область своего правила — **сделано 2026-11-21 (волна C1)**

**Что это.**  Ответ человека теперь называет **область**, в которой живёт его правило; правило,
которое ответ пишет, несёт ту же область; журнал записывает область.  Три пути — чистый
ответчик, привязанный прогон и сессия ACP — называют **свою** область через одну таблицу
носителей, и область без носителя **отвергается по имени с причиной**, а не маршрутизируется
молча в чужой носитель.  Это первая волна трека C (ядро); носители — C2, поверхности — C3.

**Решения родителя (2026-11-21; правило вне §17.2, владелец может отменить).**  Ни одна
развилка C1 не входит в §17.2, поэтому решает родитель; решение записано с датой и может быть
заменено решением владельца.  (1) **Область — отдельное поле ответа**: `:reply` остаётся **видом**
(`once`/`always`/`reject`), область — отдельное поле; канонический словарь областей: `once`,
**`run`**, `session`, `project`, `global`.  (2) **`run` добавляется** к четырём названным
(`docs/ARCHITECTURE.md:640`, постановка `docs/ARCHITECTURE-CATCHUP-PLAN.md:532-535`): в коде
область прогона **есть** (`lib/yeah-run.el:122-123`), а в документах её нет — это расхождение кода
и документа, оно зафиксировано как **F46**, а правка `docs/ARCHITECTURE.md` — решение владельца
(§0 плана, D10).  (3) **`always` не переименовывается** и не становится синонимом `global`: он
сохраняет поведение каждого пути, который его пишет, а `global` вводится как **явная новая**
область; постановка плана «`always` — это, по сути, `global`» верна только для одного пути, и
это то самое противоречие двух документов, зафиксированное в §6 плана.  (4) **Область пишется в
журнал**: событие `permission-decision` (`lib/yeah-events.el:51-53`) получило необязательное поле
`:scope` — иначе claim нельзя проверить по журналу.  (5) **На ACP — новые `optionId` при прежних
`kind`**: клиент, знающий только три `kind`, остаётся совместим; поверхности — волна C3.  (6) **Одно
каноническое написание имён ответа и конвертер на границе**: сегодня словарь ответа был написан в
трёх местах, три написания схлопываются в одно.  (7) **`reject` область не несёт**: постоянный
запрет меняет правило «последнее совпадение выигрывает» — это отдельное решение, а не следствие
C1.  (8) **Область без носителя отвергается по имени с причиной** (`project` — носителя нет;
`session` в attached-пути нет).  (9) **Контроль claim'а — детерминированный `sed`**, ломающий
**запись** области в правило, а не тайминг.

**Починка.**  Словарь областей и таблица носителей живут в `lib/yeah-perm.el`
(`yeah-perm--scopes`, `yeah-perm--carriers` — единственное место, где написано, кто какую область
несёт); словарь видов ответа и конвертеры на границе — в `lib/yeah-approval.el`; носитель прогона
— `lib/yeah-run.el` (`run`), носитель сессии — `lib/yeah-acp.el` (`session`), носитель чистого
ответчика — `global`; решение о области едет в журнал через `lib/yeah-turn.el` и
`lib/yeah-events.el`; поверхности читают словарь, а не список имён
(`lib/yeah-approval-ui.el`, `lib/yeah-service-ui.el`).  **Ложь интерфейса исправлена**: проекция
писала ответ `allow-always` как отказ (`deny`) — теперь пишет настоящий эффект `allow` и область
`session`.  Проверка волны — новая, `tests/checks/check-an-answer-carries-a-scope.el` (392 строки,
семь стендов), и седьмой стенд — «проекция интерфейса говорит правду» (починка находки F39).

**Контроли родителя (2026-11-21; на копиях в `/tmp`, репозиторий проекта не тронут).**

| контроль | что | ожидалось | получено | код |
|---|---|---|---|---|
| C1a | честное дерево волны + новая проверка | проходит | проходит | 0 |
| C1b | старое дерево (база `1175f91`) + новая проверка | отказ **по своим утверждениям** | 17 строк отказа | 1 |
| C1c | мутация зарегистрированного контроля (`sed` ломает **запись** области в правило) | отказ по своим утверждениям | 2 строки отказа: «правило сессии несёт область nil, а не :session», «правило прогона несёт область nil, а не :run» | 1 |
| C1d | та же мутация ещё дважды | тот же отказ, тот же текст | те же 2 строки | 1 |
| C1e | пять соседних проверок волны | зелёные | зелёные | 0 |

**Картина слоёв.**  `site/diagrams/core-layers.puml` называла четыре строки, которые волна сдвинула:
`lib/yeah-approval-ui.el:114→115`, `lib/yeah-service-ui.el:413→436`, `lib/yeah-perm.el:68→121`,
`lib/yeah-approval.el:59→162`.  `site/` — точка сериализации родителя, писатель её не трогал и
оставил её родителю; родитель перепривязал четыре числа, и проверка картины снова зелёная.

**Что осталось открытым (писатель сообщил, родитель не закрывал молча).**  (а) Мёртвый крюк
`yeah-perm-record-decision` (`lib/yeah-perm.el`) остаётся мёртвым: его контракт
`(:action :resource :reply :save)` не имеет места для области — это естественное место записи
решения с областью, но оживлять его молча нельзя; волна C2 или решение владельца.  (б) `always`
по-прежнему значит три разных вещи — волна C2.  (в) У `project` нет носителя, и словарь
`scope :project` — это отказ по имени, а не поведение; никто не измеряет, что означала бы
«область проекта».  (г) Поле `:scope` в журнале пока никто не читает обратно — пишется, но
поверхность его не читает.  (д) Имена видов ответа по-прежнему встречаются в ядре дважды: проверка
доказывает «словарь написан в одном месте», а не «имя вида встречается в одном месте».
(е) `scope :once` и вид `once` делят слово — в словарях они не сталкиваются, но в журнале это
стоит знать.

**Живой прогон не делался.**  Ни провайдера, ни настоящего клиента: все измерения офлайн, с
поддельным транспортом или поддельным клиентом.  Это названо здесь, а не посчитано успехом.

### 16.99 Правда записей: обещание B1, числа волны 97 и числа волн 101–102 — **сделано 2026-11-21 (волна 104)**

**Что это.**  Волна 104 не трогает ядро.  Она чинит **правду записей** — три находки дискриминатора
пакета 97–100 (F40, F41, F42 в §16.96) и одну находку пакета 101–103 (F50 в §16.100), — и она же
приводит в согласие **шапку проверки** с тем, что проверка на самом деле меряет.  Починка F40
**видна в коде**: сравнение вынесено в именованную функцию, а рядом с ним стоит **стенд**,
который ломает это сравнение в обе стороны.  Проверка выросла с 1129 строк и 49 546 байт до
**1183 строк и 52 744 байт**.

**F40 (средняя) — обещание claim'а B1 сужено до измеренного.**  Claim
`a-tool-declares-its-own-risk` обещал «профили называют ровно измеренные инструменты», а измерение
находило **10** меняющих мир инструментов, тогда как профиль `plan` в собственном контексте
проверки называл **9**: `bridge__eval` не зарегистрирован в реестре сам (его регистрирует только
`yeah-bridge-register`, `lib/yeah-bridge.el:254`), и фильтр по реестру выбрасывал его из
сравнения.  Клауза falsifier'а была выполнена буквально, и проверка её не видела.  **Починка —
аменд claim'а (текст + falsifier; `id`, `requirements`, `control` прежние):** обещание теперь
говорит ровно то, что измерено — «профили называют ровно измеренные инструменты **среди тех, что
держит реестр**», — а falsifier называет три отказа: профиль, который называет инструмент,
которого реестр не держит; профиль, который называет инструмент, измерение которого не нашло
меняющим мир; профиль, который **пропускает** измеренный меняющий мир инструмент среди тех, что
держит реестр.

**Шапка проверки приведена в согласие с измерением.**  Пункт 5 шапки теперь читает «the profiles
name exactly the tools of the measurement **that the registry holds**», и рядом стоит абзац,
который называет, **почему** сравнение идёт по реестру: правило спрашивает по объявлениям
реестра, а инструмент моста, пока мост его не зарегистрировал, профилем не назван — хотя
измерение обходит его обработчик.  Тексты отказа сказали своё: «the plan profile names %S, but
**the tools of the registry that change the world** are %S».

**Стенд, который говорит, что сравнение кусается.**  Проверка, которая не может упасть, — это
комментарий; поэтому сравнение вынесено в `yeah-check--profile-mismatch` (а отбор измеренных — в
`yeah-check--mutating-tools`), и рядом стоят **два стенда**: подделка профиля, который называет
инструмент, которого измерение не нашло, и подделка измерения, которое не держит меняющий мир
инструмент, — обе должны быть отвергнуты.  Сравнение, которое принимает всё, упало бы на этих
стендах.

**F41 (низкая) — числа волны 97 теперь названы снимком.**  `docs/PLAN.md` (§16.89) и `AGENTS.md`
называли числа модулей и разбивку определений как настоящие: «в `lib/` 66 модулей, 64 названы»
и «52 `defun`, 5 `defconst`, 5 `cl-defun`, 2 `cl-defstruct`».  Числа ссылок были помечены как
исторические, а числа модулей — нет.  Теперь они помечены так же: **снимок волны 97** (коммит
`5c12b65`).  Обновлять их было бы нельзя и по существу: числа — снимок состояния на день волны,
и подмена их сегодняшними числами сделала бы запись о волне 97 ложью другого рода.

**F42 (низкая) — числа сверки ссылок исправлены на измеренные.**  Запись о сверке 64 ссылок
говорила «59 не двинулись, 2 сдвинулись на ту же самую определение (изменилась сигнатура), 3
уехали».  Измерено: **61** из 64 ссылок удерживают то же определение на той же строке, **3**
сдвинулись и каждая указывает на то же определение с **побайтово тем же** текстом формы, и **0**
из 64 определений изменили сигнатуру.  Существенная часть утверждения была правдой — неверны были
счёт и скобка про сигнатуру.  Теперь запись говорит «61 не двинулись, 3 уехали и перепривязаны, и
ни одна сигнатура не изменилась».

**F50 (низкая) — числа волн 101 и 102 исправлены на измеренные.**  Записи называли `lib/yeah-proc.el`
как 5 966 байт (на деле **5 961**), проверку волны 101 как 14 043 байта (на деле **14 035**), а
проверку волны 102 как 340 строк (на деле **343**).  Числа 5 966 и 14 043 были верны до коммита
`8a22cf3`, а 340 — до `99958b8`; оба коммита — предки коммитов записей, то есть числа устарели
**уже в момент написания**.  В отличие от F41, эти числа не снимок, а **замер**: они должны
быть верными здесь и сейчас, и теперь они такие.

**F53 (низкая, найдена родителем при разборе F50, запись F50 — §16.100 ниже) — запись волны 101
называет раздел, которого нет.**  `waves/wave-101.json` трижды называет раздел `2.1` файла
`ELISP_BEST_PRACTICES.md`, а такого заголовка нет: заголовки файла — `§1`…`§11` и `§11.1`…`§11.17`.
Имя заменено словами внутри существующего заголовка: раздел `2` («Naming»).  **Почему страж этого не увидел:**
`tests/checks/check-the-documentation-points-at-files-that-exist.el` читает `docs/*.md`,
`AGENTS.md`, `README.md` и `ELISP_BEST_PRACTICES.md` — и **не** `waves/*.json`, где записи волн и
живут.  Расширить страж на `waves/` — **открыто** (следующая волна): у стенда есть цена (каждая
запись волны — сотни строк, и страж начнёт читать их целиком), и решение о ней принимает владелец.

**Где ещё повторялось обещание B1.**  Обещание дословно повторяли ещё три места: §16.90 в
`docs/PLAN.md`, `intent` волны 98 и её `note`.  Все три приведены в согласие с амендом.

**Что осталось за этой волной.**  F43 и F44 (находки прошлого дискриминатора) — волна 105.
Расширение измерения B1 — сравнение с «профилем плюс инструменты, зарегистрированные после
снимка» — решено как **необязательное дополнение**, а не часть починки: оно не отменяет аменд и
не входит в гейт этой волны.  Находки F47–F52 (§16.100) ждут волны 106.

### 16.100 Дискриминатор пакета волн 101–103: PASS и шесть находок — **2026-11-21**

**Что это.**  Независимый проверяющий (агент-дискриминатор) прошёл пакет волн 101–103 на
коммите `fe00b6b` (ветка `main`, дерево не менялось: `git status --porcelain` пуст, `git diff
fe00b6b --stat` пуст, HEAD не двигался).  **Вердикт: PASS.**  Пакет держит то, что обещает: все
четыре зарегистрированных контроля claim'ов падают по своему отказу (код 1) с правдивым
предметом, честное дерево зелёное по семи проверкам, старый код падает на новых проверках по их
собственным утверждениям, карта метода зелёная и без непокрытых материалов.  Отчёт:
`/tmp/discriminator-101-103-report.md` (25 контролей).

**Об обрыве агента.**  Отчёт был **записан полностью** — вердикт, таблица находок и таблица
25 контролей стоят в файле.  Сам агент упал уже после записи отчёта: провайдер вернул `429 Token
Plan usage limit reached`.  Это **блокировка провайдера, а не провал пакета** — правило
`a-provider-failure-is-not-a-failure-of-the-agent' (§16.25).  Проверки, которые дискриминатор успел
прогнать, все зелёные; непроверенным осталось только то, что он назвал сам.

**F47 (средняя) — обещание claim'а волны 101 шире своего измерения, и в пакете есть
контрпример.**  Текст claim'а `a-process-that-is-dead-is-dead-everywhere` обещает «the checks of
`tests/checks/` read the process through the one reader and not by a path of their own».  Проверка
меряет для `tests/checks/` только (а) отсутствие пробы существования пути `/proc/`, (б) отсутствие
второго правила `*-alive-p`, (в) «если файл спрашивает `yeah-proc-alive-p`, то спрашивает и
`yeah-proc-state`»; а страж «читатель stat-файла живёт в одном модуле» applies **только** к файлам
с префиксом `lib/`.  При этом stat-файл процесса в `tests/checks/` читает сам
`tests/checks/check-a-check-that-reads-a-gone-process-decides-and-does-not-crash.el:125`.  Falsifier
claim'а волны 100 («a check of `tests/checks/` reads the stat file of a process by itself»)
волной 101 **не амендирован** и остаётся буквально нарушенным той самой проверкой, которая его
доказывает.  Объём исключения — **1 файл из ~120 проверок**, и оно раскрыто в комментарии новой
проверки.  **Починка:** амендить falsifier claim'а волны 100 (исключить доказывающую проверку
поимённо) либо сузить текст нового claim'а; альтернатива — расширить страж на `tests/checks/` с
явным исключением.  **Волна 105.**

**F48 (средняя) — обещание claim'а волны 101 о двух следствиях (сокет зомби) не измеряется ни
одной строкой.**  Claim обещает: «so the socket of a zombie owner is swept away and a zombie owner
is not adopted as if it lived».  Ни одна проверка этого не меряет: `yeah-life-adopt` и
`yeah-life-socket-sweep` встречаются только в `lib/yeah-life.el` и `lib/yeah-service.el:171`, ни
один тест не говорит о зомби-владельце.  Проверка волны 101 меряет **форму** кода (текстовые
стражи), но не поведение.  По коду обещание верное (`Z` → `(yeah-proc-alive-p "Z")` = nil → сокет
зомби сносится, владелец-зомби не отвергается), но в нормативном claim'е это ничем не
подтверждено, и в falsifier'е не названо.  **Починка:** либо построить стенд (поведение
`adopt`/`sweep` с владельцем-зомби требует настоящего зомби или подменяемого дерева `/proc`), либо
сузить текст claim'а до измеренного и назвать поведение непомеренным.  **Волна 105.**

**F49 (средняя) — у пакета нет живого прогона, и ни одна запись пакета этого не называет.**  §19.1
п. 5 требует «**Живой прогон — один на пакет**».  У пакета 101–103 такого прогона нет: в
`docs/LIVE-EVIDENCE.md` последняя запись — «The live run of the package of the waves 97 to 99
(2026-11-21, 06:16 UTC)»; записи волн 101–103 не упоминают живой прогон ни как сделанный, ни как
пропущенный.  Проверено на диске: единственный содержательный журнал прогона через провайдера за
тот день — `session-7-ae346d.jsonl` (22 079 байт, 06:17, пакет 97–99); во всех 111 каталогах сессий
после 07:30 нет ни одного журнала размером больше 5 КБ.  Пакет закрывает класс дефекта «читатель
падает на файловой системе» — живой маршрут этого класса почти не касается, но порядок работы
требует один прогон на пакет, и его отсутствие не названо.  **Починка:** провести живой прогон и
записать его в `docs/LIVE-EVIDENCE.md`, либо — если владелец решит, что пакет из читанок живого
маршрута не касается — записать в §16.93–§16.95 и в записи волн, что живой прогон не делался и
почему.  **Решение владельца.**

**F50 (низкая) — числа волн 101 и 102, названные как настоящие, не совпадают с деревом.**
`waves/wave-101.json` (intent, note), `waves/wave-102.json` (intent), `docs/PLAN.md` и `AGENTS.md`
называли 5 966 байт, 14 043 байта и 340 строк; на деле — **5 961**, **14 035** и **343**.  Числа
5 966 и 14 043 были верны до коммита `8a22cf3`, а 340 — до `99958b8`; оба коммита — предки
коммитов записей, то есть числа устарели **уже в момент написания** записей.  Числа, названные как
исторические, верны.  Ни одна проверка метода не ловит расхождение размеров.  **Починка:** числа
исправлены на измеренные — **волна 104** (§16.99).

**F51 (низкая) — две части обещания claim'а волны 102 не измеряются: «дерево читается один раз»
и «дерево останавливается целиком».**  Ни один стенд этого не меряет: проверка ни разу не
вызывает `stop_tree` и нигде не считает число проходов скана.  По коду обещание верно
(`descendants()` зовёт `scan_tree` один раз; `stop_tree` проходит по полному списку), но
доказательства нет, и в falsifier'е эти пункты не названы.  **Починка:** либо измерить (счётчик
вызовов `scan_tree` в проверке — стенд уже умеет подменять дерево через `PROC_ROOT`), либо убрать
обе клаузы из текста claim'а.  **Волна 106.**

**F52 (низкая) — страж «правило жизни в одном месте» уже, чем falsifier claim'а волны 101.**
Falsifier говорит: «the rule of the life of a process lives **outside the kernel**» и «another file
of **the repository** defines the rule of the life of a process beside it».  Проверка сканирует
только `tests/checks/*.el` и `lib/*.el` и узнаёт правило только по форме: имя функции оканчивается
на `-alive-p` **и** её аргумент называет `pid`.  Второе правило с другим именем или с другим
названием аргумента, а также правило в `scripts/`, `tests/support/`, `tests/unit/` — не увидит ни
один страж.  Сегодня в репозитории таких правил нет, поэтому обещание верно **по факту** —
расходится только измерение.  **Починка:** расширить страж (по всем каталогам дерева и по признаку
«решает жизнь процесса») или сузить falsifier до того, что страж меряет.  **Волна 106.**

**Оценка находок прошлого дискриминатора (F43, F44) — обе записаны верно.**  **F43**
подтверждён на `fe00b6b`: falsifier claim'а волны 100 по-прежнему содержит «a check of
`tests/checks/` reads the stat file of a process by itself», доказывающая его проверка читает
`/proc/<pid>/stat` сама, и страж смотрит только два названных файла; волна 101 это **не
смягчила**.  Объём исключения — 1 файл, и он назван в комментарии новой проверки (см. F47).
**F44** подтверждён: `lib/yeah-risk.el:73-77` по-прежнему ловит ошибку `(require 'yeah-tools)` и
теряет её, а `lib/yeah-perm.el:112-114` отказывает словами «yeah-perm: the risks of the tools are
not known: the registry of the tools is not loaded» — настоящей причины в сообщении нет.  Поведение
верное и безопасное.

**Замечание о брифинге (не находка пакета).**  Брифинг велел записать F46 («расхождение кода и
документа по областям») в §16.98.  В дереве `fe00b6b` §16.98 ещё не было — запись появилась позже
(§16.98 в дереве `c97a58e`), и F46 зафиксирована в ней.

**Чем мерилось (25 контролей, все на копиях в `/tmp/disc101/*`).**  (1–7) честное дерево по семи
проверкам пакета — все код 0; (8–11) четыре зарегистрированных контроля claim'ов — все код 1 и
свои отказы; (12–13) старый код (`3d0900b`, `9f47e85`) против новых проверок — код 1; (14–18)
пять мутаций, каждая кусается своим отказом; (19) разбираемость всех мутированных файлов **до**
прогона — `check-parens` и `bash -n`; (20) журнал гейта — 167 меток `mathc:`, **все формы 2**
(«verifier after negative control»), формы 1 и 3 нет ни одной; (21) карта метода — green,
uncovered 0; (22–25) числа волн, картина слоёв, переезд читателя и наличие живого прогона.

### 16.101 Три контроля, которые перестали стрелять — **сделано 2026-11-21 (волна 105)**

**Что это.**  Карта пакета сказала `unknown`: три claim'а — `wire-permission-request`,
`approvals-have-reply-kinds` и `always-is-remembered-for-the-session` — получили статус
**inconclusive**.  Причина оказалась той же, что в F38: **волна C1 переписала три места, которые
мутируют их зарегистрированные контроли**, и `sed` не находил в них ни одной строки.  Мутация не
меняла ничего, проверка проходила на неизменённом коде, и доказательство claim'а не могло быть
убедительным — оно и не было.

**Измерено, а не предположено.**  На коммите `fe00b6b` (до волны C1) все три паттерна находились
(1, 2 и 1 вхождения), на текущем дереве — **0, 0 и 0**.  Места, которые изменила C1:
`(equal option "allow-once")` в `lib/yeah-acp.el` (ветка стала `(kind (list :effect :allow :reply
kind))` — решение перешло на канонический вид ответа), `'allow))` в `lib/yeah-approval.el` (вид
ответа стал отдельным словарём, а запись `always` — вызовом с областью), и
`(let ((session-id (plist-get question :session-id)))` в `lib/yeah-acp.el` (стало `let*` с двумя
связываниями).

**Починка — контроли перенесены на места, которые изменила C1, и каждый из них измерен.**  Текст,
falsifier, `scope`, `requirements` и `id` трёх claim'ов — **прежние**: обещания C1 не меняла,
изменились только места, — перенесён только `control`.

| claim | новый контроль | чем отказывает |
|---|---|---|
| `wire-permission-request` | `sed -i 's\|(list :effect :allow :reply kind))\|(list :effect :deny :reply kind))\|' lib/yeah-acp.el` | «wire-perm: the allowed write did not run: "refused"» — клиент разрешил, сервис отказал |
| `approvals-have-reply-kinds` | `sed -i 's\|(when (eq kind :always)\|(when (eq kind :never)\|' lib/yeah-approval.el` | «approvals: the answer always was not written into the rules» — `always` не пережил вопрос |
| `always-is-remembered-for-the-session` | `sed -i "/yeah-approval-remember-rule/,+3s/scoped)))/nil)))/" lib/yeah-acp.el` | «yeah-acp-an-always-answer-is-remembered-for-the-session» — решение не записано в правила сессии |

Честное дерево по всем трём проверкам — код 0; каждая мутация — код 1 и **свой** отказ.

**Две пробы, которые не годились, названы, потому что они — часть цены.**  (1) Первая проба
контроля `always-is-remembered-for-the-session` — `sed -i 's\|(yeah-approval-always-p
scoped)\|(yeah-approval-always-p nil)\|'` — **не сломала ничего**: тест прошёл с кодом 0.  То есть
признак, по которому контроль выбирался, не является причиной отказа, и контроль на нём был бы
вакуумным.  (2) Вторая проба — `sed` с лишней скобкой в замене — дала **код 255**: проверка
**умерла**, а не отказала (§11.5 `ELISP_BEST_PRACTICES.md`: «a check that dies with 255 has not
bitten»).  Обе пробы — ложный отказ, хуже отсутствия отказа, и обе отброшены; принята третья, где
мутация ломает **запись** решения, а не чтение сессии.

**F55 (средняя) — записанный контроль разошёлся с измеренным: гейт поймал потерянную скобку.**
Волна 105 перенесла три контроля и объявила их измеренными, но **измеренной была одна строка, а в
`spec.json` попала другая**: в контроле claim'а `always-is-remembered-for-the-session` при переносе
потерялась одна закрывающая скобка (`nil)))` → `nil))`).  Мутация с такой потерей **ломает файл**:
`check-parens` отвечает «Unmatched bracket or quote», верификатор умирает с кодом **255**, и карта
оставляет claim **inconclusive** — не «красным», а именно неопределённым.  Первый гейт пакета
{С1, 104, 105} это и показал: 168 меток `mathc:`, **все формы 2** (укус), код 3, и карта, где два
claim'а (`wire-permission-request`, `approvals-have-reply-kinds`) стоят `holds (current)`, а третий —
`inconclusive`.  Два других контроля в файле оказались такими, какими были измерены.

**Починка.**  Контроль исправлен на измеренную строку, и **измерение переделано так, как его надо
было делать с самого начала**: измеритель берёт контроль **из `spec.json`** (а не переписывает его
рукой), применяет его к копии дерева, проверяет **разбираемость каждого изменённого файла** и
только потом запускает верификатор; «файл изменился» проверяется по **всему дереву**, а не по одному
имени.  Измеренный результат после починки: три контроля — код 1 и **свой** отказ, честное дерево —
код 0.  **Правило, которое из этого следует:** контроль измеряется тем, что лежит в `spec.json`;
переписывание измеренной строки при записи — это уже новая, неизмеренная строка.

**Уточнение нумерации (2026-11-21).**  §16.96 отправлял F43 и F44 в волну 105; волна 105 несёт
красную линию пакета (F54) и F55, и F43 и F44 ждут **волны 106**.  Находки F47, F48, F51 и F52 (§16.100)
ждут **волны 107**.  Это уточнение с датой; владелец может решить иначе.

**Что осталось.**  F43 (falsifier claim'а волны 100 нарушен самой доказывающей проверкой) и F44
(причина ошибки теряется в `lib/yeah-risk.el` и `lib/yeah-perm.el`) — волна 106.  F47, F48, F51,
F52 — волна 107.  F49 (у пакета 101–103 нет живого прогона) — решение владельца.  Расширение
стража документации на `waves/*.json` (F53) — волна 107.

### 16.102 Дискриминатор пакета волн C1, 104, 105: PASS и три находки — **2026-11-21**

**Что это.**  Независимый проверяющий (агент-дискриминатор) прошёл пакет волн C1, 104 и 105 на
коммите `ff3c1e1` (ветка `main`; дерево не менялось: `git status --porcelain` пуст и до работы, и
после неё).  **Вердикт: PASS.**  Отчёт: `/tmp/discriminator-c1-105-report.md` (24 контроля).

**Пакет держит то, что обещает.**  Все пять зарегистрированных контролей claim'ов пакета (три
перенесённых волны 105, новый claim волны C1, амендированный claim волны 104) кусаются **своим**
отказом кодом 1, и ни один не умирает кодом 255.  Честное дерево зелёное по всем затронутым
проверкам, `byte-compile-all` — код 0, полный ERT (`tests/unit/*.el`) — 463/463.

| # | что измерено | код |
|---|---|---|
| 1–9 | три перенесённых контроля волны 105: честное дерево → 0, каждая мутация → 1 **своим** отказом («the allowed write did not run», «the answer always was not written into the rules», «an always answer is remembered for the session») | 0 / 1 |
| 10 | **регрессия F55**: сломанный контроль `93eeb6e` (`nil))`) — файл неразбираем, проверка **умерла** | **255** |
| 11–16 | claim волны C1 `an-answer-carries-a-scope` («scope: the rule of the session carries the scope nil, not :session») и claim волны 104 `a-tool-declares-its-own-risk` («the tool "edit" declares the risk "read", but its handler reaches ("write")») | 0 / 1 |
| 17–18 | стенды волны 104: **стэнд A** (дефект сравнения есть, стенды на месте) → проверка падает; **стэнд B** (тот же дефект, стенды вырезаны) → дефект проходит молча | 1 / 0 |
| 19 | C1b: старое дерево `1175f91` против новой проверки волны C1 | 1, **ровно 17** строк отказа |
| 20 | C1d: та же мутация ещё дважды — тот же текст отказа | 1 |
| 21 | восемь соседних проверок волны C1 | 0 |
| 22–24 | картина слоёв; `byte-compile-all`; полный ERT (`tests/unit/*.el`, 463/463) | 0 |

**F56 (низкая) — число, неверное уже в момент написания.**  Запись §16.89 и
`waves/wave-97.json` называли файл проверки волны 97 как «247 строк у писателя и **253** после
усиления родителя».  Файл — **251 строка**, и 251 строка у него с коммита `ca321c8`
(2026-11-21 03:30:51 UTC), тогда как запись написана коммитом `09d306b` (03:36:17 UTC), и
`ca321c8` есть предок `09d306b`.  **Число 253 не было верным ни в один момент.**  Правило чисел
волны 104 (числа-снимки помечаются, числа-замеры приводятся к текущим) применено: в §16.89
(оба места) и в `waves/wave-97.json` → `note` п. 3 **253 → 251**.

**F57 (низкая) — у пакета не было живого прогона.**  §19.1 п. 5 требует «**живой прогон — один на
пакет**»; §16.99 и §16.101 этого не называли, и ни одна запись пакета не говорила о пакете
целиком.  **Прогон сделан** (решение владельца от 2026-11-21) и записан в `docs/LIVE-EVIDENCE.md`,
«The live run of the package of the waves C1, 104 and 105».  Прогон шёл через оркестратор Paseo
на дереве пакета (`ff3c1e1`); человек ответил на вопрос о разрешении через
`session/request_permission` выбором «Allow always»; решение пришло с `reply` = `:always` и
`scope` = `session`, а **второй** такой же вызов был разрешён правилом сессии **без** нового
вопроса человеку.  Остаток назван в записи прогона: решение, пришедшее от правила, несёт
`scope` = `once`, а не область сработавшего правила, — это тот же остаток, что §16.98 назвал
словом «nobody reads the scope of the journal back yet».

**F58 (низкая) — числа, названные в настоящем времени, устарели и не помечены как снимок.**
§16.90 говорил «Теперь ссылок **65**», `waves/wave-98.json` → `note` п. 7 — «the picture now
carries **65** names», `waves/wave-97.json` → `note` п. 2 — «67 modules, **65** named».  Эти числа
**были верны**, когда их писали, но читались как настоящие.  Помечены как снимок: §16.90,
`waves/wave-98.json` → `note` п. 7 и `waves/wave-97.json` → `note` п. 2 (и п. 1 того же `note` —
там же помечена приписка «65 after wave 98»).  **Измерено сегодня:** картина несёт **66** ссылок
`file:line` и **66** названных модулей, в `lib/` **68** модулей, 2 исключены с причиной, **ноль
неназванных**; файл проверки волны 97 — 251 строка.

**Новое правило родителя (2026-11-21; правило вне §17.2 — владелец может отменить).**  Живой
прогон обязан **сверять время старта сервиса с временем коммита**.  Первый прогон пакета
(15:49:51–15:51:02 UTC) прошёл полный маршрут, но его решения несли `reply` и **не** несли
`scope`: ACP-сервис был запущен в 05:34:24 UTC, а волна C1 слита в 13:13:31 UTC — сервис держал
в памяти старое дерево, и прогон измерял не пакет.  Свидетельство независимое и на диске: сокет
жизни сервиса `/tmp/yeah-1001/yeah-life-paseo-2282.sock` имеет время создания 05:34:24 UTC, а
сокет сервиса — 16:05:44 UTC (перезапуск на дереве пакета).  Плагин оркестратора держит кэш
сервиса (`plugin/yeah-provider/index.server.ts`), и `paseo reload` этот кэш **не** сбрасывает:
после смерти процесса сервис нужно поднимать руками на юните.  Код дерева при этом не меняется.

**Чего не смог проверить дискриминатор и почему.**  (1) Полный гейт пакета (≈20 мин) не запускался
— бриф это прямо запрещал; историческое утверждение §16.101 о первом гейте пакета («168 меток
`mathc:`, все формы 2, код 3») на текущем дереве не воспроизводимо.  (2) Карта метода в состоянии
«зелёная» не проверена: `./scripts/dev map` читает след полного `./scripts/dev run`, которого в
копии дискриминатора нет, — это граница инструмента, а не дефект пакета; по карте все пять
claim'ов пакета зарегистрированы, `uncovered: 0`.  (3) Живой прогон не делался и не мог быть сделан
дискриминатором — нет провайдера и ключа в его окружении; отсутствие прогона было F57, а не его
пробелом — прогон сделал родитель.  (4) Полный набор проверок `tests/checks/*` не прогонялся:
прогнаны проверки, названные в `wave-c1.json` и `wave-105.json`, проверка картины слоёв,
`byte-compile-all` и полный ERT.

**Что осталось открытым.**  F49 (у пакета 101–103 нет живого прогона) — решение владельца; оно
не закрыто этим прогоном, потому что прогон шёл по дереву пакета C1, 104 и 105.  F43 и F44 — волна
106; F47, F48, F51, F52 и F53 — волна 107.

### 16.103 Волна 106: страж, который смотрит на дерево, и отказ, который называет причину — **2026-11-21**

**Что это.**  Волна 106 закрывает две находки дискриминатора пакета волн 97–100 (§16.96): **F43** и
**F44**.  Код волны слит в `main` коммитом `da7def9`; запись волны — `waves/wave-106.json`.

**Уточнение нумерации — и противоречие двух источников.**  §16.96 отправил F43 и F44 в волну 105, а
§16.101 (уточнение от 2026-11-21) — в волну 106: волна 105 несёт красную линию пакета (F54), F43 и
F44 ждут волны 106, а F47, F48, F51, F52 и F53 — волны 107.  Пуля пакета 97–100 в `AGENTS.md`
обещала то же волне 105 («the wave 105 extends the sentinel», «the wave 105 keeps the cause»).
**Противоречие не решено молча:** обещание в `AGENTS.md` исправлено на «the wave 106», здесь оно
зафиксировано, и обе правки — с датой.

**F43 — страж смотрел два названных файла, а обещание говорило о дереве.**  Falsifier claim'а
волны 100 обещал, что ни одна проверка `tests/checks/` не читает stat-файл процесса сама, — а
доказывающая проверка читает его сама (исключение было названо только в комментарии самой проверки);
сторож того утверждения смотрел два названных файла.  **Что стало:** страж обходит дерево проверок
и дерево поддержки (`yeah-check--stat-exceptions`), а исключение названо **поимённо** — и в коде
стража, и в falsifier, и в тексте claim'а.

**F44 — ветка отказа прятала причину.**  `yeah-perm--mutating-tools` отказывал, когда объявления
инструментов неизвестны, и говорил только «the registry of the tools is not loaded»: человек, читающий
отказ, не мог на него подействовать — причиной может быть синтаксическая ошибка в модуле ядра.
**Что стало:** ошибка загрузки реестра хранится (`lib/yeah-risk.el`: `yeah-risk--failure`,
`yeah-risk-failure`), а отказ называет её (`lib/yeah-perm.el`: `yeah-perm--refusal-cause`).

**Новое обещание — и его собственный контроль.**  «Отказ называет причину» — **новый claim**
`a-refusal-names-its-cause` в `spec.json`, с проверкой своей и **контролем своим**: одно обещание —
один контроль, иначе контроль claim'а волны 98 (`sed` по `:risk "write"`) измерял бы другое
обещание.  Контроль: `sed -i 's|(error (setq yeah-risk--failure err))|(error nil)|'
lib/yeah-risk.el` — ошибка снова проглатывается, и проверка обязана упасть **своим** отказом.
**Измерено лично:** честное дерево — код 0 (432 мс); контроль, взятый из `spec.json` и применённый к
копии дерева, — код 1 со своим отказом («the refusal does not name the cause: REFUSAL=yeah-perm: the
risks of the tools are not known: the registry of the tools is not loaded»); файл после мутации
остаётся разбираемым (скобки сходятся).  Постоянная проверка — `tests/checks/
check-a-refusal-names-its-cause.el`: она копирует **только `lib/`** (копия дерева тащила бы в каждый
прогон гейта 74 МБ плагина оркестратора), ломает `yeah-result.el` в копии и спрашивает правило в
**дочернем** процессе Emacs — модуль, который уже загружен в этом Emacs, из копии не грузится
повторно, и ответ ребёнка — единственный ответ, который может быть о копии.

**Новый текст отказа — измерен.**  Было: «yeah-perm: the risks of the tools are not known: the
registry of the tools is not loaded».  Стало: «yeah-perm: the risks of the tools are not known: the
registry of the tools is not loaded: end-of-file: End of file during parsing: <копия>/yeah-result.el».

| # | что измерено | код |
|---|---|---|
| 1 | честное дерево: проверка F44 | 0 (432 мс) |
| 2 | контроль claim'а F44 на копии дерева: проверка падает **своим** отказом | 1 |
| 3 | честный отказ называет файл, который не загрузился, и ошибку его | — |

**Решение родителя (2026-11-21; правило вне §17.2 — владелец может отменить).**  Claim волны 100
правится «amended, not rewritten»: меняются **текст и falsifier**, а `id`, `requirements`, `control`,
`kind`, `phase`, `owner` и `register` — прежние.  **Область (`scope`) выросла потому, что вырос
предмет:** falsifier теперь достаёт до дерева поддержки (`tests/support/`), и каталог добавлен в
область.  Писатель волны предлагал область не трогать (решение останется за родителем — §6.5 его
отчёта); решение принято, и причина та же, что у claim'а документации: предмет вырос — значит, растёт
и область.

**Чего не проверяли.**  Живой маршрут волной не затронут (провод, цикл прогона, журнал); полный гейт
пакета {106, 107} — в §16.105.

### 16.104 Волна 107: стенды, которые меряют обещания дерева и жизни — **2026-11-21**

**Что это.**  Волна 107 закрывает четыре находки дискриминатора пакета волн 101–103 (§16.100): **F48**,
**F51**, **F52** и **F53**.  Код волны слит в `main` коммитом `8658313`; запись волны —
`waves/wave-107.json`.

**F48 — обещание о сокете зомби измерено стендом.**  Claim волны 101 обещает «сокет владельца-зомби
сносится, а владелец-зомби не принимается так, будто он жив» — это следствия, а не форма кода, и
ничем не измерялись.  **Что стало:** пятая часть проверки волны 101 — стенд поведения
`lib/yeah-life.el`: он подменяет только читателя состояния (`yeah-proc-state` через `cl-letf` и
`symbol-function`) таблицей стенда (зомби 999999999 → `"Z"`, живой 999999998 → `"S"`), а правило
ядра (`yeah-proc-alive-p`) остаётся под доказательством и выносит свой вердикт.  Хост не спрашивается:
pid стенда выше лимита ядра.

**F51 — «дерево читается один раз» и «дерево останавливается целиком» измерены.**  Три стенда в
шелл-проверке волны 102; `scripts/lib/tree.sh` **не менялся** — обе величины измеряются снаружи, через
существующий шов `PROC_ROOT`.  Счётчик стенда 8 сделан **вне** дерева под тестом (шелл стенда
трассирует себя `set -x`): одна скан дерева читает stat-файл каждого процесса ровно один раз, и
число трассированных строк `read_stat <pid>` равно числу сканов — **1**.  Стенд 9 строит настоящее
дерево процессов хоста и требует, чтобы **каждый** его процесс поймал сигнал; предусловия
проверяются явно (`process_group`), и если группа не та, стенд говорит «дерево не измерено», а не
молчит.

**F52 — страж «правило жизни процесса» widened до дерева и до признака.**  Falsifier claim'а волны
101 шире его измерения: страж читал два каталога и узнавал правило только по форме имени.  **Что
стало:** страж читает код всего дерева (`el`, `sh`, `ts`, `mjs`, `js`) через
`directory-files-recursively` (свой обход вызывал функцию Elisp на каждый файл и умирал с
`excessive-lisp-nesting (1601)` на каталоге в 115 файлов); документы не читаются — документ
**называет** правило, программа его **определяет**; узнаваний два — форма имени (расширена:
`-alive-p` и аргумент, называющий `pid` или `process`) и **признак** (файл, который читает состояние
процесса и держит буквы жизни, решает жизнь сам, как бы его функции ни назывались); два исключения
названы в коде — `lib/yeah-proc.el` и стенд правила.  На честном дереве признак срабатывает ровно на
двух файлах, ложных срабатываний нет.

**F53 — страж документации читает записи волн.**  `yeah-check--records` = `waves/*.json` (114 файлов).
Правило раздела работает для **названного** файла, а не для того, который читается.  **Правило
файла к записям не применяется:** запись — документ прошлого, она называет файлы дня своей волны, и
файл, который после этого дня переехал или исчез, назван записью и дефектом записи **не** является.
**Измерено:** честный прогон 702 мс → **744 мс** (+42 мс) — **это измерение снимком**: «до» и «после»
измерены на дереве с **108** записями (2026-11-21, до записей волн 106 и 107), и дерева, где «до» ещё
не читало записи, больше нет — дельту обновить нечем.  **Замеры приведены к текущим:** записей
сегодня **114** (**698 КБ**) — читаются целиком, так и задумано.

**Два старых дефекта записей — названы и не починены.**  Если бы правило файла применялось к
записям — и больше ничего не менялось, — страж нашёл бы в них **два** имени, которых на диске нет:
имя модуля поддержки **до** его переезда в `lib/yeah-proc.el` (запись `waves/wave-101.json`) и
сокращённое имя сессии из трёх точек (запись `waves/wave-64.json`; сама запись это отмечает).
**Правка числа (2026-11-21; находка дискриминатора пакета — §16.106).**  Запись волны 107 называла цену
**семью** именами, и это было измерено со **снятым правилом игнора**; а страж спрашивает у git об
игнорируемых именах **раньше**, чем спрашивает, документ ли это запись, — и потому пять остальных
имён, которые записи называют (вывод прогона: `bench/results`, `tests/artifacts` и
`bench/results/20261115T150251Z.jsonl` в записи `waves/wave-63.json`), молчат уже сегодня.  **Семь —
это число имён, которые записи называют, а не число отказов, которые дал бы страж:** то же правило
игнора молчит и о **документах настоящего** — `docs/PLAN.md` называет `bench/results`,
`tests/artifacts` и `plugin/yeah-provider/node_modules`, а `docs/PLAN.md` — документ настоящего, и
правило файла к нему применяется; страж зелёный.  **Измерено (2026-11-21, на двух копиях
репозитория — рабочее дерево и свежая копия):** снято только исключение записей — **2** отказа, и это
верно **и в рабочем дереве, и в свежей копии**, где каталогов вывода прогонов нет; снято и правило
игнора — **7** отказов из записей **в свежей копии** (пять из них — вывод прогонов, которого в свежей
копии нет) и **2** — **в рабочем дереве**, где эти каталоги на диске.  **Число отказов в документах
настоящего назвать нельзя:** оно считает упоминания **в том самом документе, который его приводит**, и
потому движется вместе с текстом.  **Точный список имён — в записи
волны 107:** запись — документ прошлого, и к ней правило файла не применяется.  Ни одно из имён не
является дефектом **сегодня**, и ни одно не починено этой волной: записи волн ей не принадлежат, а
решение о правиле файла для записей — за владельцем.

**Решение родителя (2026-11-21; правило вне §17.2 — владелец может отменить).**  Claim документации
был **строже** измерения, чем обещал: страж читал записи, а область claim'а (`waves/`) их не
называла.  Claim правится «amended, not rewritten»: **текст и falsifier** меняются, **`scope`
дополняется** каталогом `waves` (предмет вырос — записи волн стали документами), а `id`,
`requirements`, `control`, `kind`, `phase`, `owner` и `register` — прежние.  Текст и falsifier прямо
говорят, что страж записи читает, а правило файла к ним не применяется.

**F47 остаётся открытым (часть `a`).**  Правило «stat-файл процесса читает один модуль ядра»
оставлено в области `lib/`: читающий stat-файл чек волны 100 — это F47, его файл этой волне не
принадлежит, а расширение правила на всё дерево задело бы чек волны 100 и увело бы волну 107 в
чужую находку.  Текст claim'а волны 101 **назван** исключением — иначе буквальное прочтение обещания
опровергается той же проверкой, что его доказывает.

**Правка после гейта пакета.**  Гейт пакета {106, 107} отверг claim `a-process-that-is-dead-is-dead-everywhere`: widened-страж F52 читал **установленные зависимости** репозитория (74 МБ в `plugin/yeah-provider/node_modules`) и отверг три файла чужого кода — ложный отказ с ложным предметом.  **Обещание claim'а не менялось:** оно говорило «another file **of the repository**», а страж мерил **больше**, чем обещал.  Починка — сузить измерение до обещания — и её измерения в §16.105.

**Чего не проверяли.**  Полный гейт пакета {106, 107} — в §16.105; живой маршрут волной не затронут.

### 16.105 Пакет волн 106 и 107: красный гейт, две починки и живой прогон — **2026-11-21**

**Что это.**  Пакет из двух волн: волна 106 (F43 и F44, §16.103) и волна 107 (F48, F51, F52 и
F53, §16.104).  Код обеих волн слит в `main` (`da7def9` и `8658313`), артефакты пакета — коммитом
`6b6f484`.  Это запись пакета: гейт и то, что он нашёл, две починки, живой прогон и числа, которые
устарели.

**ГЕЙТ ПАКЕТА БЫЛ КРАСНЫМ.**  Гейт шёл на юните `yeah-gate-106-107` (старт 16:58:32 UTC, 17 минут)
и закончился кодом 1.  Лог прочитан по трём меткам §19.1 п. 7:

| форма | что означает | сколько |
|---|---|---|
| 1 | провал положительного прогона (красный) | **2** |
| 2 | укус отрицательного контроля (зелёный) | 167 |
| 3 | провал постановки контроля | **0** |

Формы 3 не было ни одной: ни один контроль не был поставлен неверно.  Форма 1 была **дважды**, и оба
раза по существу, а не из-за окружения.  **Счёт, который сходится:** в `spec.json` **170 требований**,
и в каждом из двух гейтов ровно **169 строк** `mathc:` — по строке на каждое требование, у которого
есть проверка и контроль.  Одно требование — человеческий суд (claim о решении владельца), у него нет
ни проверки, ни контроля.  В первом гейте эти 169 строк разошлись так: **167 укусов и 2 красные
линии** — контроль claim'а, у которого положительный прогон упал, не выполняется вовсе.  Во втором
гейте — 169 укусов и ни одной красной линии.

**Провал 1 — картина слоёв указывала на строку, которой больше нет.**  Claim
`the-layer-diagram-points-at-files-that-exist` отвергнут: «the diagram names `lib/yeah-risk.el:94`,
and that line carries no definition».  **Причина — волна 106:** она добавила в `lib/yeah-risk.el`
хранилище ошибки загрузки реестра (`yeah-risk--failure`) и функцию `yeah-risk-failure`, и определение
уехало со строки 94 на строку 90.  Картина слоёв (`site/diagrams/core-layers.puml`) называла старую
строку, и страж картины — ровно та проверка, которая ловит такую рассинхронизацию, — её отверг.

**Починка 1.**  `site/diagrams/core-layers.puml` называет теперь строку 90 (коммит `da8f6ea`).
Проверка зелёная: код 0 (246 мс).

**Провал 2 — widened-страж волны 107 читал чужой код.**  Claim
`a-process-that-is-dead-is-dead-everywhere` отвергнут тремя отказами:

```
dead-process: the file plugin/yeah-provider/node_modules/typescript/lib/typescript.js decides the life of a process by itself: the rule of the life of a process is one function of the kernel (yeah-proc-alive-p)
dead-process: the file plugin/yeah-provider/node_modules/typescript/lib/_tsc.js decides the life of a process by itself: the rule of the life of a process is one function of the kernel (yeah-proc-alive-p)
dead-process: the file plugin/yeah-provider/node_modules/tsx/dist/cli.mjs decides the life of a process by itself: the rule of the life of a process is one function of the kernel (yeah-proc-alive-p)
```

**Причина — волна 107 (F52):** страж «правило жизни процесса» расширен с двух каталогов на всё
дерево, и обход зашёл в `plugin/yeah-provider/node_modules` — 74 МБ **установленных зависимостей**,
которые репозиторий **игнорирует** (`.gitignore`).  Файлы компилятора TypeScript читают
`/proc/<pid>/stat` и держат буквы `S` и `R`, и признак срабатывает.  Это **ложный отказ с ложным
предметом**: чужой код зависимости не «второе правило жизни процесса», и репозитория он не часть.
Обещание claim'а говорило «another file **of the repository**» — страж мерил **больше**, чем
обещал.

**Починка 2 — страж меряет репозиторий.**  Граница **спрошена, а не угадана**: проверка спрашивает
git, какие каталоги репозиторий игнорирует, и не заходит в них.  В дереве проекта ответ — четыре
каталога: `.math/`, `bench/results/`, `plugin/yeah-provider/node_modules` и `tests/artifacts/`.  **Если
git не может сказать, проверка отказывается с названной причиной**, а не проходит молча.  Файл с
признаком внутри игнорируемого каталога страж не видит; файл с признаком в `tests/support/` и
**неотслеживаемый, но не игнорируемый** файл в `lib/` — видит: модуль, который разработчик забыл
добавить в индекс, грузится ядром, и страж обязан его видеть.

**Решение родителя (2026-11-21; правило вне §17.2 — владелец может отменить).**  Граница стража —
не список имён, а ответ самого репозитория: код установленной зависимости и вывод прогона — не код
проекта.  **Цена границы названа:** правило жизни процесса, спрятанное в установленной зависимости,
страж не увидит.  Починку сделал воркер (отчёт `/tmp/writer-107-guard-report.md`), решение и границу
— родитель.

| # | что измерено | код |
|---|---|---|
| 1 | честное дерево с 74 МБ `node_modules`, **до** починки: 3 ложных отказа | 1 (13 576 мс) |
| 2 | честное дерево **после** починки: отказов нет | 0 (1 043 мс) |
| 3 | контроль claim'а (команда из `spec.json` дословно): семь отказов о предмете | 1 |
| 4 | тот же контроль в копии, которую делает метод: те же семь отказов | 1 |
| 5 | файл с признаком внутри игнорируемого каталога: молчит | 0 |
| 6 | тот же файл в `tests/support/`: отказ с именем файла | 1 |
| 7 | тот же файл в `lib/` (неотслеживаемый, не игнорируемый): отказ с именем файла | 1 |
| 8 | дерево без `.git`: отказ назван | 1 |
| 9 | соседняя проверка волны 100; `byte-compile-all` | 0 / 0 |

**ЖИВОЙ ПРОГОН.**  Один прогон через оркестратор Paseo на дереве пакета (`6b6f484`): модель
`MiniMax-M3.1-Flash`, режим `build`, промпт «Ответь только словом OK и вызови finish. Больше ничего
не делай.», ответ «OK», 16:53:53–16:53:57 UTC (4 с), двенадцать записей журнала.  Сервис был
перезапущен на дереве пакета перед прогоном: юнит `yeah-acp-service` стартовал в 16:53:33 UTC, сокет
`/tmp/yeah-1001/yeah-service-paseo.sock` создан в 16:53:34 UTC, а коммит `6b6f484` — в 16:51:45 UTC.
Полная запись — `docs/LIVE-EVIDENCE.md`, «The live run of the package of the waves 106 and 107».

**ЧИСЛА, КОТОРЫЕ УСТАРЕЛИ.**  Число записей волн и их размер были измерены в дереве писателя волны
107 (там записей было **108**) и перенесены в запись как измеренные в дереве, куда запись попала, — а
там записей **110**, потому что записи волн 106 и 107 пришли тем же коммитом.  Правило чисел волны
104 применено: **замеры приведены к текущим** (110 записей, 667 КБ — **снимок того дня**; нынешние
числа названы в §16.104) в §16.104, в пуле `AGENTS.md` и в
записи `waves/wave-107.json`; **дельта времени** (702 мс → 744 мс) — измерение дерева, которого
больше нет, и она **помечена как снимок** (коммит `7622d79`).

**ПЕРЕГЕЙТ ПАКЕТА.**  Второй гейт шёл на дереве после двух починок: юнит `yeah-gate-106-107-b`,
старт 17:34:39 UTC, конец 17:51:38 UTC (17 минут), лог `/tmp/w106-107-gate2.log` (4910 строк), код
выхода **3**.  Разбор по трём меткам §19.1 п. 7:

| форма | что означает | сколько |
|---|---|---|
| 1 | провал положительного прогона (красный) | **0** |
| 2 | укус отрицательного контроля (зелёный) | **169** |
| 3 | провал постановки контроля | **0** |

**Оба упавших claim'а теперь кусаются.**  В логе есть строки формы 2 и для них: строка 4838 —
`check-the-layer-diagram-points-at-files-that-exist`, строка 4885 —
`check-a-process-that-is-dead-is-dead-everywhere`.  То есть починки не просто сняли красные линии:
контроли, которые в первом гейте не выполнялись вовсе, теперь выполняются и кусаются.  Это и было
тем, чего требовал гейт.

**Почему код выхода 3, а не 0.**  Код 3 — это `unknown` по шкале метода (`scripts/dev`, A13/A14), и
причина **не в коде пакета**: устарело доказательство claim'а
`the-owner-decided-the-order-of-the-next-waves` — материалы изменились, потому что `docs/PLAN.md`
изменён записями пакета.  Это тот же предмет, что и в §16.68: claim, который ждёт человека
(требование — `kind: review, spec: owner`), честно делает вердикт не-`green`; метод различает `pass`
и не-`pass` и не различает «всё доказано» и «всё доказано, кроме одного пункта, который решает
человек».

**Что осталось до зелёной карты — ровно одна вещь, и она не в коде.**  Запись решения владельца:
она связывает уже принятое решение (2026-11-16, 2026-11-19, 2026-11-20) с материалами этого дерева.
Порядок §16.68: правка документации → пересчёт → запись владельца → карта.  Команда:

```
mathc record the-owner-decided-the-order-of-the-next-waves owner --by az --outcome pass
```

Запись идёт **последней** — после всех правок документации, иначе она устареет снова (урок §16.64).
Измеренный вердикт карты после этой записи — `docs/LIVE-EVIDENCE.md`, «The gate of the package of the
waves 106 and 107».

### 16.106 Дискриминатор пакета волн 106 и 107: PASS и одна несущественная находка — **2026-11-21**

**Что это.**  Независимый проверяющий (агент-дискриминатор) прошёл пакет волн 106 и 107 **вторым
прогоном** и на этот раз **вынес вердикт**: **PASS**.  Первый прогон по этому пакету был **отрезан
провайдером** (`terminated`) до вердикта; его отчёт уцелел (`/tmp/discriminator-106-107-report.md`,
140 строк) и дал три находки — **F59**, **F60**, **F61**, — которые родитель починил тремя коммитами
документации (`23d8eda`, `83320ed`, `bee135a`).  Второй прогон проверял именно эти починки и ту часть
первого прогона, которая осталась непроверенной, — стенды F51.  Отчёт второго прогона:
`/tmp/discriminator-106-107-report-2.md` (вердикт — на восьмой строке, чтобы отчёт был пригоден, даже
если агента отрежут снова).

**Дерево.**  Ветка `fix/wave-106-107-discriminator-findings`, HEAD `bee135a`, `git status --porcelain`
пуст, HEAD не двигался; все мутации — на копиях в `/tmp/disc-106-107-2/`.  Репозиторий не изменён.

**Что подтверждено.**

* **F59 — цена применения правила файла к записям волн = два имени.**  Снято только исключение
  записей → ровно **2** отказа, оба из записей; снято и правило игнора → ровно **7** отказов из
  записей, и пять из них — имена, которые называет запись `waves/wave-63.json`.  Причина названа рядом
  и она верна: страж спрашивает у git об игнорируемых именах **раньше**, чем спрашивает, документ ли
  это запись.  Слово «семь» нигде в репозитории не осталось как цены.
* **F60 — размер записей.**  Измерение на дереве `bee135a` — **снимок**: 682 888 Б = 666.88 КиБ → 666;
  во всех четырёх местах стояло 666, и неподвижная точка держалась (правка цифр не меняет длину).
  **После правок F62 и §16.106 записи выросли**, и число приведено к текущему (правило волны 104:
  замеры приведены к текущим): 683 314 Б = 667.30 КиБ → **667**.
* **F61 — раздел гейта в `docs/LIVE-EVIDENCE.md` построчно правдив.**  Старты 16:58:32 / 17:34:39 /
  17:56:41, коды выхода 1 / 3 / 3, три формы по каждому из трёх логов, 169 строк `mathc:`, 170
  требований в `spec.json`, укусы двух упавших claim'ов на строках 4838 и 4885, отказы на строках
  4886–4888 (три файла установленной зависимости, 74 МБ), причина кода выхода 3, запись решения
  владельца в 18:14:35, слияние в 18:15:29 и побитовое совпадение деревьев `ca163860…` и `9c08266`.
  Висячей ссылки §16.105 больше нет.
* **F51 — стенды 8, 9 и 10 живы.**  На каждом из них дефект кода под тестом роняет проверку (код 1 с
  точным отказом), а при выключенном стенде тот же дефект проходит **молча** (код 0).  Ни один стенд
  не подменяет предмет: вердикт выносит код под тестом (`scripts/lib/tree.sh`, который с `6b6f484` не
  менялся — diff пуст), а счётчик стенда 8 сделан **вне** дерева под тестом, через существующий шов
  `PROC_ROOT`.  Предусловия групп проверяются явно: при неверной группе стенд говорит («the tree is
  not measured»), а не молчит.

**F62 (несущественная) — число «11 отказов из `docs/PLAN.md`» не воспроизводилось.**  Запись волны
107, пуля `AGENTS.md` и §16.104 называли обоснованием починки F59 измерение «снято и правило игнора —
7 отказов из записей и **11** из `docs/PLAN.md`».  Дискриминатор повторил измерение на **собственной
копии** и получил из записей 7 ✓, а из `docs/PLAN.md` — **17** (на дереве, где запись живёт, — **20**);
ни одно прочтение не даёт 11.  **Родитель перемерил сам** (две копии репозитория, 2026-11-21) и
подтвердил расхождение: в **рабочем дереве**, где каталоги вывода прогонов на диске, — 4 отказа из
`docs/PLAN.md` и **2** из записей; в **свежей копии** репозитория, где этих каталогов нет, — 20 отказов
из `docs/PLAN.md`, 24 из `docs/LIVE-EVIDENCE.md`, 4 из `docs/PLAN-NEXT.md`, 1 из `README.md` и **7** из
записей.  Числа 17 и 20 — **снимки** измерений на названных деревьях, а не постоянные величины.

**Вывод починки не меняется и крепнет:** цена применения правила файла к записям — **два имени**, и
это верно **и в рабочем дереве, и в свежей копии** репозитория (правило игнора молчит о пяти именах
вывода прогонов в обоих состояниях: в рабочем дереве эти каталоги на диске и имена разрешаются, в
свежей копии их нет и молчит правило игнора).  **Починка F62 (2026-11-21).**  Число отказов в
документах настоящего **убрано из записей**: оно считает упоминания **в том самом документе, который
его приводит**, и потому движется вместе с текстом — такое число нельзя назвать в записи, не сделав её
ложью на следующий день.  Осталось сказано то, что не движется: **цена — два имени**; **семь — это
число имён, которые записи называют**, а не число отказов; правило игнора молчит и о документах
настоящего (`docs/PLAN.md` называет `bench/results`, `tests/artifacts` и
`plugin/yeah-provider/node_modules`, и страж зелёный).

**Методическая оговорка — два неверных числа в одном пакете.**  Первая попытка дискриминатора снять
правило игнора была **неверной**: `unless` разворачивается в `(if COND nil BODY)`, и условие `t`
**выключает** тело, а не включает его, — число отказов вышло ложным, и мутацию пришлось переделать
(правильная — `ignored` → `nil`).  Второе неверное число — «11» родителя: его не воспроизводит ни
одно чтение, и метод, которым оно получено, не был записан.  **Оба случая — одно и то же: мутация
проверяется на то, что она делает, а не на то, что код после неё запускается.**  Случай дискриминатора
был пойман раньше (неверная мутация не дала укуса), случай родителя — позже (неверное число стояло в
записи, пока его не перемерили).

**Что осталось открытым по пакету.**  **F47** (часть `a`) — правило «stat-файл процесса читает один
модуль ядра» осталось в области `lib/`, и сказано честно.  **Цена границы F52 названа:** правило
жизни процесса внутри установленной зависимости страж не увидит.  **Решение владельца** — применяется
ли правило файла к записям волн — не принято, и ни одно из семи имён не починено волной.

**Побочно, не дефект записи.**  Юнит гейта 2 (`yeah-gate-106-107-b`) записал вердикт в 17:51:38
(код 3), но сам остался жив и был убит systemd в 17:53:08 («State 'stop-sigterm' timed out. Killing»).
Длительность гейта в §16.105 указана верно (17:34:39 → 17:51:38), но юнит убирали принудительно.


### 16.107 Пакет волн B2, B3, C2 и C3: контракт инструмента и области согласования — **2026-11-22**

**Что это.**  Пакет из четырёх волн догоняющего плана (`docs/ARCHITECTURE-CATCHUP-PLAN.md`,
треки B и C): **B2** (ресурс, который объявляет инструмент, и блокировка этого ресурса),
**B3** (таймаут и лимит вывода, которые объявляет инструмент), **C2** (носитель каждой области
согласования и файл, который её держит) и **C3** (область ответа — в интерфейсе и в ACP).
Волны слиты в ветку пакета `feat/waves-b2-b3-c2-c3`: B2 — `90c1bbd`, C2 — `c7b61d4`,
B3 — `baec0d3`, C3 — `a890509`.  После слияния — герметичность чеков (`619a3fe`),
записи волн (`d4d0930`, `ed84210`), claim'ы (`5b26958`, `8bd6083`), перепривязка якорей
картины слоёв (`47a49db`), правка трёх устаревших текстов (`066c5bc`), живой прогон
(`5bb8817`) и починка картины (`ca71ae7`).

**ГЕЙТ ПАКЕТА БЫЛ КРАСНЫМ.**  Гейт шёл на юните `yeah-gate-b2-b3-c2-c3` (старт 08:13:31 UTC,
20 минут) и закончился кодом 1.  Второй гейт (юнит `yeah-gate-b2-b3-c2-c3-b`, 08:37:01 —
08:55:22 UTC, дерево `ca71ae7`) закончился кодом 0.  Логи прочитаны по трём меткам
§19.1 п. 7:

| форма | что означает | гейт #1 | гейт #2 |
|---|---|---|---|
| 1 | провал положительного прогона (красный) | **2** | **0** |
| 2 | укус отрицательного контроля (зелёный) | 171 | **173** |
| 3 | провал постановки контроля | **0** | **0** |

Формы 3 не было ни разу: ни один контроль не был поставлен неверно.  Формы различаются **по
содержимому**, а не по счётчику: `mathc: <команда> exited N` — провал самого верификатора,
`mathc: verifier after negative control: <команда> exited N` — контроль кусается (это
ожидаемая зелёная форма).

**Счёт, который сходится.**  В `spec.json` **172 claim'а** и **174 требования**, из которых
**173 — `verifier`** и **одно — `review`** (claim `the-owner-decided-the-order-of-the-next-waves`,
человеческий суд: у него нет ни проверки, ни контроля).  Оба гейта дали ровно **173 строки
`mathc:`** — по строке на каждое требование-`verifier`.  В первом гейте эти 173 строки
разошлись так: **171 укус и 2 красные линии** — контроль claim'а, у которого положительный
прогон упал, не выполняется вовсе.  Во втором гейте — **173 укуса и ни одной красной линии**.

**Провал 1 — картина слоёв указывала на строку, которой больше нет.**  Claim
`the-layer-diagram-points-at-files-that-exist` отвергнут: «layer-diagram: the diagram names
`lib/yeah-product.el:258`, and that line carries no definition».  **Причина — родительская
правка текста волны B2:** правка трёх устаревших текстов (`066c5bc`) сдвинула строки в
`lib/yeah-product.el`, и определение `yeah-product-open` уехало со строки 258 на строку 259.
Картина слоёв — файл владельца, и страж картины — ровно та проверка, которая ловит такую
рассинхронизацию, — её отверг.

**Починка 1.**  `site/diagrams/core-layers.puml` называет теперь строку 259 (коммит `ca71ae7`).
Проверка зелёная: код 0.

**Провал 2 — гейт убитого прогона не дошёл до конца карты.**  Claim
`a-gate-run-needs-no-watchdog` отвергнут единственным отказом: «gate: the map of the run did
not reach the end».  Вывод гейта в логе: `/home/az/Projects/yeah/scripts/live-pilot: line 181:
801 Killed "$@"` и `scripts/gate: the run was killed (code 137); it is started again (attempt 2
of 3)`.  **Это не воспроизвелось у родителя:** чек измерен пять раз вне гейта — дважды на
рабочем дереве, один раз в копии `/tmp/repro-gate` (exit 0, 6932 мс — как в гейте, 6958 мс) и
трижды под нагрузкой (четыре булевых цикла, load average 8–10) — и всегда exit 0.  Во втором
гейте тот же чек дал **укус** (форма 2), то есть зелёную метку.  **Дискриминатор пакета
воспроизвёл отказ** (2 раза из ~120 прогонов, ≈2 %) и измерил, что он означает — **см.
§16.108**, там же и починка самого чека.

**Живой прогон на дереве артефактов пакета** (08:11:53 — 08:12:21 UTC, 28 секунд, журнал
`session-1-2b20f6`, дерево `ed84210`, модель `MiniMax-M3.1-Flash`, режим `build`) — запись в
`docs/LIVE-EVIDENCE.md`, «The live run of the package of the waves B2, B3, C2 and C3».
**Вопрос по проводу принёс пять опций C3** — `allow-once`, `allow-session`, `allow-project`,
`allow-global`, `reject-once`; ответы `todo_list` и `bash` принесли свои области (`once` и
`session`), решение по `read` приняло ядро само («read is a safe read»), а `finish` — правило
ядра, без ответа и без области.  **Правило ответа `session` осталось в памяти сессии:**
ни `~/.config/yeah/rules.json`, ни `.yeah/rules.json` не появились.

**Живой прогон на финальном дереве нашёл дефект, который гейт не увидел.**  Третий живой
прогон пакета (10:19 — 10:29 UTC, журналы `session-1-ba29b2` и `session-2-181cb`) повторил
форму предыдущего и **повесил прогон**: модель попросила `bash` с `idle` в 10 000 секунд, а
инструмент объявляет предел в 120 секунд.  **Отказ по имени — обещание волны B3 — не дошёл до
модели.**  Вместо него модель прочитала «the call of \"bash\" exceeded its timeout of 120
seconds» — через **120 секунд** после вопроса, и то только потому, что таймер планировщика
закрыл висящий вызов.  Модель спросила снова с теми же аргументами, и так пять раз: прогон
сжёг десять минут и ничему не научил модель.

**Причина — измерена, а не угадана.**  Вызов, который ждёт человека, отправляется в работу
**после** ответа, и этот момент лежит **вне** обработчика планировщика: отказ реестра на
неподходящие аргументы (`lib/yeah-tools.el`, `yeah-tools--check-durations`) уходил из поворота,
вызов оставался незакрытым, и закрывал его только таймер планировщика — с сообщением о
**другой** причине.  На пути, где человека не спрашивают (решение по правилам), отказ
доходил до модели как надо: **проба 7 чека `check-a-tool-declares-its-own-limits.el` меряет
именно это и была зелёной.**  Покрыт был только путь без человека.

**Починка 2.**  Отправка отложенного вызова под стражей (`lib/yeah-turn.el`,
`yeah-turn--dispatch-guarded`): отказ реестра закрывает вызов **тем самым отказом, который
называет инструмент и предел**, — так же, как на пути без человека (коммит `45b5606`).  Чек
пределов инструмента доказывает теперь **девятое**: отложенный вызов, который не подходит под
декларацию, отказывается по имени (проба 9).  **Контроль новой пробы измерен:** со снятой
стражей чек падает кодом 1 с отказом «the call that asked for more work than the tool declares
was not refused by name when a person was asked: nil» — модель не прочитала ничего, потому
что вызов висел; со стражей чек зелёный.  **Зарегистрированный контроль claim'а
`a-tool-declares-its-own-limits` кусается по-прежнему** (три отказа в своём чеке), и после
отката чек снова зелёный.  **Проба назвала потом свой предмет** — независимый верификатор нашёл
(`§16.109`), что проба девятая не проверяла, что путь был отложенным, и починка `09a1371`
делает пробу отказывающейся, когда журнал прогона держит одно решение о разрешении вместо двух.

**Живой прогон после починки доказал её на настоящем маршруте** (10:30:53 — 10:32:13 UTC,
журнал `session-1-f4a370`, дерево `45b5606`): та же форма, тот же неподходящий `idle` (5000) —
и **отказ по имени дошёл до модели за 13 секунд** («Error: yeah-tools-call: "bash": the idle of
5000 seconds is more than the timeout of 120 seconds the tool declares»).  **Модель после
этого исправила вызов** (`idle` 10, `timeout` 120), вызов **отработал** («/home/az/Projects/yeah»),
и прогон закончился через `finish` с итогом задачи.  Это и есть разница: не «таймаут вместо
отказа», а отказ, который модель читает и на который отвечает.

**Что ещё измерено на слитом дереве.**  Шесть контролей claim'ов пакета — взятые **дословно из
`spec.json`** — кусаются поимённо, и проверка после отката снова зелёная:

| claim | контроль | отказ |
|---|---|---|
| `two-calls-on-one-resource-do-not-overlap` | `:tool-resource nil` в `lib/yeah-turn.el` | «the two calls on one resource overlapped» |
| `a-tool-declares-its-own-limits` | `(min declared yeah-result-output-limit)` → `yeah-result-output-limit` | три ассертации о пределе |
| `a-scope-decides-where-the-rule-lives` | файл правил заменён на файл пользователя | отказ по имени файла |
| `the-question-offers-the-scope` | `(:project :project)` → `(:project :global)` | пять названных отказов |
| `approvals-have-reply-kinds` | `(("always" . "session"))` → `(("always" . "global"))` | три отказа в своём чеке и восемь в двух других |
| `one-approval-surface` | `(yeah-approval-answer` → `(ignore` | `FAILED 4/12 yeah-both-paths-ask-in-the-approval-view` |

**Герметичность чеков.**  Решение родителя (2026-11-22): каждый чек получает от раннера свой
пустой `XDG_CONFIG_HOME` (`mktemp -d`, удаление в конце; при невозможности — код 2 с названной
причиной), а чек `check-approvals-have-reply-kinds.el` в конце зовёт
`yeah-perm-rules-reset-for-test` и проверяет, что не оставил правил.  **Цена названа:** вердикт
проверки зависит от кода, а не от состояния машины, — и потому проверка не может «позеленеть»
из-за чужого файла правил.  Дискриминатор измерил это отдельно: восемь проверок пакета и юнит
прогнаны **дважды подряд** — 18/18 зелёные, и **20 срезов состояния** файлов правил — во всех
файла правил нет.

**Чего не проверяли.**

* **Блокировка ресурса — блокировка ядра, а не файловой системы.**  Два процесса не из этого
харнесса ей не подчинены, а инструмент, пишущий файл вне своей декларации, ею не ловится.
* **Ресурс объявляется руками.**  Реестр отказывает декларации, которая не строка, по имени, но
он не может знать, что два инструмента объявили один файл двумя написаниями.
* **Ожидание — это ожидание, а не отказ.**  Ничто не меряет, сколько ожидание может длиться.
* **Инструмент без ресурса не сериализуется вовсе**, и волна говорит об этом, а не притворяется.
* **Таймаут — предел ожидания ядра, а не убийство процесса.**  Ядро перестаёт ждать вызов и
закрывает его провалом, который называет предел; процесс, который не входит в ядро, живёт своей
жизнью.
* **Действующий лимит вывода — меньший из объявленного и глобального** (`yeah-result-output-limit`,
32768): объявление никогда не поднимает глобальный потолок.
* **Ответ `session` — это память носителя пути**, и на простом пути (не ACP, не прогон) носителем
является файл пользователя: область `session` разрешается в область носителя, а не хранится
сама по себе.
* **Отказ реестра теперь доходит до модели на обоих путях** — и на пути без человека, и на пути,
где человека спрашивают, — **но только когда отказ случился при отправке вызова.**  Отказ,
случившийся **до** вопроса (неизвестный инструмент, неподходящий тип аргумента), по-прежнему
не измеряется: реестр отказывает при отправке, и до человека вопрос доходит.
* **Одна волна, один живой прогон, один промпт, один провайдер.**  Прогон не доказывает обещаний
пакета: claim'ы меряются их собственными проверками и контролями, а гейт покрывает дерево
целиком.

### 16.108 Дискриминатор пакета волн B2, B3, C2 и C3: PASS и восемь находок — **2026-11-22**

**Что это.**  Независимый проверяющий (агент-дискриминатор) прошёл пакет волн B2, B3, C2 и C3 и
вынес вердикт: **PASS с находками**.  Отчёт: `/tmp/discriminator-b2-b3-c2-c3-report.md` (476 строк,
вердикт — на третьей строке, чтобы отчёт был пригоден, даже если агента отрежут).

**Дерево.**  Ветка `feat/waves-b2-b3-c2-c3`, HEAD `ca71ae7`, `git status --porcelain` пуст — на
момент начала и на момент записи.  Все мутации — на копии дерева `/tmp/disc-b2b3c2c3`
(`cp -a`, тот же HEAD).  **Репозиторий не изменён.**

**Что подтверждено.**

* **Все шесть зарегистрированных контролей кусаются.**  Код возвращается в 0 после отката,
  отказ называет свой предмет, ни один контроль не приводит к 255 в сыром коде Emacs.
  Контроли брались **дословно из `spec.json`**.
* **Герметичность пакета.**  Восемь проверок пакета и юнит прогнаны **дважды подряд** — 18/18
  зелёные; **20 срезов состояния** файлов правил — во всех файла правил нет.
* **Числа гейтов совпали с числами родителя, и код выхода с ними согласован** (§16.107).
* **Вторая красная строка гейта #1 — настоящий дефект, а не шум** (картина слоёв,
  `ca71ae7`), а не однократный шум.
* **Все десять сдвинутых якорей картины слоёв несут то же определение**, что несли прежние
  строки.
* **Таблица живого прогона совпадает с журналом** (`session-1-2b20f6`, 36 записей) — ни одной
  ложной строки.
* **Словарь ответов, надписи и wire-имена совпадают с обещанием claim'а.**
* **Таблица носителей корректна** (`lib/yeah-perm.el:143-148`): ровно по одному носителю на
  каждый scope.
* **Записи волн не содержат ложных утверждений о коде.**

**Находки.**

| # | что | где |
|---|---|---|
| **F1** | **дефект проверки (отказ с ложным предметом)** — «ничего не осталось» сканирует всю машину и не привязано к своему прогону | `tests/checks/check-a-killed-gate-run-restarts-and-reaches-the-end.el:239` |
| **F2** | **дефект записи (средний)** — модуль и норматив говорят об `always` разное | `lib/yeah-approval.el:24-29` |
| **F3** | **дефект обещания (средний)** — текст claim'а `approvals-have-reply-kinds` внутренне противоречив | `spec.json`, claim `approvals-have-reply-kinds` |
| **F4** | **дефект записи (низкий)** — оставшиеся перечисления старого словаря | четыре места |
| **F5** | **дефект проверки (низкий)** — альтернативный контроль `approvals-have-reply-kinds` умирает, а не отказывает | `tests/checks/check-approvals-have-reply-kinds.el` |
| **F6** | **пробел в доказательствах (низкий)** — код отказа диспетчера `-32602` не закреплён | `tests/unit/test-yeah-acp.el:578-588` |
| **F7** | **пробел в доказательствах (низкий)** — атомарность записи правил объявлена, но не измеряется | `waves/wave-c2.json`, `tests/checks/check-a-scope-decides-where-the-rule-lives.el` |
| **F8** | **дефект проверки (средний)** — проверка убитого гейта не может отличить «карты нет» от «карта не дошла», и «гейт ответил 0» не доказывает, что карта записана | `tests/checks/check-a-killed-gate-run-restarts-and-reaches-the-end.el`, `scripts/gate`, `tests/support/yeah-fake-method.sh` |

**Починки.**

**Починка F3 (родитель, 2026-11-22).**  Перечисление в тексте claim'а называло `always` на
месте `global` — «answered once, for the session, for the project, always or reject», — а через
полслова та же фраза объявляла `always` легаси-именем ответа `session`.  **Обещание claim'а
противоречило само себе**, а `spec.json` — норматив репозитория.  Правлен **только текст**:
перечисление называет now «once, for the session, for the project, **for the user** or reject»,
а второе предложение — «the rule of the answer **global** in the file of the user» — осталось
прежним.  `falsifier`, `control`, `scope`, `requirements` и `id` — **прежние**: обещание не
изменилось, изменилось только его перечисление; контроль по-прежнему совпадает с кодом и по
прежнему кусается (прецедент §16.101 — правится то, что разошлось, а не всё подряд).

**Починки писателя (2026-11-22).**  Ветка `fix/discriminator-b2-b3-c2-c3`, восемь коммитов, слита в
ветку пакета (`43a68e9`, 10 файлов, +346/−92).  Отчёт: `/tmp/fix-b2-b3-c2-c3-report.md` (488 строк,
вердикт — на третьей строке).  К починкам относится то же правило, что и к F3: **правка обещания —
только текст; код — по замеру.**

| # | что починено | коммит | чем измерено |
|---|---|---|---|
| **F1** | предмет «ничего не осталось» больше не сканирует всю машину | `baa2dcf` | ложный предмет (посторонний процесс, который только **упоминает** путь подставного метода): на дереве до починки — отказ «the run of the gate was left behind when the gate answered: (5293)», на починенном — 0; истинный предмет (процесс прогона, который остался): на починенном — «the pids (5065) are still alive a moment later», на старом — 0 |
| **F2** | комментарий модуля `lib/yeah-approval.el` называл `always` областью пользователя | `7153342` | файл остался 521 строкой, `yeah-approval-request` — на строке 245: якорь картины слоёв цел |
| **F4** | четыре места с остатками старого словаря | `b828f64` | `lib/yeah-approval-ui.el` остался 238 строкой, `yeah-approval-open` — на строке 184: второй якорь цел |
| **F5** | проверка умирала в чужом модуле вместо своего отказа | `413041f` | **было 255 — стало 1**, строк `approvals:` в выводе 16, ни одной `Error:`/`Debugger` |
| **F6** | код отказа диспетчера `-32602` не был закреплён | `d188317` | код изменён на `-32600` → `FAILED 6/30`, отказ называет сам код (`:form (= -32602 -32600)`) |
| **F7** | атомарность записи правил объявлена волной C2, но не измерялась | `d7bd83f` | контроль (усечение и запись на месте вместо `rename-file`): **200, 244, 470** неполных прочтений за три прогона; в честном дереве ~1450 прочтений и **ни одного** неполного |
| **F8, дефект 1** | один отказ покрывал две разные причины | `3a5279e` | два предмета: «the map of the run was not written: the file … is not there» и «the map of the run did not reach the end: the file … holds "map=partial", not the marker map=complete» |
| **F8, дефект 2** | «гейт ответил 0» не доказывало, что карта записана | `79c926f` | карта не записана → «scripts/gate: the step map answered 3: the map of the project is not green» и ответ 3; карта ответила отказом → ответ гейта **1**; честный путь → 0, как и раньше |

**Подробности, которые стоит назвать.**

* **F1.**  Предмет «ничего не осталось» теперь — **этот** прогон: процессы, которые держат каталог
  прогона в своём окружении (`YEAH_FAKE_METHOD_DIR=<dir>`), **плюс** pid'ы, которые проверка и так
  знает (pid гейта и pid'ы попыток из файла попыток).  Процессы прогона получают ограниченный
  момент (5 с), прежде чем их назовут оставшимися: уборка, которую пилот прогона делает на своём
  выходе, наследует окружение и живёт на десятки миллисекунд дольше гейта — без этого момента
  проверка называла **ложный предмет** (измерено: «the run of the gate was left behind when the gate
  answered: the pids (7971) are still alive»).  **Форма, предложенная брифом как вторая (совпадение
  подставного метода как программы процесса), измерена и оказалась пустой:** подставной метод
  запускается через bash (`argv[0]="bash"`), а его путь ожидания подменяет процесс через
  `exec sleep 300`, — ни у одного процесса прогона путь не является программой.
* **F5.**  Тело проверки накапливало отказы и печатало их только в самом конце, а отказ ядра
  (`yeah-perm-rule-store`) убивал процесс с кодом **255** — и собственное именованное сообщение
  проверки не печаталось вовсе.  Добавлен помощник `yeah-check--decision`, который ловит `user-error`
  ядра и превращает его в **отказ самой проверки**, а список отказов переехал на динамическую
  переменную `yeah-check--failures` (стиль соседних проверок гейта).
* **F7.**  Замер честный и двусторонний: **читатель — отдельный процесс** (скрипт на bash, который
  пишет сама проверка), читает файл правил в тесном цикле; **писатель** (та же проверка) пишет
  файл **500 раз** двумя разными документами по 100 правил каждый, чередуя их.  Правило приёмки:
  каждый прочитанный кусок — это либо отсутствие файла, либо **целый** документ.  Отказ, если
  читатель не прочитал файл вовсе: **пустой замер — тоже отказ**, у проверки, которая не может
  сорваться, нет смысла.
* **F8, дефект 2.**  Подставной метод теперь проверяет запись карты и, если запись не удалась,
  **называет файл** и отвечает **3** (карты нет — состояние неизвестно, а неизвестность не
  проходит).  Гейт снимает код шага карты и проверяет его: код не нулевой — гейт **называет шаг и его
  код**, и ответ гейта становится ответом карты; ответ прогона, который сам не прошёл (1 или 2), **не
  затирается**: неизвестность не значит, что опровержения нет.  Шкала гейта в шапке `scripts/gate`
  дополнена третьим случаем.  **Следствие для настоящего метода:** настоящий `mathc --root . map` в
  этом репозитории отвечает **3** (claim'ы не проверены: «never-checked»), и CI читает код карты так
  же — значит, поведение гейта совпадает с прочтением CI, а не вводит новую шкалу.

**Что осталось открытым.**  Два предмета, которые починка не тронула.

* **F8, дефект 3 — `yeah-proc-alive-p` (`lib/yeah-proc.el:80-98`).**  Функция считает процесс
  мёртвым, когда буква его состояния — любая, кроме `S` и `R`; состояния `T` (остановлен сигналом)
  и `D` (непрерываемый сон) — это живые процессы, которые функция зовёт мёртвыми.  **Гипотеза
  дискриминатора не измерена:** в 1856 опросах живой карты он видел только состояния `S`, `R` и
  `nil`, поэтому находкой она не записана и код не тронут.  **Открытый вопрос владельцу.**
* **Наблюдение писателя (не из списка находок).**  В
  `tests/checks/check-a-scope-decides-where-the-rule-lives.el` есть помощник
  `yeah-check--places (root failures)`, который кладёт свои отказы в переданный список `failures`.
  Список этот лексический (`let` с `lexical-binding: t`), поэтому отказы, которые кладёт
  **помощник**, до вызывающего не доходят — ветка отказа «файл не читается» в этой проверке
  **молчит**.  Новый помощник починки F7 отказы **возвращает**, а не кладёт в чужой список, — его
  отказы видны.  Старая ветка не тронута: правка чужой проверки без замера — риск.

**Итог починок на слитом дереве.**  Семь проверок пакета, три юнит-теста и байт-компиляция — зелёные
на дереве после слияния (`43a68e9`): `check-a-tool-declares-its-own-limits`,
`check-approvals-have-reply-kinds`, `check-the-question-offers-the-scope`,
`check-two-calls-on-one-resource-do-not-overlap`, `check-a-scope-decides-where-the-rule-lives`,
`check-a-killed-run-leaves-no-copy-behind`, `check-a-killed-gate-run-restarts-and-reaches-the-end`,
`check-the-layer-diagram-points-at-files-that-exist` — код 0; `test-yeah-interaction` — 12 из 12,
`test-yeah-acp` — 30 из 30, `test-yeah-approval` — код 0; `byte-compile-all` — код 0.

**Живой прогон после починок нашёл дефект, который гейт не увидел** (дефект B3 и починка 2 — см.
§16.107): отказ по имени на отложенном вызове не доходил до модели, и гейт этого не видел, потому
что проверка пределов меряла только путь, где человека не спрашивают.

### 16.109 Независимый верификатор починки B3: PASS и три находки — **2026-11-22**

**Что это.**  Починку «the refusal of a deferred call reaches the model» (`45b5606`) проверил
**независимый агент-верификатор** (роль `verifier`), отдельно от дискриминатора пакета: его
проверял не тот, кто писал, и не тот, кто чинил.  Бриф: `/tmp/verifier-fix2-brief.md`; отчёт:
`/tmp/verifier-fix2-report.md` (вердикт — в первых строках).  **Вердикт: PASS с находками — три
находки, все низкой серьёзности; дефектов кода нет.**  Репозиторий верификатор не тронут
(`git status` пуст), все мутации — на копиях в `/tmp` (`/tmp/vf2-after`, `/tmp/vf2-before`,
`/tmp/vf2-guard`, `/tmp/vf2-control`, `/tmp/vf2-herm`).

**Что измерено — десять вопросов, десять измерений.**

1. **Дефект был настоящий.**  На изоляции починки (дерево `43a68e9` с новой пробой) отказ по имени
   **не доходит**: таймер планировщика остаётся живым, записи `tool-end` в журнале нет, и модель
   читает «Error: the call of "bash" exceeded its timeout of 120 seconds» **через 120.07 с**.
   **На маршруте ACP необработанная `user-error` убивала процесс Emacs (код 255)** — то есть
   дефект стоил не только десяти минут прогона, но и жизни сервиса.
2. **Починка работает.**  Чек зелёный **4 раза из 4** (код 0, 6.8–7.0 с); модель читает отказ по
   имени за **0.08 с**.
3. **Проба различает.**  Страж снята — код 1 с точным сообщением «…was not refused by name when
   a person was asked: nil».
4. **Зарегистрированный контроль claim'а** — паттерн ещё совпадает с кодом
   (`lib/yeah-tools.el:296`), контроль кусается (код 1, три ассерта).
5. **Формы отказа на двух путях совпадают побайтно** (`duration-equal = t`): префикс, имя
   инструмента и предел — те же самые.
6. **Страж не ловит лишнего.**  Ошибка самого обработчика даёт тот же текст «Error: the handler of
   the tool failed» на обоих путях (`boom-equal = t`).
7. **Вызов закрывается ровно один раз.**  Одна запись `tool-end`, таймер отменён (живых таймеров
   нет), ресурс `shell` отпущен (второй вызов отработал и напечатал `hello`), батч продвинулся.
8. **Других непокрытых путей нет.**  Обе точки `yeah-tools-dispatch` покрыты; маршрут ACP измерен
   отдельно — отказ по имени доходит и там.
9. **Герметичность.**  Ни новых файлов в `/tmp`, ни каталогов `yeah-tool-limits*`, ни процессов;
   дерево не тронуто.
10. **Обещание честно.**  Текст claim'а править не нужно: **починка догнала обещание, а не
    расширила его.**

**Находки.**

| # | что | где |
|---|---|---|
| **F1** | **дефект проверки (низкий)** — проба 9 не проверяет, что путь был отложенным: на копии со снятой стражей **и** снятой пометкой ответа чек **зелёный** — проба молча превращается в копию пробы 7 и перестаёт отличать снятую стражу от честного дерева | `tests/checks/check-a-tool-declares-its-own-limits.el` |
| **F2** | **дефект проверки (низкий)** — второе утверждение пробы 9 («exceeded its timeout») недостижимо: окно пробы — 2 с, предел таймера — 120 с; на снятой страже `seen` = nil и срабатывает только первое утверждение | там же |
| **F3** | **пробел в доказательстве (низкий)** — у новой пробы нет зарегистрированного контроля в `spec.json`: поле `control` claim'а трогает только предел вывода | `spec.json`, claim `a-tool-declares-its-own-limits` |

**Починки (родитель, 2026-11-22; правило вне §17.2 — владелец может отменить).**

* **F1 — проба называет свой предмет.**  Помощник прогона оставляет записи журнала в
  `yeah-check--last-records`, и проба 9 **отказывается, если журнал не держит двух решений о
  разрешении**: отложенный путь пишет откладывание вопроса и ответ человека, а путь, где решают
  правила, — одно.  **Измерено (четыре дерева, копии в `/tmp`):**

  | дерево | что изменено | код | отказ |
  |---|---|---|---|
  | честное | — | **0** | — |
  | страж снята | `yeah-turn--dispatch-guarded` → прямой `yeah-tools-dispatch` | 1 | «the call that asked for more work than the tool declares was not refused by name when a person was asked: nil» |
  | **пометка снята** | `yeah-approval-async` возвращает `nil` | **1** | «the probe did not take the path where the person is asked: the journal holds 1 decision(s) about the permission, not 2» |
  | обе сняты | и страж, и пометка | 1 | то же (срабатывает первым) |

  До починки третья строка таблицы была **зелёной** — это и есть измеренная цена находки F1.
* **F2 — утверждение, которое не может сработать, убрано.**  Любое состояние, в котором модель
  читает сообщение таймера, **не проходит и первое утверждение** (в тексте нет «more than the
  timeout of 120 seconds»), поэтому второе утверждение было избыточным и недостижимым, а
  «проверка, которая не может упасть, — это комментарий».  **Цена названа:** проба больше не
  различает сообщение таймера **по имени**; вердикт держится на первом утверждении и на новом —
  о предмете пути.
* **F3 — пробел записан, а не заклеен.**  Зарегистрированный контроль claim'а
  `a-tool-declares-its-own-limits` (**взят дословно из `spec.json`**) по-прежнему кусается: три
  ассерта, код 1, после отката — код 0.  **Страж девятой пробы в `spec.json` не зарегистрирован, и
  это структурная причина:** метод держит **один** контроль на claim, а обещание claim'а имеет
  **два** предмета (предел вывода и отложенный путь).  **Цена пробела названа:** изменение стража
  девятой пробы не будет поймано картой; его меряет родитель, и измерение живёт в коммите
  `09a1371` и в этом разделе.
* **Зарегистрированный контроль не сломан починкой** — измерено отдельно: код 1 с тремя
  ассертами, после отката мутации — код 0.

### 16.110 Пакет волн D2: семь схем сайта и страж каждой схемы — **2026-11-22**

**Что это.**  Вторая часть догоняющего плана (`docs/ARCHITECTURE-CATCHUP-PLAN.md`) — волна **D2**,
«восемь схем».  Первая схема (картина слоёв ядра, `site/diagrams/core-layers.puml`) сделана волной 97
(§16.89); этот пакет сделал остальные семь и **общий страж** всех схем сайта.  Дальше по плану: **D3**
(вставка схем в сайт и правка текстов), **D4** (проверка «диаграмма актуальна»), **E1** (решение №16 в
`docs/SITE-DESIGN.md`), **E2** (`site/README.md`), **E3** (синхронизация `docs/ARCHITECTURE.md` §5 и §8 —
только после волн A–C).

**Что сделано — семь волн, семь claim'ов, один ридер, шестнадцать картинок.**

| волна | что нарисовано (§8 `docs/SITE-DIAGRAMS-PLAN.md`) | claim | файлы |
|---|---|---|---|
| `wave-d2b` | D1 — один ход агента | `the-one-turn-diagram-shows-the-turn-of-the-agent` | `site/diagrams/one-turn.puml`, 2 картинки, проверка |
| `wave-d2c` | D3 — слой Emacs | `the-emacs-layer-diagram-shows-the-bridge-and-the-scopes` | `site/diagrams/emacs-layer.puml`, 2 картинки, проверка |
| `wave-d2d` | D4 — размещения и протоколы | `the-placements-diagram-shows-the-placements-and-the-protocols` | `site/diagrams/placements.puml`, 2 картинки, проверка |
| `wave-d2e` | D6 — фиксированная точка Y | `the-fixed-point-diagram-shows-the-loop-of-the-delegation` | `site/diagrams/fixed-point.puml`, 2 картинки, проверка |
| `wave-d2f` | D7 — уровни проверки | `the-check-levels-diagram-shows-the-four-levels` | `site/diagrams/check-levels.puml`, 2 картинки, проверка |
| `wave-d2g` | D8 — пакеты кода | `the-code-packages-diagram-names-every-module-of-the-kernel` | `site/diagrams/code-packages.puml`, 2 картинки, проверка |
| `wave-d2h` | страж каждой схемы | `every-diagram-points-at-files-that-exist` | `tests/checks/check-every-diagram-points-at-files-that-exist.el` |

Общий ридер схем — **один**: `tests/support/yeah-diagram-files.el`.  Claim'ов в `spec.json` стало **179**
(было 172).

**Что измерено (родитель, 2026-11-22).**

1. **Восемь проверок зелёные** на слитом дереве (`feat/waves-d2`): шесть проверок схем, страж всех схем
   и старая проверка картины слоёв — все код 0.
2. **Страж меряет восемь картинок, 173 ссылки и 168 мест** — «8 picture(s) of site/diagrams/ measured,
   173 reference(s) and 168 place(s) followed».
3. **Семь зарегистрированных контролей claim'ов кусаются** (мутация на копии в `/tmp/d2-ctrl`, все —
   код 1 и точным предметом): отсутствие `lib/yeah-perm.el` в схеме хода; отсутствие ссылки моста в
   схеме слоя Emacs; отсутствие `lib/yeah-wire-socket.el` в схеме размещений; отсутствие
   `lib/yeah-delegate.el` в схеме фиксированной точки; слово `integration`, заменённое другими словами, в
   схеме уровней; отсутствие `lib/yeah-todo.el` в карте пакетов; строка за пределами файла в картине
   слоёв («the file has 562 line(s)»).
4. **Три контроля починки стража кусаются**: имя несуществующего места («the diagram names the place
   lib/yeah-nowhere.el, and there is no such place in the tree»); картинка без единого места («names no
   place of the repository»); контроль проверки уровней после правки ридера (без изменений).
5. **Рендер детерминирован**: `./scripts/dev diagrams` даёт картинки байт в байт те же, что в коммите;
   `state-machine.puml`, который пайплайн перегенерирует, не изменился.
6. **Байт-компиляция чистая** (`./scripts/dev byte-compile-all`, код 0).

**Находки.**

| # | что | где |
|---|---|---|
| **F1** | **палитра сайта не покрывает вид `node`** — лист-`node` рисуется заливкой `#F1F1F1` с буквами `#FFFFFF`, контраст **1.13:1** (нечитаемо в тёмной теме); машины рисуются `node` (контраст 21:1), листья — `component`.  **Не чинится в этом пакете**: палитра — точка сериализации родителя, кандидат на отдельную волну | `site/diagrams/palette-light.puml`, `site/diagrams/palette-dark.puml` |
| **F2** | **`skinparam nodeStyle rectangle` мёртв** в PlantUML 1.2025.10 — директива не даёт эффекта | `site/diagrams/*.puml` |
| **F3** | **два писателя написали ридер схем с одинаковыми именами `yeah-diagram--*` и разной семантикой** — при слиянии это конфликт и расхождение; **родитель переписал один ридер** (`acf38e5`), второй удалён | `tests/support/yeah-diagram-files.el` |
| **F4** | **дыра стража: имя файла без номера строки не проверялось** — картинка, назвавшая только файл модуля, которого в дереве нет, проходила правила 3 и 4.  **Закрыта починкой родителя** правилом места | `tests/checks/check-every-diagram-points-at-files-that-exist.el` |
| **F5** | **в репозитории не было ни одной отрендеренной картинки** — `site/assets/diagrams/` держал только `.gitkeep`; **закрыто** коммитом `57910e9` (16 картинок) | `site/assets/diagrams/` |
| **F6** | **два брифа родителя противоречили друг другу**: страж требовал от каждой картинки имя файла как `file:line', а схема уровней называет каталоги проверок (`tests/unit`, `tests/checks`, `tests/live`, `scripts/gate`) без номеров строк.  **Страж отказал честной картинке** — и был прав по записанному правилу; **починка родителя**: правило места живёт в ридере, место — это путь, первый сегмент которого есть в корне дерева | `tests/support/yeah-diagram-files.el` |
| **F7** | **бриф и план противоречат друг другу по D8**: бриф требует назвать каждый модуль `lib/' (68 шт.), а §8 `docs/SITE-DIAGRAMS-PLAN.md` говорит «на сайт идёт огрублённая версия без лишних модулей» | `docs/SITE-DIAGRAMS-PLAN.md` §8 |
| **F8** | **картинка пакетов широкая — 3233×444** (девять колонок, 66 ссылок); на странице текст уменьшится примерно в 3.6 раза — странице нужна прокрутка по горизонтали | `site/diagrams/code-packages.puml` |

**Решения родителя (2026-11-22; правило вне §17.2 — владелец может отменить).**

* **Имена картинок — правило, а не список**: `site/diagrams/<имя>.puml`, имя картинки = имя файла
  (`docs/SITE-DIAGRAMS-PLAN.md` §7.1).  Имена: `one-turn`, `emacs-layer`, `placements`, `fixed-point`,
  `check-levels`, `code-packages`.
* **Картинки коммитятся в репозиторий** — иначе у сайта нечего показывать, и проверке «диаграмма
  актуальна» (D4) не с чем сравнивать.
* **Палитра — дело пайплайна**: в `.puml` нет ни одного цвета; «ни один цвет не единственный носитель
  смысла» выполняется тем, что цветов нет.
* **Подпись про области согласования одна и та же в D1 и D3** — слово в слово (требование §4
  догоняющего плана).
* **Правило места в ридере** (см. F6): место — это путь, первый сегмент которого есть в корне дерева, и
  место репозитория должно быть на месте.  Слово `shared/exclusive' о планировщике — это слово картинки,
  а не путь.
* **D8: в дереве — полная карта ядра** (66 модулей в девяти пакетах + 2 исключения с причиной);
  огрубление для страницы — работа волны D3.  Противоречие F7 записано, а не снято правкой документа.
* **F1 и F2 не чинятся в этом пакете** — это правка палитры, отдельная волна.

**Что остаётся за владельцем.**  Ничего нового в этом пакете; противоречие F7 разрешает D3, а не
владелец, и оно записано явно.

### 16.111 Починки пакета волн D2: гейт был зелёным, а шесть обещаний не измерялись — **2026-11-22**

**Что это.**  Гейт пакета D2 был зелёным (180 меток формы 2, ноль красных), но гейт доказывает
не «обещание выполнено», а «проверка не упала».  **Дискриминатор** — независимый агент, которому
поручено сломать обещания пакета, — дал вердикт **FAIL**: **18 находок — 6 высоких, 5 средних,
7 низких**.  Шесть высоких — это шесть обещаний, которые проверка измеряла наполовину или не
измеряла вовсе, и потому гейт молчал.  Этот параграф — что починено, чем измерено и что осталось.

**Что было не измерено (высокие находки).**

| # | что | починка | чем измерено после починки |
|---|---|---|---|
| **H-1** | D1: семь шагов хода не измерялись — любые подписи проходили | семь шагов — это семь **блоков** рисунка, слова каждого шага заданы набором, блоки разные и в порядке шагов (писатель A, `77c478e`) | подписи всех семи шагов заменены на «:a step of the turn» → **код 1**: «the picture of the turn has no block that names the step of the model: the words model, proposes and call» |
| **H-2** | D3: шесть возможностей слоя (`BUFFERS`, `INTROSPECT`, `EDIT`, `DIAGNOSE`, `COMPOSE`, `RECOVER`) не измерялись вовсе | возможности — **заголовки** рисунка; три хоста (человек, редакторский Emacs, агентский Emacs) — тоже заголовки (писатель A, `d18d2a5`) | все шесть возможностей убраны из рисунка → **код 1**: «the picture of the Emacs layer has no title that names the capability BUFFERS: the capability of the layer is not in the picture» |
| **H-3** | D4: слова `service` и `socket` находились в **именах файлов**, а не в рисунке | корень: имя файла выбрасывается **до** разбора на слова (родитель, `475fd1f`) | слова убраны из рисунка, имена файлов оставлены → **код 1**: «the drawing does not say service: the picture must show the service placement» |
| **H-4** | D6: демонстрация фиксированной точки не измерялась (вырезать — код 0) | демонстрация — **последний** блок рисунка; блок запуска проверки стоит перед ним; блок «change is the new environment» (писатель A, `1b934ab`, `8ef2cd9`) | блок демонстрации вырезан → **код 1**: «the diagram of the fixed point does not end with the demonstration of the fixed point: the last block of the picture does not name the words agent, fixed, its, own, code and check» |
| **H-5** | шаблон имени файла в ридере **никогда не срабатывал**: `(` без обратного слэша — литеральный символ | шаблон написан с shy-группой; правило живёт в `yeah-diagram--words` (родитель, `475fd1f`) | прямое измерение ридера: шаблон матчит `lib/yeah-tools.el:119`, и слово `tools` **не** является словом рисунка |
| **H-6** | D8: пункт «модуль назван в одном пакете, а не в двух» — **мёртвый код** (`delete-dups` перед `cl-count` давал всегда 1) | считаются **пакеты**, а не повторы имени; отказ называет модуль и два пакета (писатель B, `a54e207`) | модуль назван вторым пакетом → **код 1**: «the module lib/yeah-session.el is named by two packages of the picture: journal and projections and run control» |

**Средние и низкие находки — что с каждой.**

| # | что | решение |
|---|---|---|
| **M-1** | правило ссылки и правило определения жили в ридере и в старой проверке картины слоёв: одна мутация давала код 0 и код 1 | **закрыта**: старая проверка перешла на правило ридера (`2968817`) |
| **M-2** | текст claim'а D8 не говорил, что состав девяти пакетов — решение писателя волны | **закрыта**: текст обещания дополнен (`024ca62`), falsifier'ы и `refuted_by` записей волн синхронизированы **дословно** |
| **M-3** | D3: человек, редакторский Emacs и агентский Emacs не измерялись | **закрыта** писателем A (заголовки рисунка) |
| **M-4** | D6/D2: контроль бил по ссылке, а не по слову; «чинит свой код» не измерялось | **закрыта** корнем (слова берутся из рисунка) и писателем A (демонстрация — последний блок) |
| **M-5** | D7: порядок уровней мерялся по первому упоминанию слова | **закрыта**: порядок меряется по **блокам** рисунка, легенда порядок не ломает (`c6d59fd`) |
| **L-1** | проверка места в D7 жила своими `file-directory-p`/`file-regular-p` | **закрыта**: правило места ридера (`c6d59fd`) |
| **L-2** | формы пакета, заметки и исключения жили копиями в двух проверках | **закрыта** писателем C (`a04e5cc`): формы живут в ридере, обе проверки их зовут |
| **L-3** | список пяти ответов скопирован дословно в две проверки | **закрыта** родителем (`f1edd2b`): список и правило живут в ридере |
| **L-4** | страж обходил `site/diagrams/` без рекурсии | **закрыта** писателем B (`5987712`) |
| **L-5** | правило «называет хотя бы одно место» проверялось как «ссылка **или** место» | **запись исправлена** (2026-11-22): измерение родителя было **неверным** — правило места и правило ссылки **не** совпадают для файла под **скрытым** каталогом верхнего уровня (`.github/probe.el:1`: ссылка есть, места нет), и обещание claim'а не измерялось.  Починка и её измерение — в §16.112 |
| **L-6** | D8 мерял только `lib/*.el` верхнего уровня | **закрыта**: обход `lib/` **рекурсивный** у обеих проверок (писатели B и C) |
| **L-7** | файл `.gitkeep` остался рядом с 16 картинками в каталоге `site/assets/diagrams/` | **закрыта** родителем (`90ba119`): заглушка не нужна |

**Что измерено (родитель, 2026-11-22, после слияния трёх починок).**

1. **Восемь проверок пакета зелёные** на слитом дереве (`2696d2b`), 1345 мс, код 0; `byte-compile-all` — код 0.
2. **Страж меряет восемь картинок, 173 ссылки и 168 мест** — «8 picture(s) of site/diagrams/ measured, 173 reference(s) and 168 place(s) followed».
3. **Все восемь зарегистрированных контролей кусаются** (команды взяты из `spec.json`, мутация — на копии в `/tmp/d2-ctrl-work`, все — **код 1** и точным предметом):
   * D1 — «the picture of the turn does not name lib/yeah-perm.el: the step it holds is not in the picture»;
   * D3 — «the block bridge of the picture names no file»;
   * D4 — «the diagram does not name lib/yeah-wire-socket.el with a line that carries a definition»;
   * D6 — «the diagram does not name lib/yeah-delegate.el with a line that carries a definition»;
   * D7 — «the drawing does not say integration: the picture must show the level integration, and a name that is only a part of a path is not the name of a level»;
   * D8 — «the module lib/yeah-todo.el is neither named by a package of the picture nor listed in the note of the modules the picture does not name»;
   * страж — «the diagram names lib/yeah-tools.el:999999, and the file has 562 line(s)»;
   * старая проверка картины слоёв — «the module lib/yeah-trash.el is neither named by the diagram nor listed in the note of the modules the picture does not name».
4. **Шесть высоких находок дискриминатора переизмерены** родителем (таблица выше): каждая ломается кодом 1 с точным предметом; на дереве до починок те же мутации были зелёными — это и было измерено дискриминатором.
5. **Falsifier'ы и `refuted_by` совпадают дословно** во всех семи записях волн D2 (проверено разбором JSON).
6. **Писатели измерили свои починки сами**: писатель A — 13 мутаций, писатель B — 20 мутаций, писатель C — 8 мутаций **и** эквивалентность правил ридера копиям правил базы на обеих картинках, а также **расхождение копий на базе**: поломка формы пакета в одной копии оставляла вторую проверку зелёной (B-1, B-2), а модуль в подкаталоге `lib/` был невидим для проверки картины слоёв (B-3).

**Решения родителя (2026-11-22; правило вне §17.2 — владелец может отменить).**

* **H-5 чинится в ридере, а не в каждой проверке**: правило «имя файла — не слово картинки» живёт в одном месте (`yeah-diagram--words`), и шаблон имени файла написан с shy-группой.
* **Формы рисунка живут в ридере**: форма пакета, форма заметки, форма исключения и обход модулей `lib/` — в `tests/support/yeah-diagram-files.el`; обе проверки, которые их измеряют, копий не носят.
* **L-5 «не чинится» — запись отменена** (2026-11-22): измерение, на котором она стояла, было неверным — правила места и ссылки не совпадают для файлов под скрытым каталогом верхнего уровня, и обещание claim'а не измерялось.  Починка, её измерение и решение по исключению стража — в §16.112.
* **Claim'ы правились «amended, not rewritten».**  Тексты обещаний D1/D3/D6/D7/стража **не менялись** — обещания верны, их теперь измеряют; изменены **falsifier'ы**: они называют способы поломки, и `refuted_by` записей волн повторяет их дословно.
* **Ловушки записаны в `ELISP_BEST_PRACTICES.md`**: §11.18 — `(` без обратного слэша (родитель, `9fae1ae`); §11.19 — `nth` требует список в ячейке, точечная пара с такой строкой не годится (родитель, `7e5f3d7`).
* **Читатель блока рисунка не меняется**: блок — это строка рисунка, начинающаяся с `:`; продолжение activity блоком не считается.  Это семантика ридера, и решение о ней — за владельцем (находка писателя A).

**Что остаётся за владельцем.**  Ничего нового.  Открытыми остаются записи F1 (палитра вида `node`), F2 (`skinparam nodeStyle rectangle` мёртв в PlantUML 1.2025.10) и F8 (широкая картинка пакетов) — они записаны в §16.110 и относятся к волнам **D3** (вставка схем в сайт) и **D4** (проверка «диаграмма актуальна»), а также **E1**, **E2**, **E3**.

### 16.112 Независимый верификатор починок D2: две средние и четыре низкие находки — **2026-11-22**

**Что это.**  Независимый верификатор починок пакета D2 (первый круг, §16.111) подтвердил
честность шести высоких находок дискриминатора — он измерил их мутациями сам, а не поверил
отчёту — и нашёл **шесть новых находок: две средние (S-1, S-2) и четыре низкие (L-A…L-D)**.
Все шесть — одного рода: **обещание claim'а шире измеренного**.  Три из них (S-1, S-2, L-A, L-B)
касаются правил проверок, одно (L-C) — мёртвого кода ридера, одно (L-D) — пайплайна картинок.
Этот параграф — что починено, чем измерено и что осталось.

| # | что было не измерено | починка | чем измерено после починки |
|---|---|---|---|
| **S-1** | страж: правило «картинка обязана назвать место репозитория» замыкалось операндом `references` — картинка, единственные имена которой — ссылки на файлы под **скрытым** каталогом верхнего уровня (`.github/probe.el:1`), **не называет ни одного места** (скрытые записи корня пропускаются) и проходит кодом 0 | операнд `references` убран (писатель D2h, `232521f`); **сверх того** исключение картинки, которую пишет код, опознаётся по **пути** картинки (`site/diagrams/state-machine.puml`), а не по имени файла, и вторая, устаревшая часть текста отказа переписана (родитель, `76a889c`) | картинка в подкаталоге, единственное имя — `.github/probe.el:1` → **код 1**: «the picture site/diagrams/sub/extra.puml names no place of the repository, and a picture of the site must name at least one place of the tree»; картинка с тем же именем в подкаталоге (`sub/state-machine.puml`), не называющая места → **код 1** (исключение — путь, а не имя) |
| **S-2** | размещения: заметка «честного предела провода» измерялась **мешком слов** — инверсия заметки (socket — *не может*, stdio — *может*) оставляет все девять слов и даёт код 0 | измеряется **отношение**: часть заметки от `stdio` до `socket` обязана называть `cancel` **и** `cannot`, часть от `socket` — `cancel` **и** `handled`; заметка обязана быть и обязана висеть на блоке **сокета** (писатель D2i, `ddd171e`) | инверсия заметки → **код 1**: «the part of the note about the local socket does not say that a cancel is handled while the prompt is still running: the word handled is not there»; заметка на stdio → **код 1**: «the note of the picture hangs on the block stdio, and the note of the limit of the wire belongs to the local socket: on stdio a cancel cannot interrupt a running prompt» |
| **L-A** | слой Emacs: обещание «the bridge is the **only path** to the live state» и «a capability the person approves **on purpose**» не измерялись | одна строка рисунка обязана называть `only`+`path`+`live`+`state`, и одна строка — `capability`+`approve`+`purpose` (писатель D2i, `7d6832a`) | убрано `only` → **код 1**; убрано `purpose` → **код 1**; **удалены обе строки-ребра при живом комментарии** → **код 1** (комментарий — не рисунок) |
| **L-B** | ход: обещание «a call of **a tool**», «whether **the call may run**», «when **the rules ask**» не измерялись | шаг «model» требует и слово `tool`; какой-то **блок** — `call`+`may`+`run`; какая-то **строка** — `rules`+`ask`+`person` (писатель D2i, `7d6832a`) | `:the model proposes a call` → **код 1**; оба `:the call may run;` заменены → **код 1**; `if (the rules allow it)…` → **код 1**; **удаление уточнения `(may this call run?)` → код 0** — обещание ещё истинно, и это верно |
| **L-C** | ридер: `yeah-diagram--root` объявлена и **не вызвана нигде**; две ветви `((string-prefix-p "/" …))` недостижимы — образцы места и ссылки не могут дать имя, начинающееся с `/` | мёртвый код удалён (писатель D2i, `21b76cb`); **починка внесла новый мёртвый код** — находка F-1 второго круга (§16.113), и он тоже удалён | измерено: ни одно место и ни одна ссылка ридера не начинается с `/` (первые символы всех мест сайта — `l`, `s`, `t`), и **поведение всех проверок пакета не изменилось** — те же числа, те же коды |
| **L-D** | пайплайн: страж обходил `site/diagrams/` рекурсивно, а `scripts/dev diagrams` рисовал **только верхний уровень** — картинка в подкаталоге мерялась и **не рендерилась**, молча | пайплайн обходит **всё дерево** и зеркалит подкаталоги в `site/assets/diagrams/`; проверка пайплайна получила картинку в подкаталоге в своей фикстуре и требует её картинки (родитель, `0e438e7`) | подставной PlantUML: **до** — 16 картинок, подкаталог **молча пропущен**; **после** — 18 картинок, в подкаталоге `sub/` на месте `extra-light.svg` и `extra-dark.svg`; **контроль** — базовый `scripts/dev` → проверка пайплайна **код 1**: «the picture of nested/gamma (light) is missing or empty» |

**Побочная находка: файлы проверок — не целые файлы.**  Писатель D2i, меряя обещание картины хода,
нашёл в **своём** файле лишнюю закрывающую скобку: файл не читается как целый (`invalid-read-syntax
")"`), а работает только потому, что последняя форма убивает процесс **до** того, как ридер дойдёт
до лишней скобки.  Находка измерена и в **базе** (`8290c96`), и после починки.  Родитель снял
скобку в файле проверки хода (`0a1aba4`) и прогнал **все** файлы проверок дерева: тот же дефект
оказался ещё в **шести** файлах более ранних волн (`2a193ee`) — `check-registry-async.el`,
`check-a-killed-gate-run-restarts-and-reaches-the-end.el`,
`check-a-probe-of-the-catalog-leaves-no-empty-session.el`,
`check-a-session-changes-its-model-over-the-wire.el`,
`check-the-journal-holds-the-usage-of-a-request-once.el`,
`check-the-mcp-servers-of-a-session-reach-the-model.el`,
`check-the-mcp-servers-of-a-session-speak-http.el`.  Все семь после правки читаются целиком, и все
семь проверок отвечают кодом 0, как и до неё.

**Что измерено родителем на слитом дереве (2026-11-22).**

1. **Девять проверок зелёные**: восемь проверок пакета D2, старая проверка картины слоёв и
   проверка пайплайна (`0e438e7` измеряет подкаталог) — код 0, 29 208 мс; `byte-compile-all` — код 0.
2. **Все восемь зарегистрированных контролей кусаются** (команды взяты из `spec.json`, мутация — на
   копии в `/tmp`, все — **код 1** и точным предметом): «the picture of the turn does not name
   lib/yeah-perm.el…», «the block bridge of the picture names no file», «the diagram does not name
   lib/yeah-wire-socket.el…», «the diagram does not name lib/yeah-delegate.el…», «the drawing does
   not say integration…», «the module lib/yeah-todo.el is neither named by a package…», «the diagram
   names lib/yeah-tools.el:999999…», «the module lib/yeah-trash.el is neither named by the diagram…».
3. **Шесть высоких находок дискриминатора переизмерены после второго круга** — каждая ломается
   кодом 1 с точным предметом; H-5 измерен прямо на ридере.
4. **Картинки сайта не изменились**: `./scripts/dev diagrams` на слитом дереве — 16 картинок, и
   `git status --porcelain site/assets/diagrams` **пуст** (побайтовые те же).  Новый пайплайн рисует
   каждый источник в своём каталоге вывода и ищет картинку диаграммы, которая называет себя, только
   среди картинок своего источника.
5. **Тексты обещаний в `spec.json` не менялись** (`git diff 8290c96 -- spec.json` — пусто): обещания
   были **измерены**, а не переписаны.

**Решения родителя (2026-11-22; правило вне §17.2 — владелец может отменить).**

* **S-1**: операнд `references` убран из четвёртого правила стража, а исключение картинки, которую
  пишет код, привязано к **пути** `site/diagrams/state-machine.puml`: исключение не может переехать
  на картинку с тем же именем в подкаталоге.  Текст отказа переписан — старая вторая часть
  объясняла отказ, которого больше нет.
* **S-2**: меряется отношение, а не набор слов; заметка обязана быть и обязана висеть на блоке
  сокета.  Слова `stdio`, `socket`, `cancel`, `cannot` убраны из мешка слов проверки — они больше
  не несут обещание в одиночку.
* **L-A, L-B**: проза обещания измеряется дешёвыми словами: одна и та же **строка рисунка** (комментарий
  вверху файла рисунком не является) и **блок** рисунка.  Часть прозы, которую правило ридера не даёт
  измерить (уточнение `(may this call run?)` — это продолжение activity, а не блок), **сужена в
  измерении, а не в обещании**: обещание «whether the call may run» истинно и без этого уточнения.
* **L-C**: мёртвый код ридера удалён, а его недостижимость **измерена**; новая функция ридера
  (`yeah-diagram--note-alias`) внесена и в заголовочный комментарий ридера.  **Запись уточнена
  2026-11-22**: починка L-C внесла **новый** мёртвый код (`yeah-diagram--words-name-all-p`) — его
  нашёл и измерил верификатор второго круга (F-1, §16.113), и он удалён.
* **L-D**: пайплайн рисует всё дерево, дерево картинок зеркалит дерево источников, и проверка
  пайплайна держит картинку в подкаталоге в своей фикстуре.
* **Файлы проверок — целые файлы.**  Лишняя скобка снята в восьми файлах (один — из пакета D2, семь —
  из более ранних волн); поведение проверок не изменилось.

**Что остаётся за владельцем.**  Ничего нового.  Открытыми остаются записи F1 (палитра вида `node`),
F2 (`skinparam nodeStyle rectangle` мёртв в PlantUML 1.2025.10) и F8 (широкая картинка пакетов) —
они записаны в §16.110 и относятся к волнам **D3** (вставка схем в сайт) и **D4** (проверка «диаграмма
актуальна»), а также **E1**, **E2**, **E3**.

### 16.113 Независимый верификатор второго круга починок D2: PASS и две низкие находки — **2026-11-22**

**Что это.**  Второй круг независимого верификатора (бриф `/tmp/verifier-d2-round2-brief.md`,
отчёт `/tmp/verifier-d2-round2-report.md`) измерил двадцать измерений (V-1…V-20) на копиях
дерева в `/tmp` и дал вердикт **PASS**:

* все шесть находок первого круга (S-1, S-2, L-A, L-B, L-C, L-D) **починены по-настоящему** — для
  каждой измерено «до» (дефект воспроизводится кодом 0) и «после» (код 1 с точным предметом);
* починки родителя настоящие: восемь файлов проверок стали **целыми файлами**, а страж
  документации — зелёным на честном дереве и **кусается**;
* **ни одна проверка не ослаблена**: диффы показывают только ужесточения и добавления;
* **обещания не переписаны** — `git diff 8290c96 -- spec.json` пуст: чинили измерение, а не
  обещание;
* карта метода зелёная (`verdict: green`, `uncovered: 0`), все 179 claim'ов `holds (current)`.

**Две находки низкой серьёзности — и что с ними.**

| # | что было | починка | чем измерено после починки |
|---|---|---|---|
| **F-1** | починка L-C убрала мёртвый код ридера, но **внесла новый экземпляр того же дефекта**: `yeah-diagram--words-name-all-p` объявлена и **не вызвана нигде** (три вхождения: определение, упоминание в заголовочном комментарии ридера, упоминание в §16.112) | функция удалена, упоминание в заголовочном комментарии ридера снято (родитель, `ab53fe4`) | поиск по дереву: **ноль** вхождений в коде; остались только упоминания в этом параграфе и в §16.112, где сказано, что функция была и удалена |
| **F-2** | починка S-2 требовала, чтобы заметка висела на блоке сокета, но брала **псевдоним первой** заметки и **слова всех** заметок: картинка с двумя заметками (первая — на сокете и без предела, вторая — на stdio и с пределом) проходила **кодом 0** | ридер отдаёт **каждую** заметку вместе с блоком, на котором она висит (`yeah-diagram--notes`), и проверка меряет **ту заметку, которая несёт предел провода** — заметку, что говорит обоих транспортах; картинка, размазавшая предел по двум заметкам, предела не несёт (родитель, `ab53fe4`) | мутация «две заметки, предел во второй, на stdio» → **код 1**: «the note of the picture hangs on the block stdio, and the note of the limit of the wire belongs to the local socket: on stdio a cancel cannot interrupt a running prompt»; предел на блоке stdio → **код 1** (тот же отказ); честное дерево → **код 0**; предел в первой заметке, а вторая на stdio и без предела → **код 0** (лишняя заметка не нарушает обещание) |

**Что измерено родителем после починок (2026-11-22).**

1. **Восемь проверок пакета зелёные** (1392 мс), проверка пайплайна (26 389 мс) — код 0;
   `byte-compile-all` — код 0.
2. **Все восемь зарегистрированных контролей кусаются** кодом 1 с прежним точным предметом.
3. Тексты обещаний в `spec.json` не менялись.

**Ограничения вердикта (названы самим верификатором).**  Проверки, требующие живого провайдера,
не запускались; карта метода пересчитана на клоне дерева, а не в самом репозитории; полный гейт
пакета верификатор не запускал — прогонял девять проверок пакета, проверку пайплайна и проверку
картины состояний.

**Решения родителя (2026-11-22; правило вне §17.2 — владелец может отменить).**

* **F-1 и F-2 починены в этом же пакете**, а не записаны в открытую работу: обе находки того
  же класса, что находки первого круга, и обе — измерены, а не утверждены.  Запись про L-C в
  §16.112 **уточнена** (починка внесла новый мёртвый код) — документ не стал оптимистичнее.

**Что остаётся за владельцем.**  Ничего нового.  Открытыми остаются записи F1 (палитра вида
`node`), F2 (`skinparam nodeStyle rectangle` мёртв в PlantUML 1.2025.10) и F8 (широкая картинка
пакетов) из §16.110, а также волны **D3** (вставка схем в сайт), **D4** (проверка «диаграмма
актуальна»), **E1**, **E2** и **E3**.

### 16.114 Пакет волн D3, D4, E1, E2 и E3: схемы на странице, проверка «картинка — это картинка» и документ, приведённый к коду — **2026-11-22**

**Что это.**  Вторая часть догоняющего плана (`docs/ARCHITECTURE-CATCHUP-PLAN.md`): волны **D3**
(схемы на странице сайта), **D4** (проверка «диаграмма актуальна»), **E1** (решение №16 в
`docs/SITE-DESIGN.md`), **E2** (`site/README.md`) и **E3** (синхронизация `docs/ARCHITECTURE.md`
§5 и §8 с кодом волн A–C).  Вместе с пакетом волн D2 (§16.110) закрыта **вся часть II плана**
(схемы) и — вместе с волнами A–C (§16.89–§16.95) — **весь догоняющий план**.

**Что сделано — пять волн, два новых claim'а, одна проверка и один документ.**

| волна | что | claim | файлы |
|---|---|---|---|
| `wave-d3` | восемь схем на странице сайта; ASCII-рисунок архитектуры убран; у каждой картинки две темы, alt и подпись | `the-site-shows-the-diagrams-of-the-architecture` | `site/index.html`, `site/styles.css`, `tests/checks/check-the-site-shows-the-diagrams.el` |
| `wave-d4` | проверка «диаграмма актуальна»: перерисовка, источник машины состояний **из кода**, сравнение картинок в нормализованной форме | `the-diagram-on-the-site-is-current` | `tests/checks/check-site-diagrams-current.sh` |
| E1 | решение №16 в `docs/SITE-DESIGN.md` (нотация, PlantUML как авторский инструмент, две темы, палитра, alt и подпись, замена ASCII) | — | `docs/SITE-DESIGN.md` |
| E2 | `site/README.md`: «The architecture is ASCII» → «…are diagrams», раздел «The diagrams», токены палитры | — | `site/README.md` |
| E3 | `docs/ARCHITECTURE.md` §5 и §8 приведены к коду волн A–C | — | `docs/ARCHITECTURE.md` |

Claim'ов в `spec.json` стало **181** (было 179).

**Два долга, названные E3 в тексте документа (а не снятые молча).**  Документ нормативен, и
писатель волны не имел права ослабить обещание, чтобы оно совпало с кодом; обещанie оставлено
как было, а разрыв назван.

| долг | где | что говорит код |
|---|---|---|
| **A** | `docs/ARCHITECTURE.md` §5, поправка от 2026-11-22 | «Registries and permissions must not be implicit process-wide state shared by unrelated runs» — реестр прогона свой снимок (`lib/yeah-run.el:105`), правила прогона свой список (`lib/yeah-run.el:59`), но **правила процесса — один список Emacs** (`lib/yeah-perm.el:65`), и сессии ACP читают его как свои постоянные права (`lib/yeah-acp.el:100`): два прогона одного Emacs делят права процесса, не спрашивая друг друга |
| **B** | `docs/ARCHITECTURE.md` §8, поправка от 2026-11-22 | «separate read, write, process and network capabilities» — сети как capability у кода **нет**: в словаре риска четыре вида (`lib/yeah-risk.el:42`), и инструмент, пришедший с сервера вне ядра, не объявляет риска вовсе (`lib/yeah-risk.el:106`), поэтому правило спрашивает о нём как о любом меняющем мир |

Два долга волны 76 (канонический путь рабочего пространства не граница ядра; прочитанная
командой креденция попадает в журнал) остаются открытыми и **переписаны не были** — они названы
в тексте заново как открытые.  Прочие расхождения, найденные писателем и не закрытые им: три
компоненты начинают ход (контроль, размещение, ребёнок) против буквальной формулировки «the
controller is the only component that advances the run» — текст теперь называет **ход** тем, кто
двигает прогон; `\"webfetch\"` в отключённом оценщике `lib/yeah-codes.el:38`; `site/diagrams/core-layers.puml:27`
ссылается на `lib/yeah-risk.el:90`, а не на словарь (файл не писателя).

**Решения родителя (2026-11-22; правило вне §17.2 — владелец может отменить).**

* **Проверка D3 написана родителем по брифу, а не по результату писателя.**  Страница без
  проверки — это страница, которая тихо гниёт; проверка обязана жить в `tests/checks/` и быть
  связана с claim'ом, иначе карта её не увидит.  Бриф писателя называл классы `diagram`,
  `diagram__img--light` и `diagram__img--dark` — проверка писана по этому брифу и не подгонялась
  под страницу, которую писатель сделал.
* **Проверка D4 живёт в репозитории (`tests/checks/check-site-diagrams-current.sh`), а не в
  скрипте писателя**, по той же причине.
* **Источник машины состояний пишется из кода, а не читается из файла репозитория.**  Альтернатива
  (читать закоммиченный `site/diagrams/state-machine.puml`) — одна строка; владелец может
  потребовать.  Ветка «картинка против картинки кода» — та, что держит обещание волны;
  свежесть закоммиченного файла остаётся у claim'а `the-state-diagram-comes-from-the-code`.
* **Гейт не пишет свой вердикт в документы.**  Вердикт гейта живёт здесь, записью родителя.
* **Push — только по просьбе владельца.**  Ветка `main` стоит впереди `origin/main`; ничего не
  отправлено.

**Что измерено (родитель, 2026-11-22, на копиях дерева в `/tmp`).**

1. **Проверка D3.**  Честное дерево — код 0.  Семь контролей — код 1 с точным предметом: схема
   `d3` переименована в `d9` («the page shows no figure of the diagram d3»); пустой `alt` («the
   picture of the diagram d6 has no text that says what it is»); `src` на несуществующий файл
   («the picture of the diagram d1 points at assets/diagrams/one-turn-nowhere.svg and there is no
   such file»); убран `max-width: 100%` («the stylesheet does not scale the picture of a diagram
   into the column»); переименовано правило светлой картинки («the stylesheet does not hide the
   light picture in the dark theme»); ASCII-рисунок возвращён («the page still has the figure of
   ASCII»); переименован тег подписи («the figure of the diagram d6 has no caption»).
2. **Дефект, найденный измерением в проверке самого родителя:** регулярное выражение
   `<figcaption[^>]*>` принимало `<figcaptionx>` за подпись — ужесточено до
   `<figcaption\(?: [^>]*\)?>`, и контроль стал кусаться.
3. **Проверка D4.**  Честное дерево — код 0, восемь схем, шестнадцать картинок из шестнадцати.
   Шаг, добавленный в `site/diagrams/one-turn.puml` без нового рендера, — код 1, отказ называет
   `site/assets/diagrams/one-turn-light.svg` и `…-dark.svg` против своего источника.  **Изменение
   самого кода** (`lib/yeah-loop.el`, ячейка `continue` переименована) без нового рендера — код 1,
   отказ называет `state-machine-light.svg` и `…-dark.svg`: ветка, которая пишет источник из кода,
   живая, а не декоративная.  Контроль claim'а (`sed -i 's|:the call is refused|:the call is
   turned away|' site/diagrams/one-turn.puml`) — код 1 с тем же предметом, и **пять соседних
   проверок на том же дереве остаются зелёными**: контроль роняет только этот claim.
4. **Приёмка в браузере (то, что проверка не меряет).**  Страница с сервера на `127.0.0.1`,
   shared Chromium: раздел `*architecture*` — схема D2 на месте, вписана в колонку, страница не
   едет вбок; переключатель темы в меню-баре отдал тёмную тему (картинка — тёмный вариант) и
   обратно светлую (картинка — светлый вариант); подпись под схемой фиксированной точки видна.
   Сервер остановлен, браузер отпущен.

**Что остаётся за владельцем.**

* Ничего нового в этом пакете.
* Открытыми остаются находки **F1** (палитра вида `node`), **F2** (`skinparam nodeStyle rectangle`
  мёртв в PlantUML 1.2025.10) и **F8** (широкая картинка пакетов) из §16.110.
* Push — по вашей команде.

### 16.115 Гейт пакета волн D3, D4, E1, E2 и E3: одна красная метка на чужом claim'е и открытый дефект волны 59 — **2026-11-22**

**Что это.**  Гейт пакета волн D3, D4, E1, E2 и E3 закончился **красным**: красная метка одна, и
лежит она на claim'е `a-gate-run-needs-no-watchdog` (волна 59) — **не на нашем**.  Этот параграф:
что именно было красным, что о флаке доказано, что измерением исключено, что осталось открытым
дефектом и почему пакет закрывается пере-гейтом.

**Красная метка — одна, форма 1.**  Лог `/tmp/w-d3d4e-gate.log` (398 647 байт): 182 метки `mathc:`,
из них **181 — форма 2** (укус: verifier после отрицательного контроля), **форма 3 — ноль**, и
**ровно одна — форма 1** (красная):

    mathc: ./scripts/dev check tests/checks/check-a-killed-gate-run-restarts-and-reaches-the-end.el exited 1

Отказ проверки называет предмет: «gate: the map of the run was not written: the file
/tmp/yeah-gatei6JA7I/map is not there».  **Наши claim'ы при этом держатся**: карта пакета показывает
`the-site-shows-the-diagrams-of-the-architecture holds (current)`,
`the-diagram-on-the-site-is-current holds (current)` и `uncovered: 0 file(s)`.

**Флак доказан журналом метода.**  В `.math/v5/evidence.jsonl` по claim'у
`a-gate-run-needs-no-watchdog` — **60 записей: 58 pass и 2 fail**.  Отказа два, и оба приходятся на
разные деревья и разные дни:

| когда | дерево | чей пакет | лог | отказ |
|---|---|---|---|---|
| 2026-11-22 08:28:39 | `5bb88173` | B2/B3/C2/C3 (предок `main`) | `/tmp/w-b2-b3-c2-c3-gate.log`, строка 4102 | «the map of the run did not reach the end» |
| 2026-11-22 16:10:45 | `657451c` | D3/D4/E1/E2/E3 (наш) | `/tmp/w-d3d4e-gate.log`, строка 4103 | «the map of the run was not written: the file … is not there» |

Claim — **не наш**: область — `scripts/gate`, `scripts/live-pilot`, `scripts/lib/method.sh`,
`scripts/dev`, `tests/support/yeah-fake-method.sh`,
`tests/checks/check-a-killed-gate-run-restarts-and-reaches-the-end.el`; контроль —
`sed -i 's|^      attempt=\$((attempt + 1))$|      verdict=3; break|' scripts/gate`.

**Обе формы отказа — одна.**  В обоих логах вывод гейта обрывается на одной и той же строке, и
вывода второй попытки в нём **нет**:

    /home/az/Projects/yeah/scripts/live-pilot: line 181:  7877 Killed                     "$@"
    scripts/gate: the run was killed (code 137); it is started again (attempt 2 of 3)

Гейт увидел убитую попытку, **начал вторую** — и ответил 0, не записав карту; вторая попытка не
оставила в выводе ничего.  Формулировки двух отказов разные **только** потому, что починка
`3a5279e` (10:16, внутри D2) развела один отказ на два предмета: в дереве 08:28 этой починки ещё
не было (`3a5279e` — не предок `5bb88173`), и старый отказ «the map of the run did not reach the
end» покрывал **оба** случая сразу; по логу 08:28 сказать, была ли карта отсутствующей или
неполной, нельзя.  В логе 16:10 формулировка разведена, и предмет назван точно: **файла карты
нет**.

**Что исключено измерением родителя.**

1. **Двенадцать прямых прогонов чека — зелёные.**  Чек, запущенный вручную, отвечает 0.
2. **Десять прогонов с точным окружением юнита** (`env -i PATH=… YEAH_CHECK_TIMEOUT=600 HOME=/home/az
   /bin/sh -c './scripts/dev check …'`) — зелёные: окружение гейта само по себе отказа не
   воспроизводит.
3. **`setsid` не при чём.**  `ps -eo pid,ppid,pgid,sid,args` во время прогона чека: гейт ведёт свою
   группу и сессию, пилот живёт в группе гейта — **одинаково** с `setsid` и без него.
4. **Гейт действительно ответил 0.**  Emacs сообщает об `SIGKILL` как о статусе **9** (проба:
   `make-process` + `signal-process 'KILL` → `process-exit-status` = 9), значит «гейт ответил 0» —
   не «ответ не прочитан».  И **шаг карты отработал с кодом 0**: починка `79c926f` (тоже внутри D2 и
   предок `657451c`) печатает «scripts/gate: the step map answered N», когда шаг карты не удался, —
   и в логе 16:10 такой строки **нет**.  (В логе 08:28 её отсутствие ничего не доказывает: этой
   починки в том дереве ещё не было.)

**Починки F8 причину не устранили.**  `3a5279e` развёл один отказ на два предмета, `79c926f` научил
гейт слышать неудавшийся шаг карты.  Обе починки **уточнили формулировку**: ни одна не тронула путь,
на котором карта не пишется.  Сам дефект — волна 59.

**Причина не установлена — и потому не выдумана.**  В этом параграфе нет ни одной версии причины.
Что известно: это флак, а не устойчивый отказ (58 pass из 60); проявляется на двух разных деревьях в
разные дни; прямой прогон чека его не воспроизводит; в обоих случаях гейт ответил 0, начал вторую
попытку и карту не записал, а вывода второй попытки не оставил.  Дефект **открыт** и уходит в
следующую волну.

**Решения родителя (2026-11-22; правило вне §17.2 — владелец может отменить).**

* **Пакет закрывается пере-гейтом** — так же, как был закрыт пакет B2/B3/C2/C3 после того же
  флака: гейт 08:28 красный, гейты 08:55 и 11:07 зелёные.  Из семи гейтов проекта на этом чеке
  красных **два** (08:28 и 16:10), зелёных **пять** (08:55, 11:07, 12:49, 14:39, 15:15).  Это практика
  проекта, а не способ спрятать красную метку: метка записана здесь и остаётся видимой.
* **Причина не установлена — значит, не названа.**  То, что измерением исключено, названо
  исключённым; остальное названо открытым дефектом волны 59 вместе с его формой (вывод гейта
  обрывается на «attempt 2 of 3», вторая попытка без вывода, карта не записана).
* **Правка документации идёт до пересчёта** (§16.68).  Иначе доказательства claim'ов
  `the-owner-decided-the-order-of-the-next-waves` (в область входят `docs/PLAN.md` и
  `docs/ARCHITECTURE-CATCHUP-PLAN.md`) и `the-documentation-points-at-files-that-exist` (в область
  входят `AGENTS.md`, `README.md` и `ELISP_BEST_PRACTICES.md`) станут устаревшими, и карта
  покраснеет по-настоящему.

**Что остаётся за владельцем.**

* Причина флака волны 59 — открытый дефект; следующая волна.
* Push — по вашей команде.

### 16.116 Пере-гейт пакета волн D3, D4, E1, E2 и E3: красная метка ушла на другую проверку той же семьи — **2026-11-22**

**Что это.**  Находка о флаке волны 59 записана в документы (§16.115, коммит `c8ea6ce`), после чего
пакет пере-гейтили.  Гейт №2 (лог `/tmp/w-d3d4e-gate3.log`, дерево `c8ea6ce`) снова **красный**:
182 метки, из них 181 — форма 2, форма 3 — ноль, и **одна красная** — но теперь на **другом**
claim'е той же семьи:

    mathc: ./scripts/dev check tests/checks/check-a-check-that-hangs-is-stopped.el exited 1

Проверка волны 59 в этот раз прошла: её метка имеет форму 2 (укус), а не форму 1.  **Красная
метка ушла, а не исчезла** — и это стоит назвать прямо.

**Предмет отказа.**  «hang: the gate did not say that the check passed its limit»; вывод внутреннего
прогона, который попал в буфер проверки:

    scripts/dev-timeout: the command ran longer than 5s and was stopped

Claim — `the-gate-stops-a-check-that-hangs`; область — `scripts/dev-timeout`, `scripts/lib/tree.sh`,
`scripts/dev`, `tests/support/yeah-hanging-check-fixture.el`,
`tests/checks/check-a-check-that-hangs-is-stopped.el`; контроль —
`sed -i 's|^  stop_tree "$pid" TERM$|  : control|; s|^  stop_tree "$pid" KILL$|  : control|' scripts/dev-timeout`.

**Журнал метода: это первый отказ claim'а.**  По `the-gate-stops-a-check-that-hangs` в
`.math/v5/evidence.jsonl` — **62 записи: 61 pass и 1 fail**, и единственный отказ — этот.  То есть
за всю историю журнала claim отказался **впервые**.

**Механизм отказа — выведен из самого отказа.**  Проверка ждёт, пока внутренний прогон закончится,
и читает его вывод из буфера, который наполняет фильтр процесса.  В гейте буфер содержал **первую**
строку вывода внутреннего прогона и не содержал последних трёх.

1. **Внутренний прогон закончился кодом 3.**  Утверждение проверки «the gate answered N to the check
   that hangs, the third answer is 3» **не сработало** — значит код был 3.
2. **Код 3 в ветке `check` даёт только одна строка.**  `scripts/dev:335` — единственное место, где
   ставится `unknown=1`, и `scripts/dev:353` — единственный выход с этим кодом; других путей в этой
   ветке нет.
3. **Эта же строка печатает то, чего не хватило.**  `scripts/dev:336` печатает в stderr «the check
   passed the limit of ${limit}s and was stopped» — в stderr внутреннего прогона, то есть **в тот же
   пайп**, из которого наполняется буфер проверки.  Строка **была напечатана**.
4. **Буфер проверки её не содержал.**  Значит хвост пайпа ещё не дошёл до буфера.

**Вывод.**  Дефект — в чтении проверки: она ждёт смерти процесса и читает буфер, но **не ждёт, пока
пайп опустеет**.  Продуктовая сторона (гейт) ведёт себя правильно — это измерено.

**Что измерено (родитель, 2026-11-22).**

1. **Внутренний прогон напрямую: 10 из 10** — код 3 и строка «passed the limit of 5s» на месте.
2. **Сама проверка вне гейта: 15 из 15** — код 0.
3. **Проба порядка (эксперимент в `/tmp`, репозиторий не пишется): 6 из 6** — в момент смерти
   процесса строка уже в буфере (327 байт).  Окно гонки **узкое**, и проба его не поймала.
4. **Проверка волны 59 под нагрузкой: 20 прогонов** (пять рабочих по четыре) — все зелёные;
   инструментированная копия показывала карту на месте в момент чтения **каждый раз**.

**Следы прогона волны 59 — прямое свидетельство о состоянии каталога прогона.**  В `/tmp` осталось
14 каталогов проверки от прогонов дня.  Из них три **пусты** (08:37, 09:03), один содержит
`attempts` и **не содержит карты** (09:24), остальные содержат и `attempts`, и `map=complete`.
Проверка удаляет каталог прогона в конце своей работы — и в тех прогонах **удаление не закончилось**:
состояние каталога прогона к моменту чтения **не было устоявшимся**.  Это и есть то, что обе
красные метки показывают: проверки семейства гейта читают состояние внутреннего прогона, не дожидаясь
его.

**Что остаётся неустановленным.**  Причина флака волны 59 (§16.115) **не установлена** и здесь не
названа: 22 прямых прогона, 20 прогонов под нагрузкой и 15 прогонов соседней проверки зелёные, а
оставшиеся каталоги говорят о состоянии, а не о причине.  Причина второй красной метки установлена
**до гонки в чтении**, но сама гонка не воспроизведена — её окно узкое.

**Решения родителя (2026-11-22; правило вне §17.2 — владелец может отменить).**

* **Пакет закрывается пере-гейтом** — та же практика, что и в §16.115.  Красная метка записана
  здесь и остаётся видимой; наши claim'ы держатся в обоих гейтах пакета.
* **Дефекты обеих меток — волна семейства гейтов, а не этот пакет.**  Оба claim'а — волны 59 и
  `the-gate-stops-a-check-that-hangs`; оба о дефектах чтения состояния внутреннего прогона.  Это
  **следующая волна**: чтение состояния внутреннего прогона должно ждать, пока прогон успокоится.
* **Версия причины не названа там, где причина не установлена.**  Для волны 59 её нет; для второй
  метки названа гонка в чтении — и сказано, что она не воспроизведена.

**Что остаётся за владельцем.**

* Дефект чтения состояния внутреннего прогона (волны 59 и `the-gate-stops-a-check-that-hangs`) —
  следующая волна.
* Push — по вашей команде.

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
| 42 | Сервер не переживает агента: сессия кончилась — процесс ушёл | `the-server-exits-when-the-session-is-over` | сделано 2026-11-18 параллельной сессией — методом ACP `session/close` (`waves/wave-42.json`, §16.32) |
| 54 | Спин: сервер с молчащим провайдером не жжёт ядро | `the-server-does-not-spin-when-the-provider-is-silent` | сделано 2026-11-18 (§16.38) |
| 43 | Поверхность ACP для оркестратора: `cwd`, род вызова и именованные аргументы, `session/set_mode`, модель, `mcpServers` | шесть claim'ов §18.3 | сделано 2026-11-18 в пяти частях (§16.33–§16.37) |
| 65 | Исход прогона на проводе (P-B) | `the-wire-tells-how-the-run-ended` | сделано 2026-11-19 (§16.49) |
| 66 | Серверы MCP сессии говорят по HTTP (транспорт, без которого агент не запускается в Paseo) | `the-mcp-servers-of-a-session-speak-http` | сделано 2026-11-19 (§16.50) |
| 67 | Проба каталога не оставляет пустых сессий (P-C) | `the-probe-of-the-catalog-leaves-no-empty-session` | сделано 2026-11-19 (§16.51) |
| 68 | Журнал не теряет запись, в которой есть список (дефект, который нашёл живой прогон) | `the-journal-writes-a-list-as-an-array` | сделано 2026-11-19 (§16.53) |
| 69 | Ответ `session/prompt` несёт расход хода (токены, которые сообщил провайдер) | `the-prompt-response-carries-the-usage-of-the-turn` | сделано 2026-11-19 (§16.55) |
| 70 | Журнал держит расход одного запроса один раз (дефект, который нашёл живой прогон) | `the-journal-holds-the-usage-of-a-request-once` | сделано 2026-11-19 (§16.56) |
| 71 | Оркестратор видит расход хода (токены хода доходят до счётчика агента) | `the-orchestrator-sees-the-usage-of-the-turn` | сделано 2026-11-19 (§16.57) |
| 72 | Плагин говорит с ядром по сокету (сервисное размещение, P-D) | `the-plugin-talks-to-the-core-over-a-socket` | сделано 2026-11-19 (§16.58) |
| 73 | Плагин направляет уточнение в идущий ход (steering, P-A) | `the-plugin-steers-the-turn-instead-of-replacing-it` | сделано 2026-11-19 (§16.59) |
| 74 | Мёртвый сокет не проходит за живой сервис (дефект, который нашёл живой прогон) | `a-dead-socket-does-not-pass-for-a-live-service` | сделано 2026-11-19 (§16.60) |
| 76 | Профиль без человека: режим `auto` едет по проводу и не спрашивает (решение владельца §5.1) | `a-session-may-work-without-a-person`, `a-delete-goes-to-the-trash` | сделано 2026-11-19 (§16.65) |
| — | Починка двух зарегистрированных контролей, которые никогда не кусались (реестр метода, не код) | `the-prompt-response-carries-the-usage-of-the-turn`, `a-tool-that-returns-bytes-does-not-kill-the-harness` | сделано 2026-11-19 (§16.61) |
| 44 | Дети параллельно в живом ходу | `two-children-run-in-one-turn-of-the-parent`, `a-child-runs-on-the-model-of-its-preset` | следующий по плану владельца |
| 51 | Журнал прогона защищён от прогона | — | по §16.30 |
| 52 | `cwd` сессии доходит до инструментов, если волна 43 не доводит | — | условно: волна 43 довела |

Волны 77 и дальше идут по другому порядку — догоняющему плану
(`docs/ARCHITECTURE-CATCHUP-PLAN.md`): код догоняет архитектуру, и волны
схем идут после кода.  Из них в этот список попала только волна 76: её
режим `auto` закрывает пункт §5.1, а остальные волны — волны ядра, а не
интеграции с оркестратором.

Вне плана владельца (детали и места — `docs/PASEO-INTEGRATION-PLAN.md` §4.2):
- **P-A.**  Маршрут ACP в Paseo отказывает в steering'е
  (`packages/plugin/src/server/acp.test.ts:766`), хотя ядро умеет
  (`lib/yeah-acp.el`, `session/steer`).  Правка лежит в чужом репозитории
  (`/home/az/Projects/paseo`): решение владельца — апстрим PR или форк.
  **Обойдено 2026-11-19** (волна 73): плагин объявляет `prompt.steer` и сам
  переводит запрос в `session/steer` ядра, — так что правка в чужом репозитории
  больше не нужна, чтобы steering работал для агента Yeah.  Адаптер библиотеки
  steering по-прежнему не понимает, и апстрим-правка (или форк) остаётся
  решением владельца (§16.59).
- **P-B.**  Исход прогона не виден оркестратору: по проводу шли восемь видов
  событий, а `usage`, `nudge`, `unfinished` и `error` — нет.  Механизм
  расширения уже есть (`yeah.queueEvents` в `_meta`).  **Сделано 2026-11-19**
  (волна 65): `usage_update` и `yeah/outcome` едут за тем же объявлением в
  `_meta`, что и события очереди.
- **P-C.**  Discovery создаёт настоящую сессию: каждый список моделей
  оставляет сессию в журнале.  **Сделано 2026-11-19** (волна 67): файл сессии
  появляется, когда сессия пишет первую запись, и проба каталога не оставляет
  ничего (§16.51).
- **P-D.**  Плагин поднимает свой Emacs на каждое соединение вместо
  сервисного по сокету.  Плагин живёт в этом репозитории
  (`plugin/yeah-provider/`), поэтому это теперь работа без чужого дерева.
  **Код готов 2026-11-19** (волна 72): переключение — одна настройка
  `serviceMode`, умолчание прежнее (`spawn`, свой Emacs на соединение).
  **Открыто** — эксплуатационная модель сервисного размещения решает владелец
  (§5.3, §16.58).

**Находка сессии 2026-11-18, которая двигала план — закрыта 2026-11-18.**
`session/close` — не выдумка: это метод ACP, и клиент Paseo его **уже
вызывает**.  В SDK он уехал как `unstable_closeSession`
(`sendRequest("session/close")`), а клиент оркестратора зовёт `closeSession()`
при закрытии сессии агента
(`packages/plugin/src/server/acp-internal/connection.ts:690-698`) и глотает
ошибку (`.catch(() => undefined)`).

Два пути были: ядро отвечает и на `session/close` (метод ACP), и на
`session/exit` (расширение); или плагин переводит `session/close` клиента в
`session/exit` ядра.  **Выбран первый, и он честнее по протоколу:** `session/close`
— часть ACP, и клиент, который его знает, не должен ждать расширения.  Волна 42
ответила именно так, и живой прогон 2026-11-19 показал, что `initialize`
объявляет `sessionCapabilities.close`.

**Живая сверка 2026-11-19.**  Прогон тем же протоколом, каким шлёт Paseo
(`plugin/yeah-provider/scripts/probe-acp.ts`), против настоящего провайдера:
`initialize` отвечает, `session/new` отвечает режимами и моделью, промпт
доезжает до модели, ответ модели доезжает до клиента, вызов инструмента несёт
свой род и именованные аргументы, `stopReason` — `end_turn`
(`docs/LIVE-EVIDENCE.md`).  Чего этот прогон не доказал: что оркестратор
показывает это в интерфейсе.

**Что остаётся за владельцем.**  Порог паритета и итоговый набор задач
бенчмарка (§13); «провайдер заsilenceл» — это провал агента или непомеренный
запуск (§17.2); бюджет надзора дочернего агента (§18.5); апстрим или форк
для P-A (steering уже обойдён волной 73, но адаптер библиотеки оркестратора
по-прежнему его не понимает); сервисное размещение плагина против пакетного
Emacs (§5.3; код готов волной 72, выбрано не размещение); нужен ли
профиль разрешений без человека (§5.1) — **решено 2026-11-19: нужен**
(волна 76, §16.65; профиль `auto`, граница агента — учётная запись
пользователя и корзина, `docs/AGENT-SAFETY.md`).

### 19.1 Порядок работы: пакет волн вместо одиночной волны

**Решение владельца от 2026-11-19 (az).**  До этого каждая волна проходила
полный цикл сам по себе: код, проверка, кусающийся контроль, документация и
пересчёт метода.  Цикл занимал больше времени, чем волна, и два пересчёта
были потеряны из-за правок дерева во время прогона.  Владелец утвердил
порядок работы:

1. **Пересчёт — раз на пакет волн (5–7), а не на волну.**  Лимит прогона не
   меньше 3600 секунд, и дерево во время прогона не правится: правка во время
   пересчёта помечает материалы как изменившиеся и делает карту честно
   непрозрачной.
2. **Пакет — это код, проверки, контроли, документация и один пересчёт.**
   Волна внутри пакета своего пересчёта не требует.
3. **Документацию пишет воркер**, пока агент пишет код.  2026-11-19 это
   сработало: четыре файла документации волн 69–70 были написаны, пока шла
   волна 71.
4. **Полный гейт — после пакета.**  После волны проходят её проверка и её
   кусающийся контроль.
5. **Живой прогон — один на пакет**, с коротким промптом: «Ответь только
   словом OK и вызови finish».
6. **Чужой репозиторий обходится, а не чинится.**  Правки в
   `/home/az/Projects/paseo` — решение владельца (апстрим или форк), а не
   работа пакета.
7. **Лог гейта читается по трём меткам.**  Провал положительного прогона
   печатается строкой `mathc: <команда> exited <код>` — метки `verifier:`
   в ней нет, вместо неё стоит сама команда.  Укус отрицательного контроля
   печатается строкой `mathc: verifier after negative control: <команда>
   exited <код>` и так и должен выглядеть: контроль, который кусается,
   отрабатывает провалом проверки.  Третья форма — `mathc: negative control:
   <контроль> exited <код>` — это провал постановки самого контроля, а не его
   укус.  Чтение лога, где каждая строка с `exited 1` принята за красный
   тест, даёт ложную тревогу: так юнит-тест
   `yeah-context-estimate-is-cjk-aware` выглядел красным в гейте пакета
   93–96 (2026-11-21), хотя это был укус контроля claim'а `unit-tests-pass` —
   мутация `(/ cjk 2.0)` → `(/ cjk 1.0)` в `lib/yeah-context.el:69` даёт
   ровно то значение `4`, что и было записано в провале.  В том гейте строк
   с меткой `mathc:` было 161, и все они относились к форме укуса; строк
   двух других форм не было ни одной.

§19 остаётся порядком волн; этот список — порядком работы над ними.  Первым
пакетом после решения стали волны 65–71 (2026-11-19): пересчёт пакета дал
карту без непокрытых материалов и с одной причиной `unknown` — устаревшим
доказательством решения владельца об этом самом порядке.

Пункт 7 добавлен родителем 2026-11-21: это способ чтения артефакта, а не
изменение нормы кода, и решение о нём не в списке §17.2.  Владелец может его
отменить.  Правка сделана до гейта пакета 97–99, чтобы доказательство этого
пакета покрывало и её.
