;;; live-two-children.el --- two children of a live provider in one turn -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The offline canary of wave 110 proves that the kernel can hold two children
;; in one turn of the parent.  This check is the part that only a real model
;; can do: the model of the parent is asked for TWO delegations in one turn,
;; against a real provider, and the check reads the journal of the parent and
;; the journals of the children.
;;
;; What it measures:
;;
;; 1. the journal of the parent holds the spawn of two children, and their
;;    short ids differ -- the model asked for two delegations and the kernel
;;    started two children;
;; 2. the finish of the parent comes after the two spawns -- both delegations
;;    happened in ONE turn of the parent;
;; 3. both children end on their own -- the children of a live provider end,
;;    and the journal of the parent holds the end of each of them.
;;
;; The model is real and the provider is real.  The configuration comes from
;; the environment, so that no key is ever written into this repository:
;;
;;   YEAH_TEST_KEY    the API key; without it the check skips
;;   YEAH_TEST_HOST   the API host, for example api.minimax.io
;;   YEAH_TEST_MODEL  the model, for example MiniMax-M2.7
;;
;; This check lives OUTSIDE the map of the method: it needs a provider, and a
;; provider is not a proof that the kernel can be trusted.
;;
;; Exit codes: 0 — two children ran in one turn of a live parent; 1 — they did not.

;;; Code:

