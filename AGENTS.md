# AGENTS.md — the entry point to this repository

> **Yeah** is an Emacs Lisp agent harness. The user's Emacs session is
> itself the runtime of the agent: there is no sidecar process and no
> client/server split. The kernel is Elisp, the model is reached through
> `gptel`, and the tools are Elisp functions.
>
> This repository is governed by **math-coding v4**: the standing
> specification is `spec.json`, the plan is `waves/*.json`, and the
> evidence is what the checks produce. There is no decision corpus and no
> hand-written validator; see §The method below.

## Read first, in this order

1. `README.md` — what Yeah is, what runs and what does not.
2. `docs/ARCHITECTURE.md` — the target shape: the aim stated as parity
   with the reference harnesses, the three planes, the three placements,
   and the matrix of what is still missing.
3. `spec.json` — the standing specification: the goal, and every claim
   this repository makes about itself.
4. `waves/*.json` — the plan: each wave is a unit of work with an intent,
   a check, a promise and the strongest objection against it.
5. `ELISP_BEST_PRACTICES.md` — the conventions for writing kernel Elisp;
   §11 is the trap log.
6. `AGENTS.md` — this page.
7. `lib/yeah-*.el` — the kernel: one module per file, one feature per file.

If two of these contradict each other, the contradiction is a finding, not
a nuisance: say it in the wave that is open, or open a wave for it.

## The commands

```sh
./scripts/dev help                 # the list of subcommands
./scripts/dev byte-compile-all     # the kernel compiles clean, with no warnings
./scripts/dev ert tests/unit/*.el  # the unit tests
./scripts/dev check tests/checks/*  # the canaries: the checks the claims are bound to
./scripts/dev map                  # the standing specification: claims, states, uncovered
./scripts/dev run                  # execute the checks, bind the evidence, write the trail
./scripts/dev gate                 # run, then map; the exit code is the verdict
```

`scripts/dev` needs Emacs on `PATH` (or `EMACS` set) and the method
binary (or `MATHC` set). The method binary comes from the math-coding
repository: `nix build` there writes `result/bin/mathc`.

Exit codes are the method's scale: `0` pass, `1` fail, `2` blocked (input
error), `3` unknown (the method could not tell).

## The method

The map is the main artefact. Start with it:

```sh
./scripts/dev map
```

A claim is a statement about this repository with a scope, a requirement
that can close it, a falsifier, a register, and a **control**: the command
that breaks the subject and must make the check go red. A claim whose
control has never bitten is not established, and the map says so.

One claim is **refuted** today, and the map says so in red:

- `ptc-sandbox-restricts-model-code` — the PTC sandbox gates the *name* of
  a binding and then evaluates the body the model supplied. This is
  wave-07.

The loop is wired and the turn works: `the-agent-loop-is-wired` and
`the-model-turn-runs-and-parses-tool-calls` hold. The model is called in
one place only — `yeah-gptel-request` in `lib/yeah-gptel.el` — and the
canary for that reads the tree.

Twelve claims are **promises about code that does not exist yet**: the
parallel scheduler, the typed event log, the interface, the approvals with
reply kinds, the model-driven compaction, the session tree, the runtime
with its retries and timeouts, the MCP server on stdio, the three
placements, the sub-agents, the product layer, and the ACP agent speaking
JSON-RPC over stdio.

Two rules that are not negotiable here:

- **A check that cannot fail is a comment.** Every claim carries a control
  that has been shown to bite.
- **Unknown is not pass.** An exit code of `3` means the method could not
  tell, and it is never read as success.

<!-- math-coding:begin -->
## math-coding in this project

This block is written by `mathc install` and by nothing else.
Everything outside it belongs to the project and is never touched.
Re-run `mathc install` after the specification changes;
`mathc doctor` says whether this block is current.

### The aim

Yeah is an Emacs Lisp agent harness: the user's Emacs session is itself the runtime of the agent; every call to the model goes through gptel, every tool goes through the registry and the permission system, and the session log stays append-only

Stated by p.b.kosov@yandex.ru, over lib/, tests/, scripts/, schemas/, docs/, AGENTS.md, README.md, ELISP_BEST_PRACTICES.md.

### The next step

```sh
mathc --root . next
```

### What is declared

28 claim(s): 15 holds, 12 not established.

The full list, and what is not covered: `mathc --root . map`.

### If you are an agent here

```sh
mathc map      # what is claimed, what is known, what is not covered
mathc run      # run the checks, bind every proof to the content it ran against
mathc route    # what needs a person, and why
mathc next     # the next work, one item
mathc add ID "SUBJECT" SCOPE "WHAT WOULD REFUTE IT" fact \
   --requirement verifier:CMD --control CMD
```

The control is the command that breaks the subject and must fail with it:
a check that cannot fail proves nothing.

For an agent the machine surface is cheaper: `mathc --root . mcp` speaks
JSON-RPC and returns the next step with every method.

Every verb: mathc - · mathc init · mathc goal · mathc add · mathc accept · mathc control · mathc budget · mathc map · mathc route · mathc run · mathc record · mathc next · mathc wave · mathc close · mathc draft · mathc install · mathc mcp · mathc propose · mathc doctor.
<!-- math-coding:end -->

## The Elisp side

- `lib/` is Elisp only. No C, no Rust, no shell scripts inside the kernel.
- One feature per file; `(require 'yeah-x)` loads `lib/yeah-x.el`.
- Public symbols are prefixed `yeah-`; internal helpers use `yeah--`.
- Domain errors are `user-error`, never `error`.
- `defvar` variables are rebound with `setq`, not with `let`.
- Subprocesses are started with `make-process`, never with `shell-command`.

The full list, with the reasons, is in `ELISP_BEST_PRACTICES.md`.
