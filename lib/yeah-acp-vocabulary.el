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

(provide 'yeah-acp-vocabulary)
;;; yeah-acp-vocabulary.el ends here
