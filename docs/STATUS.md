# STATUS — what works, what is open

> **Status: a ledger with a date.** Every number in this file was measured by
> the command written next to it, on the date written next to it. A number
> without a date and a command is a memory, and a memory is not evidence.
> The machine-checked truth is `spec.json`, read with `./scripts/dev map`; the
> history of the runs against a real provider is `docs/LIVE-EVIDENCE.md`.

## 1. What Yeah is

An agent harness written in Emacs Lisp. The agent runs inside Emacs rather
than beside it: the model is reached through gptel, every effect is a
permissioned Elisp function, and the history of a session is an append-only
JSONL journal. The introduction is in `README.md`, the normative design in
`docs/ARCHITECTURE.md`, and the reason for the project in `docs/VISION.md`.

## 2. What works

Each area below says what the code does today. The checks that stand behind
these words are named in §4.

### The kernel and a turn

- A run is a state machine: the states of `lib/yeah-state.el` and the
  orchestration of a turn live in `lib/yeah-turn.el`.
- A typed tool registry and the last matching permission rules. A read that
  changes nothing is answered by the harness itself and says why; the answer
  `always` becomes a rule, so the same question is not asked twice. Plan and
  Build are profiles of one engine.
- A scheduler with shared and exclusive tools, one settlement per call and
  structured failures. A failure of a handler becomes a failed tool and not
  the death of the process.
- An append-only JSONL journal with a typed event vocabulary, and the view
  models of the interface as projections of it.
- Retries with backoff, deadlines, cancellation, the queue of the person,
  steering and recovery, and the compaction of the context with pruning
  events and the recovery of a corrupt tail.
- Completion supervision: a run is supervised by default, a plan is not an
  answer, and a run that spends its budget without an effect ends as failed
  rather than as done.

### The tools

- Read, guarded edit and write (a version token of the file and a
  modification tick of the buffer), an asynchronous process and job tool,
  output artifacts, introspection, Elisp checks, diagnostics, a todo list and
  the git tools of the review.
- An edit never lands on a file with unsaved changes of the person, and it
  never runs the local variables of the project.

### The wire

- ACP v1 over newline JSON-RPC, on stdio and over a local socket: real
  sessions, journal updates, streamed tool calls and cancellation. Over the
  socket a cancel preempts a running prompt.
- The whole control of a session on the wire: `session/steer`,
  `session/withdraw`, `session/recover` and a `session/load` that replays the
  journal of an earlier session. The queue of the person is a projection of
  the journal events and not a second state.
- An MCP server that publishes the read-only `emacs__*` surface, and an MCP
  client that imports the tools of a foreign server under a namespaced name.

### The placements and the bridge

- Three placements — attached, service and batch — write the same events for
  the same task.
- A service Emacs that is started, connected to and stopped, and the editor
  side of it: an ACP client that connects, matches the answers to the
  requests, answers the permission requests of the service and sees the
  streamed updates.
- The emacsclient bridge to the live buffers of an attached Emacs. It is a
  capability, approved separately and off by default.

### The interface

- The journal mode: one event-derived view, updates that preserve the reading
  position, outline folding, semantic faces, and a separate multiline
  composer with a bounded history.
- Ask, steer, cancel, recover, withdrawal, a diff review, an Org export and
  `M-x yeah-doctor`. Icons are optional decoration; every label stays
  readable text without them.

### The delegation

- Agent presets are files. The `delegate` tool names one, and the child runs
  on the model of the preset, with the tools of the preset and the
  instructions of the preset; every tool outside the preset is refused to it.
- The child has its own session, its own permissions and its own journal, and
  the tree of the children is in the journal of the run. A restart of the
  harness finds the children of a run again.

### The installation and the integration

- A package entry point through `package-vc` and a clean-Emacs bootstrap at
  `install/yeah-bootstrap.el`.
- The orchestrator Paseo speaks to this kernel through the plugin in
  `plugin/yeah-provider/`: the provider is registered, an agent of it runs in
  the workspace that is open in Paseo, its text reaches the timeline and its
  permissions reach the person.

## 3. What is open

