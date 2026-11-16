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
| `tests/live/live-model-call.el` | a real model answers through `yeah-gptel-request` — the one place where Yeah calls the model | provider key | `emacs -Q --batch -L lib -l tests/live/live-model-call.el` | 2026-11-16 16:05 UTC, on the code of wave 39 — pass on all four models: M2.5 and M2.7 answer with a tool call, M3 and M3.1-Flash answer with the text (`shape=text answer="OK"`); the status is `HTTP/2 200` every time.  The run before the repair of the stand (13:10 UTC, wave 38) failed on the stand and not on the provider (§ "The live checks of the ACP route") ||
| `tests/live/live-coding-task.el` | the harness fixes a small broken project with its own tools (read, edit, run), and the project's test passes afterwards | provider key | `emacs -Q --batch -L lib -l tests/live/live-coding-task.el` | 2026-11-16 13:10 UTC, on the code of wave 38, with MiniMax-M2.7 — pass on the first attempt: the model repaired the project with the edit of Yeah and the test of the project passes afterwards ||
| `tests/live/live-interactive-path.el` | the interactive product path against a live provider: open a session, ask, cancel, quit, restart, recover the pending input | provider key | `emacs -Q --batch -L lib -l tests/live/live-interactive-path.el` | 2026-11-16 13:10 UTC, on the code of wave 38, with MiniMax-M2.7 — pass on the first attempt ("the interactive path works") ||
| `tests/live/live-service-path.el` | the primary deployment against a live provider: a clean service Emacs, a file asked over ACP, the write approved through `session/request_permission`, the file appears | provider key, network | `emacs -Q --batch -L lib -l tests/live/live-service-path.el` | 2026-11-16 16:08 UTC, on the code of wave 39 — pass on the first attempt ("the primary path works with a live model"): the harness nudges the model that only announced the file, the write is approved over the wire, and the file holds `42`.  The run of 14:34 UTC (wave 38) failed with `end_turn` and nothing done: the budget of the supervision of the kernel was zero, and the run of a model that only announced its next step was marked finished (§ "The live checks of the ACP route") ||
| `tests/live/live-fixed-point.el` | the fixed point: a child of Yeah repairs a Yeah canary and the canary passes afterwards | provider key | `emacs -Q --batch -L lib -l tests/live/live-fixed-point.el` | 2026-11-16 13:10 UTC, on the code of wave 38, with MiniMax-M2.7 — pass on the first attempt ("the child repaired the canary") ||
| `tests/live/live-clean-install.el` | the published repository installs into a clean Emacs: the documented bootstrap runs in a throwaway HOME, the installed package loads, and `yeah`, `yeah-ask` and `yeah-doctor` are bound | network | `emacs -Q --batch -L lib -l tests/live/live-clean-install.el` | 2026-11-16 13:11 UTC, against the published repository (revision `0c07695`), on the code of wave 38 — pass: "the clean installation works" ||
| `tests/pixel/check-interface-is-seen.sh` | the interface is really on the screen: Emacs itself draws the journal and the approval view under a frame server, the screen is photographed, and the pictures are compared with each other and with the same buffer without the interface | a frame server (Xvfb), a terminal emulator, ImageMagick, Emacs — **no provider key** | `YEAH_XVFB=… YEAH_XTERM=… YEAH_MAGICK=… ./scripts/dev pixel` | 2026-11-15, pass — "the interface is on the screen: 767 colours, 16953 pixels between the journal and the approval view" |
| `bench/run-bench.el` | the parity with another harness is measured rather than claimed: the same task, the same workspace and the same model are given to Yeah and to the second harness, and the outcome of both is recorded | provider key, a second harness | `YEAH_BENCH_TASKS=… ./scripts/dev bench --run` | 2026-11-16 13:12 UTC, on the code of wave 38, with MiniMax-M2.7 and pi: Yeah passed 1 of 3 tasks and 2 failed, pi passed 3 of 3 — **not a verdict about parity** (the threshold is a decision of the owner, the sample is three tasks); the row of each failed task names the shape of the run ("the model answered with an empty message 3 times and the run ended without an effect"), which is what wave 38 added (see "The live checks and the pilot after wave 38") ||

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

## The pilot after the nudge carries the state (2026-11-15)

The third run of the pilot, on the code of wave 25, under the same
conditions (`bench/results/20261115T144021Z.jsonl`):

| Task | Yeah | pi |
|---|---|---|
| `read-answer` | **passed** — the turn ended in completed | passed |
| `fix-failing-test` | failed — the edit was refused | passed |
| `write-new-file` | **passed** — the turn ended in completed | passed |

Two tasks of three now pass: the silence of the provider no longer ends the
work, and the nudge that follows it carries the state, so the model
continues instead of starting over.  The third task fails for a different
reason, and the journal says which: the model read the file of the project,
edited it with the tick it believed it had read, and the edit was refused —
"edit: stale tick for calc.el: expected 0, current 9; read fresh state
before retrying".

That refusal is the next defect, and it is in the tools, not in the turn.
The `read` tool reports the tick of the buffer that visits the file, and
there is no such buffer until an `edit` opens it: the read of a file
nobody has edited yet returns no tick at all, and the tick of a buffer that
opens later is an arbitrary number of the global counter of Emacs (9 in this
run).  A model that has no tick and passes a plausible one — 0 — is refused
for a file that has not changed at all.  The tick is meant to catch a file
that changed under the model; as it stands it also catches a model that
guessed.

The silence is the provider, not the harness: three plain model calls in a
row answered `OK', `OK' and an **empty** message with HTTP 200
(`tests/live/live-model-call.el`).  A provider that answers half of the
time with nothing is a fact the turn has to live with, and the old turn did
not live with it: it took the silence for the work.

