;;; check-the-wire-tells-the-orchestrator-how-the-run-ended.el --- the wire tells how the run ended -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The defect: the orchestrator saw that a run ended and not how it ended.
;; The kernel writes into its journal everything a person needs to know --
;; the tokens a run spent, the nudge that pushed it, the run that ended
;; without an effect and the error that stopped it -- and the wire carried
;; none of it.  The client of the orchestrator saw `stopReason' and the words
;; of the agent, and a run that ended without an effect looked like a run that
;; had ended.
;;
;; This check starts a real ACP service on a socket, drives a run that never
;; finishes, and proves three things on the wire:
;;
;; 1. the client that announced the outcome of a run in the `_meta' of its
;;    capabilities receives the outcome: the nudge that pushed the run and the
;;    run that ended without an effect;
;; 2. the outcome names the session it belongs to;
;; 3. the client that announced nothing receives nothing: the vocabulary of
;;    Yeah travels only where it was asked for.
;;
;; The model here is a FAKE (the model is a FAKE): it only describes its next
;; step, so the kernel nudges it until the budget of the nudges is spent.
;;
;; Exit codes: 0 -- the wire told how the run ended; 1 -- it did not.

;;; Code:

(require 'cl-lib)
(require 'yeah-acp-vocabulary)
(require 'yeah-service)

(load (expand-file-name "tests/support/yeah-acp-client.el") nil t)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--model-source ()
  "Return the source of the fake model of the check.
The model is a file of its own and not a string in a check: the service loads
it in its own Emacs, and a source that is written twice is a source that is
written twice."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "tests/support/yeah-session-outcome-model.el"))
    (buffer-string)))

(defun yeah-check--start (name data-home)
  "Start the service of the check under NAME with the data home DATA-HOME.
The model of the service is the fake one of the checks."
  (yeah-service-start name
                      (yeah-check--model-source)
                      data-home
                      "#'yeah-session-outcome-model-transport"
                      t
                      nil))

(defun yeah-check--outcomes (updates)
  "Return the outcomes that the notifications UPDATES carry.
An outcome travels as a notification of a method of Yeah that is not a method
of ACP: the client of the orchestrator learns the outcome of a run through
the plugin that translates it."
  (delq nil
        (mapcar (lambda (message)
                  (when (equal yeah-acp-outcome-method (plist-get message :method))
                    (plist-get (plist-get message :params) :outcome)))
                updates)))

(defun yeah-check--sessions-of (updates)
  "Return the sessions that the outcomes of the notifications UPDATES name."
  (delq nil
        (mapcar (lambda (message)
                  (when (equal yeah-acp-outcome-method (plist-get message :method))
                    (plist-get (plist-get message :params) :sessionId)))
                updates)))

(defun yeah-check--drive (client workspace)
  "Open a session on CLIENT in WORKSPACE, run a prompt, and return its id.
The prompt asks for nothing in particular: the model of the service talks and
never acts, and the run ends without an effect."
  (let* ((answer (yeah-acp-client-request client "session/new"
                                             (list :cwd workspace)))
         (session-id (plist-get (plist-get answer :result) :sessionId)))
    (unless session-id
      (push "the session was not opened" yeah-check--failures))
    (when session-id
      (yeah-acp-client-request client "session/prompt"
                                (list :sessionId session-id
                                      :prompt (vector (list :type "text"
                                                             :text "do the thing")))
                                60))
    session-id))

(let* ((data-home (make-temp-file "yeah-outcome" t))
       (workspace (make-temp-file "yeah-outcome-work" t))
       (name (format "yeah-outcome-%d" (random 1000000)))
       (client nil)
       (updates nil)
       (plain nil)
       (plain-updates nil))
  (unwind-protect
      (progn
        (yeah-check--start name data-home)
        ;; The client that asked for the outcome of a run.
        (let ((connection (yeah-acp-client-connect (yeah-service-socket-path name))))
          (setq client (nth 0 connection)
                updates (nth 2 connection)))
        (let ((answer (yeah-acp-client-request
                       client "initialize"
                       (list :protocolVersion 1
                             :clientCapabilities
                             (list :_meta (list yeah-acp-outcome-capability t))))))
          (unless (plist-get answer :result)
            (push "the handshake was not answered" yeah-check--failures)))
        (let ((session-id (yeah-check--drive client workspace)))
          ;; 1 and 2: the outcome of the run reaches the client that asked.
          (let ((outcomes (yeah-check--outcomes (funcall updates))))
            (unless (member "nudge" outcomes)
              (push (format "the wire carried no nudge: the client that asked for the outcome was not told: %S"
                            outcomes)
                    yeah-check--failures))
            (unless (member "unfinished" outcomes)
              (push (format "the wire carried no unfinished: the run that ended without an effect was not named: %S"
                            outcomes)
                    yeah-check--failures)))
          (let ((sessions (yeah-check--sessions-of (funcall updates))))
            (unless (member session-id sessions)
              (push (format "the outcome did not name its session: %S does not hold %s"
                            sessions session-id)
                    yeah-check--failures))))
        ;; 3: the client that asked for nothing gets nothing.
        (let ((connection (yeah-acp-client-connect (yeah-service-socket-path name))))
          (setq plain (nth 0 connection)
                plain-updates (nth 2 connection)))
        (yeah-acp-client-request plain "initialize" (list :protocolVersion 1))
        (yeah-check--drive plain workspace)
        (let ((outcomes (yeah-check--outcomes (funcall plain-updates))))
          (unless (null outcomes)
            (push (format "the plain client received the outcome of a run: it did not ask for it: %S"
                          outcomes)
                  yeah-check--failures))))
    (when client (ignore-errors (yeah-client-close client)))
    (when plain (ignore-errors (yeah-client-close plain)))
    (ignore-errors (yeah-service-stop name))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory workspace t)))
  (dolist (failure yeah-check--failures)
    (message "run-outcome: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-wire-tells-the-orchestrator-how-the-run-ended.el ends here
