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
;; The session log is the durable, append-only record of an agent
;; conversation and the source for projections described in
;; `docs/ARCHITECTURE.md'.  The on-disk format is one JSONL record per line.
;; Records carry monotonic integer ids used for compaction cut-points.
;;
;; Public operations open/close sessions, append and read records, build a
;; compacted projection, record compaction and test whether a session is
;; idle.  Destructive delete/rewrite operations deliberately do not exist.
;;
;; The file of a session appears when the session writes its first record, and
;; not when the session is opened: a session that never did anything leaves no
;; file behind, and the journal of a project stays readable.  The orchestrator
;; opens a session to read the catalog of the models and never runs anything in
;; it (wave 67).

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-text)

(defgroup yeah-session nil
  "Yeah append-only session log."
  :group 'yeah)

(defconst yeah-session-schema-version 1
  "Schema version written in every newly appended journal record.")

(defcustom yeah-session-journal-from-the-start nil
  "Write the file of a session when the session opens, and not when it writes.
The journal of a session holds its header and its records, and it appears when
the session writes its first record: a session that never did anything leaves
no file behind.  A person who wants to see a session in the list of the
sessions of the project before it did anything sets this to non-nil, and every
session has its file from the start."
  :type 'boolean
  :group 'yeah-session)

(defcustom yeah-session--root nil
  "Override the root below which `sessions/<id>.jsonl' is stored.
When nil, sessions are stored below `default-directory'.  Tests can use a
request-local binding or set this explicitly for a test session."
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

(defun yeah-session--plist-p (value)
  "Return non-nil when VALUE is a proper plist with symbol keys."
  (and (consp value)
       (proper-list-p value)
       (zerop (% (length value) 2))
       (cl-loop for tail on value by #'cddr
                always (symbolp (car tail)))))

(defun yeah-session--alist-p (value)
  "Return non-nil when VALUE is an alist of pairs with symbol keys.
A plist is an alist as well; the caller asks about the plist first."
  (and (consp value)
       (proper-list-p value)
       (cl-every (lambda (cell) (and (consp cell) (symbolp (car cell))))
                 value)))

(defun yeah-session--json-value (value)
  "Return VALUE in a shape that `json-serialize' can write.
