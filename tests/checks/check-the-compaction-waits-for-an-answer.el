;;; check-the-compaction-waits-for-an-answer.el --- the compaction waits for the answer -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The context of a run overflows, and the harness asks the model for a
;; summary of the conversation.  The provider answers in pieces, and the
;; pieces are not the same thing: a model that reasons sends its thinking
;; before its answer.
;;
;; The compaction took the first piece for the answer.  A live run of the
;; wave 41 died on that: the compaction said "compaction failed" while the
;; provider was still thinking, the run degraded, and the summary that came
;; later committed a compaction and continued a run whose machine was in a
;; state that has no such transition -- "yeah-loop-tick: no transition from
;; awaiting-tool on continue" -- and the run was lost.
;;
;; The compaction waits for the answer now, and the result of a compaction is
;; delivered once.  The run that meets a provider that thinks first goes on,
;; and the run that meets a provider that answers nothing degrades and goes
;; on as well.
;;
;; The model here is a FAKE: a provider that plays the shape of the live
;; run.  No network is touched.
;;
;; Exit codes: 0 — the compaction waited for the answer and the run went on;
;; 1 — it did not.

;;; Code:

(require 'cl-lib)
(require 'yeah-perm)
(require 'yeah-session)
(require 'yeah-tools)
(require 'yeah-turn)

(defconst yeah-check--summary-prompt "Summarize this conversation"
  "The beginning of the prompt of a request for a summary.")

(defconst yeah-check--summary "the summary of the work so far"
  "The summary that the fake provider writes.")

(defconst yeah-check--thinking '(reasoning "the model thinks about the summary")
  "The thinking of a provider that reasons before it answers.")

(defun yeah-check--fail (ok message)
  "Return MESSAGE when OK is nil, and nil when OK holds."
  (unless ok
    message))

(defun yeah-check--records-of-type (records type)
  "Return the records of TYPE in RECORDS."
  (cl-remove-if-not (lambda (record)
                      (equal type (plist-get record :type)))
                    records))

(defun yeah-check--no-error (records)
  "Return nil when RECORDS holds no error, and the payload of the error otherwise."
  (let ((error (car (yeah-check--records-of-type records "error"))))
    (when error
      (plist-get error :payload))))

(defun yeah-check--probe ()
  "Register the tool the fake model calls, and allow it."
  (yeah-tools-reset-for-test)
  (yeah-perm-rules-reset-for-test)
  (yeah-tools-register
   (list :name "probe" :description "probe" :input nil
         :handler (lambda () "the output of the probe")))
  (yeah-perm-rules-add (yeah-perm-rule-make "probe" "*" 'allow)))

(defun yeah-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE holds, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 15))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-check--run (transport)
  "Run a turn with TRANSPORT and return the run and the records of it."
  (let* ((root (make-temp-file "yeah-compaction-waits" t))
         (session (yeah-session-open "waits" root)))
    (yeah-check--probe)
    (let ((turn (yeah-turn-run session "start" transport nil 1)))
      (yeah-check--await (lambda () (yeah-turn-done turn)))
      (let ((result (list :turn turn
                           :records (yeah-session-records session))))
        (ignore-errors (delete-directory root t t))
        result))))

(defun yeah-check--the-model-acts (&optional delay)
  "Return a transport whose model calls the probe tool and answers after DELAY.
The answer that follows the tool comes after DELAY seconds, so that the run
is still alive when the provider answers again.  The model ends the run
through the call of `finish': a supervised run does not end on the words of
the model (wave 53)."
  (lambda (_prompt callback)
    (funcall callback
             (list 'tool-call
                   (list (list :name "probe") (list)
                         (lambda (_value)
                           (if delay
                               (run-with-timer delay nil
                                               (lambda ()
                                                 (funcall callback
                                                          (list 'tool-call
                                                                (list (list :name "finish")
                                                                      (list "the tool ran")
                                                                      (lambda (_answer) nil))))))
                             (funcall callback
                                      (list 'tool-call
                                            (list (list :name "finish")
                                                  (list "the tool ran")
                                                  (lambda (_answer) nil)))))))))))

(defun yeah-check--the-thinking-is-not-the-answer ()
  "The thinking of the provider is not the end of the request of a summary."
  (let* ((transport
          (lambda (prompt callback)
            (if (string-prefix-p yeah-check--summary-prompt prompt)
                ;; The provider thinks first and answers after its thinking:
                ;; the thinking is the road to the answer.
                (progn
                  (funcall callback yeah-check--thinking nil)
                  (funcall callback yeah-check--summary nil))
              (funcall (yeah-check--the-model-acts) prompt callback))))
         (result (yeah-check--run transport))
         (turn (plist-get result :turn))
         (records (plist-get result :records))
         (compactions (yeah-check--records-of-type records "compaction")))
    (list
     (yeah-check--fail
      (eq (yeah-turn-state turn) 'completed)
      (format "the run did not go on: %S" (yeah-turn-state turn)))
     (yeah-check--fail
      (= (length compactions) 1)
      (format "the journal holds %d compactions, not one" (length compactions)))
     (yeah-check--fail
      (and compactions
           (equal yeah-check--summary
                  (plist-get (car compactions) :summary)))
      "the summary of the provider is not in the journal")
     (yeah-check--fail
      (null (yeah-check--records-of-type records "compaction-failed"))
      "the thinking of the provider ended the request of the summary")
     (let ((error (yeah-check--no-error records)))
       (yeah-check--fail (null error)
                        (format "the run wrote an error into the journal: %S"
                                error))))))

(defun yeah-check--the-result-arrives-once ()
  "The result of a compaction is delivered once, and not twice."
  (let* ((transport
          (lambda (prompt callback)
            (if (string-prefix-p yeah-check--summary-prompt prompt)
                ;; The provider answers the summary twice: the request is one
                ;; request, and the context is compacted once.
                (progn
                  (funcall callback yeah-check--thinking nil)
                  (funcall callback yeah-check--summary nil)
                  (funcall callback yeah-check--summary nil))
              ;; The model acts, and it answers late: the run is still alive
              ;; when the provider answers the summary again.
              (funcall (yeah-check--the-model-acts 0.3) prompt callback))))
         (result (yeah-check--run transport))
         (turn (plist-get result :turn))
         (records (plist-get result :records))
         (compactions (yeah-check--records-of-type records "compaction")))
    (list
     (yeah-check--fail
      (eq (yeah-turn-state turn) 'completed)
      (format "the run did not go on: %S" (yeah-turn-state turn)))
     (yeah-check--fail
      (= (length compactions) 1)
      (format "the journal holds %d compactions, not one" (length compactions)))
     (let ((error (yeah-check--no-error records)))
       (yeah-check--fail (null error)
                        (format "the run wrote an error into the journal: %S"
                                error))))))

(defun yeah-check--a-late-answer-does-not-break-the-run ()
  "A summary that arrives late does not break the run that waits for it."
  (let* ((transport
          (lambda (prompt callback)
            (if (string-prefix-p yeah-check--summary-prompt prompt)
                ;; The provider thinks first and answers the summary later,
                ;; when the run is waiting for it.
                (progn
                  (funcall callback yeah-check--thinking nil)
                  (run-with-timer 0.1 nil
                                  (lambda ()
                                    (funcall callback yeah-check--summary nil))))
              ;; The model acts, and it answers late: the run waits for the
              ;; answer of the model.  The answer is the call of `finish': a
              ;; supervised run does not end on the words of the model
              ;; (wave 53).
              (funcall callback
                       (list 'tool-call
                             (list (list :name "probe") (list)
                                   (lambda (_value)
                                     (run-with-timer
                                      0.3 nil
                                      (lambda ()
                                        (funcall callback
                                                 (list 'tool-call
                                                       (list (list :name "finish")
                                                             (list "the work is done")
                                                             (lambda (_answer) nil)))))))))))))
         (result (yeah-check--run transport))
         (turn (plist-get result :turn))
         (records (plist-get result :records)))
    (list
     (yeah-check--fail
      (eq (yeah-turn-state turn) 'completed)
      (format "the run did not go on: %S" (yeah-turn-state turn)))
     (yeah-check--fail
      (= (length (yeah-check--records-of-type records "compaction")) 1)
      "the journal holds no compaction of the context")
     (yeah-check--fail
      (null (yeah-check--records-of-type records "compaction-failed"))
      "the thinking of the provider ended the request of the summary")
     (let ((error (yeah-check--no-error records)))
       (yeah-check--fail (null error)
                        (format "the run wrote an error into the journal: %S"
                                error))))))

(defun yeah-check--a-provider-that-answers-nothing-degrades-the-run ()
  "A provider that ends the request of the summary without an answer degrades the run."
  (let* ((transport
          (lambda (prompt callback)
            (if (string-prefix-p yeah-check--summary-prompt prompt)
                ;; The provider thinks, and the stream ends without an answer:
                ;; there is no summary, and the run says so.
                (progn
                  (funcall callback yeah-check--thinking nil)
                  (funcall callback t nil))
              (funcall (yeah-check--the-model-acts) prompt callback))))
         (result (yeah-check--run transport))
         (turn (plist-get result :turn))
         (records (plist-get result :records)))
    (list
     (yeah-check--fail
      (eq (yeah-turn-state turn) 'completed)
      (format "the run did not go on: %S" (yeah-turn-state turn)))
     (yeah-check--fail
      (= (length (yeah-check--records-of-type records "compaction-failed")) 1)
      "the journal does not say that the summary did not arrive")
     (yeah-check--fail
      (= (length (yeah-check--records-of-type records "pruning")) 1)
      "the old outputs of the tools were not pruned")
     (let ((error (yeah-check--no-error records)))
       (yeah-check--fail (null error)
                        (format "the run wrote an error into the journal: %S"
                                error))))))

(let ((failures (delq nil
                     (append
                      (yeah-check--the-thinking-is-not-the-answer)
                      (yeah-check--the-result-arrives-once)
                      (yeah-check--a-late-answer-does-not-break-the-run)
                      (yeah-check--a-provider-that-answers-nothing-degrades-the-run)))))
  (dolist (failure failures)
    (message "compaction-waits: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-compaction-waits-for-an-answer.el ends here
