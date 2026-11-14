# VISION — Yeah, in one piece

> This document is the direction, not the evidence. What is verified today
> lives in `spec.json` and `./scripts/dev map`; what is being built lives in
> `docs/PLAN.md`. The vision is the reason for both.

## 1. The environment is people

Emacs is not an editor and not an API surface. It is a place people have
invested themselves in for decades: packages the community wrote against
real needs, configurations a person sharpened for years until they fit their
hands, habits that became muscle memory. Behind every `defun` in someone's
init file there is a solution to someone's concrete pain. The environment
is frozen human experience — not a museum, but working experience, executed
every day.

The arrival of agents carries a threat the marketing does not mention: the
new era is offered as a replacement for the old one. "Forget your editor,
here is the agent." For a person whose environment is part of how they
think, that is not a proposal about tools; it is a proposal of
self-renunciation.

Yeah begins by refusing that choice.

## 2. The agent is a participant, not a replacement

The agent does not arrive "instead of" the environment — it is born inside
it. It reads not the project's files but the person's live buffers,
including the unsaved ones; it asks the documentation of the system it
lives in; it uses the diagnostics of the LSP the person already configured;
it works under the rules the person gave it. The environment's inheritance
is not background; it is the agent's starting capital.

Hence the demands on the agent are human ones: no telemetry, no hidden
global keybindings, no secrets in the logs, refusal instead of guessing, a
journal the person can read and check. An agent living in a personal
environment must be its conscientious citizen — otherwise it is not a
participant but an occupier.

## 3. A minimal culture you can carry with you

If the value of Yeah exhausted itself in the inheritance, a bare Emacs
would have nothing for it to do. Yet it works there. So the kernel itself
carries a culture in miniature: tools as functions, state as text, history
as an append-only journal, evidence as checks that can fail.

The main property follows: **what travels is not the environment, but the
environment's capacity to be used**. The same minimal culture unfolds from
a clean CI Emacs to an Emacs inhabited for twenty years — and nowhere
requires rewriting. Inheritance is a multiplier, not a prerequisite.
Portability is not a gift of Lisp but a measurable goal with canaries and
openly named limits (Windows sockets, an external git, differences between
Emacs versions).

## 4. The thread is isolated, not the culture

Emacs is single-threaded: an agent inside the editor interferes with
editing. The answer is separate processes, not separate worlds. A service
Emacs runs the long turn; the person's editor never waits. But the model
stays the person's, the permissions stay the person's, and the buffers are
reached through an explicitly approved bridge. We isolate what interferes
and keep everything that carries meaning.

## 5. Y: the environment developing itself

The Y-combinator in the name is not an ornament. Recursion without a name
is delegation of work whose shape need not be known in advance;
self-inspection is the agent's capacity to see its own runtime, including
itself; the fixed point is the moment the environment begins to develop
itself through the agent.

This is not a self-modification trick and not a dream of autonomy. The
fixed point continues the same line: the person invested experience in the
environment → the environment gave the agent a start → the agent gives the
environment back a way to grow. Yeah repairing its own canary is the
modest, measurable form of that cycle, not its advertising image.

## 6. Honesty as ontology

The vision would be empty without the discipline it stands on: **a check
that cannot fail is a comment; unknown is not pass**. We do not call a goal
achieved because a module exists. Documentation is never more optimistic
than the code. Parity with complete harnesses is a goal measured by
completed tasks, not a checklist of features. Even this vision is not a
statement about the present but a commitment about direction.

## 7. The interface is part of the culture

An agent that lives in Emacs should behave like the rest of the Emacs
experience, not like a chat window dropped into it. The transcript is
read-only and inspectable; updates preserve the place a person is reading;
semantic faces inherit the active theme; a multiline prompt is a real text
buffer; an approval shows the concrete effect before it is allowed; and
optional icons decorate readable text rather than replace it. No required
package, global keybinding or decorative dependency may stand between the
person and the work.

This is not polish added after the kernel is true. The quality of the
interface is part of whether the agent can become a participant in an
environment whose value was built by people over decades.

## 8. Telos

To preserve the line of personal computing in the era of agents. So that a
person whose environment grew with them is not forced to leave it for new
capabilities — but finds that the new capabilities arrived in their world,
speak its language, and strengthen what they built. Not "an AI-era agent
instead of the editor", but **the person's environment, having gained the
capacity to act and to develop itself — together with the person, under
their control, on their terms**.

In one sentence: **Yeah is a way for the environment people invested
themselves in to survive the era of agents as a participant, not as an
inheritance.**