The parity of `docs/PLAN.md` §16.7 still cannot be measured honestly: the
threshold is a decision of the owner, the sample is three tasks, and the
difference the first pilot found was a defect of the turn rather than a
difference of quality.

## The pilot after the tick (2026-11-15, 15:02)

The fourth run of the pilot, on the code of wave 26, under the same
conditions (`bench/results/20261115T150251Z.jsonl`):

| Task | Yeah | pi |
|---|---|---|
| `read-answer` | blocked — the provider failed (HTTP 529) | passed |
| `fix-failing-test` | **passed** — the check of the task exits 0 | passed |
| `write-new-file` | blocked — the provider failed (HTTP 529) | passed |

The task that the tick refused now passes.  The journal says what happened
(`bench/results/20261115T150251Z/sessions/bench-fix-failing-test.jsonl`): the
model read `calc.el` and `calc-test.el`, asked for the edit with the tick it
believed it had read, and the edit went through — "Replaced 1 occurrence;
tick 23; saved."  On the code of wave 25 the same edit was refused with
"stale tick for calc.el: expected 0, current 9".  The tick is meant to catch
a file that changed under the model; it now catches that and nothing else
(wave 26, the claim
`a-guessed-tick-does-not-refuse-an-unchanged-file`).

Two tasks were not measured at all: the provider was overloaded again, and
the two journals hold nothing but the error of the provider.  The runner
says so — **blocked**, neither a pass nor a failure (wave 27).  pi passed
all three tasks of the run.

The parity is therefore **not measured** on this run: one task of three says
that Yeah does what pi does on it, and the two blocked tasks say nothing
about either harness.  What the run does say is that the third task of the
pilot — the one the tick refused — is no longer refused.

One detail of the same journal: after the edit the provider failed, and the
run ended in "failed" although the work was done and the check of the task
passed.  The run tells the person that it failed when the file was in fact
fixed.  The check of the benchmark is the arbiter there, so the measurement
is right; the outcome of a run that says "failed" after the work is done is
an open question of the product.

## The pilot after the turn learned to wait (2026-11-15, 15:39)

The fifth run of the pilot, on the code of wave 28 (`6c139e5`), under the same
conditions (`bench/results/20261115T153957Z.jsonl`):

| Task | Yeah | pi |
|---|---|---|
| `read-answer` | **passed** — the check exits 0, the turn ends in completed | passed |
| `fix-failing-test` | blocked — the transport to the provider died (curl, exit code 28) | passed |
| `write-new-file` | **passed** — the check exits 0, the turn ends in completed | passed |

Two tasks of three are measured for Yeah now, and both pass; the third is
not measured at all: the journal of the run holds one line — "Curl failed
with exit code 28" — and the runner records the run as **blocked**, neither
a pass nor a failure of the agent (wave 27).

The parity is therefore **not measured** on this run either: two tasks say
that Yeah does what pi does on them, and the third says nothing about either
harness.  What the run does say is that the provider answered at all — it was
overloaded for hours before — and that the two tasks of the run that the
provider answered, Yeah passed.

## The live checks after the turn learned to wait (2026-11-15, 15:37)

The live checks on the code of wave 28 (`6c139e5`), with a live provider:

| Check | Exit | What it says |
|---|---|---|
| `live-model-call` | 0 | the provider answers |
| `live-coding-task` | 1 | the model answered with an empty message and the run ended without an effect |
| `live-interactive-path` | 0 | the interactive path works with a live model |
| `live-service-path` | 0 | the service path works with a live model |
| `live-fixed-point` | 0 | a child repaired a canary and the canary passes afterwards |
| `live-clean-install` | 0 | the package installs into a clean Emacs |

The defect of wave 28 is gone: **no journal of this run holds a transition
error**.  The run of 15:11 died with "no transition from awaiting-tool on
stream-end" and "no transition from failed on tool-call"; the run of 15:38
holds none, and the interactive path, the service path and the fixed point
all pass with a live model.

The coding task still fails, and it fails for another reason.  The journal
holds no error: the model answered with an empty message three times — it
put its plan into the reasoning and emitted neither a text nor a tool call —
and the run ended with the record `unfinished: the model answered with an
empty message 3 times and the run ended without an effect`.  The file was
not repaired, and the check of the task did not pass.  A run that says it
ended without an effect is honest; what the provider does with the tools of
a turn is not in the hands of the harness.

## A run of an overloaded provider (2026-11-15, 14:55)

The run of 14:55 (`bench/results/20261115T145542Z.jsonl`) is **not** a
measurement of the harnesses.  The provider answered HTTP 529 — "the cluster
is overloaded" — to both harnesses, and the runner counted the runs as
failures of the agents: Yeah passed no task of three and pi passed one of
three.  Those numbers measure the provider of that minute, not the two
harnesses, and a pilot that reports a number computed over an outage is a
measurement of the day, not of the parity.

The journals show the outage without an interpretation (`bench/results/20261115T145542Z/sessions/`):
the first turn of `fix-failing-test` ends with the error
`(:type "overloaded_error" :message "The server cluster is currently under high load..." :http_code "529")`,
and the run of `write-new-file` dies on the same error.  The check of
`write-new-file` exits 255 because the file the task asks for was never
written and the check of the task loads it — the crash belongs to the check
of an empty workspace, not to the harness.

The runner says so itself now (wave 27, the claim
`a-provider-failure-is-not-a-failure-of-the-agent`): the failure of the
provider is read from the journal of the run — for Yeah — and from the
output of the run — for an external harness — and such a run is recorded as
**blocked**: neither a pass nor a failure of the agent.  A blocked
measurement is unknown, and unknown is not a pass.  The claim has a control
that bites and that changes the subject and not the check: with the
classification of a blocked run turned into a failure, the self-check of the
task set fails with a real assertion.

