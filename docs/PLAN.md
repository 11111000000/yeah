# PLAN — where this is, what comes next, and what is open

> This document is written for the next session: for an agent that will
> pick the work up without the history that produced it. It says what the
> project is, what it believes, what has been done, what is next in the
> order the plan fixes, and which questions are not the agent's to
> answer.
>
> The machine's own state is in `spec.json` and in the map
> (`./scripts/dev map`). This document is the part a map cannot carry:
> the reasoning, the order, and the open questions.

## 1. What the project is

Yeah is an Emacs Lisp agent harness. The user's Emacs session is itself
the runtime of the agent: there is no sidecar process and no
client/server split. The kernel is Elisp, the model is reached through
`gptel`, the tools are Elisp functions, and the session log is
append-only JSONL.

The harness has three faces, and they are one codebase: a REPL for a
person inside Emacs, an ACP agent that Zed or JetBrains can host, and an
MCP server that publishes the `emacs__*` tools to other agents.

## 2. What it believes

Four claims, and each can be false:

- **H1 — a platform.** Emacs is dying as a desktop application and
  living as an agent runtime: a language, an editor, a process model, an
  RPC surface and a cross-platform binary in one program — including
  Android and the browser.
- **H2 — a harness without a human.** The harness is a runtime driven
  from outside. A person is one master among several, not a required
  one. The consequence was decided by the owner: the kernel is the same
  in every placement, and what differs is *who answers* a question when
  nobody is at the keyboard — the person, or the policy.
- **H3 — the agent works in Emacs, not around it.** The tools are the
  editor's own; the undo is the editor's own; the log is a file on the
  disk. The agent acts on real buffers, real magit and real project.
- **H4 — one runtime, many places.** The same harness on a phone, in a
  browser, on a desktop, and inside editors that speak ACP.

**Parity is the aim.** Not worse than pi or opencode in everything that
works there today, at the same quality, from the point of view of the
person using it. There is no ratio and no score: the reference
implementations were read, and their code is the checklist.

**The method is math-coding v4, and it is strict about itself.** A claim
is a statement about this repository with a scope, a requirement that can
close it, a falsifier, a register, and a *control*: the command that
breaks the subject and must make the check go red. A claim whose control
has never bitten is not established, and the map says so. Unknown is
never read as pass. The waves in `waves/` are the units of work, each with
an intent, a check, a promise and the strongest objection against it.

## 3. Where the work stands

The closed waves and what they delivered:

| Wave | What it delivered |
|---|---|
| 01 | the standing specification: the third version's corpus removed, the specification and the waves in their place |
| 02 | the turn: the model is called through gptel, its tool calls are parsed and dispatched |
| 03 | the scheduler: the tools of one answer run together, an exclusive one runs alone, the batch is a barrier |
| 04 | the vocabulary of the log: every record is a declared event with the declared fields |
| 05 | the interface: the view is read from the event stream and from nothing else |
| 06 | the approvals: once, always, reject; a run with nobody answers by policy |
| 07 | the sandbox: the body of a form is confined before a single form is evaluated |
| 08 | the context: the summary is written by the model, the old tool outputs are pruned |
| 09 | the sessions: the index of a project, the tree of a session, the price of a run |
| 10 | the guards of a run: a failing call is retried, a hanging call is cut, a repeated call is stopped |

The kernel at this moment: twenty-one modules, no third-party dependency
(`cl-lib`, `json` and `ring` only), a byte-compile that is clean with no
warnings, 104 ERT cases, and seventeen canaries — all green.

The transport was verified against the real thing: gptel 20251007.257
installed, a real model asked through `yeah-gptel-request` (MiniMax,
OpenAI-compatible, the fastest model the endpoint offers), HTTP 200 and
the answer. The live check lives in `tests/live/live-model-call.el` and
takes the key from the environment; **no key is ever written into this
repository**.

## 4. What comes next, in the order the plan fixes

Each wave is a unit of work with a promise. The order is by dependency,
not by beauty.

| Wave | What it promises |
|---|---|
| 11 — провод | ACP speaks JSON-RPC over stdio, the MCP server publishes the registry over stdio, and the MCP client lets Yeah use the tools of other agents |
| 12 — размещения | the same kernel runs attached, in its own Emacs as a service, and in batch; the placement is not visible in the log |
| 13 — под-агенты | a sub-agent runs in its own session with its own context and restricted permissions, and its result comes back |
| 14 — продукт | the harness installs, serves, and explains itself to a person |

The order matters in one place: wave 11 comes before wave 12, because a
placement without a wire is a placement with nobody in it.

## 5. The variants that are open

