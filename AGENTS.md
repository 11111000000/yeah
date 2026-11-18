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
  `the-journal-never-refuses-a-record').  An error of the harness that
  happens inside the callback of an asynchronous tool becomes a failed tool
  and not the death of the process.  A run whose summary the provider did
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

120 claim(s).

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
- One feature per file; `(require 'yeah-x)` loads `lib/yeah-x.el`.
- Public symbols use `yeah-`; internal helpers use `yeah--` or the module's
  established internal prefix.
- Domain errors are `user-error` or structured tool errors, not false success.
- Use `let` for request-local dynamic configuration of special variables;
  use `setq` only for intended global/session mutation. See ELISP §11.1.
- Subprocesses use `make-process`, never blocking `shell-command` in tools.
- Interactive execution never waits by spinning the event loop.
- Run context, permissions and sessions must not leak through new global
  mutable state.
- No telemetry, secret logging, global default keybindings or global gptel
  mutation.
- Development-only Nix/mathc/research clones never become runtime dependencies.

The detailed rationale and additional rules are in `docs/ENGINEERING.md` and
`ELISP_BEST_PRACTICES.md`. Update documentation whenever behavior changes;
update `AGENTS.md` if the documented workflow itself changes.
