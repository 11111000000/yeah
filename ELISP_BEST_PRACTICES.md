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

### §11.1 — `(let ((defvar-var X)) …)` does not rebind `defvar` under `lexical-binding: t`

- **Date:** 2026-10-12 (commits `8e2f324` and `93ffe8f`)
- **Module:** `lib/yeah-validate.el` (removed in the v4 migration; the rule
  stands)
- **Symptom:** a test that does
  ```
  (let ((yeah-validate--decisions-dir "decisions"))
    …)
  ```
  fails to see the rebound value; `default-directory` is correct but
  `directory-files` reads the global dynamic value.
- **Cause:** under `lexical-binding: t`, `let` creates a lexical binding
  that shadows the variable for the lexical scope of the let body. The
  `defvar`-declared variable is also `special` (dynamic), and inside a
  function compiled with `lexical-binding: t` the function body reads the
  *global dynamic* binding, not the lexical one. The two bindings are
  independent.
- **Fix:** use `setq` to mutate the dynamic binding.
- **Convention:** when documenting a new `defvar` in `lib/`, add a
  docstring note: "Rebind with `setq`, not `let'."

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
