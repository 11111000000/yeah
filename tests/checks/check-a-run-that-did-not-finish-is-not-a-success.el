;;; check-a-run-that-did-not-finish-is-not-a-success.el --- a run that did not finish says so -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A run whose model described its next step instead of taking it ends
;; without an effect.  Such a run is not a success, and the kernel says so
;; twice: the turn ends in the state `failed', and the ACP wire answers it
;; with the stop reason `refusal'.  The wire must never answer such a run
;; with `end_turn': that reason says the work is done, and it is not.
;;
;; The model here is a FAKE: a transport that only talks.  No network is
;; touched, and the check is about the verdict of the run, not about the
;; model.
;;
;; Exit codes: 0 — the run that did not finish says so; 1 — it does not.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-acp)
(require 'yeah-session)
(require 'yeah-turn)

(defun yeah-check--talks-only ()
  "Return a transport whose model only describes its next step."
  (lambda (_prompt callback)
    (funcall callback "I will write the file now.")))

(defun yeah-check--records (root name)
  "Return the records of the log of session NAME under ROOT."
  (with-temp-buffer
    (insert-file-contents (expand-file-name (format "sessions/%s.jsonl" name) root))
    (mapcar (lambda (line) (json-parse-string line :object-type 'plist))
            (split-string (buffer-string) "\n" t))))

(defun yeah-check--request (method params id)
  "Return the JSON-RPC request string for METHOD with PARAMS and ID."
  (json-serialize
   (list :jsonrpc "2.0" :id id :method method :params params)))

(defun yeah-check--the-turn-state ()
  "Run a turn whose model only talks and return the failures.
An empty list means the turn said that it did not finish."
  (let* ((root (make-temp-file "yeah-unfinished-check" t))
         (session (yeah-session-open "unfinished" root))
         (failures nil))
    (let* ((turn (yeah-turn-run session "do the thing" (yeah-check--talks-only)))
           (records (yeah-check--records root "unfinished")))
      (unless (eq 'failed (yeah-turn-state turn))
        (push (format "the turn ended in %S, not failed: the run looks done"
                      (yeah-turn-state turn))
              failures))
      (unless (cl-some (lambda (record)
                          (equal "unfinished" (plist-get record :type)))
                        records)
        (push "the log does not hold the unfinished record" failures)))
    (ignore-errors (delete-directory root t t))
    failures))

(defun yeah-check--the-wire-answer ()
  "Ask the ACP route about a run whose model only talks.
Return the failures; an empty list means the wire refused to call it done."
  (let* ((home (make-temp-file "yeah-unfinished-acp" t))
         (emitted nil)
         (failures nil))
    (let ((yeah-data-home home))
      (setq yeah-acp--output-function (lambda (text) (push text emitted))
            yeah-acp--transport (yeah-check--talks-only))
      (let* ((raw (yeah-acp-handle-message
                   (yeah-check--request
                    "session/new"
                    (list :cwd (file-truename home) :mcpServers nil)
                    1)))
             (session-id (plist-get
                          (plist-get (json-parse-string raw :object-type 'plist)
                                     :result)
                          :sessionId)))
        (unless (stringp session-id)
          (push "the session was not created" failures)
          (setq session-id nil))
        (when session-id
          (yeah-acp-handle-message
           (yeah-check--request
            "session/prompt"
            (list :sessionId session-id
                  :prompt (vector (list :type "text" :text "do the thing")))
            2)))
        (let ((answer (cl-find-if
                       (lambda (text)
                         (let ((parsed (json-parse-string text :object-type 'plist)))
                           (and (equal 2 (plist-get parsed :id))
                                (not (plist-get parsed :method)))))
                       emitted)))
          (unless answer
            (push "the prompt was not answered" failures)
            (setq answer "{}"))
          (let ((stop (plist-get
                       (plist-get (json-parse-string answer :object-type 'plist)
                                  :result)
                       :stopReason)))
            (unless (equal "refusal" stop)
              (push (format "the wire answered %S, not refusal: the run looks done"
                            stop)
                    failures))))))
    (yeah-acp--reset-for-test)
    (ignore-errors (delete-directory home t t))
    failures))

(let ((failures (append (yeah-check--the-turn-state)
                         (yeah-check--the-wire-answer))))
  (dolist (failure failures)
    (message "unfinished: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-run-that-did-not-finish-is-not-a-success.el ends here
