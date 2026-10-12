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
| `decisions/acp-wire-v1.yaml` | Speak ACP v1 (agent side) | active |
| `decisions/emcp-mcp-server.yaml` | Expose Emacs as MCP server (`emacs__*` tools) | active |
| `decisions/tick-state-machine.yaml` | The agent loop is a 10-state FSM with 18 transitions | active |
| `decisions/append-only-session-log.yaml` | Session log is append-only JSONL; compaction is projection, not deletion | active |
| `decisions/sandbox-elisp-codes-mode.yaml` | Code-mode is sandbox.el + JSON-clean boundary + whitelist | active |
| `decisions/elisp-toolchain-only.yaml` | `lib/` is Elisp-only (no compiled languages) | active |
| `decisions/process-principles.yaml` | P1–P7 binding obligations; P3/P4 are manual-acceptance | active |

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
| `lib/yeah-state.el` | The 10 FSM states | planned (Tier 0) |
| `lib/yeah-loop.el` | The agent loop | planned (Tier 0 skeleton) |
| `lib/yeah-tools.el` | Tool registry | planned (Tier 3) |
| `lib/yeah-perm.el` | Permission system | planned (Tier 3) |
| `lib/yeah-session.el` | Append-only JSONL log | planned (Tier 3) |
| `lib/yeah-compact.el` | Compaction (projection) | planned (Tier 4) |
| `lib/yeah-codes.el` | Sandbox.el-PTC | planned (Tier 4) |
| `lib/yeah-undo.el` | Per-tick undo-boundary | planned (Tier 4) |
| `lib/yeah-gptel.el` | gptel hook integration | planned (Tier 2) |
| `lib/yeah-acp.el` | ACP agent side | planned (Tier 2) |
| `lib/yeah-emcp.el` | MCP server side (`emcp` tools) | planned (Tier 2) |
| `lib/yeah-shell.el` | REPL in `*yeah-shell*` | planned (Tier 3) |

## Schemas (by file)

| File | What it is | Status |
|---|---|---|
| `schemas/acp-v1.json` | ACP v1 wire surface (subset we use) | planned |
| `schemas/emcp-v1.json` | `emcp` tool registry | planned |
| `schemas/session-event.json` | JSONL event shape for the append-only log | planned |

## Fixtures

To be created as the corresponding kernel module lands. Each
decision that adds capability has a positive + negative fixture
pair obligation.

| File pattern | Purpose |
|---|---|
| `tests/fixtures/positive/loop-*.el` | FSM transitions that must work |
| `tests/fixtures/negative/loop-*.el` | FSM transitions that must be rejected |
| `tests/fixtures/positive/acp-*.json` | ACP messages that must round-trip |
| `tests/fixtures/negative/acp-*.json` | ACP messages that must be rejected |
| `tests/fixtures/positive/emcp-*.json` | `emcp` tool calls that must work |
| `tests/fixtures/negative/emcp-*.json` | `emcp` tool calls that must be rejected |
| `tests/fixtures/positive/session-*.el` | Append-only log scenarios |
| `tests/fixtures/negative/session-*.el` | Forbidden log mutations |
| `tests/fixtures/positive/codes-*.el` | Sandbox.el-PTC scenarios that work |
| `tests/fixtures/negative/codes-*.el` | Sandbox.el-PTC scenarios that fail safely |

## Tests (by file)

| File | What it asserts |
|---|---|
| `tests/unit/test-yeah-state.el` | The 10 states exist; transitions are well-formed |
| `tests/unit/test-yeah-loop.el` | The 18 transitions trigger in isolation |
| `tests/unit/test-process-principles-p1.el` | Read-first order in `AGENTS.md` |
| `tests/unit/test-process-principles-p2.el` | Decision ↔ fixture pairing |
| `tests/unit/test-process-principles-p5.el` | `scripts/dev edit-loop-detect` exists |
| `tests/unit/test-process-principles-p6.el` | `scripts/dev byte-compile-all` exists and is clean |

## Deficits

No deficits logged yet. The format will be
`obligations/DEFICIT-<short-slug>.yaml` with the fields `rule`,
`subject`, `reason`, `remedy`.
