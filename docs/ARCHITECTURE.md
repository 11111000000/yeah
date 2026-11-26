# ARCHITECTURE — Yeah, the Emacs Agent Harness

> **Document status: normative target.** This file describes the system Yeah
> is being built to become. It is not evidence that the system already works.
> `spec.json` and `./scripts/dev map` describe the verified present;
> `docs/PLAN.md` describes the path from one to the other.
>
> When this document and the code disagree, the disagreement is a finding.
> Do not silently rewrite either side.

## 1. Identity and purpose

**Yeah** means **Yeah, Emacs Agent Harness**: a recursive acronym, the **Y**
is the Y-combinator.  `docs/VISION.md` states the whole reason in one
piece; this section fixes the identity it implies.

The Y-combinator gives recursion without requiring a name. Yeah takes three
consequences from that idea:

1. **Recursion.** An agent may create bounded child work without knowing the
   whole shape of the work in advance.
2. **Self-reference.** An agent can inspect the runtime in which it runs,
   including Yeah itself: functions, documentation, buffers, tests and tools.
3. **A fixed point.** Yeah must eventually be able to develop and verify
   Yeah. The canonical demonstration is: inspect a failing canary, edit its
   subject, run the tests, review the diff and commit through Magit.

Yeah is not a chat client, a terminal wrapper, or an interface to an agent
implemented elsewhere. **The harness itself is Emacs Lisp.** A model provider
is an external service; the agent is not.

The purpose is larger than a coding assistant: to preserve and extend the
useful culture of Emacs — introspection, inspectable state, composable tools,
user control and durable text — in an agent-native form.

The reason for that purpose is the environment itself, not its API list.
Emacs already holds decades of community packages and years of each person's
own configuration: an environment people shaped until it fit them. An agent
born inside that environment starts from that inheritance instead of from
nothing. **The agent does not replace the person's environment; it becomes
a participant in it** — and the environment, through the agent, gains a way
to develop itself. The fixed point of the Y is therefore not a
self-modification trick: it is the moment the accumulated environment
begins to improve itself through the agent, the person included.

## 2. The product promise

Yeah is intended to become competitive with complete harnesses such as
opencode and pi, while offering what a shell-only harness cannot: the
accumulated environment of the person's own Emacs, reached directly:

- direct access to live buffers, including unsaved text;
- the editor's own documentation and source as agent context;
- structured edits and undo in the user's actual editing environment;
- Eglot/Flymake diagnostics without a second build system;
- Magit, Org, project.el, Dired, TRAMP and emacsclient as native capabilities;
- an inspectable, durable session journal rather than an opaque process state;
- local models and offline workflows as first-class configurations.

The service placement isolates the thread, not the culture: the editing
Emacs never waits for a long turn, while the model configuration, the
permissions and the live buffers remain the person's own.

Parity is a goal to be measured, not a claim to be advertised prematurely.
The primary success measure is whether tasks are completed correctly, not
whether the feature checklist is long.

## 3. Non-negotiable invariants

1. **Elisp kernel.** `lib/` is Elisp. There is no hidden agent sidecar.
2. **One model gateway.** All model traffic goes through the private gptel
   adapter. The rest of the kernel does not know provider APIs.
3. **One tool gateway.** Model-originated tool execution goes through the
   registry, argument validation and permission policy.
4. **Append-only history.** No operation rewrites or deletes an acknowledged
   journal record. Compaction and pruning create projections or new events.
5. **No blocking wait in interactive Emacs.** Waiting is represented by a
   process callback, a timer or an explicit state.
6. **The kernel does not know its master.** Human, ACP, MCP and batch drivers
   use the same run controller and journal.
7. **Fail closed.** Unknown protocol shapes, unapproved effects and unknown
   sandbox operations are refused rather than guessed.
8. **No silent stubs.** A public path that is not implemented says so and
   stops. A green check must never be produced by a placeholder.
9. **User ownership.** No telemetry by default, no hidden global keybindings,
   no secret material in configuration examples or logs.
10. **Honest limits.** Documentation states what cancellation, persistence,
    undo, isolation and replay do *not* guarantee.

## 4. The ten architectural decisions

These decisions are the stable core of the design. Changing one requires an
explicit update to this section, the relevant plan item and the specification.

### D1 — The journal is the source of truth

The session journal is append-only JSONL. Model context, UI state, cost,
pending approvals, session trees and recovery information are projections.

Every journal event has a schema version, session id, event id and timestamp.
Events that participate in execution also carry the relevant run, turn,
tool-call and parent/correlation identifiers. The vocabulary includes not
only messages and tools, but compaction, pruning, steering, nudges,
cancellation, approvals, dropped calls and protocol errors.

A provider history that cannot be replayed safely is not silently repaired.
The session becomes explicitly non-replayable and further execution stops.

*Amended on 2026-11-15 (wave 30): a decision that was dropped as a repeat
left no record, so a reader of the journal could not tell a repeated decision
from a decision that never came, and the run looked different from what
happened. The drop is a journal event now, carrying the tool, the reason and
the arguments; the promise of the journal as the source of truth is kept and
made explicit, not relaxed.*

