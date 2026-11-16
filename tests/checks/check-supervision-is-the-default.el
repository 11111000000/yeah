;;; check-supervision-is-the-default.el --- the kernel supervises a run -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The budget of the completion supervision is a default of the kernel, and
;; the default is positive: a run of Yeah is supervised unless the caller
;; asks for no supervision at all.  A budget of zero made the ACP route hand
;; out `end_turn' for a run in which the model had only described its next
;; step: the wire said the work was done, and nothing had been done.
;;
;; The model here is a FAKE: a transport that only talks.  The check runs a
;; turn with the default budget and asserts that the model was nudged and
;; that the run did not end as a completed job.
;;
;; Exit codes: 0 — the default supervises; 1 — it does not.

;;; Code:

(require 'cl-lib)
(require 'yeah-turn)
(require 'yeah-session)

(defun yeah-check--talks-only ()
  "Return a transport whose model only describes its next step.
The model never calls a tool and never finishes: it talks."
  (lambda (_prompt callback)
    (funcall callback "I will write the file now.")))

(defun yeah-check--records (root name)
  "Return the records of the log of session NAME under ROOT."
  (with-temp-buffer
    (insert-file-contents (expand-file-name (format "sessions/%s.jsonl" name) root))
    (mapcar (lambda (line) (json-parse-string line :object-type 'plist))
            (split-string (buffer-string) "\n" t))))

(defun yeah-check--run-with-the-default ()
  "Run a turn with the default budget and return the failures.
An empty list means the default supervised the run."
  (let* ((root (make-temp-file "yeah-supervision-check" t))
         (session (yeah-session-open "supervised" root))
         (failures nil))
    (let* ((turn (yeah-turn-run session "do the thing" (yeah-check--talks-only)))
           (records (yeah-check--records root "supervised")))
      (unless (yeah-turn-done turn)
        (push "the turn did not finish" failures))
      (unless (eq 'failed (yeah-turn-state turn))
        (push (format "the turn ended in %S, not failed: the default does not supervise it"
                      (yeah-turn-state turn))
              failures))
      (unless (cl-some (lambda (record)
                          (equal "nudge" (plist-get record :type)))
                        records)
        (push "the model was not nudged: the run was not supervised" failures))
      (unless (cl-some (lambda (record)
                          (equal "unfinished" (plist-get record :type)))
                        records)
        (push "the run that did not finish is not in the log" failures)))
    (ignore-errors (delete-directory root t t))
    failures))

(let ((failures nil))
  (unless (and (integerp yeah-turn-default-max-nudges)
               (> yeah-turn-default-max-nudges 0))
    (push (format "the default budget of the supervision is %S, not a positive number"
                  yeah-turn-default-max-nudges)
          failures))
  (setq failures (append failures (yeah-check--run-with-the-default)))
  (dolist (failure failures)
    (message "supervision: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-supervision-is-the-default.el ends here