## The pilot that found the gap in the apparatus (2026-11-15, 15:04)

The run of 15:04 (`bench/results/20261115T150457Z.jsonl`) measured the
apparatus and not the harnesses:

| Task | Yeah | pi |
|---|---|---|
| `read-answer` | blocked — the provider failed (HTTP 529) | passed |
| `fix-failing-test` | failed — the transport to the provider died | passed |
| `write-new-file` | blocked — the provider failed (HTTP 529) | passed |

The journal of `fix-failing-test` holds one line: "Curl failed with exit
code 28. See Curl manpage for details."  The run was not measured — the
transport to the provider died — but the first version of the markers of
wave 27 knew only the overload of the provider, so the runner recorded the
run as a failure of the agent.  The markers name the transport as well now,
and the self-check of the task set proves both cases: the overload of the
provider and the failure of the transport.  A run of 15:04 measured with the
runner of today would be recorded as blocked.

## The pilot that measured the copy of the version token (2026-11-15, 17:06)

The sixth run of the pilot (`bench/results/20261115T170600Z.jsonl`), on the
code of waves 30+31 (`a1ff7c1`), with MiniMax-M2.7 and pi as the second
harness:

| Task | Yeah | pi |
|---|---|---|
| `read-answer` | failed — the file was never written | passed |
| `fix-failing-test` | failed — the test of the task still fails | failed — the test of the task still fails |
| `write-new-file` | passed | passed |

Yeah passed 1 of 3, pi passed 2 of 3.  **The parity is not measured**: the
threshold is a decision of the owner (`docs/PLAN.md` §13), the sample is three
tasks, and both harnesses failed a task for a reason that has nothing to do
with either of them (see below).

All three runs of Yeah ended with the record "unfinished": the provider
answered with an empty message after every batch of tool results, and the
nudge that carries the state of the work did not bring an answer either.  The
work of the two failed tasks was not done.

One of the tasks failed on a defect that is worth naming exactly, because it
is the reason the file was not repaired:

- the model read `calc.el` and received the version token of the file, the
  digest of its bytes: 64 characters of hex;
- it presented a token of **58** characters — the same digest with six
  characters lost in the middle (`…777dfddb` `00efcb8` `6c41135c…` became
  `…777dfddb` `06c41135c…`);
- the edit compared the presented token with the version of the file, did not
  find them equal, and refused the edit — correctly: the guard of wave 29 did
  its work;
- but the refusal said "the file changed since the read", and the file had
  **not** changed: the sha256 of the file on disk was and remained
  `fe26cedb46546a55777dfddb00efcb86c41135cb25811737952f8388e5b0e165`, the
  very digest the read had handed out.

So the guard is not the defect, and neither is the file.  The defect is that
the token is 64 characters of hex — too many for a model to copy back
unchanged — and that the refusal blames the file, which sends the model
looking for a change that is not there.  Wave 32 shortens the token and makes
the refusal name the token instead of the file.

The task `fix-failing-test` also needs `emacs` on PATH, and the environment
of the bench has none ("emacs: command not found").  Both harnesses failed
that task, so the comparison is fair, but the task measures the environment
as much as the agent.

## The pilot after the token became short (2026-11-15, 17:23)

The seventh run of the pilot (`bench/results/20261115T172343Z.jsonl`), on the
code of wave 32, with MiniMax-M2.7 and pi as the second harness.  This time
`emacs` was on PATH: the check of the task `fix-failing-test` judges the work
with a real ERT run, and without an Emacs both harnesses failed that task for
a reason that had nothing to do with either of them.

| Task | Yeah | pi |
|---|---|---|
| `read-answer` | passed | passed |
| `fix-failing-test` | failed — the test of the task still fails | passed |
| `write-new-file` | passed | passed |

Yeah passed 2 of 3, pi passed 3 of 3 — the run before measured 1 of 3 and 2
of 3.  **The parity is still not measured**: the threshold is a decision of
the owner (`docs/PLAN.md` §13) and the sample is three tasks.

The token is short in the live path: the read of `calc.el` handed out
`[version: fe26cedb4654]`, twelve characters, and the model used the tools
with it.  The task that Yeah failed failed on the provider and not on the
token: the model wrote "The bug is integer division. Fixing it to use
floating-point division:" and called no tool, the turn ended there, and the
file was never changed.  The harness cannot tell that a message which
announces an action is not an answer; the nudge of wave 25 carries the state
of the work, but it fires when the model is silent and not when the model
talks without acting.

The live checks of 17:21–17:23 on the same code pass: the model repaired the
project of `live-coding-task` with the edit of Yeah (the edit landed with the
short token) and the test of the project passes afterwards, the interactive
path held, the service path works with a live model, the child repaired the
canary, and the clean installation works.  The provider went silent in the
middle of the batch: the run of `live-model-call` passed on one of three
attempts, and the attempt of `live-service-path` of 17:21 failed with the
empty answer of the provider and passed on the retry.

The verdict of the method on this code is `green`, with 84 claims `holds
(current)` — the two new ones among them:
`a-version-token-is-short-enough-to-copy` and
`an-edit-refuses-a-wrong-token-with-the-current-one`.

## The live checks and the pilot after wave 33 (2026-11-16, 06:29–06:50)

Wave 33 made the refusal of the unsaved changes the answer of every edit and
gave the write of a whole file the version token of the read.  The verdict of
the method on that code is `green`, with 86 claims `holds (current)` — the two
new ones among them: `an-edit-never-lands-on-a-file-with-unsaved-changes` and
`a-write-never-lands-on-a-file-that-changed`, and the method proved the
negative control of each of them itself.

