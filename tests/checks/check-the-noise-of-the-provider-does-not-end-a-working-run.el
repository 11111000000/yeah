;;; check-the-noise-of-the-provider-does-not-end-a-working-run.el --- the silence of a provider does not end a run that works -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A provider answers with an empty message after the tools of the model have
;; come back.  The model has acted: it called its tools, and the results are
;; in front of it.  The empty message is the noise of the provider, not the
;; refusal of the model to act.
;;
;; The budget of the nudges pays for the nudges that no effect answered.  A
;; run whose model works must not be ended by the noise of the provider: the
;; live run of 2026-11-17 called seventeen tools and was ended with the
;; record "the model answered with an empty message 8 times and the run ended
;; without an effect" — the run had an effect, and the record said it had
;; none.
;;
;; Three things are checked here.
;;
;; 1. A run whose provider is noisy and whose model works goes on, and it can
;;    finish: the noise nudges the model, and the nudges do not spend the
;;    budget.
;; 2. A run whose model never acts still ends: the budget pays for the
;;    nudges that no effect answered, and the run says that it did not finish.
;; 3. The record of a run that did not finish is true: a run that called its
;;    tools is not described as a run that ended without an effect.
;;
;; The model here is a FAKE: a transport that plays the shape of the live
;; run.  No network is touched.
;;
;; Exit codes: 0 — the noise did not end the working run and the record is
;; true; 1 — it did.

;;; Code:

(require 'cl-lib)
(require 'yeah-perm)
(require 'yeah-session)
(require 'yeah-tools)
(require 'yeah-turn)

(defun yeah-check--fail (ok message)
  "Return MESSAGE when OK is nil, and nil when OK holds."
  (unless ok
    message))

(defun yeah-check--records-of-type (records type)
  "Return the records of TYPE in RECORDS."
  (cl-remove-if-not (lambda (record)
                      (equal type (plist-get record :type)))
                    records))

(defun yeah-check--probe ()
  "Register the tool the fake model calls, and allow it."
  (yeah-tools-reset-for-test)
  (yeah-perm-rules-reset-for-test)
  (yeah-tools-register
   (list :name "probe" :description "probe" :input nil
         :handler (lambda () "tool output")))
  (yeah-perm-rules-add (yeah-perm-rule-make "probe" "*" 'allow)))

(defun yeah-check--wait (turn)
  "Wait until TURN is done, or ten seconds pass."
  (let ((deadline (+ (float-time) 10)))
    (while (and (not (yeah-turn-done turn))
                (< (float-time) deadline))
      (accept-process-output nil 0.02))))

(defun yeah-check--noisy-provider (rounds)
  "Return a transport that plays the shape of the live run.
The model calls a tool, and the provider answers with an empty message after
every batch.  After ROUNDS rounds the model calls `finish'."
  (let ((count 0))
    (lambda (_prompt callback)
      (setq count (1+ count))
      (if (> count rounds)
          (funcall callback
                   (list 'tool-call
                         (list (list :name "finish") (list "the work is done")
                               (lambda (_value) nil))))
        (funcall callback
                 (list 'tool-call
                       (list (list :name "probe") (list)
                             (lambda (_value) (funcall callback "")))))))))

(defun yeah-check--silent-provider ()
  "Return a transport whose model never acts and never says anything."
  (lambda (_prompt callback)
    (funcall callback "")))

(defun yeah-check--stops-provider ()
  "Return a transport whose model acts once and then says nothing.
The first answer comes with a tool call; the silence that follows it is the
noise of the provider.  The silences that follow are the model itself."
  (let ((count 0))
    (lambda (_prompt callback)
      (setq count (1+ count))
      (if (= count 1)
          (funcall callback
                   (list 'tool-call
                         (list (list :name "probe") (list)
                               (lambda (_value) (funcall callback "")))))
        (funcall callback "")))))

(defun yeah-check--run (name transport max-nudges)
  "Run TURN with TRANSPORT under the session NAME and return the turn."
  (let* ((root (make-temp-file "yeah-noise" t))
         (session (yeah-session-open name root)))
    (yeah-check--probe)
    (let ((turn (yeah-turn-run session "start" transport nil 60000 max-nudges)))
      (yeah-check--wait turn)
      (let ((result (list :turn turn :records (yeah-session-records session))))
        (ignore-errors (delete-directory root t t))
        result))))

(defun yeah-check--the-noise-does-not-end-a-working-run ()
  "A run whose provider is noisy and whose model works goes on and finishes.
Return the failures; an empty list means the run survived the noise."
  (let* ((result (yeah-check--run "noisy" (yeah-check--noisy-provider 5) 2))
         (turn (plist-get result :turn))
         (records (plist-get result :records))
         (nudges (yeah-check--records-of-type records "nudge")))
    (list
     (yeah-check--fail
      (eq 'completed (yeah-turn-state turn))
      (format "the run ended in %S, not completed: the noise of the provider spent the budget"
              (yeah-turn-state turn)))
     (yeah-check--fail
      (null (cl-remove-if-not (lambda (record)
                                 (equal "unfinished" (plist-get record :type)))
                               records))
      "the journal holds an unfinished record: the noise of the provider ended the run")
     (yeah-check--fail
      (> (length nudges) 2)
      (format "the run was nudged %d times, not more than the budget of two: the noise never reached the model"
              (length nudges))))))

(defun yeah-check--a-run-that-never-acts-still-ends ()
  "A run whose model never acts ends with the record that says so.
Return the failures; an empty list means the budget still pays."
  (let* ((result (yeah-check--run "silent" (yeah-check--silent-provider) 2))
         (turn (plist-get result :turn))
         (records (plist-get result :records))
         (unfinished (car (yeah-check--records-of-type records "unfinished"))))
    (list
     (yeah-check--fail
      (eq 'failed (yeah-turn-state turn))
      (format "the run ended in %S, not failed: a model that never acts looks done"
              (yeah-turn-state turn)))
     (yeah-check--fail
      unfinished
      "the journal holds no unfinished record")
     (yeah-check--fail
      (and unfinished
           (string-match-p "without an effect"
                           (or (plist-get unfinished :payload) "")))
      (format "the record does not say that the run ended without an effect: %S"
              (and unfinished (plist-get unfinished :payload)))))))

(defun yeah-check--the-record-of-a-run-that-did-not-finish-is-true ()
  "A run that called its tools is not described as a run without an effect.
Return the failures; an empty list means the record is true."
  (let* ((result (yeah-check--run "stops" (yeah-check--stops-provider) 2))
         (records (plist-get result :records))
         (unfinished (car (yeah-check--records-of-type records "unfinished")))
         (payload (and unfinished (plist-get unfinished :payload))))
    (list
     (unless unfinished
       "the journal holds no unfinished record")
     (unless (and payload (string-match-p "called 1 tool" payload))
       (format "the record does not name the tool the run called: %S" payload))
     (unless (and payload (not (string-match-p "without an effect" payload)))
       (format "the record says the run ended without an effect, and it did not: %S"
               payload)))))

(let ((failures (delq nil
                     (append (yeah-check--the-noise-does-not-end-a-working-run)
                             (yeah-check--a-run-that-never-acts-still-ends)
                             (yeah-check--the-record-of-a-run-that-did-not-finish-is-true)))))
  (dolist (failure failures)
    (message "provider-noise: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-noise-of-the-provider-does-not-end-a-working-run.el ends here
