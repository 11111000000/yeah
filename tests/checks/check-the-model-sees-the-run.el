;;; check-the-model-sees-the-run.el --- the model is told what the run has done -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Every request of the harness starts a fresh conversation with the model:
;; the transport is given a prompt, and the prompt is all the model is told.
;; A model that answers with a plan instead of an action therefore loses the
;; run: the next request carries no trace of the work, and the model starts
;; the task over.  The live run of the wave 41 of 2026-11-17 is the proof of
;; the shape: the model read `AGENTS.md' six times, read the check of the
;; bridge twice and read the plan twice, and changed nothing.
;;
;; The run now tells the model what it has already done: every request carries
;; the transcript of the run before the prompt.  The transcript is a projection
;; of the journal, and the journal keeps the plain messages it was written
;; with.
;;
;; Three things are checked here.
;;
;; 1. The first request of a run carries the request and nothing else: a run
;;    that has done nothing has nothing to tell.
;; 2. A request that follows the work of the run carries the transcript: the
;;    call the model made, the result it got, and the answer it gave.
;; 3. The journal keeps the plain prompt: the transcript is a projection and
;;    not a second copy of the run in the journal.
;;
;; The model here is a FAKE: a transport that plays the shape of the live run.
;; No network is touched.
;;
;; Exit codes: 0 — the model was told what the run has done; 1 — it was not.

;;; Code:

(require 'cl-lib)
(require 'yeah-perm)
(require 'yeah-session)
(require 'yeah-tools)
(require 'yeah-turn)

(defconst yeah-check--transcript-prefix
  "This is what has been done in this run so far:"
  "The words the transcript of a run begins with.")

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
         :handler (lambda () "the output of the probe")))
  (yeah-perm-rules-add (yeah-perm-rule-make "probe" "*" 'allow)))

(defun yeah-check--transport (record)
  "Return a transport that plays the shape of the live run.
RECORD is called with the prompt of every request of the model.
The model calls a tool, and answers with a plan when the result is back.  The
plan ends the request of the model, and the harness asks again: that second
request is the one that must carry the work of the run."
  (let ((count 0))
    (lambda (prompt callback)
      (funcall record prompt)
      (setq count (1+ count))
      (if (= count 1)
          (funcall callback
                   (list 'tool-call
                         (list (list :name "probe") (list)
                               (lambda (_value)
                                 (funcall callback "I'll read the file next.")))))
        (funcall callback "the work is done")))))

(defun yeah-check--wait (turn)
  "Wait until TURN is done, or ten seconds pass."
  (let ((deadline (+ (float-time) 10)))
    (while (and (not (yeah-turn-done turn))
                (< (float-time) deadline))
      (accept-process-output nil 0.02))))

(defun yeah-check--run ()
  "Run the turn and return the turn, the records and the prompts of the model."
  (let* ((root (make-temp-file "yeah-transcript" t))
         (session (yeah-session-open "transcript" root))
         (prompts nil))
    (yeah-check--probe)
    (let ((turn (yeah-turn-run session "start"
                               (yeah-check--transport
                                (lambda (prompt) (push prompt prompts)))
                               nil 60000 2)))
      (yeah-check--wait turn)
      (let ((result (list :turn turn
                           :records (yeah-session-records session)
                           :prompts (nreverse prompts))))
        (ignore-errors (delete-directory root t t))
        result))))

(defun yeah-check--the-first-request-carries-nothing-but-the-request ()
  "The first request of a run is the request itself."
  (let* ((result (yeah-check--run))
         (prompts (plist-get result :prompts)))
    (list
     (yeah-check--fail
      prompts
      "the model was asked nothing")
     (yeah-check--fail
      (equal "start" (car prompts))
      (format "the first request of the run is %S, not the request itself"
              (car prompts))))))

(defun yeah-check--a-request-that-follows-the-work-carries-the-transcript ()
  "A request that follows the work of the run carries the transcript."
  (let* ((result (yeah-check--run))
         (prompts (plist-get result :prompts))
         (second (nth 1 prompts)))
    (list
     (yeah-check--fail
      second
      "the model was asked only once")
     (yeah-check--fail
      (or (null second)
          (string-prefix-p yeah-check--transcript-prefix second))
      (format "the second request does not carry the transcript of the run: %S"
              second))
     (yeah-check--fail
      (and second (string-match-p "\\[tool probe" second))
      (format "the request does not name the call the model made: %S" second))
     (yeah-check--fail
      (and second (string-match-p "the output of the probe" second))
      (format "the request does not carry the result of the call: %S" second))
     (yeah-check--fail
      (and second (string-match-p "I'll read the file next" second))
      (format "the request does not carry the answer the model gave: %S" second)))))

(defun yeah-check--the-journal-keeps-the-plain-prompt ()
  "The journal keeps the plain message: the transcript is a projection."
  (let* ((result (yeah-check--run))
         (records (plist-get result :records))
         (messages (yeah-check--records-of-type records "user-message"))
         (holds-transcript
          (cl-find-if
           (lambda (record)
             (let ((case-fold-search nil))
               (and (stringp (plist-get record :payload))
                    (string-match-p yeah-check--transcript-prefix
                                    (plist-get record :payload)))))
           messages)))
    (list
     (yeah-check--fail
      messages
      "the journal holds no message of the run")
     (yeah-check--fail
      (cl-find-if (lambda (record)
                    (equal "start" (plist-get record :payload)))
                  messages)
      "the journal does not hold the plain request of the run")
     (yeah-check--fail
      (null holds-transcript)
      "the journal holds the transcript: the projection is a copy of the run"))))

(let ((failures (delq nil
                     (append
                      (yeah-check--the-first-request-carries-nothing-but-the-request)
                      (yeah-check--a-request-that-follows-the-work-carries-the-transcript)
                      (yeah-check--the-journal-keeps-the-plain-prompt)))))
  (dolist (failure failures)
    (message "transcript: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-model-sees-the-run.el ends here