The live checks of 06:35–06:43 pass, all six of them:

| Check | Outcome |
|---|---|
| `live-model-call` | pass on the first attempt (`status="HTTP/2 200" answer="OK"`) |
| `live-coding-task` | pass on the third attempt; the two attempts before it failed on the provider (HTTP 529, `overloaded_error`) |
| `live-interactive-path` | pass ("the interactive path works") |
| `live-service-path` | pass ("the primary path works with a live model") |
| `live-fixed-point` | pass, one child ("the child repaired the canary") |
| `live-clean-install` | pass ("the clean installation works") |

The first attempt of `live-coding-task` is worth naming: the edit of Yeah
landed and the file was already correct, and the run still ended `failed`,
because the provider answered the next turn with HTTP 529.  The check of the
task looks at the state of the run as well as at the file, so it failed.  The
third attempt passed.  The failure is the failure of the provider and not a
defect of the harness, and the two are told apart here.

The pilot ran twice on this code, because the first run had a task that the
provider stopped.  The two runs together measured the same result: **Yeah
passed 2 of 3 tasks, pi passed 3 of 3.**

| Task | Run of 06:43 (Yeah) | Run of 06:48 (Yeah) | pi (both runs) |
|---|---|---|---|
| `read-answer` | blocked — the provider failed (`overloaded_error`) | passed | passed |
| `fix-failing-test` | passed | failed — the test of the task still fails | passed |
| `write-new-file` | passed | passed | passed |

A blocked task is neither a pass nor a failure of the agent, so the first run
measured two tasks and not three.  **The parity is still not measured**: the
threshold is a decision of the owner (`docs/PLAN.md` §13) and the sample is
three tasks.

The task that Yeah failed in the second run failed on the model and not on the
harness.  The session shows four turns: the model read `calc.el` and the test
of the task, ran the test, read the files again and ran the test again — and
never called the edit.  The provider answered with an empty message twice, so
the nudge of wave 25 fired and carried the state of the work, and the run
ended with the workspace unchanged and the test of the task still failing.
The guard of waves 29 and 32 was never in the way: no edit was refused, no
edit was attempted.  This is the same shape as the failure of the pilot of
17:23 — the model that announces an action and calls no tool — and the
harness still cannot tell that a message which promises an action is not an
answer.

## The live checks and the pilot after wave 34 (2026-11-16, 06:58–07:08)

Wave 34 made the edit of Yeah open the file of the edit without the local
variables of the project, so that a file of the project cannot run its own code
through Emacs.  The verdict of the method on that code is `green`, with 87
claims `holds (current)` — the new one among them:
`an-edit-never-runs-the-local-variables-of-the-project`.

The live checks of 06:58–07:02 pass, all six of them:

| Check | Outcome |
|---|---|
| `live-model-call` | pass on the second attempt (`status="HTTP/2 200" answer="OK"`); the first attempt answered `status="HTTP/2 200" answer=""` |
| `live-coding-task` | pass on the first attempt |
| `live-interactive-path` | pass ("the interactive path works") |
| `live-service-path` | pass on the fourth attempt ("the primary path works with a live model"); the three attempts before it failed on the model, which refused the task |
| `live-fixed-point` | pass, one child ("the child repaired the canary") |
| `live-clean-install` | pass ("the clean installation works") |

Two things in that table are worth naming, because they are the provider and
not the harness.  The first attempt of `live-model-call` was answered with an
empty string and the status of a success, and the model of
`live-service-path` refused the task three times in a row (`:stopReason
"refusal"`, "the model did not create the file") before it wrote the file.

The pilot ran once on this code and measured **Yeah passed 1 of 3 tasks, pi
passed 3 of 3.**

| Task | Yeah | pi |
|---|---|---|
| `read-answer` | failed — `answer.txt` does not exist | passed |
| `fix-failing-test` | failed — the test still fails | passed |
| `write-new-file` | **passed** | passed |

**The parity is still not measured**: the threshold is a decision of the owner
(`docs/PLAN.md` §13) and the sample is three tasks.  The two runs before this
one measured 2 of 3 for Yeah and 3 of 3 for pi, so the difference between the
runs is the noise of the provider and the model, and not a regression of the
code of wave 34.

Both tasks that Yeah failed failed on the model and not on the harness, and
both failed in the same way: **the model read the files and never called the
tool that would change them.**  In `read-answer` the model read `sales.csv`,
computed the sum with `bash` (2036), answered with an empty message twice and
never called the write; the nudge of wave 25 fired and carried the state of the
work, the model repeated the exploration and the run ended `unfinished` with
the nudge budget spent.  In `fix-failing-test` the model read `calc.el` and the
test, ran the test, read them again, answered with an empty message twice and
announced "I'll look at the current state of calc.el." without a tool call
afterwards.  The guards of waves 29, 32, 33 and 34 were never in the way: no
edit was refused, no edit was attempted, and no local variable of the project
ran.

This is the third shape of the same failure: the model of the provider puts
its plan into the text of the answer and emits neither a text nor a tool call
(`docs/ARCHITECTURE.md` §D1 names it).  The harness cannot tell that a message
which promises an action is not an answer.

## The live checks and the pilot after wave 35 (2026-11-16, 07:59–08:14)

Wave 35 made the delegation of a child a tool of the kernel: `delegate` names
an agent preset and hands the model of the preset, the tools of the preset and
the instructions of the preset to a child that runs in a session of its own,
and `delegate-result` reports what became of it.  The verdict of the method on
that code is `green`, with 90 claims `holds (current)` — the three new ones
among them:

