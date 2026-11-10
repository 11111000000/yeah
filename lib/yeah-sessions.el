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

(defun yeah-sessions--records-of (file)
  "Return the records of the log FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (mapcar (lambda (line) (json-parse-string line :object-type 'plist))
            (split-string (buffer-string) "\n" t))))

(defun yeah-sessions--estimated-tokens (record)
  "Return the number of tokens the RECORD is worth, estimated."
  (max 1 (ceiling (/ (length (format "%S" record)) 4.0))))

(defun yeah-sessions-cost (records)
  "Return what the run RECORDS cost: a plist of the tokens.
The tokens the provider reported are counted as they are; the rest is
estimated from the text of the records, because a run must be able to
say what it cost even when the provider said nothing."
  (let ((reported-input 0)
        (reported-output 0)
        (estimated 0))
    (dolist (record records)
      (if (equal (plist-get record :type) "usage")
          (progn
            (setq reported-input (+ reported-input (or (plist-get record :input) 0)))
            (setq reported-output (+ reported-output (or (plist-get record :output) 0))))
        (setq estimated (+ estimated (yeah-sessions--estimated-tokens record)))))
    (list :reported-input reported-input
          :reported-output reported-output
          :estimated estimated
          :total (+ reported-input reported-output estimated))))

(defun yeah-sessions-index (root)
  "Return the sessions under ROOT: a list of plists.
Each is `(:id ID :records N :cost COST)', and the list is ordered by
the identifier of the session."
  (let ((dir (expand-file-name "sessions" root))
        (result nil))
    (when (file-directory-p dir)
      (dolist (file (directory-files dir t "\\.jsonl\\'"))
        (let* ((id (file-name-base file))
               (records (yeah-sessions--records-of file)))
          (push (list :id id
                      :records (length records)
                      :cost (yeah-sessions-cost records))
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
