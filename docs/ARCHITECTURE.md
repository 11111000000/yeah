# ARCHITECTURE — the target shape of Yeah

> **Status: target, not current.**
>
> This document says what Yeah is being built to become, and what "done"
> means for it. It is not a description of the code: `lib/` is the code,
> `spec.json` says what is true of the code today, and `waves/*.json` are
> the units of work. This document says what the whole thing is *for*, so
> that a change can be judged against an intention and not only against
> a test.

## 1. The aim, stated as parity

Yeah is an Emacs Lisp agent harness. It must be **not worse than the
reference harnesses — pi and opencode — in everything that works in them
today, at the same quality, from the point of view of the person using
it.**

That is the whole definition, and it is deliberately not a number. There
is no ratio to compute and no score to optimise. The reference
implementations are readable, and their code is the specification of what
"works there": the loop over model turns, parallel tool calls, a typed
event stream, approvals with remembered answers, compaction by a model
call, file checkpoints, resumable and branching sessions, cost accounting,
retries and timeouts, background jobs, sub-agents, an MCP client, an ACP
agent side, a server mode, a user interface, and an installation.

Parity means all of that, working as well as it works there. The
reference code was read for this document, and the matrix in §5 is taken
from it, not from their documentation.

## 2. The four hypotheses

- **H1 — a platform.** Emacs is dying as a desktop application and living
  as an agent runtime. It is the only mature program that is at once a
  programming language runtime, an editor, a process model, an RPC
  surface, and a cross-platform binary — including Android and the
  browser.
- **H2 — a harness without a human.** The harness is not an interface
  inside Emacs. It is a runtime driven from outside; a human at the
  keyboard is one master among several, not a required one.
- **H3 — the agent works in Emacs, not around it.** The agent's tools are
  Emacs functions, its state is Emacs state, and it acts on the user's
  real buffers, magit, project and org-mode. A shell agent pays a
  process boundary and a serialisation for every one of those.
- **H4 — one runtime, many places.** The same harness runs on a phone, in
  a browser, on a desktop, and inside editors that speak ACP.

H2 and H3 are the load-bearing ones, and they pull in opposite
directions, which is why §6 exists.

## 3. Three planes

```
  plane 1 — the kernel        pure Elisp: no UI, no transport, no policy
      lib/yeah-state.el   the twelve states
      lib/yeah-loop.el    the eighteen transitions
      lib/yeah-tools.el   the tool registry
      lib/yeah-perm.el    the permission rules
      lib/yeah-session.el the append-only log
      lib/yeah-compact.el compaction as a projection
      lib/yeah-undo.el    the undo boundary
      lib/yeah-codes.el   programmatic tool calling
      lib/yeah-subagent.el  the delegation API
      lib/yeah-shell.el   the human REPL
      lib/yeah-gptel.el   the transport bridge

  plane 2 — the transports   one conversation, spoken by several masters
      lib/yeah-acp.el     ACP, agent side: JSON-RPC 2.0 over stdio
      lib/yeah-emcp.el    MCP server: the emacs__ tool namespace
      lib/yeah-gptel.el   the model transport, through gptel

  plane 3 — the runtime      where Emacs lives, and who is watching
      attached   a session a person is using
      service    a dedicated Emacs, driven by protocol clients
      batch      one process, one task, no persistence
```

### The invariant

**The kernel does not know who is driving it.** It is handed a prompt and
it produces records; it never opens a socket, never asks a question it
cannot record, and never assumes that a human will answer.

Everything else follows:

- A tool is a plain Elisp function with a declared input shape. It is
  called the same way from the human REPL, from an ACP client and from an
  MCP client.
- A session is an append-only log. Every master sees the same log.
- A permission decision is a *record*, not a question. The kernel never
  blocks waiting for an answer; it emits a decision request and
  continues when the policy answers it.

## 4. The three masters

| Master | Envelope | What it needs from the kernel |
|---|---|---|
| a human | the REPL, and the ordinary Emacs UI | a readable transcript, a place to approve, and nothing that breaks the editor |
| an ACP client | JSON-RPC 2.0 over stdio | sessions that can be cancelled, prompts that stream, results that arrive as messages |
| another agent | MCP over stdio: the `emacs__*` namespace | tools that are named, described, argument-checked and safe to call from outside |

The human is the odd one out: the other two are programs with no
patience and no window. They need a session id, a way to cancel, and an
honest answer when something cannot be done. The human needs a face.

## 5. The parity matrix

Read from the reference implementations. "Yeah" is the state of this
repository today.