*Amended on 2026-11-17 (wave 45): the journal does not refuse a record. A
record of a run can hold a value that JSON cannot write — a symbol, a
character, a cons that is not a list of pairs — and the refusal of JSON must
not take the run down: the record is written as a stand-in that says the
journal could not write it, and the journal takes the records that follow.
The promise is strengthened, not weakened: a journal that drops a record
without saying so is not a source of truth. The same wave bounds the reason
of a failure: a provider that refused a request hands the whole conversation
of the run back inside the refusal, and one record of the journal is a
record and not a transcript. The reason is cut at two thousand characters,
the fields that name the failure are kept, and the place where the text was
cut is said.*

*Amended on 2026-11-19 (wave 68): a list in a record is not a value that JSON
cannot hold. `json-serialize' writes a list as an object or refuses it, and a
record that held a list — the record of a queued input, whose frozen
configuration names the MCP servers of the session — was therefore written as a
stand-in, and the record was lost. The journal writes a list as an array: the
other fields of the record survive, and the reader of a JSON array gives a
vector back, the same rule the tasks of a todo event follow. The stand-in
keeps its meaning and its scope: a value JSON cannot hold at all — a symbol, a
cons that is not a list of pairs — is still written as a stand-in, and the
journal still takes the records that follow. The promise of the journal as the
source of truth is strengthened, not weakened: a record that holds a list is a
record, not a stand-in.*

*Amended on 2026-11-19 (wave 67): the file of a session appears when the
session writes its first record, and not when the session is opened. The
orchestrator reads the catalog of the models through a real session and never
closes it, so every list of the models left a session behind — a file with a
single header and nothing else, in the place where a person looks for the
truth about a run. The promise is strengthened, not weakened: a journal that
holds a session that never happened holds a thing that did not happen. The
journal stays append-only, the header stays the first line of the file, and a
session that never wrote anything leaves no file at all. The same wave amends
the contract of `session/load`: the kernel refuses only a session it knows
nothing about, and a session of this process that never wrote loads with
nothing to replay — the absence of a file is not the absence of a session.*

*Amended on 2026-11-19 (wave 70): the journal held the cost of one request
twice. The transport of gptel hands the info of a request to every shape of it
— the reasoning of the model and the answer that follows it carry the same
tokens — and the turn wrote the usage of the request for every shape that
carried it, so a model that thinks was paid twice in the journal and the
reported cost of the run was twice the cost of the run. The usage of a request
is written once: the road to the answer — the reasoning, the result of a tool
that ran and the sentinel of a stream that is over — is not a second request,
and the decision of what the road is lives in one place
(`lib/yeah-answer.el`). The promise of the journal as the source of truth is
kept and made explicit, not relaxed: a record of the cost that is written twice
is not the truth about the cost. The journal stays append-only, and the records
that were written twice stay where they are.*

### D2 — Yeah owns its execution state machine

Yeah does not build its correctness on advice to gptel internals. gptel owns
HTTP and provider serialization; Yeah owns run state, tool settlement,
permissions, cancellation and recovery.

The number of states is not an invariant. The invariants are valid
transitions, once-only settlement, bounded waiting and a recoverable terminal
state. Four failure classes are mandatory checks: malformed tool arguments,
exceptions in handlers, duplicate asynchronous callbacks and nil/non-string
tool results.

*Amended on 2026-11-17 (wave 45): two more failure classes are mandatory.
An error of the harness that happens inside the callback of an asynchronous
tool arrives in the sentinel of a process, where no handler of the turn
stands, and it kills the Emacs process: the error becomes a failed tool
instead, and the run ends with a reason. And a run whose context overflows
and whose summary the provider does not write does not die: the summary is an
economy and not a necessity, so the old outputs of the tools are pruned, the
journal says that the summary did not arrive, and the run goes on. A second
overflow without a summary ends the run, and the journal says why.*

### D3 — gptel is a narrow, private model adapter

The adapter normalizes streaming text, reasoning, tool calls, usage and
provider errors. It does not mutate the user's global gptel configuration or
install global hooks.

Backend, model, instructions and editor context are frozen when input is
accepted. Supported gptel versions are pinned and checked with contract
tests. A missing hook or changed callback shape is a compatibility failure,
not a no-op.

### D4 — Typed tools are central; evaluation is an explicit option

The ordinary agent uses declared tools with JSON-compatible schemas and
structured results. The initial set is Read, Glob, Grep, Edit, Write, Bash,
Introspect, Diagnostics and the relevant Emacs buffer/project tools.

An Eval capability may expose ordinary Elisp helper functions, but it is
separately permissioned and confirmed. It is not a sandbox. The old PTC path
is experimental and must not be presented as a security boundary.

Batch helper operations are preferred over unrestricted programmatic tool
calling: one Edit call can apply a validated list of replacements without
giving the model a general evaluator.

### D5 — Edits use optimistic concurrency

Every read that can lead to an edit returns the state the model saw: the
`buffer-chars-modified-tick` of the buffer that visits the file, and the
version of the file itself — the digest of its bytes on disk — for a file that
no buffer visits. An edit presents the tick or the version that a read handed
out, together with exact old text/ranges. A presented tick or version that is
no longer current is refused; a state that no read handed out is ignored, and
the edit says so. All ranges are validated before mutation; edits apply
bottom-up; a logical edit is one undo step; a no-op does not add undo history.

Stale input is rejected and reread. The agent never guesses offsets after the
user or another tool has changed the file, and it does not edit a file whose
unsaved changes in the editor a read cannot show.

*Amended on 2026-11-15 (wave 29): the decision named only the tick of a
buffer, and the tick exists only when a buffer visits the file, so the
promise could not hold for the file that nobody opened. The version of the
file is the second form of that state; the promise is kept and made
explicit, not relaxed.*

*Amended on 2026-11-15 (wave 32): the version is a digest that a model has to
copy back, and the pilot measured a digest of 64 characters of hex come back
with six characters missing — the edit then refused a file that had not
changed. The token is therefore short: twelve characters of the digest, 48
bits, enough to tell two states of a file apart. A refusal of a token that is
not the version of the file now names the token and reports the current one,
because a token that was copied wrong does not mean that the file changed;
the promise of the guard is kept and made honest, not relaxed.*

*Amended on 2026-11-15 (wave 33): the decision promised that the agent does
not edit a file whose unsaved changes in the editor a read cannot show, and
the code kept that refusal only for the edits that presented a version. The
refusal is now the answer of every edit, with a version or without one: a
read shows the disk, and the changes of the person live in the buffer. The
write of a whole file takes the same short version token as the edit, so a
write never lands on a file the model did not read; the promise is kept and
made explicit, not relaxed.*

### D6 — Large output becomes an artifact; context is calibrated

Tool output has explicit limits. Oversized output is written with private
permissions below Yeah's data directory; the model receives a bounded excerpt,
an absolute artifact reference and truncation metadata.

Context estimates start with a documented heuristic (including CJK-aware
counting) and are calibrated against provider-reported usage. Compaction is
an asynchronous model operation that commits only a complete, nonblank
summary. Its source events remain in the journal.

The model is told what the run has done. Every request of the harness carries
the transcript of the run before the prompt: the call the model made, the
result it got and the answer it gave, so that a model which answers with a
plan instead of an action does not start the task over. The transcript is a
projection of the journal and not a second copy of the run: the journal keeps
the plain message the run was written with, and the projection is put together
on the way to the model. The first request of a run carries the request as it
is, because a run that has done nothing has nothing to tell.

*Amended on 2026-11-17 (wave 47): every request of the harness started a
fresh conversation with the model — the prompt was all the model was told — so
the model could not continue the work and began the task over. Two live runs
of the wave 41 measured the shape: 108 and 122 calls of tools and no change of
the repository, with `AGENTS.md` read ten and nine times. The promises above
are kept and made explicit, not relaxed: the transcript is a projection and
not a copy, and it is cut — twelve records of the run, six hundred characters
of the result of a tool. What it is not is a context: the projection of the
context, the compaction and the pruning are still not on the road to the
model.*

*Amended on 2026-11-17 (wave 48): the death of the transport is not the death
of the run. A request that the provider dropped — the transport failed and
there is no HTTP status — and a request that met a busy provider (429, 500,
502, 503, 504, 529) are asked again, and the model is asked the same question
with the transcript of the run in front of it. The retry is bounded by a budget
of its own, the journal holds it as a record of its own, and the machine of
the states does not move: the run was waiting for the model and waits again.
A request that the provider refused is an answer, and the run fails at once
and says why. The status of the wire decides which of the two it is, and the
transport of gptel reports that status as a string, so it is read as a number
and not only as a number.*

*Amended on 2026-11-17 (wave 49): the compaction waits for the answer of the
provider, and the decision of an answer lives in the kernel. The compaction
took the first piece of the answer for the whole answer, and a provider that
reasons sends its thinking first: a live run of the wave 41 degraded for
nothing and died on a transition that its machine did not have. What counts as
an answer is now decided in one place (`lib/yeah-answer.el`): text with
content and a tool call are answers, the empty string, the streaming sentinel
and the reasoning are not, and everything but the road to the answer ends the
request of the provider. The compaction waits for that answer and delivers the
outcome once, so a provider that answers twice does not compact the context
twice and does not break the run. The promise above is kept and made explicit:
the compaction commits only a complete, nonblank summary, and a request that
ends without one leaves the journal unchanged and the run goes on.*

### D7 — The human is an asynchronous master

Steering is delivered at a batch boundary, never halfway through a tool batch.
Pending input is bounded, persisted and recovered only deliberately.
Cancellation stops further settlement and managed processes where possible;
it does not pretend to roll back arbitrary effects or kill every descendant.

Completion nudges are bounded, visible events. They ask the model to verify
completion criteria instead of stopping prematurely; they are not an infinite
hidden loop. Supervision is the default of the kernel: the budget of the
completion nudges is positive, and a caller that wants no supervision at all
asks for it with a budget of zero. A run that spends its budget without an
effect ends in the state `failed`, and the journal of the run says so; a run
that did not do the work is never presented as a finished one.

The budget of the nudges pays for the nudges that no effect answered. A
provider answers with an empty message after a batch of tool results have come
back, and that silence is the noise of the provider and not the refusal of the
model to act: a nudge that follows it does not spend the budget, because the
model has acted. A model that never acts still ends, and the run says that it
did not finish. The record of a run that did not finish is true: it names the
tools the run called, and a run that called its tools is never described as a
run that ended without an effect.

The wire of Yeah speaks ACP and nothing else. A content chunk carries one
content block, as the protocol says, and a client that checks the wire
refuses an update whose shape it does not know. The events of the pending
queue of a session are not ACP, so they travel only to the client that asked
for them: the client announces them in the `_meta` of its capabilities at
`initialize`, and a client that announces nothing is served plain ACP. The
editor of Yeah announces them and sees the queue of the session.

The answer of the agent is the message of the agent. A model that answers
only through the `finish` tool says nothing else, so the summary of a
finished run travels as the message of the agent, and a client that waits
for the words of the agent sees them. The call of a tool travels with what
the tool was called with and what it returned: the arguments are the values
themselves and not their printed form, and the printed form of arguments
that come from the model is read as data and never as code.

The bytes on the wire are the bytes of the text. A serialized message is
UTF-8, and it leaves the process as UTF-8: the words of the agent reach
the client as the words the model wrote, and a Russian answer does not
arrive as a Latin-1 reading of its own bytes. The wire carries text, not
a promise about a character set.

A supervised run ends through the `finish` tool. A text answer that reports
a result is not a completion: the run nudges the model into the call that
ends it, and the nudge carries the state of the work, so that the model
continues instead of starting the task over. A model that never calls
`finish` spends the budget of the nudges, and the run ends as a failed run
that says what it did not do. A run that asked for no supervision at all (a
budget of zero) ends on the word of the model, because there is nobody to
nudge it.

*Amended on 2026-11-18 (wave 53): the supervision was declared and not held.
The kernel took every text answer of the model for the end of the run, so a
live run of wave 42 that called 261 tools, finished nothing and was cut off
in the middle of a sentence was recorded as `completed`. Two claims of one
specification contradicted each other here — one said that the run ends
through `finish`, the other read the words of the model as the end of the
run — and the code followed the softer one. The promise above is kept and
made explicit, not relaxed: the path of the completion is the call of the
tool and not the talk of the model, and a run that says its result in words
is nudged into the call that ends it.*

*Amended on 2026-11-16 (wave 40): the wire carried two shapes that ACP does
not have — the content of a chunk was an array of blocks instead of one
block, and the events of the pending queue travelled to every client as if
they were ACP. A client that validates the wire refused the whole update,
so the text of the agent never reached the client. The promises above are
kept and made explicit, not relaxed. The same wave found that the words
themselves were spoiled on the way out: Emacs read the bytes of a
unibyte string as Latin-1 and wrote them back as UTF-8, so every
non-ASCII answer arrived at the client written twice over.*

*Amended on 2026-11-19 (wave 69): the answer of `session/prompt` carried a
stop reason and nothing else, and the orchestrator counted the tokens of a run
of Yeah it never saw — it reads them from the field `usage` of that answer.
The answer carries the usage of its turn now: the tokens the provider reported,
as `inputTokens`, `outputTokens` and `totalTokens`. The usage is the usage of
the turn and not the usage of the session — the records of the usage of a run
share the run id of that run, and a run is one prompt. A provider that reported
nothing has no field in its answer: the kernel has no tokenizer of the provider
and does not estimate the cost of a run. The promises above are kept and made
explicit, not relaxed: a client that knows nothing of the field ignores the
key, and the answer of a run that spent nothing it reported is an answer
without the field.*

*Amended on 2026-11-19 (wave 71): the answer of `session/prompt` reaches the
orchestrator through a connection that keeps one stop reason and throws the
rest away, so the field `usage` of the answer never reached the counter of the
agent. The tokens of a turn travel by a second path, which this repository
owns: the kernel sends them as the notification `yeah/usage` — a method of Yeah
and not of ACP — to the clients that asked for them in the `_meta` of their
capabilities, and the plugin of the orchestrator translates the notification
into the event of the provider `session.usage`, the only event the orchestrator
carries into that counter. The translation completes one part of the usage with
the other and replaces neither: the size of the window comes from the update
of the context of ACP, and the tokens of the turn come from the kernel, and the
counter of the agent holds both whichever of the two the orchestrator handles
last. The promises above are kept and made explicit, not relaxed: the
notification travels only to the clients that asked for it, and the kernel
sends nothing when the provider reported nothing.*

### D8 — Agents and skills are declarative

Agent presets live in Markdown or Org files with metadata: name, description,
model, allowed tools and system prompt. Skills use the agentskills.io layout
and compatible well-known directories where practical.

A sub-agent has a child run context, an explicit parent event, a restricted
tool set, a depth limit and a budget. Its intermediate events remain
inspectable; a summary alone is not an audit trail.

A parent model asks for a child through the `delegate` tool, which names an
agent preset: the child runs in a session of its own, on the model of that
preset, with the tools of that preset and with the instructions of that preset,
and every tool outside the preset is refused to it. The `delegate` tool answers
at once with the id of the child, so the turn of the parent is not held; the
child answers on its own, later, and the `delegate-result` tool reports what
became of it. A delegation is a change of the world, and the Plan profile
denies it.

*Amended on 2026-11-16 (wave 35): the decision named a sub-agent but not the
way a parent model reaches one, and the presets of the agents were files that
nothing in the model-facing surface read. The delegation is now a tool of the
kernel: it names a preset, it hands the model of the preset, the tools of the
preset and the instructions of the preset to the child, it refuses every tool
outside the preset, and it keeps the turn of the parent free while the child
works. The promises above are kept and made explicit, not relaxed.*

*Amended on 2026-11-16 (wave 36): the delegation had no journal of its own,
and it took the journal of a run it remembered instead of the journal of the
run that asked for it. A run binds the session it writes into while it
dispatches a call, and the child of that call is written into the journal of
that run; a call with no run has no journal and is refused. The id of a child
is short, because the model has to copy it back and a long token is copied
with an error; a wrong id names the children that do exist. A child has a time
of its own, and a child that ran out of time is cancelled and the parent is
told why. The promises above are kept and made explicit, not relaxed.*

*Amended on 2026-11-16 (wave 37): the tree of the children was kept in the
memory of the running Emacs and not in the journal, so a restart of the
harness forgot the children that still worked. The tree belongs in the
journal: the journal of the run holds the short id, the session and the depth
of every child, and the journal of the child holds where the child stands in
the tree. A harness that starts again reads the tree from there — the child of
a run is found by the id the model was given, what became of it is told, and a
child the journal holds no end of is not reported as a child that still works,
because the restart ends the child as well. The depth of a child is read from
its own journal, so a child of depth one does not look like a root after a
restart and is refused the delegation that would go deeper than the agent of
the child allows. The promises above are kept and made explicit, not relaxed.*

### D9 — Plan, Build and Auto are permission profiles

Plan mode is a read-oriented rule profile. Build mode enables the normal
approved effect set. Switching modes is a journal event. PlanExit is an
approval operation, not a second execution engine.

Build carries a separate workspace-trust toggle. With the toggle on, one
remembered answer covers later work below the session directory. Bash has a
separate workspace-shell grant, so one answer covers later Bash commands
there, not one command. Paths below another root ask separately. This is a
permission boundary over named tool arguments, not an operating-system
sandbox.
Read-only review tools — including git status and git diff — answer as safe
reads. While one call waits for permission, another call from the same batch
may settle; the run remains in the permission-wait state.

Auto mode is the third profile: it allows the tools that change the world
without a question, because there is nobody to answer the question. The
owner decided on 2026-11-19 that the mode is needed (the orchestrator runs
the agent unattended, and every question is a question nobody answers). The
mode does not make the agent safe: the safety of the agent is the safety of
its tools, and that is why the deletion of the agent is a move into the
trash of the user and not a removal (`lib/yeah-trash.el`), and why the
commands that destroy in place are refused by name
(`lib/yeah-shell-guard.el`). The guard is a list of forms and not a
sandbox: the honest boundary of the agent is the account it runs as, and
the map of what is and is not protected is `docs/AGENT-SAFETY.md`.

*Amended on 2026-11-19 (wave 76): the profile `auto` was added, the effect
`allow` of a profile is honoured by the wire and by the approval of the
attached path, and a rule may name every action with the wildcard. The
decision of the owner is recorded in `docs/PASEO-INTEGRATION-PLAN.md` §5.1
and in `docs/PLAN.md` §16.65.*

### D10 — Design rationale and verified facts live together

This file records why the architecture has its shape. `spec.json` records
what is currently established. `docs/PLAN.md` records intended work.
`ELISP_BEST_PRACTICES.md` records language-level traps;
`docs/ENGINEERING.md` records system-wide engineering rules.

A substantial decision change updates this file before or with its code.
Git is the historical record; there is no second, contradictory design corpus.

## 5. Component architecture

```text
 Human (`M-x yeah`)     ACP clients      MCP clients      Batch
         |                   |                |             |
                             +--- Wire ------+
                             (stdio, socket)
         \________________Session API / Run Controller  ____/
                                  |
             +--------------------+--------------------+
             |                    |                    |
       Model adapter        Tool registry        Policy / approvals
       (private gptel)    (typed, validated)    (rules as data,
                                                declared risk)
             |                    |                    |
             +--------- Execution scheduler -----------+
                       shared/exclusive, resource lock,
                       once-only, bounded
                                  |
                    Append-only versioned JSONL journal
                                  |
             +--------------------+--------------------+
             |                    |                    |
        Model context        Read models/UI       Session index/cost
                                  |
                  attached, service, batch placements
