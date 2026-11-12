# ELISP_BEST_PRACTICES — Yeah v0.1.0-alpha

> Conventions for writing kernel Elisp in this repository. Each rule says
> what to do and, where the rule was learned the hard way, why.
>
> §11 is the trap log: recurring Elisp and packaging errors with minimal
> reproducers. Every entry is added in the same commit that surfaces the
> trap.

## §1. The kernel stays small and Elisp-only

§1.1 — **byte-compile clean.** Every file under `lib/` must byte-compile
with no errors and no warnings under `./scripts/dev byte-compile-all`.
A warning is a failure: the check greps for `Warning:` and refuses.

§1.2 — **one feature per file.** Each `lib/yeah-*.el` provides exactly
one feature, matching the file name. `(require 'yeah-x)` loads
`lib/yeah-x.el`. No cross-file `defun` is allowed; only
`(defun yeah-x-foo …)` or fully-qualified helpers.

§1.3 — **no `require` cycles.** Cycles in the require graph are
forbidden. The graph is visible in `lib/` and in `spec.json`, where each
claim names the files it is about.

## §2. Naming

§2.1 — **prefix `yeah-` on public symbols.** Internal helpers may use
`--` (e.g. `yeah--state-default`), but anything that could be called from
another module uses a single dash.

§2.2 — **defclass slot names use `:kebab-case`.** The plist keyword and
the reader accessor both use `:kebab-case`. `cl-defstruct` is preferred
for records, and `eieio` only for inheritance.

§2.3 — **records are `cl-defstruct` with `:conc-name yeah-x-`.** This
gives `yeah-x-foo` accessors without `defclass` ceremony.

## §3. Errors

§3.1 — **domain errors are `(user-error …)`.** Tool rejections,
permission declines and input validation failures use `user-error`: the
model sees them as a structured tool failure.

§3.2 — **never `(error …)` for expected user-visible conditions.**
Reserve `error` for actual bugs. Anything that "the user could have done
differently" is `user-error`.

§3.3 — **wrap `cl-loop` and `dolist` in `condition-case`.** A tool body
must never let an exception escape; the wrapper catches `error`,
`user-error` and `(signal 'cl-assertion-failed …)` explicitly.

## §4. Process / IO

§4.1 — **use `make-process` for any subprocess.** Never call
`shell-command`, `async-shell-command` or `call-process` from inside a
tool body. The kernel's process table is a single source of truth for
live subprocesses.

§4.2 — **filters return either a string or an `(error …)` form.** The
sentinel `'(error "...")` is the only way a `:filter` function reports
failure; this is the convention used by `jsonrpc.el`.

§4.3 — **set `:coding` to `'(utf-8 . utf-8)` for any process that may
carry non-ASCII output.** The default Emacs coding on many platforms is
`iso-latin-1`, and that is the wrong default for LLM output.

## §5. JSON

§5.1 — **use `json-parse-string` and `json-serialize`.** The built-in
JSON parser handles our use cases. `jsonrpc.el` exposes its own plist
shape, but inside Yeah plists are fine — we convert to and from alists at
the wire boundary only.

§5.2 — **JSON keys are `kebab-case` over the wire and in Elisp.** No
camelCase at any layer. This is the convention that matches the ACP and
MCP wire shape and avoids constant re-keying at the boundary.

§5.3 — **`json-parse-string` with `:object-type 'plist` produces keyword
keys, at every level.** `(plist-get parsed :result)` is right;
`(plist-get parsed 'result)` is nil, and so is a nested lookup with a
plain symbol. The same holds for the alist object type: its keys are
symbols, so `(assoc 'examples json)` is right and `(assoc "examples" json)`
is nil.

## §6. Tests and checks

§6.1 — **ERT tests live in `tests/unit/test-*.el`.** The file name is
`test-<module>.el`, and the test symbols are named
`yeah-<module>-<aspect>-<case>`.

