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

### The order

16.1 first (it is small and it is the last piece of the kernel), then
16.2 and 16.3 together (the service becomes the default when the control
is whole), then 16.4 and 16.6 (the product works everywhere and is seen),
then 16.7 (the goal is measured), and 16.5 and 16.8 whenever.


Re-opened when a person says so: the math-coding aim block in AGENTS.md is
written by `mathc install` and is not edited by hand.
