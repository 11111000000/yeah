# Yeah v0.0.0-alpha — AGENTS protocol

> **Work in progress.** Yeah follows the math-coding-style
> decision-driven workflow: every non-trivial change is recorded as a
> `decisions/*.yaml` ADR. This `AGENTS.md` is short on purpose; the
> load-bearing artefact is the decision set in `decisions/`.

This repository implements Yeah v0.0.0-alpha. Until the `yeah gate`
and `yeah self-check` subcommands are wired (Tier 1 of `ROADMAP.md`),
every change is subject to the **eight manual bootstrap checks**
below, in lieu of automated guarantees.

- **Author**: Petr Kosov &lt;p.b.kosov@yandex.ru&gt;
- **License**: Apache-2.0 (see `LICENSE`, `NOTICE`)
- **Active policy**: `bootstrap-yeah@0` (see `decisions/decision.yaml`)

## Read first

Before changing anything in this repository, read in order:

1. `ROADMAP.md` — single source of truth for priorities. Read this
   first; it supersedes any inline priority lists.
2. `PACKAGES.md` — single source of truth for "what exists": every
   decision, fixture, kernel module, schema, axiom. Use this file to
   find which decision file to read.
3. `README.md` — short pitch and pointers.
4. `decisions/decision.yaml` — the active policy.
5. The decision file that names the area you're touching
   (e.g. `decisions/acp-wire-v1.yaml` for ACP work).
6. The corresponding obligation under `obligations/`, if any.
7. The corresponding positive + negative fixture pair under
   `tests/fixtures/`, if any.

If any of these contradict each other, the contradiction is a
deficit. Log it as `obligations/DEFICIT-<sha>.yaml` with a remedy;
do not silently resolve it.

## Bootstrap gate (eight manual checks)

Until `yeah self-check` is wired (Tier 1), every change must satisfy:

1. **Read-first order** — items 1–7 above were read in order.
2. **Decision exists** — every change creates or updates a
   decision file if it introduces a new commitment, tradeoff,
   public contract, or architectural choice.
3. **Fixture pair** — every obligation closes with a positive
   fixture AND a negative fixture.
4. **Axiom reference** — every non-trivial change cites an axiom
   by id in the decision's `axiom_link`. (Axiom index lives in
   `decisions/`; for now the `axiom_link` values are
   `A0…A4` to keep alignment with the future validator.)
5. **Counterexample** — every non-trivial change records a
   `counterexample:` field.
6. **Honest time report** — duration claims use one of three
   observable scales (wall-clock / token-budget / step-count)
   with a reference class.
7. **Source distinction** — every "evidence" claim distinguishes
   declared / derived / attested / reviewed / observed.
8. **No silent resolve** — every contradiction between documents
   is logged as a deficit.

## Before work

State this compact contract before editing:

```yaml
intent: What should become true?
change_kind: implementation | decision | policy | constitution
affected_capabilities: []
must_preserve: []
counterexample: What plausible case would make this change wrong?
unknowns: []
planned_evidence: []
```

For a provably editorial change:

```yaml
change_kind: editorial
reason: Why behavior and policy are unchanged.
```

## Friction

Apply the least sufficient response:

- `silent` — deterministic evidence shows no semantic or protected
  change.
- `record` — the change is meaningful but covered by existing
  decisions and evidence.
- `ask` — an answer would change behavior, risk, obligations, or
  recovery.
- `block` — an explicit policy requirement has an unresolved
  deficit.

Never block without naming the rule, affected subject, reason, and
at least one remedy. Unknown is not Pass. A waiver is not Pass.

## Edit-loop prevention

If 3 consecutive verification attempts (`emacs -Q --batch -l
scripts/dev byte-compile-all`, an ERT run, etc.) fail with the same
error class, STOP. Write `tests/unit/probe_X.el`, run it directly,
identify whether the issue is a SYNTAX fix (1–3 lines) or a
STRUCTURE fix (refactor). The trap log at
`ELISP_BEST_PRACTICES.md §11` is the first place to look when
debugging.

## Honest time reporting

Three allowed scales, **never** combined:

```text
wall-clock-minutes   real seconds/minutes from session start to now
token-budget         prompt + completion tokens consumed
step-count           tool calls / reasoning rounds performed
```

No fourth scale is acceptable without an axiomatic justification.

## Self-application

Changes to this protocol, the active policy, the kernel, or the
wire contract always require:

1. a decision under the currently active rules;
2. a strongest practical countercase;
3. positive and negative conformance fixtures;
4. a migration and recovery path;
5. authorization by the previous active policy;
6. an explicit list of changed verdicts.

Candidate rules cannot authorize their own adoption.