- `a-child-runs-with-the-model-and-the-tools-of-its-preset`
- `a-delegation-does-not-hold-the-turn-of-its-parent`
- `the-plan-profile-denies-a-delegation`

Each of the three has a control that breaks the subject and not the check, and
each of them fails exactly one test.

The live checks of 07:59–08:07 pass, all six of them:

| Check | Outcome |
|---|---|
| `live-model-call` | pass on the third attempt (`status="HTTP/2 200" answer="OK"`); the two attempts before it answered `status="HTTP/2 200" answer=""` |
| `live-coding-task` | pass on the first attempt |
| `live-interactive-path` | pass ("the interactive path works"); the attempt before it ended with an empty answer of the provider |
| `live-service-path` | pass on the first attempt ("the primary path works with a live model") |
| `live-fixed-point` | pass on the third attempt, one child ("the child repaired the canary"); the two attempts before it failed on the provider: an empty answer and a transport that died ("Curl failed with exit code 28") |
| `live-clean-install` | pass ("the clean installation works") |

Three of the six needed a second attempt or more, and every one of those
attempts failed on the provider and not on the harness: empty answers with the
status of a success, and a transport that timed out.  That is the shape the
provider has had for two days.

The pilot ran once on this code and measured **Yeah passed 2 of 3 tasks and 1
was blocked, pi passed 3 of 3.**

| Task | Yeah | pi |
|---|---|---|
| `read-answer` | blocked — the provider failed: the model had read the file and computed the sum with `bash`, and the transport to the provider died with "Curl failed with exit code 28" | passed |
| `fix-failing-test` | **passed** | passed |
| `write-new-file` | **passed** | passed |

**The parity is still not measured**: the threshold is a decision of the owner
(`docs/PLAN.md` §13) and the sample is three tasks.  The blocked task is not a
failure of the agent: the runner records a run that the provider stopped as
blocked, and it says nothing about either harness.

The two tasks that Yeah worked on passed, and they are the first two of a row
after the runs of waves 33 and 34 measured 2 of 3 and 1 of 3.  The difference
between the runs is the noise of the provider and of the model, and not a
regression of the code: the guards of waves 29, 32, 33 and 34 were never in the
way, no edit was refused, and no delegation was attempted — the benchmark has a
fixed set of tools, and the delegation is not among them, so the pilot measured
the parent alone.

## The live checks and the pilot after wave 36 (2026-11-16, 09:50–10:11)

Wave 36 gave a delegation the run that asked for it.  The run binds the
session it writes into while it dispatches the call, and the child of that
call is written into the journal of that run and of no other; the id of a
child is short (`sub-1`), a wrong id is refused by name and the refusal names
the children that do exist; and a child has a time of its own (`timeout:` in
the preset, 900 seconds by default).  The verdict of the method on that code
is `green`, with 94 claims `holds (current)` — the four new ones among them:

- `a-delegation-is-written-into-the-journal-of-its-own-run`
- `a-child-is-found-by-a-short-id`
- `delegate-result-names-the-children-of-the-run`
- `a-child-ends-when-its-time-is-up`

Each of the four has a control that breaks the subject and not the check, and
each of them fails exactly one test.  The control of the first one breaks the
code of wave 35 as well: the new test of the journal fails on the code of
wave 35, and that is the proof that the defect the audit found was real.

The live checks of 09:50–10:11 pass, all six of them, but the provider is
in its worst shape of the week and four of the six needed more than one
attempt:

| Check | Outcome |
|---|---|
| `live-model-call` | pass on the second attempt (`status="HTTP/2 200" answer="OK"`); the attempt before it answered `status="HTTP/2 200" answer=""` |
| `live-coding-task` | pass on the first attempt |
| `live-interactive-path` | pass on the second attempt ("the interactive path works"); the attempt before it died with "Curl failed with exit code 28" |
| `live-service-path` | pass on the first attempt ("the primary path works with a live model") |
| `live-fixed-point` | pass on the fourth attempt ("the child repaired the canary"); the three attempts before it failed at the provider: the child answered with an empty message four times (twice) and once described its next step four times and called no tool |
| `live-clean-install` | pass ("the clean installation works") |

Every attempt before a pass failed on the provider and not on the harness: an
empty answer with the status of a success, a transport that timed out, and a
child that announced its next step and called no tool.  That is the shape the
provider has had for two days.

The pilot ran once on this code and measured **Yeah passed 2 of 3 tasks, pi
passed 3 of 3** (`bench/results/20261116T100011Z.jsonl`).

| Task | Yeah | pi |
|---|---|---|
| `read-answer` | failed — the sum was computed and the file was never written | passed |
| `fix-failing-test` | **passed** | passed |
| `write-new-file` | **passed** | passed |

The journal of the third task says exactly what happened: the model read the
file with `read`, computed the sum with `bash` (the tool answered `100`), and
then it answered with an empty message.  The harness nudged three times, every
nudge carrying the state of the work, and the run ended `unfinished` with the
nudge budget spent.  The file was never written, so the check of the task
failed and the runner recorded a failure of the agent.

This is not a regression of wave 36: `write-new-file` passed in the same
pilot, so the write path of the code of wave 36 works, and the guards of
waves 29, 32, 33 and 34 were never in the way.  It is the shape that cost the
tasks of waves 33, 34 and 35 as well.

**The parity is still not measured**: the threshold is a decision of the owner
(`docs/PLAN.md` §13) and the sample is three tasks.  Nobody may quote this
run as a verdict about parity.

### The classification of a run that the provider silenced