```

The site publishes this architecture as a diagram -- in the notation of the bands,
not in the notation of the components: what asks, what decides, what is remembered
and what is seen -- and every leaf of that picture names the
files that implement it (`site/diagrams/core-layers.d2`; `site/index.html`).
The figure above and that diagram are one architecture: the drivers submit to
the controller, the controller drives the model adapter, the tool registry and
the policy, the scheduler runs what may run, everything that happened is
written into one journal, and the projections read the journal.

### Run Controller

A run has an explicit context: its id, its placement, its session, its
transport to the model, its own rules, its answerer, its budget, its
deadline, its input, the number of nudges it may get, its cancellation flag
and its own snapshot of the tool registry (`lib/yeah-run.el:40`). The session
is the event sink and the clock is the clock of Emacs.

Registries and permissions must not be implicit process-wide state shared by
unrelated runs. The registry of a run is its own snapshot
(`lib/yeah-run.el:105`; `lib/yeah-tools.el:69`), and the rules of a run are
its own list: a run asks with the rules of the run and with the rules of the
files, and not with the rules of the process (`lib/yeah-run.el:156`).

The controller is the only component that advances the run. UI, protocols and
tests submit commands to it; they do not reproduce its transitions. The
advance happens in the turn (`lib/yeah-turn.el:256`), and every move of the
turn is a cell of the table of the machine (`lib/yeah-loop.el:26`); the check
of that promise is
`tests/checks/check-every-transition-of-the-table-is-taken.el`. A placement
and a child start a run of their own through that same turn
(`lib/yeah-placement.el:136`; `lib/yeah-subagent.el:223`).

### Tool contract

A tool declaration is a plist, and the registry refuses a declaration it does
not understand (`lib/yeah-tools.el:202`). It contains:

- `:name`, `:description`, `:input` and `:handler` — the four are required
  (`lib/yeah-tools.el:110`);
- `:input` — a list of `(:name PARAM :type TYPE [:optional t] [:duration t])`,
  where the type is `string`, `integer`, `symbol` or `boolean`; the required
  parameters come first and the optional ones come last, and the values are
  the JSON-safe ones, so that the wire and the journal can carry them
  (`lib/yeah-tools.el:125`; `lib/yeah-tools.el:343`);
- `:kind` — `read`, `edit`, `delete`, `move`, `search`, `execute`, `think`,
  `fetch`, `switch_mode` or `other`; a tool that declares no kind has the
  kind `other`, and a kind outside this vocabulary is refused by name
  (`lib/yeah-tools.el:96`; `lib/yeah-tools.el:218`);
- `:risk` — `read`, `write`, `execute` or `destroy`; a tool that declares no
  risk has a risk that is not known, and a risk that is not known changes the
  world: the rule asks about it, and the absence of a declaration never makes
  the rule softer (`lib/yeah-risk.el:42`; `lib/yeah-risk.el:113`);
- `:concurrency` — `shared` (the default) or `exclusive`
  (`lib/yeah-tools.el:258`);
- `:resource` — a nonempty string that names what the tool touches; it is a
  lock: two calls that declare one resource never run at the same time, and a
  tool that declares no resource is never held back
  (`lib/yeah-tools.el:161`; `lib/yeah-scheduler.el:104`);
- `:async` — the handler takes a continuation (`lib/yeah-tools.el:173`);
- `:timeout` — the upper bound of the work of one call, in seconds; only an
  asynchronous tool may declare one, because the kernel cannot interrupt the
  handler of a synchronous tool (`lib/yeah-tools.el:181`);
- `:output-limit` — the upper bound of the output of one call, in characters;
  the limit that applies is the smaller of the declared one and the global
  one (`yeah-result-output-limit`), and the global limit is a ceiling that a
  declaration cannot raise (`lib/yeah-tools.el:288`).

The arguments of a call are checked against the declaration before the handler
runs: the count of the arguments and the type of every one of them must
match, and a tool is never called with arguments it did not ask for
(`lib/yeah-tools.el:397`). A parameter that says how long the work may take
is marked `:duration t`, and a call that asks for a duration longer than the
timeout of the tool is refused by name (`lib/yeah-tools.el:198`).

A result is structured: success/failure, content or typed error, truncation
information and artifact references (`lib/yeah-result.el:34`). Tool errors
are values for the model and events for the journal; they do not wedge the
run.

The content of a result is text. A tool of the agent can return bytes that
are not text — `tail -c` cuts a character of a UTF-8 file in half — and such
bytes arrive in two shapes: a unibyte string of bytes, and a multibyte string
that holds a raw byte where the decoder refused one. The text of the harness
is decided in one place (`lib/yeah-text.el`); a byte that is not text becomes
the replacement character, and the rest of the text is kept as it is. The
text of the model is the same kind of text, for the same reason: the answer
of a model reaches the client and the journal, and neither can carry bytes
that are not text.

### Event envelope

The exact schema is versioned, and the record is JSON: the journal is JSONL,
one record per line (`lib/yeah-session.el:167`). At minimum:

```text
schema_version, id, type, session_id, timestamp
run_id, turn_id, tool_call_id, parent_event_id   (when applicable)
```

The envelope of every new record carries `schema_version`, `session_id` and
`timestamp`, and the writer supplies `id` and `type` (`lib/yeah-events.el:30`;
`lib/yeah-session.el:336`).

Payloads are typed per event: the vocabulary declares the required and the
optional fields of every type (`lib/yeah-events.el:38`). Writers validate
before append, and an unknown type and an unknown field are refused by name
(`lib/yeah-events.el:139`). Readers detect truncation and corruption rather
than silently dropping records: a malformed line is counted, an unterminated
final line is named, and the warning says that the file was not modified
(`lib/yeah-session.el:210`). A record of a type that the vocabulary does not
name stays in the journal and is not projected: the reader of the wire sends
no update for it (`lib/yeah-acp.el:637`).

*Amended on 2026-11-22 (wave E3): this section is synchronized with the code
of the tracks A, B and C, and one line of it is a **declaration and not a
description**. The line is "registries and permissions must not be implicit
process-wide state shared by unrelated runs". The registry of a run is its
own snapshot (`lib/yeah-run.el:105`), and the rules of a run are its own list
(`lib/yeah-run.el:59`): a run that registers a tool or that widens its own
rules touches neither the registry nor the rules of another run. The rules of
the process are another thing: they are one list of the Emacs
(`lib/yeah-perm.el:65`), and the sessions of a process read that list as the
standing permissions (`lib/yeah-acp.el:100`), so two runs of one Emacs share
the permissions of the process without asking each other. The module of the
permissions states the promise itself (`lib/yeah-perm.el:25`), and the path
of the ACP does not keep it yet. The promise is kept and the debt is named:
the rules of the process are the rules of the person, and what the promise
forbids is that they be the implicit state of a run.*

## 6. Emacs-native capability layer

The differentiating tools are not decorations. They are the reason to build
the harness in Emacs:

- **Introspection:** describe functions/variables, apropos, source location,
  documentation and relevant Info text.
- **Live state:** read and edit buffers, compilation output, messages,
  project state and diagnostics without terminal scraping.
- **Elisp verification:** check-parens, byte compilation, checkdoc and ERT.
- **Structural editing:** sexp operations for Lisp and tree-sitter where a
  grammar is available.
- **Diagnostics:** Eglot/Flymake feedback after edits.
- **Version control:** Magit-aware status, diff, checkpoints and review.
- **Org:** plans as TODO trees, session export as durable documents and
  reproducible examples through Babel.
- **Remote work:** TRAMP through the same buffer/file abstractions.
- **Inter-process Emacs:** emacsclient as an explicit, permissioned bridge to
  a person's attached session.

Optional packages are detected at runtime. The base system works without
Magit, Eglot, Org add-ons or a particular completion framework.

## 7. Concurrency and placements

Emacs threads may coordinate waiting; they are not an isolation boundary.
Heavy, unattended or untrusted work belongs in a separate Emacs process.

**Primary deployment (decided 2026-11-12): the service placement.** A
dedicated Emacs process runs the harness, because the person's editing
Emacs is single-threaded and an in-editor agent would block editing. The
editing Emacs reaches the harness through the emacsclient bridge; external
clients and orchestrators speak ACP or MCP to the same service Emacs.

- **Service:** the primary placement. A dedicated Emacs runs the harness;
  orchestrators and protocol clients connect over ACP/MCP. The person's
  editing Emacs reaches live buffers only through the emacsclient bridge,
  which is an explicitly approved capability. The wire is stdio or a local
  socket; on the socket a connection is a process, the event loop keeps
  running while the server waits, and a cancel is handled while a prompt
  is still running — stdio cannot do that (a blocking read stops the event
  loop, and a reader thread holds the interpreter lock).
- **Attached:** the development, demo and fallback placement. The agent
  shares the person's process, works with live buffers and must never
  block editing. Heavy or unattended work does not belong here.
- **Batch:** one process and one task, suitable for CI and benchmarks.

The placement may change process ownership and who answers approvals. It may
not change the canonical sequence of semantic events.

This revises the earlier "attached is the default interactive placement"
wording, per D10: decision changes are recorded explicitly with their
document update. The identity invariant still holds — there is no agent
runtime in another language; in the service deployment both sides are
Emacs, so "Emacs is not a client to an agent living somewhere else" remains
true. The honest limits stand: the bridge is checked against a real Emacs
server (tests/checks/check-bridge-live-server.el), but not yet against a
person's Emacs in day-to-day use, and the stdio wire server answers one
request at a time.

## 8. Security model

The model, repository instructions, fetched text and tool output are
untrusted inputs. Security is capability-based:

- canonical workspace paths and explicit outside-workspace permission;
- separate read, write, process and network capabilities: the code asks by
  the risk that the tool declares, and the risks are `read', `write',
  `execute' and `destroy' (`lib/yeah-risk.el:42`); a tool that declares no
  risk has a risk that is not known, and a risk that is not known changes the
  world (`lib/yeah-risk.el:113`);
