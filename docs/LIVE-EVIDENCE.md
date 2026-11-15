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
| `tests/live/live-model-call.el` | a real model answers through `yeah-gptel-request` — the one place where Yeah calls the model | provider key | `emacs -Q --batch -L lib -l tests/live/live-model-call.el` | 2026-11-15 17:03 UTC, on the code of waves 30+31, with MiniMax-M2.7: `status="HTTP/2 200" answer="OK"` |
| `tests/live/live-coding-task.el` | the harness fixes a small broken project with its own tools (read, edit, run), and the project's test passes afterwards | provider key | `emacs -Q --batch -L lib -l tests/live/live-coding-task.el` | 2026-11-15 17:03 UTC, on the code of waves 30+31, with MiniMax-M2.7 — pass: the run ended `completed` and the test of the project passes afterwards |
| `tests/live/live-interactive-path.el` | the interactive product path against a live provider: open a session, ask, cancel, quit, restart, recover the pending input | provider key | `emacs -Q --batch -L lib -l tests/live/live-interactive-path.el` | 2026-11-15 17:03 UTC, on the code of waves 30+31, with MiniMax-M2.7 — pass ("the interactive path works"); the model answered with an empty message four times and the run ended `unfinished`, and the journey itself — ask, cancel, quit, restart, recover — held |
| `tests/live/live-service-path.el` | the primary deployment against a live provider: a clean service Emacs, a file asked over ACP, the write approved through `session/request_permission`, the file appears | provider key, network | `emacs -Q --batch -L lib -l tests/live/live-service-path.el` | 2026-11-15 17:03 UTC, on the code of waves 30+31, with MiniMax-M2.7 — pass ("the primary path works with a live model") |
| `tests/live/live-fixed-point.el` | the fixed point: a child of Yeah repairs a Yeah canary and the canary passes afterwards | provider key | `emacs -Q --batch -L lib -l tests/live/live-fixed-point.el` | 2026-11-15 17:04 UTC, on the code of waves 30+31, with MiniMax-M2.7 — pass, one child: "the child repaired the canary"; the child's last run ended `unfinished` (empty answers), and the canary was repaired before that |
| `tests/live/live-clean-install.el` | the published repository installs into a clean Emacs: the documented bootstrap runs in a throwaway HOME, the installed package loads, and `yeah`, `yeah-ask` and `yeah-doctor` are bound | network | `emacs -Q --batch -L lib -l tests/live/live-clean-install.el` | 2026-11-15 17:04 UTC, against the published repository, on the code of waves 30+31 — pass: "the clean installation works" (this is what closed the public alpha gate) |
| `tests/pixel/check-interface-is-seen.sh` | the interface is really on the screen: Emacs itself draws the journal and the approval view under a frame server, the screen is photographed, and the pictures are compared with each other and with the same buffer without the interface | a frame server (Xvfb), a terminal emulator, ImageMagick, Emacs — **no provider key** | `YEAH_XVFB=… YEAH_XTERM=… YEAH_MAGICK=… ./scripts/dev pixel` | 2026-11-15, pass — "the interface is on the screen: 767 colours, 16953 pixels between the journal and the approval view" |
| `bench/run-bench.el` | the parity with another harness is measured rather than claimed: the same task, the same workspace and the same model are given to Yeah and to the second harness, and the outcome of both is recorded | provider key, a second harness | `YEAH_BENCH_TASKS=… ./scripts/dev bench --run` | 2026-11-15 17:06 UTC, on the code of waves 30+31, with MiniMax-M2.7 and pi: Yeah passed 1 of 3 tasks, pi passed 2 of 3 — **not a verdict about parity**; all three runs of Yeah ended `unfinished` (the provider answered with an empty message), and the pilot found a defect of the token of the file (see "The pilot that measured the copy of the version token") |

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

## What is still open

- A real editor (an agent-shell, or a person's Emacs) against a live
  provider: not yet checked.
- The bridge to the buffers of an attached Emacs against a person's Emacs in
  day-to-day use: the live daemon is checked, the daily use is not.
- The picture of the interface is compared with itself and with the same
  buffer without the interface, not with a stored golden picture.
- The parity with other harnesses is measured on three tasks only.  The
  threshold is not decided (`docs/PLAN.md` §13) and the sample is small, so
  the parity of the last run is not measured either.  The difference the last
  run found was a defect of the token of the file (the section above), not a
  difference of quality: both harnesses failed `fix-failing-test`, and the two
  tasks that Yeah failed ended `unfinished` because the provider went silent.
- The token of the file was 64 characters of hex and the model copied 58 of
  them, so the guard refused the edit of a file that had not changed.  Wave 32
  shortens the token and makes the refusal name the token instead of the
  file; the next pilot will say how much of the difference that explains.
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
