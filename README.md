# Yeah — Y(eah) Emacs Agent Harness

> **Status:** v0.1.0-alpha. All Tier 0–4 tasks from `ROADMAP.md`
> are landed as stubs; the wire layer (ACP, emcp) speaks the
> protocol but defers real network IO. The 9 active decisions
> under `decisions/` are the load-bearing artefacts.

**Yeah** is an Emacs-native agentic harness. The user has an Emacs
session; that session **is** the run-time of the agent. The harness:

- speaks **ACP** (Agent Client Protocol) on the upstream side
  (any ACP client — Zed, JetBrains IDE — can host Yeah);
- speaks **MCP** on the downstream side, including `emcp` —
  Emacs-flavoured tools (`emacs__eval`, `emacs__buffer_*`,
  `emacs__magit_*`, `emacs__dired_*`, `emacs__describe_*`);
- re-uses the entire GNU ELPA / MELPA surface (`gptel`,
  `mcp-server-lib`, `sandbox.el`, `deadgrep`, `jsonrpc.el`,
  `transient`, …);
- is governed by a decision-driven workflow, with every non-trivial
  change recorded as a `decisions/*.yaml` ADR.

## What works in v0.1.0-alpha

- 14 kernel Elisp modules, byte-compile clean under
  `emacs -Q --batch -L lib -f batch-byte-compile lib/*.el`
- 104 ERT cases, all passing
- `scripts/dev` wrapper: `smoke`, `validate`,
  `byte-compile-all`, `help`
- Two wire-stable schemas: `schemas/acp-v1.json` and
  `schemas/emcp-v1.json` (documentation; not enforced at
  runtime in this revision)
- The agent loop FSM: 12 states, 18 transitions, observed in
  `lib/yeah-state.el` and `lib/yeah-loop.el`

## What is a stub in v0.1.0-alpha

- ACP `session/prompt`: returns a fake `messageId`; the real
  LLM call lives in `lib/yeah-gptel.el`, which is a stub that
  does not yet call gptel.
- emcp tool handlers: return placeholder strings; the real
  tool implementations land in v0.2.
- Code-mode (`lib/yeah-codes.el`): whitelists names, validates
  inputs, and runs a JSON-clean eval; the real `sandbox.el`
  integration lands in v0.2 once we add an Emacs 29+ CI
  target.
- Sub-agent (`lib/yeah-subagent.el`): spawns a child session
  and returns a stub result; the async gptel integration
  lands in v0.2.
- Compaction (`lib/yeah-compact.el`): uses a deterministic
  placeholder summarizer; the real gptel summarization lands
  in v0.2.

## Author

- **Petr Kosov** &lt;p.b.kosov@yandex.ru&gt;

## License

- **Apache-2.0** (see `LICENSE`, `NOTICE`)

## How to read this repo as an agent

1. `AGENTS.md` — protocol, bootstrap checks, friction ladder,
   self-application rule.
2. `ROADMAP.md` — single source of truth for priorities.
3. `PACKAGES.md` — single source of truth for what exists.
4. `decisions/decision.yaml` — active policy.
5. The specific decision file for the area you're touching.
6. The corresponding obligation (if any) under `obligations/`.
7. The corresponding positive + negative fixture pair under
   `tests/fixtures/`.

If two documents contradict each other, the contradiction is a
deficit. Log it; do not silently resolve it.

## How to run the tests

```
emacs -Q --batch -L lib -f batch-byte-compile lib/*.el
emacs -Q --batch -L lib -l tests/unit/test-yeah-*.el \
      -f ert-run-tests-batch-and-exit
./scripts/dev validate
./scripts/dev byte-compile-all
bash tests/unit/test-scripts-dev.sh
```

All five commands should exit 0 on a healthy tree.