The pilot also found a question about the measurement.  The runner knows that
the provider stopped a run from the error records of the journal
(`overloaded_error`, "curl failed"), and it records such a run as `blocked`:
neither a pass nor a failure of the agent.  The silence of the provider is not
an error record — the transport answered with the status of a success and the
body of an empty answer — so the run of `read-answer` was recorded as a
failure of the agent, although the work was never finished because the
provider stopped talking.

The two shapes are told apart by the journal, and the question "is a run that
the provider silenced a failure of the agent or a run that was never
measured" is not decided.  It stands in `docs/PLAN.md` §17.1 and in
`docs/PLAN-NEXT.md`.  Nothing in this wave changes the number of the pilot:
the number above is the number the runner recorded.

## The live checks and the pilot after wave 37 (2026-11-16, 10:41–10:44)

Wave 37 moved the tree of the children into the journal.  The journal of the
run holds the short id, the session and the depth of every child, and the
journal of the child holds where that child stands in the tree: its parent,
its depth and the id the model calls it by.  A harness that starts again
reads the tree from there — the child of a run is found by the id the model
was given, what became of it is told, and a child the journal holds no end of
is not reported as a child that still works, because the restart ends the
child as well.  The depth of a child is read from its own journal, so a child
of depth one does not look like a root after a restart.

The verdict of the method on that code is `green`, with 96 claims `holds
(current)` — the two new ones among them:

- `a-child-is-found-after-the-harness-restarts`
- `a-session-knows-its-depth-from-the-journal`

Each of the two has a control that breaks the subject and not the check, and
each of them fails exactly one test.  Both tests fail on the code of wave 36
as well: the defect was real, and the tests find it.

The live checks of 10:41–10:42 pass, all six of them, two of them on the
second attempt:

| Check | Outcome |
|---|---|
| `live-model-call` | pass on the first attempt (`status="HTTP/2 200" answer="OK"`) |
| `live-coding-task` | pass on the second attempt; the attempt before it did not repair the project ("the test of the project does not pass") |
| `live-interactive-path` | pass on the first attempt ("the interactive path works") |
| `live-service-path` | pass on the second attempt ("the primary path works with a live model"); the attempt before it failed at the provider: the model answered with an empty message and then refused |
| `live-fixed-point` | pass on the first attempt ("the child repaired the canary") |
| `live-clean-install` | pass ("the clean installation works") |

The provider was in a better shape than in the morning of wave 36: four of
the six checks passed on the first attempt, and the fixed point — the only
check that exercises a child of a live model — passed without a retry.

The pilot ran once on this code and measured **Yeah passed 2 of 3 tasks, pi
passed 3 of 3** (`bench/results/20261116T104357Z.jsonl`).

| Task | Yeah | pi |
|---|---|---|
| `read-answer` | failed — the sum was not written | passed |
| `fix-failing-test` | **passed** | passed |
| `write-new-file` | **passed** | passed |

The third task is the shape of the morning, and the journal says what
happened: the model read the file with `read`, ran `bash`, and then answered
with an empty message.  The harness nudged it — the nudge carries the state of
the work — and the model read the file again and went silent once more.  The
file was never written, so the check of the task failed and the runner
recorded a failure of the agent.  This is the same shape as the pilot of wave
36 and the same provider, and `write-new-file` passed in the same pilot, so
the write path of the code of wave 37 works.

**The parity is still not measured**: the threshold is a decision of the owner
(`docs/PLAN.md` §13) and the sample is three tasks.  Nobody may quote this run
as a verdict about parity.

## The live checks and the pilot after wave 38 (2026-11-16, 13:10–13:12)

Wave 38 made the pilot name the shape of a run that did not finish.  The
journal of a run already held that shape — the record `unfinished` says that
the model answered with an empty message three times, or that it described
its next step three times and called no tool — and the row of the run in the
results of the pilot said only that the check exited 1.  Now the reason of the
row begins with what the journal holds, and the verdict of the row is
untouched: whether such a run is a failure of the agent or a run that was
never measured is still the decision of the owner (`docs/PLAN.md` §17.2).

The verdict of the method on that code is `green`, with 97 claims `holds
(current)` — the new one among them:

- `the-pilot-names-the-shape-of-a-run-that-did-not-finish`

Its control breaks the subject and not the check: with the naming taken out
of the reason of the row, exactly one check fails, and it fails on the row
that does not name the shape.  The self-check of the bench still holds under
that control, so the two claims of the bench keep their evidence.  The check
fails on the code of wave 37 as well, with a message and not with a crash.

The live checks of 13:10–13:11 pass, all six of them, two of them on the
second attempt:

| Check | Outcome |
|---|---|
| `live-model-call` | pass on the second attempt; the attempt before it was answered by the provider with an empty message (`status="HTTP/2 200" answer=""`) |
| `live-coding-task` | pass on the first attempt |
| `live-interactive-path` | pass on the first attempt ("the interactive path works") |
| `live-service-path` | pass on the second attempt ("the primary path works with a live model"); the attempt before it failed at the provider: the model answered with an empty message and then refused |
| `live-fixed-point` | pass on the first attempt ("the child repaired the canary") |
| `live-clean-install` | pass ("the clean installation works") |

The provider was in a better shape than in the morning: four of the six checks
passed on the first attempt, and the fixed point — the only check that
exercises a child of a live model — passed without a retry.

The pilot ran once on this code and measured **Yeah passed 1 of 3 tasks, pi
passed 3 of 3** (`bench/results/20261116T131159Z.jsonl`).

| Task | Yeah | pi |
|---|---|---|
| `read-answer` | failed — the sum was not written | passed |
| `fix-failing-test` | failed — the file was not repaired | passed |
| `write-new-file` | **passed** | passed |

This is the first pilot in which two tasks of Yeah failed, and the rows say
why — that is what wave 38 added:

