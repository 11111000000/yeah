# The live evidence register

The checks in `tests/live/` are **evidence without a claim**. They need a real
model and sometimes the network, so no negative control can bite without a
provider: the math-coding map cannot carry them, and the green verdict of the
declared claims says nothing about them. They are kept here, honestly
labelled, instead of being quietly counted as proof.

A live check that cannot run because the environment lacks a key **skips**; a
skip is not a pass, and a skip never turns into a claim.

## The register

| Check | What it proves | Needs | How to run | Last recorded run |
|---|---|---|---|---|
| `tests/live/live-model-call.el` | a real model answers through `yeah-gptel-request` — the one place where Yeah calls the model | provider key | `emacs -Q --batch -L lib -l tests/live/live-model-call.el` | 2026-11-15, with MiniMax-M2.7: three calls in a row answered `OK', `OK' and an **empty** message — the silence of the provider is intermittent, and it is the provider that is silent, not the harness |
| `tests/live/live-coding-task.el` | the harness fixes a small broken project with its own tools (read, edit, run), and the project's test passes afterwards | provider key | `emacs -Q --batch -L lib -l tests/live/live-coding-task.el` | 2026-11-15, with MiniMax-M2.7 — pass: the model repairs the project with the tools of Yeah and the test passes afterwards |
| `tests/live/live-interactive-path.el` | the interactive product path against a live provider: open a session, ask, cancel, quit, restart, recover the pending input | provider key | `emacs -Q --batch -L lib -l tests/live/live-interactive-path.el` | 2026-11-15, with MiniMax-M2.7 — pass; it failed on the same day before the turn noticed the empty answer of the model (wave 24) |
| `tests/live/live-service-path.el` | the primary deployment against a live provider: a clean service Emacs, a file asked over ACP, the write approved through `session/request_permission`, the file appears | provider key, network | `emacs -Q --batch -L lib -l tests/live/live-service-path.el` | 2026-11-15, with MiniMax-M2.7 — pass (one earlier attempt failed at the provider — an intermittent refusal, not a harness defect) |
| `tests/live/live-fixed-point.el` | the fixed point: a child of Yeah repairs a Yeah canary and the canary passes afterwards | provider key | `emacs -Q --batch -L lib -l tests/live/live-fixed-point.el` | 2026-11-15, with MiniMax-M2.7 — pass, one child; it failed on the same day before the turn noticed the empty answer of the model (wave 24) |
| `tests/live/live-clean-install.el` | the published repository installs into a clean Emacs: the documented bootstrap runs in a throwaway HOME, the installed package loads, and `yeah`, `yeah-ask` and `yeah-doctor` are bound | network | `emacs -Q --batch -L lib -l tests/live/live-clean-install.el` | 2026-11-15, against the published repository — pass: "the clean installation works" (this is what closed the public alpha gate) |
| `tests/pixel/check-interface-is-seen.sh` | the interface is really on the screen: Emacs itself draws the journal and the approval view under a frame server, the screen is photographed, and the pictures are compared with each other and with the same buffer without the interface | a frame server (Xvfb), a terminal emulator, ImageMagick, Emacs — **no provider key** | `YEAH_XVFB=… YEAH_XTERM=… YEAH_MAGICK=… ./scripts/dev pixel` | 2026-11-15, pass — "the interface is on the screen: 767 colours, 16953 pixels between the journal and the approval view" |
| `bench/run-bench.el` | the parity with another harness is measured rather than claimed: the same task, the same workspace and the same model are given to Yeah and to the second harness, and the outcome of both is recorded | provider key, a second harness | `YEAH_BENCH_TASKS=… ./scripts/dev bench --run` | 2026-11-15, with MiniMax-M2.7 and pi: pi passed 3 of 3 tasks, Yeah passed 1 of 3 — **not a verdict about parity** (see "The pilot of the parity") |

## The environment

The credentials never live in this repository. Every check that needs the
model reads them from the environment and skips without them; the
clean-install check needs the network instead of a key:

| Variable | Meaning |
|---|---|
| `YEAH_TEST_KEY` | the provider key |
| `YEAH_TEST_HOST` | the provider host, for example `api.minimax.io` |
| `YEAH_TEST_MODEL` | the model, for example `MiniMax-M3.1-Flash` |
| `EMACS` | the Emacs binary (optional; the checks find one themselves) |

## How this register is kept true

- A row is updated when a check is actually run, with the date, the model and
  the outcome — including a skip or a failure.
- A row is never updated from a plan, a hope or a report of somebody else's
  session.
- When the code changes in a way that can break a check, the row says
  "re-check needed" until the check has been run again.
- The claims in `spec.json` cover the offline surface. These rows cover the
  world. Neither replaces the other, and the map's verdict must never be
  quoted as if it covered these rows.

## The picture of the interface

`tests/pixel/check-interface-is-seen.sh` is the only check in this register
that needs no provider at all: it needs a frame server, a terminal emulator
and ImageMagick.  Emacs itself draws the journal and the approval view in a
terminal under Xvfb, the screen is photographed with ImageMagick, and three
pictures are compared with each other:

| Comparison | What it rules out |
|---|---|
| the number of colours of the journal picture | a blank screen |
| the journal picture against the same buffer without the interface | a renderer that draws a heading and nothing else |
| the journal picture against the approval picture | an approval view that looks like the journal |

Nothing is compared with a stored picture: a stored picture fails on every
machine whose fonts differ, and a check that fails for that reason teaches
nobody anything.  The pictures land in `tests/artifacts/` and are not kept in
git.

