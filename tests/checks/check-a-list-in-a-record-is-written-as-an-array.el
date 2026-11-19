;;; check-a-list-in-a-record-is-written-as-an-array.el --- the journal keeps a record that holds a list -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The journal is JSONL, and `json-serialize' writes a list as an object or
;; refuses it: a list of names is not a shape it can write.  A record that
;; held such a list was therefore written as a stand-in that said the journal
;; could not write it, and the record itself was lost.  A live run of the
;; orchestrator showed the shape: the record of a queued input holds the
;; names of the MCP servers of the session, and the record became a stand-in.
;;
;; The rule of the kernel: a list in a record is written as an array, and the
;; record keeps everything else.  The reader of a JSON array gives a vector
;; back -- the same rule the tasks of a todo event follow.
;;
;; The check proves three things: a record that holds a list is written with
;; the list as an array and is not a stand-in; the journal file holds the
;; whole record; and the record of a queued input whose frozen configuration
;; names MCP servers -- the shape the live run lost -- holds the whole record.
;;
;; Exit codes: 0 — the journal keeps a record that holds a list;
;; 1 — the record was lost to a stand-in.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-session)
(require 'yeah-control)
(require 'yeah-input)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--expect (ok message)
  "Record MESSAGE as a failure when OK is nil."
  (unless ok
    (push message yeah-check--failures)))

(defun yeah-check--record-with-a-list ()
  "Return a record whose frozen configuration holds a list of names."
  (list :type "input-queued"
        :input_id "input-1"
        :input_kind "ask"
        :prompt "the prompt"
        :frozen (list :cwd "/tmp" :mcp-servers (list "paseo" "another"))))

(defun yeah-check--read (line)
  "Parse LINE the way the journal reads it: a plist, arrays as vectors."
  (condition-case nil
      (json-parse-string line :object-type 'plist)
    (error nil)))

(defun yeah-check--lines (path)
  "Return the lines of the journal file at PATH."
  (with-temp-buffer
    (insert-file-contents path)
    (split-string (buffer-string) "\n" t)))

(defun yeah-check--stand-in-p (record)
  "Return non-nil when RECORD is a stand-in that says it could not be written."
  (and (consp record) (plist-get record :unserializable)))

(defun yeah-check--the-serialized-record ()
  "Check the record the serializer writes when the record holds a list."
  (let* ((line (yeah-session--serialize (yeah-check--record-with-a-list)))
         (record (yeah-check--read line)))
    (yeah-check--expect (stringp line)
                        "the journal wrote no line for a record that holds a list")
    (yeah-check--expect (not (yeah-check--stand-in-p record))
                        "the journal wrote a stand-in instead of the record that holds a list")
    (yeah-check--expect (equal (plist-get record :input_id) "input-1")
                        "the journal lost the field of the record that holds a list")
    (let ((frozen (plist-get record :frozen)))
      (yeah-check--expect (equal (plist-get frozen :cwd) "/tmp")
                          "the journal lost the frozen configuration of the record")
      (yeah-check--expect (equal (plist-get frozen :mcp-servers) ["paseo" "another"])
                          (format "the list of the record was not written as an array: %S"
                                  (plist-get frozen :mcp-servers))))))

(defun yeah-check--the-journal-file ()
  "Check that the journal file holds the record that holds a list."
  (let* ((root (make-temp-file "yeah-journal-list" t))
         (session (yeah-session-open "list" root))
         (path (plist-get session :path)))
    (unwind-protect
        (progn
          (yeah-session-append session (yeah-check--record-with-a-list))
          (dolist (line (yeah-check--lines path))
            (let ((record (yeah-check--read line)))
              (yeah-check--expect (not (yeah-check--stand-in-p record))
                                  "the journal file holds a stand-in instead of the record that holds a list"))))
      (ignore-errors (delete-directory root t t)))))

(defun yeah-check--the-queued-input ()
  "Check the record of a queued input whose frozen configuration names MCP servers.
This is the shape the live run of the orchestrator lost: the frozen
configuration of the session holds the names of its MCP servers, and the
record of the queued input held them."
  (let* ((root (make-temp-file "yeah-control-list" t))
         (yeah-input-directory root)
         (session (yeah-session-open "control-list" root))
         (control (yeah-control-new
                   session
                   (lambda (_prompt _callback) nil)
                   nil 60000 0
                   (list :cwd "/tmp" :mcp-servers (list "paseo")))))
    (unwind-protect
        (progn
          (yeah-control-submit control "the prompt")
          (let* ((lines (yeah-check--lines (plist-get session :path)))
                 (queued (cl-find-if
                          (lambda (line)
                            (equal "input-queued" (plist-get (yeah-check--read line) :type)))
                          lines)))
            (yeah-check--expect queued
                                "the journal holds no record of the queued input")
            (when queued
              (let ((record (yeah-check--read queued)))
                (yeah-check--expect (not (yeah-check--stand-in-p record))
                                    "the record of the queued input is a stand-in: the names of the MCP servers were lost")
                (let ((frozen (plist-get record :frozen)))
                  (yeah-check--expect (equal (plist-get frozen :mcp-servers) ["paseo"])
                                      (format "the names of the MCP servers were not written as an array: %S"
                                              (plist-get frozen :mcp-servers))))))))
      (ignore-errors (delete-directory root t t)))))

(yeah-check--the-serialized-record)
(yeah-check--the-journal-file)
(yeah-check--the-queued-input)

(dolist (failure yeah-check--failures)
  (message "journal-list: %s" failure))
(if yeah-check--failures
    (kill-emacs 1)
  (kill-emacs 0))

;;; check-a-list-in-a-record-is-written-as-an-array.el ends here
