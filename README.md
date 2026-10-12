# Yeah — Y(eah) Emacs Agent Harness

> **Status:** v0.0.0-alpha. Skeleton only; no kernel source yet.
> The 9 active decisions under `decisions/` are the load-bearing
> artefacts.

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
