;;; check-model-turn-runs.el --- canary for the turn -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The turn asks the model, takes the tool calls the model asked for, runs
;; them through the permission system and the registry, writes what
;; happened into the append-only log, and asks the model again until it
;; asks for nothing.
;;
;; The model here is a FAKE: a transport that answers with the shape gptel
;; uses — one tool call first, text afterwards. No network is touched, and
;; the check is about the turn, not about the model.
;;
;; Two things are asserted: that a permitted call runs and is logged, and
;; that a call the rules refuse does NOT run and is logged as a refusal.
;;
;; Exit codes: 0 — the turn behaves; 1 — it does not.

;;; Code:

(require 'yeah-turn)
(require 'yeah-tools)
(require 'yeah-perm)
(require 'yeah-session)

(defun yeah-check--register-probe (ran)
  "Register the tool `probe', which records the PATH it ran on.
RAN is a one element cell holding the path, so that the handler and
the check see the same variable."
  (yeah-tools-register
   (list :name "probe"
         :description "A tool that records that it ran."
         :input (list (list :name "path" :type 'string))
         :handler (lambda (path)
                    (setf (car ran) path)
                    (format "probe ran on %s" path)))))

(defun yeah-check--fake-model (asked)
  "Return a transport that asks the model once and then answers.
The first answer is a tool call for `probe'; the second is text. The
result of the call is handed back to the model, as gptel does. ASKED is
a one element cell holding the number of times the model was asked."
  (lambda (prompt callback)
    (setf (car asked) (1+ (car asked)))
    (if (= (car asked) 1)
        (funcall callback
                 (list 'tool-call
                       (list (list :name "probe")
                             (list "/tmp/probe-target")
                             (lambda (value)
                               (funcall callback (format "done: %s" value))))))
      (funcall callback "the model is done"))))

(defun yeah-check--log-records (root name)
  "Return the records of the log of session NAME under ROOT.
The file is the truth: the in-memory list of a session is a cache of
it, and a check that reads the cache checks the cache."
  (with-temp-buffer
    (insert-file-contents (expand-file-name (format "sessions/%s.jsonl" name) root))
    (mapcar (lambda (line) (json-parse-string line :object-type 'plist))
            (split-string (buffer-string) "\n" t))))

(defun yeah-check--types (records)
  "Return the type of every record in RECORDS."
  (mapcar (lambda (record) (plist-get record :type)) records))

(defun yeah-check--permitted ()
  "Run a turn whose tool call the rules allow, and check what happened.
Returns a list of failures; an empty list means the turn behaved."
  (let* ((root (make-temp-file "yeah-turn-check" t))
         (session (yeah-session-open "turn" root))
         (ran (list nil))
         (asked (list 0))
         (failures nil))
    (yeah-tools-reset-for-test)
    (yeah-perm-rules-reset-for-test)
    (yeah-check--register-probe ran)
    (yeah-perm-rules-add (yeah-perm-rule-make "probe" "*" 'allow))
    (let* ((turn (yeah-turn-run session "do the thing"
                                    (yeah-check--fake-model asked)))
           (records (yeah-check--log-records root "turn")))
      (unless (yeah-turn-done turn)
        (push "the turn did not finish" failures))
      (unless (eq 'completed (yeah-turn-state turn))
        (push (format "the turn ended in %S, not completed"
                      (yeah-turn-state turn))
              failures))
      (unless (equal (car ran) "/tmp/probe-target")
        (push (format "the permitted tool ran on %S" (car ran)) failures))
      (unless (= 1 (car asked))
        (push (format "the model was asked %d times, expected 1" (car asked))
              failures))
      (unless (equal (yeah-turn-states turn)
                     '(deciding post-decide awaiting-tool accumulating
                       post-decide deciding post-decide completed))
        (push (format "the machine went through the wrong states: %S"
                      (yeah-turn-states turn))
              failures))
      (unless (equal (yeah-check--types records)
                     '("header" "user-message" "tool-request"
                       "permission-request" "permission-decision"
                       "tool-end" "assistant-message"))
        (push (format "the log holds the wrong records: %S"
                      (yeah-check--types records))
              failures))
      (unless (equal (plist-get (nth 5 records) :tool) "probe")
        (push "the logged tool is not the one that ran" failures)))
    (ignore-errors (delete-directory root t t))
    failures))

(defun yeah-check--refused ()
  "Run a turn whose tool call the rules deny, and check what happened.
Returns a list of failures; an empty list means the turn behaved."
  (let* ((root (make-temp-file "yeah-turn-check" t))
         (session (yeah-session-open "denied" root))
         (ran (list nil))
         (asked (list 0))
         (failures nil))
    (yeah-tools-reset-for-test)
    (yeah-perm-rules-reset-for-test)
    (yeah-check--register-probe ran)
    (yeah-perm-rules-add (yeah-perm-rule-make "probe" "*" 'deny))
    (let* ((turn (yeah-turn-run session "do the thing"
                                    (yeah-check--fake-model asked)))
           (records (yeah-check--log-records root "denied")))
      (unless (eq 'completed (yeah-turn-state turn))
        (push (format "the refused turn ended in %S, not completed"
                      (yeah-turn-state turn))
              failures))
      (when (car ran)
        (push "the refused tool ran anyway" failures))
      (unless (= 7 (length records))
        (push (format "the log holds %d records, expected 7" (length records))
              failures))
      (when (>= (length records) 6)
        (unless (equal "deny: probe on /tmp/probe-target"
                       (plist-get (nth 5 records) :payload))
          (push (format "the refusal was not logged as one: %S"
                        (plist-get (nth 2 records) :payload))
                failures))))
    (ignore-errors (delete-directory root t t))
    failures))

(let ((failures (append (yeah-check--permitted)
                         (yeah-check--refused))))
  (dolist (failure failures)
    (message "turn: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-model-turn-runs.el ends here
