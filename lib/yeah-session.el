;;; yeah-session.el --- append-only JSONL session log -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The session log is the durable, append-only record of an
;; agent conversation. See `decisions/append-only-session-log@0'
;; for the contract and `decisions/session-impl@0' for the
;; shape. The on-disk format is one JSONL record per line; the
;; first line is always a `header' record; later lines are
;; `message', `tool-call', `tool-result', or `compaction'
;; records. Records carry a monotonic integer id; the id is
;; the only handle for compaction cut-points.
;;
;; The public API is exactly seven functions:
;;
;;   * `yeah-session-open'                 -- open or create the log
;;   * `yeah-session-close'                -- release the buffer handle
;;   * `yeah-session-append'               -- write a new record
;;   * `yeah-session-records'              -- list all records (read-only)
;;   * `yeah-session-project'              -- compacted projection
;;   * `yeah-session-record-compaction'    -- write a compaction record
;;   * `yeah-session-idle-p'               -- session is at the header
;;
;; The functions `yeah-session-delete' and `yeah-session-rewrite'
;; are deliberately *not* defined. The negative fixture and the
;; ERT case `yeah-session-no-delete-or-rewrite-api' assert this.

;;; Code:

(require 'cl-lib)
(require 'json)

(defgroup yeah-session nil
  "Yeah append-only session log."
  :group 'yeah)

(defcustom yeah-session--root nil
  "Override the default Yeah root for the session log directory.
When nil, the directory holding `lib/yeah-session.el' is used
as the default root in tests, and `default-directory' is used
otherwise. Rebind with `setq', not `let'."
  :type '(choice (const nil) directory)
  :group 'yeah-session)

(defun yeah-session--default-root ()
  "Return the directory under which `sessions/<id>.jsonl' lives."
  (let ((root yeah-session--root))
    (or root default-directory)))

(defun yeah-session--path-for (session-id &optional root)
  "Return the absolute path to the JSONL log for SESSION-ID under ROOT."
  (let* ((base (or root (yeah-session--default-root)))
         (dir  (expand-file-name "sessions" base))
         (file (expand-file-name (concat session-id ".jsonl") dir)))
    (make-directory dir t)
    file))

(defun yeah-session--read-file (path)
  "Read PATH, returning its contents as a string."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents path)
      (buffer-string))))

(defun yeah-session--lines (text)
  "Split TEXT on newlines and return a list of non-empty lines."
  (let ((lines (split-string text "\n" t)))
    lines))

(defun yeah-session--parse-line (line)
  "Parse a single JSONL LINE into a record plist with `:id'.
Returns nil if LINE is blank or unparseable."
  (unless (or (null line) (string= line ""))
    (condition-case nil
        (let* ((obj (json-parse-string line :object-type 'plist
                                                 :null-object nil
                                                 :false-object nil))
               (id  (or (plist-get obj :id) 0)))
          (plist-put obj :id id))
      (error nil))))

