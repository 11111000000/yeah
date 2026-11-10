;;; yeah-runtime.el --- the runtime of a run -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; An agent that runs without a person has obligations a person does not
;; have. A call can fail, and failing once is not a reason to stop; a
;; call can hang, and hanging is not a reason to wait for ever; and a
;; model can ask for the same thing for ever, which is a way of spending
;; somebody's money without making any progress.
;;
;; So there are three guards: a call is retried, a call is cut, and a run
;; that repeats itself is stopped.
;;
;; And none of the guards holds the main loop: a command runs in a
;; process, its output arrives at the filter, its end arrives at the
;; sentinel, and the answer comes to a callback when it comes.

;;; Code:

(require 'cl-lib)

(defconst yeah-runtime--default-retries 2
  "How many times a failing call is tried again.")

(defconst yeah-runtime--default-timeout 120
  "How many seconds a call may take before it is cut.")

(defconst yeah-runtime--doom-loop-threshold 3
  "How many times the same call in a row is a loop.")

(defun yeah-runtime-doom-loop-p (calls)
  "Non-nil when CALLS holds the same call three times in a row.
A model that asks for the same thing for ever is not making progress,
and the run must be stopped before it spends the money of somebody
else."
  (let ((run 0)
        (last nil)
        (found nil))
    (dolist (call calls)
      (if (equal call last)
          (setq run (1+ run))
        (setq run 1))
      (setq last call)
      (when (>= run yeah-runtime--doom-loop-threshold)
        (setq found t)))
    found))

(defun yeah-runtime--settle (state)
  "Hand the outcome of one attempt to the callback in STATE.
STATE is a plist: :command, :callback, :timeout, :attempt, :retries,
:timed-out, :status and :output."
  (let ((command (plist-get state :command))
        (callback (plist-get state :callback))
        (timeout (plist-get state :timeout))
        (attempt (plist-get state :attempt))
        (retries (plist-get state :retries))
        (timed-out (plist-get state :timed-out))
        (status (plist-get state :status))
        (output (plist-get state :output)))
    (cond
     ((and (not timed-out) (zerop status))
      (funcall callback (list :ok t :output output :attempts attempt)))
     (timed-out
      (funcall callback (list :ok nil :timeout t :attempts attempt
                              :output output)))
     ((> retries 0)
      (yeah-runtime--attempt command callback timeout (1+ attempt) (1- retries)))
     (t
      (funcall callback (list :ok nil :attempts attempt :output output))))))

(defun yeah-runtime--attempt (command callback timeout attempt retries)
  "Run COMMAND once and hand the outcome to CALLBACK.
TIMEOUT is the number of seconds the call may take, ATTEMPT which
attempt this is, and RETRIES how many attempts are left after this one."
  (let ((output "")
        (answered nil)
        (timed-out nil)
        (timer nil)
        (process nil))
    (setq process (make-process :name "yeah-runtime"
                                :command (list "sh" "-c" command)
                                :noquery t))
    (set-process-filter
     process
     (lambda (_proc chunk)
       (setq output (concat output chunk))))
    (set-process-sentinel
     process
     (lambda (proc _message)
       (when timer
         (cancel-timer timer))
       (unless answered
         (setq answered t)
         (yeah-runtime--settle
          (list :command command :callback callback :timeout timeout
                :attempt attempt :retries retries :timed-out timed-out
                :status (process-exit-status proc) :output output)))))
    (setq timer
          (run-with-timer
           timeout
           nil
           (lambda ()
             (unless answered
               (setq answered t)
               (setq timed-out t)
               (ignore-errors (delete-process process))
               (yeah-runtime--settle
                (list :command command :callback callback :timeout timeout
                      :attempt attempt :retries retries :timed-out t
                      :status 1 :output output))))))))

(cl-defun yeah-runtime-call (command callback &key retries timeout)
  "Run COMMAND and call CALLBACK with the outcome.
COMMAND is a shell command. CALLBACK is called with a plist: `:ok',
`:output', `:attempts', and `:timeout' when the call was cut. A call
that fails is tried again, up to RETRIES times; a call that takes
longer than TIMEOUT seconds is cut.

The command runs in a process and the answer arrives at the callback,
so the main loop is never held."
  (yeah-runtime--attempt command callback
                      (or timeout yeah-runtime--default-timeout)
                      1
                      (or retries yeah-runtime--default-retries)))

(provide 'yeah-runtime)
;;; yeah-runtime.el ends here
