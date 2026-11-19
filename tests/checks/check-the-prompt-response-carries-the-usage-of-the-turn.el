;;; check-the-prompt-response-carries-the-usage-of-the-turn.el --- the prompt response carries the usage of the turn -*- lexical-binding: t; no-byte-compile: t -*-
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
;; tokens of a run of Yeah it never saw.  The kernel knew them -- the provider
;; reports them and the journal holds them -- but the answer to `session/prompt'
;; carried a stop reason and nothing else, so the client that counts the tokens
;; of a turn had nothing to count.
;;
;; This check starts a real ACP service on a socket, drives two prompts in one
;; session and one quiet prompt in another, and proves three things on the wire:
;;
;; 1. the answer to `session/prompt' carries the `usage' of the turn: the
;;    tokens the provider reported;
;; 2. the usage is the usage of the turn and not the usage of the session: the
;;    second prompt of the same session reports its own tokens and not the sum
;;    of the two runs;
;; 3. a provider that reported nothing has no usage in its answer: the kernel
;;    does not guess the tokens of a provider that said nothing.
;;
;; The model here is a FAKE (the model is a FAKE): it ends the run with the
;; `finish' tool and reports the tokens of the turn the way gptel reports them.
;;
;; Exit codes: 0 -- the answer carried the usage of the turn; 1 -- it did not.

;;; Code:

(require 'cl-lib)
(require 'yeah-service)

(load (expand-file-name "tests/support/yeah-acp-client.el") nil t)

(defvar yeah-check--failures nil
  "The failures this check found.")

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

(defun yeah-check--prompt (client session-id text)
  "Send the prompt TEXT to CLIENT in SESSION-ID and return the answer."
  (yeah-acp-client-request client "session/prompt"
                            (list :sessionId session-id
                                  :prompt (vector (list :type "text" :text text)))
                            60))

(defun yeah-check--usage (answer)
  "Return the usage the ANSWER of `session/prompt' carries, or nil."
  (plist-get (plist-get answer :result) :usage))

(defun yeah-check--session (client workspace)
  "Open a session on CLIENT in WORKSPACE and return its id."
  (let* ((answer (yeah-acp-client-request client "session/new"
                                             (list :cwd workspace)))
         (session-id (plist-get (plist-get answer :result) :sessionId)))
    (unless session-id
      (push "the session was not opened" yeah-check--failures))
    session-id))

(defun yeah-check--expect-input (usage input what)
  "Fail unless USAGE reports INPUT input tokens.
WHAT names the case, so that a reader of the log knows which claim was broken."
  (unless (equal (plist-get usage :inputTokens) input)
    (push (format "%s: the usage carried the wrong input tokens: %S is not %d"
                  what (plist-get usage :inputTokens) input)
          yeah-check--failures)))

(let* ((data-home (make-temp-file "yeah-usage" t))
       (workspace (make-temp-file "yeah-usage-work" t))
       (name (format "yeah-usage-%d" (random 1000000)))
       (client nil))
  (unwind-protect
      (progn
        (yeah-check--start name data-home)
        (let ((connection (yeah-acp-client-connect (yeah-service-socket-path name))))
          (setq client (nth 0 connection)))
        (yeah-acp-client-request client "initialize" (list :protocolVersion 1))
        ;; 1: the answer carries the tokens the provider reported.
        (let* ((session-id (yeah-check--session client workspace))
               (usage (yeah-check--usage
                       (yeah-check--prompt client session-id "do the thing, spend 1200"))))
          (unless usage
            (push "the answer to the prompt carried no usage: the client that counts the tokens of a turn had nothing to count"
                  yeah-check--failures))
          (when usage
            (yeah-check--expect-input usage 1200 "the first prompt")
            (unless (equal (plist-get usage :outputTokens) yeah-check--output)
              (push (format "the first prompt: the usage carried the wrong output tokens: %S is not %d"
                            (plist-get usage :outputTokens) yeah-check--output)
                    yeah-check--failures))
            (unless (equal (plist-get usage :totalTokens) (+ 1200 yeah-check--output))
              (push (format "the first prompt: the usage carried the wrong total: %S is not %d"
                            (plist-get usage :totalTokens) (+ 1200 yeah-check--output))
                    yeah-check--failures))))
        ;; 2: the usage is the usage of the turn, not the usage of the session.
        (let* ((session-id (yeah-check--session client workspace))
               (first (yeah-check--usage
                       (yeah-check--prompt client session-id "the first one, spend 1200")))
               (second (yeah-check--usage
                        (yeah-check--prompt client session-id "the second one, spend 1300"))))
          (yeah-check--expect-input first 1200 "the first prompt of the session")
          (yeah-check--expect-input
           second 1300
           "the second prompt of the session: it reported the tokens of the session and not the tokens of its turn"))
        ;; 3: a provider that said nothing has no usage in the answer.
        (let* ((session-id (yeah-check--session client workspace))
               (usage (yeah-check--usage
                       (yeah-check--prompt client session-id "quiet please"))))
          (when usage
            (push (format "the answer carried the usage of a provider that reported nothing: %S"
                          usage)
                  yeah-check--failures)))
        (dolist (failure yeah-check--failures)
          (message "prompt-usage: %s" failure)))
    (when client (ignore-errors (yeah-client-close client)))
    (ignore-errors (yeah-service-stop name))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory workspace t)))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-prompt-response-carries-the-usage-of-the-turn.el ends here
