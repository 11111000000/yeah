# AGENTS.md — the entry point to this repository

> **Yeah** means **Yeah, Emacs Agent Harness**: a recursive acronym, the
> **Y** is the Y-combinator. The harness itself is
> Emacs Lisp; Emacs is not merely a client to an external agent. The model is
> reached through gptel, effects go through the tool registry and permission
> system, and session history is append-only JSONL.
>
> The long-term Y metaphor means bounded recursive delegation, runtime
> self-inspection and a fixed point where Yeah can develop and verify Yeah.
> These are goals, not assertions about today's prototype.
>
> This repository is governed by **math-coding v5**: `spec.json` holds the
> standing specification (`schema_version: 5`) and the claims, `waves/*.json`
> holds the historical work units, and evidence comes from checks bound by
> `mathc run`.  Version 4 is frozen and archived at `waves/spec-v4.json`;
> its evidence is not current.
> `docs/PLAN.md` defines the current target sequence; do not mistake an old
> wave number or a green module row for a working end-to-end feature.

## Read first, in this order

1. `README.md` — actual current status and explicit limitations.
2. `docs/ARCHITECTURE.md` — the normative target: purpose, ten decisions,
   contracts, security, placements and non-goals.
3. `docs/PLAN.md` — the detailed eight-stage execution plan and release gates.
4. `docs/ENGINEERING.md` — binding dependency, infrastructure, library,
   process, security, testing and packaging practices.
5. `spec.json` — the standing machine-checked specification.
6. `waves/*.json` — existing math-coding units, with intent, check, promise
   and objection.
7. `ELISP_BEST_PRACTICES.md` — kernel Elisp conventions; §11 is the trap log.
8. `lib/yeah-*.el` — the implementation, one feature per file.
9. `docs/PASEO-INTEGRATION-PLAN.md` — the state of the integration with the
   orchestrator Paseo, the gaps of the ACP surface and the order of the work;
   the plugin of Paseo lives in `plugin/yeah-provider/` (TypeScript, outside
   `lib/`, which stays Elisp only).
10. `docs/PLAN.md` §19 — the order of the work on the integration: the waves,
    the four points outside the plan of the owner, and the decisions that only
    the owner may make.
11. `docs/ARCHITECTURE-CATCHUP-PLAN.md` — the order of the waves that bring
    the code up to the architecture: the tracks A, B and C of the code, the
    waves of the diagrams (D) and of the documentation (E), and the decision
    of the owner of 2026-11-20 that named that order.

If two sources contradict each other, report the contradiction in the open
work item. Never resolve it by silently making documentation more optimistic.

## Current warnings for every agent

