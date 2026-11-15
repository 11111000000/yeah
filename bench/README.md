# The benchmark of Yeah

This directory holds the measurement apparatus of `docs/PLAN.md` §16.7: a task
set of ten tasks of the kind a person actually asks an agent for, and a runner
that gives the same tasks to Yeah and to any other harness, and writes down
what happened.

It is development-only infrastructure.  Nothing under `lib/` requires it, the
package does not ship it, and no existing test depends on it.  It never
changes the behaviour of Yeah.

## What is here

| Path | What it is |
|---|---|
| `manifest.el` | the task set: the single place the runner reads the tasks from |
| `run-bench.el` | the runner: the self-check and the measurement |
| `tasks/<id>/task.md` | the title, the exact prompt, and what "done" means |
| `tasks/<id>/setup/` | the files copied into the workspace before the run |
| `tasks/<id>/check.sh` | the command that judges the task, run in the workspace |
| `results/` | the result files of the runs (not in git) |

The task set covers ten kinds of work: reading a file and answering, fixing a
failing test, writing a new file, changing existing behaviour, running a
command and reporting it, refactoring with callers, diagnosing a failure,
writing documentation, using Emacs introspection, and a multi-step
implementation with tests.

## How to run it

```sh
./scripts/dev bench          # the self-check: no model, no credentials, no network
./scripts/dev bench --run    # the measurement: needs credentials, or a comparable harness
```

The same thing without the wrapper:

```sh
emacs -Q --batch -L lib -l bench/run-bench.el -- --self-check
emacs -Q --batch -L lib -l bench/run-bench.el -- --run
```

The self-check proves two halves, without any model, without credentials and
without a network:

1. **The task set is measurable.**  Every task exists, has a non-empty
   prompt, has an executable `check.sh`, and that check **fails on an
   untouched workspace**.  A check that passes before the work is a rubber
   stamp, and the self-check says so and fails.
2. **The runner is honest.**  The self-check runs the Yeah harness path with
   no provider credentials — it removes `YEAH_TEST_KEY` for the run, whatever
   the machine holds — writes the records to a scratch directory under the
   temporary directory (never to `results/`), and reads them back.  Every
   task must be recorded as `skipped` with the reason `no provider`, and **no
   task may be recorded as `passed`**: a harness that could not run is never
   a pass, and never a failure of the agent either.  If the runner recorded
   a pass for a harness that did not run, the self-check says so and fails.

The measurement gives every task to every configured harness.  For each task
the runner creates a fresh temporary workspace, copies `setup/` into it, hands
the task to the harness, and then runs the task's `check.sh` in that
workspace.  The check decides the outcome; the runner never decides it.

The prompt of a task holds the literal text `%workspace%`.  The runner
replaces it with the absolute path of the task workspace before the prompt
reaches any harness, so that every harness gets an absolute path and the task
stays reproducible.  Every other character of the prompt is the person's own
text.

## The environments

| Variable | Meaning |
|---|---|
| `YEAH_TEST_KEY` | the provider key of the Yeah harness; without it the task is `skipped: no provider` |
| `YEAH_TEST_HOST` | the provider host, for example `api.minimax.io` |
| `YEAH_TEST_MODEL` | the model, for example `MiniMax-M3` |
| `YEAH_BENCH_EXTERNAL_COMMAND` | the command template of the external harness |
| `YEAH_BENCH_EXTERNAL_NAME` | the label of the external harness in the results (default `external`) |

The Yeah harness drives Yeah through its own headless path, the way
`tests/live/live-coding-task.el` does: the real tools, a real session, a real
journal, and the provider credentials of the environment.  The journal of a
Yeah run is written next to the results, under `results/<timestamp>/sessions/`.

A comparable harness (opencode, pi, or anything else) is installed and
configured by the person who owns the benchmark, not by this repository.
Give the runner a command template and it runs that command in the workspace
of the task:

```sh
export YEAH_BENCH_EXTERNAL_COMMAND="opencode run --cwd %workspace% %prompt%"
export YEAH_BENCH_EXTERNAL_NAME="opencode"
./scripts/dev bench --run
```

The template knows two placeholders: `%workspace%`, the absolute path of the
task workspace, and `%prompt%`, the prompt of the task.  Both are quoted for
the shell, so a prompt with spaces or quotes is safe.  The command runs with
the task workspace as its working directory.  The first word of the template
is the executable: when it is not installed, every task of that harness is
recorded as `not-available`, never as a pass and never as a failure of the
agent.

## The statuses

| Status | Meaning |
|---|---|
| `passed` | the harness ran and the check of the task exited 0 |
| `failed` | the harness ran and the check of the task exited non-zero |
| `skipped` | the harness could not run for a reason that is not the task's fault, for example `no provider` |
| `not-available` | the harness or the check is not installed or cannot run |

The runner never invents a pass.  A harness that could not run is `skipped` or
`not-available`, with the reason in the record.  The self-check enforces
this rule: it runs the Yeah harness without credentials and fails when a
record says `passed`.

## The results

Every run writes one JSON line per (task, harness) to
`results/<timestamp>.jsonl`, and prints a comparison table:

```json
{"task":"read-answer","harness":"yeah","status":"skipped","check_exit":null,"reason":"no provider"}
```

The fields are the task, the harness, the status, the exit code of the check
(`null` when the check did not run) and a short reason.  The table is the same
information, for the eye.

## There is no threshold

**No acceptance threshold is declared yet.**  The final benchmark task set and
the acceptable parity threshold are a decision of the owner, recorded in
`docs/PLAN.md` §13.  Until that decision is made, the runner reports
measurements and no verdict: it never says that Yeah is as good as another
harness, and the exit code of a run says that the apparatus did its work, not
that parity holds.

The green verdict of the math-coding map says nothing about these
measurements.  The benchmark is outside the claim map, like the live tests:
the map cannot speak for it, and a benchmark result cannot speak for the map.

## What the self-check does not prove

The self-check proves that the task set is well formed, that every check
fails before the work, and that the runner does not invent a pass for a
harness that could not run.  It does not prove that a task is solvable, that
the prompt is unambiguous, or that a check accepts every reasonable solution:
it needs a model for that.  A check that always failed would pass the
self-check; the honest way to find such a check is to solve the task by hand
and to see that the check turns green.
