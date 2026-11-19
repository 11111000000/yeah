;;; yeah-acp-vocabulary.el --- the vocabulary the ACP sides of Yeah share -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; The ACP server of Yeah and the ACP client of Yeah speak one protocol: the
;; version of that protocol and the name of Yeah's own extension are named
;; here, so that both sides name them the same way and a change reaches both.

;;; Code:

(defconst yeah-acp-protocol-version 1
  "Version of the ACP protocol Yeah speaks.")

(defconst yeah-acp-queue-events-key "yeah.queueEvents"
  "Key in the `_meta' of the client capabilities that asks for Yeah's queue
events.  The queue events are not part of ACP: a client that does not know
them refuses the whole update, so they travel only to a client that asked
for them.")

(defconst yeah-acp-queue-events-capability
  (intern (concat ":" yeah-acp-queue-events-key))
  "The key of the announcement of the queue events, as Emacs reads it.
Emacs parses a JSON object into a property list whose keys are keywords,
so the key of the announcement is this keyword and not the plain symbol of
the same name.")

(defun yeah-acp-queue-events-capabilities ()
  "Return the capabilities a client announces to understand Yeah's queue events.
The announcement travels in the `_meta' of the capabilities of the client:
the queue events are not ACP, so a client that does not ask for them never
sees them.  The editor of Yeah announces them and sees the queue of the
session; a client that announces nothing is served plain ACP."
  (list :_meta (list yeah-acp-queue-events-capability t)))

(defconst yeah-acp-outcome-key "yeah.runOutcome"
  "Key in the `_meta' of the client capabilities that asks for the outcome of a
run: the nudge that pushed it, the run that ended without an effect and the
error that stopped it.  The outcome of a run is Yeah's own vocabulary, and a
client that does not ask for it is served plain ACP.")

(defconst yeah-acp-outcome-capability
  (intern (concat ":" yeah-acp-outcome-key))
  "The key of the announcement of the outcome of a run, as Emacs reads it.
Emacs parses a JSON object into a property list whose keys are keywords,
so the key of the announcement is this keyword and not the plain symbol of
the same name.")

(defun yeah-acp-outcome-capabilities ()
  "Return the capabilities a client announces to understand the outcome of a
run.  The announcement travels in the `_meta' of the capabilities of the
client: the outcome of a run is not ACP, so a client that does not ask for it
never sees it.  The plugin of the orchestrator announces it and translates
what comes back into what the orchestrator shows."
  (list :_meta (list yeah-acp-outcome-capability t)))

(defconst yeah-acp-outcome-method "yeah/outcome"
  "The method of the notification that carries the outcome of a run.
It is not a method of ACP: the outcome of a run is Yeah's own vocabulary, and
the orchestrator learns it through the plugin that translates it.  The tokens
a run spent are not here -- they travel as `usage_update', which is a part of
ACP.")

(defconst yeah-acp-usage-key "yeah.usage"
  "Key in the `_meta' of the client capabilities that asks for the tokens of a
turn.  The tokens of a turn are the vocabulary of Yeah: the provider of the
model reports them, and the kernel does not count them itself.  A client that
does not ask for them is served plain ACP.")

(defconst yeah-acp-usage-capability
  (intern (concat ":" yeah-acp-usage-key))
  "The key of the announcement of the tokens of a turn, as Emacs reads it.
Emacs parses a JSON object into a property list whose keys are keywords,
so the key of the announcement is this keyword and not the plain symbol of
the same name.")

(defun yeah-acp-usage-capabilities ()
  "Return the capabilities a client announces to understand the tokens of a turn.
The announcement travels in the `_meta' of the capabilities of the client:
the tokens of a turn are not ACP, so a client that does not ask for them
never sees them.  The plugin of the orchestrator announces them and translates
what comes back into what the orchestrator counts."
  (list :_meta (list yeah-acp-usage-capability t)))

(defconst yeah-acp-usage-method "yeah/usage"
  "The method of the notification that carries the tokens of a turn.
It is not a method of ACP: the tokens of a turn are Yeah's own vocabulary.
The context of a session travels as `usage_update', which is a part of ACP and
carries the size of the window -- not the tokens a turn spent.")

(provide 'yeah-acp-vocabulary)
;;; yeah-acp-vocabulary.el ends here