- once, session, project and global approval scopes, and the refusal: the
  answers a person may give are `once', `session', `project', `global' and
  `reject' (`lib/yeah-approval.el:60`), the legacy name `always' is read as
  the answer `session' (`lib/yeah-approval.el:74`), and every scope has
  exactly one carrier (`lib/yeah-perm.el:143`): `once' holds no rule, `run'
  and `session' keep their rules in the memory of the path that owns them,
  and `project' and `global' keep their rules in a file of the project and a
  file of the user;
- deny-by-default headless policy (`lib/yeah-approval.el:300`);
- bounded time, tokens, output, pending input and child depth: a tool may
  declare the upper bound of its own work (`lib/yeah-tools.el:181`) and a run
  may have a deadline (`lib/yeah-run.el:61`); the budget of the context is
  60000 tokens by default (`lib/yeah-context.el:32`), the output of one tool
  is 32768 characters by default (`lib/yeah-result.el:23`), the queue of the
  pending input holds eight entries (`lib/yeah-input.el:33`) and 262144 bytes
  (`lib/yeah-input.el:34`), the depth of a child is three
  (`lib/yeah-subagent.el:57`), and the budget of the completion nudges is
  three (`lib/yeah-turn.el:141`);
- no secret files or credentials in logs, examples or test fixtures;
- no claim that regex/whitelist evaluation is a complete sandbox;
- the code of the project is never run: a file that the harness opens for an
  edit comes up with the local variables of the file and the directory-local
  variables of its directory neutralized (`lib/yeah-untrusted.el:35`).

