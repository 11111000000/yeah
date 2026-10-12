# ELISP_BEST_PRACTICES — Yeah v0.0.0-alpha

> Conventions for writing kernel Elisp in this repository. Adapted
> from `math-coding 3.0-alpha/OCAML_BEST_PRACTICES.md`: the OCaml
> trap log is replaced here by an Elisp trap log, and the §1
> "offline kernel" rule becomes §1.1 "byte-compile clean".

This file is the project's Elisp-specific conventions. When the
trap log in §11 is empty, it is also a placeholder; the first
real entry lands as the first kernel module is built.

## §1. The kernel stays small and Elisp-only

§1.1 — **byte-compile clean.** Every file under `lib/` must
byte-compile with no warnings or errors under
`emacs -Q --batch -f batch-byte-compile lib/*.el`.

§1.2 — **one feature per file.** Each `lib/yeah-*.el` provides
exactly one feature (matches the file name). `(require 'yeah-x)`
loads `lib/yeah-x.el`. No cross-file `(defun)` is allowed; only
`(defun yeah-x-foo …)` or fully-qualified helpers.

§1.3 — **no `(eval-when-compile (require …))` cycles.** Cycles
in the require graph are forbidden. The graph is recorded in
`PACKAGES.md §"Kernel modules (by file)"` and validated by hand
until `scripts/dev dep-check` is wired.

## §2. Naming

§2.1 — **prefix `yeah-` on public symbols.** Internal helpers
may use `--` (e.g. `yeah--state-default`), but anything that
could be called from another module uses a single dash.

§2.2 — **defclass slot names use `:kebab-case`.** The plist
keyword and the reader accessor both use `:kebab-case`. We do
not run `eieio` on legacy code; `cl-defstruct` is preferred for
records, and `eieio` only for inheritance.

§2.3 — **records are `cl-defstruct` with `:conc-name yeah-x-`.**
This gives `yeah-x-foo` accessors without `defclass` ceremony.

## §3. Errors

§3.1 — **domain errors are `(user-error …)`.** Tool rejections,
permission declines, and input validation failures use
`user-error`. The model sees them as a structured tool failure.

§3.2 — **never `(error …)` for expected user-visible conditions.**
Reserve `error` for actual bugs. Anything that "the user could
have done differently" is `user-error`.

§3.3 — **wrap `cl-loop` and `dolist` in `condition-case`.** A
tool body must never let an exception escape; the wrapper
catches `error`, `user-error`, and `(signal 'cl-assertion-failed …)`
explicitly.

## §4. Process / IO

§4.1 — **use `make-process` for any subprocess.** Never call
`shell-command`, `async-shell-command`, or `call-process` from
inside a tool body. The kernel's process table is a single
source of truth for live subprocesses.

§4.2 — **filters return either a string or a `(error …)` form.**
The sentinel `'(error "...")` is the only way a `:filter`
function reports failure; this is the convention used by
`jsonrpc.el`.

§4.3 — **set `:coding` to `'(utf-8 . utf-8)` for any process
that may carry non-ASCII output.** Default Emacs coding on
many platforms is `iso-latin-1`; this is the wrong default for
LLM output.

## §5. JSON

§5.1 — **use `json-parse-string` and `json-serialize`.** The
built-in JSON parser handles all our use cases. `jsonrpc.el`
exposes its own plist shape, but inside Yeah, plists are
fine — we convert to/from alists at the wire boundary only.

§5.2 — **JSON keys are `kebab-case` over the wire, `kebab-case`
in Elisp.** No camelCase at any layer. This is the math-coding
convention; it matches the ACP/MCP wire shape and avoids
constant re-keying at the boundary.

## §6. Tests

§6.1 — **ERT tests live in `tests/unit/test-*.el`.** The file
name is `test-<module>.el`. The test symbols are named
`yeah-<module>-<aspect>-<case>`.

§6.2 — **every test has a positive and a negative companion.**
The positive exercises the happy path; the negative exercises
the closest plausible failure mode. They live in the same
file, with names that share a common prefix.

## §7. Performance

§7.1 — **don't optimise until `yeah validate` is green.**
Premature optimisation in `lib/` is forbidden under
`decisions/elisp-toolchain-only.yaml`.

§7.2 — **measure with `elp` or `benchmark-run`.** Wrap
optimisation candidates in `(benchmark-run 1000 …)` and
record the result in the PR description; the load-bearing
number is the regression, not the absolute time.

## §8. JSON-RPC / ACP / MCP

§8.1 — **the `jsonrpc.el` connection object is the only thing
that crosses the ACP / MCP boundary.** Do not write
`(make-network-process …)` directly to talk to a remote
agent; route through `jsonrpc-process-connection`.

§8.2 — **`emacsclient` calls go through `make-process`, not
through `call-process`.** Even a one-shot `emacsclient -e '(…)'`
is a `:coding`/`utf-8` trap if you let `call-process` coerce the
output; `make-process` + `:filter` gives the result string back
in the buffer you control.

## §9. Concurrency

§9.1 — **don't use `make-thread` in the kernel.** The agent loop
is single-threaded; sub-agents run in their own Emacs processes,
not threads. This is `decisions/emacs-native-runtime@0`'s
companion rule.

§9.2 — **accept-process-output is the only blocking call.** All
subprocess IO returns to the loop through a process filter; the
loop itself never blocks on user input — that is the
`awaiting_user_*` state.

## §10. Working with the future `mathc` validator

§10.1 — **every decision file's `axiom_link` is one of
`A0…A4`.** Today these names are placeholders; the day `mathc`
is wired, the validator will check the link is in
`axioms/index.md`. Until then, the link is human-meaningful
(`A0` = separation, `A1` = feedback, `A2` = invariants,
`A3` = self-application, `A4` = care).

§10.2 — **every obligation closes via `obligations/*.yaml` and
`attestations/*.yaml`.** The closure chain
`obligation → attestation` is what the validator will check.
Until then, the obligation text lives inline in the decision
file's `outcomes` list.

## §11. Trap log (Elisp)

This section will record recurring Elisp and package errors with
minimal reproducers, the same way `OCAML_BEST_PRACTICES.md §11`
records OCaml/dune errors.

> No entries yet. The first entry will be added as the first
> real kernel module is built.
