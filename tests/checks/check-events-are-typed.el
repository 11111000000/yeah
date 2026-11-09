;;; check-events-are-typed.el --- canary for the event vocabulary -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The log is the stream of the run: what was asked, what the rules
;; answered, what the tool did, what the model said. Every record of it
;; is one of the declared events, and it carries the fields its type
;; declares — otherwise the log is a trace that only its writer can read.
;;
;; The check runs a turn against a fake model and then reads the log: the
;; vocabulary and the writer are compared against each other, and an
;; event of an unknown type, or with the wrong fields, must be refused.
;;
;; Exit codes: 0 — the vocabulary and the log agree; 1 — they do not.

;;; Code:

(require 'yeah-events)
(require 'yeah-turn)
(require 'yeah-tools)
(require 'yeah-perm)
(require 'yeah-session)

(defun yeah-check--records (root name)
  "Return the records of the log of session NAME under ROOT."
  (with-temp-buffer
    (insert-file-contents (expand-file-name (format "sessions/%s.jsonl" name) root))
    (mapcar (lambda (line) (json-parse-string line :object-type 'plist))
            (split-string (buffer-string) "\n" t))))

(defun yeah-check--keys (plist)
  "Return the keys of the plist PLIST, in the order they are in."
  (let ((keys nil) (rest plist))
    (while rest
      (setq keys (cons (car rest) keys))
      (setq rest (cddr rest)))
    (nreverse keys)))

(defun yeah-check--types (records)
  "Return the type of every record in RECORDS."
  (mapcar (lambda (record) (plist-get record :type)) records))

(let ((failures nil)
      (ran (list nil))
      (asked 0))

  ;; --- a turn, and the log it leaves ------------------------------------
  (let* ((root (make-temp-file "yeah-events-check" t))
         (session (yeah-session-open "events" root)))
    (yeah-tools-reset-for-test)
    (yeah-perm-rules-reset-for-test)
    (yeah-tools-register
     (list :name "probe"
           :description "A tool that records that it ran."
           :input (list (list :name "path" :type 'string))
           :handler (lambda (path)
                      (setf (car ran) path)
                      (format "probe ran on %s" path))))
    (yeah-perm-rules-add (yeah-perm-rule-make "probe" "*" 'allow))
    (let* ((transport
            (lambda (prompt callback)
              (setq asked (1+ asked))
              (if (= asked 1)
                  (funcall callback
                           (list 'tool-call
                                 (list (list :name "probe")
                                       (list "/tmp/probe-target")
                                       (lambda (value)
                                         (funcall callback
                                                  (format "done: %s" value))))))
                (funcall callback "the model is done"))))
           (turn (yeah-turn-run session "do the thing" transport))
           (records (yeah-check--records root "events")))
      (unless (equal (car ran) "/tmp/probe-target")
        (push "the tool did not run" failures))
      (unless (equal (yeah-check--types records)
                     '("header" "user-message" "tool-request"
                       "permission-request" "permission-decision"
                       "tool-end" "assistant-message"))
        (push (format "the log holds the wrong events: %S"
                      (yeah-check--types records))
              failures))
      ;; Every record is a declared event, and it carries the fields its
      ;; type declares.
      (dolist (record records)
        (let* ((type (plist-get record :type))
               (spec (yeah-events-spec type)))
          (unless spec
            (push (format "the log holds an event of an unknown type: %S" type)
                  failures))
          (when spec
            (let ((declared (plist-get spec :fields))
                  (given (delq :id (delq :type (yeah-check--keys record)))))
              (unless (equal (sort (copy-sequence declared) #'string<)
                             (sort (copy-sequence given) #'string<))
                (push (format "the event %S declares %S and was given %S"
                              type declared given)
                      failures))))))
      ;; An event of an unknown type is refused.
      (condition-case nil
          (progn
            (yeah-events-write session "no-such-event" :payload "x")
            (push "an event of an unknown type was accepted" failures))
        (user-error nil))
      ;; An event with the wrong fields is refused.
      (condition-case nil
          (progn
            (yeah-events-write session "user-message" :payload "x" :extra "y")
            (push "an event with fields it does not declare was accepted" failures))
        (user-error nil)))
    (ignore-errors (delete-directory root t t)))

  (dolist (failure failures)
    (message "events: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-events-are-typed.el ends here