General untrusted evaluation, if ever offered, requires a separately designed
process boundary and its own adversarial verification.

*Amended on 2026-11-16 (wave 34): the model opens the files of the project
on behalf of the agent, and Emacs runs the local variables of a file and the
directory-local variables of its directory when it opens one. That code is
the code of the project, and the project is untrusted input. The harness now
opens the file of an edit with that machinery neutralized, whatever the
configuration of that Emacs is. The price is named, not hidden: the mode line
of the file is part of its content, so it is ignored, and the buffer of the
person shows the file in the mode of its name. The rule is added, and the
security model is made explicit, not relaxed.*

*Amended on 2026-11-19 (wave 76), and the amendment names a debt instead of
hiding it: two lines of this model are a **declaration and not a
description**. The first is "canonical workspace paths and explicit
outside-workspace permission": there is no such check in the kernel, the
tools of a session read and write wherever they are told to, and the
directory of the session is the working directory and not a boundary. The
second is "no secret files or credentials in logs": the output of a tool and
the arguments of a tool are written into the journal as they are, and a
credential read by a command lands in the log. The map of what is protected
and what is not is `docs/AGENT-SAFETY.md`; the two debts above are its
sections 2.1 and 2.3, and they are the first two waves proposed there. The
third line of this model is true and stays true: there is no claim that a
regex or a whitelist is a complete sandbox -- the guard of the shell
(`lib/yeah-shell-guard.el`) is a list of forms, and the trash of the agent
(`lib/yeah-trash.el`) keeps what the agent throws away.*

