;;; check-tools-run-in-parallel.el --- canary for the scheduler -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The tools of one answer of the model are a batch. The shared ones may
;; run together; an exclusive one runs alone; the batch is a barrier: the
;; turn continues when the last call has settled, not before.
;;
;; The check observes the order of the events — which call started, which
;; call finished — and asserts three things: two shared calls overlap,
;; an exclusive call starts when nothing else is running, and the
;; continuation of the batch is not called before every call has settled.
;;
;; No network is touched: the calls wait on a timer, which is what a tool
;; that waits does. The event loop is pumped in small steps, because a
;; timer that is started inside another timer is only reached by a later
;; turn of the loop.
;;
;; Exit codes: 0 — the scheduler behaves; 1 — it does not.

;;; Code:

(require 'yeah-scheduler)

(defun yeah-check--pump ()
  "Let the event loop run for a while, in small steps.
A timer that is started inside another timer is only reached by a later
turn of the loop, so the loop is pumped rather than slept through."
  (dotimes (_ 40) (sleep-for 0.05)))

(defun yeah-check--waiting-tool (name delay events)
  "Return a call to a tool that waits DELAY seconds before it answers.
EVENTS is a one element cell holding the list of what happened, in the
order it happened, so that the handler and the check see the same list."
  (list :name name
        :args nil
        :async t
        :mode 'shared
        :handler (lambda (args done)
                   (setf (car events)
                         (cons (concat name "-start") (car events)))
                   (run-with-timer delay nil
                                   (lambda ()
                                     (setf (car events)
                                           (cons (concat name "-finish")
                                                 (car events)))
                                     (funcall done (format "%s is done" name)))))))

(let ((failures nil))

  ;; --- two shared calls overlap, and the batch is a barrier --------------
  (let ((events (list nil))
        (results nil))
    (yeah-scheduler-run
     (list (yeah-check--waiting-tool "a" 0.15 events)
           (yeah-check--waiting-tool "b" 0.15 events))
     (lambda (settled) (setq results settled)))
    (unless (null results)
      (push "the batch settled before the calls had" failures))
    (yeah-check--pump)
    (unless results
      (push "the batch never settled" failures))
    (let ((chronological (reverse (car events))))
      (unless (equal (list (nth 0 chronological) (nth 1 chronological))
                     '("a-start" "b-start"))
        (push (format "the shared calls did not overlap: %S" chronological)
              failures))
      (unless (equal (mapcar (lambda (i) (aref results i)) '(0 1)) '("a is done" "b is done"))
        (push "the results are not in the order of the calls" failures))))

  ;; --- an exclusive call runs alone -------------------------------------
  (let ((events (list nil))
        (results nil))
    (yeah-scheduler-run
     (list (yeah-check--waiting-tool "a" 0.15 events)
           (plist-put (yeah-check--waiting-tool "x" 0.10 events)
                      :mode 'exclusive)
           (yeah-check--waiting-tool "b" 0.10 events))
     (lambda (settled) (setq results settled)))
    (yeah-check--pump)
    (unless results
      (push "the batch with an exclusive call never settled" failures))
    (let ((chronological (reverse (car events))))
      (unless (equal chronological
                     '("a-start" "a-finish" "x-start" "x-finish"
                       "b-start" "b-finish"))
        (push (format "the exclusive call did not run alone: %S" chronological)
              failures))))

  (dolist (failure failures)
    (message "scheduler: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-tools-run-in-parallel.el ends here