§6.2 — **the canaries live in `tests/checks/` and they must fail today,
or fail when the subject is broken.** A unit test asserts that a module
behaves; a check asserts that the module is what the specification says
it is, and it is bound to a claim in `spec.json`. The control of a claim
is the command that breaks the subject and must make the check go red; a
control that has never bitten proves nothing, and the map says so.

§6.3 — **a check that fails by crashing is not a check that bites.** The
method reads the exit code of a check under its control: `1` means the
check bit, `0` means the check cannot see the subject, and anything else
(exit `2`, `3`, `127`, or an Emacs batch that dies with `255`) means the
check did not run. Break the subject so that the *assertion* fails, not
so that the file stops being readable.

## §7. Performance

§7.1 — **don't optimise until the map is green.** Premature optimisation
in `lib/` is forbidden: the kernel is small, and a fast module that is
not the module the claims are about is a loss.

§7.2 — **measure with `elp` or `benchmark-run`.** Wrap optimisation
candidates in `(benchmark-run 1000 …)` and record the result; the
load-bearing number is the regression, not the absolute time.

## §8. JSON-RPC / ACP / MCP

§8.1 — **the `jsonrpc.el` connection object is the only thing that
crosses the ACP / MCP boundary.** Do not write `(make-network-process …)`
directly to talk to a remote agent; route through
`jsonrpc-process-connection`.

§8.2 — **`emacsclient` calls go through `make-process`, not through
`call-process`.** Even a one-shot `emacsclient -e '(…)'` is a
`:coding`/`utf-8` trap if you let `call-process` coerce the output;
`make-process` + `:filter` gives the result string back in the buffer you
control.

## §9. Concurrency

§9.1 — **the main loop never waits.** This is the rule that everything
else in this section serves. A wait is a process filter, a timer, or a
state of the machine — never a call that blocks the loop. The person
using Emacs must be able to keep typing while the agent works, whether
the agent runs in their session or in its own.

§9.2 — **threads are for waiting, not for isolation.** Emacs has real
threads, and `lexical-binding` is `t` by default since Emacs 30, so
lexical variables are private to a thread while globals stay shared. Use
a thread for a slow read or a slow process. Do not use one to isolate
the agent: a thread shares the address space, sees the buffers and the
secrets of the person, and a crash in it takes the editor down.

§9.3 — **isolation is a process, and the process is another Emacs.**
Heavy work, work that must not touch the person's session, and work
that runs unattended belong in a separate Emacs. Emacs already speaks to
another Emacs over `emacsclient`, so the second process can act on the
first one's buffers — as a tool, not as a trespass.

§9.4 — **do not plan on the branch API.** `make-branch`,
`clone-branch` and `terminate-branch` were in Emacs 29 and are **not in
Emacs 30** — verified on the Emacs 30.2 this repository targets. A plan
that depends on them is a plan on an API that does not exist.

§9.5 — **accept-process-output is the only blocking call.** All
subprocess IO returns to the loop through a process filter; the loop
itself never blocks on user input — that is the `awaiting-user-input`
state.

## §10. The method

§10.1 — **the specification is `spec.json`, the plan is `waves/*.json`,
and the evidence is what the checks produce.** There is no decision
corpus: a record of what changed lives in git, and a rule lives while its
subject lives.

§10.2 — **every claim carries a control, and the control is a command
that breaks the subject.** A claim without a control is not refused, but
the map says that its check is not proven able to fail. Declare it
anyway: the map shows whose check has been shown to fail and whose has
not.

§10.3 — **the uncertainty budget is finite and visible.** Three
unanswered claims at a time is the price this project agreed to pay. When
it is spent, the options are to find a check, to ask for authority, or to
stop.

§10.4 — **the exit codes are the method's scale.** `0` pass, `1` fail,
`2` blocked (input error), `3` unknown. `unknown` is never read as
success, and a waived claim is never read as a passing one.

## §11. Trap log (Elisp)

> Each entry is added in the same commit that surfaces the trap; the date
> is the commit date.

### §11.1 — know whether a variable is special before choosing `let` or `setq`

