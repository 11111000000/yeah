# ENGINEERING — practices, constraints and infrastructure

> **Status: binding project guidance.** This file describes how Yeah is built
> and operated. Language-specific rules and the trap log live in
> `ELISP_BEST_PRACTICES.md`; architectural invariants live in
> `docs/ARCHITECTURE.md`.
>
> A rule may be changed deliberately, with its documentation and affected
> checks updated together. Do not route around a rule silently.

## 1. Dependency policy

### Runtime core

The kernel should remain loadable with Emacs, gptel and libraries already
available in a normal Emacs installation. Built-in foundations include:

- `cl-lib`, `json`, `ring`, `project`, `tabulated-list`, `auth-source`;
- `make-process`, timers, process filters/sentinels and `jsonrpc`;
- `emacsclient`/server for explicit inter-Emacs operations;
- tree-sitter and SQLite only when the running Emacs provides them and the
  relevant capability has been checked.

Do not add a dependency because it is popular. Add it only when it removes a
real implementation burden, has an acceptable licence and can be isolated
behind a small adapter.

### Optional product integrations

These are preferred to bespoke replacements where appropriate, but must not
become kernel dependencies:

| Purpose | Preferred facility | Constraint |
|---|---|---|
| Foldable UI sections | `magit-section` | UI only; feature-detect |
| Command menus | `transient` | UI only |
| Session/job tables | built-in `tabulated-list` | no external dependency |
| Selection | `completing-read` | cooperate with user's Vertico/Consult/etc. |
| Credentials | `auth-source` | never write keys to session data |
| Settings | `defcustom`/Customize | no mandatory hand-written init code |
| Web transport | gptel or an existing Emacs HTTP library | no second model transport |
| Async style | callbacks first; `aio` only after a demonstrated need | no new async framework casually |
| Compatibility | `compat` if the version matrix requires it | declare exact minimum |
| Session index | JSONL first; built-in SQLite as a derived index if measured necessary | journal remains authoritative |

### Development-only infrastructure

Emacs, ERT, `scripts/dev` and math-coding are development tools. Nix and the
`mathc` binary must never be required to install or run Yeah. CI pins tool
versions; a local incompatible `mathc` is reported as a tooling failure, not
interpreted as a passing map.

Research clones under `../emacs-agents-research/` are references, not runtime
sources or dependencies. Never load code from that directory in Yeah.

## 2. Supported environment and packaging

- The currently verified development baseline is Emacs 30.2. Any additional
  supported Emacs version must have CI evidence before documentation claims
  support.
- gptel versions are pinned for contract testing. Internal gptel APIs are not
  assumed stable; the adapter fails explicitly on an unsupported contract.
- `lexical-binding` is enabled in every Elisp file.
- Source and stale bytecode must never be confused. Use `scripts/dev`, which
  removes stale `.elc` files before checks.
- Runtime data follows XDG-compatible locations where available. Project data
  and user configuration are separate; no session logs are written into the
  source checkout by default.
- Installation must work on a clean Emacs without this repository's developer
  tooling. A package entry point, autoloads and `yeah-doctor` are required
  before the public alpha.
- No global keybindings are installed by default. No unsolicited minor modes,
  global hooks or changes to the user's gptel setup.

## 3. Module and state discipline

- One feature per `lib/yeah-*.el` file; public names use `yeah-`, internal
  names use `yeah--` or the module's established prefix.
- Keep the `require` graph acyclic. Kernel modules do not depend on UI,
  protocol adapters or optional packages.
- Execution receives an explicit run context. Do not introduce process-wide
  registries, permission sets, current sessions or model settings for
  unrelated runs.
- A module owns its state transitions. Other modules call its public API
  rather than reaching into its data structures.
- Pure projections do not write. Writers do not render UI. Protocol adapters
  do not implement agent logic.
- Expected domain failures use `user-error` or structured tool errors;
  programming errors are not disguised as successful tool results.
- Comments and docstrings must describe current behavior. Historical Tier,
  ROADMAP and nonexistent `decisions/` references are defects.

## 4. Processes, waiting and cancellation

- Start subprocesses with `make-process`, never blocking shell commands in a
  tool body. Use argv arrays where possible; make any shell interpretation an
  explicit part of the tool contract.
- Set process coding systems deliberately, normally UTF-8. Bound collected
  output and expose truncation.
- Every asynchronous operation has one settlement. The first terminal result
  wins; later callbacks are ignored and recorded when useful.
- A handler exception produces a tool failure and allows the batch to settle.
  A nil result is normalized before it reaches a provider serializer.
- Waiting uses callbacks, timers or explicit states. Do not spin on
  `accept-process-output` in interactive execution paths.
- Cancellation is propagated to model requests, managed processes and pending
  callbacks. It does not claim transactional rollback, recursive process-tree
  termination or restoration of files.