- This is a kernel prototype, not a usable coding product.
- The parity with other harnesses was piloted on 2026-11-15, and the
  difference the pilot found was a defect of the turn, not a difference of
  quality: after the results of the tool calls arrive, the model may answer
  with an empty message, and the turn took that as the end of the work and
  stopped without the effect (docs/LIVE-EVIDENCE.md, "The pilot of the
  parity").  The defect is fixed (the claim
  `an-empty-answer-does-not-end-the-run'), and the pilot on the fixed turn
  moved one task of three; the nudge now carries the state of the work
  (the claim `a-silence-nudge-carries-the-state-of-the-work'), because the
  provider goes silent after every batch of tool results and the model was
  answering the nudge by starting the work over.  With that, Yeah passes
  two tasks of three and pi passes three.  The third task failed in the
  tools: the `read` of a file nobody has edited yet returns no tick, and
  the `edit` refused the tick the model guessed as stale although the file
  has not changed; wave 26 makes a guessed tick ignored rather than
  refused (the claim
  `a-guessed-tick-does-not-refuse-an-unchanged-file'), and that task of the
  pilot passes now.  The provider was overloaded for hours (HTTP 529 to both
  harnesses), so the pilot of 15:02 measured one task of three and two
  blocked runs: the runner records a run the provider stopped as **blocked**,
  neither a pass nor a failure (the claim
  `a-provider-failure-is-not-a-failure-of-the-agent').  The pilot of 15:39, on
  the code of wave 28, measured two tasks of three — Yeah passed both of them
  and pi passed all three — and the third was blocked, because the transport
  to the provider died.  The parity of that run is not measured either.  The
  pilot of 17:06, on the code of waves 30+31, measured one task of three for
  Yeah and two of three for pi: all three runs of Yeah ended `unfinished`,
  because the provider goes silent, and the one task that failed in the tools
  failed on the **version token** of the file — the model copied 58 of the 64
  characters of the digest and the edit refused the edit of a file that had
  not changed (docs/LIVE-EVIDENCE.md, "The pilot that measured the copy of the
  version token").  The pilot of 17:23, on the code of wave 32, measured two
  tasks of three for Yeah and three of three for pi: the token of the file is
  short now, the read handed out twelve characters, and the tasks the model
  worked on passed.  The task that Yeah failed failed on the provider: the
  model announced the fix ("Fixing it to use floating-point division:") and
  called no tool (docs/LIVE-EVIDENCE.md, "The pilot after the token became
  short").  The pilot of 2026-11-16 06:43–06:48, on the code of wave 33, measured
  two tasks of three for Yeah and three of three for pi, and the pilot of
  07:04, on the code of wave 34, measured one task of three for Yeah and three
  of three for pi.  Both failures were the same failure of the model and not of
  the harness: the model read the files of the task and never called the tool
  that would change them, while the guards of waves 29, 32, 33 and 34 were
  never in the way (docs/LIVE-EVIDENCE.md, "The live checks and the pilot after
  wave 34").  The pilot of 08:07, on the code of wave 35, measured two tasks of
  three for Yeah and three of three for pi, and the third task of Yeah was
  blocked: the transport to the provider died with "Curl failed with exit code
  28" after the model had read the file and computed the sum.  A run that the
  provider stops is blocked and not a failure of the agent, and it says
  nothing about either harness (docs/LIVE-EVIDENCE.md, "The live checks and the
  pilot after wave 35").  The pilot of 10:00, on the code of wave 36, measured
  two tasks of three for Yeah and three of three for pi, and the third task of
  Yeah failed in the tools: the model read the file, computed the sum with
  `bash` (the tool answered 100) and then answered with an empty message three
  times; the harness nudged three times, every nudge carrying the state of the
  work, and the run ended "unfinished" with the nudge budget spent.  The file
  was never written, so the runner recorded a failure of the agent; that is
  the shape the provider has had for two days, and `write-new-file` passed in
  the same pilot, so the write path of the code of wave 36 works (docs/
  LIVE-EVIDENCE.md, "The live checks and the pilot after wave 36").  The
  pilot of 10:44, on the code of wave 37, measured the same: two tasks of
  three for Yeah and three of three for pi, and the third task of Yeah
  failed in the tools the same way — the model read the file, ran `bash`,
  and then answered with an empty message; the harness nudged it with the
  state of the work, and the model went silent again (docs/LIVE-EVIDENCE.md,
  "The live checks and the pilot after wave 37").  The pilot of 13:12, on the
  code of wave 38, measured one task of three for Yeah and three of three for
  pi: two tasks of Yeah failed in the same shape — the model read the files,
  and then answered with an empty message three times, and the run ended
  "unfinished" with the nudge budget spent.  The row of such a run names the
  shape of it since wave 38, so the reader of the pilot sees the cause of the
  failed check and not only its verdict; the verdict of the row is still the
  verdict, because the classification of a run that did not finish is a
  decision of the owner (docs/LIVE-EVIDENCE.md, "The live checks and the
  pilot after wave 38").  The threshold of the
  parity is a decision of the owner (docs/PLAN.md §13), and nobody may quote
  the pilot as a verdict about parity.
- A decision that arrives while the tools of the previous decision are still
  running no longer breaks the run: the turn keeps the calls, runs them when
  the running batch has settled, and gives the model the results of every
  batch together (wave 28, the claims
  `a-decision-that-arrives-while-the-tools-run-does-not-break-the-run' and
  `the-same-tool-call-does-not-run-twice').  The live checks of 15:38 hold
  no transition error at all.  The live coding task still fails, and it fails
  for another reason: the model of the provider answers with an empty message
  and the run ends with the record "unfinished" — the work is not done, and
  the run says so.
- The read of a file shows the file on disk, but the tick it hands out
  belongs to the buffer that visits the file: when Emacs holds unsaved
  changes of that file, the model sees the disk and the edit applies to the
  buffer.  Wave 29 refused that case when the model presents the version of
  the read; wave 33 makes the refusal the answer of every edit, with a
  version or without one, because a read of the disk cannot show the changes
  of the person (the claim
  `an-edit-never-lands-on-a-file-with-unsaved-changes').  The write takes the
  same short version token and is refused when the file changed after the
  read that handed it out (the claim
  `a-write-never-lands-on-a-file-that-changed'); the token of the write is
  optional, so a model that presents no version writes without that guard.
  A write of a file that Emacs holds unsaved changes of is not refused: the
  write goes to the disk and the buffer becomes stale — that is open in
  docs/PLAN-NEXT.md.
- The harness opens the files of the project on behalf of the model, and
  Emacs runs the local variables of a file and the directory-local variables
  of its directory when it opens one.  That code is the code of the project,
  and the project is untrusted input: a `mode:` entry names a function that
  Emacs calls, and an `eval:` entry is Elisp that Emacs evaluates.  The edit
  opens the file through `yeah-untrusted-open-file` (lib/yeah-untrusted.el),
  where that machinery is neutralized whatever the configuration of the
  Emacs is (wave 34, the claim
  `an-edit-never-runs-the-local-variables-of-the-project').  The price is
  named: the mode line of the file is part of its content, so it is ignored,
  and the buffer of the person shows the file in the mode of its name.
- Every read now hands the model the version of the file as well: the digest
  of its bytes (lib/yeah-version.el). The edit checks that version and is
  refused when the file changed after the read, so an edit never lands on a
  file the model did not read; it is also refused when Emacs holds unsaved
  changes of the file, because a read of the disk cannot show them. A
  version that no read handed out is ignored, like a tick that no read handed
  out. docs/ARCHITECTURE.md §D5 was amended, not weakened: it names the
  version as the second form of the state a read returns.
- The process of the ACP server outlives the agent when the client keeps its
  pipe open, and some of those processes burn half a core in a tight loop of
  userspace. The read loop of the server is not the cause (an idle server
  costs no CPU and leaves on EOF) and the wait for a turn is not either (about
  four per cent of a core): the spin is on the path of the live request of the
  provider, and the loop is not localized yet. Nobody may quote the ACP
  server as free of this until a canary says so — docs/PLAN.md §17.1.
- The version token is short (12 characters of the digest) and a refusal of a
  token that does not match names the token, not the file, and reports the
  current token so that the retry lands: the pilot of 17:06 measured a model
  that copied 58 of the 64 characters of the digest and an edit that refused
  a file that had not changed (wave 32, the claims
  `a-version-token-is-short-enough-to-copy' and
  `an-edit-refuses-a-wrong-token-with-the-current-one'). A model can still
  lose a character of twelve, and the harness cannot make the model retry.
- A decision that repeats a call that is already running is dropped, and the
  drop is now in the journal: the event `tool-dropped` carries the tool, the
  reason and the arguments, so a reader of the log tells a repeated decision
  from a decision that never came (wave 30). The model is not told that its
  repetition was refused, because a tool that runs twice would repeat its
  side effect; the identity of a call is still the tool and its arguments.
  docs/ARCHITECTURE.md §D1 was amended, not weakened: the vocabulary it
  names now includes dropped calls.
- The checks read the journals through one reader
  (`tests/support/yeah-journal-files.el`), and that reader skips the lock
  files of Emacs (`.#`) next to a journal and survives a journal that
  vanishes between the scan and the read. A check that crashes on the
  filesystem does not fail on its assertion, and the method reads a crashed
  verifier as an error and not as a proven control (wave 31).
- Stage 7 is implemented offline: an agent preset is a file (a Markdown or
  Org header and a body), and a child runs for real in its own session with
  only the tools it was granted. The fixed-point demonstration passes with
  a live model: a child repairs a Yeah canary and the canary passes
  afterwards (tests/live/live-fixed-point.el, one child). Parallel
  children and the cheaper child model are not implemented yet; an Org
  preset header and the Org export of a session are (lib/yeah-agent.el,
  lib/yeah-org.el).
- The delegation of a child is a tool of the kernel (wave 35): `delegate`
  names an agent preset and a task, and the child runs in a session of its
  own, on the model of the preset, with the tools of the preset and with
  the instructions of the preset; every tool outside the preset is refused
  to it. The turn of the parent is not held: `delegate` answers at once
  with the id of the child, the child answers on its own, and
  `delegate-result` reports what became of it. A delegation changes the
  world, so the Plan profile denies it (lib/yeah-delegate.el,
  docs/PLAN.md §16.18).
- A delegation belongs to the run that asked for it (wave 36). The audit of
  wave 35 found the defect: the tool that delegates remembered the sessions of
  the runs whose calls were allowed and took the first of them, so a
  delegation could be written into the journal of another run, and a call that
  failed left its session behind for the next delegation to take. The run binds
  the session it writes into while it dispatches the call (lib/yeah-session.el,
  lib/yeah-turn.el), and the child of that call is written into the journal of
  that run; a call with no run has no journal and is refused. The id of a child
  is short (`sub-1`), because the model has to copy it back and a long token is
  copied with an error; a wrong id is refused by name, and the refusal names
  the children that do exist. A child has a time of its own (`timeout:` in the
  preset, 900 seconds by default): a child that ran out of time is cancelled,
  and the parent is told why. Several children in one turn of the parent work
  already — the audit proved it, and the plan that said otherwise was wrong.
  Not implemented then: the depth of the tree of the children and the children
  themselves were kept in the running Emacs and not in the journal; wave 37
  moved the tree into the journal (docs/PLAN.md §16.19, §16.20, §17.1).
- Wave 37 moved the tree of the children into the journal: the journal of the
  run holds the short id, the session and the depth of every child, and the
  journal of the child holds where that child stands in the tree (its parent,
  its depth and the id the model calls it by). A harness that starts again
  reads the tree from there: the child of a run is found by the id the model
  was given, what became of it is told, and a child the journal holds no end
  of is not reported as a child that still works — the restart ends the child
  as well, because the child runs in the same Emacs. The depth of a child is
  read from its own journal, so a child of depth one does not look like a root
  after a restart and is refused the delegation that would put the grandchild
  at the depth two, when the agent of the child allows the depth one
  (lib/yeah-delegate.el, lib/yeah-subagent.el, lib/yeah-events.el; the claims
  `a-child-is-found-after-the-harness-restarts' and
  `a-session-knows-its-depth-from-the-journal'; docs/PLAN.md §16.20).
  Not implemented: a child that was running when the Emacs died is not
  brought back to life — the work of that child is lost.
- Wave 38 made the pilot name the shape of a run that did not finish: the
  reason of the row begins with what the journal of the run holds — the model
  answered with an empty message N times, or it described its next step N
  times and called no tool — so that a reader of the pilot sees the cause of
  a failed check and not only its verdict.  The status of the row does not
  change: whether such a run is a failure of the agent or a run that was never
  measured is a decision of the owner (docs/PLAN.md §17.2), and the runner does
  not take it (bench/run-bench.el; the claim
  `the-pilot-names-the-shape-of-a-run-that-did-not-finish'; docs/PLAN.md
  §16.21).
- Wave 39 made the kernel supervise a run by default: the budget of the
  completion nudges is positive (`yeah-turn-default-max-nudges` is 3), so a run
  of Yeah is supervised unless the caller asks for no supervision at all (a
  budget of zero).  Before the change, the ACP route answered `end_turn` for a
  run in which the model had only described its next step — the wire said the
  work was done, and nothing had been done.  A run that spends its budget
  without an effect now ends in the state `failed`, and the ACP route answers
  it with the stop reason `refusal` (the claims
  `supervision-is-the-default' and
  `a-run-that-did-not-finish-is-not-a-success'; docs/PLAN.md §16.22).  The
  budget of a child of a delegation is a separate default and is still zero:
  that decision belongs to the owner (docs/PLAN.md §17.2).
- Wave 40 made the wire of Yeah speak ACP: the content of a chunk is one
  content block (the protocol says one block, and a client that checks the
  wire refuses an array), and the events of the pending queue of a session —
  `input_queued', `input_taken', `input_recovered', `input_withdrawn' — are
  not ACP at all.  They travel only to the client that asked for them: the
  client announces them in the `_meta' of its capabilities at `initialize',
  and a client that announces nothing is served plain ACP.  The editor of
  Yeah announces them and sees the queue.  The name of the extension, the
  version of the protocol and the way the announcement is read live in
  `lib/yeah-acp-vocabulary.el`, which both sides of Yeah require (the claims
  `the-wire-speaks-acp' and
  `the-queue-events-travel-where-they-were-asked-for'; docs/PLAN.md §16.23).
  The defect this wave repairs was found by a client that validates the wire:
  it refused every `session/update' of Yeah, so the text of the agent never
  reached the timeline of the client.
- The shapes of the wire were not the whole of it: the text of the agent
  still did not reach the client, because the model of the live task answered
  only with the call of the `finish' tool and the `finish' tool was not
  projected at all.  A client that speaks ACP expects the words of the agent
  as the message of the agent, so the summary of a finished run travels as
  `agent_message_chunk', and the call of a tool carries what it was called
  with and what it returned (`rawInput' and `rawOutput'; the claims
  `the-answer-of-the-agent-reaches-the-client' and
  `a-tool-call-carries-its-input-and-its-output').  The arguments of a call
  are read back from their printed form as data and never as code.
- The words themselves were spoiled on the way out, and the live check in
  Paseo found it: the answer of the model reached the timeline of the agent
  and arrived as mojibake, while the journal of the session held the right
  text.  Emacs's `json-serialize' returns a unibyte string whose bytes are
  UTF-8, and `princ' of such a string makes Emacs read every byte as a
  character of Latin-1 and write the characters back as UTF-8 — every
  non-ASCII answer was written twice over.  The wire now writes the bytes of
  a message as they are (`lib/yeah-wire.el', `yeah-wire-print-line'), and both
  protocols that write to a stream use it (the claim
  `the-text-on-the-wire-is-the-text-the-model-wrote'; the check reads the
  bytes of a real server process, because a character set would answer a
  different question).
- Wave 45 made the harness live.  The live test of Yeah against a real
  provider found four defects that no offline check had seen, because every
  offline check had been written by the same hand as the code.  A `bash'
  tool whose output ends in a byte that is not valid UTF-8 killed the whole
  Emacs process: the refusal of JSON arrived inside the sentinel of the
  process, where no handler of the turn stands, and the run left no record
  of itself (exit code 255).  The bytes arrive in two shapes, and both are
  now text: a unibyte string of bytes, and a multibyte string that holds a
  raw byte where the decoder of a process refused one (a character whose
  code is at or above #x3FFF00).  The text of the harness is decided in one
  place (`lib/yeah-text.el'), and a byte that is not text becomes the
  replacement character (the claim
  `the-text-of-the-harness-is-always-text').  The journal never refuses a
  record: a record that JSON cannot write is written as a stand-in that
  says so, and the journal takes the records that follow (the claim
  `the-journal-never-refuses-a-record').  A list in a record is not such a
  value: the journal writes a list as an array, the record keeps its other
  fields, and the reader of a JSON array gives a vector back (the claim
  `the-journal-writes-a-list-as-an-array', wave 68).  An error of the
  harness that happens inside the callback of an asynchronous tool becomes
  a failed tool and not the death of the process.  A run whose summary the provider did
  not write does not die either: the old outputs of the tools are pruned,
  the journal says that the summary did not arrive, and the run goes on (the
  claim `a-run-degrades-when-the-summary-does-not-arrive').  The reason of
  a failure that goes into the journal is cut at two thousand characters,
  because a provider that refuses a request hands the whole conversation of
  the run back inside the refusal, and one record of the journal is a
  record and not a transcript (the claim
  `the-record-of-a-failure-is-bounded'; the record of the failure of the
  second live run was 2.8 MB).  The end-to-end check of the first defect
  runs a real child process that runs the real tool
  (tests/checks/check-a-tool-that-returns-bytes-does-not-kill-the-harness.el),
  and all five controls were run and bit; docs/PLAN.md §16.24.  The repaired
  harness was then run against a real provider with a real coding task: the
  model wrote a calculator (5 553 bytes), wrote its own tests (4 699 bytes,
  fifteen where the task asked for eight), ran them and the run of the tests
  outside the harness says `OK` (docs/LIVE-EVIDENCE.md, "The live coding run
  after wave 45").  The same run is the first live proof of the repair: one
  command of the model cut a multibyte character of the journal in half, and
  the journal of the run is valid UTF-8 from the first byte to the last.
  The wave is
  numbered 45 and not 41: the waves 41 to 44 are the plan the owner named
  on 2026-11-16 (docs/PLAN.md §18), and that plan is not rewritten here.
- Wave 46 made the noise of the provider harmless to a run that works.  The
  first live run of Yeah on the task of the owner (the wave 41) called
  seventeen tools and still ended in the state `failed`: the provider answered
  every batch of the results with an empty message, the harness read that
  silence as the silence of a model that does not act, and the budget of the
  nudges was spent on the noise.  The record of that run said "the model
  answered with an empty message 8 times and the run ended without an effect",
  and both halves of it were false: the run had an effect and the model had
  acted.  The budget of the nudges now pays for the nudges that no effect
  answered, and a nudge that follows the silence of the provider after the
  tools of the model have come back does not spend it (the claim
  `the-noise-of-the-provider-does-not-end-a-working-run').  A model that never
  acts still ends, and the record of a run that did not finish names the tools
  the run called, so a run that called its tools is never described as a run
  that ended without an effect (the claim
  `the-record-of-a-run-that-did-not-finish-is-true').  The check of the wave
  plays the shape of that live run with a fake transport, and both of its
  controls were run and bit; docs/PLAN.md §16.25, docs/LIVE-EVIDENCE.md, "The
  self-development run that found the noise of the provider".
- Wave 47 gave the model the memory of the run.  Every request of the harness
  started a fresh conversation with the model: the prompt was all the model was
  told, so a model that answered with a plan instead of an action began the
  task over.  Two live runs of the wave 41 measured the shape — 108 and 122
  calls of tools, no change of the repository, `AGENTS.md' read ten and nine
  times, the input of the requests not growing at all (4149 tokens at the
  start of the run and 919 after 122 calls).  Every request now carries the
  transcript of the run before the prompt: the call the model made, the result
  it got and the answer it gave, and the words that keep the work where it is
  (the claim `the-model-is-told-what-the-run-has-done').  The transcript is a
  projection of the journal and not a second copy of the run — the journal
  keeps the plain message it was written with (the claim
  `the-transcript-is-a-projection-and-not-a-second-copy-of-the-run').  The
  check of the wave plays the shape of those live runs with a fake transport,
  and both of its controls were run and bit; docs/PLAN.md §16.26,
  docs/LIVE-EVIDENCE.md, "The self-development runs that found the missing
  memory".
- Wave 48 made the death of the transport harmless to a run that works.  Three
  live runs of the wave 41 died the same way — `Curl failed with exit code 28',
  `16' and `28' — after 108, 122 and 70 calls of tools, and the harness read
  the death of the transport as the end of the run and threw the work of the
  model away with it.  A request that the provider dropped (no HTTP status) and
  a request that met a busy provider (429, 5xx, 529) are asked again, with the
  transcript of the run in front of the model, and the retry is bounded by a
  budget of its own; the journal holds the retry as a record of its own
  (`retry'), and the machine of the states does not move (the claims
  `a-dropped-request-is-asked-again' and `the-retries-of-a-run-are-bounded').
  A request that the provider refused is an answer and is not asked again (the
  claim `a-refused-request-is-not-asked-again').  The status of the wire
  decides which of the two it is, and gptel reports it as a string, so it is
  read as a number: without that a refusal of the provider would have been
  taken for a request that was never answered.  The check of the wave plays
  the shape of those live runs with a fake provider, down to the string that
  carries the status, and all three of its controls were run and bit; docs/PLAN.md
  §16.27, docs/LIVE-EVIDENCE.md, "The run on the code of wave 47 and the death
  of the transport".
- Wave 49 made the compaction wait for the answer of the provider.  The live run
  of the wave 41 on the code of the waves 47 and 48 (2026-11-17 18:17) died in
  the tools and not in the provider: the compaction took the thinking of the
  provider for the answer, the run degraded for nothing, and the summary that
  came later continued a run whose machine was in a state that has no such
  transition — `yeah-loop-tick: no transition from awaiting-tool on continue'.
  The decision what counts as an answer moved from the tree of the tests into
  the kernel (lib/yeah-answer.el), because the run loop and the compaction meet
  the same shapes of the provider: text with content and a tool call are
  answers, the empty string, the streaming sentinel and the reasoning are not,
  and everything but the road to the answer ends the request.  The compaction
  waits for that answer and delivers its outcome once, so a provider that
  answers twice does not compact the context twice and does not break the run
  (the claims `the-compaction-waits-for-an-answer' and
  `the-outcome-of-a-compaction-arrives-once'); the claim
  `the-live-stand-waits-for-an-answer' was amended and not rewritten, and its
  control moved with the decision.  The check of the wave plays the shape of
  that live run with a fake provider, and both of its controls were run and
  bit; docs/PLAN.md §16.28, docs/LIVE-EVIDENCE.md, "The self-development run
  that found the compaction that did not wait".
- Wave 50 made the check of the wire decide its verdict by construction.  The
  check of the wire was flaky, and the reason was in the check itself:
  `yeah-check--raw` read the chunks of the wire with `nreverse`, which turns
  the list over in place and leaves the variable at the cell that was its
  head, so the second reading of the wire found one chunk and not the wire,
  and the verdict of the check depended on how many times it had read the
  wire before.  The reading is repaired (the list is read and not turned over,
  and the lines are cut out of the bytes before they are decoded), and the
  check waits now for the end of the turn and not for the equality of the
  text: the equality is the assertion of the check and not the condition of
  the wait, so a run that the control has broken ends in a second and not in
  thirty.  The new check
  (tests/checks/check-wire-check-decides-its-verdict-by-construction.el) takes
  the control of the claim of the text on the wire and runs the check of the
  wire against it twenty times in a copy of the repository: every one of the
  twenty runs must fail by an assertion of the check, and every one of them
  must fail in the same way — the same code of the exit and the same words.
  The claim `the-wire-check-decides-its-verdict-by-construction` is registered,
  and its control (the moment of the clock in the words of the check) breaks
  that determinism: nineteen of the twenty runs decided in another way than
  the first one; docs/PLAN.md §16.29.
- Wave 41 — the wave of the plan of the owner — was carried out by the harness
  itself (2026-11-17 18:48–19:15): a live model (MiniMax-M3.1-Flash) worked on
  a copy of the repository in a live run of Yeah, wrote the check of the wave
  (tests/checks/check-bridge-check-decides-the-race-by-construction.el), found
  three defects in its own check (the keys of a JSON object come as symbols
  from Emacs 30, so the control of the claim of the bridge was never found;
  file-copy-file does not create the directory of the target; the buffer of the
  words of a run was bound in a let that binds in parallel), registered the new
  claim the-bridge-check-decides-the-race-by-construction in spec.json, proved
  that the control of the claim of the bridge bites twelve times of twelve and
  that the control of the new claim breaks the determinism of the check, and
  finished through the finish tool — the state of the run was completed.  The
  first of the two runs died ten minutes into the work (the machine), the
  second picked the work up from the tree and finished it.  The second
  criterion of the exit of the wave was met on 2026-11-18: the owner recorded
  the review of the plan of the owner, the paragraph of §18.1 that named the
  verdict of the map was rewritten so that the plan carries no statement about
  a verdict that the next run may change, and two consecutive runs of the
  method ended in `green` (03:00:48 and 03:09:20 UTC, the code 0 both times).
  The decision of the owner did not change (docs/PLAN.md §17.2, §18.1;
  docs/LIVE-EVIDENCE.md, "The self-development run that finished the wave 41"
  and "The map of the method came out green twice").
- Wave 53 made the words of the model not end a supervised run.  The live run
  of wave 42 (2026-11-18 06:24–06:38) found the defect: both attempts ended
  with `final state: completed' while the work was not done — 261 calls of
  tools in the first attempt, 142 in the second, no call of `finish' at all,
  and the last words of the model cut off mid-phrase.  Every text answer of the
  model ended the turn, so the run looked done.  Two claims of one
  specification contradicted each other: `finish-is-the-only-completion-path'
  said that a supervised run ends through the call of `finish', and
  `nudge-only-for-plans' read the words of the model as the end of the run —
  the code followed the softer one.  The stricter reading won, because the
  comment in the code, `docs/ARCHITECTURE.md` §D7 and the prelude of the
  harness all say the same: a supervised run (a run with a positive budget of
  nudges) ends through the call of `finish'; a text answer that reports a
  result is nudged into that call, and the nudge carries the state of the
  work, so the model continues instead of starting the task over.  A run that
  asked for no supervision (a budget of zero) still ends on the word of the
  model, because there is nobody to nudge it.  The record of such a run names
  the shape: "the model reported a result without calling `finish' N times".
  The claim `a-text-answer-does-not-end-a-supervised-run' is registered, and
  the controls of the two claims of the completion path (the supervision of the
  run) bite: the check fails on its own assertion, not on an error of the code.
  The wave changed the checks of others as well, and this is said here and not
  hidden: twelve checks and six unit test files ended their run in words, and
  their fake models now call `finish' (or the check asks for no supervision,
  when its subject is not the path of the completion); docs/PLAN.md §16.31.
- The journal of a live run lies in the working tree, and the model can erase
  it: in the run of wave 50 the model deleted its own journal
  (`rm -f sessions/wave50-1.jsonl').  The observation of a run is therefore not
  protected from the run itself; this is an open defect of the harness and not
  a wave yet.
- The working directory of a session (`cwd') is still not applied to the
  tools: in the live check the `bash' of the agent ran in the directory of
  the process, not in the repository of the task (docs/PLAN.md §17.1).
- The live stand of the transport was at fault, and not the provider: it stopped
  waiting at the first line that arrived, and the empty string that a
  reasoning model sends between its thinking and its answer was the absence of
  an answer.  The decision what counts as an answer now lives in the kernel
  (lib/yeah-answer.el, since the wave 49) and is tested offline — text with
  content and a tool call are answers, the empty string, the streaming sentinel
  and the reasoning are not (the claim
  `the-live-stand-waits-for-an-answer').
- Stage 6 is implemented offline: the run context owns the session, the
  transport, the answerer and the rules of one run, and the three
  placements — attached, service, batch — write the same events for the
  same task. The bridge to the buffers of an attached Emacs is off until
  the operator turns it on; it is checked against a live Emacs server
  (a real daemon) by tests/checks/check-bridge-live-server.el.
- Stage 5 is implemented offline: the ACP agent and the MCP server speak
  newline JSON-RPC over stdio and over a local socket, the `emacs__*`
  handlers are real, and the MCP client imports foreign tools. The wire is
  now driven by a third-party client (xenodium/acp.el) with a fake model;
  the service path with a live provider is covered by
  tests/live/live-service-path.el;
  what is still not proven is a real editor against a live provider.  Two
  limits are not hidden — the stdio server answers one request at a time
  (a blocking stdin read stops the event loop, so a cancel cannot preempt
  a running prompt there; the socket transport can), and a live provider
  has not driven the MCP server.
- REPL still contains placeholders. Do not build new public behavior on
  top of it while its stage's prerequisites are unmet.
- Stage 4 is implemented offline and verified against a live provider:
  `M-x yeah`, journal commands, the Org export, doctor and a package-vc
  bootstrap exist.  A real model (MiniMax-M3.1-Flash) finishes the Stage 1 coding
  task, and the interactive path works against a live provider.  The
  clean-Emacs install path is network-tested against the published
  repository (tests/live/live-clean-install.el): the public alpha gate is
  closed; v0.2.0 carries the Emacs-native interface.
- The interface is seen, not only described: `tests/pixel/` draws the journal
  and the approval view in Emacs itself under a virtual frame server and
  photographs the screen; `./scripts/dev pixel` compares the pictures with
  each other and with the same buffer without the interface.  It needs a
  frame server, a terminal emulator and ImageMagick but no provider key, so
  it lives outside the map — like the live checks — and is registered in
  `docs/LIVE-EVIDENCE.md`.  A stored golden picture is still open.
- Stage 3 is implemented offline: the Plan and Build permission profiles,
  a persistent pending FIFO, frozen inputs,
  steering at batch boundaries, cancellation, nudges and deadlines have
  integration tests, including synchronous callback races. The journey of a
  person — ask, steer, quit, restart, withdraw, recover, cancel — is checked
  end to end with a fake model.
- Stage 2 is implemented offline: usage calibration, asynchronous compaction,
  pruning events and corrupt-tail recovery are covered by unit/canary tests.
  The compatibility `yeah-context-summarize` never waits; real providers use
  the asynchronous API. Live-provider acceptance remains unverified.
- Stage 1 is implemented offline: coding tools, tick editing, async jobs,
  output artifacts and Emacs introspection pass their unit and end-to-end
  checks. Live-provider acceptance has not been verified.
- Stage 0.5 is implemented: module comments match current behavior and no
  longer reference nonexistent decisions/Tier/ROADMAP documents. Stage 0.4
  is implemented: the project migrated to math-coding v5; `mathc run`, `map`
  and `gate` work with the installed v5 binary.
- Stage 0.3 is implemented: tool failures are bounded, model-facing results
  are strings, and duplicate async callbacks cannot settle a call twice.
- Stage 0.2 is implemented: PTC is disabled by default and the demonstrated
  higher-order-function bypasses have regression tests. It remains an
  experimental restricted evaluator, never a sandbox for untrusted code.
- Stage 0.1 is implemented: gptel requests use a private, version-checked
  adapter without global hooks. Recheck compatibility whenever gptel changes;
  supported pinned versions are declared in `lib/yeah-gptel.el`.
- A `holds` claim proves its stated check only, not overall product readiness.
- The owner named the order of the next waves on 2026-11-16 (az): wave 41
  (the deterministic verifier of the bridge), wave 42 (the process of the
  server), wave 43 (the surface of ACP for an orchestrator), wave 44 (parallel
  children in a live turn).  The plan is `docs/PLAN.md` §18, and the decision
  is recorded by the method as the judgment claim
  `the-owner-decided-the-order-of-the-next-waves` — a claim whose evidence is
  a human review, not a machine verifier.  Three decisions of the owner stay
  open, and no agent may take them: the threshold of the parity, the
  classification of a run that the provider silenced, and the budget of the
  supervision of a child (`docs/PLAN.md` §17.2, §18.5).
- Everything that is still open is written down in one place:
  `docs/PLAN.md` §17 — the work an agent may do, the decisions only the owner
  may make (§17.2), and the order to follow when the owner says nothing
  (§17.3).  Read it before starting the next wave; do not resolve an owner
  decision silently.
- The integration with the orchestrator Paseo is live: the provider `yeah` is
  registered by the plugin in `plugin/yeah-provider/` (the decision of the
  owner on 2026-11-18 — the plugin was outside the repository and outside
  version control before that), the agent runs, its text reaches the timeline
  and its permissions reach the person.  Four gaps of the surface remain open
  and are written down in `docs/PASEO-INTEGRATION-PLAN.md`: the `cwd` of a
  session does not reach the tools (the agent works in the directory of the
  daemon, not in the repository of the task), the route of ACP in Paseo
  refuses a steering message, the outcome of a run does not travel over the
  wire, and the plugin speaks to a fresh Emacs per connection instead of the
  service of the kernel.  The order of the work is the plan of the owner
  (`docs/PLAN.md` §18: waves 42 and 43); the plugin is TypeScript and lives
  outside `lib/`, which stays Elisp only.
- The order of the work on the integration is written down in `docs/PLAN.md`
  §19: it lays the order of the owner out over the waves and adds the four
  points that the plan of the owner does not name (P-A…P-D).  Wave 54 is done
  (2026-11-18): the spin of the server does not reproduce on the code of that
  day, and the bound of one per cent of a core over ten seconds is now a
  check.
- The finding that moves the order: `session/close` is a method of ACP, and
  the client of Paseo already calls it (`connection.ts:690-698`, the SDK sends
  it as a request and the error is swallowed).  The kernel answers `-32601`.
  The extension `session/exit` does not reach that client by itself, so either
  the kernel answers `session/close` as well, or the plugin translates it.
  This is written down in `docs/PASEO-INTEGRATION-PLAN.md` §3.6 and §8; wave
  42 answered it with the method of ACP.
- Wave 42 (the first half) made the server end with the session of its client.  The
  core answers the request `session/close' — the method of ACP that Paseo calls when
  it closes the session of the agent, and the error of the answer is swallowed there,
  so a core that did not know the method kept its session and its process alive
  without a word.  The server over stdio serves one client, so the end of that
  session is the end of the process: it leaves its loop without waiting for the pipe
  of the client to close.  The server over a socket serves many clients and keeps
  running when one of them closes its session.  The live run of the self-development
  copy had built the end of the session as the notification `session/exit' — a name
  that is not part of ACP and that no client sends; the contradiction with the plan
  of the integration is written down in `waves/wave-42.json`, and the decision took
  the method of ACP.  The check is
  `tests/checks/check-the-server-exits-when-the-session-is-over.el', the claim is
  `the-server-exits-when-the-session-is-over' (docs/PLAN.md §16.32).
- Wave 43 (the first part) made the tools of a session run in the directory of the
  session.  The `cwd' that the client sends in `session/new' was recorded in the
  journal and in the frozen input of the run, and the tools did not read it: a
  relative path of a tool was counted from the directory of the Emacs process, so
  the `bash' of the agent ran in the directory of the installation of the CLI of
  Paseo and not in the repository of the task.  The session carries its directory
  now, and the tools of the run are dispatched inside the binding of it — one
  place, `yeah-session-with' in `lib/yeah-session.el`, and through it pass the
  synchronous tools and the asynchronous ones alike.  A session that was opened
  without a directory (an older journal) leaves the directory of the process
  alone.  The check is
  `tests/checks/check-a-session-runs-in-its-own-directory.el', the claim is
  `a-session-runs-in-its-own-directory' (docs/PLAN.md §16.33).
- Wave 43 (the second part) made the call of a tool carry its kind and its named
  arguments.  The `tool_call' of the wire named the tool and carried what it was
  called with, but no kind: a client that renders the call of a tool by its kind
  saw the name and nothing else, and the plugin of Paseo had to guess the kind
  from the name of the tool.  The arguments travelled as a positional list, so a
  client that looks for named fields found nothing and could not draw the edit of
  a file.  The tool declares its kind now — the new field `:kind' of the
  specification in `lib/yeah-tools.el' — and the request of the call in the
  journal carries the kind and the arguments under the names the tool declared;
  the wire carries both, and the journal stays the source of truth: a record
  written before the kernel named the arguments still travels the way it was
  written.  The names on the wire are the names the tool declared and the names
  the model was given (`path', `old_str', `new_str', `command'); the client of
  Paseo reads `filePath', `oldString' and `newString', and that translation is
  the work of the plugin, because it is the convention of Paseo and not the
  convention of the kernel.  The checks are
  `tests/checks/check-a-tool-call-carries-its-kind.el' and
  `tests/checks/check-a-tool-call-carries-named-arguments.el', the claims are
  `a-tool-call-carries-its-kind' and `a-tool-call-carries-named-arguments'
  (docs/PLAN.md §16.34).
- Wave 43 (the third part) made the permission profile of a session change over
  the wire.  The method `session/set_mode' did not exist and a client that asked
  was answered with `-32601'; the profile was chosen when the process started and
  could not be changed, so a person could not tell the agent to look without
  touching and the client of Paseo had no modes to show.  The modes of a session
  are the permission profiles of the kernel (`plan' and `build'), `session/new'
  publishes them with the mode the session is in, `session/set_mode' changes the
  mode, and the mode decides before anybody is asked: a mode that forbids an
  action refuses it without a question to the client.  The journal stays the
  source of truth — the change of the mode is a record of the session
  (`session-mode') and the wire carries it as the `current_mode_update'
  notification that ACP names, so a session that is opened again keeps the mode
  it was left in.  The check is
  `tests/checks/check-a-session-changes-its-permission-profile-over-the-wire.el'
  and the claim is `a-session-changes-its-permission-profile-over-the-wire'
  (docs/PLAN.md §16.35).  The check runs against a service on a socket and not
  against a server on stdio: a server on stdio reads its input between the
  requests, so the answer of the client to a question about a permission would
  come after the run it belongs to had ended.
- Wave 43 (the fourth part) made the model of a session change over the wire.
  Neither `session/set_model' nor `session/set_config_option' existed, and a
  client that asked was answered with `-32601'; the model was chosen when the
  process started, so a person could see the model and not switch it.  The
  catalog of the models is what the client may choose from, and it names the
  models that can really run: the models of the backend of gptel
  (`lib/yeah-model.el').  `session/new' and `session/load' publish them as
  `configOptions' -- an array, because `json-serialize' does not serialize a
  list of objects -- with the category `model' that the client of Paseo looks
  for, and `session/set_config_option' changes the model, refuses a model that
  no session may run on, and answers with the options and their new values.
  The journal names the new model (the record `session-model'), the wire
  carries it as the `config_option_update' notification, and a session that is
  opened again keeps the model it was left in.  The model reaches the call of
  the model without a change of the contract of the transport: the transport of
  the service is one for every session, and the model of the session is bound
  around the call of that transport (`yeah-model--current'), and
  `yeah-gptel-request' takes it when nobody named a model explicitly -- the
  same shape as the working directory of the session (wave 43, part 1).  The
  plugin of Paseo stopped being the one who changes the model: it registers
  every model it knows in the backend of gptel (the setting `models', a list
  through a comma) and does not intercept the change -- the request goes to the
  kernel, and the kernel decides whether the session may run on the named
  model.  The check is
  `tests/checks/check-a-session-changes-its-model-over-the-wire.el' and the
  claim is `a-session-changes-its-model-over-the-wire' (docs/PLAN.md §16.36).
  Two traps of this wave are worth keeping: the catalog of the models was
  empty because the check asked for `gptel-backend' through `fboundp', and
  that is a variable and not a function; and the check of the model and the
  check of the mode had the client of the checks written twice, so the client
  now lives in `tests/support/yeah-acp-client.el'.
- Wave 43 (the fifth part) made the MCP servers of a session reach the model.
  The `mcpServers' array of `session/new' and of `session/load' was checked
  and thrown away: the kernel verified that it was an array and forgot it, so
  a client that named a server got a session whose model could not use a
  single tool of it.  The servers the client names are connected
  (`lib/yeah-session-mcp.el'), the handshake of MCP is spoken (initialize,
  then tools/list), and the tools of those servers become ordinary entries of
  the registry of the runs of that session -- only stdio is spoken, and a
  server of another transport is refused by name; a server that does not
  answer in ten seconds refuses the session rather than opening it without
  the tools the client asked for.  (Wave 66 amended this sentence and not
  the wave: the transport of HTTP was added to the transports the kernel
  speaks, because the orchestrator names its own MCP server over HTTP and no
  agent of Yeah could run inside it at all.)  The tools live in the snapshot of the
  registry of the run, and not in the shared registry, so the tools of one
  session do not leak into the runs of another.  The journal holds only the
  names of the servers: the command of a server and its environment may hold
  secrets.  The environment of the server is given by the program `env' in
  the command line, because `make-process' in Emacs 30 knows no
  `:environment' and `process-environment' is a variable, not a function.
  This wave found a defect of the core: the deferred permission -- the answer
  of the person comes later, and the route of ACP defers the permission of
  every tool -- ran the tool outside the binding of the registry, so a tool of
  a session was not found and the run hung; `yeah-turn--run-or-refuse' binds
  the registry of the turn around the call of the tool now.  The check is
  `tests/checks/check-the-mcp-servers-of-a-session-reach-the-model.el' and the
  claim is `the-mcp-servers-of-a-session-reach-the-model' (docs/PLAN.md
  §16.37).  Four traps of this wave are worth keeping: `json-serialize' in
  Emacs 30 reads a list as a plist, so an array on the wire is a vector and an
  object is a hash table; the properties of a schema arrive as a plist with
  keyword keys, and the name of a keyword carries its colon (`symbol-name' of
  `:text' is ":text", not "text"); `force-output' and `flush-output' do not
  exist in Emacs 30, neither as a function nor as a macro, while the stdout of
  a batch Emacs is not buffered a line at a time; and `mcpServers: null' passed
  the check "this is an array" and then went into `mapcar'.
- Wave 65 made the wire tell the orchestrator how the run ended.  The kernel
  writes into its journal everything a person needs to know about a run -- the
  tokens it spent, the nudge that pushed it, the run that ended without an
  effect and the error that stopped it -- and the wire carried none of it: the
  client of the orchestrator saw `stopReason' and the words of the agent, and a
  run that ended without an effect looked like a run that had ended.  The
  kernel projects the outcome now, and only to the clients that asked for it:
  the client announces `yeah.runOutcome' in the `_meta' of its capabilities at
  `initialize', the same way it asks for the queue events (`yeah.queueEvents').
  The tokens travel as `usage_update', which is a part of ACP; the nudge, the
  unfinished run and the error travel as a notification of the method of Yeah
  (`yeah/outcome'), which is not a method of ACP and which the plugin of the
  orchestrator translates into a vendor update.  A client that knows nothing of
  the vocabulary of Yeah is served plain ACP, as it was before.  The size of
  the context in `usage_update' is the budget of the kernel and not the window
  of the provider: the kernel does not know the window of the provider and
  does not guess it.  The wave found that the schema of the wire
  (`schemas/acp-v1.json') was behind the implementation -- waves 42 and 43 had
  added `session/close', `session/set_mode', `session/set_config_option',
  `current_mode_update' and `config_option_update' without touching it -- and
  the schema is the measure of the wire, so the wave brought it in line.  The
  check is `tests/checks/check-the-wire-tells-the-orchestrator-how-the-run-ended.el',
  the claim is `the-wire-tells-how-the-run-ended' (docs/PLAN.md §16.49).  The live
  path was measured on 2026-11-19 (06:05) with the wire of the plugin against the
  real kernel: `nudge' three times and `unfinished' once reached the orchestrator
  as the notices of the plugin.  What nobody watched is how the notice is drawn in
  the UI of the orchestrator, and the command line of Paseo cannot show it: the
  curator of the activity of Paseo has no branch for the type `notification' and
  skips such an item in silence.  A reader who looks for the notice in
  `paseo logs' must not conclude that the wire carried nothing.
- Wave 66 gave the kernel the transport of MCP over HTTP.  No agent of Yeah
  could run inside the orchestrator Paseo, and the reason was the transport and
  not the model, not the tools and not the wire of ACP: the orchestrator names
  its own MCP server over HTTP (`{type: http, url: http://127.0.0.1:6767/mcp/agents?…,
  headers: [Authorization: Bearer …]}' -- `toAcpMcpServers',
  `withRuntimePaseoMcpServer'), and the kernel spoke the stdio transport and
  no other, so the session was refused by name ("Yeah speaks stdio only") and
  the live run died on that line.  The transport is a property of the agent and
  not of the plugin, so it was repaired in the kernel: `lib/yeah-mcp-http.el'
  is a minimal asynchronous HTTP/1.1 client on `make-network-process'.  The
  socket is read as binary, because the sizes of the chunks of HTTP are
  measured in bytes; the bytes become text in one place only
  (`lib/yeah-text.el'), so a byte that is not text cannot kill the process.
  The answer of MCP over HTTP comes as the stream of the events of MCP over
  HTTP, and the socket is closed after the message that carries an `id' -- the
  server of the SDK of the orchestrator keeps no state and its stream does not
  end by itself.  The headers `Mcp-Session-Id' and `MCP-Protocol-Version' are
  sent, so a server that keeps a state works too.  The transport `sse' is
  refused by name, and so is `https': there is no TLS in a socket of Emacs.
  The kernel declares the transport in the handshake of ACP
  (`mcpCapabilities: {http: true, sse: false}').  The check is
  `tests/checks/check-the-mcp-servers-of-a-session-speak-http.el', the claim is
  `the-mcp-servers-of-a-session-speak-http' (docs/PLAN.md §16.50).  The stdio
  path did not move: `check-the-mcp-servers-of-a-session-reach-the-model.el' is
  still green.
- Wave 67 stopped the journal of a project from filling with sessions that
  never happened.  The orchestrator reads the catalog of the models and the
  modes through a real session: `discover()' calls `session/new' and never
  closes the session it opened, and the kernel wrote the file of the session
  when the session was opened -- a file with a single header and nothing else.
  Every list of the models and every diagnostic left one more such file
  behind, and the journal of a project filled with them: in the place where a
  person looks for the truth about a run.  The file of a session appears now
  when the session writes its first record, and a session that never did
  anything leaves no file at all; the header is still the first line of the
  file, the ids are still monotonic, and the log is still append-only.  A
  person who wants to see a session in the list of the sessions of the project
  before it did anything has a switch for that
  (`yeah-session-journal-from-the-start', off by default), and that switch is
  what the control of the claim turns.  The unit test that named the old
  behaviour was amended and not deleted.  The wave does not remove the files of
  the old behaviour: the journal is append-only and the kernel deletes
  nothing.  The check is
  `tests/checks/check-a-probe-of-the-catalog-leaves-no-empty-session.el', the
  claim is `the-probe-of-the-catalog-leaves-no-empty-session' (docs/PLAN.md
  §16.51).
- Wave 69 made the answer of `session/prompt' carry the cost of the turn.  The
  orchestrator counts the tokens of a run of opencode and never saw the tokens
  of a run of Yeah: it takes them from the field `usage' of the answer of the
  prompt (`packages/server/src/server/agent/providers/acp-agent.ts'), and the
  answer of Yeah carried a stop reason and nothing else; the handler of the
  notification `usage_update' of the orchestrator is empty (`void update;'), so
  the notification is of no use to it either.  The kernel knew the tokens: the
  provider reports them (`lib/yeah-gptel.el' puts them into the info of the
  answer as `:yeah-usage'), the turn writes them into the journal as the event
  `usage', and the journal of the session holds them -- but none of it went on
  the wire.  The answer of `session/prompt' carries the usage of its turn now:
  the tokens the provider reported, as `inputTokens', `outputTokens' and
  `totalTokens'.  The usage is the usage of the turn and not the usage of the
  session -- the records of the usage of a run share the run id of that run,
  and a run is one prompt.  A provider that reported nothing has no field in
  its answer: the kernel has no tokenizer of the provider and does not guess
  the cost of a run (`yeah-context-usage' holds the estimate of the context,
  and that is the budget of the kernel and not the bill of the provider).  The
  field is the field of ACP -- the `Usage' of the schema of the protocol, marked
  unstable by the protocol itself -- and the schema of the repository names it
  now (`schemas/acp-v1.json').  The fix is in the kernel and not in the plugin:
  the plugin translates what is not ACP (the outcome of a run), and the tokens
  are ACP.  A client that knows nothing of the field ignores the key.  The
  check is
  `tests/checks/check-the-prompt-response-carries-the-usage-of-the-turn.el',
  the claim is `the-prompt-response-carries-the-usage-of-the-turn' (docs/PLAN.md
  §16.55).  Two controls of the claim bit in copies of the tree, each by the
  assertion of the check and not by a crash: the usage taken out of the answer
  (the check said "the answer to the prompt carried no usage") and the usage
  summed over the whole session instead of over the run (the check said "the
  second prompt of the session: it reported the tokens of the session and not
  the tokens of its turn: ... 2500 is not 1300").  The live run of 19 November
  answered through the orchestrator in about eleven seconds, and `LastUsage'
  did not appear: the SDK connection of the plugin of the orchestrator
  (`@getpaseo/plugin' 0.15.2, `runAcpProvider') drops the field `usage' from
  the answer of `session/prompt', and there is no hook for that answer at the
  `AcpTransformer'.  That route was repaired from this side in wave 71, and
  a reader who sees no `LastUsage' in the orchestrator must still not read it
  as a missing field in the answer of the kernel.
- Wave 70 made the journal hold the cost of one request once.  The live run of
  19 November wrote two records of the usage of one request with the same
  numbers (13775 in and 528 out), and the first request of that run -- the
  model that did not think -- held one.  The cause is in the transport of gptel
  and in the kernel together: the callback of the request is called with
  `(cons 'reasoning ...)' and then with the answer, and the same `info' goes
  to both, and the kernel wrote the usage of the request for every shape that
  carried it.  A model that thinks was paid twice in the journal, and the cost
  of the run that the orchestrator shows was twice the cost of the run.  The
  road to the answer -- the reasoning of the model, the result of a tool that
  ran and the sentinel of a stream that is over -- is not a second request:
  `yeah-answer-road-p' (`lib/yeah-answer.el') names those shapes, and the
  record of the usage in `lib/yeah-turn.el' stands under the guard
  `(not (yeah-answer-road-p answer))'.  The decision lives in the module that
  already owns the decision of what counts as an answer (wave 49), and the turn
  asks it.  The journal is append-only and the wave does not rewrite it: the
  records that were written twice stay where they are.  The notification
  `usage_update' is untouched -- it is the size of the context and not the
  cost of the turn -- and a request that ends in an error and carries no
  answer writes nothing, because the provider never reported those tokens.
  The check is
  `tests/checks/check-the-journal-holds-the-usage-of-a-request-once.el', the
  claim is `the-journal-holds-the-usage-of-a-request-once' (docs/PLAN.md
  §16.56).
- Wave 71 made the orchestrator see the usage of the turn.  The answer of
  `session/prompt' reaches the orchestrator through a connection that keeps one
  stop reason and throws the rest away, so the field `usage' of the answer of
  wave 69 never reached the counter of the agent, and the update of the context
  (`usage_update') carries the size of the window and not the tokens of the
  turn.  The tokens of a turn travel now by a path this repository owns: the
  kernel sends them as the notification `yeah/usage' -- a method of Yeah and
  not of ACP -- to the clients that asked for them in the `_meta' of their
  capabilities (`yeah.usage'), the plugin of the orchestrator announces that
  method in the request `initialize' and translates the notification into the
  event of the provider `session.usage', and that event is the only one the
  orchestrator carries into the counter of the agent.  The translation
  completes one part of the usage with the other and replaces neither: the size
  of the window comes from the update of the context, the tokens come from the
  kernel, and the counter holds both whichever of the two the orchestrator
  handles last -- the first live run after the repair showed zeros for exactly
  that reason.  The vocabulary travels only where it was asked for: the client
  that announced nothing receives nothing, and the kernel sends nothing when
  the provider reported nothing.  The check is
  `tests/checks/check-the-orchestrator-sees-the-usage-of-the-turn.el', the
  claim is `the-orchestrator-sees-the-usage-of-the-turn' (docs/PLAN.md
  §16.57).  Two controls bit in copies of the tree, each by the assertion of
  the check and not by a crash: the call of the kernel that sends the usage
  (the check said "the wire carried no usage of a turn") and the call of the
  plugin that reports it (two tests of the plugin failed).  The live run of 19
  November (`e1cdf9b6-9269-4bea-8602-2ddf1564f482') shows
  `LastUsage  InputTokens: 12960, OutputTokens: 99', where the run before it
  showed zeros.
- Wave 72 gave the plugin of the orchestrator a live core to talk to.  The
  plugin raised its own Emacs for every connection, and that has a hard
  boundary: over a pipe the kernel reads the next request only after the turn
  has settled, so a request that arrives during a turn waits for the end of
  the turn.  The kernel already speaks ACP over a Unix socket
  (`yeah-acp-serve-socket`), and that is the path on which a request during a
  turn is read while the turn runs.  The placement is now a setting of the
  plugin (`serviceMode`), and the default is the old behaviour: one Emacs per
  connection, so a host that chose nothing changes nothing.  The service lives
  once, and the life of the service is tied to the life of its host.  The
  check is `tests/checks/check-the-plugin-talks-to-the-core-over-the-socket.sh',
  the claim is `the-plugin-talks-to-the-core-over-a-socket' (docs/PLAN.md
  §16.58).  The wave did not prove the real command of the service: it needs
  gptel and the key of the provider, and the check raises the core with its
  own command and a fake model.
- Wave 73 made the plugin steer the running turn instead of replacing it.  The
  orchestrator can send a message into a running turn without replacing it --
  that is steering, and a provider declares it with the capability
  `prompt.steer'.  The ACP adapter of the library of the orchestrator does
  not know the capability, and a request with `delivery: "steer"' never reaches
  the kernel: the adapter interrupts the turn and starts a new one.  The plugin
  declares the capability -- in the connection and in the session it opens --
  and translates such a request into `session/steer' of the kernel, which the
  kernel already knows (`lib/yeah-acp.el'); the request never reaches the
  adapter, so the turn is not interrupted, and the orchestrator is answered
  with the identifier of the turn that runs, which is what it checks.  The
  check is `tests/checks/check-the-plugin-steers-the-running-turn.sh', the
  claim is `the-plugin-steers-the-turn-instead-of-replacing-it' (docs/PLAN.md
  §16.59).  The live run of 19 November closed the gap the check left open:
  the orchestrator sent a clarification into a running turn, the kernel took
  it into the turn (`input-taken' with the kind `steering'), and the model
  ended the turn at once with a short answer instead of going on with its plan
  (docs/LIVE-EVIDENCE.md).  Steering is timely only in the service placement
  of wave 72: over a pipe the request is read after the turn has settled and
  becomes an ordinary ask.  The adapter of the library of the orchestrator
  still replaces a turn when it is given a steering request -- that is a
  decision of the owner, and the plugin works around it.
- Wave 74 stopped the plugin from believing a dead socket.  The service of
  wave 72 leaves its socket file on the disk when it dies, and the plugin
  decided that such a service is alive by the presence of that file.  The live
  run of 19 November found it: the kernel was killed by the OOM-killer of the
  host, the socket stayed, and the next agent came to a socket with no kernel
  behind it -- the orchestrator answered `ACP connection closed' until the
  plugin was reloaded by hand.  The plugin asks the socket now whether anyone
  listens on it, and a socket that nobody listens on is removed and the
  service is raised again.  The check is
  `tests/checks/check-the-plugin-does-not-trust-a-dead-socket.sh', the claim
  is `a-dead-socket-does-not-pass-for-a-live-service' (docs/PLAN.md §16.60).
  The wave does not make the service survive the death of the kernel, and it
  does not remove the cause of that death: the context of the run had grown
  past the window of the model.
- The recalculation of 19 November (16:03–16:37) found that two registered
  controls had never bitten: the control of
  `the-prompt-response-carries-the-usage-of-the-turn` had no closing delimiter
  of its `s' command at all (`sed` answered `unterminated 's' command', the
  file did not change), and the control of
  `a-tool-that-returns-bytes-does-not-kill-the-harness` matched a call that the
  code no longer has, so the subject changed and the check still passed.  A
  claim whose control does not bite is not established, so both claims stood
  unestablished in the map until the controls were repaired and re-verified on
  that day: both are `pass' with `negative control proven' now (docs/PLAN.md
  §16.61).
- The same recalculation refuted one claim outside the package:
  `the-pilot-that-runs-out-of-time-leaves-no-server-behind` answered "the
  server of the pilot stayed behind after the limit passed".  The check waits
  fifteen seconds of wall time for that death, the host was swapping (4.7 GiB
  of swap, zram full) while the run took twice as long as usual, and the check
  passes outside the run -- eleven times before, and twice more after.  The
  cause is not established, the map stood in `red' because of it, and the
  repair (a check that does not depend on the speed of the host) was a wave of
  its own; the owner took its order on 2026-11-19 -- wave 75, the bullet below
  (docs/PLAN.md §16.62, §16.63).
- Wave 75 repaired that refutation, and the repair is a change of the measure:
  the server of the pilot dies at once when the limit passes (the state of its
  process changes from `S' to `Z' and the entry leaves `/proc' within a tenth
  of a second), and what lingers is its corpse, which waits to be reaped by the
  init of the host -- the init of the host is not the subject of the claim.
  The check now reads the state of the process in `/proc/<pid>/stat' and counts
  a zombie as dead, so the measure of the claim does not depend on the speed
  of the host; the fifteen seconds stayed the bound of the wait and are no
  longer the measure of the death, and the wording of the claim followed the
  measure ("dead" and "still running", not "gone" and "still alive").  The
  host that refuted the claim (swapping, zram full) was not reproduced, so
  nobody may quote this wave as the proof that the refutation is gone
  (docs/PLAN.md §16.63, waves/wave-75.json).
- The gate of 19 November 2026 (18:29–18:44 UTC, after wave 75) holds 152
  claims of 153 as `holds (current)`: no `inconclusive`, no `refuted`,
  `uncovered: 0`.  The one claim that was not current was the order of the
  waves, which the owner named: its scope is `docs/PLAN.md`, the document
  moved with the waves, and its evidence was stale -- a human settles it, and
  the owner settled it on 2026-11-19
  (`mathc record the-owner-decided-the-order-of-the-next-waves owner --by az
  --outcome pass`).  The map after that record is `green`: 153 claims of 153
  hold, `uncovered: 0`, and the exit code is 0 (docs/PLAN.md §16.64).
- Wave 76 gave the agent a mode without a person and a trash instead of a
  deletion, and the two are one decision: a mode that allows everything is
  only as safe as the tools it allows.  The profile `auto` allows the tools
  that change the world without a question (the orchestrator runs the agent
  unattended, and a question nobody answers is a hang), the `rm` of the
  shell of the agent is a script that moves what it is given into the trash
  of the user (`lib/yeah-trash.el`), and the commands that destroy in place
  are refused by name (`lib/yeah-shell-guard.el`).  The guard is a list of
  forms and NOT a sandbox: there is no boundary of the working directory
  either, and the secrets of the output of a tool are written into the
  journal as they are.  The map of what is protected and what is not is
  `docs/AGENT-SAFETY.md`, and it names two debts of `docs/ARCHITECTURE.md` §8
  (the workspace paths and the secrets in the log) that the architecture
  declared and the code did not make (docs/PLAN.md §16.65).
- The order of the work is the catch-up plan, `docs/ARCHITECTURE-CATCHUP-PLAN.md`:
  the code catches up to `docs/ARCHITECTURE.md`, and the diagrams follow the
  code, not the other way round.  The owner named the order on 2026-11-20:
  A0 (the decision about the waiting states), then A1, then A3, then the tracks
  B (the contract of a tool) and C (the scopes of an approval) -- both of them
  independent of A, so they may run in parallel -- and the waves of the
  diagrams (D) and of the documentation (E) after them; the waves of the
  diagrams wait for the decision of the owner about PlantUML.  A1 is wave 77,
  A3 is wave 78, B4 is wave 79; the rest of B, all of C, D and E are open.
- Wave 77 made the waiting states part of the state machine.  The table of the
  machine (`lib/yeah-loop.el`) was rewritten against the real paths of the
  runtime: twenty cells became thirty-one, the dead cells (`tick-resume`,
  `ask-user`) are gone, the living ones moved onto the path they really take
  (`permission-ask` leads from `awaiting-tool` to `awaiting-user-permission`,
  `answer` and `timeout` lead back), and the cells of the waiting were added
  (`nudge`, `rate-blocked`, `rate-relief`).  The runtime walks the table and
  not around it: a state changes only through `yeah-turn--tick`
  (`lib/yeah-turn.el`), and a run that is nudged no longer writes a false
  `completed` into its own history.  The state `awaiting-user-input` was
  removed -- twelve states became eleven -- because no event of the runtime
  ever entered it, and the kernel has no mechanism "the model asks the
  person" (docs/PLAN.md §16.66).  The claim `a-run-waits-in-a-state` says
  that a run which waits for a person stands in `awaiting-user-permission` and
  leaves it when the answer comes, and that a run whose provider was busy
  passes through `blocked-on-rate`.  What the wave does not do: the state of a
  run is not written into the journal, so a run that was waiting when Emacs
  died is still lost, and the state of the waiting is not shown to the person
  (`lib/yeah-faces.el` knows it, the place that shows it is another wave).
- Wave 78 said the table of the machine out loud.  A check reads the sources of
  the kernel with the reader of Emacs, looks for the calls of `yeah-turn--tick`
  and for the label each of them takes, and says that every label of the table
  has such a place; the same check walks the table from the first state and
  says that every state is reachable.  The check is static on purpose: a
  dynamic one would need a run that takes every move, and there is no such run
  -- a run that meets no busy provider never takes `rate-blocked`, and a run
  that never grows long never takes `budget-overflow`.  The code of the kernel
  did not change: the table of wave 77 was already honest, and the wave only
  keeps it that way (docs/PLAN.md §16.69).  The claim
  `every-transition-of-the-table-is-taken` says that the runtime has a place
  where it takes every move of the table -- not that a run takes every move,
  which no run can do.
- Wave 79 closed the vocabulary of the kinds of a call.  A tool that declares
  a kind outside the vocabulary is refused by name, and the message names the
  tool and the kind (`lib/yeah-tools.el`); before the wave such a kind passed
  silently and the call went on the wire as `other`.  The vocabulary is a
  convention of the kernel and not an enumeration of the protocol:
  `schemas/acp-v1.json` declares the kind of a call as a plain string and
  names no values.  The wave also corrected the premise of B4 in the catch-up
  plan, which named a place of the defect that does not exist (docs/PLAN.md
  §16.70).
- Wave 80 made the proof of the table match its promise.  A discriminator found
  that the check of wave 78 promised a cell of the table and proved a label: the
  cell `(compacting error . failed)` was replaced with
  `(compacting interrupt . interrupted)`, the machine could no longer move a run
  out of `compacting` into `failed` on the label `error`, and the check stayed
  green.  The check now speaks about cells: the machine makes every cell, the
  runtime takes the label in a place of the code that lives, a fan of a label
  covers exactly the states a run can live in and ends in one state, and every
  cell is walked.  The liveness of a place is a graph: a root is an autoload
  cookie, a reference of the tests or of the scripts or of a top-level form of
  `lib/`, and the walk goes on by the calls.  The label is read from the
  position of the label and from nowhere else.  The claim of wave 78 is amended
  and not renamed (docs/PLAN.md §16.72).
- Wave 81 gave the site a pipeline for its diagrams.  The diagrams of the
  architecture were a drawing that nobody could redraw: `scripts/dev diagrams`
  now renders every diagram of `site/diagrams/` into `site/assets/diagrams/`,
  two pictures per diagram, the light one and the dark one.  PlantUML is found
  by the script itself — the chain of the search lives in one place,
  `scripts/lib/tools.sh`, the function `find_tool`, and it is the same chain
  for every tool: the variable of the environment, the command on PATH, the
  binary of the user in `~/.nix-profile/bin`, and the store of nix when the
  caller names the glob (the step in the store is given to PlantUML only: the
  store holds many versions of Emacs, and the version of Emacs must not be a
  random choice).  The script answers with the code 3 when the instrument is
  not there, so a missing instrument is never read as a fine diagram.  The skin
  of a theme is a file of its own (`site/diagrams/palette-light.puml`,
  `palette-dark.puml`) and its colours are the tokens of the site
  (`--face-default-bg`, `--face-default-fg`, `--face-fringe-bg`,
  `--face-divider`, `--face-prose` of `site/styles.css`).  The wave draws no
  diagram: the first one — the machine of the states, born out of the code — is
  the wave D1 (docs/PLAN.md §16.73).  A discriminator found the proof weaker
  than the promise: the chain of the search is not measured step by step, one
  diagram is not every diagram, the code 1 of a failed PlantUML is not
  measured, and the colours of the picture are checked against numbers instead
  of against the tokens of the site.  The code of the wave is honest; the proof
  is repaired in wave 83 (docs/PLAN.md §16.73).
- Wave 82 repaired the proof of the table of the machine.  The check promised a
  cell and proved a label, and the reason was in two dead branches: the
  arguments of a form are `(cdr form)`, and the code took `(cdr (cdr form))`,
  so the state of a place was never read and any place of a label witnessed any
  cell of that label.  The check now reads the state of a place from its guard,
  binds every cell to its `FROM` (a place that takes the move of the cell from
  another state is named), compares a fan of a label with the runtime and not
  with the table (a runtime that narrows a fan breaks the check), and separates
  "live for the runtime" from "live for the tests": a root of the runtime is an
  autoload cookie or a reference of a top-level form of `lib/`, and a definition
  that only the tests call is dead for the runtime.  An error of the check is a
  verdict and not the death of the process.  Sixteen of the thirty-one cells
  rest on a guard that says nothing about the state — the check counts those
  cells and names them, and only the runtime can make them strong.  The claim
  is amended and not renamed (docs/PLAN.md §16.74).  **A control must reach the
  subject of every requirement of its claim:** the gate of the package caught a
  control of this claim that broke the runtime and not the table, so the unit
  test of the table stayed green and the method said `inconclusive` instead of
  `pass` — the claim was not green until the control broke both.
- Wave 83 repaired the proof of the pipeline of the diagrams.  The pipeline
  works, but the check of wave 81 promised more than it proved: no step of the
  chain of the search was measured, one diagram is not every diagram, the code 1
  of a failed PlantUML was not measured, the colours of the picture were bound
  to numbers instead of to the tokens of the site, and the check leaned on the
  wording of the report.  The check now runs the chain four times — one step
  available each time (the environment, PATH, `~/.nix-profile/bin`, the store of
  nix) — draws two diagrams, derives the list of the expected pictures from the
  tree, measures the three ways PlantUML fails, reads the expected colours out
  of `site/styles.css` by the names of the tokens, and catches a skin that is
  baked into the code with a marker of the fixture.  No grep of the wording of
  the report is left.  The code of the pipeline, the skins and the site are
  untouched (docs/PLAN.md §16.75).
- Wave 84 gave the site a diagram that is born out of the code.  The machine of
  the kernel is a table (`yeah-state-list`, `yeah-loop--raw-transitions`), and the
  diagram of that machine is written out of the table: `lib/yeah-state-diagram.el`
  says the PlantUML source, `scripts/dev state-diagram` writes it, and
  `scripts/dev diagrams` generates it before it draws anything — a generation that
  failed ends the pipeline with its own answer, and nothing is drawn.  The source
  is committed (`site/diagrams/state-machine.puml`), and the check compares its
  bytes with the bytes that a **copy** of the kernel writes, adds a cell and a
  state to that copy and waits for the arrow and for the state, and reads the
  numbers of the machine out of the code.  **PlantUML does not read a dash in an
  identifier:** a name with a dash in it (`post-decide`) keeps its text as the
  label of the state and gets an identifier of its own (`post_decide`), and the
  ends of the arrows speak that identifier — the names of the machine are in the
  picture as they are.  `@startuml state-machine` gives the picture the name of
  the diagram and not the name of the file, and the pipeline learned to find the
  picture that a diagram which names itself writes.  `scripts/dev diagrams` needs
  the kernel now: a tree without one answers with the code 3 and draws nothing.
  The wave commits no SVG — the pictures of the site are waves D3 and D4
  (docs/PLAN.md §16.76).
- Wave 85 repaired the proof of the table of the machine, the second time.  The
  kernel is honest; the proof was not, and the check of the cells **could not
  fail at all**: the verdict stood inside a `dolist`, and `dolist' returns nil,
  so the check answered "yes" whatever the kernel said.  The verdict is out of
  the loop now, and the witness of a cell is read over **all** the places of its
  label and not over the first one.  A witness is a place **the runtime runs**:
  a place that only a name, a test or a script reaches is dead for the runtime
  and witnesses nothing — death and silence are two different things, so a
  **live** place that names no state witnesses a cell weakly, and that is a
  measurement and not a refusal.  A name is not a call: `'f' and `(function f)'
  name a definition, while the name in the first argument of `funcall' and of
  `apply' is a call, because the runtime calls the value there.  The state of a
  place is read from the guard around the place and from the chain of the moves
  before it, and a state bound to a local variable is read as well.  A fan is
  judged only when the runtime states the whole coverage of it — the coverage of
  the fan `interrupt' is not stated at all, and the check names that fan instead
  of blaming the runtime.  The report names the numbers: 31 cells, 17 labels, 11
  states, 23 places of a tick (all 23 live), 14 of the 23 naming the state and 9
  naming none, 8 of the 17 labels with no place that names a state, 15 of the 31
  cells resting on a place that names no state, 16 of the 31 proven by the state
  of their place, and 1 of the 2 fans with the whole coverage stated.  The
  claim is amended and not renamed (docs/PLAN.md §16.78).
- Wave 86 repaired the proof of the pipeline of the diagrams, the second time.
  The pipeline works, but two promises of the check were not measured: the chain
  of the search "lives in one place" was satisfied by a comment that named the
  file, and a copy of the body of the chain under another name was not seen at
  all; and "the picture is drawn from its own source" was measured by the label
  of the source, so a picture drawn from a cut source passed.  The check now
  looks for the sourcing line and the call of the chain, extracts the body of
  the chain from `scripts/lib/tools.sh` and searches every other file of
  `scripts/` for a copy of that body — name-blind — and for the steps of the
  search; and it compares every label of the source, the states and the arrows,
  with the texts of the picture.  The old check answers with the code 0 on a
  copy of the body and on a cut source; the new one answers with the code 1.
  The code of the pipeline, the skins and the site are untouched (docs/PLAN.md
  §16.77).
- Wave 87 repaired the proof of the diagram of the machine of the states.  The
  kernel and the pipeline are honest; the proof was not.  Two promises were not
  measured.  **The pipeline swallowed a failed generation**: the check ran the
  subcommand `state-diagram' in a tree without the kernel and waited for the code 3,
  but nobody ran the **pipeline** `scripts/dev diagrams' there — and a mutation that
  made the call of the generator conditional in the pipeline answered 0 and drew the
  pictures of yesterday, while both checks (84 and 86) stayed green.  The pipeline
  itself is run in a tree without the kernel now, and the check demands the code 3
  **and no picture at all**; the three answers are named apart: the pipeline answered
  and it is not 3, the pipeline answered 3 and drew pictures, the pipeline drew
  pictures although the generation failed.  And **the check fell with the wrong
  subject**: the comparison of the cells with the arrows was a comparison of numbers,
  so a generator that reads the table and leads every cell elsewhere passed, while
  the message said "the generator does not read the table" — false in both halves,
  the arrow was there with ends of its own.  Now **every** cell of the table is
  compared with its arrow by its ends (`from --> to : label'), the identifier of a
  state is computed by the check itself (PlantUML does not read a dash in an
  identifier: `post-decide' becomes `post_decide'), and the three cases are named
  apart: the cell is not in the diagram, the cell is drawn elsewhere, the label of
  the arrow is not the label of the cell.  A guard says that a comparison which did
  not finish is a failure and not a silence.  The kernel and the pipeline are
  untouched (docs/PLAN.md §16.79).
- Wave 88 repaired the proof of the table of the machine, the third time.  The kernel
  is honest; the proof was not, in two places.  **A place without a definition was
  counted as live**: the walk over the top-level forms of `lib/` gives such a place
  the name `nil', and the rule of liveness read the name `nil' as "a place the
  runtime runs" — a tick inside a `defconst' lambda that nobody calls was a witness
  of the cell `(post-decide nudge . deciding)', and the runtime takes that move not
  at all.  Such a place is dead for the runtime now, and the report names those
  places as a class of their own.  And **a place whose label cannot be read fell out
  of every verdict**: it witnessed no cell, was compared with no state and broke the
  chain of the moves of its neighbours — the fan `error' lost its whole coverage and
  stopped being judged, the runtime took the move `no-such-move' that the machine does
  not have, and the check answered with the code 0.  Such a place is a defect in
  itself now: the check names it by file and line and answers with the code 1.  The
  report is compared with the numbers measured before: a measurement that became
  smaller does not pass as the same one, because a proof that rests on less is
  weaker, and the check says so instead of being silent.  The price is named: the
  numbers of the report are nailed to the kernel of 2026-11-20, so a wave that
  changes `lib/' has to change the constant of the check too.  The kernel is
  untouched (docs/PLAN.md §16.80).
- Wave 89 repaired the proof of the pipeline of the diagrams, the third time.  The
  class of escape was named in the objection of wave 86 already, but the **text of
  the claim and its falsifier were stronger than the proof**: "the chain of the
  search lives in one place" was satisfied by textual probes, and a copy of the chain
  **rewritten in other words** (its own `type -P', its own `-f' for the profile)
  passed.  The check now looks at the **code of the pipeline**: the comments, the
  body of the heredoc and the calls of `find_tool' are taken out of `scripts/dev',
  and the words of the steps of the search are forbidden in the rest — a step built
  on the fly is not seen, and that is named.  The promise is brought to what is
  measured: the chain lives in one place **in `scripts/'**, `scripts/dev' reads it,
  calls it and does not write a step of the search itself, another script of
  `scripts/' does not define the chain and does not carry a copy of its body, a copy
  rewritten in other words is not seen, and the **search in the checks themselves is
  its own, by design** — the tree carries its own search in
  `tests/checks/check-the-state-diagram-comes-from-the-code.sh', and the promise says
  so outright.  The old check of wave 86 answers with the code 0 on the same
  mutation; the new one answers with the code 1.  The code of the pipeline is
  untouched (docs/PLAN.md §16.81).
- Wave 90 repaired the proof of the table of the machine, the fourth time.  The kernel is
  honest; the proof was weaker than its own doctrine in four places, and all four are one
  family.  **The walk of the code read a name as a call**: the head of a quoted list became
  a call, so a definition that named only a quoted list became a root of the runtime and the
  move inside it a move of the runtime — the doctrine of the check says the opposite (a name
  calls nothing), and the code of the walk said otherwise.  **A name in a list of names was
  a call**: the bindings of a `let`, the variable of the spec of a `dolist`, the pattern of a
  `pcase`, the types of the handlers of a `condition-case`, the type and the slots of a
  `cl-defstruct`, the name of a derived mode — the runtime reads them and does not run
  them.  **A tick that stands in data was a place of the runtime**: the runtime does not run
  a quoted form, so such a tick witnesses nothing.  Now **the walk does not go into data**:
  the operands of `quote` are names, the designator of `function` is a name, the parameters
  of a `lambda` are names, the body of a `lambda` is code wherever it stands, a list of
  names is names (the values of the bindings, the collection of the spec, the subject of
  `pcase`), the bodies of the clauses and of the handlers are code, and the walk goes into
  them.  The type, the options and the slots of a `cl-defstruct` are names and the value of
  a slot is code; the name of a mode and the name of its parent are names, the value of the
  keyword is code and the body of the mode is code.  The first argument of `funcall`/`apply`
  **stays a call** (the runtime calls the value there).  The promise was brought to what is
  measured: the text of the claim now says that the walk reads a name as a name and not as
  a call, and that a tick in data is no place of the runtime.  Twelve controls — three by
  the writer and **nine by the parent, independently of the report of the writer** — all gave
  the verdict asked for; three of the parent's controls measured the classes named by the
  review: a tick in a quoted form in a live function was quiet with the numbers of before
  (23/23), while the name of a type in a `cl-defstruct` and the name of a derived mode,
  each with a definition that nobody calls, answered with the code 1 and the class
  `:places-of-a-dead-definition` (expected 0, measured 1).  The kernel is untouched
  (docs/PLAN.md §16.82).
- Wave 91 repaired the proof of the pipeline of the diagrams, the fourth time.  The
  pipeline is honest; the proof was weaker than the promise in two places.  **The probe
  of "one place" was a probe of the wording**: it looked for five groups of words (the
  command on the PATH, the type of the shell, the binary of the user in the profile, the
  store of nix, the binary of a tool), and a step of the search written in other words
  was not seen.  And **two probes of a copy of the chain were literal**: the head of the
  chain was read as `find_tool()` with no space (`find_tool ()` is the same function),
  and the pair of the steps of the profile was read as `-x ... .nix-profile/bin/` with
  both markers on one line — so a full second chain that overlapped the common one
  passed.  Now **the chain is proved by the behaviour of the pipeline and not by its
  wording**: a copy of the tree whose chain hands out a **decoy instrument** — a PlantUML
  that writes a picture with a mark of its own, and an Emacs that writes a mark and calls
  the Emacs of the machine — is drawn by the pipeline.  A pipeline that takes the
  instrument from the chain draws the pictures of the decoy; a pipeline that searches for
  the instrument by itself draws the pictures of the machine and leaves no mark at all.
  The check demands the mark in every picture of the copy and the mark of the Emacs of
  the chain.  The textual probes are kept as a supplement: the head of the chain is read
  with a space or without it, the definition is looked for in every file of `scripts/`,
  and the steps are looked for in the whole of a file and in the code of the file.  The
  old check of wave 89 answers 0 on a mutation it cannot see; the new one answers 1.  The
  code of the pipeline is untouched (docs/PLAN.md §16.83).
- Wave 92 repaired the proof of the diagram of the machine of the states, the third
  time.  The kernel and the generator are honest; the proof was not.  **The comparison
  reported a duplicate cell as an absent cell**: the table of the machine named one cell
  twice, the diagram carried one arrow for the two cells, and the comparison fell into
  `report_absent` — so the check answered with the false subject "the generator does
  not read the table", while the generator read the table and the table said one thing
  about one event twice.  A false refusal with a false subject is worse than no
  refusal: it sends the reader to the generator, and the defect is in the table.  Now
  the comparison counts the cells the table names twice, the arrows the diagram carries
  for them and the arrows the diagram repeats, and the defect has a subject of its own:
  `twice` (the table names the same cell more than once) and `twice-arrow` (the diagram
  carries the same arrow more than once).  The subjects of wave 87 stay where they are
  true.  **[Amended 2026-11-21, wave 95:]** their *names* are not the same any more:
  `leads` is now `label` and `label` is now `wrong-label` — the cases are the cases, the
  words are other.  **The check proves this on itself**: a copy of the kernel whose table names the
  same cell twice is compared with the diagram of the repository, and the comparison
  must name the duplicate and must not call the cell absent — and the old comparison of
  wave 87, put back into the new check, fails with two refusals, so the path of the
  duplicate is measured and not a comment.  The duplicate itself is forbidden where it
  belongs: the machine has a unit test of its own.  The kernel and the generator are
  untouched (docs/PLAN.md §16.84).
- Wave 93 repaired the proof of the table of the machine of the states, the fifth time.  The
  kernel is honest; the proof was not.  **The walk read a name in a position where a name
  stands as a call, and the class was not closed**: the objection of wave 90 said that the
  kernel holds no such position today, and that was false — the kernel holds 55
  `when-let`/`if-let`/`*when-let` and 3 `cl-labels` that the closed list of five positions
  did not name; on a tree where the runtime takes the move `idle --user-prompt--> deciding`
  no more, the check answered 0.  Now the walk knows the position of **every** form it
  meets: the special forms of Emacs are read out of Emacs itself (22), the macros of the
  kernel out of the files of the kernel (3), and the forms the walk meets out of the walk
  itself (55) — and a macro or a special form that the table of the positions does not know
  is a defect of the check, named by its file and its line.  **The body of a local function
  that nobody calls is not code the runtime runs**: the walk goes into the body of a local
  function whose name stands in the code of the form — a call, a call from a neighbouring
  local function, or the name as a value the runtime calls.  **A name in data is data**: the
  rule asks the same question the global walk asks — does the runtime call this name? — and
  a name in a quoted form that nobody calls is data.  The numbers of the report are
  unchanged and were not tuned: 23 places of a tick, 23 of them live, 14 name the state of
  the run and 9 do not, 15 cells rest on a place that says nothing about the state, 2 fans,
  55 forms met and 55 known.  The kernel is untouched (docs/PLAN.md §16.85).
- Wave 94 repaired the proof of the pipeline of the diagrams, the fifth time.  The code of
  the pipeline is honest; the proof was blind.  **The decoy was blind to a copy of the
  chain that resolves the instrument by the profile**: the decoy ran in a hermetic
  environment (the home of the user empty, the store of nix empty), so only the step of
  the environment and the step of the PATH resolved there; a copy of the chain that looks
  the instrument up in the profile of the user fell back to the chain of the repository
  silently, the pipeline took the instrument from that copy, and the check answered 0 — a
  proof that is green on a tree whose pipeline does not do what the claim says.  Now the
  decoy runs in an alive environment (the home with the profile, the store with the store,
  `PLANTUML` and `EMACS`, the `PATH`): all four steps of the chain resolve there, and every
  one of them resolves to the instrument of the machine and not to the decoy; the chain of
  the copy is the only thing that hands out the decoy.  The probe of the steps of the search
  refuses on **any** step it finds in **any** file of `scripts/` — before the wave it demanded
  a **pair** of steps (the one on the PATH and the one of the profile), and the copy of the
  finding F28, which used the step of the profile alone, passed; the probe of the second
  chain, which looks for a function with two or more kinds of steps under any name, is
  **duplicating** — two kinds include one, and the probe of the file has seen it already, so
  it cannot fire alone and adds a second line of refusal about the same defect and not a
  wider reach.  The requirement of the mark counts how many times it was asked — a
  requirement that was asked about nothing is noticed and not silently met.  **[Amended
  2026-11-21 by the discriminator of the waves 94 and 95: the words "the textual probes read
  all the files of `scripts/`" were false as a change — the probe of the file read all of them
  since wave 91; what changed is what it looks for.]**  **The boundary of the probe is named, and it is not the
  boundary of wave 91**: the decoy sees a copy that resolves the instrument in the
  environment of the decoy, and it does not see a copy that resolves it in a place that
  the environment of the decoy does not provide.  The code of the pipeline is untouched
  (docs/PLAN.md §16.86).
- Wave 95 repaired the proof of the diagram of the machine of the states, the fourth time.
  The kernel and the generator are honest; the proof named a subject that is not there.
  **The comparison reported an absent cell as a cell that is led elsewhere**: the cell
  `(post-decide nudge . deciding)` is not in the diagram at all — no arrow of the diagram
  carries its label — and the comparison fell out of its branches into a guess by the order
  of the table: it answered "the generator reads the table but leads the cell elsewhere:
  the cell (post-decide nudge deciding) is drawn as (idle --> deciding : weird)".  A
  refusal with a subject that is not there sends the reader to the generator, and the
  defect is in the diagram.  Now the comparison tells the cases apart **by content and not
  by order**, and every kind of the defect has a subject that is there: `absent` (no arrow
  of the diagram carries the label of the cell), `label` (the label of the cell is in the
  diagram and the ends of its arrow are not the ends of the cell), `wrong-label` (the ends
  of the cell are in the diagram and the label of its arrow is not the label of the cell),
  `twice`, `twice-arrow`, `count` and the new `extra-arrow` (the diagram carries an arrow
  that the table of the machine does not name).  **The check proves this on stands of its
  own**: four small tables of cells and four small diagrams, written in the file of the
  check and not read out of the kernel.  The kernel and the generator are untouched
  (docs/PLAN.md §16.87).

## The commands

```sh
./scripts/dev help                  # the list of subcommands
./scripts/dev byte-compile-all      # kernel compiles clean, with no warnings
./scripts/dev ert tests/unit/*.el   # unit tests
./scripts/dev check tests/checks/*  # canaries bound to claims
./scripts/dev map                   # claims, states and uncovered surface
./scripts/dev run                   # execute checks and bind evidence
./scripts/dev gate                  # run, then map; exit code is the verdict
# Opt-in real model call; credentials come from the environment:
emacs -Q --batch -L lib -l tests/live/live-model-call.el
```

`scripts/dev` needs Emacs on `PATH` (or `EMACS`). Method commands also need a
compatible math-coding binary on `PATH` or in `MATHC`. A CLI/version mismatch
is blocked tooling, not a successful check.

Exit codes are: `0` pass, `1` fail, `2` blocked/input error and `3` unknown.
Unknown is never pass.

### The runners

The gate is one foreground runner.  `./scripts/dev gate` is `scripts/gate`; the
gate waits for the run of the method instead of watching it.  No runner in this
repository polls a log to find out whether a run is alive, and no runner holds a
command that sleeps.

| Runner | What it owns |
|---|---|
| `scripts/gate` | the run of the method: it starts a run that was killed again and writes the map when the run ends |
| `scripts/live-pilot` | the tree of the run: the group of the run, its children, the limit of the time |
| `scripts/dev-timeout` | one check: the limit of the check, and the answer 3 (unknown) when the limit is reached |
| `scripts/lib/tree.sh` | the one implementation of the tree of processes |

| Variable | Meaning | Default |
|---|---|---|
| `YEAH_CHECK_TIMEOUT` | the limit of one check, in seconds | 120 |
| `YEAH_GATE_TIMEOUT` | the limit of one attempt of the gate, in seconds | 1800 |
| `YEAH_GATE_ATTEMPTS` | how many times a killed run is started again | 3 |
| `YEAH_LIFE_SOCKET` | the socket of the life of the owner | — |

The life of a server is a socket, not a poll: `lib/yeah-life.el` describes it,
the server watches it, and the file of the socket of a dead owner is swept by
the next owner that starts a service.  An owner passes its socket of life
through `YEAH_LIFE_SOCKET`, so a server that a check started goes away with the
check.

The copies of a run of the method (`mathc-v5-<pid>-<n>` in the temporary
directory) belong to the run that made them: they are swept when that run is
gone and left alone while it is alive.

## The method

Start with the map when the compatible method binary is available:

```sh
./scripts/dev map
```

A claim has a scope, requirement, falsifier, register and **control**. The
control breaks the subject and must make the check fail by a real assertion,
not merely by making the test unreadable or crashing Emacs. A claim whose
control has not bitten is not established.

Two rules are not negotiable:

- **A check that cannot fail is a comment.**
- **Unknown is not pass.**

A placeholder that returns success is also a failed implementation. Public
scenarios must be tested end to end, not inferred from the presence of a
function or module.

<!-- math-coding:begin -->
## math-coding in this project

Yeah is an Emacs Lisp agent harness: the harness runs in a dedicated Emacs process (the service placement); the model goes through gptel, every tool goes through the registry and the permission system, the session log stays append-only, and the editor reaches it through the bridge or an ACP/MCP client

153 claim(s).

```sh
mathc run
```

Every verb: mathc help mathc init mathc goal mathc add mathc run mathc map mathc next mathc context mathc waive mathc record mathc install mathc doctor mathc adopt mathc import-adr mathc import-junit mathc authorize mathc re-evaluate mathc review-source mathc mcp
<!-- math-coding:end -->

## Task recording for the Math Coding field pilot

This project takes part in a measurement of the method itself. A task that ends
with a handoff is recorded in the field lab; without that record the pilot has
no data and the method cannot be judged.

At the end of the task, create a draft — the machine fields are filled for you:

```sh
~/Projects/math-coding-field-lab/scripts/record draft yeah --kind <kind> --base <revision-at-task-start>
```

Fill the fields marked `TODO`: the model, the time, the counters. Leave `outcome`
as `pending` and `accepted_by` empty — the owner decides the outcome and records
the acceptance, and that is not the agent's call. Then write the record:

```sh
~/Projects/math-coding-field-lab/scripts/record commit yeah --task-id <id>
```

Rules: do not choose tasks by their result, do not rewrite a written record to
make it look better, and do not drop unsuccessful ones — the pilot publishes
every outcome. The lab records every task that starts after the declared rule:
it never stops asking and it never filters by result. If the lab is not
available, finish the task as usual: a missing record is a gap in the
measurement, not a reason to change the work.

## Working rules

- Follow the stage order in `docs/PLAN.md`; do not start ACP, placements or
  sub-agents ahead of their prerequisites.
- Every new claim needs a control shown to bite. Every feature needs an
  observable end-to-end check appropriate to its layer.
- `lib/` is Elisp only. No C, Rust or shell scripts inside the kernel.
- One feature per file; `(require 'yeah-acp)` loads `lib/yeah-acp.el`.
- Public symbols use `yeah-`; internal helpers use `yeah--` or the module's
  established internal prefix.
- Domain errors are `user-error` or structured tool errors, not false success.
- Use `let` for request-local dynamic configuration of special variables;
  use `setq` only for intended global/session mutation. See ELISP §11.1.
- Subprocesses use `make-process`, never blocking `shell-command` in tools.
- Interactive execution never waits by spinning the event loop.
- One implementation of the tree of processes: `scripts/lib/tree.sh`.  A second
  copy of the stop of a tree is a second behaviour of the stop.
- The run of the method is waited for, not watched: no log is polled to find out
  whether a run is alive, and no runner holds a command that sleeps.
- A server goes away with the owner that started it: the life of the server is
  the socket of the life (`lib/yeah-life.el`), and the owner passes it through
  `YEAH_LIFE_SOCKET`.
- Every check has a limit (`YEAH_CHECK_TIMEOUT`), and a check that reached the
  limit answers 3 — unknown, never pass.
- Run context, permissions and sessions must not leak through new global
  mutable state.
- No telemetry, secret logging, global default keybindings or global gptel
  mutation.
- Development-only Nix/mathc/research clones never become runtime dependencies.

The detailed rationale and additional rules are in `docs/ENGINEERING.md` and
`ELISP_BEST_PRACTICES.md`. Update documentation whenever behavior changes;
update `AGENTS.md` if the documented workflow itself changes.