- **Date:** clarified on 2026-11-10 while making gptel requests private.
- **Rule:** `let` dynamically rebinds a special variable (one defined by
  `defcustom` or an initialized `defvar`) and restores its previous value on
  exit. This is the correct way to scope configuration without mutating
  global state. gptel explicitly documents it for `gptel-backend`,
  `gptel-model`, `gptel-use-tools` and `gptel-use-context`.
- **Trap:** an uninitialized forward declaration such as `(defvar x)` must
  not be relied on to make test/fake bindings special in every context.
  Declare external variables with an initial value, for example
  `(defvar gptel-model nil)`, when the local module needs dynamic bindings
  before the real library is loaded. `special-variable-p` can verify the
  declaration; tests should also verify the observed value.
- **Do not** replace request-local `let` bindings with global `setq`: that
  leaks configuration into unrelated sessions. Use `setq` only when global
  mutation is actually intended.

### §11.2 — a stale `.elc` shadows a newer `.el`, and Emacs says so while doing it

- **Date:** 2026-11-09 (the math-coding v4 migration)
- **Symptom:** a check that is supposed to fail on a modified source
  passes, and the tree prints
  ```
  Source file ‘…/lib/yeah-tools.el’ newer than byte-compiled file; using older file
  ```
- **Cause:** Emacs loads the byte-compiled file when it exists, even when
  the source is newer. `batch-byte-compile` writes `lib/*.elc` next to the
  sources, so after the first byte-compilation the tests test yesterday's
  code. Every claim whose control modifies a source is blind to it.
- **Fix:** the bytecode is a build artefact, not part of the tree.
  `./scripts/dev` removes `lib/*.elc` before it loads anything, and
  `byte-compile-all` removes it after compiling.
- **Convention:** a check that modifies a source and runs the tests
  proves nothing until the bytecode is gone.

### §11.3 — `write-region` appends whenever `APPEND` is non-nil

- **Date:** 2026-11-09 (the math-coding v4 migration)
- **Symptom:** a control that replaced `'append` with `'overwrite` did not
  truncate the file, and the check that reads the file passed anyway.
- **Cause:** the fourth argument of `write-region` is "append to existing
  file contents **if any**" when it is non-nil. Both `'append` and
  `'overwrite` are non-nil, so both append. Only `nil` truncates.
- **Fix:** pass `nil` to overwrite.
- **Convention:** a control must be read against the documentation of the
  function it breaks, not against what its name suggests.

### §11.4 — `json-parse-string` with `:object-type 'plist` gives keyword keys

- **Date:** 2026-11-09 (the math-coding v4 migration)
- **Symptom:** `(plist-get parsed 'result)` is nil while the parsed value
  prints as `(:result …)`.
- **Cause:** the object type `plist` symbolises the keys of every object,
  at every level, including nested ones. A plist printed as `(:a (:b 2))`
  and an alist printed the same way are different values.
- **Fix:** use keywords with `plist`, symbols with `alist`.
- **Convention:** when a lookup on a parsed document returns nil, print
  the value before changing the code.

### §11.5 — a check that dies with 255 has not bitten

- **Date:** 2026-11-09 (the math-coding v4 migration)
- **Symptom:** a control that appended a state to the state list made the
  check exit `255` (Emacs died while reading the file), and the map said
  "the check did not run" rather than "the check bit".
- **Cause:** the method reads the exit code of a check under its control.
  `1` is a failure, `0` is a check that cannot see the subject, and
  everything else — including `255` — is a check that did not run.
- **Fix:** break the subject so that an assertion fails, not so that the
  file stops being readable. Removing a state from a list that ends with
  the closing parenthesis changes the count and breaks the syntax at the
  same time; swapping two states changes the contract and keeps the file
  readable.
- **Convention:** a check is a claim about behaviour. A control that
  destroys the file destroys the claim too.

### §11.6 — a hook on a variable that no longer exists is not a hook

