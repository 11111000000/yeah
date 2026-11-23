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
| `tests/live/live-two-children.el` | two children in one turn of a live parent: the model is asked for two delegations in one turn, the journal of the parent holds the spawn of two children with different short ids, the finish of the parent comes after them, and both children end on their own | provider key | `emacs -Q --batch -L /path/to/gptel -L lib -l tests/live/live-two-children.el` | 2026-11-23 10:28 UTC, on the code of wave 110, with MiniMax-M2.7 — pass (exit 0): the spawn of `sub-1` and `sub-2` at 10:28:04 UTC in the turn `turn-2`, the finish of the parent at 10:28:18, and the end of both children on their own.  The first attempt failed on two defects of the path: the directories of the presets were bound with `let` and the tools of a child run in the event loop, long after the binding was gone ("no agent named \"reviewer\""), and the child had no tool `finish`, so it could never end and worked for ever ||
| `tests/live/live-clean-install.el` | the published repository installs into a clean Emacs: the documented bootstrap runs in a throwaway HOME, the installed package loads, and `yeah`, `yeah-ask` and `yeah-doctor` are bound | network | `emacs -Q --batch -L lib -l tests/live/live-clean-install.el` | 2026-11-16 13:11 UTC, against the published repository (revision `a0259e6`), on the code of wave 38 — pass: "the clean installation works" ||
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

The fifth run of the pilot, on the code of wave 28 (`008c1ca`), under the same
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

The live checks on the code of wave 28 (`008c1ca`), with a live provider:

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
code of waves 30+31 (`d833a9d`), with MiniMax-M2.7 and pi as the second
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

## The live coding run after wave 45 (2026-11-17, 15:31–15:33)

Wave 45 made the harness survive what the tools return.  The run below is the
first live run on that code, and it is a **coding** run: the model had to write
a program, write its tests, run them and repair them if they failed.  The
provider was MiniMax-M3.1-Flash at `api.minimax.io`, the key came from the
environment and is in no repository, and the harness ran in
`/home/az/Projects/yeah-live-2` with the tools `read`, `glob`, `grep`, `edit`,
`write`, `bash`, `finish`, `introspect` and `diagnostics`.

The task: write `calc.py`, a console calculator that evaluates an arithmetic
expression (`+`, `-`, `*`, `/`, parentheses, unary minus, spaces) taken from the
command line or from stdin, printing the result on stdout and a readable
message on stderr with exit code 2 on a division by zero or a syntax error;
then write `test_calc.py` with at least eight `unittest` tests; then run
`python3 -m unittest -v` and repair the code until the tests pass; then finish
through the tool `finish`.

**The run ended in the state `completed`, and the work is really there.**  The
journal of the session (`sessions/calc.jsonl`, 118 records, 91 348 bytes) holds
17 tool calls — `write` twice, `bash` seven times, `glob` twice, `read` once,
`git_status` once, `todo_add` three times, `todo_list` once — with a permission
request and a permission decision for every one of them, 33 usage records, 4
assistant messages and 3 nudges.

| What the model wrote | Size |
|---|---|
| `calc.py` | 5 553 bytes |
| `test_calc.py` | 4 699 bytes |

The arbiter of the task is outside the harness: run by hand in the directory of
the task, `python3 -m unittest -v` prints `Ran 15 tests` and `OK` and exits 0.
The model wrote 15 tests where the task asked for eight, and the run of the
tests inside the harness (`python3 -m unittest -v 2>&1 | tail -40`) shows every
one of them `ok`.

**The harness had to push the model three times.**  The provider answered with
a plan instead of an action — "I'll create the calculator program and its
tests." and "Nothing exists yet in the project dir except the session log, so
I'll create the two files now." — and every nudge of the harness carried the
state of the work into the model: which tools the run had not called yet, and
the sentence "your next answer must contain the tool call, not a plan".  The
run recovered each time and the work was done.  This is the shape the register
has named since wave 34; what is new here is that the work was finished after
the third nudge, and that the state of the run says so.

**The run is also the first live proof of wave 45.**  One of the commands of
the model was `head -c 3000 sessions/calc.jsonl`, which cut a multibyte
character of the journal in half: the tool returned a string with a raw byte.
Before wave 45 that string was written into the journal as it was, and
`json-serialize` refused it (`wrong-type-argument json-value-p`) — the defect
of the run of 2026-11-16, where the error of the sentinel killed the process.
On this code the harness replaced the raw byte with U+FFFD: the journal of the
run is valid UTF-8 from the first byte to the last, and it holds two U+FFFD
where the two reads of the cut output were written (`tool-end` id 57 and id
64).  The live coding task of the register has a new failure mode that the
code of wave 45 no longer has.

**Two things the run did not do, and the register does not hide them.**

- The model never called the tool `finish`, although the task asked for it.
  The run ended with a text message, and the harness recorded `completed`.
  The state of a run is therefore not a proof that the instructions of the task
  were followed; the check of the task is.
- The last message of the model was "All 15 tests pass. Verifying the CLI
  end-to-end from a shell:" — an announcement of a step that was never taken.
  The harness did not nudge it, because the regexp of the plan
  (`yeah-turn-plan-regexp`) knows "I'll", "I will", "Let me", "I'm going to"
  and "I am going to", and this sentence opens with the report of a finished
  work ("All 15 tests pass") and continues with "Verifying".  A message that
  reports a result and announces the next step at the same time is a plan in
  part, and the harness does not see that part.  The task was already done, so
  the gap costs nothing here; it is open.
- The tools of the run ran in the directory that the model named in the call
  (`bash` carries a directory argument, and the model passed
  `/home/az/Projects/yeah-live-2` itself), not in the working directory of the
  session: the working directory of a session is still not applied to the
  tools (`docs/PLAN.md` §17.1).  This run says nothing about that defect
  either way.

**What this run does not prove.**  It is one task, one model and one provider
on one day.  It says nothing about the parity with another harness (the
threshold is a decision of the owner, `docs/PLAN.md` §13).  It is not a check
of the register either: it was driven by the driver of the site
(`/home/az/Projects/yeah-site/artifacts/driver.el`), not by a check of
`tests/live/`, and a run of `live-coding-task` on the code of wave 45 is still
owed.

## The self-development run that found the noise of the provider (2026-11-17, 15:45–15:53)

The next live run was the first run of Yeah on the task of the owner: the wave
41 of the plan (`docs/PLAN.md` §18.1), the deterministic verifier of the
bridge.  The harness ran in a copy of the repository with the code of wave 45
(`/home/az/Projects/yeah-selfdev-1`), the provider was MiniMax-M3 at
`api.minimax.io`, and the model was told that it works in the repository of
Yeah itself.

**The run failed, and the failure was the harness's.**  The journal of the
session (`sessions/wave41.jsonl`, 132 records, 232 577 bytes) holds 17 calls of
tools — `read` eight times, `git_status` three times, `bash` three times, and
`glob`, `grep` and `todo_list` once each — with a permission request and a
permission decision for every one of them, 8 nudges and 9 assistant messages.
The model was working: it read the rules of the repository, searched them, ran
the commands and kept its state.

The provider answered every batch of those results with an empty message.  The
harness read that silence as the silence of a model that does not act, spent
the whole budget of the nudges on it (eight), and ended the run in the state
`failed`.  The last record of the journal said:

> the model answered with an empty message 8 times and the run ended without an effect

Both halves of that sentence were false.  The run had an effect — seventeen
tools — and the model had not refused to act: it had acted, and the results
were in front of it.  The five empty answers were the noise of the provider.

This is the defect of wave 46 (`docs/PLAN.md` §16.25).  The budget of the
nudges now pays for the nudges that no effect answered: a nudge that follows
the silence of the provider after the tools of the model have come back does
not spend it, and a model that never acts still ends.  The record of a run that
did not finish names the tools the run called, so a run that called its tools
is never described as a run that ended without an effect.

**What the run does not prove.**  The run of wave 41 on the code of wave 46 is
written down below.  The run above says nothing about the parity, and nothing
about the working directory of a session: the tools of the run ran in the
directory of the process, and the `cwd` of a session is still not applied to
them (`docs/PLAN.md` §17.1).

**The second run of the wave 41, on the code of wave 46 (16:16–16:23).**  The
same task, the same copy of the repository, the provider MiniMax-M3.1-Flash
this time, and the harness of wave 46.  The run made 108 calls of tools — 64
`bash`, 30 `read`, 4 `git_status`, 3 `glob`, 3 `grep`, 3 `todo_list`, one
`todo_add` — and 4 nudges, and it read the whole of the rules of the
repository, the plan, the check of the bridge, the claims of `spec.json` and
the history of the commits.  Then it started the whole suite of the checks of
the repository (`./scripts/dev check tests/checks/*`) inside the harness, and
while the harness was waiting for that, the transport to the provider died:
`Curl failed with exit code 28`.  The run ended in the state `failed` with
that error in the journal, and it changed no file of the repository.

The shape of that failure is the shape the register has named since wave 35: a
transport that times out is a run the provider stopped, and a run the provider
stopped is blocked and not a failure of the agent (`docs/PLAN.md` §17.2).  The
run is also the first live proof that wave 46 holds under a live provider: the
run of the wave 41 on the code of wave 45 spent its whole budget of nudges on
the silence of the provider and died, and the run of the same task on the code
of wave 46 was still alive after 108 calls of tools, with the budget of the
nudges untouched.

**What the second run says about the model.**  Two live runs of the same task
on the same code found the same shape: the model researches and does not
change anything.  The task asks for a rewrite of a check, and the model reads
the repository, measures the race with experiments of its own
(`/tmp/exp1.el`, `/tmp/exp2.el`), and does not come to the change.  The
harness cannot tell the research from the work: both are calls of tools, and
the nudge of the harness names the tools the run has not called yet — among
them `edit` and `write`.  This is open work, and it is written down in
`docs/PLAN.md` §17.1.

## The self-development runs that found the missing memory (2026-11-17, 16:15–16:48)

Two more live runs of the wave 41 were made on the code of wave 46, with the
provider MiniMax-M3.1-Flash this time, in the same copy of the repository
(`/home/az/Projects/yeah-selfdev-1`).  The task was the same — the deterministic
verifier of the bridge (`docs/PLAN.md` §18.1) — and the second run was given a
tighter brief: *start with the change, do not run the whole suite of the
checks*.

**The second run (16:15–16:23).**  The journal
(`sessions/wave41b.jsonl`, 694 records, 928 652 bytes) holds 108 calls of tools —
64 `bash`, 30 `read`, 4 `git_status`, 3 `glob`, 3 `grep`, 3 `todo_list`, one
`todo_add` — 4 nudges and 4 assistant messages, and every one of those messages
is a plan: "I'll start by reading the repository rules", "I'll start by
exploring the repository structure".  The tool `read` was called on `AGENTS.md`
ten times, on `docs/PLAN.md` five times, on `docs/PLAN-NEXT.md` four times and on
`waves/wave-46.json` three times.  It read the whole of the rules of the
repository, the plan, the check of the bridge, the claims of `spec.json` and the
history of the commits, and then it started the whole suite of the checks of the
repository (`./scripts/dev check tests/checks/*`) inside the harness.  While the
harness was waiting for that, the transport to the provider died: `Curl failed
with exit code 28`.  The run ended in the state `failed` with that error in the
journal, and it changed no file of the repository.

**The third run (16:26–16:48).**  The journal (`sessions/wave41c.jsonl`, 769
records, 1 125 827 bytes) holds 122 calls of tools — 64 `bash`, 27 `read`, 10
`grep`, 5 `todo_list`, 5 `write`, 4 `glob`, 3 `git_status`, 2 `git_diff`, one
`todo_add`, one `todo_update` — 7 nudges and 7 assistant messages, and every
one of those messages is a plan as well: "Let me measure the actual race
behaviour with the real `emacsclient` before designing the fix".  The `read`
tool was called on `AGENTS.md` nine times and on `waves/wave-46.json` five
times.  The five
`write` calls of the run went to `/tmp/exp1.el` … `/tmp/exp4.el`: the model
measured the race with experiments of its own and did not come to the change.
The repository was not touched.  The transport died at the end with `Curl
failed with exit code 16`.

**The reason is in the harness, and the journals show it.**  Every request of
the harness starts a *fresh conversation* with the model: `yeah-turn--ask` hands
the transport a prompt, and the prompt is all the model is told.  The usage
records of the third run show it plainly — the first request of the run carried
4149 input tokens, and the last request, after 122 calls of tools, carried 919.
A conversation that grows with the work would grow; this one does not grow at
all.  So the model is asked again and again with nothing but the request, it
cannot see what it has already done, and it starts the task over: it reads
`AGENTS.md` ten times in one run, reads the claim of the wave 46 five times in
another, and never reaches the change.

The machinery of the context is not the cause: it exists, and it is not on the
road to the model.  `yeah-context-project` and `yeah-session-project` compute a
projection, the compaction and the pruning write their events into the journal,
and the projection itself never reaches a request.  What the model got was the
prompt and nothing else.

