;;; yeah-context.el --- the budget of the context -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A run is a conversation, and a conversation has a size. The size is
;; counted in tokens, and the count is what decides whether the run may
;; go on: when the context of the model is nearly full, the run must be
;; made shorter, and it must be made shorter without losing what
;; happened.
;;
;; There are two ways to make it shorter, and they are not the same:
;;
;;   * COMPACTION writes a summary of what was said and keeps the
;;     records on disk. The summary is written by the model, because
;;     nothing else knows what mattered.
;;
;;   * PRUNING marks the outputs of old tools as no longer to be sent
;;     to the model. The records stay where they are — the log is
;;     append-only and a pruned record is still a record — but the model
;;     stops carrying them around.
;;
;; The two are counted separately, because they cost different things:
;; a compaction costs a model call, a pruning costs nothing.

;;; Code:

(require 'cl-lib)
(require 'yeah-session)

(defvar yeah-context--transport nil
  "The transport the summarizer asks the model through.
It is a variable and not a constant so that a test can put a fake model
under it. When it is nil, the gptel bridge is used.")

(defconst yeah-context--chars-per-token 4
  "How many characters of text make one token.
The number is the same one the reference harnesses use; it is an
estimate, and an estimate that is honest about being an estimate is
better than a counter that pretends otherwise.")

(defconst yeah-context--default-budget 60000
  "The number of tokens of context a run may hold before it is compacted.
It is a default and not a law: a model with a bigger window may hold
more, and the number belongs to the model, not to the kernel.")

(defun yeah-context-tokens (text)
  "Return the number of tokens TEXT is worth."
  (if (or (null text) (not (stringp text)))
      0
    (max 0 (ceiling (/ (length text) (float yeah-context--chars-per-token))))))

(defun yeah-context-record-tokens (record)
  "Return the number of tokens the RECORD is worth."
  (let ((text (format "%S" record)))
    (yeah-context-tokens text)))

(defun yeah-context-usage (records)
  "Return the number of tokens the RECORDS hold.
The usage events are counted first, because they are what the provider
reported; the rest is estimated from the text of the records."
  (let ((reported 0)
        (estimated 0))
    (dolist (record records)
      (if (equal (plist-get record :type) "usage")
          (setq reported (+ reported (or (plist-get record :input) 0)
                              (or (plist-get record :output) 0)))
        (setq estimated (+ estimated (yeah-context-record-tokens record)))))
    (list :reported reported :estimated estimated :total (+ reported estimated))))

(defun yeah-context-overflow-p (records &optional budget)
  "Non-nil when the context of RECORDS does not fit into BUDGET tokens.
BUDGET defaults to `yeah-context--default-budget'."
  (> (plist-get (yeah-context-usage records) :total)
     (or budget yeah-context--default-budget)))

(defun yeah-context-prune (records &optional keep-chars)
  "Return the records of the run with the old tool outputs marked.
A record is marked, not removed: the log is append-only, and what is
marked is only no longer sent to the model. KEEP-CHARS is the tail of
the conversation that is kept whole; it defaults to a quarter of the
budget."
  (let* ((texts (mapcar (lambda (record) (format "%S" record)) records))
         (total (apply #'+ (mapcar #'length texts)))
         (keep (or keep-chars (/ yeah-context--default-budget 4)))
         (drop-from total))
    (let ((i 0))
      (while (and (< i (length records)) (> drop-from keep))
        (let ((record (nth i records)))
          (when (equal (plist-get record :type) "tool-end")
            (setq drop-from (- drop-from (length (nth i texts))))
            (setf (nth i records)
                  (plist-put (plist-put record :pruned t) :pruned-at (format-time-string "%Y-%m-%dT%H:%M:%S%z")))))
        (setq i (1+ i))))
    records))

(defun yeah-context-summarize (text &optional transport)
  "Ask the model to summarize TEXT and return what it said.
The model is the only one who knows what mattered in a conversation, so
the summary of a run is written by the model and by nobody else.

TRANSPORT is a function of (PROMPT CALLBACK) that calls CALLBACK with
the answer; it defaults to the gptel bridge. The answer arrives on the
event loop, so the loop is pumped until it comes — this is the one place
where the main loop is held, and it happens between turns of a run."
  (let* ((transport (or transport
                      yeah-context--transport
                      (and (fboundp 'yeah-gptel-request) #'yeah-gptel-request)))
         (answer nil))
    (unless transport
      (signal 'user-error (list "yeah-context-summarize: no transport")))
    (funcall transport
             (format "Summarize this conversation for someone who will continue it. \
Keep what was asked, what was done, what is open, and which files matter. \
Answer with the summary and nothing else.\n\n%s" text)
             (lambda (response &optional _info)
               (when (stringp response)
                 (setq answer response))))
    (let ((waited 0))
      (while (and (null answer) (< waited 120))
        (accept-process-output nil 1)
        (setq waited (1+ waited))))
    (or answer "")))

(provide 'yeah-context)
;;; yeah-context.el ends here