(defun yeah-session--write-line (path line)
  "Append LINE (plus newline) to the JSONL file at PATH.
Creates the file if it does not exist. Caller is responsible
for uniqueness; this is the lowest-level mutation primitive."
  (let ((coding-system-for-write 'utf-8))
    (with-temp-buffer
      (insert line "\n")
      (write-region (point-min) (point-max) path 'append 'no-message))))

(defun yeah-session--serialize (record)
  "Serialize RECORD (a plist) to a one-line JSON string.
The `:id' field is preserved on the wire for cross-reference
by compaction records."
  (let* ((id (plist-get record :id))
         (copy record))
    (when id
      (setq copy (plist-put copy :id id)))
    (json-serialize copy)))

(defun yeah-session-open (session-id &optional root)
  "Open (or create) the session log for SESSION-ID under ROOT.
If the file does not exist, it is created with a single
`header' record. If it does exist, the records are read into
memory; the in-memory state is the source of truth for the
returned session object. Idempotent.

Returns a plist of shape:
  (:id ID :path PATH :records LIST :next-id N)"
  (unless (and (stringp session-id) (> (length session-id) 0))
    (signal 'user-error
            (list (format "yeah-session-open: bad session id %S" session-id))))
  (let* ((path (yeah-session--path-for session-id root))
         (exists (file-exists-p path))
         (records nil)
         (next-id 0))
    (if exists
        (progn
          (let* ((text (yeah-session--read-file path))
                 (lines (yeah-session--lines text)))
            (dolist (line lines)
              (let ((rec (yeah-session--parse-line line)))
                (when rec
                  (push rec records)
                  (let ((rid (plist-get rec :id)))
                    (when (and (integerp rid) (> rid next-id))
                      (setq next-id rid)))))))
          (setq records (nreverse records)))
      (let* ((header (list :type "header"
                           :id 0
                           :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                           :session_id session-id))
             (serialized (yeah-session--serialize header)))
        (yeah-session--write-line path serialized)
        (setq records (list header)
              next-id 0)))
    (list :id session-id :path path :records records :next-id (1+ next-id))))

(defun yeah-session-close (session)
  "Close SESSION, releasing any file handle. No record mutation."
  (unless (and (consp session) (stringp (plist-get session :id)))
    (signal 'user-error
            (list (format "yeah-session-close: not a session %S" session))))
  session)

(defun yeah-session--next-id (records)
  "Return the next monotonic id strictly greater than any id in RECORDS."
  (let ((max 0))
    (dolist (r records)
      (let ((rid (plist-get r :id)))
        (when (and (integerp rid) (> rid max))
          (setq max rid))))
    (1+ max)))

(defun yeah-session-append (session record)
  "Append RECORD (a plist `:type :timestamp :payload') to SESSION.
Writes one JSONL line, appends the parsed record (with a fresh
`:id') to `:records', and returns the new record id (an integer)."
  (unless (and (consp session) (plist-get session :path))
    (signal 'user-error
            (list (format "yeah-session-append: not a session %S" session))))
  (unless (and (consp record) (stringp (plist-get record :type)))
    (signal 'user-error
            (list (format "yeah-session-append: record missing :type %S" record))))
  (let* ((path (plist-get session :path))
         (next (yeah-session--next-id (plist-get session :records)))
         (with-id (plist-put (copy-sequence record) :id next))
         (serialized (yeah-session--serialize with-id)))
    (yeah-session--write-line path serialized)
    (plist-put session :records (append (plist-get session :records)
                                        (list with-id)))
    (plist-put session :next-id (1+ next))
    next))

(defun yeah-session-records (session)
  "Return the list of all records in SESSION, in append order.
Read-only: the returned list is the live cell structure of
the session, but `yeah-session' only ever appends to it."
  (unless (and (consp session) (plist-get session :records))
    (signal 'user-error
            (list (format "yeah-session-records: not a session %S" session))))
  (plist-get session :records))

(defun yeah-session--latest-compaction (records)
  "Return the most recent compaction record in RECORDS, or nil.
RECORDS is the in-memory record list in append order."
  (let ((latest nil))
    (dolist (r records)
      (when (string= (plist-get r :type) "compaction")
        (setq latest r)))
    latest))

(defun yeah-session-project (session)
  "Return the compacted projection of SESSION.
If no `compaction' record exists, the projection is the full
record list. If one or more compaction records exist, the
projection is the most recent compaction record followed by
the records whose `:id' is strictly greater than the most
recent compaction record's `:cut_point', excluding the
compaction record itself (which already appears as the head)."
  (let* ((records (yeah-session-records session))
         (latest  (yeah-session--latest-compaction records)))
    (if (null latest)
        records
      (let* ((cut      (plist-get latest :cut_point))
             (latest-id (plist-get latest :id))
             (tail     nil))
        (dolist (r records)
          (let ((rid (plist-get r :id)))
            (when (and (integerp rid) (> rid cut)
                       (not (eq rid latest-id)))
              (push r tail))))
        (append (list latest) (nreverse tail))))))

(defun yeah-session-record-compaction (session compaction-record)
  "Append a `compaction' record to SESSION.
COMPACTION-RECORD is a plist `:cut-point ID :summary STRING'.
The compaction record carries `:type \"compaction\"' on the
wire. Source records are not modified."
  (unless (and (consp compaction-record)
               (integerp (plist-get compaction-record :cut-point))
               (stringp (plist-get compaction-record :summary)))
    (signal 'user-error
            (list (format "yeah-session-record-compaction: bad compaction record %S"
                          compaction-record))))
  (let* ((timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))
         (wire (list :type "compaction"
                     :cut_point (plist-get compaction-record :cut-point)
                     :summary   (plist-get compaction-record :summary)
                     :timestamp timestamp)))
    (yeah-session-append session wire)))

(defun yeah-session-idle-p (session)
  "Non-nil if SESSION has no records, or only a header record."
  (let ((records (and (consp session) (plist-get session :records))))
    (or (null records)
        (and (= (length records) 1)
             (string= (plist-get (nth 0 records) :type) "header")))))

(provide 'yeah-session)
;;; yeah-session.el ends here