These are decisions about meaning, not about mechanism. They are the
owner's to make; the plan assumes the first and leaves the rest.

1. **The surface of the harness.** Does the familiar interface live
   inside Emacs (a chat buffer with the shape of the harnesses people
   know), outside it (the web and the terminal that opencode and pi
   have), or both? The plan assumes the kernel serves both and the
   interface is a client of it.
2. **How much the agent may do without a person.** The rules decide
   today, and the default is to refuse. The variant: which operations
   are allowed unattended by default — reading, editing a scratch file,
   running a command — and which always need a person.
3. **What the model may write.** The PTC sandbox confines a form to the
   tools of the registry and a small core. The variant: whether the
   model may also write plain Elisp that is *read* rather than run
   (a macro, a piece of configuration), and what the boundary is.
4. **The trust of the service mode.** In the attached mode the agent
   runs with the rights of the person. In the service mode it runs as a
   daemon. The variant: what the service mode is allowed to reach —
   the person's buffers through `emacsclient`, or nothing of theirs.
5. **The packaging.** The kernel needs only an interpreter, and the
   interface needs more. The variant: what is shipped — a package, a
   tarball, or an `emacs -Q` script that fetches what it needs — and
   what a phone is expected to install.
6. **The measurement.** The method measures the method; nobody has
   measured the harness. The variant: the experiment that would decide
   whether an Emacs Lisp agent is as good as a shell one — the same
   task, two arms, the same rubric.
7. **The licence of the ecosystem.** The kernel is Apache-2.0 and
   depends on nothing outside Emacs. The variant: what happens to that
   if the sandbox turns out to need `sandbox.el`, which is GPL.

## 6. How to work in this repository

```sh
./scripts/dev map                 # the state: claims, states, uncovered
./scripts/dev next                # the next unit of work, one item
./scripts/dev byte-compile-all     # the kernel compiles clean, no warnings
./scripts/dev ert tests/unit/*.el  # the unit tests
./scripts/dev check tests/checks/* # the canaries
./scripts/dev run                  # the method executes the checks and binds the evidence
./scripts/dev gate                 # run, then map; the exit code is the verdict
```

The rules that the repository holds itself to:

- A wave closes only when its promises are met, and a promise is a claim
  in `spec.json`.
- A claim carries a **control**: the command that breaks the subject and
  must make the check go red. If the control changes nothing, the map
  says "the control changed nothing in the tree" — and the claim is not
  established. That message is the most useful thing the method says.
- The evidence is bound to the content of the files: change a file and
  the proof of the claim about it is stale.
- The scope of a claim names the files the claim is about *and* the
  instrument that checks it, so that changing either invalidates the
  proof.
- A check that cannot fail is a comment. The canaries in `tests/checks/`
  are the checks; the claims in `spec.json` are what they are bound to.

## 7. The traps that were paid for

They are in `ELISP_BEST_PRACTICES.md` §11, and they are worth knowing
before writing a line of kernel code:

- A `let` does not shadow the **cell of a function** in Emacs Lisp. A
  form that calls `read` inside a sandbox calls the built-in `read`, not
  the tool of the registry. The tools are reached through one function
  and a rewrite, and the names of the tools are data.
- `&key` is a `cl-lib` extension: in a plain `defun` it is either
  malformed or wrong. Use `cl-defun`.
- `write-file`'s second argument is `VISIT`, not the content. A file
  written that way is empty, and a check that reads it will say that the
  thing under test is empty.
- Emacs loads a byte-compiled file **in preference to a newer source**.
  A stale `.elc` next to a modified source makes every control blind, and
  `scripts/dev` removes the bytecode before it loads anything.
- `process-filter` takes one argument in current Emacs; the pending
  output is read by calling the filter with an empty string.
- `run-with-timer` takes three arguments: the time, the repeat, the
  function.
- A timer that is started inside another timer is only reached by a
  later turn of the event loop. A check that waits must pump the loop in
  steps, not sleep through it.
- The filter of a process receives the output as its second argument. A
  filter that reads the output *from the filter* calls itself for ever,
  and the nesting depth is the symptom.
- `&key` is an extension of `cl-lib`: in a plain `defun` it is either
  malformed or wrong. Use `cl-defun`.
- A model that reasons sends its thinking as its own chunk, before the
  answer. The turn waits for the answer and ignores the thinking, and
  the fake in the checks speaks the way gptel speaks.

## 8. If you continue

Read in this order: `AGENTS.md`, this document, `docs/ARCHITECTURE.md`,
then `./scripts/dev map` and `./scripts/dev next`. Take the wave that
`next` names. Write the module, write the canary, give the claim a
control that bites, and close the wave only when the method says its
promises are met.