*Amended on 2026-11-22 (wave E3): this model is synchronized with the code of
the tracks B and C, and the amendment names a third debt instead of hiding
it. The scopes of an approval are the scopes of a rule and the answers of a
person: the dictionary of the answers is `once', `session', `project',
`global' and `reject' (`lib/yeah-approval.el:60`), the legacy name `always'
is read as the answer `session' (`lib/yeah-approval.el:74`), and the scope
of a rule and the answer that writes it are the same thing now -- every
scope has exactly one carrier (`lib/yeah-perm.el:143`). The capabilities of
the model are the risks of a tool: `read', `write', `execute' and `destroy'
(`lib/yeah-risk.el:42`), and the rule asks by the declaration of the tool and
not by its name (`lib/yeah-risk.el:106`). The third debt of this model is
that the network is not a capability of the code: there is no risk of the
network in the vocabulary, and a tool that comes from a server outside the
kernel declares no risk at all, so the rule asks about it as about any other
tool that changes the world (`lib/yeah-risk.el:106`). The separation the
model promises is the separation between the tools that only look and the
tools that change the world, and it is kept; what the code has not got is a
capability of its own for the network. The two debts of wave 76 stand where
they stood: the canonical workspace path is not a boundary of the kernel, and
a credential that a command read is in the log. The map of what is protected
and what is not is `docs/AGENT-SAFETY.md`.*

