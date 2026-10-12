# Yeah v0.0.0-alpha — ROADMAP

> **Status (2026-10-12, skeleton):** the project is at
> `v0.0.0-alpha`. The 9 active decisions under `decisions/` are
> the load-bearing artefacts; no kernel source exists yet. The
> roadmap below is the single source of truth for what Yeah does,
> in what order, and why.

## Working chain (recap)

```text
intent -> decision -> obligation -> change -> attestation -> revision
```

Every commit on `main` closes at least one obligation. No obligation
closes without a positive + negative fixture pair. No kernel change
ships without a `decisions/*.yaml` decision under the active policy.

## Priority queue (highest leverage first)

### Tier 0 — skeleton: open

The skeleton consists of the **9 active decisions** plus the
documents they reference. Tier-0 closes when the
`scripts/dev` wrapper exists, the first `lib/yeah-*.el` file
byte-compiles, and the first positive + negative fixture pair
runs under ERT.

| # | Task | Decision | Closes | Effort |
|---|---|---|---|---|
| 1 | All 9 decisions on `main` | (this Tier) | the policy skeleton | done |
| 2 | `scripts/dev` stub | `elisp-toolchain-only@0` | the canonical CLI surface | small |
| 3 | `lib/yeah-state.el` (10 states, no transitions yet) | `tick-state-machine@0` | the kernel's first module | small |
|   |  ↑ closed in commit (this Tier) |  |  |  |
| 4 | `lib/yeah-loop.el` skeleton (no tool calls yet) | `tick-state-machine@0` | the loop entry | small |
|   |  ↑ closed in commit (this Tier) |  |  |  |
| 5 | ERT fixture pair (positive + negative) for `yeah-state-init` | `tick-state-machine@0` | first obligation closure | small |

Once Tier 0 closes, the bootstrap gate will be reconsidered:
closure means `emacs -Q --batch -l scripts/dev byte-compile-all`
exits 0 and the first ERT pair is green.

### Tier 1 — process hardening (after bootstrap)

| # | Task | Decision | Closes |
|---|---|---|---|
| 6 | `yeah validate` (smoke: read-first, fixture-pair, axiom-link) | `process-principles@0` | the seven P1–P7 obligations |
|   |  ↑ closed in commit (this Tier) |  |  |  |
| 7 | `yeah gate BASE HEAD` (compliance verdict) | (TBD) | cross-decision conformance |
| 8 | `yeah self-check` (CI blocking) | (TBD) | admin-gate automation |
| 9 | Pre-commit hook (decision-required) | `process-principles@0` | drift detection |
| 10 | `ELISP_BEST_PRACTICES.md §11` (trap log) | `process-principles@0` | agent memory |
| 11 | `tests/unit/test-process-principles-*.el` (P1, P2, P5, P6) | `process-principles@0` | machine-checkable subset |

### Tier 2 — wire layer (ACP + emcp)

| # | Task | Decision | Closes |
|---|---|---|---|
| 12 | `lib/yeah-acp.el` (ACP JSON-RPC server) | `acp-wire-v1@0` | the wire-stable protocol |
| 13 | `lib/yeah-emcp.el` (MCP-server, `emacs__*` tools) | `emcp-mcp-server@0` | emcp surface |
| 14 | `lib/yeah-gptel.el` (the transport bridge) | `gptel-as-transport@0` | §A6 enforcement |
| 15 | ACP fixture pair (positive + negative) | `acp-wire-v1@0` | obligation closure |
| 16 | emcp fixture pair (positive + negative) | `emcp-mcp-server@0` | obligation closure |

### Tier 3 — agent-loop kernel

| # | Task | Decision | Closes |
|---|---|---|---|
| 17 | `lib/yeah-loop.el` full FSM (18 transitions) | `tick-state-machine@0` | the agent loop |
| 18 | `lib/yeah-tools.el` (registry + first `read`) | (TBD) | first tool |
| 19 | `lib/yeah-perm.el` (rules + transient UI) | (TBD) | permission system |
| 20 | `lib/yeah-session.el` (append-only JSONL log) | `append-only-session-log@0` | durable persistence |
| 21 | `lib/yeah-shell.el` (REPL in `*yeah-shell*`) | (TBD) | user REPL |

### Tier 4 — code-mode + sub-agent + compaction

| # | Task | Decision | Closes |
|---|---|---|---|
| 22 | `lib/yeah-codes.el` (sandbox.el-PTC) | `sandbox-elisp-codes-mode@0` | code-mode |
| 23 | sub-agent (`task` tool) | (TBD) | A2-3 derivation |
| 24 | compaction (gptel-summarize tail) | (TBD) | §A5 enforcement |
| 25 | `lib/yeah-undo.el` (per-tick undo-boundary) | (TBD) | §A3 enforcement |

### Deferred (post v0.1.0)

- Elicitation (ACP v1 stable, MCP-spec field) — when ready.
- ACP v2 (currently draft at agentclientprotocol.com) — when stabilised.
- Desktop / native-client front-end — separate project.

## Author / license / active policy

- **Author**: Petr Kosov &lt;p.b.kosov@yandex.ru&gt;
- **License**: Apache-2.0
- **Active policy**: `bootstrap-yeah@0` (see `decisions/decision.yaml`)
