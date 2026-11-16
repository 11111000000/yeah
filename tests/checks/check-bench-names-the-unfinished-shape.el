;;; check-bench-names-the-unfinished-shape.el --- canary for the shape of a run that did not finish -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The pilot names the verdict of every run, but the verdict of a run that did
;; not finish says nothing about the cause: the row of such a run must name
;; the shape of the failure, so that a reader of the pilot sees what the
;; journal of the run holds -- the model answered with an empty message N
;; times, or it described its next step N times -- and not only that the
;; check failed.
;;
;; The naming does not decide anything else.  The status of the row stays what
;; it was: whether a run that did not finish is a failure of the agent or a
;; run that was never measured is a decision of the owner (docs/PLAN.md,
;; 17.2), and a runner that decided it silently would take that decision away.
;;
;; Exit codes: 0 -- the shape is named; 1 -- it is not.

;;; Code:

(require 'cl-lib)
(require 'json)

(defvar yeah-check--root
  (expand-file-name "../.."
                     (file-name-directory (or load-file-name buffer-file-name)))
  "The root of the repository.")

(load (expand-file-name "bench/run-bench.el" yeah-check--root))

(defvar yeah-check--scratch nil
  "The temporary directories this check made.")

(defun yeah-check--journal (record)
  "Write RECORD to a journal of a fresh directory and return the path of it."
  (let* ((root (file-name-as-directory (make-temp-file "yeah-bench-shape" t)))
         (path (expand-file-name "bench.jsonl" root)))
    (push root yeah-check--scratch)
    (with-temp-file path
      (insert (json-encode record) "\n"))
    path))

(defun yeah-check--unfinished-record (payload)
  "Return the record of a run that did not finish, with PAYLOAD as its shape."
  (list (cons "type" "unfinished")
        (cons "payload" payload)
        (cons "reason" "the nudge budget was spent")))

(defun yeah-check--task ()
  "Return the task of the set whose check needs nothing but bash."
  (or (cl-find-if (lambda (candidate)
                    (equal (plist-get candidate :id) "read-answer"))
                  (yeah-bench--manifest))
      (error "the task set does not hold the task read-answer")))

(defun yeah-check--failures ()
  "Return the ways in which the runner does not name the shape of a run that did not finish."
  (let* ((failures nil)
         (empty-shape "the model answered with an empty message 3 times and the run ended without an effect")
        (plan-shape "the model described its next step 2 times and the run ended without an effect")
        (journal (yeah-check--journal (yeah-check--unfinished-record empty-shape)))
        (task (yeah-check--task))
        (workspace (yeah-bench--workspace task))
        (measurement nil)
        (plain nil))
    (unwind-protect
        (progn
          (unless (and (fboundp 'yeah-bench--journal-unfinished)
                       (fboundp 'yeah-bench--unfinished-clause))
            (push "the runner does not name the shape of a run that did not finish"
                  failures))
          (when (null failures)
            ;; The journal of a run that did not finish is read: the shape is
            ;; what the record carries.
            (unless (equal (yeah-bench--journal-unfinished journal) empty-shape)
              (push (format "the journal of a run that did not finish was not read as the shape it names: %S"
                            (yeah-bench--journal-unfinished journal))
                    failures))
            ;; The other shape is read as well: the model that described its
            ;; next step and called no tool is a run of its own shape.
            (unless (equal (yeah-bench--journal-unfinished
                            (yeah-check--journal
                             (yeah-check--unfinished-record plan-shape)))
                           plan-shape)
              (push "the journal of a run that described its next step was not read as the shape it names"
                    failures))
            ;; The row of a run that did not finish names the shape.
            (setq measurement
                  (yeah-bench--measure
                   "yeah"
                   (lambda (_task _workspace _prompt _session-root)
                     (list :outcome "ran"
                           :note "the turn ended in unfinished"
                           :unfinished empty-shape))
                   task workspace "a prompt" (file-name-directory journal)))
            (let ((reason (plist-get measurement :reason)))
              (unless (and (stringp reason)
                           (string-match-p "the run did not finish" reason)
                           (string-match-p "empty message 3 times" reason))
                (push (format "the row of a run that did not finish did not name the shape: %S"
                              reason)
                      failures)))
            ;; The naming does not decide the status: the row is what it was
            ;; before the shape was named, because the classification of a run
            ;; that did not finish belongs to the owner.
            (unless (equal (plist-get measurement :status) "failed")
              (push (format "the row of a run that did not finish changed its status to %s"
                            (plist-get measurement :status))
                    failures))
            ;; A run that ended in its own way carries no such clause: the
            ;; naming must not be a decoration of every row.
            (setq plain
                  (yeah-bench--measure
                   "yeah"
                   (lambda (_task _workspace _prompt _session-root)
                     (list :outcome "ran" :note "the turn ended in completed"))
                   task workspace "a prompt" (file-name-directory journal)))
            (let ((reason (plist-get plain :reason)))
              (when (and (stringp reason)
                         (string-match-p "the run did not finish" reason))
                (push "the row of a run that ended in its own way names a run that did not finish"
                      failures)))))
      (ignore-errors (delete-directory workspace t t))
      (dolist (root yeah-check--scratch)
        (ignore-errors (delete-directory root t t))))
    (nreverse failures)))

(let ((failures (yeah-check--failures)))
  (dolist (failure failures)
    (message "%s" failure))
  (when failures
    (kill-emacs 1)))

(kill-emacs 0)

;;; check-bench-names-the-unfinished-shape.el ends here