## 9. Product and interface

`M-x yeah` opens the service placement; the attached placement stays
reachable as `yeah-attached', the development path and the fallback when the
service cannot start.  The primary deployment is also driven through ACP/MCP
clients and orchestrators against a service Emacs.
The editor side of the service and the attached placement use the same
person-facing transcript: `yeah-ui.el` projects the canonical events,
`yeah-journal.el` renders that projection as a read-only outline-structured
buffer, and `yeah-compose.el` owns the separate multiline prompt. The
attached driver is `yeah-product.el`; the service driver and its ACP mapping
are `yeah-service-ui.el`. The transcript shows streamed text, reasoning
visibility, tool calls and results, approvals, diffs, usage, errors, child
work and cancellation state. Incremental updates replace only the changed
block and preserve the reader's position.

Semantic faces inherit the active theme. `nerd-icons` and `markdown-mode`
are optional adapters: icons never replace the readable state text, and
plain text remains a complete baseline. `yeah-approval-ui.el` and
`yeah-diff.el` own the approval and read-only preview surfaces, and the
question of the permission is asked in one place: the shared approval view,
which both the attached and the service path open (claim
`one-approval-surface`). The preview is a read-only text diff, not the full
`diff-mode` surface.

Emacs UI libraries are adapters, not kernel dependencies. magit-section,
transient, tabulated-list and the user's completing-read framework are
preferred to custom replacements when they reduce UI code.

Installation targets a clean supported Emacs with one documented action.
Development tools such as mathc and Nix are never runtime dependencies.

## 10. Verification and success

There are four verification levels:

1. **Unit:** pure transitions, validation, projections and helpers.
2. **Contract/canary:** the failure classes and invariants named by claims,
   each with a control that can make the check fail.
3. **Integration:** real gptel versions, process/protocol round trips,
   restart/recovery and the complete coding scenario.
4. **Live/evaluation:** pinned real providers, comparative tasks against
   opencode/pi and Emacs-native tasks.

The fixed-point scenario — Yeah repairing a Yeah canary and producing a
reviewable commit — is the flagship integration test. Long-session recovery,
responsive cancellation and clean-Emacs installation are release gates.

## 11. Non-goals

- a second kernel in another language;
- a terminal or web UI before the interactive vertical slice works;
- advice-based modification of gptel internals as an architecture;
- destructive compaction or snapshots replacing the journal;
- unrestricted evaluation presented as safe;
- a plugin ecosystem duplicating the tool and skill registries;
- telemetry, provider lock-in or mandatory cloud-only operation.

## 12. Research references

Shallow research clones are kept outside this repository under
`../emacs-agents-research/`. The useful conclusions are:

- **karthink/gptel-agent:** declarative agents, interoperable skills and a
  strong compaction prompt; not its destructive buffer compaction.
- **beacoder/gptel-agent-harness:** concrete gptel failure classes,
  completion nudges, token calibration and Plan/Build behavior; not its
  advice-based coupling to gptel internals.
- **punzik/emacs-agent:** tick-based editing, output artifacts, bounded
  steering/pending input, frozen configuration, replay validation and honest
  documentation of limitations; not unrestricted evaluation as a safe tool.
- **xenodium/acp.el** and the ACP specification: protocol references only;
  agent-shell, Claude Code clients, aidermacs and ECA clients are not
  in-Emacs harnesses and are not architectural models for the kernel.
