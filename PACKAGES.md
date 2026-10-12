# Yeah v0.0.0-alpha — PACKAGES

> Single source of truth for **what exists** in this repository.
> Read this to find which decision file to read or which fixture
> to modify; it supersedes any inline "where things live" lists
> elsewhere in the project.

## Active policy

`bootstrap-yeah@0` — see `decisions/decision.yaml`. All changes
under the policy; superseded only by a protected-policy transition
(see `AGENTS.md §"Self-application"`).

## Bootstrap packages (by file)

| File | What it is | Status |
|---|---|---|
| `decisions/decision.yaml` | Active policy (`bootstrap-yeah@0`) | active |
| `decisions/emacs-native-runtime.yaml` | Emacs is the run-time, not a client over a sidecar | active |
| `decisions/gptel-as-transport.yaml` | `gptel` is the only LLM transport | active |
| `decisions/gptel-hook-surface.yaml` | The three gptel hooks `lib/yeah-gptel.el` registers | active |
| `decisions/acp-wire-v1.yaml` | Speak ACP v1 (agent side) | active |
| `decisions/emcp-mcp-server.yaml` | Expose Emacs as MCP server (`emacs__*` tools) | active |
| `decisions/tick-state-machine.yaml` | The agent loop is a 10-state FSM with 18 transitions | active |
| `decisions/append-only-session-log.yaml` | Session log is append-only JSONL; compaction is projection, not deletion | active |
| `decisions/sandbox-elisp-codes-mode.yaml` | Code-mode is sandbox.el + JSON-clean boundary + whitelist | active |
| `decisions/elisp-toolchain-only.yaml` | `lib/` is Elisp-only (no compiled languages) | active |
| `decisions/process-principles.yaml` | P1–P7 binding obligations; P3/P4 are manual-acceptance | active |
| `decisions/compact-impl@0.yaml` | The compactor (Tier 4 #24); pure projection over the append-only log | landed (Tier 4 #24) |

## Modules (by file)

| File | What it is | Status |
|---|---|---|
| `AGENTS.md` | Agent protocol — read first | v0 |
| `ROADMAP.md` | Single source of truth for priorities | v0 |
| `PACKAGES.md` | This file | v0 |
| `README.md` | Short pitch and pointers | v0 |
| `LICENSE` | Apache-2.0 | v0 |
| `NOTICE` | Apache-2.0 attribution | v0 |
| `VERSION` | v0.0.0-alpha tag | v0 |
| `scripts/dev` | CLI wrapper (byte-compile, validate, self-check) | stub |
| `ELISP_BEST_PRACTICES.md` | Elisp toolchain conventions; §11 is the trap log | placeholder |

## Kernel modules (by file)

| File | What it is | Status |
|---|---|---|
| `lib/yeah-state.el` | The 12 FSM states | landed (Tier 0 #3) |
| `lib/yeah-loop.el` | The agent loop (12 states, 18 transitions) | landed (Tier 0 #4) |
| `lib/yeah-validate.el` | The decision-driven validator | landed (Tier 1 #6) |
| `lib/yeah-loop.el` | The agent loop (12 states, 18 transitions) | landed (Tier 0 #4) |
| `lib/yeah-tools.el` | Tool registry | landed (Tier 3 #18) |
| `lib/yeah-perm.el` | Permission system | landed (Tier 3 #19) |
| `lib/yeah-session.el` | Append-only JSONL log | landed (Tier 3 #20) |
| `lib/yeah-compact.el` | Compaction (projection) | planned (Tier 4) |
| `lib/yeah-subagent.el` | Sub-agent delegation API (stub) | landed (Tier 4 #23) |
| `lib/yeah-codes.el` | Sandbox.el-PTC (stub; `sandbox.el` integration in `codes-impl@1') | landed (Tier 4 #22) |
| `lib/yeah-undo.el` | Per-tick undo-boundary | landed (Tier 4 #25) |
| `lib/yeah-gptel.el` | gptel hook integration | landed (Tier 2 #14) |
| `lib/yeah-acp.el` | ACP agent side | landed (Tier 2 #12) |
| `lib/yeah-emcp.el` | MCP server side (`emcp` tools) | landed (Tier 2 #13) |
| `lib/yeah-shell.el` | REPL in `*yeah-shell*` | landed (Tier 3 #21) |

## Schemas (by file)

| File | What it is | Status |
|---|---|---|
| `schemas/acp-v1.json` | ACP v1 wire surface (subset we use) | landed (Tier 2 #12) |
| `schemas/emcp-v1.json` | `emcp` tool registry | landed (Tier 2 #13) |
| `schemas/session-event.json` | JSONL event shape for the append-only log | planned |

## Fixtures

To be created as the corresponding kernel module lands. Each
decision that adds capability has a positive + negative fixture
pair obligation.

| File pattern | Purpose |
|---|---|
| `tests/fixtures/positive/loop-*.el` | FSM transitions that must work |
| `tests/fixtures/negative/loop-*.el` | FSM transitions that must be rejected |
| `tests/fixtures/positive/yeah-gptel-prompt-with-prelude.el` | A transformed prompt carries the prelude |
| `tests/fixtures/negative/yeah-gptel-prompt-without-prelude.el` | A raw prompt (no prelude) is a drift |
| `tests/fixtures/positive/acp-*.json` | ACP messages that must round-trip |
| `tests/fixtures/negative/acp-*.json` | ACP messages that must be rejected |
| `tests/fixtures/positive/emcp-*.json` | `emcp` tool calls that must work |
| `tests/fixtures/negative/emcp-*.json` | `emcp` tool calls that must be rejected |
| `tests/fixtures/positive/session-*.el` | Append-only log scenarios |
| `tests/fixtures/negative/session-*.el` | Forbidden log mutations |
| `tests/fixtures/positive/codes-*.el` | Sandbox.el-PTC scenarios that work |
| `tests/fixtures/negative/codes-*.el` | Sandbox.el-PTC scenarios that fail safely |
| `tests/fixtures/positive/yeah-compact-cut.el` | Compactor finds the cut-point and writes a projection | landed (Tier 4 #24) |
| `tests/fixtures/negative/yeah-compact-cut-noop.el` | Compactor is a no-op when the budget exceeds every record | landed (Tier 4 #24) |

## Tests (by file)

| File | What it asserts |
|---|---|
| `tests/unit/test-yeah-state.el` | The 10 states exist; transitions are well-formed |
| `tests/unit/test-yeah-compact.el` | The compactor finds the cut-point, returns nil when over-budget, summarises (default + custom), runs no-op or records, projection length shrinks | landed (Tier 4 #24) |
| `tests/unit/test-yeah-gptel.el` | The three gptel hooks are installed, the prelude is prepended, the FSM handler accepts valid shapes, missing-gptel is a no-op |
| `tests/unit/test-yeah-loop.el` | The 18 transitions trigger in isolation |
| `tests/unit/test-yeah-perm.el` | Permission rule registry, matching algorithm, last-matching-wins | landed (Tier 3 #19) |
| `tests/unit/test-process-principles.el` | P1, P2, P5, P6 conformance | landed (Tier 1 #11) |
| `tests/unit/test-yeah-subagent.el` | Sub-agent delegation API: spawn returns completed, creates a child session, wait returns the same plist, fork-summary includes the id, depth limit default = 3 and overridable, depth-0 allowed | landed (Tier 4 #23) |

## Deficits

No deficits logged yet. The format will be
`obligations/DEFICIT-<short-slug>.yaml` with the fields `rule`,
`subject`, `reason`, `remedy`.
