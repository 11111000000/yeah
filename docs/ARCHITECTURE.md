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
cancellation, approvals and protocol errors.

A provider history that cannot be replayed safely is not silently repaired.
The session becomes explicitly non-replayable and further execution stops.

### D2 — Yeah owns its execution state machine

Yeah does not build its correctness on advice to gptel internals. gptel owns
HTTP and provider serialization; Yeah owns run state, tool settlement,
permissions, cancellation and recovery.

The number of states is not an invariant. The invariants are valid
transitions, once-only settlement, bounded waiting and a recoverable terminal
state. Four failure classes are mandatory checks: malformed tool arguments,
exceptions in handlers, duplicate asynchronous callbacks and nil/non-string
tool results.

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

### D5 — Buffer edits use optimistic concurrency

Every read that can lead to an edit returns the buffer's
`buffer-chars-modified-tick`. An edit requires a current tick and exact old
text/ranges. All ranges are validated before mutation; edits apply bottom-up;
a logical edit is one undo step; a no-op does not add undo history.

Stale input is rejected and reread. The agent never guesses offsets after the
user or another tool has changed the buffer.

### D6 — Large output becomes an artifact; context is calibrated

Tool output has explicit limits. Oversized output is written with private
permissions below Yeah's data directory; the model receives a bounded excerpt,
an absolute artifact reference and truncation metadata.

Context estimates start with a documented heuristic (including CJK-aware
counting) and are calibrated against provider-reported usage. Compaction is
an asynchronous model operation that commits only a complete, nonblank
summary. Its source events remain in the journal.

### D7 — The human is an asynchronous master

Steering is delivered at a batch boundary, never halfway through a tool batch.
Pending input is bounded, persisted and recovered only deliberately.
Cancellation stops further settlement and managed processes where possible;
it does not pretend to roll back arbitrary effects or kill every descendant.

Completion nudges are bounded, visible events. They ask the model to verify
completion criteria instead of stopping prematurely; they are not an infinite
hidden loop.

### D8 — Agents and skills are declarative

Agent presets live in Markdown or Org files with metadata: name, description,
model, allowed tools and system prompt. Skills use the agentskills.io layout
and compatible well-known directories where practical.

A sub-agent has a child run context, an explicit parent event, a restricted
tool set, a depth limit and a budget. Its intermediate events remain
inspectable; a summary alone is not an audit trail.

### D9 — Plan and Build are permission profiles

Plan mode is a read-oriented rule profile. Build mode enables the normal
approved effect set. Switching modes is a journal event. PlanExit is an
approval operation, not a second execution engine.

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
          \__________________ Session API / Run Controller __________/
                                  |
             +--------------------+--------------------+
             |                    |                    |
       Model adapter        Tool registry        Policy / approvals
       (private gptel)    (typed, validated)    (rules as data)
             |                    |                    |
             +--------- Execution scheduler -----------+
                       shared/exclusive, once-only,
                       cancellation, deadlines
                                  |
                    Append-only versioned event journal
                                  |
             +--------------------+--------------------+
             |                    |                    |
        Model context        Read models/UI       Session index/cost
                                  |
                 attached / service / batch placements
```

### Run Controller

A run has an explicit context containing at least its ids, session, model
adapter, registry, policy, answerer, cancellation token, budgets, clock and
event sink. Registries and permissions must not be implicit process-wide
state shared by unrelated runs.

The controller is the only component that advances the run. UI, protocols and
tests submit commands to it; they do not reproduce its transitions.

### Tool contract

A tool declaration contains:

- stable name and human/model description;
- JSON-compatible input schema, required and optional fields;
- handler and synchronous/asynchronous shape;
- risk/capability classification;
- shared/exclusive or resource-lock declaration;
- timeout and output limits where applicable.

A result is structured: success/failure, content or typed error, truncation
information and artifact references. Tool errors are values for the model and
events for the journal; they do not wedge the run.

### Event envelope

The exact schema is versioned. At minimum:

```text
schema-version, event-id, session-id, timestamp, type, payload
run-id, turn-id, tool-call-id, parent-event-id   (when applicable)
```

Payloads are typed per event. Unknown types and unknown replay-relevant
provider fields fail closed. Writers validate before append. Readers detect
truncation/corruption rather than silently dropping records.

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
true. The honest limits stand: the bridge has so far been checked only
against a stub program, and the stdio wire server answers one request at a
time.

## 8. Security model

The model, repository instructions, fetched text and tool output are
untrusted inputs. Security is capability-based:

- canonical workspace paths and explicit outside-workspace permission;
- separate read, write, process and network capabilities;
- once/session/project/global approval scopes;
- deny-by-default headless policy;
- bounded time, tokens, output, pending input and child depth;
- no secret files or credentials in logs, examples or test fixtures;
- no claim that regex/whitelist evaluation is a complete sandbox.

General untrusted evaluation, if ever offered, requires a separately designed
process boundary and its own adversarial verification.

## 9. Product and interface

`M-x yeah` currently opens the attached placement; the primary deployment
is driven through ACP/MCP clients and orchestrators against a service Emacs.
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
`yeah-diff.el` own standalone approval and read-only preview surfaces;
wiring one approval question into both placements remains open, so neither
path may claim that the other is its UI.

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
