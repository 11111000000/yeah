;;; yeah-runtime.el --- asynchronous runtime guards -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Failing commands are retried with bounded linear backoff, hanging commands
;; are cut by a timer, and repeated mutating calls are detected as possible
;; doom loops.  Repeated read-only inspection is explicitly allowed.

;;; Code:

(require 'cl-lib)

(defconst yeah-runtime--default-retries 2
  "How many times a failing call is tried again.")

(defconst yeah-runtime--default-timeout 120
  "How many seconds a call may take before it is cut.")

(defconst yeah-runtime--default-backoff 0.25
  "Seconds before the next retry after a transient failure.")

(defconst yeah-runtime--doom-loop-threshold 3
  "How many identical mutating calls in a row indicate a possible loop.")

(defun yeah-runtime-doom-loop-p (calls)
  "Return non-nil when CALLS repeats one mutating call three times in a row.
Read, glob and grep calls are inspection, so their repetition is legitimate."
  (let ((run 0)
        (last nil)
        (found nil))
    (dolist (call calls)
      (unless (memq (car call) '(read glob grep))
        (if (equal call last)
            (setq run (1+ run))
          (setq run 1))
        (setq last call)
        (when (>= run yeah-runtime--doom-loop-threshold)
          (setq found t))))
    found))

(defun yeah-runtime--settle (state)
  "Hand the outcome of one attempt to the callback in STATE."
  (let ((command (plist-get state :command))
        (callback (plist-get state :callback))
        (timeout (plist-get state :timeout))
        (attempt (plist-get state :attempt))
        (retries (plist-get state :retries))
        (backoff (plist-get state :backoff))
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
      (run-at-time backoff nil
                   (lambda ()
                     (yeah-runtime--attempt command callback timeout
                                            (1+ attempt) (1- retries) backoff))))
     (t
      (funcall callback (list :ok nil :attempts attempt :output output))))))

(defun yeah-runtime--attempt (command callback timeout attempt retries backoff)
  "Run COMMAND once and hand its outcome to CALLBACK."
  (let ((output "")
        (answered nil)
        (timed-out nil)
        (timer nil)
        (process nil))
    (setq process (make-process :name "yeah-runtime"
                                :command (list "sh" "-c" command)
                                :coding '(utf-8 . utf-8)
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
                :attempt attempt :retries retries :backoff backoff
                :timed-out timed-out
                :status (process-exit-status proc) :output output)))))
    (setq timer
          (run-at-time
           timeout nil
           (lambda ()
             (unless answered
               (setq answered t)
               (setq timed-out t)
               (ignore-errors (delete-process process))
               (yeah-runtime--settle
                (list :command command :callback callback :timeout timeout
                      :attempt attempt :retries retries :backoff backoff
                      :timed-out t :status 1 :output output))))))))

(cl-defun yeah-runtime-call (command callback &key retries timeout backoff)
  "Run COMMAND asynchronously and call CALLBACK with its outcome.
RETRIES defaults to 2, TIMEOUT to 120 seconds and BACKOFF to 0.25 seconds.
Only failed attempts are delayed; a hanging attempt is cut without retry."
  (yeah-runtime--attempt command callback
                         (or timeout yeah-runtime--default-timeout)
                         1
                         (or retries yeah-runtime--default-retries)
                         (or backoff yeah-runtime--default-backoff)))

(provide 'yeah-runtime)
;;; yeah-runtime.el ends here
