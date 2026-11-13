;;; check-concurrent-sessions.el --- two sessions run at once in one Emacs -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A service Emacs holds more than one run.  This check runs two sessions
;; at once in one Emacs process, with two run contexts whose fake
;; transports wait on timers, so the runs really interleave.
;;
;; What is proven:
;;
;;   - both runs reach a terminal state;
;;   - every event of each journal carries that session's work and none of
;;     the other's (the journals are compared for cross-talk);
;;   - cancelling one run stops it and leaves the other run to finish.
;;
;; No network is involved.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-run)
(require 'yeah-session)
(require 'yeah-turn)

(defvar yeah-check--data-home (make-temp-file "yeah-concurrent" t)
  "The data home of the two sessions.")

(defun yeah-check--journal (session-id)
  "Return the records of the journal of SESSION-ID, or nil."
  (let ((file (car (directory-files-recursively
                    yeah-check--data-home
                    (regexp-quote (concat session-id ".jsonl"))))))
    (when file
      (delq nil
            (mapcar (lambda (line)
                      (unless (string-blank-p line)
                        (json-parse-string line :object-type 'plist)))
                    (split-string
                     (with-temp-buffer (insert-file-contents file)
                                       (buffer-string))
                     "\n" t))))))

(defun yeah-check--payloads (records)
  "Return the payloads of the message records in RECORDS."
  (delq nil
        (mapcar (lambda (record)
                  (when (member (plist-get record :type)
                                '("user-message" "assistant-message"))
                    (plist-get record :payload)))
                records)))

(defun yeah-check--transport (answer delay)
  "Return a transport that answers ANSWER after DELAY seconds, on a timer."
  (lambda (_prompt callback)
    (run-with-timer delay nil (lambda () (funcall callback answer)))))

(defun yeah-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE holds, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-check--start (name answer delay)
  "Create a session and a run context named NAME and start the run.
The run answers ANSWER after DELAY seconds."
  (let ((context (yeah-run-context-create
                  :placement 'service
                  :session (yeah-session-open name yeah-check--data-home)
                  :transport (yeah-check--transport answer delay))))
    (yeah-run-context-start context "the task")
    context))

(let ((failures nil)
      (context-a nil)
      (context-b nil))
  (unwind-protect
      (progn
        ;; two runs interleave
        (setq context-a (yeah-check--start "session-a" "answer-a" 0.4))
        (setq context-b (yeah-check--start "session-b" "answer-b" 0.8))
        (unless (yeah-check--await
                 (lambda ()
                   (and (yeah-turn-done (yeah-run-context-turn context-a))
                        (yeah-turn-done (yeah-run-context-turn context-b))))
                 20)
          (push "the two runs did not finish" failures))
        (let ((journal-a (yeah-check--journal "session-a"))
              (journal-b (yeah-check--journal "session-b")))
          (unless (member "answer-a" (yeah-check--payloads journal-a))
            (push "session A does not hold its own answer" failures))
          (unless (member "answer-b" (yeah-check--payloads journal-b))
            (push "session B does not hold its own answer" failures))
          (when (member "answer-b" (yeah-check--payloads journal-a))
            (push "session A holds the answer of session B" failures))
          (when (member "answer-a" (yeah-check--payloads journal-b))
            (push "session B holds the answer of session A" failures))
          (when (cl-some (lambda (record)
                           (equal "cancel" (plist-get record :type)))
                         (or journal-a '()))
            (push "session A was cancelled though nobody asked" failures)))

        ;; cancelling one run leaves the other to finish
        (let ((context-c (yeah-check--start "session-c" "answer-c" 2.0))
              (context-d (yeah-check--start "session-d" "answer-d" 0.5)))
          (accept-process-output nil 0.2)
          (yeah-run-context-cancel context-c "stop c")
          (unless (yeah-check--await
                   (lambda () (yeah-turn-done (yeah-run-context-turn context-d)))
                   20)
            (push "the run that was not cancelled did not finish" failures))
          (unless (yeah-turn-done (yeah-run-context-turn context-c))
            (push "the cancelled run is not terminal" failures))
          (let ((journal-c (yeah-check--journal "session-c"))
                (journal-d (yeah-check--journal "session-d")))
            (unless (cl-some (lambda (record)
                               (equal "cancel" (plist-get record :type)))
                             (or journal-c '()))
              (push "the cancelled session has no cancel event" failures))
            (unless (member "answer-d" (yeah-check--payloads journal-d))
              (push "the run that was not cancelled lost its answer" failures))
            (when (member "answer-c" (yeah-check--payloads journal-c))
              (push "the cancelled run produced an answer" failures)))))

    (dolist (failure failures)
      (message "concurrent: %s" failure))
    (ignore-errors (delete-directory yeah-check--data-home t))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-concurrent-sessions.el ends here
