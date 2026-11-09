# Yeah — an Emacs Lisp agent harness

> **Status:** v0.1.0-alpha, governed by **math-coding v4**.
>
> The standing specification is `spec.json`: twenty-eight claims about this
> repository, each with a check and a control that has been shown to bite.
> The plan is `waves/*.json`: fourteen units of work, one per row of the
> parity matrix in `docs/ARCHITECTURE.md`, each with an intent, a check, a
> promise and the strongest objection against it.
>
> The aim is stated as parity: everything that works in the reference
> harnesses — pi and opencode — must work here too, at the same quality,
> from the point of view of the person using it. The matrix says which
> rows are still empty.
>
> Run `./scripts/dev map` for the current state. It is the main artefact.

**Yeah** is an Emacs-native agentic harness. The user has an Emacs
session; that session **is** the run-time of the agent. There is no
sidecar process and no client/server split:

- the kernel is **Elisp** (`lib/`, fourteen modules, one feature per file);
- the model is reached through **gptel**, and only through gptel;
- the tools are **Elisp functions**, registered in a registry and gated by
  a permission system;
- the session log is **append-only JSONL**; compaction is a projection over
  it, never a deletion;
- the wire is **ACP** on the upstream side (JSON-RPC 2.0 over stdio: Zed,
  JetBrains and any other ACP client can host Yeah) and **MCP** on the
  downstream side (`emacs__*` tools, so Emacs can be a tool for an
  external agent).

## What runs today

| Module | What it is | State |
|---|---|---|
| `yeah-state.el` | the twelve states of the agent loop | holds |
| `yeah-loop.el` | the eighteen transitions between them | holds |
| `yeah-session.el` | the append-only JSONL session log | holds |
| `yeah-compact.el` | compaction as a projection over the log | holds |
| `yeah-undo.el` | the undo boundary around a tick | holds |
| `yeah-tools.el` | the in-process tool registry | holds |
| `yeah-perm.el` | the permission rules, last match wins | holds |
| `yeah-acp.el` | the ACP agent side | holds |
| `yeah-emcp.el` | the `emacs__*` tool registry | holds |
| `yeah-gptel.el` | the gptel hook surface | holds |
| `yeah-subagent.el` | the sub-agent delegation API | holds |
| `yeah-shell.el` | the `*yeah-shell*` REPL | holds |
| `yeah-turn.el` | one turn of the model: the call, the tool calls, the dispatch | holds |
| `yeah-codes.el` | the PTC sandbox | **refuted** |

## What does not run yet, and is said so

One claim is **refuted** in the map, and the wave says what will turn it
green:

- `ptc-sandbox-restricts-model-code` — the PTC sandbox gates the *name* of
  a binding and then evaluates the body the model supplied. The check is
  `tests/checks/check-ptc-sandbox-restricts.el`; it fails today.

The loop itself is wired: `the-agent-loop-is-wired` holds, and the turn
that carries it — `lib/yeah-turn.el` — asks the model through gptel,
dispatches the tool calls it asked for through the permission system and
the registry, writes what happened into the append-only log, and asks the
model again until it asks for nothing. The canary is
`tests/checks/check-model-turn-runs.el`; it runs against a fake model and
touches no network.

Two more are **promises about code that does not exist yet** (wave-4): a
real call to the model through the gptel hooks, and the ACP agent speaking
JSON-RPC over stdio.

The map is red, and that is the point: the surface nobody has checked is
published, not hidden. `unknown` is not `pass` — an exit code of `3` means
the method could not tell.

## How to run it

```sh
./scripts/dev help                  # the subcommands
./scripts/dev byte-compile-all      # the kernel compiles clean, no warnings
./scripts/dev ert tests/unit/*.el   # the unit tests
./scripts/dev check tests/checks/*  # the canaries the claims are bound to
./scripts/dev map                   # claims, states, uncovered surface
./scripts/dev run                   # execute the checks, bind the evidence
./scripts/dev gate                  # run, then map; the exit code is the verdict
```

`scripts/dev` needs Emacs on `PATH` (or `EMACS` set) and the method
binary (or `MATHC` set). The method binary comes from the math-coding
repository — `nix build` there writes `result/bin/mathc`.

## How to read this repository as an agent

1. `AGENTS.md` — the entry point: the reading order, the commands, and
   the block that `mathc install` generates.
2. `docs/ARCHITECTURE.md` — the target shape: the aim stated as parity
   with the reference harnesses, the three planes, the three placements,
   and the matrix of what the reference harnesses have and Yeah does not.
3. `spec.json` — the standing specification.
4. `waves/*.json` — the plan: fourteen units of work, one per row of the
   parity matrix, each with an intent, a check, a promise and the
   strongest objection against it.
5. `ELISP_BEST_PRACTICES.md` — the conventions for kernel Elisp; §11 is
   the trap log.
6. `lib/yeah-*.el` — the kernel.

There is no decision corpus: a record of what changed lives in git, and a
rule lives in `spec.json` while its subject lives.

## Author

- **Petr Kosov** <p.b.kosov@yandex.ru>

## License

- **Apache-2.0** (see `LICENSE`, `NOTICE`)
