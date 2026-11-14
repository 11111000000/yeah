;;; yeah-sessions.el --- the sessions of a project -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A log of a run is a file. A project has many of them, and a person
;; needs three things about them: which ones there are, what any of them
;; cost, and what happens when a run is continued from a point other than
;; the end.
;;
;; The tree is the honest answer to the third. A session is not a line
;; but a path: to continue from an earlier point is to take the path that
;; ends there and to let the rest of the line be the path that was
;; abandoned. Nothing is deleted — the abandoned path is still in the log
;; — and the branch is what the next appends build on.

;;; Code:

(require 'cl-lib)
(require 'yeah-session)
(require 'yeah-ui)

(defun yeah-sessions--records-of (file)
  "Return the records of the log FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (mapcar (lambda (line) (json-parse-string line :object-type 'plist))
            (split-string (buffer-string) "\n" t))))

(defun yeah-sessions--cost-from-usage (usage)
  "Return the session cost corresponding to view USAGE.
Reported values remain nil when the provider supplied none.  :total is the
legacy aggregate of the values that are known plus the separate estimate."
  (let ((input (plist-get usage :input))
        (output (plist-get usage :output))
        (reported-p (plist-get usage :reported-p))
        (estimated (plist-get usage :estimated)))
    (list :reported-input input
          :reported-output output
          :reported-p reported-p
          :estimated estimated
          :total (when (or reported-p (and estimated (> estimated 0)))
                   (+ (or input 0) (or output 0) (or estimated 0))))))

(defun yeah-sessions-cost (records)
  "Return what the run RECORDS cost.
:reported-input and :reported-output contain only provider-reported totals and
are nil when unknown.  :reported-p records whether either value was reported.
:estimated is a separate record-text estimate.  The legacy :total key combines
known values and the estimate; consumers that must distinguish evidence from a
heuristic use the other fields instead."
  (yeah-sessions--cost-from-usage (plist-get (yeah-ui-view records) :usage)))

(defun yeah-sessions-index (root)
  "Return the sessions under ROOT, ordered by session id.
Each entry preserves :id, :records and :cost, and adds :mtime (the file
modification time), :title, :last-status (the projected state), :model,
:placement and :profile.  :status aliases :last-status for session-list
callers.  This is a full-scan projection of the JSONL journals, not a derived
second source of truth."
  (let ((dir (expand-file-name "sessions" root))
        (result nil))
    (when (file-directory-p dir)
      (dolist (file (directory-files dir t "\\.jsonl\\'"))
        (let* ((id (file-name-base file))
               (records (yeah-sessions--records-of file))
               (view (yeah-ui-view records))
               (session (plist-get view :session))
               (state (plist-get (plist-get view :status) :state))
               (cost (yeah-sessions--cost-from-usage (plist-get view :usage)))
               (mtime (file-attribute-modification-time (file-attributes file))))
          (push (list :id id
                      :records (length records)
                      :cost cost
                      :mtime mtime
                      :title (plist-get session :title)
                      :last-status state
                      :status state
                      :model (plist-get session :model)
                      :placement (plist-get session :placement)
                      :profile (plist-get session :profile))
                result))))
    (sort result (lambda (a b) (string< (plist-get a :id) (plist-get b :id))))))

(defun yeah-sessions-branch (records at)
  "Return the branch of RECORDS that ends at the record AT.
AT is the identifier of a record. The records after it are the path that
was abandoned: they are kept, and they are reported as the branch that
was left, so that nothing disappears and the choice is visible."
  (let ((path nil)
        (abandoned nil)
        (seen nil))
    (dolist (record records)
      (if seen
          (push record abandoned)
        (push record path))
      (when (and (null seen) (equal (plist-get record :id) at))
        (setq seen t)))
    (list :path (nreverse path)
          :abandoned (nreverse abandoned))))

(provide 'yeah-sessions)
;;; yeah-sessions.el ends here
