;;; check-compaction-degrades-when-the-summary-is-missing.el --- the run goes on -*- lexical-binding: t; no-byte-compile: t -*-
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
;; summary of the conversation.  A provider that answers with an empty
;; message answers with no summary at all.
;;
;; The run must not die because of that.  The summary is an economy, not
;; a necessity: the harness prunes the old outputs of the tools, the
;; journal says that the summary did not arrive, and the run goes on.
;; Only a second overflow without a summary ends the run, and then the
;; journal says why.
;;
;; Exit codes: 0 — the run degraded and went on; 1 — it died because the
;; model wrote no summary.

;;; Code:

(require 'cl-lib)
(require 'yeah-turn)
(require 'yeah-tools)
(require 'yeah-perm)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--expect (ok message)
  "Record MESSAGE as a failure when OK is nil."
  (unless ok
    (push message yeah-check--failures)))

(defun yeah-check--record-of-type (records type)
  "Return the first record of TYPE in RECORDS, or nil."
  (cl-find-if (lambda (record) (equal type (plist-get record :type))) records))

(let* ((root (make-temp-file "yeah-compaction-degrades" t))
       (session (yeah-session-open "degrades" root))
       (turn nil)
       (asked 0))
  (unwind-protect
      (progn
        (yeah-tools-reset-for-test)
        (yeah-perm-rules-reset-for-test)
        (yeah-tools-register
         (list :name "probe" :description "probe" :input nil
               :handler (lambda () "tool output")))
        (yeah-perm-rules-add (yeah-perm-rule-make "probe" "*" 'allow))
        (let ((transport
               (lambda (prompt callback)
                 (if (string-prefix-p "Summarize this conversation" prompt)
                     ;; The provider answers, and the answer holds no summary.
                     (funcall callback "" nil)
                   (setq asked (1+ asked))
                   (if (= asked 1)
                       (funcall callback
                                (list 'tool-call
                                      (list (list :name "probe") nil
                                            (lambda (_value)
                                              (funcall callback "the tool ran")))))
                     ;; The model answers the delivered results.
                     (funcall callback "the work is done"))))))
          (setq turn (yeah-turn-run session "start" transport nil 1))
          (let ((deadline (+ (float-time) 10)))
            (while (and (not (yeah-turn-done turn))
                        (< (float-time) deadline))
              (accept-process-output nil 0.02))))
        ;; 1. The run went on.
        (yeah-check--expect
         (eq 'completed (yeah-turn-state turn))
         (format "the run died because the model wrote no summary: %S"
                 (yeah-turn-state turn)))
        ;; 2. The journal says what happened.
        (let* ((records (yeah-session-records session))
               (failure (yeah-check--record-of-type records "compaction-failed"))
               (pruning (yeah-check--record-of-type records "pruning"))
               (error (yeah-check--record-of-type records "error")))
          (yeah-check--expect
           failure
           "the journal does not say that the summary did not arrive")
          (yeah-check--expect
           pruning
           "the old outputs of the tools were not pruned")
          (yeah-check--expect
           (null error)
           (format "the run wrote an error into the journal: %S" error))))
    (ignore-errors (delete-directory root t t))
    (dolist (failure yeah-check--failures)
      (message "compaction-degrades: %s" failure))
    (if yeah-check--failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-compaction-degrades-when-the-summary-is-missing.el ends here
