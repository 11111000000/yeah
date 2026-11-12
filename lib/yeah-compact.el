;;; yeah-compact.el --- compaction over the session journal -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Compaction appends a summary record; source events are never deleted.
;; `yeah-compact-run-async' is the production API: the summary arrives through
;; a callback and only a complete nonblank answer is committed.  The older
;; `yeah-compact-run' remains useful with synchronous test summarizers.

;;; Code:

(require 'cl-lib)
(require 'yeah-session)
(require 'yeah-context)

(defgroup yeah-compact nil
  "Yeah compaction over the append-only session journal."
  :group 'yeah)

(defun yeah-compact-cut-point (session target-chars)
  "Return the first record id whose cumulative printed length crosses TARGET-CHARS.
Return nil when SESSION fits the target.  TARGET-CHARS must be nonnegative."
  (unless (and (consp session) (plist-get session :records))
    (signal 'user-error (list (format "yeah-compact-cut-point: not a session %S"
                                      session))))
  (unless (and (integerp target-chars) (>= target-chars 0))
    (signal 'user-error
            (list (format "yeah-compact-cut-point: invalid target %S"
                          target-chars))))
  (let ((running 0)
        (result nil))
    (dolist (record (yeah-session-records session))
      (setq running (+ running (length (prin1-to-string record))))
      (when (and (null result) (> running target-chars))
        (setq result (plist-get record :id))))
    result))

(defun yeah-compact--before (session cut-point)
  "Return SESSION records with ids strictly below CUT-POINT."
  (cl-remove-if-not
   (lambda (record)
     (let ((id (plist-get record :id)))
       (and (integerp id) (< id cut-point))))
   (yeah-session-records session)))

(defun yeah-compact-summarize (session cut-point &optional summarizer)
  "Summarize SESSION records before CUT-POINT with SUMMARIZER.
The default summarizer is the nonblocking-when-possible compatibility wrapper
around `yeah-context-summarize'.  Use `yeah-compact-run-async' for gptel."
  (unless (integerp cut-point)
    (signal 'user-error (list "yeah-compact-summarize: invalid cut-point")))
  (let ((summarizer (or summarizer
                        (lambda (records)
                          (yeah-context-summarize
                           (mapconcat (lambda (record) (format "%S" record))
                                      records "\n"))))))
    (funcall summarizer (yeah-compact--before session cut-point))))

(defun yeah-compact--result (session cut summary &optional error)
  "Return a compaction result for SESSION, CUT, SUMMARY and optional ERROR."
  (list :cut-point cut
        :summary summary
        :error error
        :projection-count (length (yeah-session-project session))))

(defun yeah-compact-run (session target-chars &optional summarizer)
  "Compact SESSION synchronously when SUMMARIZER answers immediately.
This function never pumps the event loop.  If no SUMMARIZER is supplied and
the model responds asynchronously, it signals `user-error'; use
`yeah-compact-run-async' in production."
  (let ((cut (yeah-compact-cut-point session target-chars)))
    (if (null cut)
        (yeah-compact--result session nil nil)
      (let ((summary (yeah-compact-summarize session cut summarizer)))
        (unless (and (stringp summary) (not (string-blank-p summary)))
          (signal 'user-error
                  (list "yeah-compact-run: summary is empty or asynchronous")))
        (yeah-session-record-compaction
         session (list :cut-point cut :summary summary))
        (yeah-compact--result session cut summary)))))

(defun yeah-compact-run-async (session target-chars transport callback
                                        &optional live-p)
  "Compact SESSION with TRANSPORT and deliver the outcome to CALLBACK.
TRANSPORT may be nil to use gptel or the configured test transport.  CALLBACK
receives (RESULT INFO).  A failed or blank summary leaves the journal unchanged
and produces a result with an :error field; no empty summary is committed.
When optional LIVE-P is non-nil, it is called before committing and can cancel
late compaction without modifying the journal."
  (unless (functionp callback)
    (signal 'user-error (list "yeah-compact-run-async: invalid callback")))
  (let ((cut (yeah-compact-cut-point session target-chars)))
    (if (null cut)
        (funcall callback (yeah-compact--result session nil nil) nil)
      (yeah-context-summarize-async
       (mapconcat (lambda (record) (format "%S" record))
                  (yeah-compact--before session cut) "\n")
       transport
       (lambda (summary info)
         (cond
          ((and live-p (not (funcall live-p)))
           (funcall callback
                    (yeah-compact--result session cut nil "cancelled")
                    info))
          ((not summary)
           (funcall callback
                    (yeah-compact--result
                     session cut nil
                     (format "compaction failed: %S" info))
                    info))
          (t
           (yeah-session-record-compaction
            session (list :cut-point cut :summary summary))
           (funcall callback
                    (yeah-compact--result session cut summary)
                    info))))))))

(defun yeah-compact-projection-length (session)
  "Return the number of records in SESSION's current projection."
  (length (yeah-session-project session)))

(provide 'yeah-compact)
;;; yeah-compact.el ends here