```
read-answer    yeah  failed  1  the run did not finish: the model answered with an
                                empty message 3 times and the run ended without an
                                effect; the check exited 1: check: answer.txt does
                                not exist | ...
fix-failing-test yeah failed 1  the run did not finish: the model answered with an
                                empty message 3 times and the run ended without an
                                effect; the check exited 1: FAILED calc-average-keeps-
                                the-fraction | ...
```

The journals of the two runs agree with the rows.  In `read-answer` the model
read the file, computed the sum with `bash` (the tool answered `100`) and then
answered with an empty message three times; the harness nudged it three
times, every nudge carrying the state of the work, and the file was never
written.  In `fix-failing-test` the model read `calc.el` and `calc-test.el`,
went silent three times, and never called the edit.  The third task
(`write-new-file`) passed in the same pilot, so the write path of the code of
wave 38 works.

**The parity is still not measured**: the threshold is a decision of the owner
(`docs/PLAN.md` §13) and the sample is three tasks.  Nobody may quote this run
as a verdict about parity.  The number of this run is lower than the number
of the runs of waves 36 and 37 (2 of 3 each), and the cause is the same
provider that silenced the model in those runs; what this run adds is that the
rows say so.

## The live checks of the ACP route (2026-11-16, 14:34–15:11)

These runs were made for a different question than the waves above: not
"does Yeah work", but "does the ACP route — the way an orchestrator drives
an agent — report the truth".  The provider was MiniMax-M3.1-Flash (and
M2.5, M2.7, M3 for the cross-checks), the key came from the environment and
is in no repository, and the transport was the socket one: a service Emacs
serving ACP to a client that answers `session/request_permission`.

| Check | Outcome |
|---|---|
| `live-model-call` | **fail** — and the check is at fault, not the provider (§ below) |
| `live-coding-task` | pass on the first attempt: `state=completed`, the project repaired, the test of the project green |
| `live-service-path` | **fail** — the model announced the file and the run ended `end_turn` with nothing done and no permission asked |

The failure of `live-service-path` is the finding.  Its journal holds six
records and nothing else:

```text
header → input-queued → input-taken → user-message → usage → assistant-message
```

where the assistant message is "I'll create that file now.".  The client
received `stopReason: "end_turn"` — the run looked finished and was not.
The cause is in the default of the route, not in the provider:
`yeah-turn-default-max-nudges` is 0 (`lib/yeah-turn.el:118`), the frozen
input carries it (`lib/yeah-control.el:51-59`), and with a budget of zero
the turn neither nudges a model that only announces its next step nor
writes the record `unfinished` — it marks the run done
(`lib/yeah-turn.el:755`, `:782`, `:795`).  The behaviour is deliberate and
is fixed by an offline test (`tests/unit/test-yeah-control.el:190`).

With `(setq yeah-turn-default-max-nudges 3)` in the init form of the same
service, the same live task works: the model announces the file, the
harness nudges it ("You have not called these tools yet: …"), the model
calls `write`, the file appears, the model ends the run with `finish`.  The
nudge fires on the announcement itself — `yeah-turn-plan-regexp` matches
"I'll write the file with that content." and "I'll create that file now."
(checked by running it), so the harness does tell a promise from an
answer; it is the budget of the route that stops it from acting on that
knowledge.

Two more measurements of the same runs:

- The `cwd` of the session does not reach the tools.  The model was told to
  write the relative path `answer.txt`; the file landed in the working
  directory of the service process, not in the `cwd` of the session
  (measured twice, in two independent runs).
- `live-model-call` fails with `answer=""` on M2.5, M2.7 and M3, and the
  provider is innocent: a direct request to the provider returns HTTP 200
  and a non-empty `content` for all four models, and the same request
  through `yeah-gptel-request` without tools answers "OK".  The check stops
  waiting at the first string it receives — the empty string that arrives
  between the reasoning block and the tool call — and it counts a tool
  call as no answer.  A model that answers with the `finish` tool, as the
  prelude of Yeah asks it to, is not a model that failed to answer.

## The live checks after the kernel began to supervise (2026-11-16, 16:05–16:10)

These runs repeat the live checks of the ACP route on the code of wave 39.  The
provider was MiniMax-M3.1-Flash (and M2.5, M2.7, M3 for the cross-checks), the
key came from the environment and is in no repository.

| Check | Outcome |
|---|---|
| `live-model-call` | pass on all four models: M2.5 and M2.7 answer with a tool call (`shape=tool-call`), M3 and M3.1-Flash answer with the text (`shape=text answer="OK"`); the status is `HTTP/2 200` every time |
| `live-service-path` | **pass** — "the primary path works with a live model"; the file appears in the working directory of the service and holds `42` |
| `live-coding-task` | pass: the project is repaired and the test of the project is green |
| `live-fixed-point` | pass: the child repaired the canary |

Two things changed, and both are visible here.

**The stand of the transport was at fault, and the provider was innocent.**  The
stand stopped waiting at the first string it received, and the empty string
that a reasoning model sends between its thinking and its answer was the
absence of an answer; a tool call was no answer either.  The stand now waits
for a terminal form, and the decision what counts as an answer lives in
`tests/support/yeah-live-answer.el` and is tested offline.  The row above is
the proof that the provider answers all four models: the M2.5 and the M2.7
answer with a tool call, and the stand now calls that an answer.

**The route of the ACP does not call a run without an effect finished.**  The
run of `live-service-path` of 14:34 answered `end_turn` after the model had
only announced the file.  On the code of wave 39 the same task works: the
harness nudges the model, the model calls `write`, the write is approved over
the wire, the file appears, and the model ends the run with `finish`.  The
budget of the supervision of the kernel is positive now
(`yeah-turn-default-max-nudges` is 3), so a run is supervised unless the
caller asks for no supervision at all, and a run that spends its budget ends
in the state `failed` and is answered with the stop reason `refusal`.

