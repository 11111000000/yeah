;;; yeah-ui.el --- what the person sees -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The reference harnesses are mostly interface, and their interface reads
;; one thing: the event stream. The run is rendered from the events and not
;; from the state of the agent, so that what the person sees and what the
;; log says cannot be two different stories.
;;
;; This module is that reading: it turns the records of the log into a view
;; — the transcript, the tool calls with their state, the approvals that
;; are still waiting and what the run has cost. It does not draw anything:
;; drawing is the business of whatever shows the view, and the REPL in
;; `lib/yeah-shell.el' is one such thing.
;;
;; The view is a plain plist. That is deliberate: an interface that has to
;; read a structure nobody can name is an interface nobody can replace.

;;; Code:

(require 'cl-lib)
(require 'yeah-events)

(defun yeah-ui--records (root session-id)
  "Return the records of the log of session SESSION-ID under ROOT."
  (let ((path (expand-file-name (format "sessions/%s.jsonl" session-id) root)))
    (if (file-exists-p path)
        (with-temp-buffer
          (insert-file-contents path)
          (mapcar (lambda (line) (json-parse-string line :object-type 'plist))
                  (split-string (buffer-string) "\n" t)))
      nil)))

(defun yeah-ui--call-state (records index)
  "Return the state of the tool call that starts at INDEX in RECORDS.
The state is `running' while nothing has ended it, `refused' when the
rules refused it, and `done' otherwise."
  (let ((outcome nil))
    (let ((i (1+ index)))
      (while (and (nth i records)
                  (not (equal (plist-get (nth i records) :type) "tool-end")))
        (setq i (1+ i)))
      (when (nth i records)
        (setq outcome (nth i records))))
    (cond
     ((null outcome) 'running)
     ((not (yeah-events-boolean-p (plist-get outcome :ok))) 'refused)
     (t 'done))))

(defun yeah-ui-view (records)
  "Return the view of the run RECORDS.

The view is a plist:

  :transcript  the messages, in the order they were said
  :calls       the tool calls, with their state and their result
  :pending     the approvals that were asked and not answered
  :usage       what the run has cost: input and output tokens

A :transcript entry is `(:role ROLE :text TEXT)'; a :calls entry is
`(:tool NAME :args ARGS :state STATE :ok BOOL :result TEXT)'."
  (let* ((usage-in 0)
         (usage-out 0)
         (transcript nil)
         (calls nil)
         (pending nil))
    (let ((i 0))
      (while (< i (length records))
        (let ((record (nth i records))
              (type (plist-get (nth i records) :type)))
          (cond
           ((equal type "user-message")
            (push (list :role "user" :text (plist-get record :payload))
                  transcript))
           ((equal type "assistant-message")
            (push (list :role "assistant" :text (plist-get record :payload))
                  transcript))
           ((equal type "tool-request")
            (let ((state (yeah-ui--call-state records i)))
              (push (list :tool (plist-get record :tool)
                          :args (plist-get record :args)
                          :state state
                          :ok (eq state 'done)
                          :result (or (plist-get (nth (1+ i) records) :payload) ""))
                    calls)))
           ((equal type "permission-request")
            (unless (and (nth (1+ i) records)
                         (equal (plist-get (nth (1+ i) records) :type)
                                "permission-decision"))
              (push (list :action (plist-get record :action)
                          :resource (plist-get record :resource))
                    pending)))
           ((equal type "usage")
            (setq usage-in (+ usage-in (or (plist-get record :input) 0))
                  usage-out (+ usage-out (or (plist-get record :output) 0)))))
          (setq i (1+ i)))))
    (list :transcript (nreverse transcript)
          :calls (nreverse calls)
          :pending (nreverse pending)
          :usage (list :input usage-in :output usage-out))))

(provide 'yeah-ui)
;;; yeah-ui.el ends here
