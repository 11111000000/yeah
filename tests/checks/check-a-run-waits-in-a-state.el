;;; check-a-run-waits-in-a-state.el --- a run that waits says so -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A run that waits for the answer of a person, or for a provider that was too
;; busy, used to wait without saying so.  The state of the run stayed
;; `awaiting-tool' or `deciding', and nothing could tell a run that waits for a
;; person from a run that waits for a tool.  The table of the machine named the
;; states `awaiting-user-permission' and `blocked-on-rate', but no move of the
;; runtime ever led into them: the cells were there and the transitions were
;; not (wave 77).
;;
;; Four things are checked here.
;;
;; 1. A run whose question waits for the person is in the state
;;    `awaiting-user-permission', and the history of the run holds that state.
;; 2. The answer of the person ends the wait: the run goes on and finishes.
;; 3. A run whose provider was too busy is in the state `blocked-on-rate', and
;;    the run goes on when the provider answers.
;; 4. The table of the machine and the runtime agree: every move the runtime
;;    made is a cell of the table.
;;
;; The model here is a FAKE: a provider that plays the shape of the live run.
;; No network is touched.
;;
;; Exit codes: 0 — the run waits in a state; 1 — it does not.

;;; Code:

(require 'cl-lib)
(require 'yeah-loop)
(require 'yeah-session)
(require 'yeah-state)
(require 'yeah-tools)
(require 'yeah-turn)

(defun yeah-check--fail (ok message)
  "Return MESSAGE when OK is nil, and nil when OK holds."
  (unless ok
    message))

(defun yeah-check--probe ()
  "Register the tool the fake model calls."
  (yeah-tools-reset-for-test)
  (yeah-tools-register
   (list :name "probe" :description "probe" :input nil
         :handler (lambda () "the output of the probe"))))

(defun yeah-check--call-probe (continuation)
  "Return a gptel-shaped call of the tool `probe' with CONTINUATION."
  (list 'tool-call (list (list :name "probe") (list) continuation)))

(defun yeah-check--busy-reason ()
  "Return the reason a provider that is too busy gives."
  "the provider is busy and refused the request")

(defun yeah-check--permission-run ()
  "Run a turn whose question waits for the answer of the person.
Return the turn, the session and the root of the run."
  (yeah-check--probe)
  (let* ((root (make-temp-file "yeah-waits" t))
         (session (yeah-session-open "waits" root))
         (turn (yeah-turn-run
                session "wait"
                (lambda (_prompt callback)
                  (funcall callback
                           (yeah-check--call-probe
                            (lambda (_value)
                              (funcall callback "the tool has run")))))
                (lambda (_request) (list :defer "permission-1"))
                60000 0)))
    (list :turn turn :session session :root root)))

(defun yeah-check--busy-run ()
  "Run a turn whose provider is too busy on the first request.
Return the turn, the session and the root of the run."
  (yeah-check--probe)
  (let* ((root (make-temp-file "yeah-rate" t))
         (session (yeah-session-open "rate" root))
         (cell (vector 0)))
    (let ((turn
           (yeah-turn-run
            session "wait"
            (lambda (_prompt callback)
              (if (zerop (aref cell 0))
                  (progn
                    (aset cell 0 1)
                    ;; The shape of a provider that is too busy: the status
                    ;; of the wire is a string, and the info names it.
                    (funcall callback (cons 'error (yeah-check--busy-reason))
                             (list :error (yeah-check--busy-reason)
                                   :http-status "529")))
                (funcall callback
                         (yeah-check--call-probe
                          (lambda (_value)
                            (funcall callback "the tool has run"))))))
            nil 60000 0)))
      (list :turn turn :session session :root root))))

(defun yeah-check--cell-p (from to)
  "Return non-nil when the table of the machine has a cell from FROM to TO."
  (cl-some (lambda (cell)
             (and (eq (nth 0 cell) from)
                  (eq (nthcdr 2 cell) to)))
           yeah-loop-transitions))

(defun yeah-check--moves-of-the-table (states)
  "Return the moves of STATES that the table of the machine does not have.
STATES is the history of a run: the states the run has really been in."
  (let ((moves nil))
    (while (cdr states)
      (let ((from (car states))
            (to (cadr states)))
        (unless (yeah-check--cell-p from to)
          (push (list from to) moves)))
      (setq states (cdr states)))
    (nreverse moves)))

(defun yeah-check--a-run-that-waits-for-the-person-is-in-a-state ()
  "A run whose question waits for the person is in the state of a run that waits."
  (let* ((result (yeah-check--permission-run))
         (turn (plist-get result :turn)))
    (unwind-protect
        (list
         (yeah-check--fail
          (eq (yeah-turn-state turn) 'awaiting-user-permission)
          (format "the run that waits for the person is in %S, not in the state of a run that waits"
                  (yeah-turn-state turn)))
         (yeah-check--fail
          (memq 'awaiting-user-permission (yeah-turn-states turn))
          (format "the history of the run does not hold the waiting state: %S"
                  (yeah-turn-states turn)))
         (yeah-check--fail
          (yeah-state-p 'awaiting-user-permission)
          "the waiting state is not a state of the machine")
         (yeah-check--fail
          (not (yeah-turn-done turn))
          "the run ended before the person answered"))
      (ignore-errors (delete-directory (plist-get result :root) t t)))))

(defun yeah-check--the-answer-of-the-person-ends-the-wait ()
  "The answer of the person ends the wait, and the run goes on."
  (let* ((result (yeah-check--permission-run))
         (turn (plist-get result :turn)))
    (unwind-protect
        (progn
          (yeah-turn-resume-permission
           turn "permission-1" (list :effect :allow :reply :once))
          (list
           (yeah-check--fail
            (yeah-turn-done turn)
            "the run did not go on after the answer of the person")
           (yeah-check--fail
            (eq (yeah-turn-state turn) 'completed)
            (format "the run ended in %S, not in completed"
                    (yeah-turn-state turn)))
           (yeah-check--fail
            (not (eq (yeah-turn-state turn) 'awaiting-user-permission))
            "the run stayed in the state of a run that waits")
           (yeah-check--fail
            (memq 'awaiting-user-permission (yeah-turn-states turn))
            "the run never was in the state of a run that waits")))
      (ignore-errors (delete-directory (plist-get result :root) t t)))))

(defun yeah-check--a-run-that-waits-for-a-busy-provider-is-in-a-state ()
  "A run whose provider was too busy is in the state of a run that waits."
  (let* ((result (yeah-check--busy-run))
         (turn (plist-get result :turn)))
    (unwind-protect
        (list
         (yeah-check--fail
          (memq 'blocked-on-rate (yeah-turn-states turn))
          (format "the history of the run does not hold the state of a run that waits for a provider: %S"
                  (yeah-turn-states turn)))
         (yeah-check--fail
          (eq (yeah-turn-state turn) 'completed)
          (format "the run ended in %S, not in completed"
                  (yeah-turn-state turn))))
      (ignore-errors (delete-directory (plist-get result :root) t t)))))

(defun yeah-check--the-table-and-the-runtime-agree ()
  "Every move the runtime made is a cell of the table of the machine."
  (let ((moves nil))
    (dolist (run '(yeah-check--permission-run yeah-check--busy-run))
      (let* ((result (funcall run))
             (turn (plist-get result :turn)))
        (unwind-protect
            (setq moves (append moves
                                (yeah-check--moves-of-the-table
                                 (yeah-turn-states turn))))
          (ignore-errors (delete-directory (plist-get result :root) t t)))))
    (list
     (yeah-check--fail
      (null moves)
      (format "the runtime made a move that the table does not have: %S" moves)))))

(let ((failures (delq nil
                     (append
                      (yeah-check--a-run-that-waits-for-the-person-is-in-a-state)
                      (yeah-check--the-answer-of-the-person-ends-the-wait)
                      (yeah-check--a-run-that-waits-for-a-busy-provider-is-in-a-state)
                      (yeah-check--the-table-and-the-runtime-agree)))))
  (dolist (failure failures)
    (message "waits: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-run-waits-in-a-state.el ends here