The check lives outside the map for the same reason the live checks do: it
needs a frame server, which the environment of the method does not have, so a
run without one is **blocked**, not pass.  It is a check that can fail: with
the renderer broken (`yeah-journal--apply-view` replaced by `nil`) it fails
with "the interface does not change the screen".

## The pilot of the parity

On 2026-11-15 three tasks of the set — `read-answer`, `fix-failing-test` and
`write-new-file` — were given to Yeah and to `pi` under the same conditions:
the same provider, the same model (`MiniMax-M2.7`), the same task workspaces
and the same prompts.  The result is in `bench/results/20261115T135915Z.jsonl`
and the journals of the runs are in `bench/results/20261115T135915Z/sessions/`.

| Task | Yeah | pi |
|---|---|---|
| `read-answer` | failed — `answer.txt` does not exist | passed |
| `fix-failing-test` | failed — the test still fails | passed |
| `write-new-file` | failed — the file was not written | passed |

**This is not a verdict about parity.**  Three reasons, all of them
load-bearing:

1. The threshold is a decision of the owner that has not been taken
   (`docs/PLAN.md` §13).  A parity without a threshold is not an assertion.
2. Three tasks are a sample, not a benchmark.
3. The difference the pilot found is a **defect of one turn**, not a
   difference of quality between the agents.

The third reason is the one that matters for the next wave.  In all three
runs of Yeah the model did call tools, the results of those tools arrived,
and then the provider answered with an **empty** message; the turn took that
empty answer as the end of the work and stopped without the effect, and
nothing in the journal said that the work was not done.  The live path of the
kernel with the same key and the same model passes
(`tests/live/live-coding-task.el` — the model repairs the project with the
tools of Yeah and the test passes afterwards), so the tools and the model
work; what does not work is the turn that has to notice that the model has
not advanced.

Two defects of the apparatus were found and fixed before the measurement
was made; both of them would have distorted the numbers:

- the whole registry of the tools was announced to the model while only ten
  of them were permitted, so the model spent turns on calls the permission
  layer refuses.  The harness is now offered exactly the tools it may use,
  and `finish` is among them: the system prompt asks the model to end the run
  with it, and a tool the prompt names while the permission refuses it is a
  contradiction the model pays for in turns;
- the external harness was given a standard input that never ends, so it
  waited for the end of the pipe and was counted as a failure it never had a
  chance to avoid (27 s instead of 2.6 s with the end of the input at once).

With `MiniMax-M3` and `MiniMax-M3.1-Flash` the same provider returns an empty
answer through `gptel` even for the plain model call, so the model of the
pilot is the one that both harnesses can be compared with.

The defect has been fixed (2026-11-15, wave 24, the claim
`an-empty-answer-does-not-end-the-run`): an answer that says nothing is
nudged into the action while the budget of the nudges lasts, the run says
it did not finish when the budget is spent, and a run without supervision
fails instead of ending as a finished job.  The claim has a control that
bites: with the silent-answer branch disabled, the two tests of the claim
fail on real assertions.

## The pilot after the fix (2026-11-15)

The pilot was run again on the fixed turn under the same conditions
(`bench/results/20261115T142743Z.jsonl`):

| Task | Yeah | pi |
|---|---|---|
| `read-answer` | failed — the answer was computed, the file was not written | passed |
| `fix-failing-test` | failed — the test still fails | passed |
| `write-new-file` | **passed** — the turn ended in completed | passed |

The fix moved one task of three: the harness now keeps the work alive when
the provider goes silent, and it says what it did not finish.  The number is
still not a verdict about parity — the threshold is not decided, the sample
is three tasks, and the difference that remains is still not a difference of
quality.

What the journals show now (`bench/results/20261115T142743Z/sessions/`): the
provider answers with an empty message after **every** batch of tool
results, not only at the end of the run.  Each silence costs one nudge of
the budget of three, and the model tends to answer the nudge by exploring
again rather than by finishing the work: in `read-answer` it computed the
right total with `bash` and never wrote the file, and in `fix-failing-test`
it read the two files of the project three times.  The open work is
therefore not the turn any more but the **nudge**: it has to carry the state
of the work, so that the model continues instead of starting over.

The nudge does that now (wave 25, the claim
`a-silence-nudge-carries-the-state-of-the-work`): the nudge that follows a
silence carries the tools the run already called and the results they
returned, and it does not name an unused tool as the next call.  A nudge
that says "call `read' now" after the model has already read the file is
what sent the pilot round in circles.  The claim has a control that bites:
with the state removed from the nudge, the test of the claim fails and the
other tests keep passing.

The silence is the provider, not the harness: three plain model calls in a
row answered `OK', `OK' and an **empty** message with HTTP 200
(`tests/live/live-model-call.el`).  A provider that answers half of the
time with nothing is a fact the turn has to live with, and the old turn did
not live with it: it took the silence for the work.

The parity of `docs/PLAN.md` §16.7 still cannot be measured honestly: the
threshold is a decision of the owner, the sample is three tasks, and the
difference the first pilot found was a defect of the turn rather than a
difference of quality.

## What is still open

- A real editor (an agent-shell, or a person's Emacs) against a live
  provider: not yet checked.
- The bridge to the buffers of an attached Emacs against a person's Emacs in
  day-to-day use: the live daemon is checked, the daily use is not.
- The picture of the interface is compared with itself and with the same
  buffer without the interface, not with a stored golden picture.
- The parity with other harnesses is measured on three tasks only, and the
  difference it found is a defect of one turn, not a difference of quality.
  The threshold is not decided (`docs/PLAN.md` §13), the sample is small, and
  the defect itself has no claim with a biting control yet.