| Capability | opencode | pi | Yeah |
|---|---|---|---|
| Loop over model turns, parsing tool calls | `session/prompt.ts:1081` | `core/agent-loop.ts:526` | present: `lib/yeah-turn.el` — the tick, the dispatch, the log, and the model asked again |
| Parallel tools from one assistant message | FiberSet per tool call | shared/exclusive scheduling with a per-batch barrier | absent: one `awaiting-tool` state |
| Typed events and a stream for the interface | 12 part types, typed bus, SSE | 13 event types, own EventStream | present: `lib/yeah-events.el` — the vocabulary of the log, and a record that is refused when it is not of a declared type |
| Approvals: reply kinds, remembered answers, no-human mode | once, always, reject; headless auto-answer | tool-declared tiers, modes, fails closed | only allow, deny, ask; ask raises |
| Compaction by a model call, plus pruning of old tool output | hidden compaction agent, fixed template | five methods, own tokenizer | deterministic placeholder |
| File checkpoint and undo | shadow git, revert restores blobs | absent: context branch only | native Emacs undo — better than both, for buffers |
| Sessions: index, tree, resume, revert | SQLite, projections, fork | JSONL, branching | append-only log, no index |
| Token and cost accounting per session | per step, message, session | same, plus per-tool latency | absent |
| Robustness: retries, timeouts, deadline, loop guard, background | all five | all five | absent |
| MCP client for foreign tool servers | present | present | absent; we are a server |
| ACP agent side | 13 methods | present | 4 handlers, no process |
| Server mode and headless run | serve, run, acp, mini | CLI, ACP, RPC | absent |
| Sub-agents with their own session | task tool with a child session | task tool with a branch | stub |
| Interface, installation, documentation for people | TUI, web, desktop | TUI, web, extensions | a REPL buffer |

Fourteen rows. Three are now filled — the turn, the scheduler and the
event vocabulary — and eleven are still empty. That is the size of the remaining work, and it is the plan:
`waves/` is this table, one unit of work per row, ordered by dependency.

## 6. The tension between H2 and H3, and how it resolves

**The tension.** H3 says the agent acts in the user's Emacs: real
buffers, real magit, real project. H2 says the harness must run without a
human, which means it must be a runtime that can be driven from outside,
which means it must not be entangled with one person's editing session.
A single Emacs process cannot be both the user's editor and a service for
other clients.

**How the references solve it.** They never try. opencode's agent is
always a separate process, and the editor is a client of it; pi's agent
is a process with several modes. Neither shares an address space with the
user's editor, which is exactly why neither is blocked by a single
thread.

**How Yeah resolves it.** Three placements of one kernel:

| Placement | Who lives there | Single-threading | Cost |
|---|---|---|---|
| attached: the agent in the person's session | the same Emacs | agent work blocks the editor if it waits in the main loop | least: the agent works on live buffers |
| service: the agent in its own Emacs | a separate process, clients outside | no problem: the runtime has its own main loop | the agent does not see the person's buffers directly — but it reaches them through `emacsclient`, that is, as a tool |
| batch: one process, one task | the same Emacs | no problem | no state between runs except the log |

**The rule that follows.** The kernel must run in all three, and no
placement may block the main loop. Heavy or isolated work goes to
another Emacs: Emacs already speaks to another Emacs over
`emacsclient`, so the second process can act on the first one's buffers.
The agent in its own Emacs, with the user's Emacs as one more client, is
the form that satisfies H2 and H3 together — and it is precisely the
form in which a second Emacs gets opened.

**Threads, and what they are good for.** Emacs has real threads
(`make-thread`), and `lexical-binding` is `t` by default since Emacs 30,
which makes lexical variables private to a thread while globals stay
shared. Threads buy concurrency of *waiting*: a slow process or a slow
network read can proceed while the main loop stays alive. They do not buy
isolation: a thread shares the address space, sees the user's buffers
and secrets, and a crash in it takes the editor down. Note also that the
branch API of Emacs 29 (`make-branch` and friends) is **not present in
Emacs 30** — verified on the Emacs 30.2 this repository targets — so no
plan may depend on it.

The division is therefore: threads for waiting, another process for
isolation, and a scheduler for parallel work.

## 7. What the model transport actually gives us

The transport is gptel, and reading its source changes two assumptions.

**The model call does not need a thread.** gptel's request is
asynchronous and its callback is invoked from the main loop while the
editor stays usable. So the rule "the main loop never waits" is
satisfiable with gptel as it is. What is forbidden is a *blocking* call
inside a tool body — the thing `ELISP_BEST_PRACTICES` §4.1 already
forbids.

**gptel executes tool calls one at a time.** Its dispatch loop is
sequential, with an opt-in `async` flag per tool. So parallel tool
calls are *ours* to build: the registry's spec needs a concurrency field
of the kind pi has (`shared` or `exclusive`), and the scheduler needs to
exist. gptel will not provide it.