The journal is JSONL: a list is written as an array, and the reader of a
JSON array gives a vector back -- the same rule the tasks of a todo event
follow.  A plist and an alist are objects, and they keep their shape.
A value that JSON cannot hold at all (a symbol, a cons that is not a list)
is returned as it is: the writer of the journal decides what to do with it."
  (cond
   ((yeah-session--plist-p value)
    (let (result)
      (while value
        (push (car value) result)
        (push (yeah-session--json-value (cadr value)) result)
        (setq value (cddr value)))
      (nreverse result)))
   ((yeah-session--alist-p value)
    (mapcar (lambda (cell) (cons (car cell) (yeah-session--json-value (cdr cell))))
            value))
   ((and (consp value) (proper-list-p value))
    (vconcat (mapcar #'yeah-session--json-value value)))
   ((vectorp value)
    (vconcat (mapcar #'yeah-session--json-value value)))
   (t value)))

(defun yeah-session--serialize (record)
  "Serialize RECORD (a plist) to a one-line JSON string.
Every string of the record is valid UTF-8: a tool can hand back bytes that
are not text, and a byte that is not text becomes the replacement character.
A list in the record is written as an array: the journal keeps the whole
record instead of losing it to a stand-in.
A record that JSON cannot hold at all is written as a stand-in that says so,
because the journal is append-only and the run must go on.
The `:id' field is preserved on the wire for cross-reference
by compaction records."
  (let* ((id (plist-get record :id))
         (copy record))
    (when id
      (setq copy (plist-put copy :id id)))
    (or (condition-case nil
            (json-serialize (yeah-session--json-value (yeah-text-value-valid copy)))
          (error nil))
        (json-serialize
         (append (list :type (or (plist-get record :type) "unknown"))
                 (when (integerp id) (list :id id))
                 (list :unserializable t
                       :note (format "the record holds a value that the journal cannot write: %S"
                                     (plist-get record :type))))))))

(defun yeah-session-open (session-id &optional root cwd)
  "Open (or create) the session log for SESSION-ID under ROOT.
If the file does not exist, the session is opened but its file is not
written yet: the file appears with its header when the session writes its
first record.  A session that never did anything therefore leaves no file
behind -- the orchestrator opens a session to read the catalog of the models
and never runs anything in it, and such a session must not litter the journal
of the project.  If the file does exist, the records are read into
memory; the in-memory state is the source of truth for the
returned session object. Idempotent.

CWD is the directory the work of the session happens in: the tools of
the session run there, and a relative path of a tool is counted from it.
It is nil when the session has no directory of its own.

Malformed nonempty lines are omitted from the readable records and reported
in a `:recovery' plist with `:malformed-lines', `:partial-tail' and
`:message'.  A partial tail is an unterminated malformed final nonempty
line.  Corruption emits a warning, but never rewrites the log or appends a
recovery event.  Clean logs have no `:recovery' metadata and emit no warning.

Returns a plist of shape:
  (:id ID :path PATH :records LIST :next-id N :header RECORD
   :pending-header BOOL [:cwd CWD] [:recovery RECOVERY])"
  (unless (and (stringp session-id) (> (length session-id) 0))
    (signal 'user-error
            (list (format "yeah-session-open: bad session id %S" session-id))))
  (let* ((path (yeah-session--path-for session-id root))
         (exists (file-exists-p path))
         (records nil)
         (next-id 0)
         (recovery nil)
         (header nil)
         (pending-header nil))
    (if exists
        (progn
          (let* ((text (yeah-session--read-file path))
                 (lines (yeah-session--lines text))
                 (last-line-index (1- (length lines)))
                 (unterminated (and (> (length text) 0)
                                    (not (string-suffix-p "\n" text))))
                 (malformed-lines 0)
                 (partial-tail nil))
            (cl-loop for line in lines
                     for line-index from 0
                     do (let ((rec (yeah-session--parse-line line)))
                          (if rec
                              (progn
                                (push rec records)
                                (let ((rid (plist-get rec :id)))
                                  (when (and (integerp rid) (> rid next-id))
                                    (setq next-id rid))))
                            (setq malformed-lines (1+ malformed-lines))
                            (when (and unterminated
                                       (= line-index last-line-index))
                              (setq partial-tail t)))))
            (when (> malformed-lines 0)
              (let ((message
                     (format
                      "Session log %s contains %d malformed nonempty JSONL line%s%s. Valid records remain readable; the file was not modified."
                      path malformed-lines
                      (if (= malformed-lines 1) "" "s")
                      (if partial-tail
                          ", including an unterminated final line that may be truncated"
                        ""))))
                (setq recovery (list :malformed-lines malformed-lines
                                     :partial-tail partial-tail
                                     :message message))
                (display-warning 'yeah-session message :warning))))
          (setq records (nreverse records)))
      (setq header (list :type "header"
                          :schema_version yeah-session-schema-version
                          :id 0
                          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                          :session_id session-id)
            records (list header)
            next-id 0
            pending-header (not yeah-session-journal-from-the-start))
      (unless pending-header
        (yeah-session--write-line path (yeah-session--serialize header))))
    (append (list :id session-id :path path :records records
                  :next-id (1+ next-id)
                  :header header
                  :pending-header pending-header)
            (when cwd
              (list :cwd cwd))
            (when recovery
              (list :recovery recovery)))))

(defvar yeah-session--current nil
  "The session of the run that is running right now, or nil.
A tool that writes into the journal of its own run reads this binding:
the run binds the session it writes into while it dispatches the call, and
the binding is gone when the call is over.  The binding is request-local
and never leaks into another run.")

(defmacro yeah-session-with (session &rest body)
  "Evaluate BODY with SESSION as the session of the run that is running.
SESSION is evaluated once, in the scope of BODY.  A tool that acts on the
world of the run -- a delegation, a write -- reads the session through
`yeah-session-current' and writes into the journal of that run.

The tools of the run also work in the directory of the session: a relative
path of a tool is counted from the `cwd' of the session and not from the
directory of the process.  A session without a directory of its own leaves
the directory of the process alone."
  (declare (indent 0) (debug t))
  `(let* ((yeah-session--current ,session)
          (yeah-session--cwd (plist-get yeah-session--current :cwd)))
     (let ((default-directory
            (if (and (stringp yeah-session--cwd)
                     (file-directory-p yeah-session--cwd))
                (file-name-as-directory yeah-session--cwd)
              default-directory)))
       ,@body)))

(defun yeah-session-current ()
  "Return the session of the run that is running right now, or nil.
A call outside of a run has no session: there is no journal to write into,
and a tool that needs one says so instead of guessing."
  yeah-session--current)

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

(defun yeah-session--context (context)
  "Validate and normalize optional correlation CONTEXT for a new record."
  (unless (and (proper-list-p context) (zerop (% (length context) 2)))
    (signal 'user-error (list "yeah-session-append: context must be a plist")))
  (let ((allowed '(:run_id :turn_id :tool_call_id :parent_event_id))
        (normalized nil))
    (dolist (key allowed)
      (when-let ((value (plist-get context key)))
        (setq normalized (append normalized (list key value)))))
    (let ((rest context))
      (while rest
        (unless (memq (car rest) allowed)
          (signal 'user-error
                  (list (format "yeah-session-append: unknown context field %S"
                                (car rest)))))
        (setq rest (cddr rest))))
    normalized))

(defun yeah-session--flush-header (session)
  "Write the header of SESSION to disk when the session has not written it yet.
The header is the first line of the file and the file is created by it: a
session that writes nothing leaves no file behind.  A file that exists
already is left alone -- another writer has created it, and a second header
would be a lie."
  (when (plist-get session :pending-header)
    (let ((path (plist-get session :path)))
      (unless (file-exists-p path)
        (yeah-session--write-line
         path (yeah-session--serialize (plist-get session :header))))
    (plist-put session :pending-header nil))))

(defun yeah-session-append (session record &optional context)
  "Append RECORD to SESSION with a fresh common envelope.
CONTEXT may contain `:run_id', `:turn_id', `:tool_call_id' and
`:parent_event_id'.  Existing records are never rewritten.  Return the new
monotonic integer id."
  (unless (and (consp session) (plist-get session :path))
    (signal 'user-error
            (list (format "yeah-session-append: not a session %S" session))))
  (unless (and (consp record) (stringp (plist-get record :type)))
    (signal 'user-error
            (list (format "yeah-session-append: record missing :type %S" record))))
  (yeah-session--flush-header session)
  (let* ((path (plist-get session :path))
         (next (yeah-session--next-id (plist-get session :records)))
         (metadata (yeah-session--context context))
         (with-id (plist-put (copy-sequence record) :id next)))
    (setq with-id (plist-put with-id :schema_version yeah-session-schema-version))
    (setq with-id (plist-put with-id :session_id (plist-get session :id)))
    (unless (plist-member with-id :timestamp)
      (setq with-id
            (plist-put with-id :timestamp
                       (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))
    (dolist (key '(:run_id :turn_id :tool_call_id :parent_event_id))
      (when (plist-member metadata key)
        (setq with-id (plist-put with-id key (plist-get metadata key)))))
    (yeah-session--write-line path (yeah-session--serialize with-id))
    (plist-put session :records (append (plist-get session :records)
                                        (list with-id)))
    (plist-put session :next-id (1+ next))
    next))

(defun yeah-session-records (session)
  "Return the list of all records in SESSION, in append order.
Read-only: the returned list is the live cell structure of
the session, but `yeah-session' only ever appends to it."
  (unless (and (consp session) (plist-get session :path))
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

(defun yeah-session-record-fields (record)
  "Return RECORD's payload and correlation fields, excluding type and schema.
Correlation remains visible to the placement projection's volatile-field
filter; the constant schema version does not change semantic event equality."
  (let ((rest record)
        (fields nil))
    (while rest
      (when (eq (car rest) :type)
        (setq rest (cddr rest))
        (while rest
          (unless (eq (car rest) :schema_version)
            (setq fields (append fields (list (car rest) (cadr rest)))))
          (setq rest (cddr rest))))
      (when rest
        (setq rest (cddr rest))))
    fields))

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