;;; yeah-scheduler.el --- one batch of tool calls -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The tools of one answer of the model are a BATCH: they were asked for
;; together, and the model is asked again when they have all answered.
;; Running them one after the other makes the model wait for the slowest
;; of them before each of them; running them together is what the
;; reference harnesses do, and it is the difference between one round
;; trip and several.
;;
;; Two rules, and both come from the same place — the tools of one answer
;; were asked for together, so they may touch the same thing:
;;
;;   * a tool declared SHARED may run alongside the other shared tools;
;;   * a tool declared EXCLUSIVE runs alone: it waits for everything that
;;     is running, and everything after it waits for it.
;;
;; The third rule is about the log: the execution is parallel, the record
;; is not. The results are written in the order of the CALLS, never in the
;; order in which they happened to finish, so that the log of a run can
;; be read the same way twice.
;;
;; The scheduler never blocks. A call that waits — on a process, on a
;; timer — says so: its handler takes a continuation and calls it when
;; the call has settled. The batch settles when every call has settled,
;; and only then is the continuation of the batch called.

;;; Code:

(require 'cl-lib)

(cl-defstruct (yeah-batch (:constructor yeah-batch--make))
  "One batch of tool calls.

CALLS are the calls to run. INDEX is the next one to consider. RUNNING
is the number of calls that have not settled. RESULTS is a vector of
the results, in the order of the calls. DEFERRED holds the exclusive
calls that wait for the others to finish, in the order they were met.
EXCLUSIVE is the exclusive call that is running, if any. CONTINUATION
is called with the results when the batch has settled. SETTLED says
whether it has."
  (calls nil)
  (index 0)
  (running 0)
  (results nil)
  (deferred nil)
  (exclusive nil)
  (continuation nil)
  (settled nil))

(defun yeah-scheduler--settle (batch index result)
  "Record RESULT as the result of the call at INDEX in BATCH."
  (aset (yeah-batch-results batch) index result)
  (cl-decf (yeah-batch-running batch))
  (when (and (yeah-batch-exclusive batch)
              (= (plist-get (yeah-batch-exclusive batch) :index) index))
    (setf (yeah-batch-exclusive batch) nil))
  (yeah-scheduler--advance batch))

(defun yeah-scheduler--start (batch index)
  "Start the call at INDEX in BATCH. Return t when it settled at once."
  (let* ((call (nth index (yeah-batch-calls batch)))
         (handler (plist-get call :handler))
         (args (plist-get call :args)))
    (cl-incf (yeah-batch-running batch))
    (if (plist-get call :async)
        (progn
          (funcall handler args
                    (lambda (result)
                      (yeah-scheduler--settle batch index result)))
          ;; This call is waiting: the next shared call may start now.
          (yeah-scheduler--advance batch)
          nil)
      (let ((result (funcall handler args)))
        (yeah-scheduler--settle batch index result)
        t))))

(defun yeah-scheduler--advance (batch)
  "Start what may be started in BATCH, and finish it when nothing is left."
  (unless (yeah-batch-settled batch)
    (cond
     ;; An exclusive call that is running: nothing else may start.
     ((yeah-batch-exclusive batch) nil)
     ;; An exclusive call that waits: it starts when nothing else runs.
     ((and (yeah-batch-deferred batch)
           (= (yeah-batch-running batch) 0))
      (let* ((call (car (yeah-batch-deferred batch)))
             (index (plist-get call :index)))
        (setf (yeah-batch-deferred batch) (cdr (yeah-batch-deferred batch)))
        (when (plist-get call :async)
          (setf (yeah-batch-exclusive batch) call))
        (yeah-scheduler--start batch index)))
     ((and (null (yeah-batch-deferred batch))
           (< (yeah-batch-index batch) (length (yeah-batch-calls batch))))
      (let* ((index (yeah-batch-index batch))
             (call (nth index (yeah-batch-calls batch))))
        (setf (yeah-batch-index batch) (1+ index))
        (if (eq (plist-get call :mode) 'exclusive)
            (progn
              ;; The calls after an exclusive one wait for it.
              (setf (yeah-batch-deferred batch)
                    (append (yeah-batch-deferred batch)
                            (list (plist-put call :index index))))
              (yeah-scheduler--advance batch))
          (yeah-scheduler--start batch index))))
     ((and (null (yeah-batch-deferred batch))
           (= (yeah-batch-running batch) 0))
      (setf (yeah-batch-settled batch) t)
      (when (yeah-batch-continuation batch)
        (funcall (yeah-batch-continuation batch) (yeah-batch-results batch)))))))

;;;###autoload
(defun yeah-scheduler-run (calls continuation)
  "Run CALLS and call CONTINUATION with their results when they have all
settled.

CALLS is a list of plists:

  :name     the name of the tool
  :args     the arguments of the call
  :handler  the function that runs it; it is called with the list of
            arguments, and with a continuation when the call is async
  :async    non-nil when the handler takes a continuation
  :mode     `shared' or `exclusive'

The results are a vector in the order of the CALLS, whatever order the
calls finished in. The function returns immediately: a batch that is
still running is finished later, when its last call settles."
  (let ((batch (yeah-batch--make
                :calls calls
                :results (make-vector (length calls) nil)
                :continuation continuation)))
    (yeah-scheduler--advance batch)
    batch))

(provide 'yeah-scheduler)
;;; yeah-scheduler.el ends here