- **Date:** 2026-11-09 (the parity analysis)
- **Symptom:** `lib/yeah-gptel.el` registers three gptel hooks. Two of
  them exist in current gptel; the third, `gptel-fsm-handlers`, does
  not. `add-hook` on an unbound variable succeeds, the install function
  reports success, and the hook is never called by anything.
- **Cause:** gptel changed its surface: the current hooks are
  `gptel-prompt-transform-functions`, `gptel-pre-tool-call-functions` and
  `gptel-post-tool-call-functions`, and gptel grew an internal state
  machine of its own. A hook that no longer exists cannot fail, and a
  registration that cannot fail is indistinguishable from a working one.
- **Fix:** a hook is a claim about a foreign program, and it needs a
  check like any other: the check must ask the foreign program whether
  the variable is bound, and its control must remove the binding and
  make the check red.
- **Convention:** when registering a hook in a program you do not own,
  assert that the variable exists, and record that assertion as a claim.

### §11.7 — `defun` with `&key` does not bind keyword arguments in this Emacs

- **Date:** 2026-11-12 (the run context of Stage 6)
- **Symptom:** a function defined with `(defun f (&key a b) …)` called as
  `(f :a 1 :b 2)` binds `a` to `1` and `b` to `:b`: the keywords are
  taken as positional arguments. The byte compiler also warns
  "`f' called with 4 arguments, but accepts only 3", and the call fails
  at runtime with "wrong number of arguments" as soon as more than half
  of the declared keywords are passed.
- **Cause:** in the Emacs 30.2 this project is built against, the
  interpreter and the byte compiler compute the arity of a `&key`
  function as if the keys were ordinary required arguments, so the
  keyword convention is never applied. The same lambda list written
  with `cl-defun` works: cl-lib binds the keywords itself.
- **Fix:** write a function with keyword arguments as `cl-defun`, as
  `lib/yeah-runtime.el` and `lib/yeah-gptel.el` already do.
- **Convention:** `cl-defun` replaces the docstring with a generated
  one, so the keyword arguments of a `cl-defun` are documented in the
  comment above it, not only in the docstring.

### §11.8 — `json-serialize` writes `nil` as `{}`, not as `null`

- **Date:** 2026-11-12 (the canonical projection of the placements)
- **Symptom:** a boolean field of the journal reads `{"ok":{}}` where a
  reader expects `true` or `false`, and a reader that tests the value
  with `(if (plist-get record :ok) …)` sees a failure as a success.
- **Cause:** `json-serialize` treats `nil` as an empty object, because
  `nil` is an empty alist. The symbol `:false` is the JSON false, and
  `:null` is the JSON null.
- **Fix:** write booleans as `t` and `:false`, and read them back as
  `(memq value '(nil :false))` when the value may come from either the
  in-memory result or the journal.
- **Convention:** the journal is a public artefact: what a client reads
  from it must be what the field means.

### §11.9 — `string-match-p` does not update the match data

- **Date:** 2026-11-12 (the agent presets)
- **Symptom:** a function that looks for a header with `string-match-p` and
  then reads `match-end 0` returns a position that belongs to an earlier
  match — or to nothing at all. The first call works and the second one
  does not, which looks like state in the wrong place.
- **Cause:** `string-match-p` returns the position of the match and leaves
  the match data as it was. `match-end 0` then answers about the previous
  match, not about the one that just happened.
- **Fix:** use `string-match` when the match data is needed, and prefer
  `string-prefix-p` when only the beginning of a string is in question.
- **Convention:** a position that a function computes must come from the
  call that computed it, never from the match data of another call.

### §11.10 — `plist-put` mutates the plist it is given

- **Date:** 2026-11-12 (the agent presets)
- **Symptom:** a function that builds a plist with `plist-put` returns the
  values of an earlier call: the name of the first preset is the name of
  every preset.
- **Cause:** `plist-put` changes the list it is given when the property is
  already in it. A literal list in the source is a constant shared by every
  call, so the first call writes into it and every later call reads it.
