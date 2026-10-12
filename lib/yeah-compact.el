;;; yeah-compact.el --- pure compactor over the session log -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The compactor is a pure projection over the append-only
;; session log (see `decisions/append-only-session-log@0' and
;; `decisions/compact-impl@0'). Given a session and a target
;; character count, it walks the records from oldest to newest,
;; accumulates a `prin1'-length budget, and returns the record
;; id of the first record that crosses the target. Records
;; before the cut-point are summarised; records from the
;; cut-point onwards are preserved verbatim.
;;
;; The compactor is A0-separated from `lib/yeah-session.el':
;; the only write it performs is through
;; `yeah-session-record-compaction', which appends a single
;; `compaction' record. Source records are never modified.
;;
;; Real summarisation is a `gptel' call (Tier 4 / Tier 5);
;; the default summarizer here is a deterministic placeholder
;; that returns a hand-readable string. The replacement point
;; is `yeah-compact-summarize''s optional SUMMARIZER argument.

;;; Code:

(require 'cl-lib)
(require 'yeah-session)

(defgroup yeah-compact nil
  "Yeah compactor (pure projection over the session log)."
  :group 'yeah)

(defun yeah-compact-cut-point (session target-chars)
  "Return the record id of the first record that crosses TARGET-CHARS.
Walks SESSION's records oldest to newest, accumulating
`(length (prin1-to-string record))' per record. Returns the
:id of the first record whose running total is strictly
greater than TARGET-CHARS. Returns nil when no record crosses
the budget (no compaction needed).

Records before the returned id are summarised; records from
the returned id onwards are preserved verbatim."
  (unless (and (consp session) (plist-get session :records))
    (signal 'user-error
            (list (format "yeah-compact-cut-point: not a session %S" session))))
  (unless (and (integerp target-chars) (>= target-chars 0))
    (signal 'user-error
            (list (format "yeah-compact-cut-point: target must be a non-negative integer, got %S"
                          target-chars))))
  (let ((running 0)
        (result nil))
    (dolist (r (yeah-session-records session))
      (setq running (+ running (length (prin1-to-string r)))))
    (setq running 0)
    (dolist (r (yeah-session-records session))
      (setq running (+ running (length (prin1-to-string r))))
      (when (and (null result) (> running target-chars))
        (setq result (plist-get r :id))))
    result))

(defun yeah-compact--default-summarizer (records)
  "Deterministic placeholder summarizer.
Prints the count, the first record's id, and the last record's
id. The replacement point for the real `gptel' summarisation
(Tier 4 / Tier 5) is `yeah-compact-summarize''s optional
SUMMARIZER argument."
  (format "summary of %d records, first=%S, last=%S"
          (length records)
          (car records)
          (car (last records))))

(defun yeah-compact-summarize (session cut-point &optional summarizer)
  "Summarise the records before CUT-POINT in SESSION.
Returns the string produced by SUMMARIZER (a `(lambda (records) -> string)')
called with the list of records whose id is strictly less than
CUT-POINT. When SUMMARIZER is nil, uses
`yeah-compact--default-summarizer'."
  (unless (and (consp session) (plist-get session :records))
    (signal 'user-error
            (list (format "yeah-compact-summarize: not a session %S" session))))
  (unless (integerp cut-point)
    (signal 'user-error
            (list (format "yeah-compact-summarize: cut-point must be an integer, got %S"
                          cut-point))))
  (let ((before nil)
        (summarizer (or summarizer #'yeah-compact--default-summarizer)))
    (dolist (r (yeah-session-records session))
      (let ((rid (plist-get r :id)))
        (when (and (integerp rid) (< rid cut-point))
          (push r before))))
    (funcall summarizer (nreverse before))))

(defun yeah-compact-run (session target-chars &optional summarizer)
  "One-shot compaction entry point.
Returns a plist `(:cut-point ID :summary STRING :projection-count N)'.
When the cut-point is nil (budget not exceeded), the session log
is unchanged and the function returns a no-op plist with the
total record count as `:projection-count'. Otherwise gathers
records before the cut-point, summarises them, writes the
compaction via `yeah-session-record-compaction', and returns
the plist above."
  (let ((cut (yeah-compact-cut-point session target-chars)))
    (if (null cut)
        (list :cut-point nil
              :summary nil
              :projection-count (length (yeah-session-records session)))
      (let* ((summary (yeah-compact-summarize session cut summarizer))
             (compaction (list :cut-point cut :summary summary)))
        (yeah-session-record-compaction session compaction)
        (list :cut-point cut
              :summary summary
              :projection-count (length (yeah-session-project session)))))))

(defun yeah-compact-projection-length (session)
  "Return the record count in the current projection of SESSION.
A thin wrapper over `yeah-session-project'. Shrinks after a
compaction; grows again with new appends."
  (length (yeah-session-project session)))

(provide 'yeah-compact)
;;; yeah-compact.el ends here