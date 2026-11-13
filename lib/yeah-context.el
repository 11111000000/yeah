;;; yeah-context.el --- context budgets and projections -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Provider-reported usage and estimated context size are separate values.
;; Estimates are CJK-aware and calibrated against actual input usage when it
;; becomes available.  Pruning is a pure projection; recording it appends an
;; event and never rewrites source records.  Summarization has an asynchronous
;; API and never waits on the main event loop or commits an empty summary.

;;; Code:

(require 'cl-lib)
(require 'yeah-session)
(require 'yeah-events)

(defgroup yeah-context nil
  "Yeah context budgets and projections."
  :group 'yeah)

(defvar yeah-context--transport nil
  "Optional model transport used for summaries and deterministic tests.")

(defcustom yeah-context-default-budget 60000
  "Default estimated token budget before a run compacts its context."
  :type 'integer
  :group 'yeah-context)

(defconst yeah-context--default-budget 60000
  "Compatibility value for callers of the former budget constant.")

(defvar yeah-context-token-calibration 1.0
  "Multiplicative calibration for estimated tokens, learned from usage.")

(defconst yeah-context--summary-prompt
  "Summarize this conversation so another agent can continue it accurately.
Preserve the goal, constraints and preferences, progress, key decisions,
mistakes and dead ends, important files and technical details, open questions,
and concrete next steps.  For exploratory discussions preserve narrative flow
and explicit user instructions.  Return only the summary.\n\n%s"
  "Prompt used for model-written compaction summaries.")

(defconst yeah-context--cjk-regexp
  (concat "[" (string #x3000) "-" (string #x9fff)
          (string #xf900) "-" (string #xfaff)
          (string #xff00) "-" (string #xffef)
          (string #x20000) "-" (string #x2fa1f) "]")
  "Regexp matching one CJK character, for token estimation.
The count is measured with `how-many', which is C speed, so the estimate
does not walk the text character by character in Lisp.")

(defun yeah-context-estimate-tokens (text)
  "Estimate tokens in TEXT using Latin/CJK-aware character classes."
  (if (not (stringp text))
      0
    (let ((cjk (with-temp-buffer
                 (insert text)
                 (goto-char (point-min))
                 (how-many yeah-context--cjk-regexp))))
      (max 0 (ceiling (+ (/ (- (length text) cjk) 4.0)
                         (/ cjk 2.0)))))))

(defun yeah-context-tokens (text)
  "Return the estimated token count for TEXT."
  (yeah-context-estimate-tokens text))

(defun yeah-context-record-tokens (record)
  "Return the estimated token count for RECORD."
  (yeah-context-estimate-tokens (format "%S" record)))

(defun yeah-context-calibrate (estimated info)
  "Calibrate ESTIMATED tokens against provider usage in INFO.
Return the new calibration, clamped to [0.5, 3.0].  Unknown or zero values
leave the previous calibration unchanged."
  (let* ((usage (and (listp info) (plist-get info :yeah-usage)))
         (actual (and usage (plist-get usage :input))))
    (if (and (numberp actual) (> actual 0)
             (numberp estimated) (> estimated 0))
        (setq yeah-context-token-calibration
              (max 0.5 (min 3.0 (/ (float actual) estimated))))
      yeah-context-token-calibration)))

(defun yeah-context-usage (records)
  "Return reported, estimated and total token usage for RECORDS."
  (let ((reported 0)
        (estimated 0))
    (dolist (record records)
      (if (equal (plist-get record :type) "usage")
          (setq reported (+ reported (or (plist-get record :input) 0)
                            (or (plist-get record :output) 0)))
        (setq estimated (+ estimated (yeah-context-record-tokens record)))))
    (let ((calibrated (round (* estimated yeah-context-token-calibration))))
      (list :reported reported :estimated calibrated
            :raw-estimated estimated
            :calibration yeah-context-token-calibration
            :total (+ reported calibrated)))))

(defun yeah-context-overflow-p (records &optional budget)
  "Return non-nil when RECORDS exceed BUDGET tokens."
  (> (plist-get (yeah-context-usage records) :total)
     (or budget yeah-context-default-budget
         yeah-context--default-budget)))

(defun yeah-context-prune (records &optional keep-chars)
  "Return a projected copy of RECORDS with old tool outputs marked pruned.
The input records are not modified.  KEEP-CHARS is the recent suffix retained
whole, defaulting to one quarter of the default token budget."
  (let* ((projected (mapcar (lambda (record) (copy-sequence record)) records))
         (texts (mapcar (lambda (record) (format "%S" record)) projected))
         (total (apply #'+ (mapcar #'length texts)))
         (keep (or keep-chars (/ yeah-context-default-budget 4)))
         (remaining total))
    (let ((index 0))
      (while (and (< index (length projected)) (> remaining keep))
        (let ((record (nth index projected)))
          (when (equal (plist-get record :type) "tool-end")
            (setq remaining (- remaining (length (nth index texts))))
            (setf (nth index projected)
                  (plist-put (plist-put record :pruned t)
                             :pruned-at
                             (format-time-string "%Y-%m-%dT%H:%M:%S%z")))))
        (setq index (1+ index))))
    projected))

(defun yeah-context-prune-session (session &optional keep-chars)
  "Record a pruning event for SESSION and return its projected records."
  (let ((keep (or keep-chars (/ yeah-context-default-budget 4))))
    (yeah-events-write session "pruning" :keep-chars keep)
    (yeah-context-prune (yeah-session-project session) keep)))

(defun yeah-context-project (session)
  "Return the current model-facing projection of SESSION."
  (let* ((records (yeah-session-records session))
         (latest nil))
    (dolist (record records)
      (when (equal (plist-get record :type) "pruning")
        (setq latest record)))
    (if latest
        (yeah-context-prune (yeah-session-project session)
                            (plist-get latest :keep-chars))
      (yeah-session-project session))))

(defun yeah-context-summarize-async (text transport callback)
  "Ask TRANSPORT to summarize TEXT and deliver the result to CALLBACK.
CALLBACK receives (SUMMARY INFO).  SUMMARY is nil for provider failures,
non-string responses and blank answers.  The function returns immediately."
  (unless (functionp callback)
    (signal 'user-error (list "yeah-context-summarize-async: invalid callback")))
  (let ((transport (or transport
                       yeah-context--transport
                       (and (fboundp 'yeah-gptel-request)
                            #'yeah-gptel-request))))
    (unless transport
      (signal 'user-error (list "yeah-context-summarize-async: no transport")))
    (funcall transport
             (format yeah-context--summary-prompt text)
             (lambda (response &optional info)
               (funcall callback
                        (and (stringp response)
                             (not (string-blank-p response))
                             response)
                        info)))))

(defun yeah-context-summarize (text &optional transport)
  "Return a summary only when TRANSPORT answers synchronously.
This compatibility wrapper never waits.  For real asynchronous providers use
`yeah-context-summarize-async'.  A pending or failed answer signals
`user-error' instead of producing an empty authoritative summary."
  (let ((answered nil)
        (pending nil)
        (info nil))
    (yeah-context-summarize-async
     text transport
     (lambda (summary request-info)
       (setq answered summary info request-info pending t)))
    (cond
     (answered answered)
     (pending
      (signal 'user-error
              (list (format "yeah-context-summarize: no summary: %S" info))))
     (t
      (signal 'user-error
              (list "yeah-context-summarize: response is asynchronous; use the async API"))))))

(provide 'yeah-context)
;;; yeah-context.el ends here
