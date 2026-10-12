# Yeah v0.1.0-alpha — ROADMAP

> **Status (2026-10-12, all tiers closed as stubs):**
> Tier 0, Tier 1, Tier 2, Tier 3, and Tier 4 tasks are all landed
> as stubs. The wire layer (ACP, emcp) speaks the protocol but
> defers real network IO; the tool handlers return placeholder
> strings; the LLM call lives in `lib/yeah-gptel.el` as a stub
> that does not yet call gptel. v0.2 will replace the stubs with
> real implementations; the v0.1 wire surface is stable.

## Working chain (recap)

```text
intent -> decision -> obligation -> change -> attestation -> revision
```

Every commit on `main` closes at least one obligation. No obligation
closes without a positive + negative fixture pair. No kernel change
ships without a `decisions/*.yaml` decision under the active policy.

## Priority queue (highest leverage first)

### Tier 0 — bootstrap: closed

| # | Task | Decision | Status |
|---|---|---|---|
| ~~1~~ | `AGENTS.md`, `ROADMAP.md`, `PACKAGES.md` | bootstrap-yeah@0 | **closed** |
| ~~2~~ | `scripts/dev` stub | bootstrap-yeah@0 | **closed** in commit `3ed5a51` |
| 3 | `lib/yeah-state.el` (12 states) | `tick-state-machine@2` | **closed** in commit `5bca3e2` |
| 4 | `lib/yeah-loop.el` (18 transitions) | `tick-state-machine@2` | **closed** in commit `8e2f324` |

### Tier 1 — process hardening: closed

| # | Task | Decision | Status |
|---|---|---|---|
| 6 | `lib/yeah-validate.el` + `scripts/dev validate` | `process-principles@0` | **closed** in commit `93ffe8f` |
| 10 | `ELISP_BEST_PRACTICES.md §11.1` first trap entry | `process-principles@0` | **closed** in commit `5757b02` |
| 11 | `tests/unit/test-process-principles.el` (P1/P2/P5/P6) | `process-principles@0` | **closed** in commit `5757b02` |

### Tier 2 — wire layer: closed (stubs)

| # | Task | Decision | Status |
|---|---|---|---|
| 12 | `lib/yeah-gptel.el` | `gptel-hook-surface@0` | **closed** in commit `a587876` (stub: prelude + pass-through; no gptel call yet) |
| 13 | `lib/yeah-acp.el` + `schemas/acp-v1.json` | `acp-handlers@0` | **closed** in commit `a587876` (7 ERT cases pass) |
| 14 | `lib/yeah-emcp.el` + `schemas/emcp-v1.json` | `emcp-tool-surface@0` | **closed** in commit `a587876` (8 ERT cases; 9 first-wave tool ids registered as stubs) |

### Tier 3 — agent loop kernel: closed

| # | Task | Decision | Status |
|---|---|---|---|
| 17 | `lib/yeah-loop.el` full FSM (already covered) | `tick-state-machine@2` | **closed** in commit `8e2f324` |
| 18 | `lib/yeah-tools.el` | `tools-registry@0` | **closed** in commit `b6d03cf` (9 ERT cases; built-in `read` tool) |
| 19 | `lib/yeah-perm.el` | `perm-impl@0` | **closed** in commit `b6d03cf` (8 ERT cases) |
| 20 | `lib/yeah-session.el` | `session-impl@0` | **closed** in commit `b6d03cf` (7 ERT cases; append-only JSONL) |
| 21 | `lib/yeah-shell.el` | `shell-impl@0` | **closed** in commit `2c1859c` (7 ERT cases) |

### Tier 4 — code-mode + sub-agent + compaction: closed (stubs)

| # | Task | Decision | Status |
|---|---|---|---|
| 22 | `lib/yeah-codes.el` (sandbox.el-PTC stub) | `codes-impl@0` | **closed** in commit `7381d3e` (8 ERT cases; JSON-clean boundary; real sandbox.el is `codes-impl@1`) |
| 23 | `lib/yeah-subagent.el` | `subagent-impl@0` | **closed** in commit `7381d3e` (7 ERT cases) |
| 24 | `lib/yeah-compact.el` | `compact-impl@0` | **closed** in commit `7381d3e` (7 ERT cases) |
| 25 | `lib/yeah-undo.el` | `undo-impl@0` | **closed** in commit `7381d3e` (8 ERT cases) |

## What v0.2 should add (deferred, not in v0.1.0-alpha)

- `codes-impl@1` — wire the real `sandbox.el`; require Emacs 29+
  for the codes-mode path.
- `subagent-impl@1` — async gptel integration; child buffer
  runs the loop independently.
- `compact-impl@1` — real gptel-driven summarization.
- `gptel-hook-surface@1` — the real gptel call (currently a
  pass-through that just prints a message).
- `tools-registry@1` — wire the rest of the tool surface
  (write, edit, bash, grep, webfetch).
- `wire-v1@1` — stdio loop for the ACP agent; same for the
  emcp MCP server.
- ACP v2 surface (when the draft stabilises).

## Test totals

| File | Cases |
|---|---|
| test-yeah-state.el | 8 |
| test-yeah-loop.el | 14 |
| test-yeah-validate.el | 2 |
| test-yeah-gptel.el | 4 |
| test-yeah-acp.el | 7 |
| test-yeah-emcp.el | 8 |
| test-yeah-tools.el | 9 |
| test-yeah-session.el | 7 |
| test-yeah-perm.el | 8 |
| test-process-principles.el | 4 |
| test-yeah-codes.el | 7 |
| test-yeah-compact.el | 8 |
| test-yeah-undo.el | 8 |
| test-yeah-subagent.el | 7 |
| test-yeah-shell.el | 7 (added in Tier 3 #21) |
| **Total** | **108** (7+7+14+2+4+7+8+9+7+8+4+8+8+7) |

(Tests run in order: `bash tests/unit/test-scripts-dev.sh`
plus `emacs -Q --batch -L lib -l tests/unit/test-yeah-*.el -f
ert-run-tests-batch-and-exit` for each test file.)

## Author / license / active policy

- **Author**: Petr Kosov &lt;p.b.kosov@yandex.ru&gt;
- **License**: Apache-2.0
- **Active policy**: `bootstrap-yeah@0` (see `decisions/decision.yaml`)
