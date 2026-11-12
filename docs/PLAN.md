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

Verified on 2026-11-12 in this checkout:

- all 33 `lib/` modules byte-compile without warnings;
- 198/198 ERT unit tests pass;
- all 23 canaries pass when run directly (`./scripts/dev check tests/checks/*`);
- the installed `mathc` does not accept the `--root` invocation used by
  `scripts/dev`, so the map/gate needs a compatible pinned tool;
- live provider behavior was not verified during that review.

The code contains a working kernel and a working wire, but not yet a usable
product:

- `yeah-shell.el` echoes a stub rather than running a turn;
- sub-agent execution is a placeholder, and the three placements are not
  implemented;
- the stdio server answers one request at a time, so a cancel cannot preempt
  a running prompt;
- global registries/rules and incomplete event correlation obstruct isolated
  concurrent runs;
- the PTC whitelist was experimentally bypassed with a permitted higher-order
  function and a quoted `delete-file` symbol. It is not a safe boundary.

The first stages therefore prioritize truth, security and a vertical slice,
not additional protocols.

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

ACP and service mode are delayed deliberately: they must transport a working
kernel, not conceal missing execution behind protocol handlers. Minimal
Emacs-native UI and installation come before them because they validate the
actual user experience.

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

**0.4 Make the evidence toolchain reliable.** **Status: deferred pending the
math-coding v5 migration.** v4 is frozen; its map/run/gate commands were not
run during Stages 0.1–0.3. Ordinary byte compilation, ERT and direct canary
execution remain the active local checks.

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

### Exit criteria

The integration scenario “start → steer → cancel → restart Emacs → inspect
partial results → deliberately recover input” works. No late callback changes
a terminal run; no hidden infinite nudge/retry loop exists.

## 7. Stage 4 — installable interactive product (public alpha)

### Intent

A person can install and use Yeah without reading source or developer docs.

**Status: implemented offline on 2026-11-11.** `yeah.el` declares package
requirements and exposes `M-x yeah`, `M-x yeah-ask` and `M-x yeah-doctor`.
The journal buffer renders events from the journal, supports ask/steer/
cancel/recover/withdraw/diff and refreshes without blocking.  Sessions and
pending input use private project-scoped data directories.  `install/
yeah-bootstrap.el` documents the clean-Emacs package-vc path.  The public
alpha gate remains open because bootstrap has not been network-tested and a
live-provider interactive task has not been run.

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

### Alpha release gate

On a clean supported Emacs, one documented installation action and backend
configuration lead to the Stage 1 coding task in the interactive UI. The user
can approve, steer, cancel, inspect the diff, quit, restart and resume. No
credentials appear in logs. Unit/canary/integration suites pass.

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

**Two limitations are not hidden.** The stdio server answers one request at a
time, so a cancel that arrives during a prompt is read after that prompt
reaches a terminal state: preemption is not implemented. And no third-party
client or editor has driven either server yet; the wire checks use Yeah's own
processes.

### Work items

- JSON-RPC stdio framing using the project's chosen `jsonrpc` adapter;
- real ACP initialize/new/prompt/update/cancel/load behavior against the
  current protocol schema;
- MCP server with actual registry handlers, argument validation and bounded
  results;
- MCP client with namespaced imported tools and independent permission rules;
- backpressure, malformed-message handling, shutdown and cancellation;
- protocol redaction and trust documentation.

Use `../emacs-agents-research/acp.el/` and the ACP specification as references,
not as runtime dependencies.

### Exit criteria

A real ACP editor completes the Stage 1 scenario, including streaming and
cancel. An external MCP client lists and calls explicitly published Emacs
capabilities. The same canonical journal semantics hold as in interactive use.

The first two criteria are **open**: they need a third-party client and a
live provider, neither of which was available in this environment.

## 9. Stage 6 — attached, service and batch placements

### Intent

One kernel, three operational forms, no hidden global run state.

### Work items

- Move session registry, policy, cancellation and configuration into run
  contexts;
- attached placement with nonblocking interactive behavior;
- service placement in a dedicated Emacs with lifecycle management;
- batch entry for CI/benchmarks with explicit headless allowlists;
- emacsclient bridge to a person's buffers as a separately approved tool;
- canonical event comparison across placements, excluding timestamps/random
  ids and explicitly transport-specific metadata.

### Exit criteria

The same scripted task produces equivalent semantic events in all three
placements. Service cannot access attached buffers without the bridge
capability. Batch returns a useful exit code and durable journal.

## 10. Stage 7 — declarative delegation and ecosystem

### Intent

Implement the Y in Yeah: bounded, inspectable recursive work.

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

## 11. Continuous quality and 1.0 release gates

### Benchmark suites

1. **General coding:** identical initial repositories, tasks, model and
   budgets for Yeah/opencode/pi; score verified task success, time, tokens,
   cost and human interventions.
2. **Emacs-native:** live buffers, Eglot, Magit, Org and introspection tasks;
   these test the architectural advantage, not just parity.
3. **Robustness:** long sessions, network failures, duplicate callbacks,
   malformed data, cancellation, crash/restart and output floods.
4. **Fixed point:** the Yeah-on-Yeah canary repair with a reviewable result.

### 1.0 requires

- stages 0–7 closed by current claims and controls;
- clean installation and the interactive vertical slice passing on every
  supported Emacs/gptel combination;
- no known security-boundary bypass or public placeholder path;
- durable recovery and cancellation integration tests passing;
- benchmark results published with methodology, including losses;
- README limitations, security/privacy guide, architecture, engineering
  guidance and user documentation current;
- package checks clean and a versioned release with migration policy.

## 12. Immediate execution order

Start with a small, reviewable Stage 0 sequence:

1. repair the gptel contract and remove the dead hook (0.1);
2. quarantine PTC and add its exploit regression (0.2);
3. add and satisfy U1–U4 canaries (0.3);
4. restore a reliable map/gate toolchain (0.4);
5. reconcile module comments and claims (0.5).

Do not start ACP, service mode or sub-agents before the corresponding earlier
exit criteria hold. Each implementation commit should be small enough to
review and should include its tests, control and documentation update.

## 13. Decisions still requiring product ownership

These are not implementation details for an agent to decide silently:

- exact minimum Emacs/gptel versions and release cadence;
- default unattended capabilities and command/network policy;
- whether restricted evaluation deserves a separate process design at all;
- service-mode access to personal buffers;
- package distribution channels (MELPA/ELPA/bootstrap) and signing;
- final benchmark task set and acceptable parity threshold;
- whether Apache-2.0 remains compatible with every optional integration.