## What is still open

- A real editor (an agent-shell, or a person's Emacs) against a live
  provider: not yet checked.
- The bridge to the buffers of an attached Emacs against a person's Emacs in
  day-to-day use: the live daemon is checked, the daily use is not.
- The picture of the interface is compared with itself and with the same
  buffer without the interface, not with a stored golden picture.
- The parity with other harnesses is measured on three tasks only.  The
  threshold is not decided (`docs/PLAN.md` §13) and the sample is small, so
  the parity of the last run is not measured either.  The run of wave 38
  measured 1 of 3 for Yeah and 3 of 3 for pi, and two tasks of Yeah failed
  after the model had gone silent three times; the run of wave 37 measured
  2 of 3 for Yeah and 3 of 3 for pi, and the third task of Yeah failed after
  the model had gone silent twice; the run of wave 36 measured 2 of 3 for
  Yeah and 3 of 3 for pi, and the third task of Yeah failed after the
  provider had silenced the model three times; the run of wave 35 measured
  2 of 3 for Yeah and 3 of 3 for pi, and the third task of Yeah was blocked
  by the provider; the run of wave 34 measured 1 of 3 for Yeah and 3 of 3
  for pi, the run of wave 33 measured 2 of 3 and 3 of 3.  The difference the
  runs found was not the quality of the work but a model that announced the
  fix and called no tool.
- A run that the provider silenced and a run that the provider failed are not
  told apart by the runner: the silence is not an error record of the
  journal, so the runner records it as a failure of the agent, and a run that
  was never measured counts against the agent.  The pilot of wave 38 measured
  two tasks of Yeah in that shape (the sum was computed, the file was never
  written; the files were read, the edit was never called), and the pilot of
  wave 37 measured the third task in the same shape.  Whether that shape is a
  failure of the agent or a run that was never measured is not decided, and
  the decision belongs to the owner (`docs/PLAN.md` §17.2).  Since wave 38 the
  row of such a run names the shape of it, so that the reader of the pilot
  sees the cause of the failed check and not only its verdict.
- The delegation of wave 35 is not exercised by a live model in the pilot:
  the benchmark gives its runs a fixed set of tools, and the delegation is not
  among them.  The live evidence of a child that works is the fixed-point
  check, and that is one child and one task.  The id of a child is short
  since wave 36 (`sub-1`), so a model that has to copy it into
  `delegate-result` can no longer lose a character of it, and a wrong id is
  refused by name together with the children that do exist.  Since wave 37
  the tree of the children is in the journal, so a restart of the harness
  finds the child of a run again and tells what became of it; the live
  evidence of that is the code of wave 37, not a live run of it.
- The token of the file was 64 characters of hex and the model copied 58 of
  them, so the guard refused the edit of a file that had not changed.  Wave 32
  shortens the token and makes the refusal name the token instead of the
  file; the pilot of 17:23 handed out a token of twelve characters and the
  tasks that the model worked on passed.  A model can still lose a character
  of twelve, and the harness cannot make the model retry.
- A model can end its turn with a message that announces an action and call no
  tool: the pilot of 17:23 measured "Fixing it to use floating-point
  division:" and nothing after it.  The harness cannot tell that a message
  which promises an action is not an answer, and the nudge of wave 25 fires
  when the model is silent and not when the model talks without acting.  The
  pilot of 2026-11-16 measured the same shape in a longer form: the model
  read the files of the task four times, ran the test twice, never called the
  edit, and the provider answered with an empty message twice.  The pilot of
  wave 34 measured it twice more: "I'll look at the current state of
  calc.el." without a tool call after it, and a model that computed the sum of
  a table and never called the write.
  **The live checks of the ACP route of 14:34–15:11 corrected the second half
  of that sentence.**  The harness does tell a promise from an answer:
  `yeah-turn-plan-regexp` matches "I'll write the file with that content."
  and "I'll create that file now.", and a run that asks for supervision is
  nudged on such an announcement — measured with a live model.  What is left
  is the budget: the ACP route runs with `yeah-turn-default-max-nudges` = 0,
  so there is nobody to nudge it, the record `unfinished` is not written
  either, and the run ends as `completed` — `stopReason: "end_turn"` for a
  run that did nothing.  Whether the default of the route changes is a
  decision of the owner (`docs/PLAN.md` §17.2).
- The outcome of a run does not describe the work that was done: the run of
  `fix-failing-test` ended in "failed" because the provider failed after the
  edit, while the check of the task passed.  The check of the benchmark is the
  arbiter, so the measurement is right; the person is told something else.
- The model of the provider goes silent after a batch of tool results: it puts
  its plan into the reasoning and emits neither a text nor a tool call.  The
  run then ends with the record "unfinished", which is honest, but the work is
  not done: the live coding task of 15:38 repaired nothing.  The nudge carries
  the state of the work (wave 25), and the harness cannot do more than ask
  again; what the provider does with the tools of a turn is not in its hands.
- The provider is overloaded for hours: HTTP 529 to both harnesses, and a
  plain model call that answers with nothing now and then.  A measurement of
  the parity needs a provider that answers; until then the runs that the
  provider stops are recorded as blocked and say nothing about the agents.
  The checks of wave 34 measured two more shapes of it: a call that answered
  with the status of a success and an empty string, and three refusals of the
  same task in a row (`:stopReason "refusal"`).  A refusal is a failure of the
  model and not of the harness, and it is told apart from it here.