The full list with the evidence for every item is `docs/PLAN.md` §17.1; the
decisions that only the owner may make are `docs/PLAN.md` §17.2. The short
list:

- **The turn.** A message that reports a finished work and announces the
  next step reads as a result, and the harness does not see the plan in it.
  A run that ends on a text answer is a completed run even when the task
  asked for the tool `finish`; the check of the task is the arbiter.
- **The provider.** A provider that is overloaded or that drops a request
  ends a run in ways the runner of the benchmark does not tell apart: a run
  the provider stopped is blocked, and not a failure of the agent.
- **The delegation.** Several children in one turn of the parent work, but no
  live turn of a parent with two children of a live provider has been
  measured, and no child of a live provider has run on a model other than the
  model of its parent. A child that was running when the Emacs died is not
  brought back to life.
- **The product.** A real editor against a live provider is not checked yet;
  the bridge is verified against a live Emacs server and not against a
  person's Emacs in day-to-day use; the picture of the interface is compared
  with itself and not with a stored golden picture. PTC stays experimental,
  off by default, and is not a security boundary.
- **The wire as an orchestrator sees it.** The `cwd` of a session does not
  reach the tools, the model and the permission profile cannot be changed
  over the wire, the `mcpServers` of a session are ignored, and the outcome of
  a run does not travel in `session/update`. The gaps are written down in
  `docs/PASEO-INTEGRATION-PLAN.md`.
- **The life of the process.** A client that keeps the pipe of the server
  open leaves an Emacs process alive, and some of those processes spin. The
  spin is not localized yet.

## 4. The evidence, and its levels

Four levels, and each level proves its own subject. A green module is not a
working product.

1. **Unit tests** of the pure transitions.
2. **Canaries** bound to the claims of `spec.json`, each with a control that
   breaks the subject and makes the check fail by an assertion.
3. **Integration checks** with real processes, real gptel contracts and a
   restart.
4. **Live checks** against a real provider. They need credentials, so no
   control can bite, and their green says nothing about the claims of the
   specification.

What was measured on 2026-11-24, on the tree of that day:

| What | Measured | Command |
|---|---|---|
| The unit tests of the kernel | 463 tests, 463 results as expected, 0 unexpected | `./scripts/dev ert tests/unit/*.el` |
| The claims of the standing specification | 185 claims: 140 of them are bound to a canary, 42 to the unit tests, one is a decision of the owner | `spec.json` |
| The verdict of the method | unknown: 184 claims hold, one is not established | `./scripts/dev gate` |

The claim that is not established is
`the-owner-decided-the-order-of-the-next-waves`: a decision of the owner is
not a fact that a check can establish, and the map answers unknown until the
owner records it. Unknown is not pass.

The runner of CI has no evidence trail of its own, so the map answers unknown
there as well, and the workflow warns about it instead of failing the build.
The colour of the CI and the verdict of the method are two different things,
and this file names the second one.

The live checks are not part of CI and are not a part of the numbers above.
What each of them proves, how to run it and when it was last recorded is in
`docs/LIVE-EVIDENCE.md`.

The parity with other harnesses was piloted against `pi` on three tasks with
a live provider. The sample is small, the numbers differ between runs with the
noise of the provider, and the threshold of the parity is a decision of the
owner (`docs/PLAN.md` §13). Nobody may quote the pilot as a verdict about
parity.

## 5. How to refresh this file

```sh
./scripts/dev byte-compile-all
./scripts/dev ert tests/unit/*.el
./scripts/dev check tests/checks/*
./scripts/dev gate
```

The gate needs Emacs on `PATH` and a `mathc` that can read the specification
of the project; a tool that cannot is a blocked measurement, not a green one.
When the numbers of this file are older than the tree, the tree is the fact
and the command above is the way to it.

## 6. The road

- `docs/PLAN.md` §17.1 — the open work of the code.
- `docs/PLAN.md` §17.2 — the decisions of the owner.
- `docs/ARCHITECTURE-CATCHUP-PLAN.md` — the order of the waves that bring the
  code up to the architecture.
- `docs/PASEO-INTEGRATION-PLAN.md` — the order of the work on the integration
  with Paseo.
