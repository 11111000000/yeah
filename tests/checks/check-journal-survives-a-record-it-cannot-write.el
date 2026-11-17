;;; check-journal-survives-a-record-it-cannot-write.el --- the journal never refuses -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The journal is append-only, and a record of a run is written by the
;; harness on the way of the run.  A record can hold a value that JSON
;; cannot write: a symbol, a character, a cons that is not a list of
;; pairs.  Such a record must not take the run down with it: the journal
;; writes a stand-in that says the record could not be written, and the
;; run goes on.
;;
;; The check also proves that the journal is still writable after such a
;; record: a stand-in that ends the journal would be no better than a
;; refusal.
;;
;; Exit codes: 0 — the journal writes what it cannot write and goes on;
;; 1 — it refuses and the run would die.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-session)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--expect (ok message)
  "Record MESSAGE as a failure when OK is nil."
  (unless ok
    (push message yeah-check--failures)))

(defun yeah-check--unwritable-record ()
  "Return a record that JSON cannot write: its payload is a symbol."
  (list :type "tool-end" :payload 'a-symbol-that-json-cannot-write))

(defun yeah-check--readable-p (line)
  "Return non-nil when LINE is a JSON object that the journal can hold."
  (condition-case nil
      (let ((record (json-parse-string line :object-type 'plist
                                        :array-type 'list)))
        (and (consp record) (stringp (plist-get record :type))))
    (error nil)))

(let* ((root (make-temp-file "yeah-journal-survives" t))
       (session (yeah-session-open "survives" root))
       (path (plist-get session :path)))
  (unwind-protect
      (progn
        ;; 1. The serializer does not raise.
        (let ((outcome (condition-case err
                            (list :ok (yeah-session--serialize
                                       (yeah-check--unwritable-record)))
                          (error (list :error err)))))
          (yeah-check--expect
           (null (plist-get outcome :error))
           (format "the journal refused to serialize a record: %S"
                   (plist-get outcome :error)))
          (let ((line (plist-get outcome :ok)))
            (yeah-check--expect
             (and (stringp line) (yeah-check--readable-p line))
             "the journal did not write a readable stand-in for the record")
            (when (and (stringp line) (yeah-check--readable-p line))
              (let ((record (json-parse-string line :object-type 'plist
                                                :array-type 'list)))
                (yeah-check--expect
                 (plist-get record :unserializable)
                 "the stand-in does not say that the record could not be written")))))
        ;; 2. The journal writes such a record and stays open.
        (let ((outcome (condition-case err
                            (list :ok (yeah-session-append
                                       session
                                       (yeah-check--unwritable-record)))
                          (error (list :error err)))))
          (yeah-check--expect
           (null (plist-get outcome :error))
           (format "the journal refused to write a record: %S"
                   (plist-get outcome :error))))
        ;; 3. The journal still takes the records that follow.
        (let ((outcome (condition-case err
                            (list :ok (yeah-session-append
                                       session
                                       (list :type "tool-end"
                                             :payload "a normal record")))
                          (error (list :error err)))))
          (yeah-check--expect
           (null (plist-get outcome :error))
           (format "the journal stopped taking records: %S"
                   (plist-get outcome :error))))
        ;; 4. Every line of the journal is readable.
        (when (file-exists-p path)
          (with-temp-buffer
            (insert-file-contents path)
            (let ((lines (split-string (buffer-string) "\n" t)))
              (yeah-check--expect
               (cl-every #'yeah-check--readable-p lines)
               "the journal holds a line that cannot be read back")))))
    (ignore-errors (delete-directory root t t))
    (dolist (failure yeah-check--failures)
      (message "journal-survives: %s" failure))
    (if yeah-check--failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-journal-survives-a-record-it-cannot-write.el ends here