- Retries are reserved for transient failures and use bounded backoff. A
  malformed request, permission denial or deterministic test failure is not
  retried blindly.

## 5. Buffer and file safety

- Reads that lead to edits return a modification tick. Edits require a fresh
  tick and exact expected content/ranges.
- Validate every range before mutating. Apply multiple edits bottom-up and as
  one logical undo step.
- Preserve user buffers, point, narrowing and unsaved changes unless the tool
  contract explicitly says otherwise.
- Do not save automatically merely to run a check. Saving is a separate,
  visible operation.
- Full tool output artifacts use private directories (`0700`) and files
  (`0600`), with no secrets intentionally included.
- Journal writes are append-only. Readers detect a partial tail or malformed
  record; snapshots/caches use temporary files and atomic rename when used.
- Do not promise that undo survives restart or that the journal is an
  exactly-once side-effect ledger.

## 6. Security and privacy

Treat the model, project instructions, fetched pages and tool output as
untrusted. Permission checks happen before effects, not after logging.

- Canonicalize paths before checking workspace boundaries.
- Separate read, write, process and network approval.
- Headless execution denies anything not explicitly allowed.
- Always-on logging must not capture credentials. Tests use fake keys only.
- No arbitrary Elisp evaluation is called a sandbox. A static whitelist is
  not proof of isolation; higher-order functions and quoted function symbols
  are part of the attack surface.
- Experimental PTC/eval capabilities are disabled by default and have their
  own claims, threat model and adversarial tests before exposure.
- MCP/ACP publishing is an explicit trust decision. A connected client may be
  able to exercise everything the published capabilities allow.

## 7. Context and cost discipline

- Count provider-reported usage separately from estimates. Unknown usage is
  unknown, not zero.
- Token estimates document their heuristic and are calibrated from real
  usage where possible. Include system prompts and tool definitions, not just
  chat text.
- Bound model input, tool output, pending input, child depth and total run
  cost. A run may stop because its budget is exhausted; that is a normal,
  recorded outcome.
- Compaction commits only a complete nonblank summary and preserves sources.
  Failure never becomes an empty authoritative summary.
- Do not repeatedly inject hidden reminders without recording them. Nudges,
  steering and mode changes are journal events.

## 8. Testing and claims

Every change runs the relevant existing tests; the standard final gates are:

```sh
./scripts/dev byte-compile-all
./scripts/dev ert tests/unit/*.el
./scripts/dev check tests/checks/*
./scripts/dev gate
```

If `mathc` is unavailable or incompatible, report the map/gate as blocked.
Do not replace a failing standard check with a custom success command.

Test layers:

1. pure unit tests;
2. canaries bound to claims, with controls that break behavior and produce a
   real assertion failure rather than a reader/crash failure;
3. integration tests with processes, real gptel contracts and restart;
4. opt-in live provider tests using environment credentials;
5. comparative task benchmarks.

Mandatory adversarial cases include malformed tool arguments, handler errors,
duplicate callbacks, nil results, stale edit ticks, partial journal tails,
cancellation races and secret-redaction checks.

A placeholder that returns success is a failed implementation. Tests must
exercise observable behavior, not merely the presence of a function.

## 9. Performance and operability

Measure before optimizing. Use `benchmark-run`, `elp` or process timing and
record the scenario with the result.

Watch at least: event append cost, full-log scans, UI rerendering, token
estimation, session indexing and large tool output. Derived indexes and
caches are disposable projections, never second sources of truth.

`yeah-doctor` should diagnose supported Emacs/gptel versions, load paths,
backend configuration (without printing secrets), data directories, stale
bytecode and pending processes. Logs are local and user-controlled.

## 10. Documentation and Emacs package culture

- README describes current user-visible behavior and explicit limitations.
- ARCHITECTURE describes target invariants; PLAN describes unfinished work.
- Public functions have useful docstrings; run checkdoc/package-lint when the
  packaging wave introduces them.
- Customize settings have correct types and safe local-variable declarations
  where relevant.
- Optional packages are loaded lazily and feature-detected.
- Offline/local-model use is a supported design constraint, not an afterthought.
- Provide Info documentation when the product stabilizes; Org export makes
  sessions durable and readable outside the running agent.
- Changes include their rationale where the architecture changes. Git is the
  history; do not create contradictory duplicate plans.

## 11. Definition of done for every work item

A work item is done only when:

1. the requested behavior exists end to end, with no stub on the path;
2. relevant unit, canary and integration checks pass;
3. new claims have controls shown to bite;
4. no unrelated regression is hidden or deleted;
5. comments and docs match actual behavior;
6. generated artifacts are cleaned and the working tree contains only
   intended changes;
7. remaining limits are stated plainly.
