;;; check-the-orchestrator-sees-the-usage-of-the-turn.el --- the orchestrator sees the usage of the turn -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The gap: the orchestrator counted the tokens of a run of opencode and the
;; tokens of a run of Yeah it never saw.  The kernel knows them -- the provider
;; of the model reports them and the journal holds them -- but the connection
;; of the orchestrator takes from the answer to `session/prompt' one stop
;; reason and throws the rest away, so the tokens of a turn never reached the
;; place where the orchestrator counts them.
;;
;; This check starts a real ACP service on a socket and proves three things on
;; the wire:
;;
;; 1. the client that asked for the tokens of a turn receives them: the
;;    notification of the kernel names the tokens the provider reported;
;; 2. the notification names the session it belongs to;
;; 3. the client that asked for nothing receives nothing: the vocabulary of
;;    Yeah travels only where it was asked for.
;;
;; The model here is a FAKE (the model is a FAKE): it ends the run with the
;; `finish' tool and reports the tokens of the turn the way gptel reports them.
;;
;; Exit codes: 0 -- the orchestrator saw the usage of the turn; 1 -- it did not.

;;; Code:

(require 'cl-lib)
(require 'yeah-acp-vocabulary)
(require 'yeah-service)

(load (expand-file-name "tests/support/yeah-acp-client.el") nil t)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defconst yeah-check--input 1200
  "The input tokens the fake model reports.")

(defconst yeah-check--output 34
  "The output tokens the fake model reports.")

(defun yeah-check--model-source ()
  "Return the source of the fake model of the check.
The model is a file of its own and not a string in a check: the service loads
it in its own Emacs, and a source that is written twice is a source that is
written twice."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "tests/support/yeah-session-usage-model.el"))
    (buffer-string)))

(defun yeah-check--start (name data-home)
  "Start the service of the check under NAME with the data home DATA-HOME.
The model of the service is the fake one of the checks."
  (yeah-service-start name
                      (yeah-check--model-source)
                      data-home
                      "#'yeah-session-usage-model-transport"
                      t
                      nil))

(defun yeah-check--usages (updates)
  "Return the parameters of the notifications of the usage that UPDATES carry.
The tokens of a turn travel as a notification of a method of Yeah that is not
a method of ACP: the client of the orchestrator learns them through the plugin
that translates them."
  (delq nil
        (mapcar (lambda (message)
                  (when (equal yeah-acp-usage-method (plist-get message :method))
                    (plist-get message :params)))
                updates)))

(defun yeah-check--drive (client workspace)
  "Open a session on CLIENT in WORKSPACE, run a prompt, and return its id.
The prompt names the tokens the model spends, the way the checks of the usage
of a turn do."
  (let* ((answer (yeah-acp-client-request client "session/new"
                                             (list :cwd workspace)))
         (session-id (plist-get (plist-get answer :result) :sessionId)))
    (unless session-id
      (push "the session was not opened" yeah-check--failures))
    (when session-id
      (yeah-acp-client-request client "session/prompt"
                                (list :sessionId session-id
                                      :prompt (vector (list :type "text"
                                                             :text "do the thing, spend 1200")))
                                60))
    session-id))

(let* ((data-home (make-temp-file "yeah-turn-usage" t))
       (workspace (make-temp-file "yeah-turn-usage-work" t))
       (name (format "yeah-turn-usage-%d" (random 1000000)))
       (client nil)
       (updates nil)
       (plain nil)
       (plain-updates nil))
  (unwind-protect
      (progn
        (yeah-check--start name data-home)
        ;; The client that asked for the tokens of a turn.
        (let ((connection (yeah-acp-client-connect (yeah-service-socket-path name))))
          (setq client (nth 0 connection)
                updates (nth 2 connection)))
        (let ((answer (yeah-acp-client-request
                       client "initialize"
                       (list :protocolVersion 1
                             :clientCapabilities
                             (list :_meta (list yeah-acp-usage-capability t))))))
          (unless (plist-get answer :result)
            (push "the handshake was not answered" yeah-check--failures)))
        (let ((session-id (yeah-check--drive client workspace)))
          ;; 1: the tokens of the turn reached the client that asked for them.
          (let ((usages (yeah-check--usages (funcall updates))))
            (unless usages
              (push "the wire carried no usage of a turn: the client that counts the tokens of a turn had nothing to count"
                    yeah-check--failures))
            (dolist (usage usages)
              (unless (equal (plist-get usage :inputTokens) yeah-check--input)
                (push (format "the usage of the turn carried the wrong input tokens: %S is not %d"
                              (plist-get usage :inputTokens) yeah-check--input)
                      yeah-check--failures))
              (unless (equal (plist-get usage :outputTokens) yeah-check--output)
                (push (format "the usage of the turn carried the wrong output tokens: %S is not %d"
                              (plist-get usage :outputTokens) yeah-check--output)
                      yeah-check--failures)))
            ;; 2: the usage names the session it belongs to.
            (unless (member session-id (mapcar (lambda (usage)
                                                 (plist-get usage :sessionId))
                                               usages))
              (push (format "the usage did not name its session: %S does not hold %s"
                            (mapcar (lambda (usage) (plist-get usage :sessionId)) usages)
                            session-id)
                    yeah-check--failures))))
        ;; 3: the client that asked for nothing gets nothing.
        (let ((connection (yeah-acp-client-connect (yeah-service-socket-path name))))
          (setq plain (nth 0 connection)
                plain-updates (nth 2 connection)))
        (yeah-acp-client-request plain "initialize" (list :protocolVersion 1))
        (yeah-check--drive plain workspace)
        (let ((usages (yeah-check--usages (funcall plain-updates))))
          (unless (null usages)
            (push (format "the plain client received the usage of a turn: it did not ask for it: %S"
                          usages)
                  yeah-check--failures))))
    (when client (ignore-errors (yeah-client-close client)))
    (when plain (ignore-errors (yeah-client-close plain)))
    (ignore-errors (yeah-service-stop name))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory workspace t)))
  (dolist (failure yeah-check--failures)
    (message "turn-usage: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-orchestrator-sees-the-usage-of-the-turn.el ends here
