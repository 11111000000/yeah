;;; check-a-text-answer-does-not-end-a-supervised-run.el --- the words of the model do not end a run -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A supervised run ends through the `finish' tool.  A text answer that
;; reports a result is not a completion: the run nudges the model into the
;; call that ends it, and a model that never calls `finish' spends the budget
;; of the nudges and ends as a failed run that says it did not finish.
;;
;; The defect this check guards against is the false success: a live run of the
;; harness (wave 42, 2026-11-18) called a tool 261 times, was in the middle of
;; the work, answered "Now the ACP module itself:" and was recorded as a
;; completed job.  The work that was left was thrown away with the run.
;;
;; The model here is a FAKE: a transport that calls one tool and then reports
;; a result in words, and never calls `finish'.  The check runs a supervised
;; turn and an unsupervised one, and asserts that the first does not end as
;; completed and the second does.
;;
;; Exit codes: 0 — the words do not end a supervised run; 1 — they do.

;;; Code:

(require 'cl-lib)
(require 'yeah-session)
(require 'yeah-tools)
(require 'yeah-turn)

(defun yeah-check--works-then-reports ()
  "Return a transport whose model calls a tool and then reports a result.
The model never calls the `finish' tool: it says that the work is done."
  (lambda (_prompt callback)
    (funcall callback
             (list 'tool-call
                   (list (list :name "probe")
                         (list)
                         (lambda (_value)
                           (funcall callback "The work is done; the test passes.")))))))

(defun yeah-check--records (root name)
  "Return the records of the log of session NAME under ROOT."
  (with-temp-buffer
    (insert-file-contents (expand-file-name (format "sessions/%s.jsonl" name) root))
    (mapcar (lambda (line) (json-parse-string line :object-type 'plist))
            (split-string (buffer-string) "\n" t))))

(defun yeah-check--some-record (records type)
  "Return the first record of TYPE in RECORDS, or nil."
  (cl-find-if (lambda (record) (equal type (plist-get record :type))) records))

(defun yeah-check--wait-for (predicate &optional timeout)
  "Wait until PREDICATE holds, up to TIMEOUT seconds.
Return the value of PREDICATE."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-check--run (name max-nudges)
  "Run a turn under the budget MAX-NUDGES and return the turn, the records and
the failures of the run."
  (let* ((root (make-temp-file "yeah-text-end-check" t))
         (session (yeah-session-open name root))
         (failures nil))
    (unless (yeah-tools-get "probe")
      (yeah-tools-register
       (list :name "probe" :description "A tool that runs." :input nil
             :handler (lambda () "the probe ran"))))
    (let ((turn (yeah-turn-run session "do the thing" (yeah-check--works-then-reports)
                                nil 60000 max-nudges)))
      (yeah-check--wait-for (lambda () (yeah-turn-done turn)))
      (unless (yeah-turn-done turn)
        (push "the turn did not finish" failures))
      (let ((records (yeah-check--records root name)))
        (ignore-errors (delete-directory root t t))
        (list turn records failures)))))

(let ((failures nil))
  ;; --- the supervised run ---
  (let* ((result (yeah-check--run "supervised" 2))
         (turn (nth 0 result))
         (records (nth 1 result)))
    (push (nth 2 result) failures)
    (when (eq 'completed (yeah-turn-state turn))
      (push (format "the supervised run ended in %S: a text answer is not a completion"
                    (yeah-turn-state turn))
            failures))
    (unless (eq 'failed (yeah-turn-state turn))
      (push (format "the supervised run ended in %S, not failed: it spent its budget without finishing"
                    (yeah-turn-state turn))
            failures))
    (unless (yeah-check--some-record records "nudge")
      (push "the model was not nudged into the call of `finish'" failures))
    (unless (yeah-check--some-record records "unfinished")
      (push "the run that did not finish is not in the log" failures))
    (when (yeah-check--some-record records "finish")
      (push "the run has a record of `finish': the model never called it" failures)))

  ;; --- the unsupervised run ---
  (let* ((result (yeah-check--run "unsupervised" 0))
         (turn (nth 0 result)))
    (push (nth 2 result) failures)
    (unless (eq 'completed (yeah-turn-state turn))
      (push (format "the unsupervised run ended in %S, not completed: nobody was there to nudge it"
                    (yeah-turn-state turn))
            failures)))

  (dolist (failure (apply #'append failures))
    (message "text-end: %s" failure))
  (if (apply #'append failures)
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-text-answer-does-not-end-a-supervised-run.el ends here