**This is the defect of wave 47 (`docs/PLAN.md` §16.26).**  Every request of a
run now carries the transcript of the run before the prompt: a projection of
the journal — the call the model made, the result it got and the answer it gave
— and the words that keep the work where it is ("Do not start the work over:
continue from here.").  The first request of a run carries the request as it
is, because a run that has done nothing has nothing to tell.  The transcript is
a projection and not a second copy of the run: the journal keeps the plain
message it was written with.

**What the runs do not prove.**  Neither run says anything about the parity, and
neither run is a proof that the transcript is enough: the model of these runs
answers with a plan instead of an action, and that shape is not repaired by
being told what the run has done (`docs/PLAN.md` §17.1).  The `cwd` of a session
is still not applied to the tools (§17.1), and the transport of the provider
died in both runs, which the register has named since wave 35 as a run the
provider stopped and not a failure of the agent (§17.2).

## The run on the code of wave 47 and the death of the transport (2026-11-17, 17:10–17:15)

A third live run of the wave 41 was made on the code of wave 47, in the same copy
of the repository (`/home/az/Projects/yeah-selfdev-1`), with the same task and the
same model (MiniMax-M3.1-Flash).

**The journal (`sessions/wave41d.jsonl`, 429 records) holds 70 calls of tools** —
33 `bash`, 20 `read`, 9 `write`, 4 `grep`, 3 `glob`, one `todo_list` — 3 nudges
and 3 assistant messages, and the three messages are plans as well: "I'll start
by opening the two files the task points at", "Now let me look at the check
runner and experiment with the actual Emacs behaviour", "Let me experiment with
Emacs 30 process semantics to find the exact loss window".

**The effect of wave 47 is visible in the journal.**  The tool `read` was called
on `AGENTS.md` **once** — the runs of 16:15 and 16:26 called it ten and nine
times — and the twenty reads of the run went to fifteen different files.  The
input tokens of the requests do not grow with the work: the first request of
the run carried 4320 input tokens and the last 888, where the runs before the
transcript carried 3997 → 793 and 4149 → 919.  The model no longer starts the
task over: it reads the rules of the repository once and works.

**The work still did not happen.**  The nine `write` calls of the run went to
`/tmp/exp1.el`, `/tmp/exp5.el`, `/tmp/exp6.el` and `/tmp/exp/exp1.el`: the model
measured the race of the bridge with experiments of its own and never came to
the change in the repository.  The run ended with the transport dead: `Curl
failed with exit code 28`.

**Three runs in a row died the same way**, after 108, 122 and 70 calls of tools:
`Curl failed with exit code 28`, `Curl failed with exit code 16`, `Curl failed
with exit code 28`.  The harness read the death of the transport as the end of
the run and threw the work of the model away with it.

**This is the defect of wave 48 (`docs/PLAN.md` §16.27).**  A request that the
provider dropped is asked again: the death of the transport is not the death of
the run.  The retry is bounded (two by default), the journal holds it as a
record of its own, and the model is asked the same question with the transcript
of the run in front of it, so the retry continues the work.  A request that the
provider *refused* is an answer and is not asked again.

**What this does not prove.**  The run on the code of wave 47 says that the
transcript reaches the model and that the model stops starting the task over; it
does not say that the model then makes the change, and it did not.  The shape of
the provider that answers with a plan instead of an action is not repaired by
either wave (§17.1), and the guard that asks the model for the change after a
number of calls of tools without one is still open (§17.1).  The run of 17:10
was made before the code of wave 48, so it does not measure the retry either.

## The self-development run that found the compaction that did not wait (2026-11-17, 17:58–18:17)

A fourth live run of the wave 41 was made on the code of the waves 47 and 48, in the
same copy of the repository (`/home/az/Projects/yeah-selfdev-1`), with the same
task and the same model (MiniMax-M3.1-Flash).  The journal
(`sessions/wave41e.jsonl`) holds 2170 records of 19 minutes.

**The model wrote to the repository for the first time.**  337 calls of tools:
205 `bash`, 68 `read`, 20 `write`, 16 `edit`, 7 `elisp-check`, 6 `grep`, 5
`diagnostics`, 4 `glob`, 3 `git_status`, 2 `git_diff`, 1 `buffer-read`.  The
`write` and the `edit` of the run went to the repository itself: the check
`tests/checks/check-bridge-keeps-the-answer.el` was written and then edited
nine times, and a second check,
`tests/checks/check-bridge-check-decides-the-race-by-construction.el`, was
written.  The first check passes on the code of the run
(`./scripts/dev check tests/checks/check-bridge-keeps-the-answer.el`, exit 0).
The model did not register the claims of the task in `spec.json`: that is the
work the run did not finish.

**The retry of wave 48 worked in the live run.**  Nine records of the type
`retry`, among them the busy provider of the wave 48 (`overloaded_error`, the
status `529` of the wire) and eight deaths of the transport (`Curl failed with
exit code 28`).  Without the wave 48 the run would have died nine times.

**The run died in the tools and not in the provider.**  At 18:17:33 the journal
holds, in this order:

- `compaction-failed` (id 2158) — the compaction of the context said that the
  summary did not arrive;
- `pruning` (id 2159) — the run degraded and went on;
- `tool-request`, `permission-request`, `permission-decision` (ids 2160–2162) —
  the model called a tool of its own;
- `compaction` (id 2163) — the summary arrived after all, and committed a
  compaction;
- `error` (ids 2164–2166) — `yeah-loop-tick: no transition from awaiting-tool
  on continue`, and the cascade that followed it.

**This is the defect of wave 49 (`docs/PLAN.md` §16.28).**  The provider that
reasons sends its thinking before its answer, and the compaction took the first
piece for the answer: the run degraded for nothing, and the summary that came
later continued a run whose machine was in a state that has no such transition.
The compaction waits for the answer now, the outcome of a compaction is
delivered once, and the decision of an answer lives in the kernel
(`lib/yeah-answer.el`).

**What this does not prove.**  The run says that the harness can write to a
repository with a live provider and that the retry of wave 48 works in the
world; it does not say that the model finishes the task, and it did not: the
claims of the task were never registered in `spec.json`.  The shape of the
provider that announces its next step instead of acting is still there (four
assistant messages, all of them plans) and is not repaired by this wave
(§17.1).

## The self-development run that finished the wave 41 (2026-11-17, 18:48–19:15)

The wave 41 of the plan of the owner (`docs/PLAN.md` §18.1) is the wave that
repairs the evidence of the bridge: the check of `bridge-keeps-the-answer` used
to race the subject, five runs of six bit and one did not, and the map of the
method came out `unknown` for a reason that had nothing to do with the code it
named.  The wave was carried out by the harness itself: a live model
(`MiniMax-M3.1-Flash`) worked on a copy of the repository in a live run of
Yeah, and the journals of the copy (`sessions/wave41g.jsonl`,
`sessions/wave41h.jsonl`) hold the runs.

**What the model wrote, and what it found in it.**  The check of the wave
(`tests/checks/check-bridge-check-decides-the-race-by-construction.el`) reads
the control of the claim of the bridge from the standing specification, copies
`lib/` and `tests/` into a temporary directory, applies that control there and
runs the check of the bridge ten times; every one of the ten runs must fail by
an assertion of the check.  The model found three defects in that check while
it worked:
- the keys of a JSON object come as symbols from Emacs 30, so `alist-get "id"`
  found nothing, the control was never found, and the check said "the claim of
  the bridge declares no control to run";
- `file-copy-file` does not create the directory of the target, so the copy of
  the tree of the check failed;
- the buffer of the words of a run was bound in a `let` that binds in parallel,
  so the filter of the process saw a void variable (`void-variable (words)`).

The model then registered the new claim `the-bridge-check-decides-the-race-by-construction`
in `spec.json` with a control that breaks the determinism of the check (the
holding of the answer of the child process is taken out), and it did not touch
the claim of the bridge: its control bit twelve times of twelve, each time by
the assertion of the check.

**The two runs.**  The first run (the journal `wave41g.jsonl`) was killed by
the machine ten minutes into the work — after both changes were written and
after the control of the bridge had bitten twelve times in a row, and while the
model was verifying the criteria of the exit.  The second run (the journal
`wave41h.jsonl`) picked the work up from the tree, checked the three criteria
(the check of the wave passes on the whole bridge; the ten runs of the control
of the bridge each fail with `bridge-keep: the bridge lost the answer`; the
control of the new claim makes the check of the wave fail with "the run N of
the control ended with the code 0"), and finished through the `finish` tool at
19:14:58.  The state of the run was `completed` and the exit code of the driver
was 0.

**What this proves, and what it does not.**  The harness carries a task of that
size to its end with a live provider: the model reads the plan, writes the
check, finds the defects of its own check, registers the claim in the standing
specification, proves that the control bites and finishes.  The first run of
the wave (of 15:45–15:53, the section above) did not, and the difference
between the two runs is not the harness but the shape of the tree it was given:
the first run found the uncommitted changes of the repair waves and went to
verify them, and the second one found a clean tree and the work already done.
That is a fact about the setup of a run and not about the model alone, and it
belongs in the open list: a run that begins in a tree with changes in it has
no way to tell the work of the run from the work that was there before it.

The run does not measure the parity of the harnesses, and the second criterion
of the exit of the wave (two consecutive runs of the method that end in
`green`) was not met at that time: the verdict of the map was `unknown`,
because the human review of the plan of the owner was outdated, and that
decision belongs to the owner and not to a machine verifier
(`docs/PLAN.md` §17.2).  The criterion was met on 2026-11-18; the section
below holds the two runs.

## The map of the method came out green twice (2026-11-18, 03:00–03:18)

The second criterion of the exit of the wave 41 (two consecutive runs of the
method that end in `green`) needs three things at once: a run that reaches the
end, a review of the plan of the owner that is fresh at the time of the run,
and no change of the materials between the two runs.

**The run has to be detached.**  Three runs of the method died with SIGTERM at
the same place (the section above), and the sender of the signal is still
unknown.  The way around it is a watchdog: the run starts in a session of its
own (`setsid`), and after a death it starts again; the trail of evidence grows
with every attempt, so every attempt moves the map forward, and the cycle ends
when the map holds no claim that was never checked.  Both runs of this section
were detached in that way, and both of them reached the end on the first
attempt.

**The review of the owner.**  The claim
`the-owner-decided-the-order-of-the-next-waves` carries the review of the plan
of the owner as its evidence, and the material of that claim is `docs/PLAN.md`
itself: every edit of the plan makes the review stale, and a stale review makes
the verdict of the map `unknown`.  The paragraph of §18.1 that named the
verdict of the map as `unknown` was rewritten before the runs, so that the plan
no longer carries a statement about a verdict that the next run may change, and
the owner recorded the review again afterwards (`mathc record
the-owner-decided-the-order-of-the-next-waves owner --by az --outcome pass`).
The decision itself — the order of the waves of §18 — did not change.

**The two runs.**

| Run | Start | End | Duration | Code | Verdict |
|-----|-------|-----|----------|------|---------|
| A | 03:00:48 | 03:09:12 | 8 min 24 s | 0 | green |
| B | 03:09:20 | 03:17:54 | 8 min 34 s | 0 | green |

Every claim of the map (122 of them) holds, and 26 files are still uncovered.
The two runs are the ones the exit criterion asks for: the same materials, the
same review, two runs in a row, and the verdict `green` both times.

**What this does not prove.**  The map is green because every claim of it was
checked on this tree; it says nothing about the parity of the harnesses, which
is measured on three tasks and has no decided threshold (`docs/PLAN.md` §13).
The SIGTERM that killed three runs of the method is still unexplained, and the
watchdog is a way around it, not a repair of it.

## The live run of wave 42 that found the words of the model (2026-11-18, 06:24–06:38)

The live run of wave 42 (the life cycle of the ACP server) was the first run of
the harness on the code of waves 46 to 50, and it found a defect of the kernel
that no offline check had seen.  The run was on a copy of the repository
(`/home/az/Projects/yeah-selfdev-2`), with the model `MiniMax-M3.1-Flash`, and
its journal is `sessions/wave42-1.jsonl` (2464 records).

| Attempt | Start | End | Calls of tools | Nudges | Retries | Last words of the model | Final state |
|---|---|---|---|---|---|---|---|
| 1 | 06:24:28 | 06:32:25 | 261 | 5 | 2 | "Now the ACP module itself:" | `completed` |
| 2 | 06:35:08 | 06:38:45 | 142 | 4 | 0 | "Now the dispatcher and the serve loop:" | `completed` |

Both attempts ended with `final state: completed`, and **neither of them called
the `finish` tool**: the journal of the run holds no record of `finish` at all.
The work was not done — the model had added `yeah-acp-session-exit-method` to
`lib/yeah-acp-vocabulary.el` and implemented `yeah-acp-session-exit` and
`yeah-acp--end-session` in `lib/yeah-acp.el` (+64 lines), but the routing in the
dispatcher, the end of the server process, the check, the claim and the
documentation of the wave were not written.  The second attempt was given the
state of the work as its input, and it continued from there, and it was cut off
in the same way.

**The defect was in the kernel, and it was old.**  Every text answer of the
model ended the turn: the words of the model were taken for the end of the
work, and a run that had called 261 tools and finished nothing was recorded as
a successful one.  This is the opposite of what the claim
`finish-is-the-only-completion-path` says, and it is what the claim
`nudge-only-for-plans` says in practice: two claims of one specification
contradicted each other, and the code followed the softer one.  The strict
reading won in wave 53 (a supervised run ends through the call of `finish';
a text answer that reports a result is nudged into that call, and the nudge
carries the state of the work), and the record of a run that did not finish
names the form it had: "the model reported a result without calling `finish'
N times".  A run that asked for no supervision (a budget of zero) keeps the
old behaviour, because there is nobody to nudge it.

**What this run does not prove.**  The provider cut the model off in the middle
of a sentence twice, and the run of wave 42 is not finished; the wave 53
repair makes such a run say that it did not finish instead of claiming that it
did, and the continuation of wave 42 waits for it.  The spin of the server
process (`docs/PLAN.md` §17.1) was not located by this run either: it is the
second half of wave 42 and it is measured on the ticks of `/proc/<pid>/stat`.

## The spin of the server, measured three times (2026-11-18)

The spin of the server process was the second half of wave 42 of the plan of
the owner (`docs/PLAN.md` §18.2).  On 2026-11-16 a server process was measured
with 1 921 354 involuntary context switches and six voluntary ones -- it never
slept -- at 25-60 per cent of a core.  On 2026-11-18 the same thing was
measured three times on the code of that day, and the defect did not
reproduce.  The unit of the measurement is the tick of `/proc/<pid>/stat`
(user time plus system time), the unit the defect itself was measured in, and
not the percentage of the CPU that `top' prints.  The clock of the kernel
ticks a hundred times a second.

| Scenario | Ticks in 10 s | CPU | Share of a core | Bound (1 %) |
|---|---|---|---|---|
| A transport that never calls back | 0 | 0.000 s | 0.0 % | under |
| The live path of gptel and curl, the connection to the provider hangs (host 192.0.2.1) | 4 | 0.040 s | 0.4 % | under |
| The live path of gptel and curl, the provider streams keep-alives every 50 ms and never answers | 6 | 0.060 s | 0.6 % | under |

The second and the third scenarios are the live path: gptel with the backend
`gptel-openai`, the request going out through curl, the provider never
answering.  The third one is the shape that the plan suspected -- a provider
that speaks but does not answer, so that the output of the process is always
there and the pump of the wire wakes on every piece of it.

**What the measurement does not prove.**  It does not prove that the loop of
2026-11-16 was in the pump of the wire: the counters that would localize it
(the iterations of the pump and the iterations of the request of the provider)
are not in the code, and the measurement says only what the cost was.  The
bound is now a check of the repository
(`tests/checks/check-the-server-does-not-spin-when-the-provider-is-silent.el`,
the claim `the-server-does-not-spin-when-the-provider-is-silent'), and its
control brings the busy loop back: with the pump of the wire no longer
waiting, the process cost 6.000 seconds of CPU in ten seconds -- sixty per
cent of a core, the shape of the defect -- and the check failed by its own
assertion.

## The leaks of the run, measured and closed (2026-11-18, 12:00–15:00)

Six waves, six defects of one family: a process of the run outlived the thing
that started it.  The plan of the owner called it a spin
(`docs/PLAN.md` §16.39–§16.44), and the measurement said otherwise.  What
burned the core and filled the disk was not a loop but a leak: servers that
stayed alive after their owner was killed, checks that hung for ever, copies
of the project that survived the run that made them, and a watchdog that
waited instead of acting.  Each wave below states what was measured, what the
control did to the subject, and what the check found wrong with itself — the
last part is the reason the waves are trustworthy: every one of these checks
failed on its first run for a reason of its own.

### Wave 55 — the server of a service outlived its owner

The owner of a service was killed with SIGKILL, and the server of the service
was gone 0.2 seconds later — the bound of the plan is ten seconds.  The socket
of the service and the file of the life of the owner were gone as well; the
file of the life of a dead owner is swept by the next owner that starts a
service.  The control took the watch of the server out
(`sed -i 's|(and watch (lambda () (not (yeah-life-alive-p watch))))|nil|' lib/yeah-acp.el`),
and the check failed by its own assertion: `the server of the service stayed
behind after its owner was killed (pid 4729)' and `the socket of the service
stayed behind'.

The check found a defect of itself on the first run: it killed the owner with
`(signal-process pid "KILL")', and `signal-process' takes a symbol or a
number, not a string — the signal never went out, the owner stayed alive, and
the check failed.  The check now uses the symbol `KILL' and asserts that the
signal was sent, so a kill that did not happen is a failure of the check and
not a verdict of the subject.

### Wave 56 — a check of the gate leaves no server behind

A check of the suite was started through `scripts/dev check', the check
started a server on a local socket, the owner of that server was killed with
SIGKILL, and the server was gone within a second; the socket of the server
was gone with it.  The control took the inherited life out
(`sed -i 's|(let* ((life (or life (yeah-life-inherited-path)))|(let* ((life life)|' lib/yeah-acp.el`),
and the check failed by its own assertion: `the server of the check stayed
behind after its owner was killed (pid 7401)' and `the socket of the server
stayed behind'.

The check found two defects of itself on the first runs: it made the report
of the fixture with `make-temp-file' and a directory instead of a file, and
it built the path of the gate from the literal string `default-directory'
instead of the value of that variable.  Both are the kind of mistake that a
check which never fails can hide, and both are now the ordinary code of the
check.  The fixture of the wave lives in `tests/support/' and not in
`tests/checks/': it never ends by itself, so the gate must not run it as a
check of its own.

A third defect of this check was found by wave 58, and it is worth naming
here: the check ended its gate with `(kill-emacs (process-id gate))', and
`kill-emacs' with an argument does not kill a process — it ends Emacs with
that pid as the exit code, so the code of the check was the pid of the gate
modulo 256, and the check passed or failed by an accident of the pid.  The
repair (kill the tree by pid with SIGKILL) belongs to this wave and not to
the wave that found it: a commit that carries a check which fails in its own
state is a commit that breaks `git bisect'.

### Wave 57 — the check that hangs does not eat the gate

`check-a-tool-that-returns-bytes-does-not-kill-the-harness.el' took 20 462 ms
before the repair and 460 ms after it — forty-four times faster; the base
sweep of the 79 checks on an idle machine took 2 min 19.6 s before it.  The
check of the wave itself runs 5.3 s.  The control took the stop of the timer
away (a `sed' over `scripts/dev-timeout'), and the check failed after 45 s
with its four assertions: `the check that hangs was not stopped (pid 6196)',
`the child of the check that hangs stayed behind (pid 6201)', `the gate did
not finish the run of the check that hangs', `the gate did not say that the
check passed its limit'.  The second control (a fast one) changed the answer
of a stopped command from 3 to 1, and the check failed with `the gate
answered 1 to the check that hangs, the third answer is 3'.

The check of the wave found two defects of itself: the fixture wrote its
report after a twenty-second wait — the gate with a five-second limit killed
it earlier, and the report was never read — and `kill_group' passed its
arguments to `call-process' as a list, while in Emacs 30 the fourth positional
argument of `call-process' is DISPLAY and ARGS come later as separate
strings; the call failed in silence under `condition-case', killing nothing.
One more reason to wait three seconds before the KILL came out on the way:
Emacs defers SIGTERM while it sleeps in `sleep-for', so the stop reaches the
child only through SIGKILL.

### Wave 58 — the pilot leaves no server behind

The orphan server of the pilot had been running for three and a half hours.
The watchdog that guarded it was a loop of `sleep 5' plus a grep over the
log, with `MAX_ATTEMPTS=6' — forty-four minutes of waiting a day, and a
server that waited with it.  The runner of the pilot is now a foreground
process: an interrupted pilot is stopped in 4.1 s, and a pilot at its limit
takes 13.4 s (a limit of ten seconds plus the stop).

The control of the first check (two lines of `signal_pilot') brought the
defect back: the check failed after 19 s with its assertion `the server of
the pilot stayed behind after the pilot was interrupted (pid 5825)'.  The
control of the second (the line of the timer) failed after 45.9 s with three
assertions: the server stayed behind (pid 2442), the runner answered 0
instead of the third answer, the runner did not stop at the limit (pid 2429).
The fast control (exit 3 → exit 0) failed in 13.4 s with one assertion.

The checks of the wave found three defects of themselves.  First: the path of
Emacs that the check gave to the runner was `/proc/self/exe', and that name
means "whoever opens it" — the runner, not Emacs; the runner ran itself and
died with `-Q: invalid option'.  The path is now read once as `(car
(file-attributes "/proc/self/exe"))' and passed as a name.  Second: the
`kill-emacs' of wave 56, described above; now all three checks kill their
tree by pid (SIGKILL) and name the reason.  Third: the socket file of a
server killed by a signal stays on the disk, because Emacs does not clean up
on SIGTERM; the first version of the check demanded that the file be gone,
the assertion was removed, and the reason was written into the objection.

### Wave 59 — a gate run needs no watchdog

`scripts/gate' is the foreground runner of the gate: it starts the run again
when the run was killed, it writes the map at the end whatever happened, and
the codes 0/1/2/3 are the answers of the method while a code of 128 or more
is a kill.  The measurement of the wave is 6.5 s.  Five controls were shown to
bite: A (the gate does not start the killed run again) failed after 3.8 s
with `the killed run was not started again: the run was started 1 time(s)';
B (the gate does not wait for the run) failed in 0.8 s with `the run of the
gate was left behind when the gate answered'; C (the gate does not write the
map) failed in 7.1 s with `the map of the run did not reach the end'; D (the
gate polls through `sleep') failed in 11.7 s with `the gate holds a command
that sleeps'; E (the wrapper holds a gate of its own) failed in 0.3 s with
`the wrapper does not run the one gate of the project'.

Measured separately: a gate killed with SIGKILL two seconds after the start
(the background run of 2026-11-18) left the processes of the run behind —
`bash scripts/gate', `bash live-pilot', `sleep 300' — and they died by
themselves after 63 s, when the limit of the pilot (60 s) expired.  That was
left in the objection and not hidden: fixing it is the work of wave 60.

The check of the wave found a defect of itself: it read the report of the
attempts as a plist and searched it with `assq', and `assq' reads an alist —
on a plist in Emacs 30 it silently returns nil.  The predicate of the wait
was therefore always nil (`the run of the gate never started'), the count was
always zero (`the killed run was not started again: 0 time(s)'), the pid of
the probe was never read, nothing was killed, the pilot fired on its limit
and the gate answered with the third answer.  Checked directly: `(assq :run
'(:run 1 :pid 4210))' → nil; `(memq :run …)' → ok; `(plist-get …)' → 1;
`(car :run)' → wrong-type-argument.  The report of the attempts is an alist
now, the docstring says why, and the check reads the pid of the probe and
kills by that pid.

### Wave 60 — the killed run leaves no copy behind

The copies of the method are named `mathc-v5-<pid>-<n>'
(`adapter/io.ml:18-25`, `adapter/isolated_run.ml`), and `Fun.protect' does
not run in a process that was killed: the copy of a dead run stayed in the
temporary directory for ever.  The measurement of 2026-11-18 found 48 copies,
about a gigabyte, piling up for months.  The sweep of the wave takes only the
copy of a dead run (there is no `/proc/<pid>' for it), a non-numeric pid is
skipped, and the copy of a living run is not touched.  The measurement of the
check is 6.6 s.  Control A (the gate does not call the sweep) failed after
6.5 s with `the copy of the run that was killed stayed behind:
/tmp/mathc-v5-6205-0'; control B (the sweep does not check whether the run
is alive) failed after 6.5 s with `the copy of the living run was removed:
/tmp/mathc-v5-6435-0'.

The check of the wave found four defects of itself.  It started the gate
through `call-process', and `call-process' leaves no process in the
destination buffer: `(get-buffer-process output)' gives nil, and
`process-exit-status' dies with `wrong-type-argument (processp nil)'.  The
working path is `make-process' + `accept-process-output' +
`process-exit-status'.  Second: `process-environment' in Emacs 30 in this
environment is a full snapshot of the environment and not nil; replaced with a
list of its own, it takes PATH away from the child, and the gate dies with
the code 3 (`dirname: command not found', `scripts/gate is missing').  The
environment of the child is built as a base (`process-environment', otherwise
`/proc/self/environ') plus the overridable entries MATHC,
YEAH_FAKE_METHOD_DIR and TMPDIR — the names are cleaned out of the base and
added again; the TMPDIR of the gate is made equal to the TMPDIR of the
check, otherwise the sweep looks elsewhere.  Third: `make-process' has no
`:environment' key — the environment is set by a dynamic `let' around
`make-process' only — and `/proc/self/exe' cannot be given to another
process, one needs `(car (file-attributes "/proc/self/exe"))'.  Fourth: the
report of the failure is printed before the buffer is killed, because after
`kill-buffer' the content cannot be read any more, and `Selecting deleted
buffer' masks the real message.

### The watchdog and the sender of the signal

The watchdog is gone: four scripts were removed (`watchdog-mathc.sh',
`watchdog-selfdev.sh', `watchdog-selfdev-b.sh', `watchdog-selfdev-w42.sh'),
and `yeah-site/artifacts/run-selfdev.sh' now runs through
`scripts/live-pilot' with a limit of 3300 s.  A watchdog that waits is not a
watchdog; the runner that stops the tree itself is one.

Three runs of the method were killed with SIGTERM, and not by the method: the
only kill the method does is a SIGKILL over the group of the verifier
(`adapter/process.ml:60'), and a SIGTERM was never sent by it.  The sender was
outside the method — most likely the timeout of the tool of the agent.  That
is a candidate D10 in `math-coding', and it is not a repair of `yeah'.

**What the measurements do not prove.**  They prove that the six leaks above
are closed on the paths that were measured, and that every one of the six
claims has a control that was shown to bite.  They do not prove that the
provider path never leaks: the live path needs a key of the provider, and the
checks of the live path were not run here.  They do not prove that no other
kind of leak exists — they prove that six kinds were found by measurement and
closed by measurement, and the six kinds were the ones the plan named.

## The after-measurement of the plan of 2026-11-18 (2026-11-18, 17:11–17:12)

The plan of the owner (`math-coding-field-lab/projects/yeah/remediation-plan-2026-11-18.md`)
named the list of what had to be measured again after the repairs: `pgrep -c
emacs`, `uptime`, the copies of the method in `/tmp/mathc-v5-*`, the time of the
sweep and the ticks of the daemon.  The same list, the same units, the same
machine.

| What was measured | Before (2026-11-18, 11:17–11:30 UTC) | After (2026-11-18, 17:11 UTC) |
|---|---|---|
| `pgrep -c emacs` | 42 -- two of them burning a core, forty of them idle servers of checks | 0 |
| load average | 13.42 | 0.90, 0.87, 0.87 |
| copies of the method (`/tmp/mathc-v5-*`) | 48, about a gigabyte | 0 |
| the temporary directory | 3.1 GB | 2.5 GB |
| ticks of the daemon in 10 s | 399--498 ticks -- 80--100 % of a core | no daemon is running, see below |
| the sweep of the gate | 8.5--11.5 min for 121 verifiers at load 13 | 14.3 min for 143 claims at load 0.9 -- 24.0 min of wall clock, of which 9.7 min was one check that the host starved |

**What the after-measurement does not prove.**  It proves that the leaks of the
run are closed on the machine of the measurement: no server of a check is left
alive, no copy of a dead run is left on the disk, and the load of the machine is
the load of an idle machine.  It does not prove that the spin of the daemon of a
live session is gone: the daemon was stopped in step 0 of the plan and was not
started again, because the live session belongs to the owner of the machine, so
the row of the ticks is empty for that reason and not because the defect was
repaired.  The spin of the live path is not localized and not closed; it is an
open defect, and it is written down as one.

The sweep is the gate of 2026-11-18, 17:12--17:36: 143 claims, 241 runs of a
verifier (a baseline for every claim, a control run for every claim that has a
control and passed), `real 23m59.404s`.  Nine and a half minutes of that were
one check that the host starved; without it the sweep took 14.3 min, that is
3.6 s per run against the 4.2--5.8 s per check of the plan.  The reason the run
got cheaper is written down below: the copy that the method makes for every
claim lost seven eighths of its size.

### Wave 61 — the dead controls bite again

Two claims stood in the map as Inconclusive because their negative controls had
stopped touching the subject.  The control of `service-lifecycle` was
`sed -i 's|(yeah-acp-serve-socket %S %s)|(ignore)|' lib/yeah-service.el`, and
the call of the server changed its shape in wave 55 into
`(yeah-acp-serve-socket %S %s nil 'local %S)` (`lib/yeah-service.el:157`), so the
pattern never matched any more.  The control of
`the-check-leaves-no-server-behind` was
`sed -i 's|(let* ((life (or life (yeah-life-inherited-path)))|(let* ((life life)|'
`lib/yeah-acp.el`, and it never matched either: in a basic regular expression
`t*` is a quantifier, so `let*` asked for a space after `le` and the line
`(let* ((life (or life (yeah-life-inherited-path)))` did not match it.  The
method behaved correctly -- reach `nothing` gives Inconclusive, not green -- and
the two properties were untested all the same.  Wave 61 changes only the way
the negative control is applied; the requirement, the falsifier and the check
stay exactly as they were.

Measured in isolated copies of the repository (the method does the same thing:
`adapter/isolated_run.ml` -- clone, `checkout --detach HEAD`, the working tree
over it).  The baseline of `check-a-check-that-is-killed-leaves-no-server.el` was
884 ms, exit 0; the baseline of `check-service-lifecycle.el` was 779 ms, exit 0.
The new control of `the-check-leaves-no-server-behind`
(`sed -i 's|(not (yeah-life-alive-p watch))|nil|g' lib/yeah-acp.el`) took the
notice of the death of the owner out of the server, and the check failed after
20 816 ms, exit 1, with its own assertions: `the server of the check stayed
behind after its owner was killed (pid 4669)' and `the socket of the server
stayed behind: /tmp/yeah-fixtureI3zMpc/server.sock'.  The new control of
`service-lifecycle` (`sed -i 's|(yeah-acp-handle-message line)|nil|g'
lib/yeah-acp.el`) took the answer of the server out, and the check failed after
10 595 ms, exit 1, with `the service did not create a session' and `the service
did not answer the handshake'.

A rejected candidate is written down as well, because a control that bites for
the wrong reason is worse than a control that does not bite:
`sed -i 's|(yeah-life-socket-connect life)|nil|g' lib/yeah-acp.el' bites too
(20 583 ms, exit 1), but it drops the server at the start (`the server of the
check was not alive (pid 6207)') -- the server did not stay behind, it never
rose, and the falsifier of the claim is not proved by that.

The dead anchors were measured literally: the command of the control, taken from
`spec.json` and run through `sh -c` in a copy, returned 0 and changed nothing.
That is reach `nothing`, written down rather than assumed.

### Wave 62 — the uncovered has an owner

The map showed 40 files that no claim owned: five areas of the repository stood
without a master, and not one check stood on their side.  The areas were
`tests/support` (14 files), `tests/live` (5), `tests/pixel` (2), `site` (8) and
`docs` together with `ELISP_BEST_PRACTICES.md` (11).  Wave 62 gave them five
claims and five checks, and after it `mathc map` shows `uncovered: 0 file(s)`.

Four of the five checks written for that volume turned out to be defective, each
in its own way, and each of them quietly: a check that cannot fail is a comment.
The check of the live tests took its "copy" with `copy-file` under the same path
as the source, so the copy was the source itself, and the `delete-file` at the
end of the check erased the live test out of the repository and reported success
besides; the live tests are marked `no-byte-compile: t`, which means they are
read, not compiled.  It was rewritten as
`tests/checks/check-the-live-tests-are-whole-files.el`: it reads every live test
to the end, compares the brackets with `check-parens`, requires a header and a
footer, and writes nothing.  The check of the support fixtures did not parse at
all (two closing brackets were missing), and it loaded the fixtures in the same
Emacs while three of them raise a server and wait for ever, so the check hung
instead of failing.  It was rewritten to load every fixture in a child Emacs,
one child per fixture, with a limit of ten seconds: a hanging fixture gives its
name and its reason instead of silence; the three server fixtures are named and
checked for presence, not for loading, and no process is left after the run.
The check of the version of the site needed `string-match-all', which Emacs 30.2
does not have, so it could not run at all; it was rewritten on a loop of
`string-match'.  The check of the documentation was truncated; it was rewritten
too.

The rewritten checks stood on wrong assumptions about the dialect of Emacs 30.2,
and those assumptions were wrong: the "zero or one" operator is a bare `?'
(`\?' is a literal question mark), `\b' and `\B' are word boundaries, `\<' and
`\>' work, `(?:' is supported, `a{2}' is a literal, `\d' is a literal, a
look-behind is not supported, a regular expression that starts with `"*' never
matches, `string-trim' in Emacs 30 takes regular expressions in its second and
third arguments and calls `string-match' inside, which erases the match data
(`args-out-of-range'), `string-match-all' is absent, `directory-files' has the
prototype `(FULL MATCH NOSORT COUNT)' and not `(NOSORT MATCH-DOTFILES
RETURN-ABSOLUTE)', and `member' compares strings with `eq' and takes no test
function.

The baseline of the check of the documentation was red because of the same kind
of assumption: it built the list of the top level of the repository with the
wrong prototype of `directory-files', so the list held `.', `..' and the hidden
names, and the path of the neighbouring project `../emacs-agents-research' was
taken for a path of this repository.  Four live links of the documentation were
named in the check and were correct: `AGENTS.md:858`, `ELISP_BEST_PRACTICES.md:16`
to `19`, `docs/PASEO-INTEGRATION.md:695` and `docs/PASEO-INTEGRATION.md:889`.
The links were repaired in the documentation and the rule was not weakened.

The five controls were shown to bite, in isolated copies of the repository, with
the commands taken from `spec.json` themselves.  For every one of them the scope
of the claim changed, the code of the control was 0, and the code of the check
after the control was 1:

| Claim | Baseline | After the control | What the check said |
|---|---|---|---|
| `the-support-fixtures-load` | 2448 ms, exit 0 | 2452 ms, exit 1 | `support: the fixture yeah-journal-files.el does not load: Error: invalid-read-syntax (")" 54 1)' |
| `the-live-tests-are-whole-files` | 251 ms, exit 0 | 280 ms, exit 1 | `the live test live-model-call.el has no footer', `has an unmatched parenthesis on line 117', `is empty', `is not a whole file: Invalid read syntax: ")", 117, 1' |
| `the-interface-is-seen` | 5939 ms, exit 0 | 5526 ms, exit 1 | `check-interface-is-seen: the interface does not change the screen: 0 pixels differ' |
| `the-site-shows-the-current-version` | 234 ms, exit 0 | 243 ms, exit 1 | `site: the page shows the version 0.3.1, the project is at 0.3.0' |
| `the-documentation-points-at-files-that-exist` | 814 ms, exit 0 | 910 ms, exit 1 | `docs: PLAN.md: it names docs/there-is-no-such-file.md, and there is no such file' |

The first run of the measurer said `BITES: False` for all five, and that was a
defect of the measurer and not of the checks: `run' returns `(code, ms, out)'
and the unpacking was `(ms, code, out)', so the printed 4/6/5/7/6 were the
milliseconds of the control and not its code.

**What the wave does not prove.**  `uncovered' does not touch the verdict of the
map -- it touches `next' only.  A claim without files is a property without a
subject: it can neither be refuted nor repaired, and the map is silent about it
in the same way it is silent about a property that nobody checks.  Three of the
five checks watch the absence of a defect (a link in the documentation, the
version on the page, the wholeness of a live test), and such a property breaks
at every renaming: that is the price of a property "the tree of the
documentation is whole", and it is written down here instead of being hidden.
The pixel check needs a frame server, a terminal and ImageMagick; where they
are missing the script prints `blocked' and leaves the code 2, that is, not a
Pass -- the method shows such a case as Inconclusive and not as green.

### The stall of 2026-11-18, 17:13–17:23 — a starved host, not a defect of the project

One claim of the map came out of the gate as Inconclusive: `product-installs'.
The trail says it plainly -- `mathc: ./scripts/dev check
tests/checks/check-product-installs.el exited 3', `check: 578922 ms',
`scripts/dev-timeout: the command ran longer than 120s and was stopped', and
`control_reach: null', that is, the control never ran.

The number itself is the evidence.  The check has a limit of 120 s, and the
watchdog of the runner (`scripts/dev-timeout`) stopped it -- but the check had
already been running for 578.9 s: the watchdog of the check fired 459 s late.
A watchdog that is late by eight minutes is not a watchdog that is broken, it is
a watchdog that was not scheduled; and the only thing that keeps a timer
subprocess from running for eight minutes is a host that has no time left.

What the host looked like at 18:12, an hour after the stall: seven and more
processes of another agent (`minimax-code', 290--700 MB of resident memory
each), the daemon of Paseo, 4477 MiB of the 8068 MiB of swap occupied, zram0 at
about 3.9 GB, `kswapd` busy, the load average 2.25, 1.74, 5.40, and
`pid_max = 8192`, so the numbers of the processes are reused quickly.  In
`/tmp`, files of that other agent appeared between 18:06 and 18:07 -- the
middle of the window in which our check was hanging.  The check itself is fast
and always was: ten consecutive runs took 313--482 ms and ended with the code 0,
and in the gate of 15:04 the same claim was green (`product-installs: pass',
`negative control proven', the control run took 409 ms).

Every hypothesis that pointed into the repository was measured and dropped:
with `</dev/null' and with a pipe without an end of file the check is fast; a
shell that refuses to die is stopped in 8 s under a limit of 5 s and a hanging
Emacs is stopped exactly at the limit, so the watchdog works; `(require 'yeah)'
gives 204 features in 0.297 s and no side effect; one full scan of
`/proc/[0-9]*/stat' costs 8 ms at 214 processes, and the recursion of the tree
of the runner makes three such scans, not minutes; the repository is 399
tracked files and 3.4 MB, and the copy of it is 21 MB at worst.

The conclusion is written down as it stands: the 579 s were an external stall of
a shared machine, the check is not slow, and the project is not the cause.
A new wave of code was not started for it, because there is nothing in this
repository to repair.  What the map cannot show is the difference between a
host that is busy and a check that hangs, and that difference is an open item.

### The hygiene of the repository — the copy of the method got smaller

The method makes an isolated copy of the repository for every control it runs
(`adapter/isolated_run.ml`), and the gate of the day ran 98 of those copies.
Before `git gc` the copy carried 2314 loose objects (19.47 MiB) with them, so
the `.git` of the copy was 21 MB and the clone took 97 ms; after `git gc
--quiet` there is not one loose object left, 2527 objects are in a pack, the
`.git` of the copy is 2.7 MB, and five clones in a row took 21, 33, 19, 19 and
18 ms.  The gate writes about 6 GB of copies in that state and about 0.8 GB in
this one.  `git status' did not change and the working tree was not touched:
this is the hygiene of the object store and not a change of the project.

### Wave 63 — the control bites for its own reason

The second full gate of 2026-11-18 (14 min 7 s) gave the map one non-green row —
the judgment of the owner — and every other claim `holds (current)` with
`uncovered: 0 file(s)`.  The log of that gate said something the map did not: the
check of the documentation reported four documents naming `bench/results/*.jsonl`
and `tests/artifacts`, names that are not there.  A green check that reports four
broken names is not a green check, and the map had believed a claim that the
working tree and the isolated copy of the method answered differently about.

**The cause.**  The method runs every control in an isolated copy of the repository
(`adapter/isolated_run.ml` of the method repository).  The copy holds the files of
the repository and nothing else: `git clone --no-hardlinks --no-checkout`, `git
checkout --detach HEAD`, the files of `git ls-files -z --cached --others
--exclude-standard`, and `git add -A -- .`.  `bench/results/` and
`tests/artifacts/` are ignored by `.gitignore`, so they are the output of a run and
not files of the repository, and the copy does not have them.  The check of wave 62
listed the directories of the working tree and took every name that began with a
known thing of the top level to be a path of the repository: in the working tree
`tests/artifacts` is there and the name is true, in the copy it is not there and
the name is a dead end.  The same check, two answers.

**The consequence for the control.**  The control of the claim
`the-documentation-points-at-files-that-exist` appends the name of a file that is
not there to `docs/PLAN.md` and expects the check to fall.  In the copy the check
fell — but it fell on three other names (`tests/artifacts` in `README.md` and
`docs/LIVE-EVIDENCE.md`, `bench/results` in `docs/PLAN-NEXT.md`) and not on the name
the control had put there.  Reach was `subject`, the code after the control was 1,
and the check had bitten for a reason that had nothing to do with the control.  A
control of that kind proves that the check can fail, and nothing more.

**The stand that lied.**  The first measurement of the controls of wave 62 said
`5 of 5 BITES`.  That stand copied the repository with `shutil.copytree` and
`ignore_patterns("tests/artifacts")`, and `fnmatch` compares the basename, so a
pattern with a slash in it never matched: the ignored directories came into the
copy, the base line was green there, and the control bit.  The stand was wrong,
not the checks.  The second stand repeats the recipe of the method word for word
(`git clone --no-hardlinks --no-checkout`, `git checkout --detach HEAD`, the files
of `git ls-files -z --cached --others --exclude-standard` over the checkout, `git
add -A -- .`), and with it four of the five claims of wave 62 bite honestly
(`the-support-fixtures-load`, `the-live-tests-are-whole-files`,
`the-interface-is-seen`, `the-site-shows-the-current-version` — all `BITES: True`),
and the fifth does not bite at all: `BITES: False`, base line exit 1, and the check
falls with the three names that the copy does not have.

**The fix.**  The rule of the check is now: the repository decides what a path of
the repository is.  The files of the repository are the files git knows (`git
ls-files --cached --others --exclude-standard`), the top level of the repository is
built from that list and not from a listing of directories, and an ignored name is
the output of a run and not a path of the repository — git says so (`git
check-ignore`), and such a name is left alone.  Every name is asked about twice,
as it is written and with a slash at the end of it: the rule `tests/artifacts/`
matches only a name that git knows to be a directory, and the directory is not
there in the copy of the method, so the form with the slash is the one that
answers the same way in both places.  The check still has to find at least one
name, or it falls with "no name of the documentation was followed".

**The measurement after the fix.**  Base line exit 0 (497 ms), after the control
exit 1 (620 ms), the scope changed, the code of the control was 0, and the check
fell with its own finding: "docs: PLAN.md: line 3721: it names
docs/there-is-no-such-file.md, and there is no such file".  The working tree: exit
0, 435 ms.  The other four claims of wave 62 keep biting on the same stand:
support 2495 ms exit 0 and 2502 ms exit 1, live 262 ms exit 0 and 247 ms exit 1,
pixel 6006 ms exit 0 and 5363 ms exit 1, site 230 ms exit 0 and 253 ms exit 1.

**Two dialects found on the way.**  `delete-dups` in Emacs 30.2 takes one argument;
the comparison of strings needs `cl-remove-duplicates` with `:test #'string=`.  And
`git check-ignore --stdin` waits for EOF, which `process-send-string` does not
send, so the check hung; the paths are passed as arguments.

### The third gate of 2026-11-18 and the map that came out green

The third full gate of 2026-11-18 (19:04–19:19 UTC) took 14 min 16 s, of which
`user` was 2 min 34 s and `sys` 1 min 6 s: the rest was waiting and not work.
Its exit code was 3 (Inconclusive) and it had exactly one non-green row — the
judgment of the owner, `the-owner-decided-the-order-of-the-next-waves`, whose
materials (`docs/PLAN.md`) had changed in wave 63, so the attestation of the
earlier round had gone stale (`materials-changed`). Every other claim was
`holds (current)` and `uncovered` was 0 file(s).

The owner settled that row the way the method expects of a human:
`mathc record the-owner-decided-the-order-of-the-next-waves owner --by az
--outcome pass`. The map after that record:

    verdict: green, exit 0
    143 claims, 143 holds
    uncovered: []
    next: nothing to do - declared evidence is current and the tree is covered

The order is not a detail. The record binds the materials of the claim, so it
has to come after the last change of `docs/PLAN.md`, and the claim of the
documentation binds the whole `docs` directory, so any documentation written
after a gate makes that claim stale — and the map says so instead of hiding
it. The sequence of this round was: the fix of wave 63, the gate, the record,
and the map that came out green.

**The machine after the round.**  0 `emacs`, load average 0.39, 0 copies of the
method in `/tmp/mathc-v5-*`, `/tmp` 2.1 GB, the root at 72 GB of 99 GB. The
before-measurement of the same day was 42 `emacs`, load 13.42 and 48 copies.

**What this round says about the method.**  A green map of this repository was
green dishonestly once, and the method did not see it (wave 62).  It was seen
by a stand that repeats the recipe of the method word for word, and the fix was
in the check, not in the method.  The question of the owner — whether a claim
whose control bit for another reason may stay green — is still open and is
written down in the list below.

## The journals that the documentation names — wave 64 (2026-11-19, 02:29–02:43)

The sixth gate of this repository ran on 2026-11-19 at 02:29:33 UTC, in a session
of its own, and it came out red.  It was the first full gate after `origin/main`
was merged into `main` (commit `f975b80`, 2026-11-19), and the one claim it
refused to call green was `the-documentation-points-at-files-that-exist`.  The map
said `verdict: red`, 142 claims held, one `refuted`, `uncovered: 0`, `next: the
claim the-documentation-points-at-files-that-exist is refuted`, and the run ended
with `GATE_EXIT=1` after 13m44s.

The check itself took 378 ms and said why:

```
docs: LIVE-EVIDENCE.md: line 930: it names sessions/calc.jsonl, and there is no such file
docs: LIVE-EVIDENCE.md: line 1250: it names sessions/wave41g.jsonl, and there is no such file
docs: LIVE-EVIDENCE.md: line 1251: it names sessions/wave41h.jsonl, and there is no such file
docs: LIVE-EVIDENCE.md: line 1356: it names sessions/wave42-1.jsonl, and there is no such file
docs: PLAN.md: line 3468: it names sessions/wave41g.jsonl, and there is no such file
docs: PLAN.md: line 3468: it names sessions/wave41h.jsonl, and there is no such file
```

Six names on five lines, and every one of them is a journal of a live run.  The
documentation has been naming them since the first live run of this repository,
and for four years the names pointed at nothing.

**Why the check was silent until the merge.**  The rule of the check (wave 63) is
that a name is a path of this repository when its first part is a thing of the top
level of the repository, and the things of the top level are the ones git knows.
Before the merge the directory `sessions/` did not exist in this repository at
all — `origin/main` brought it with commit `d162d3c` — so `sessions/calc.jsonl`
was not a name of this repository, and the rule had no reason to look for it.  The
name pointed into the empty.  The merge brought five journals of the same kind
(`sessions/wave41.jsonl`, `sessions/wave41b.jsonl`, `sessions/wave41c.jsonl`,
`sessions/wave41d.jsonl`, `sessions/wave41e.jsonl` — 5 295 312 bytes), `sessions/`
became a directory of the repository, and from that moment the rule asked what the
documentation had been promising all along: a journal that is named must be in the
repository.

The silence was not the weakness of the check.  The silence was the hiding of the
documentation.

**The journals.**  All four were on the disk of this machine, in the copies on
which the runs had happened, and in no branch of this repository:

| Journal | Bytes | Records | Where it was |
|---|---|---|---|
| `sessions/calc.jsonl` | 91 348 | 118 | `/home/az/Projects/yeah-live-2/sessions/calc.jsonl` |
| `sessions/wave41g.jsonl` | 641 365 | 501 | `/home/az/Projects/yeah-selfdev-1/sessions/wave41g.jsonl` |
| `sessions/wave41h.jsonl` | 665 833 | 578 | `/home/az/Projects/yeah-selfdev-1/sessions/wave41h.jsonl` |
| `sessions/wave42-1.jsonl` | 2 981 451 | 2464 | `/home/az/Projects/yeah-selfdev-2/sessions/wave42-1.jsonl` |

The counts are the ones the documentation gives: line 930 of this file says
«118 records, 91 348 bytes» and line 1356 says «2464 records».  They were compared
before the files were copied, not after, so the journals are the ones that are
described.  A search for the usual shapes of a key (`sk-…`, `api_key=`, `Bearer …`,
`eyJ…`, `AKIA…`) in the four files found nothing.

**What wave 64 did.**  It put the journals where the documentation already put them
and where `origin/main` had put five others: into `sessions/`.  It rewrote no
documentation, because the names of the documentation were right — it was the
documentation that was untrue.  The wave adds no property; it repairs one, the way
wave 63 repaired one.  The file of the wave is `waves/wave-64.json`, and the
section of the plan is `docs/PLAN.md` §16.48.

**The rule is stricter than it looks.**  The first draft of that section named a
journal the short way, with three dots at the end of the path, and the check
answered that it names a path that does not exist.  That was its own reason and not
a defect: three dots are inside the class of characters a name may have, so the
short way is read as a literal path — unlike the star and the question mark, which
the check drops as patterns.  The documentation names the directory `sessions/` and
not the short way.  The finding is worth writing down because it shows the edge of
the rule word for word: a path may not be shortened with dots in this
documentation.

## The live route through the orchestrator — waves 66 and 67 (2026-11-19, 05:10–05:31)

The first live run of the agent through the UI of the orchestrator Paseo died before
a single token was spent.  The command was the obvious one:

```
$ paseo run --provider yeah --cwd /home/az/Projects/yeah \
    --title "Живой маршрут волны 66" "Ответь словом OK и вызови инструмент finish."
Error: Failed to create agent: the MCP server paseo speaks http; Yeah speaks stdio only
```

**The defect was the transport of MCP.**  The orchestrator names its own MCP server
over HTTP — `{type: http, url: http://127.0.0.1:6767/mcp/agents?callerAgentId=…,
headers: [Authorization: Bearer …]}` — and the kernel spoke the stdio transport and
no other (wave 43, part 5).  A session that named such a server was refused by name.
This was not a gap of the list of §3 of the plan of the integration; it was the
reason why no agent of Yeah could run inside Paseo at all, and no check had seen it,
because every check of the kernel speaks the protocol to the kernel itself.

The transport is a property of the agent and not of the plugin, so it was repaired
in the kernel (wave 66, `lib/yeah-mcp-http.el`): a minimal asynchronous HTTP/1.1
client on `make-network-process` that reads the answer of MCP over HTTP as the
stream of the events of MCP over HTTP, that sends the headers `Mcp-Session-Id` and
`MCP-Protocol-Version`, and that closes the socket after the message that carries
an `id`.  The kernel declares it in the handshake: `mcpCapabilities: {http: true,
sse: false}`.

**The route after the repair (05:21:13 UTC).**  The same command, unchanged:

```
$ paseo run --provider yeah --cwd /home/az/Projects/yeah \
    --title "Живой маршрут волны 66" "Ответь словом OK и вызови инструмент finish."
AGENT ID                              STATUS      PROVIDER    CWD                             TITLE
8b5be4a0-5755-4111-b9db-eda721afd716  completed   yeah        /home/az/Projects/yeah          Живой маршрут волны 66

$ paseo logs 8b5be4a0-5755-4111-b9db-eda721afd716
[Message received] Аудит интеграции агента yeah с Paseo
Ответь словом OK и вызови инструмент finish.
[Finish]
OK
```

The journal of the run holds the truth of the route:

| Record | What it says |
|---|---|
| `user-message` | the prompt of the orchestrator, in the shape it sends it |
| `usage` (twice) | the tokens of the run |
| `tool-request` | `finish` with the kind `other` and the named argument `{"summary": "OK"}` |
| `permission-request` / `permission-decision` | the question of the kernel and the answer of the client |
| `tool-end` | the answer of the tool |
| `finish` | the summary `OK` |

Nothing of the route is a stub: the model answered, the tool call carried its
named arguments, the question about the permission went to the client and came
back, and the words of the agent reached the timeline of the orchestrator.

**The journal of the project was full of sessions that never happened.**  The
orchestrator reads the catalog of the models and the modes through a real session:
`discover()` calls `session/new` and never closes the session it opened
(`packages/plugin/src/server/acp-internal/connection.ts`).  The kernel wrote the
file of the session when the session was opened, so every list of the models and
every diagnostic left a file with a single header behind.  The data home of this
machine held 140 files of sessions, and 88 of them held one record each — nothing
but their header.  A live run of 05:21 left two more: one from the discovery of
the models (05:21:03) and one from the probe of the session (05:21:12).

Wave 67 repaired it in the kernel: the file of a session appears when the session
writes its first record, and a probe of the catalog leaves nothing behind.  The
measurement after the repair, same machine, same commands (`paseo provider
diagnostic yeah` and one `paseo run`):

| | Files of sessions | Files with one record |
|---|---|---|
| before | 140 | 88 |
| after the diagnostic and one live run | 141 | 88 |

The one new file is the journal of the live run (14 records), and no file with a
single record was added: the discovery of the models left nothing.  The 88 files of
the earlier behaviour are still there — the journal is append-only and the kernel
does not delete records; they are the business of the person.

## The outcome of a run on the wire of the plugin (2026-11-19, 06:05)

The live route of 05:30 left a `nudge` in the journal of the session
(`session-1-16712a.jsonl`, record 6, 05:30:18) — the model answered "OK", the
kernel told it that words are not a completion, and the model called `finish`.
Wave 65 sends that nudge to the orchestrator as the notification `yeah/outcome`,
and the plugin of the orchestrator turns it into a vendor update.  The route was
measured with the same wire the plugin uses in Paseo (`acpStream`) and with the
same interception of the request `initialize` (`yeahInitializeRequest`): the
kernel was started in the stdio mode with the fake model of the checks, which
only talks and never acts, so the run ends without an effect.

The wire carried:

```
[initialize] {"protocolVersion":1,...,"mcpCapabilities":{"http":true,"sse":false},...}
[session/new] "session-1-5902d1"
[outcome] nudge -> {"type":"notice","notice":{"id":"yeah-nudge-session-1-5902d1","severity":"info","title":"Агент подтолкнут",...}}
[outcome] nudge -> {...}
[outcome] nudge -> {...}
[outcome] unfinished -> {"type":"notice","notice":{"id":"yeah-unfinished-session-1-5902d1","severity":"warning","title":"Прогон закончился без результата","description":"the model described its next step 3 times and the run ended without an effect"}}
```

Three nudges and the run that ended without an effect — the announcement in the
`_meta` of the capabilities of the client, the notification of the kernel and the
translation of the plugin are one path, and it is measured live.

What is not measured: how the notice is drawn in the UI of the orchestrator.
The command line of the orchestrator (`paseo logs`, `get_agent_activity`) does
not show notifications at all — the curator of the activity of Paseo
(`packages/server/src/server/agent/activity-curator.ts`) has no branch for the
type `notification` and skips such an item in silence.  That is a property of
Paseo and not of Yeah; the item of the timeline is of the type `notification`
and the UI draws it.

## The record of the queue that the journal was losing — wave 68 (2026-11-19, 07:40)

A live run through the orchestrator of 19 November 2026, 07:40 UTC
(`b63e68cb-8564-4d1f-b3be-f1791f52ad88`, `completed`) named two MCP servers, and
the journal of its session holds the record of the queued input in full:

```
{"type":"input-queued","id":1,...,"frozen":{"budget":60000,"max-nudges":3,
 "submitted-at":1795072250.679943,"cwd":"/home/az/Projects/yeah",
 "mcp-servers":["paseo","shared-browser"]}}
```

The list of the names of the servers is an array, and the record is not a
stand-in.

Before the repair the same record was lost.  The session of the run of 06:52
(`session-1-530ba2.jsonl`) holds:

```
{"type":"input-queued","id":1,"unserializable":true,
 "note":"the record holds a value that the journal cannot write: input-queued"}
```

Three such stand-ins sat in the journals of the project — one per live run that
named an MCP server.  The cause was not the orchestrator: the frozen
configuration of an ACP session holds the *names* of its servers, the names are
a list, and `json-serialize` in Emacs 30 writes a list as an object or refuses
it.  The record that names the cwd of the session and its servers could not be
written, and the journal replaced it with a stand-in that says only that it
could not be written.

The repair is in the kernel (`lib/yeah-session.el`, `yeah-session--json-value`):
a list is written as an array, the other fields of the record survive, and the
stand-in keeps its scope — a value that JSON cannot hold at all (a symbol, a
cons that is not a list of pairs) is still written as a stand-in, and the
journal still takes the records that follow.

What the repair does not do: it does not rewrite what the journal has already
written.  The three stand-ins of the live runs of 19 November stay where they
are, and the session `session-1-530ba2.jsonl` still holds its stand-in next to
the records of the run that followed it.  The journal is append-only, and the
wave says so in its objection.

## The live runs of the usage of the turn — waves 69 and 70 (2026-11-19)

Two live runs through the orchestrator Paseo were made on the code of the waves 69
and 70.  The first one answered and came to an end:

```
$ paseo run --provider yeah --cwd /home/az/Projects/yeah \
    --title "usage wave 69-70" "Ответь только словом OK и вызови finish. Больше ничего не делай."
AGENT ID                              STATUS      PROVIDER    CWD                             TITLE
22094ccb-8ca1-490a-b8a6-c7f02fb1255e  completed   yeah        /home/az/Projects/yeah          usage wave 69-70
```

The run answered in about eleven seconds and the agent came to `idle`.  The
functional goal is reached: the prompt reaches Yeah through Paseo and the agent
answers.

**`LastUsage` did not appear.**  The usage of the turn now travels in the answer of
`session/prompt` (wave 69), and the orchestrator did not show it.  The cause is
named exactly: the SDK connection of the plugin of the orchestrator
(`@getpaseo/plugin` 0.15.2, `runAcpProvider`) drops the field `usage` from the
answer of `session/prompt`, and there is no hook for that answer at the
`AcpTransformer`.  A separate loss: the translation of `usage_update` into
`session.usage` in the SDK keeps only `contextWindowUsedTokens`,
`contextWindowMaxTokens` and `totalCostUsd`, while `paseo inspect` reads
`inputTokens`, `outputTokens` and `cachedInputTokens`.

**The route was repaired here afterwards (wave 71).**  The repair did not need
the SDK and did not need a change in the orchestrator: the SDK gives every
notification of an unknown method to the transformers of the plugin, together
with the session it belongs to.  So the kernel sends the tokens of the turn as
the notification `yeah/usage` to the clients that asked for them in the `_meta`
of their capabilities, the plugin of this repository announces that method in
the request `initialize` and translates the notification into the event of the
provider `session.usage` — the only event the orchestrator carries into the
counter of the agent.  The live proof is below (docs/PLAN.md §16.57).

The note of the wave (`waves/wave-69.json`) promises that the orchestrator shows
the tokens of the run in `LastUsage`.  The run measured here did not show them.
The contradiction was recorded here and was not resolved silently: the wave
proves the kernel, and the route of the orchestrator is a property of the
orchestrator.  Wave 71 closed it from this side — the tokens now travel by a
path this repository owns — and the promise of wave 69 holds.

**The second live run stuck.**  The run `736efdb` (the title "usage wave 69") went
into a loop of MCP calls — the model called `paseo list agents/hosts` by itself —
and stayed in the state `running`.

**The journal of the live run found a second defect.**  The session of the run
(`session-1-606d27.jsonl`) held two records of the usage of the second request of
the run with the same numbers (13775 in and 528 out), and the first request of
that run — the model that did not think — held one.  The cause is in the
transport of gptel and in the kernel together: the callback is called with
`(cons 'reasoning ...)` and then with the answer, and the same `info` goes to
both.  The kernel wrote the usage of the request for every shape that carried
it, so a model that thinks was paid twice in the journal and the cost of the run
that the orchestrator shows was twice the cost of the run.

Wave 70 writes the usage of a request once: the road to the answer — the
reasoning of the model, the result of a tool that ran and the sentinel of a
stream that is over — is not a second request (`yeah-answer-road-p`,
`lib/yeah-answer.el`).  The check is
`tests/checks/check-the-journal-holds-the-usage-of-a-request-once.el` and the
claim is `the-journal-holds-the-usage-of-a-request-once` (docs/PLAN.md §16.56).

## The live run that shows the usage of the turn — wave 71 (2026-11-19)

The repair of wave 71 was measured by a live run through the orchestrator Paseo.
The plugin was reloaded (`paseo plugin reload yeah-provider`), the run answered
and came to an end as before:

```
$ paseo run --provider yeah --cwd /home/az/Projects/yeah \
    --title "usage wave 71b" "Ответь только словом OK и вызови finish. Больше ничего не делай."
AGENT ID                              STATUS      PROVIDER    CWD                             TITLE
e1cdf9b6-9269-4bea-8602-2ddf1564f482  completed   yeah        /home/az/Projects/yeah          usage wave 71b
```

The counter of the agent is not empty now:

```
$ paseo inspect e1cdf9b6-9269-4bea-8602-2ddf1564f482
Status              idle
LastUsage           InputTokens: 12960, OutputTokens: 99, CachedTokens: 0, CostUsd: $0.00
```

The run before it showed `InputTokens: 0, OutputTokens: 0`.  The first live run
after the repair (`ca3bafe0`, the title "usage wave 71") showed zeros as well,
and the cause was in the order of the orchestrator: the update of the context
(`usage_update`) goes through the lane of the notifications, and the notification
of an unknown method is handled at once — so the size of the window arrived
last and wiped the tokens.  The plugin now completes one part of the usage with
the other instead of replacing it, and the second run shows both.

The check is
`tests/checks/check-the-orchestrator-sees-the-usage-of-the-turn.el`, the claim
is `the-orchestrator-sees-the-usage-of-the-turn` (docs/PLAN.md §16.57).

## The live run of the steering through the orchestrator — wave 73 (2026-11-19, 15:37–15:38)

The live run of the package of waves 72 and 73 went through the real orchestrator
Paseo, and the steering arrived.  The agent was
`31f7a281-710b-4ca2-b24c-bec81a77b2c3`, the provider was
`yeah/MiniMax-M3.1-Flash`, the mode was `plan`, and the placement was the service
one (`serviceMode: service`): Emacs listened on
`/tmp/yeah-1001/yeah-service-paseo.sock` through `yeah-acp-serve-socket`, and the
session of the orchestrator `671e7f82-ca06-4068-bd1f-bdfa38eb4224` spoke to the
session of the kernel `session-19-6b544`.

| Time | What happened |
|---|---|
| 15:37:38 | the turn began (`input-taken`, `input_kind` "ask") |
| 15:38:04 | the request of the orchestrator with `delivery: steer` was intercepted by the plugin and translated into `session/steer` of the kernel, with the session id of the kernel and the text of the clarification; the kernel answered, and the journal of the plugin holds no line of a refusal |
| 15:38:07 | the kernel took the clarification into the running turn: the record `input-taken` with `input_kind` "steering" and the event "steering" with the text of the clarification |
| 15:38:10 | after the clarification the model finished the turn at once with the tool `finish` and answered briefly: "Прочитал README.md, первые 300 строк docs/PLAN.md и AGENTS.md; подсчитал заголовки ### 16.N в docs/PLAN.md поиском по регулярке ^### 16\.[0-9]+: их 58 … Три последних: 16.57 …" |

The turn was neither interrupted nor replaced: its identifier stayed
`acp:eb285023-4851-487b-9692-b47619fa6076`.

Where to look: the journal of the kernel
`~/.local/share/yeah/yeah/projects/<hash>/sessions/session-19-6b544.jsonl` holds
the records `input-queued` (`input_kind` "steering"), `input-taken`
(`input_kind` "steering") and `steering` (the payload is the clarification).

The check of the wave is
`tests/checks/check-the-plugin-steers-the-running-turn.sh`, the claim is
`the-plugin-steers-the-turn-instead-of-replacing-it` (docs/PLAN.md §16.59).

**What the live run did not prove.**

- The clarification reaches the model at the boundary of a batch of tools and not
  between two tools: that is the rule of the kernel itself.
- The queue of delivery of the orchestrator ("delivery after two quiet seconds")
  asks for the clarification to be sent while the turn runs.  In the first run of
  the day the turn lasted 74 s (15:26:22–15:27:36), the clarification was sent at
  15:28:04 — after the end of the turn — and it came as an ordinary question
  (`input_kind` "ask"), not as a steering.
- The profile `plan` asks the person about `git_status`: in the second run of the
  day the turn stood until the person answered the permission.  This is the known
  gap of the profile without a person
  (`docs/PASEO-INTEGRATION-PLAN.md` §3.11).
- The second run of the day died: the OOM-killer of the host killed the kernel
  (SIGKILL) at 15:34:15, after the context of the run had grown past the window
  of the model (103385 tokens with a window of 60000).  The socket of the service
  stayed on the disk, the following attempts to create an agent answered
  "ACP connection closed", and the plugin had to be reloaded by hand before an
  agent could run again.  That is the defect of wave 74
  (`docs/PLAN.md` §16.60); the live run found it and no offline check had seen it.

## The two controls that never bit, and the claim that a loaded host refuted (2026-11-19, 16:03–16:37)

The recalculation of the package of waves 65–74 was run twice on this day, and the
two runs tell two different stories about the registry of the method itself.

**The first run (16:03–16:15) ended with the verdict `unknown`.**  The map could
not compute a verdict because two claims stayed `inconclusive`, and neither of
them was code of the package — both had been registered with a control that
could not bite at all.

- `the-prompt-response-carries-the-usage-of-the-turn` (wave 69) had the control
  `sed -i 's|(when usage (list :usage usage))))))))))|(when usage nil)))))))))' lib/yeah-acp.el`.
  The expression of the `s` command had no closing delimiter: there were two
  pipes and there must be three.  `sed` answered `sed: -e expression #1, char
  67: unterminated 's' command`, the file did not change at all, and the
  evidence held `control_reach: "nothing"`.  The claim was never established:
  its code and its check were right, its registration was not.
- `a-tool-that-returns-bytes-does-not-kill-the-harness` (wave 45) had the
  control `sed -i -e '/yeah-text-valid content/d' -e 's|(json-serialize (yeah-text-value-valid copy))|(json-serialize copy)|' lib/yeah-result.el lib/yeah-session.el`.
  The second part of it did not match the code: the call had been wrapped in
  `yeah-session--json-value`, so the call reads
  `(json-serialize (yeah-session--json-value (yeah-text-value-valid copy)))`.
  The first part did match, so the subject changed (`control_reach: "subject"`)
  and the check still passed: the second reading of the broken bytes was still
  there.  A control that changes the subject and leaves the verifier green is
  not a control.

**The repair.**  Both controls were rewritten to mean what their wave notes say
they mean, and to run at all:

- usage: `sed -i 's|(when usage (list :usage usage))))))))))|(when usage nil)))))))))|' lib/yeah-acp.el`
  — the closing pipe is added.  The parentheses stay balanced (two open and ten
  close in the original, one open and nine close in the replacement), so the
  file still compiles under the control.
- bytes: `sed -i -e '/yeah-text-valid content/d' -e 's|(yeah-text-value-valid copy)|copy|' lib/yeah-result.el lib/yeah-session.el`
  — both readings of the broken bytes are removed.

Both controls were run against a copy of the tree and both bit by the assertion
of their own check: the usage check answered "the answer to the prompt carried
no usage: the client that counts the tokens of a turn had nothing to count" and
"the first prompt of the session: the usage carried the wrong input tokens:
nil is not 1200"; the bytes check answered "the broken byte did not become the
replacement character" and "the journal holds no record of the tool".  The clean
tree ends with the code 0 for both checks.

**The second run (16:23–16:37) ended with the verdict `red`.**  The two claims
above came out `pass` with `negative control proven`, and the map holds 152
claims `holds (current)` and no `inconclusive` claim at all.  But one claim
outside the package was refuted: `the-pilot-that-runs-out-of-time-leaves-no-server-behind`
answered with its own words — "limit: the server of the pilot stayed behind
after the limit passed (pid 7457)" — and the map named its next action: "the
claim the-pilot-that-runs-out-of-time-leaves-no-server-behind is refuted".

**What is known about that refutation.**  The claim had passed 11 times out of 11
before (the evidence of the day runs from 02:42 to 16:14).  The check waits for
the death of the server of the pilot for fifteen seconds — a deadline in wall
time, not a property of the process.  In the run the check took 28.4 seconds
against 13.4 seconds in the ordinary case, and the host was swapping at that
moment: 4.7 GiB of swap in use, zram filled to 3.4 of 3.9 GiB at priority 100.
Outside the run the check passes: two runs in a row (13.4 s) and two runs under
a load of four busy cores (13.8 s), all with the code 0.

**What that does not prove.**  Neither that the property holds nor that it is
broken: the cause is not established.  It may be a teardown that is too slow
under pressure, and it may be a deadline that is too tight for a host that
swaps.  The method does not tell these two apart — it wrote `refuted`.  The
repair of it is a wave of its own (the check must not depend on the speed of
the host), and the order of the waves is a decision of the owner
(docs/PLAN.md §16.62).

## The server of the pilot dies at once, and only its corpse waits — wave 75 (2026-11-19, 18:10–18:25)

The claim that a loaded host refuted was measured before it was repaired, and the
measurement says something the refutation did not.

**What the refutation saw.**  The check waits for the server of the pilot to leave
`/proc` within fifteen seconds of the limit, and under a swapping host it did not
manage: "limit: the server of the pilot stayed behind after the limit passed (pid
7457)".  The claim was written `refuted` and the map went `red`.

**What the process did.**  The server of the pilot was watched in `/proc` from
the moment the pilot reported it (`pilot=4933 server=4946`, a real pilot
through `scripts/live-pilot` with a limit of ten seconds):

```
probe: t=0.0s server state="S" alive=t      <- the server lives with the pilot
probe: t=8.9s server state="S" alive=t
probe: t=9.4s server state="Z" alive=t      <- the limit passed: the process died
probe: t=9.4s server state=nil alive=nil    <- and left /proc at once
```

The death is immediate: the state changes from `S` to `Z` and the entry is gone
within a tenth of a second.  What lingers is not the server but its corpse: a
zombie waits to be reaped by the init of the host, and the init of the host is
not the subject of the claim.  The check counted the corpse as a living server
and waited for the reaping in seconds of wall time.

**What the repair measures.**  The check reads the state of the process and
counts a zombie as dead — it burns no CPU, answers nobody and holds no client.
The fifteen seconds stay the bound of the wait and are no longer the measure of
the death.  The wording of the claim follows the measure.

**The evidence of the repair.**  The check passes on the clean tree (13.3 s) and
under four busy cores (13.7 s), both with the code 0.  The control of the claim
was applied to a copy of the tree and bit by the assertion of the check and not
by a crash: the runner was told not to stop the tree of the pilot, and the check
ended with the code 1 and with its own words — "the server of the pilot was still
alive fifteen seconds after the limit passed (pid 6531, state "S")", "the runner
of the pilot did not stop when the limit passed", "the runner of the pilot
answered 0 when the limit passed, the third answer is 3".

**What this does not prove.**  The host that refuted the claim was swapping with
a full zram, and that host was not reproduced.  The repair does not make the
corpse disappear faster; it stops the measure of the claim from depending on the
reaping, which was never the subject of the claim.

## The mode without a person and the trash of the agent — wave 76 (2026-11-19, 18:05–00:20)

Two decisions of the owner on this day: the mode in which the orchestrator
never asks the person, and the trash in place of the deletion.

**The live route (19 November 2026, 00:14).**  The catalog of the provider
after the plugin was reloaded: `Plan, Build, Auto`.  The run:

```
$ paseo run --provider yeah --mode auto --cwd /home/az/Projects/yeah \
    --title "Живой режим auto: команда без вопроса" \
    "Выполни в терминале команду pwd и напиши ответ словом OK."
```

The journal of the session holds the mode and the decisions:

```
{"type":"session-mode","mode":"auto",...}
{"type":"tool-request","tool":"mcp--paseo--list_hosts",...}
{"type":"permission-request","action":"mcp--paseo--list_hosts",...}
{"type":"permission-decision","action":"mcp--paseo--list_hosts","effect":"allow",
 "reply":":once","reason":"the auto mode allows mcp--paseo--list_hosts without a question",...}
```

The orchestrator was asked **zero** times.  The reason in the record is the
whole of the wave: the mode decides before anybody is asked, because there is
nobody to ask.  The second call of the model (`mcp--paseo--create_terminal`)
was decided the same way.

**What the live run did not finish.**  The model chose the tools of the
orchestrator (the MCP server of Paseo) instead of the `bash` of Yeah, and the
call of `create_terminal` did not answer: the last record of the session is
the usage of the turn of 00:17:16, and the run was still `running` at 00:26.
That is a separate matter -- the tools of the orchestrator over the ACP route --
and this wave does not claim anything about it.  What the live run proves is
narrower and is about the permissions: the session in the mode `auto` decided
both calls itself, and the person was not asked about either.

**The measurement of the trash.**  A file moved into the trash and came back
with its content; a tree moved with what was in it; two files of one name got
two entries (`victim.txt` and `victim.txt.1`); the `rm -rf` of the shell left
the tree in the trash and not on the disk, and the inner file of the tree
came with it.  Without `gio` the shim refuses the removal instead of letting
it through (`rm: command not found`), so the failure of the host is a failure
and not a deletion.

**The measurement of the guard.**  Refused by name, with the reason: `sudo
rm -rf /tmp/x`, `/bin/rm -rf /tmp/x`, `find . -delete`, `shred -u secret`,
`dd if=/dev/zero of=/dev/sda`, `mkfs.ext4 /dev/sdb1`, `git clean -fdx`, the
fork bomb.  Passed through: `rm -rf build` (it goes into the trash), `git
status`, `cargo build --release`, `ls -la`, `make test`.

**What this does not prove.**  The guard is a list of forms and not a
sandbox, and a command that hides its intent is not caught by it.  The
boundary of the agent is the account it runs as and the trash that keeps
what it throws away; the map of what is and is not protected is
`docs/AGENT-SAFETY.md`.

## The package of waves 76 to 79, and one call to a real model (2026-11-20, 13:45–13:52 UTC)
**What was run.**  The four checks of the waves of the package on the tree of
the package, and one call to a real model through the transport of Yeah:
```
check:   2243 ms  tests/checks/check-a-session-may-work-without-a-person.el
check:    922 ms  tests/checks/check-a-run-waits-in-a-state.el
check:    528 ms  tests/checks/check-every-transition-of-the-table-is-taken.el
check:    693 ms  tests/checks/check-a-tool-kind-is-in-the-vocabulary.el
live: status="HTTP/2 200" shape=tool-call calls=3 answer=nil reason=nil
```
The live call is `tests/live/live-model-call.el` with the key of the provider
from the environment file outside the repository; the exit code is 0.
**What this proves.**  The harness of the package still reaches a real model
and the answer of the model comes back: the transport answered with HTTP 200,
and the answer came as a tool call.  That is all: it is one call of one model,
not a run of the agent over a task.
**What it does not prove.**
* The recalculation of the package has not run.  The gate of 20 November 2026
  (09:13–10:04 UTC, `docs/PLAN.md` §16.68) covers the code of wave 77; the
  waves 78 and 79 landed after it, and the map of the package does not exist
  yet.
* The live run through the orchestrator of the package has not happened.  The
  rule is one live run per package (`docs/PLAN.md` §19.1, rule 5), and the
  last live run through the orchestrator was on 19 November 2026 (waves 72
  and 73, above).
* The criteria of readiness of §4.3 of `docs/PASEO-INTEGRATION-PLAN.md` were
  not observed in the interface of Paseo: that needs a live run and a watching
  person.
## The live run of the package of the waves 87 to 89 (2026-11-20, 21:48 UTC)

**What was run.**  One live run through the orchestrator Paseo on the code of the
package, with the short prompt of the rule 5 of `docs/PLAN.md` §19.1:

```
$ paseo run --provider yeah --cwd /home/az/Projects/yeah \
    --title "Живой маршрут пакета 87-89" \
    "Ответь только словом OK и вызови finish. Больше ничего не делай."
AGENT ID                              STATUS      PROVIDER    CWD                             TITLE
c1343063-e35a-4664-815e-bfcc34051241  completed   yeah        /home/az/Projects/yeah          Живой маршрут пакета 87-89
```

The run began at 21:48:27 UTC and came to an end at 21:48:32 UTC — six seconds.
The model was `MiniMax-M3.1-Flash`, the mode was `build`, and the agent came to
`idle` with `LastUsage` `InputTokens: 12924, OutputTokens: 34`.

**What the journal says.**  The journal of the session
(`session-13-31f4b7.jsonl`) holds the whole run:

| Record | What it says |
|---|---|
| `user-message` | the prompt of the run, carried through the wire of the orchestrator |
| `assistant-message` | `I'll respond with OK and finish.` — the model **described** its next step and called no tool |
| `nudge` | the harness asked the model to act and named the tools it had not called |
| `tool-request` | `finish`, kind `other`, named argument `{"summary": "OK"}` |
| `permission-request` / `permission-decision` | the request of the permission and the decision that allowed it |
| `tool-end` | `finish`, `ok: true`, payload `OK` |
| `finish` | the summary `OK` |

**What this proves.**  The route of the orchestrator reaches the model on the code
of the package, and the model **acts** on it: the tool `finish` was called with the
summary `OK`, and the run ended.  The tree of the repository was not changed by the
run (`git status` was empty afterwards).

**The shape of the first answer is measured, not hidden.**  The model answered with
a description of its next step and called no tool, and the harness nudged it once.
That is the known shape of the provider (the claims of the waves 38 and 39: the
nudge carries the state of the work), and the run continued and finished.  The
nudge of this run is recorded in the journal of the session, and it is a fact of
this run and not a defect repaired here.

**What it does not prove.**

* It is one run with a prompt of two sentences, and not a run of the agent over a
  task: nothing was written, nothing was checked, and no code of the repository was
  read by the model.
* It says nothing about the three proofs of the package.  Those are the business of
  the gate of 2026-11-20 21:25–21:41 UTC (`docs/PLAN.md` §16.79, §16.80, §16.81)
  and of the discriminator that follows it.

## The live run of the package of the waves 90 to 92 (2026-11-20, 22:59 UTC)

**What was run.**  One live run through the orchestrator Paseo on the tree of the
package, with the short prompt of the rule 5 of `docs/PLAN.md` §19.1:

```
$ paseo run --provider yeah --cwd /home/az/Projects/yeah \
    --title "Живой маршрут пакета 90-92" \
    "Ответь только словом OK и вызови finish. Больше ничего не делай."
AGENT ID                              STATUS      PROVIDER    CWD                             TITLE
356bb4f2-f568-44b4-99de-dfb5714d6e28  completed   yeah        /home/az/Projects/yeah          Живой маршрут пакета 90-92
```

The run began at 22:59:57 UTC and came to an end at 23:00:01 UTC — four seconds.
The model was `MiniMax-M3.1-Flash`, the mode was `build`, and the agent came to
`idle` with `LastUsage` `InputTokens: 13051, OutputTokens: 136, CachedTokens: 0`.

**What the journal says.**  The journal of the session (`session-15-1a719a.jsonl`)
holds the whole run:

| Record | What it says |
|---|---|
| `user-message` | the prompt of the run, carried through the wire of the orchestrator |
| `usage` | `InputTokens: 13051, OutputTokens: 136` |
| `tool-request` | `finish`, kind `other`, named argument `{"summary": "OK"}` |
| `permission-request` / `permission-decision` | the request of the permission and the decision that allowed it |
| `tool-end` | `finish`, `ok: true`, payload `OK` |
| `finish` | the summary `OK` |

**What this proves.**  The route of the orchestrator reaches the model on the tree
of the package, and the model **acts** on it: the tool `finish` was called with the
summary `OK`, and the run ended.  The tree of the repository was not changed by the
run (`git status` was empty afterwards).

**The shape of the answer is measured, not hidden.**  This run differs from the run
of the package of the waves 87 to 89 in one record: the model answered with **no**
`assistant-message` that described its next step and the harness **nudged it not at
all**.  The model called the tool of the first answer.  The known shape of the
provider (the claims of the waves 38 and 39) is a fact of other runs and not of this
one; what this run shows is that the shape is not obligatory, and that the route
works without it.

**What it does not prove.**

* It is one run with a prompt of two sentences, and not a run of the agent over a
  task: nothing was written, nothing was checked, and no code of the repository was
  read by the model.
* It says nothing about the three proofs of the package.  Those are the business of
  the gate that follows this record and of the discriminator that follows the gate
  (`docs/PLAN.md` §16.82, §16.83, §16.84).
* It says nothing about the tree of the waves themselves: the run was made on the
  tree of the commit `3a3d0fd`, which carries the artifacts of the package and the
  code of the three waves merged before it (`1ecb5e6`, `eb0f9a1`, `ab0d3a9`).

## The live run of the package of the waves 93 to 96 (2026-11-21, 01:47 UTC)

**What was run.**  One live run through the orchestrator Paseo on the tree of the
package, with the short prompt of the rule 5 of `docs/PLAN.md` §19.1:

```
$ paseo run --provider yeah --cwd /home/az/Projects/yeah \
    --title "Живой маршрут пакета 93-96" \
    "Ответь только словом OK и вызови finish. Больше ничего не делай."
AGENT ID                              STATUS      PROVIDER    CWD                             TITLE
f72b0c1b-ecd0-4a1a-b98a-6c2208145d15  completed   yeah        /home/az/Projects/yeah          Живой маршрут пакета 93-96
```

The run began at 01:47:21 UTC and came to an end at 01:47:37 UTC — sixteen seconds.
The model was `MiniMax-M3.1-Flash`, the mode was `build`, and the agent came to
`idle` with `LastUsage` `InputTokens: 13056, OutputTokens: 27, CachedTokens: 0`.

**What the journal says.**  The journal of the session (`session-18-d7142a.jsonl`)
holds the whole run:

| Record | What it says |
|---|---|
| `header` | `session-18-d7142a`, `2026-11-21T01:47:21+0000` |
| `session-model` | `MiniMax-M3.1-Flash` |
| `input-queued` / `input-taken` | the prompt of the run, carried through the wire of the orchestrator |
| `user-message` | the prompt of the run |
| `usage` | `input: 13056, output: 27` |
| `tool-request` | `finish`, kind `other`, named argument `{"summary": "OK"}` |
| `permission-request` / `permission-decision` | the request of the permission and the decision that allowed it |
| `tool-end` | `finish`, `ok: true`, payload `OK` |
| `finish` | the summary `OK` |

**What this proves.**  The route of the orchestrator reaches the model on the tree
of the package, and the model **acts** on it: the tool `finish` was called with the
summary `OK`, and the run ended.  The tree of the repository was not changed by the
run (`git status` was empty afterwards).

**The shape of the answer is measured, not hidden.**  As in the run of the package of
the waves 90 to 92, the journal holds no record of a nudge and no answer that
described a next step: the model called the tool of the first answer.

**What it does not prove.**

* It is one run with a prompt of two sentences, and not a run of the agent over a
  task: nothing was written, nothing was checked, and no code of the repository was
  read by the model.
* It says nothing about the four proofs of the package.  Those are the business of
  the gate that follows this record and of the discriminator that follows the gate
  (`docs/PLAN.md` §16.85, §16.86, §16.87, §16.88).
* It says nothing about the tree of the waves themselves: the run was made on the
  tree of the commit `a274742`, which carries the artifacts of the waves 93 and 96
  and the code of the four waves merged before it (`98b4e2a`, `530105d`, `f364982`,
  `9d3d1ea`).

## The live run of the package of the waves 97 to 99 (2026-11-21, 06:16 UTC)

**What was run.**  One live run through the orchestrator Paseo on the tree of the
package.  The prompt of the packages before it was two words — answer and call
`finish` — and this one is not: the package carries the wave 98, which moved the
rule of the profile onto the declaration of the tool, so the run had to show a
tool that changes the world and the question it caused.

```
$ paseo run --provider yeah --cwd /home/az/Projects/yeah \
    --title "Живой маршрут пакета 97-99" \
    "Вызови инструмент todo_add с текстом «проверка маршрута», затем вызови finish. Больше ничего не делай."
AGENT ID                              STATUS      PROVIDER    CWD                             TITLE
8f289eab-a9b2-4968-b1bc-44a2ca469dc9  idle        yeah        /home/az/Projects/yeah          Живой маршрут пакета 97-99
```

The run began at 06:16:44 UTC and came to an end at 06:17:01 UTC — seventeen
seconds.  The model was `MiniMax-M3.1-Flash`, the mode was `build`, and the
journal of the session is `session-7-ae346d.jsonl`.  The tree of the repository
was not changed by the run (`git status` was empty afterwards), and the tree was
the one of the commit `28b8780`.

**What the journal says.**  The journal holds twenty-seven records, and they
hold the whole run:

| Record | What it says |
|---|---|
| `header` | `session-7-ae346d`, `2026-11-21T06:16:44+0000` |
| `session-model` | `MiniMax-M3.1-Flash` |
| `input-queued` / `input-taken` | the prompt of the run, carried through the wire of the orchestrator |
| `user-message` | the prompt of the run |
| `usage` | `input: 12941, output: 43` |
| `assistant-message` | "I'll add the todo item and finish." — words, and no call |
| `nudge` and `user-message` | the supervision of the run asked for the tools it still needed |
| `usage` | `input: 13902, output: 776` |
| `tool-request` | `todo_add`, named argument `{"text": "проверка маршрута"}` |
| `permission-request` | `todo_add` on `проверка маршрута` |
| `permission-decision` | `defer` — the question waits for the person |
| `permission-decision` | `allow`, reply `:once` — the person answered |
| `todo` | `{"id": "1", "text": "проверка маршрута", "status": "pending"}` |
| `tool-end` | `todo_add`, `ok: true` |
| `permission-request` / `permission-decision` | `read` on `README.md` → `allow`, reason "read is a safe read: it changes nothing" |
| `tool-end` | `read`, `ok: true` |
| `tool-request` | `finish`, named argument `{"summary": "…"}` |
| `permission-request` / `permission-decision` | `finish` → `allow`, without a reason and without a reply |
| `tool-end` | `finish`, `ok: true` |
| `finish` | the summary of the run |

**What it proves.**  The rule asked exactly where the declaration of the tool
says that the tool changes the world.  `todo_add` declares the risk `write`
(`lib/yeah-todo.el:263`); the profile `build` asks for every tool that changes
the world; the question went out over the wire of ACP and waited; the answer of
the person (`allow`, once) let the tool run.  The task was created (id `1`), and
the tool `finish` closed the run with the summary of the model.

The run shows the **second** path as well — the one that answers the tools the
profile does not name.  `read` declares the risk `read` (`lib/yeah-files.el:240`),
and the profile therefore does not ask about it; the answer came from the
hand-written list of the safe reads (`lib/yeah-approval.el:74`), and the decision
says why: "read is a safe read: it changes nothing".  The tool `finish` is asked
about by nobody: the kernel allows that name outright (`lib/yeah-turn.el:386`),
and its decision carries neither a reason nor a reply — the journal shows it.

**The supervision of the run was needed.**  The first answer of the model was
words without a call — "I'll add the todo item and finish." — and the harness
asked it for the tools it still needed (the record `nudge`, which carries the
state of the work).  The model acted after the nudge.  This is the supervision
that became the default in wave 39, and this run is its live proof in the route
of ACP: one nudge out of a budget of three.

**What it does not prove.**

* It is one run, one prompt and one model.  The provider was `MiniMax-M3.1-Flash`,
  and nothing here says that another model asks the same way.
* The mode was `build`.  The run says nothing about the profile `plan`, which
  denies the same tools instead of asking, and nothing about `auto`, which
  allows them.
* The model did **more** than the prompt told it to do: it read `README.md`, and
  the prompt said "Больше ничего не делай".  The run was a short prompt and not
  a task, and the extra call is recorded here as it happened.
* **The residue of the wave 98 is visible in this run.**  The safe-read list is
  written by hand, and it does not follow the declarations: the list holds nine
  names, while the tools that declare the risk `read` are more than nine —
  `todo_list`, `git_status`, `git_diff` and `delegate-result` declare it and are
  not in the list, so they are still asked although they change nothing.  The
  next step of B1 is to make that list follow the declarations; this run does not
  do it and does not pretend to.
* The numbers of the usage are the ones the provider reported, and the last
  request of the run reports `input: 82` — less than the first one
  (`input: 12941`).  The journal holds no record of a compaction, and this run
  does not measure the context of the run: the fact is recorded here, not
  explained.

## The live run of the package of the waves C1, 104 and 105 (2026-11-21, 16:05 UTC)

**What was run.**  One live run through the orchestrator Paseo on the tree of the
package — the commit `ff3c1e1`.  The package carries the wave C1, which gave the
answer of a person the scope of its rule, so the run had to show a question, an
answer that names a scope, and a rule that answers the next call by itself.

```
Вызови инструмент todo_add с текстом «проверка области ответа». Потом вызови
todo_add ещё раз с тем же самым текстом. Потом вызови finish. Больше ничего не делай.
```

The model was `MiniMax-M3.1-Flash`, the mode was `build`, and the journal of the
session is `session-1-ed8a9.jsonl`.  The run began at 16:05:56 UTC and came to an
end at 16:06:55 UTC — fifty-nine seconds.  The tree of the repository was not
changed by the run (`git status` was empty afterwards).

**The question and the answer.**  The first `todo_add` asked the person: the
client received a `session/request_permission` with the three options
`allow-once`, `allow-always` and `reject-once`.  The answer was **Allow always**
(`selectedActionId: "allow-always"`), and the journal holds the decision that the
answer produced:

| Record | What it says |
|---|---|
| `header` | `session-1-ed8a9`, `2026-11-21T16:05:56+0000` |
| `session-model` | `MiniMax-M3.1-Flash` |
| `input-queued` / `input-taken` / `user-message` | the prompt of the run, carried through the wire of the orchestrator |
| `usage` | `input: 12968, output: 42` |
| `assistant-message` | "I'll add the todo items as requested." — words, and no call |
| `nudge` and `user-message` | the supervision of the run asked for the tools it still needed |
| `usage` | `input: 12968, output: 42` |
| `tool-request` | `todo_add`, named argument `{"text": "проверка области ответа"}` |
| `permission-request` | `todo_add` on `проверка области ответа` |
| `permission-decision` | `defer` — the question waits for the person |
| `usage` | `input: 13916, output: 370` |
| `permission-decision` | `allow`, `reply: ":always"`, **`scope: "session"`** — the person answered |
| `todo` | `{"id": "1", "text": "проверка области ответа", "status": "pending"}` |
| `tool-end` | `todo_add`, `ok: true` |
| `usage` | `input: 107, output: 34` |
| `tool-request` | `todo_add` again, the same text |
| `permission-request` | `todo_add` |
| `permission-decision` | `allow`, `reply: ":once"`, `scope: "once"` — **no `defer`**: nobody was asked |
| `todo` | `{"id": "2", "text": "проверка области ответа", "status": "pending"}` |
| `tool-end` | `todo_add`, `ok: true` |
| `usage` | `input: 38, output: 63` |
| `tool-request` | `finish` |
| `permission-request` / `permission-decision` | `finish` → `allow`, without a reason and without a reply |
| `tool-end` | `finish`, `ok: true` |
| `finish` | the summary of the run |

**What it proves.**  The answer of the person carries the scope of the carrier of
its path: the answer came over the wire as a name of an option, the wire name was
read by the one dictionary of the answers (`lib/yeah-acp.el:1110`), the scope of
the answer was named by the scope of the carrier of the session
(`lib/yeah-acp.el:220`, `lib/yeah-approval.el:115`), and the journal holds it —
`reply: ":always"`, `scope: "session"`.  That is the promise of the claim of the
wave C1, measured on a live route.

The second identical call was allowed **without a question**: the record of a
deferral is absent and the decision came in the same second as the request.  The
rule that the answer wrote fired — it lives in the rules of the session
(`lib/yeah-acp.el:1148`) and the answerer asks the client only about what the
rules do not name (`lib/yeah-acp.el:225`).  The task was created twice (the ids
`1` and `2`) and `finish` closed the run with the summary of the model.

**The residue, named and not hidden.**  The decision that came from the rules
carries `reply: ":once"` and `scope: "once"`, and not the scope of the rule that
matched (`session`).  The path that answers from the rules writes an answer that
remembers nothing (`lib/yeah-acp.el:238`), and the scope of that answer is
the scope of this call — the scope of the rule that matched is not read back.
§16.98 named this residue ("nobody reads the scope of the journal back yet"); the
run measures it, and it does not close it.

**The first run of this package measured an old tree, and this is how it was
found.**  The first run (15:49:51–15:51:02 UTC, agent `2346411c`, journal
`session-20-3f22fe.jsonl`) took the whole route — the question, the answer "Allow
always", the tool, the second call allowed by the rules, `finish` — but its
decisions carried the reply `:always` and **no scope at all**.  The cause is not
the model and not the wire: the ACP service of the orchestrator had been started
at **05:34:24 UTC**, while the wave C1 was merged at **13:13:31 UTC**, so the
service held the old tree in memory and the run measured a code that was not the
package.  The evidence is on the disk and independent of the memory of the run:
the socket of the life of the service `/tmp/yeah-1001/yeah-life-paseo-2282.sock`
has the time of its creation **05:34:24 UTC**, and the socket of the service
`/tmp/yeah-1001/yeah-service-paseo.sock` — **16:05:44 UTC**, the restart on the
tree of the package.  The service was therefore started by hand on a unit
(`systemd-run --unit=yeah-acp-service`), because the plugin of the orchestrator
keeps the service in a cache (`plugin/yeah-provider/index.server.ts`) and
`paseo reload` does not drop that cache: after the process dies, the service
stays down until it is raised by hand.

**The rule that follows (the parent, 2026-11-21; a rule outside §17.2, the owner
may cancel it).**  A live run must compare the time the service started with the
time of the commit it claims to measure.  A run that does not say which tree it
measured measures nothing: the route can be perfectly green and be about a tree
that is not there any more.

**What it does not prove.**

* It is one run, one prompt and one model.  Nothing here says that another model
  answers the same way, and the model was `MiniMax-M3.1-Flash`.
* The mode was `build`.  The run says nothing about the profile `plan`, which
  denies the same tools instead of asking, and nothing about `auto`.
* The carrier of the rules was `session`.  The run says nothing about the
  carriers `run` and `global`, and nothing about the scope `project`, which has
  no carrier at all.
* The model did **exactly** what the prompt told it to do — two `todo_add` and
  `finish`, and no other call — so this run says nothing about the extra calls
  of the run of the package of the waves 97 to 99.
* The numbers of the usage are the ones the provider reported.  The last
  request of the run reports `input: 38` — less than the first one
  (`input: 12968`) — and the journal holds no record of a compaction; the fact is
  recorded here, not explained.

## The live run of the package of the waves 106 and 107 (2026-11-21, 16:53 UTC)

**What was run.**  One live run through the orchestrator Paseo on the tree of the
package — the commit `6b6f484` (the artifacts of the package).  The prompt asked
for one word and the tool `finish`:

```
Ответь только словом OK и вызови finish. Больше ничего не делай.
```

The model was `MiniMax-M3.1-Flash`, the mode was `build`, and the journal of the
session is `session-1-29e138.jsonl`.  The run began at 16:53:53 UTC and came to
an end at 16:53:57 UTC — four seconds.  The tree of the repository was not
changed by the run.

**The service measured the tree of the package.**  The service was restarted by
hand before the run, because the plugin of the orchestrator keeps the service in
a cache (`plugin/yeah-provider/index.server.ts`) and `paseo reload` does not
drop that cache.  The unit `yeah-acp-service` started at **16:53:33 UTC**, the
socket `/tmp/yeah-1001/yeah-service-paseo.sock` has the time of its creation
**16:53:34 UTC**, and the last commit of the tree before the run is `6b6f484`
at **16:51:45 UTC**.  The service therefore held the tree of the package and
not an older one — the rule of the run that measured an old tree (§16.102).

**What the journal holds.**

| Record | What it says |
|---|---|
| `header` | `session-1-29e138`, `2026-11-21T16:53:53+0000` |
| `session-model` | `MiniMax-M3.1-Flash` |
| `session-mode` | `build` |
| `input-queued` / `input-taken` / `user-message` | the prompt of the run, carried through the wire of the orchestrator |
| `usage` | `input: 13055, output: 129` |
| `tool-request` | `finish`, named argument `{"summary": "OK"}` |
| `permission-request` | `finish` on `OK`, arguments `["OK"]` |
| `permission-decision` | `allow` — **without a reply and without a scope** |
| `tool-end` | `finish`, `ok: true`, payload `OK` |
| `finish` | the summary of the run, `OK` |

**The decision without a reply is the rule of the kernel and not a defect.**  The
tool `finish` asks nobody: the turn decides it before the answerer is called
(`lib/yeah-turn.el:388`), and the decision carries no reply, no reason and no
scope because there is no answer of a person to carry.  The fields of the
decision are written only when there is something to write
(`lib/yeah-turn.el:573`).  The run of the package of the waves C1, 104 and 105
showed the same shape for its own `finish` call, and this run confirms it on the
tree of this package.  The source is the kernel and not the plugin: the plugin
of the orchestrator has no mention of `permission` at all.

**What it proves.**  The tree of the package loads and works on the real route:
the orchestrator starts a session, the model answers, the tool is called, the
permission of the tool is decided by the kernel, the tool runs and the run ends
with the summary of the model.  Four seconds and twelve records.

**What it does not prove.**

* It proves nothing about the promises of the package.  The claims of the waves
  106 and 107 are about the guards of the tree and the stands that measure the
  claims of the tree; they are measured by their own checks and by their
  controls, and the run of the orchestrator is not one of them.
* **It was run on the tree of the artifacts (`6b6f484`), and not on the tree
  after the two repairs the gate of the package asked for.**  The repairs
  (`da8f6ea` and `6b0f43b`) came after the run, and the run says nothing about
  them.  The gate of the package is what covers the repaired tree.
* It is one run, one prompt and one model.  Nothing here says that another model
  answers the same way, and the model was `MiniMax-M3.1-Flash`.
* The mode was `build`.  The run says nothing about the profile `plan`, which
  denies the same tools instead of asking.
* The prompt asked for one word, and the model called one tool.  The run says
  nothing about the extra calls of the model, and nothing about the stands of the
  wave 107 — a stand is not on the route of a run of the orchestrator.
* The numbers of the usage are the ones the provider reported.

## The gate of the package of the waves 106 and 107 (2026-11-21, 16:58–18:14 UTC)

**Three gates, and the question each of them answered.**  The package was gated
three times.  The logs are `/tmp/w106-107-gate.log`, `/tmp/w106-107-gate2.log`
and `/tmp/w106-107-gate3.log`.

| gate | unit | start (UTC) | exit | form 1 (red) | form 2 (bite) | form 3 |
|---|---|---|---|---|---|---|
| 1 | `yeah-gate-106-107` | 16:58:32 | 1 | **2** | 167 | 0 |
| 2 | `yeah-gate-106-107-b` | 17:34:39 | 3 | 0 | 169 | 0 |
| 3 | `yeah-gate-106-107-c` | 17:56:41 | 3 | 0 | 169 | 0 |

The three forms are the reading of §19.1 п. 7: form 1 is a positive run that
failed (red), form 2 is a negative control that bit (green), form 3 is a
control that was set up wrongly.  Each log holds 169 lines `mathc:` — one per
requirement that has a check and a control.  The one requirement that has
neither is the human judgment of the owner.

**The first gate was red, and it found two defects.**  Both were real and both
were repaired: the picture of the layers named a line of `lib/yeah-risk.el`
that the wave 106 had moved (94 → 90), and the widened guard of the wave 107
walked the installed dependencies of the plugin (74 MB under
`plugin/yeah-provider/node_modules`) and refused three files of a foreign
code.  The promise of the claim was not changed by either repair; the
measurement was narrowed to it.

**The second and the third gate were green by all three forms.**  Both claims
that had fallen now bite: line 4838 of the log is
`check-the-layer-diagram-points-at-files-that-exist`, line 4885 is
`check-a-process-that-is-dead-is-dead-everywhere`.  The controls that did not
run at all in the first gate now run and bite.

**The exit code 3 is the method's `unknown`, and its cause is not in the
code.**  The scale of the method (`scripts/dev`, A13/A14): 0 is green, 1 is
red, 2 is blocked, 3 is `unknown` — the method could not tell.  The reason is
named in the log of the gate itself: the evidence of the claim
`the-owner-decided-the-order-of-the-next-waves` was stale, because the
materials changed — `docs/PLAN.md` was changed by the records of the package.
It is the same subject as §16.68: a claim that waits for a person (the
requirement is `kind: review, spec: owner`) honestly makes the verdict
not-green, and the method distinguishes `pass` from not-`pass` and does not
distinguish "everything is proved" from "everything is proved except the one
point a person decides".

**The order of §16.68 was kept.**  The recount of the package ended at
18:14:13 UTC (`/tmp/w106-107-gate3.exit`), the record of the owner was made at
18:14:35, and the merge into `main` at 18:15:29 — documentation, recount,
record, map.

**The map is green.**  `mathc --root . map` → `verdict: green`,
`uncovered: 0 file(s)`, `next: nothing to do - declared evidence is current
and the tree is covered`; `mathc --root . re-evaluate` →
`{"needs_re_evaluation": []}`.  The merge did not make the evidence stale: the
tree of the merge commit (`ca163860…`) is **bitwise the same** as the tree of
the recount (`9c08266`), and the method measures the materials, not the name
of the commit.

**What this gate does not prove.**  It proves that the checks of the package
pass and that their controls bite.  It says nothing about the promises of the
package beyond what those checks measure, and it says nothing about the live
route — the live run of the package is the section above, and it was made on
the tree of the artifacts, before the two repairs.

## The live run of the package of the waves B2, B3, C2 and C3 (2026-11-22, 08:11 UTC)

**What was run.**  One live run through the orchestrator Paseo on the tree of the
package — the commit `ed84210` (the record of the wave C3).  The prompt asked for
one word and the tool `finish`:

```
Ответь только словом OK и вызови finish. Больше ничего не делай.
```

The model was `MiniMax-M3.1-Flash`, the mode was `build`, and the journal of the
session is `session-1-2b20f6`.  The run began at 08:11:53 UTC and came to an end
at 08:12:21 UTC — twenty-eight seconds.  The tree of the repository was not
changed by the run (`git status` is empty, HEAD is `ed84210`).

**The service measured the tree of the package.**  The service was restarted by
hand before the run, because the plugin of the orchestrator keeps the service in
a cache (`plugin/yeah-provider/index.server.ts`) and `paseo reload` does not drop
that cache.  The unit `yeah-acp-service` started at **08:11:19 UTC**, the socket
`/tmp/yeah-1001/yeah-service-paseo.sock` has the time of its creation
**08:11:20 UTC**, and the last commit of the tree before the run is `ed84210` at
**08:10:06 UTC** (the record of the wave C3).  The service therefore held the tree
of the package and not an older one — the rule of the run that measured an old
tree (§16.102).

**The question of the permission carried the five answers of the wave C3.**  The
question that came to the client over the wire named the tool and offered the
options `allow-once`, `allow-session`, `allow-project`, `allow-global` and
`reject-once`, with the labels «Allow once», «Allow for this session», «Allow
for this project», «Allow always» and «Reject».  Two questions were asked (the
tool `todo_list` and the tool `bash`); the client answered both, and the answer
that came back carried the scope it named.

**What the journal holds.**

| Record | What it says |
|---|---|
| `header` | `session-1-2b20f6`, `2026-11-22T08:11:53+0000` |
| `session-model` | `MiniMax-M3.1-Flash` |
| `session-mode` | `build` |
| `input-queued` / `input-taken` / `user-message` | the prompt of the run, carried through the wire of the orchestrator |
| `usage` | `input: 12950, output: 31` |
| `assistant-message` | «I'll check my task list first, then respond as instructed.» |
| `nudge` / `user-message` | the nudge of the run; the state of the work in it |
| `tool-request` | `todo_list`, args `nil` |
| `permission-request` | `todo_list` on `nil` |
| `permission-decision` | `allow`, **reply `:once`, scope `once`** |
| `tool-end` | `todo_list`, `ok: true`, payload «The task list is empty.» |
| `tool-request` | `bash`, args `("pwd; ls -la" 15 "." 5)` — the named arguments are the command, the timeout, the directory and the idle limit |
| `permission-request` | `bash` on `pwd; ls -la` |
| `permission-decision` | `allow`, **reply `:session`, scope `session`** |
| `tool-end` | `bash`, `ok: true`, payload `/home/az/Projects/yeah` and the listing of the directory |
| `tool-request` / `tool-end` | `read` of `README.md`, `ok: true` |
| `tool-request` | `finish`, named argument `{"summary": "OK"}` |
| `permission-decision` | `allow` — **without a reply and without a scope** |
| `tool-end` | `finish`, `ok: true`, payload `OK` |
| `finish` | the summary of the run, `OK` |

**The scope of the answer is on the wire — this is the promise of the wave C3, measured live.**  The
decision of the answer `once` carries the scope `once`, and the decision of the
answer `session` carries the scope `session`.  Before the wave C3 the decision of
an answer of a person carried a reply `always` and no scope at all, and the
question over the wire offered two answers and a refusal.  The run shows the
five answers of the dictionary of the scopes on the real route, with the scope
that each answer names.

**The rule of the answer `session` stayed in the memory of the session.**  The
answer `session` was given on the ACP path, whose carrier is the memory of the
session; after the run **no file of rules exists** — neither
`~/.config/yeah/rules.json` nor `.yeah/rules.json` of the project.  This is the
carrier of the wave C2 measured on the real route: the scope of an answer says
where the rule lives, and the rule of the answer `session` on this path lives in
the memory of the session and not on the disk of the person.

**The decision without a reply is the rule of the kernel and not a defect.**  The
tool `finish` asks nobody: the turn decides it before the answerer is called, and
the decision carries no reply, no reason and no scope because there is no answer
of a person to carry.  The run of the package of the waves 106 and 107 showed the
same shape, and this run confirms it on the tree of this package.

**What it proves.**

* The tree of the package loads and works on the real route: the orchestrator
  starts a session, the model answers, the tools are called, the permission of a
  tool is decided by the kernel, the tools run and the run ends with the summary
  of the model.
* The wave C3 is on the road: the question over the wire carries the five
  answers of the dictionary of the scopes, and the answer that comes back carries
  the scope it named.
* The wave C2 is on the road: the rule of the answer `session` landed in the
  carrier of the path that asks and left no file on the disk of the person.

**What it does not prove.**

* It proves nothing about the promises of the package as a whole.  The claims of
  the waves B2, B3, C2 and C3 are measured by their own checks and by their
  controls; the run of the orchestrator is not one of them.  The gate of the
  package is what covers the tree as a whole.
* **The run asked a person three times and the person answered by hand.**  The
  answers were `allow-once` (the tool `todo_list`) and `allow-session` (the tool
  `bash`), and the decision of `read` was taken by the kernel itself, because a
  read is a safe read.  The run shows the *route* of an answer; it does not show
  what a person does with the five options in front of them.
* The model did more than the prompt told it to do: it called `todo_list`, then
  `bash`, then `read`, and answered «OK» before the `finish`.  The run says
  nothing about the extra calls of the model.
* It is one run, one prompt and one model, and the mode was `build`.  The run
  says nothing about the profile `plan`, which denies the same tools instead of
  asking.
* The numbers of the usage are the ones the provider reported.


## The live run that found the defect of the refusal (2026-11-22, 10:20 UTC)

**What was run.**  One live run through the orchestrator Paseo on the tree of the
package after the merge of the repairs of the discriminator — the commit
`43a68e9` of 10:18:01 UTC.  The prompt asked for the list of the tasks, for
`pwd` in `bash`, and then for `finish`:

```
Вызови инструмент todo_list, затем выполни bash с командой pwd, затем вызови finish с ответом OK. Больше ничего не делай.
```

The model was `MiniMax-M3.1-Flash`, the mode was `build`.  **The service measured
the tree of the package:** the instance that served the run was started at
**10:19:03 UTC**, the merge of the repairs is at 10:18:01 UTC, and the socket
`/tmp/yeah-1001/yeah-service-paseo.sock` was created by that instance — the
rule of the run that measured an old tree (§16.102) is kept.

**The run hung, and it hung for a reason that the gate had not seen.**  The
journal of the session is `session-2-181cb` (60 records), and it holds this:

| Time (UTC) | Record | What it says |
|---|---|---|
| 10:20:50 | `header` | the session begins |
| 10:20:54 | `tool-request` | `bash`, args `("pwd" 30 "." 10000)` — the command, the timeout of 30, the directory and **the idle limit of 10 000** |
| 10:20:54 | `permission-request` / `permission-decision` | the question of the tool `bash` |
| 10:21:16 | `permission-decision` | the person answered: **reply `:once`, scope `once`** |
| 10:22:54 | `tool-end` | `bash`, `ok: false`, payload «Error: the call of "bash" exceeded its timeout of 120 seconds» |
| 10:22:58 | `tool-request` | `bash`, args `("pwd" 30 "/" 10000)` — the same impossible call |
| 10:24:58 | `tool-end` | the same payload |
| 10:25:03 | `tool-request` | `bash`, args `("pwd" 60 "/tmp" 5000)` |
| 10:27:03 | `tool-end` | the same payload |
| 10:27:07 | `tool-request` | `bash`, args `("pwd" 20 "/home" 5000)` |
| 10:29:07 | `tool-end` | the same payload |
| 10:29:24 | `tool-end` | `git_status`, `ok: true` — the tree, with the two files of the repair still uncommitted |

**The refusal by name never reached the model.**  The tool `bash` declares the
timeout of **120** seconds, and the model asked for the idle of 10 000 — the
refusal of the registry is the promise of the wave B3, and it names the tool and
the bound.  The model read something else: «the call of "bash" exceeded its
timeout of 120 seconds».  That message is the timer of the scheduler, and it
arrived at **10:22:54** — 120 seconds after the request and **98 seconds after
the person had already answered**.  The model asked again with the same
arguments, four times, and every time it read the same message.  The run burned
**eight minutes and thirty-nine seconds** (10:20:50 → 10:29:29) and ended
without a `finish`: the instance of the service was stopped at 10:29:50.

**The dropped call is the promise of the wave 30, and it held.**  The model asked
for `todo_list` while `bash` was running; the journal holds `tool-dropped` with
the reason «the same call is already running» — the repeated call was refused by
name, and the refusal named its subject.

**What it proves.**  The promise of the wave B3 — «a call that does not fit the
declaration of the tool is refused by name» — was **not kept on the path where a
person is asked**, and the model cannot learn from a refusal it never sees: it
repeated the same impossible call five times.  **The gate did not see it**
because the check of the limits measured the path where the rule of the
permissions decides alone; the path where a person is asked was covered by
nothing.

**What it does not prove.**  It proves nothing about the promises of the package
as a whole.  The claims of the waves B2, B3, C2 and C3 are measured by their own
checks and by their controls; the run of the orchestrator is not one of them.

## The live run after the repair (2026-11-22, 10:30 UTC)

**What was run.**  The same prompt, on the tree that carries the repair of the
defect above: the guard of the deferred dispatch
(`lib/yeah-turn.el`, `yeah-turn--dispatch-guarded`) and the ninth probe of the
check of the limits.  **The instance of the service was restarted by hand at
10:29:51 UTC**, and the commit that carries the repair (`45b5606`) was made at
**10:31:58 UTC** — after the run.  The run therefore measured the **working
tree**, and not the commit; that the instance held the repaired code is proved
by what the model read, and not by the name of a commit.

**The refusal by name reached the model, and the model acted on it.**  The
journal of the session is `session-1-f4a370` (40 records):

| Time (UTC) | Record | What it says |
|---|---|---|
| 10:30:49 | `header` | the session begins |
| 10:30:53 | `tool-request` | `bash`, args `("pwd" 30 "." 5000)` — the same impossible idle |
| 10:31:04 | `permission-decision` | the person answered: **reply `:once`, scope `once`** |
| 10:31:06 | `tool-end` | `bash`, `ok: false`, payload «Error: yeah-tools-call: "bash": the idle of 5000 seconds is more than the timeout of 120 seconds the tool declares» |
| 10:31:06 | `tool-request` | `bash`, args `("pwd && ls -la" 20 "." 5000)` — the same idle, once more |
| 10:31:54 | `tool-end` | the same refusal by name |
| 10:31:57 | `tool-request` | `bash`, args `("pwd" 120 "." 10)` — **the model corrected the call**: the idle of 10 and the timeout of 120 |
| 10:32:10 | `tool-end` | `bash`, `ok: true`, payload `/home/az/Projects/yeah` |
| 10:32:13 | `tool-end` / `finish` | `finish`, `ok: true`, and the summary of the task |

**The measure is the time.**  The refusal by name arrived at 10:31:06 —
**13 seconds** after the request and **two seconds** after the answer of the
person.  The run before it read the message of the timer of the scheduler 98
seconds after the answer of the person; the two runs differ by the kernel and
not by the model: the model is the same, the prompt is the same, and the model
repeats the impossible call only while the kernel refuses it with the wrong
reason.

**What it proves.**  The repair holds on the real route: the refusal of the
registry settles the deferred call with the same refusal by name that the path
without a person gives, and the model **corrected the call instead of repeating
it** — the run ended through `finish` at 10:32:13, twenty-four seconds after the
session began.

**What it does not prove.**  It proves nothing about the promises of the package
as a whole — the claims are measured by their own checks and by their controls,
and the gate of the package is what covers the tree as a whole.

## The gate of the package of the waves D3, D4, E1, E2 and E3 (2026-11-22, 15:56-17:52 UTC)

**Four gates, and the question each of them answered.**  The package was gated
four times.  The logs are `/tmp/w-d3d4e-gate.log`, `/tmp/w-d3d4e-gate2.log`,
`/tmp/w-d3d4e-gate3.log` and `/tmp/w-d3d4e-gate4.log`.

| gate | unit | window (UTC) | exit | form 1 (red) | form 2 (bite) | form 3 |
|---|---|---|---|---|---|---|
| 1 | `yeah-gate-d3d4e` | 15:56:15-16:14:23 | 1 | **1** | 181 | 0 |
| -- | `yeah-gate-d3d4e-2` | 16:40:52-16:43:44 | stopped (TERM) | -- | -- | -- |
| 2 | `yeah-gate-d3d4e-3` | 16:50:12-17:07:28 | 1 | **1** | 181 | 0 |
| 3 | `yeah-gate-d3d4e-4` | 17:30:21-17:48:19 | 3 | 0 | 182 | 0 |

The three forms are the reading of §19.1 п. 7: form 1 is a positive run that
failed (red), form 2 is a negative control that bit (green), form 3 is a
control that was set up wrongly.  Each log holds 182 lines `mathc:` -- one
per requirement that has a check and a control.

The run between the second and the third gate was **stopped on the third
minute on purpose**: the order of §16.68 asks for the finding to be written
into the documents before the recount, or the evidence of the claims of the
documentation goes stale and the map turns red for a real reason.

**Both red marks were of the family of the gate, and not of this package.**
The first lay on the claim `a-gate-run-needs-no-watchdog` (wave 59): the gate
restarted the run that was killed, answered 0 and wrote no map.  The journal of
the method proves it a flake and not a verdict: 60 entries on that claim, 58
pass and 2 fail -- 2026-11-22 08:28:39 on the tree `5bb88173` and 2026-11-22
16:10:45 on the tree `657451c`.  The second lay on the claim
`the-gate-stops-a-check-that-hangs`: the buffer of the check held the first
line of the output of the inner run and not its tail.  The mechanism follows
from the refusal itself: the inner run answered 3, the code 3 comes in the
branch `check` of `scripts/dev` from one line only, and that line prints
exactly the sentence the check did not find -- so the sentence was written into
the pipe of the check and had not reached its buffer yet.  **The defect is in
the read of the check**: it waits for the death of the process and reads the
buffer, and it does not wait for the pipe to empty.  The journal holds 62
entries on that claim, 61 pass and 1 fail -- the first refusal of that claim
in the history of the journal.  Both defects are the next wave; the cause of
the flake of the wave 59 is still not established and is not named.  The
findings are written down in `docs/PLAN.md` §16.115 and §16.116.

**The promises of the package held in every gate.**  The map of the third gate
says `the-site-shows-the-diagrams-of-the-architecture holds (current)` and
`the-diagram-on-the-site-is-current holds (current)`, and `uncovered: 0
file(s)`.

**The exit code 3 of the third gate is the voice of a person, not a red
mark.**  The gate finished all 182 requirements: form 1 is zero, form 2 is
182 bites, form 3 is zero.  The map said `verdict: unknown` and named the
reason itself: "the evidence of the-owner-decided-the-order-of-the-next-waves
is stale (materials-changed)" -- the materials of that claim (`docs/PLAN.md`
and `docs/ARCHITECTURE-CATCHUP-PLAN.md`) changed, because §16.115 and §16.116
are the records of the package.  The requirement of that claim is `kind:
review, spec: owner`, and the method does not distinguish "everything is
proved" from "everything is proved except the one point a person decides".
The record of the owner was made at 17:52:26 UTC: `mathc --root . record
the-owner-decided-the-order-of-the-next-waves owner --by az --outcome pass`,
and the map answered `verdict: green`, `uncovered: 0 file(s)`, `next: nothing
to do - declared evidence is current and the tree is covered`.

**What this gate does not prove.**  It proves that the checks of the package
pass and that their controls bite.  It says nothing about the promises of the
package beyond what those checks measure, and it says nothing about the live
route: the package of the waves D3, D4, E1, E2 and E3 was measured offline.

## What is still open

- A control that bites for the wrong reason is green for the method.  The
  control of the claim `the-documentation-points-at-files-that-exist` fell on three
  names that had nothing to do with the control, and the map held the claim as
  green (wave 62, 2026-11-18).  The method asks for `reach = subject` and for the
  code of the check after the control, and both were there; it does not ask
  whether the check fell on the thing the control touched.  Wave 63 fixed the
  check, not the method, and the question of the owner is whether the method
  should tell the two apart.
- The spin of the daemon of a live session is neither localized nor closed.
  The measurement of 2026-11-18 (399–498 ticks in ten seconds, 80–100 % of a
  core) was taken on the code of that day; the waves 55–61 closed leaks, not
  that loop.  The daemon was stopped in step 0 of the plan of the owner and was
  not started again — the live session belongs to the owner of the machine — so
  the row of the after-measurement is empty for that reason and not because the
  defect was repaired.  The counter that would name the loop (the iterations of
  the pump of the wire and of the request of the provider) is still not in the
  code, and the claim `the-server-does-not-spin-when-the-provider-is-silent`
  covers the synthetic scenarios and not the live path of the plugin.
- The negative control of a claim is a line of code, and it dies at every
  renaming: waves 55, 56 and 61 measured that on live code.  The call of the
  server changed its shape in wave 55 and the pattern of the `sed` never
  matched, because `t*` in a basic regular expression is a quantifier.  A dead
  control is not worse than a missing one — the method says Inconclusive and not
  green — but the property it was meant to test is untested all the same, and
  the map says exactly that instead of hiding it.
- A verdict of the map cannot tell a busy host from a hanging check.  On
  2026-11-18, 17:13–17:23, the check `product-installs` ran 578.9 s instead of
  0.4 s and even its own watchdog of 120 s fired 459 s late, because another
  agent was filling the memory of the same host; the cause was outside the
  repository and the check is green in ten runs out of ten.  Nothing in the
  runner tells a starved host from a stuck check, so a map of a shared machine
  carries a verdict that depends on the neighbours of that machine.  The way out
  is a claim about the load of the host, not a faster check.
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
- A message that reports a finished work **and** announces the next step is a
  plan in part, and the harness does not see that part.  The live coding run of
  2026-11-17 ended with "All 15 tests pass.  Verifying the CLI end-to-end from
  a shell:" — an announcement of a verification that never happened — and the
  regexp of the plan (`yeah-turn-plan-regexp`) knows no such opening, so the
  run was completed.  The task was already done there; a task whose last step
  is the announced one would end as a completed run with the step missing.
- A run that ends on a text answer is a completed run even when the task asked
  for the tool `finish`: the live coding run of 2026-11-17 was told to finish
  through `finish` and never called it.  The state of a run is not a proof
  that the instructions of the task were followed; the check of the task is
  the arbiter.
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
- The silence of the provider after a batch of tool results is the noise of the
  provider and not the refusal of the model, and since wave 46 it does not spend
  the budget of the nudges of a run whose model has acted.  The run of the wave
  41 of 15:45–15:53 is the live proof of the defect, and the two runs of the
  wave 41 of 16:15–16:48 on the code of wave 46 are the live proof of the
  repair: both of them were still alive after a hundred calls of tools, with
  the budget of the nudges untouched, and both of them ended when the
  transport to the provider died.
- The transcript of a run is a projection of the journal and not a second copy
  of the run, and it is put in front of every request of the run since wave
  47.  What it is not is a context: it is cut at twelve records of the run, and
  the result of a tool is cut at six hundred characters, so a long run pays for
  the tail of its own work in every request.  The projection of the context
  (`lib/yeah-context.el`) is the machinery that is meant to answer this, and it
  is still not on the road to the model.
- The budget of the nudges is no longer a bound on the length of a run: it pays
  for the nudges that no effect answered, and a model that acts and then says
  nothing is not charged for the silence.  The deadline of the run and the
  deadline of the request still bound it.
- A live run can measure a tree that is not the repository.  The ACP service of
  the orchestrator is long-lived: it holds the code it was started with in
  memory, and the plugin keeps the service in a cache that `paseo reload` does
  not drop.  The first run of the package of the waves C1, 104 and 105
  (15:49 UTC) measured the code of 05:34 UTC -- the wave C1 was merged at
  13:13 UTC -- and its decisions carried no scope at all, because the tree it
  ran was the tree before the wave.  The route was green and the run was about
  nothing.  The rule of the parent of 2026-11-21 asks a live run to compare the
  time the service started with the time of the commit, and the socket of the
  life of the service on the disk says when that instance started; but nothing in
  the harness says it, and the plugin still starts the service once and keeps
  it.
- A process in the state `T' (stopped by a signal) or `D' (uninterruptible
  sleep) is alive, and `yeah-proc-alive-p` (`lib/yeah-proc.el:80-98`) calls it
  dead: it holds a process dead when the letter of its state is anything but `S'
  and `R'.  The hypothesis came from the discriminator of the package of the
  waves B2, B3, C2 and C3 (2026-11-22) and was **not measured**: 1856 polls of
  the live map showed only the states `S', `R' and nothing.  The code was not
  touched, and the question is the owner's.
- A branch of refusal that never fires is a check that cannot fail.  The helper
  `yeah-check--places' of `tests/checks/check-a-scope-decides-where-the-rule-lives.el'
  puts its refusals into the list it is given, and the list is lexical: the
  refusals of the helper do not reach the caller, and the branch "the file
  cannot be read" of that check stays silent.  It was reported by the writer of
  the repairs of 2026-11-22 and was not repaired: a change of a foreign check
  without a measurement is a risk.  The new helper of the repair returns its
  refusals instead of putting them into a foreign list.