**Two more facts, both uncomfortable.** gptel has its own tool-call
acceptance UI, with accept, reject and steer; and the hook
`gptel-fsm-handlers`, which `lib/yeah-gptel.el` registers, **no longer
exists** in current gptel — the current hooks are
`gptel-prompt-transform-functions`, `gptel-pre-tool-call-functions` and
`gptel-post-tool-call-functions`, and gptel now has an internal state
machine of its own. So: two approval UIs must not both exist, and the
third hook of Yeah is currently dead. Both need their own claims.

## 8. H3, restated

The earlier form of this hypothesis was "the agent generates Elisp". The
reference code says that is the risky form: neither opencode nor pi lets
the model write free-form code. Their tools are declared with schemas,
and code execution is an *option* — opencode has a sandboxed code mode
that calls tools in parallel inside it, pi has `eval` as one of its
tools.

Parity says something sharper: a shell agent can write and run code, so
Yeah must be able to as well, and must do it inside Emacs. The shape
that satisfies both safety and capability is:

1. a **declared, typed vocabulary** of tools, with input shapes and
   concurrency modes;
2. **programmatic tool calling** on top of it: one form that performs
   several operations in one round trip, which is what the code mode of
   opencode does and what `lib/yeah-codes.el` is for;
3. the form runs inside a **boundary** — a static analysis of the free
   symbols of the form, and eventually `sandbox.el` — so that a form
   cannot reach the host.

The claim `ptc-sandbox-restricts-model-code` is refuted today, because
the whitelist gates the *name* of the binding and not the body inside
it. Until that is repaired, H3 has no safe implementation: the one
mechanism that would make an Elisp agent competitive with a shell agent
is also the one that is currently unsafe.

## 9. The strongest objection to this architecture

*An agent that works in Emacs needs a bootstrap that Python and shell do
not need, and the bootstrap is the whole difference between a runtime
that runs on a phone and one that needs a package manager on the phone.
Until the bootstrap is solved, H3 is a preference and H4 is a hope, and
the only parts that work are the ones Emacs already did: text, buffers,
files and a shell.*

**What would refute it:** an agent on a phone, running the same task
through Emacs Lisp and through shell, where the Emacs arm needs a
package manager and the shell arm does not. The architecture is wrong if
the bootstrap is the bottleneck in every run, because the bootstrap is
the part that does not travel.

This objection lives on the plan, in `wave-14`, because the method holds
that the dialectic belongs to the unit of work.

## 11. Two defects of the tool, found by using it

**The wave queue is sorted lexicographically, not numerically.** `mathc
next` reads the files of `waves/` and sorts their names as strings, so
with ten waves or more it points at `wave-10` before `wave-2`, and the
agent is led to the wrong work. The waves here are therefore named
`wave-01` … `wave-14`, and the numbering is padded on purpose. The same
defect affects the method's own repository, which has twenty waves.

**The build of the method is a moving target, so the build is named.**
`mathc --version` prints the hash of the binary's own bytes, and two
different binaries of the same version must never be confused. A claim
proved by one build is not proved by another. On 2026-11-09 a build of
the method stopped being able to establish any claim at all — including
in the method's own repository, where the verdict became `unknown` with
every claim inconclusive — because it compared the digest of the subject
*after* putting the tree back, so a control that broke the subject and
was faithfully restored looked as if it had broken nothing. The fix was
to take the fingerprint immediately after the control and before both the
check and the restore, and the reason it matters is general: the residue
of a control is the proof that it did something, so asking after the
cleanup asks the wrong question. The evidence in `.math/trail.jsonl` is
bound to the content that ran, not to the build that ran it, so a claim
proved green by one build stays proved until the subject moves; but a
build that cannot establish anything will report every claim as
inconclusive. When the method changes under us, the right response is to
name the build, not to rewrite the claims.

**A directory with no specification is no longer green, but a claim
without a check is still allowed.** `mathc add` refuses a claim with no
requirement, and accepts one whose check does not exist yet; the map then
says "the check is not proven able to fail". The fourteen promises of
this plan are in that state on purpose — they are plans, and a plan is
not an uncertainty (law A17). The price is that they cost nothing until
their subject appears.

## 12. Out of scope, on purpose

- A GUI that imitates another harness. The interface is one master among
  several; it comes last, and it should look like whatever is familiar,
  not like the kernel.
- A second runtime. The kernel is Elisp, and the decision to keep it so
  is in the aim and the claims.
- A plugin ecosystem beyond the tool registry and the MCP client. The
  registry is the extension point; anything else is a second way to say
  the same thing.