(require 'gptel)
(require 'gptel-openai)
(require 'yeah-control)
(require 'yeah-delegate)
(require 'yeah-gptel)
(require 'yeah-perm)
(require 'yeah-session)
(require 'yeah-turn)

(defconst yeah-live-two--preset
  "---\nname: reviewer\ndescription: Reviews a short text and says what is wrong with it.\nmodel: %s\ntools: read, grep, finish\ntimeout: 240\n---\n\nYou are a reviewer. Read the text you are given and say in one sentence what is wrong with it. When you are done, call the finish tool with your answer.\n"
  "The preset the children are delegated to.  The model is the one of the
environment.  The child has the tool `finish', or it could never end: a run
that cannot end is a run that works for ever.")

(defun yeah-live-two--directory (model)
  "Return a directory with the preset of the children, for MODEL."
  (let ((directory (make-temp-file "yeah-live-two" t)))
    (with-temp-buffer
      (insert (format yeah-live-two--preset model))
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    directory))

(defun yeah-live-two--wait (turn &optional timeout)
  "Wait for TURN to end and return its state."
  (let ((deadline (+ (float-time) (or timeout 600))))
    (while (and (not (yeah-turn-done turn)) (< (float-time) deadline))
      (accept-process-output nil 0.2))
    (yeah-turn-state turn)))

(defun yeah-live-two--records (session type)
  "Return the records of TYPE in the journal of SESSION."
  (let ((found nil))
    (dolist (record (yeah-session-records session))
      (when (equal (plist-get record :type) type)
        (push record found)))
    (nreverse found)))

(defun yeah-live-two--positions (types type)
  "Return the positions of TYPE in TYPES, in order."
  (let ((position 0)
        (found nil))
    (dolist (one types)
      (setq position (1+ position))
      (when (equal one type)
        (push position found)))
    (nreverse found)))

(defun yeah-live-two--run ()
  "Run the parent turn and return a failure message, or nil."
  (let* ((key (getenv "YEAH_TEST_KEY"))
         (host (or (getenv "YEAH_TEST_HOST") "api.minimax.io"))
         (model (or (getenv "YEAH_TEST_MODEL") "MiniMax-M2.7"))
         (directory nil)
         (failure nil))
    (unless key
      (message "live two: skipped — no YEAH_TEST_KEY in the environment")
      (kill-emacs 0))
    (setq directory (yeah-live-two--directory model))
    (setq gptel-backend
          (gptel-make-openai "yeah-live-two"
            :host host
            :endpoint "/v1/chat/completions"
            :key key
            :models (list (intern model))))
    (setq gptel-model (intern model))
    ;; The tools of a child run in the event loop, long after this function
    ;; returned: a `let' of a global variable is not in their dynamic
    ;; environment, so the directories of the presets and the budget of the
    ;; nudges of a child are set for the process of this check.
    (setq yeah-agent-directories (list directory)
          yeah-subagent-max-nudges 3)
    (yeah-delegate-register)
    (dolist (tool '("delegate" "delegate-result" "read" "grep"))
      (yeah-perm-rules-add (yeah-perm-rule-make tool "*" 'allow)))
    (let* ((session (yeah-session-open "live-two" directory))
           (control (yeah-control-new
                     session
                     (lambda (prompt callback)
                       (yeah-gptel-request
                        prompt callback
                        :system (format "You are an agent inside Emacs. You have the tool `delegate', which starts a child agent with the name `reviewer' and gives it a task. Ask for TWO delegations, with two different tasks, and only then end the turn by calling the finish tool. Both delegations must be asked for before you finish.")
                        ))
                     nil nil 3))
           (turn nil))
      (yeah-control-ask
       control
       "Ask for a delegation of the agent `reviewer' twice: the first task is \"the first text to review\", the second is \"the second text to review\". Then end the turn by calling the finish tool.")
      (setq turn (yeah-control-active-turn control))
      (unless turn
        (message "live two: the run did not start")
        (kill-emacs 1))
      (message "live two: state=%S" (yeah-live-two--wait turn))
      (dolist (event (yeah-session-records session))
        (message "live two: %s" event))
      ;; 1. the journal of the parent holds the spawn of two children
      (let* ((spawns (yeah-live-two--records session "spawn"))
             (ids (mapcar (lambda (record) (plist-get record :short-id)) spawns)))
        (unless (= 2 (length spawns))
          (setq failure (format "the journal of the parent holds %d spawn(s) of a child, not two: %S"
                                (length spawns) ids)))
        (unless (equal ids '("sub-1" "sub-2"))
          (setq failure (format "the two children carry the short ids %S" ids))))
      ;; 2. the finish of the parent comes after the two spawns
      (let* ((types (mapcar (lambda (record) (plist-get record :type))
                            (yeah-session-records session)))
             (spawns-at (yeah-live-two--positions types "spawn"))
             (finish-at (yeah-live-two--positions types "finish")))
        (unless (and (= 2 (length spawns-at))
                     (= 1 (length finish-at))
                     (> (car finish-at) (cadr spawns-at)))
          (setq failure (format "the journal of the parent holds the types %S: the spawns are at %S and the finish at %S"
                                types spawns-at finish-at))))
      ;; 3. both children end on their own
      (let ((deadline (+ (float-time) 300)))
        (while (and (not failure)
                    (< (length (yeah-live-two--records session "child-end")) 2)
                    (< (float-time) deadline))
          (accept-process-output nil 0.2))
        ;; The journal of every child is read before the directory of the
        ;; check is removed: the end of a child is the truth about it.
        (dolist (id '("live-two.sub-1" "live-two.sub-2"))
          (let ((child (yeah-session-open id directory)))
            (message "live two: the child %s holds %d record(s)" id
                     (length (yeah-session-records child)))
            (dolist (record (yeah-session-records child))
              (message "live two:   child %s: %s" id record))))
        (unless (= 2 (length (yeah-live-two--records session "child-end")))
          (setq failure (format "the journal of the parent holds %d end(s) of a child, not two"
                                (length (yeah-live-two--records session "child-end"))))))
    (ignore-errors (delete-directory directory t))
    failure)))

(let ((failure (yeah-live-two--run)))
  (when failure
    (message "live two: %s" failure)
    (kill-emacs 1))
  (message "live two: two children of a live provider ran in one turn of the parent")
  (kill-emacs 0))

;;; live-two-children.el ends here
