;;; check-an-error-record-is-bounded.el --- the journal holds records, not conversations -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A run that stops for a reason writes that reason into the journal.  A
;; provider that refused a request hands back the whole conversation of
;; the run inside the refusal, and the journal must not keep a copy of
;; the conversation: one record of the journal is a record, not a
;; transcript.
;;
;; The reason that goes into the journal is bounded, and it names the
;; cause: the beginning of the reason is kept, and the place where the
;; text was cut is said.
;;
;; Exit codes: 0 — the record of the error is bounded and names the
;; cause; 1 — it is not.

;;; Code:

(require 'cl-lib)
(require 'yeah-turn)
(require 'yeah-session)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defconst yeah-check--limit 4000
  "The largest error record that the journal may hold.")

(defun yeah-check--expect (ok message)
  "Record MESSAGE as a failure when OK is nil."
  (unless ok
    (push message yeah-check--failures)))

(defun yeah-check--error-record (session reason)
  "Write REASON into SESSION as the failure of a run and return the record.
The record of the failure that was just written is the newest one."
  (let ((turn (yeah-turn--make :session session :budget 100 :id "run-1")))
    (yeah-turn--fail turn reason)
    (cl-reduce (lambda (found record)
                 (if (equal "error" (plist-get record :type)) record found))
               (yeah-session-records session)
               :initial-value nil
               :from-end t)))

(let* ((root (make-temp-file "yeah-error-bounded" t))
       (session (yeah-session-open "bounded" root)))
  (unwind-protect
      (progn
        ;; 1. A reason that is a long text.
        (let* ((cause "the provider refused the request: HTTP 529")
               (reason (concat cause ": " (make-string 200000 ?x)))
               (record (yeah-check--error-record session reason))
               (payload (plist-get record :payload)))
          (yeah-check--expect
           record
           "the journal holds no record of the failure")
          (yeah-check--expect
           (and payload (stringp payload))
           "the record of the failure holds no text")
          (when (and payload (stringp payload))
            (yeah-check--expect
             (< (length payload) yeah-check--limit)
             (format "the record of the failure is not bounded: %d characters"
                     (length payload)))
            (yeah-check--expect
             (string-match-p "the provider refused the request" payload)
             "the record of the failure does not name the cause")
            (yeah-check--expect
             (string-match-p "characters more" payload)
             "the record of the failure does not say where the text was cut")))
        ;; 2. A reason that is a refusal with a whole conversation in it.
        (let* ((reason (list :status "rate-limited"
                              :http-status 529
                              :error (concat "the conversation of the run: "
                                              (make-string 200000 ?y))))
               (record (yeah-check--error-record session reason))
               (payload (plist-get record :payload)))
          (yeah-check--expect
           record
           "the journal holds no record of the failure")
          (yeah-check--expect
           (and payload (stringp payload))
           "the record of the failure holds no text")
          (when (and payload (stringp payload))
            (yeah-check--expect
             (< (length payload) yeah-check--limit)
             (format "the record of the failure is not bounded: %d characters"
                     (length payload)))
            (yeah-check--expect
             (string-match-p "the conversation of the run" payload)
             "the record of the failure does not name the cause")))
        ;; 3. The journal itself holds no conversation.
        (let ((path (plist-get session :path)))
          (when (file-exists-p path)
            (let ((size (with-temp-buffer
                          (insert-file-contents path)
                          (string-bytes (buffer-string)))))
              (yeah-check--expect
               (< size (* 8 yeah-check--limit))
               (format "the journal grew to %d bytes over two failures" size))))))
    (ignore-errors (delete-directory root t t))
    (dolist (failure yeah-check--failures)
      (message "error-bounded: %s" failure))
    (if yeah-check--failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-an-error-record-is-bounded.el ends here