- **Fix:** build the empty plist with `list`, not with a literal, and
  assign one property at a time: a `setq` with several pairs does not
  promise that the next pair sees the previous one.
- **Convention:** a value that a function returns must be built by that
  call; a constant in the source is not a scratch pad.

### §11.11 — the model names the arguments of a tool; the registry expects positional

- **Date:** 2026-11-12 (the live coding task)
- **Symptom:** every tool call fails with "expected N..M args, got K".
- **Cause:** the model sends named arguments (`:path`, `:offset`, ...), and
  `yeah-tools-call` expects positional arguments in the order the tool
  declared them. The mismatch is invisible in offline tests because the
  fake transports pass positional arguments.
- **Fix:** normalize at the boundary — `yeah-tools-normalize-args` maps
  named arguments to the declared positional order, and a missing optional
  argument keeps its place as nil so that later arguments do not move.
- **Convention:** the tool contract is a contract about order; the model's
  contract is about names. The adapter owns the difference.

### §11.12 — JSON false arrives as `:json-false`

- **Date:** 2026-11-12 (the live coding task)
- **Symptom:** a model that passes a boolean argument is refused with
  "arg N (replace_all) expected boolean".
- **Cause:** gptel parses the model's JSON with `:false-object
  :json-false`, so JSON `false` arrives as the symbol `:json-false`, not
  as nil. The type check then rejects the argument.
- **Fix:** normalize JSON booleans and null at the boundary too —
  `:json-false` and `:json-null` mean nil, and `:json-true` means t.
- **Convention:** a tool that declares a boolean argument must accept
  every spelling of false that a provider can produce.

### §11.13 — an edit that is never saved is not an edit

- **Date:** 2026-11-12 (the live coding task)
- **Symptom:** the edit tool reports "Replaced 1 occurrence", and the file
  on disk is unchanged, so the model reads the broken file again and
  retries forever.
- **Cause:** the tool edited the buffer without saving it. An agent that
  cannot save cannot finish a coding task.
- **Fix:** the edit saves the buffer by default
  (`yeah-edit-save-after-edit`), with the undo boundary preserved so the
  person can revert. Saving also must not add a final newline to a file
  that had none, or the tool silently reformats the file.
- **Convention:** a coding agent's changes must reach the file; review is
  undo, not an unsaved buffer.

### §11.14 — the tick of a file is how the model proves it read it

- **Date:** 2026-11-12 (the live coding task)
- **Symptom:** the model's guarded edit is refused with "stale tick",
  because the model passed 0 as the tick.
- **Cause:** the model had no way to learn the tick. The read tool did not
  return it, so the model guessed.
- **Fix:** the read tool returns the tick in its metadata, and the edit
  tool's description says to pass the tick from the read result, or to
  omit it to skip the guard.
- **Convention:** optimistic concurrency is only useful when the reader
  can see the version it is supposed to compare against.

### §11.15 — the tick must be visible to the model, not only to the edit tool

- **Date:** 2026-11-12 (the live interactive path)
- **Symptom:** the model's guarded edit is refused with "stale tick",
  because the model passed 0.
- **Cause:** the read tool returned the tick in its metadata, but the
  model's view of the result (`yeah-result-model-text') did not include
  the metadata, so the model never saw the tick.
- **Fix:** the model's view of a result carries the tick as `[tick: N]`
  when the result has one.
- **Convention:** a value the model must pass to a guarded edit must be in
  the model's view, not only in the result's metadata.

### §11.16 — a session that cannot be resumed cannot be quit

- **Date:** 2026-11-12 (the live interactive path)
- **Symptom:** `M-x yeah' after a restart opens a new session, and the
  pending inputs of the old one are not found.
- **Cause:** the product created a new timestamped session id on every
  open; the restart had no way to resume the previous session.
- **Fix:** `yeah-product-open' accepts a session id to resume, and
  `yeah-product-latest-session-id' finds the most recent session of the
  project, so a person can quit and come back.
- **Convention:** a quit is not a delete.  A restart must find the
  previous session, or the pending work is lost.
