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
;; Shared tools may overlap; an exclusive tool runs alone.  Results retain
;; call order regardless of completion order.
;;
;; A call may declare the RESOURCE it touches: two calls that declare one
;; resource never run at the same time.  The lock is switched on by the
;; declaration: a call that declares no resource is never held back by
;; another call.  The lock is held from the start of the call until the
;; call settles.
;;
;; The waiting is finite, and the reason is the shape of the waiting: a
;; call waits for the calls that are RUNNING and for nothing else.  A
;; running call waits for nothing, so a call that waits for a resource is
;; waiting for calls that will end.  There is no cycle to enter, and no
;; two calls that wait for each other.
;;
;; A call may declare the limits of the tool it runs: `:timeout' is the
;; upper bound of the work of the call in seconds, and `:output-limit' is
;; the upper bound of its output in characters.  The kernel stops waiting
;; for a call at its timeout and closes it with a failure that names the
;; bound; the output of a call is bounded by its limit, so that the model
;; reads what fits and the whole text goes into a private artifact.
;;
;; Every call settles at most once.  Handler failures become structured
;; `(:yeah-error MESSAGE)' results, nil results are explicit failures, and
;; successful model-facing results are strings.  A duplicate asynchronous
;; callback cannot decrement the pending count or advance the batch twice.

;;; Code:

(require 'cl-lib)
(require 'yeah-result)

(cl-defstruct (yeah-batch (:constructor yeah-batch--make))
  "One batch of tool calls.

CALLS are the calls to run.  PENDING holds the calls that have not started
yet, in the order of the calls, as (INDEX . CALL) pairs.  RUNNING is the
number of calls that have not settled.  RESULTS is a vector in call order.
SETTLED-CALLS is the per-call once-only guard.  RESOURCES holds the resources
that the running calls declared, and the index of the call that holds each of
them.  EXCLUSIVE is the active exclusive call, if any, as an (INDEX . CALL)
pair.  TIMERS holds the timeout timer of every call, so that a timer of a
call that settled is cancelled.  CONTINUATION is called once after the whole
batch settles.  SETTLED says whether that has happened."
  (calls nil)
  (pending nil)
  (running 0)
  (results nil)
  (settled-calls nil)
  (resources nil)
  (exclusive nil)
  (timers nil)
  (continuation nil)
  (settled nil))

(defun yeah-scheduler--normalize-result (result)
  "Return a provider-safe representation of one tool RESULT.
A nil result is a failure.  Structured Yeah results retain their metadata;
legacy `(:yeah-error ...)' values retain their identity; other non-string
values are printed."
  (cond
   ((and (listp result)
         (booleanp (plist-get result :ok))
         (or (plist-member result :content)
             (plist-member result :error)))
    result)
   ((null result)
    (list :yeah-error "Error: tool produced no result"))
   ((and (consp result) (plist-get result :yeah-error)) result)
   ((stringp result) result)
   (t (format "%S" result))))

(defun yeah-scheduler--error-result (err)
  "Return a structured failure for signaled error ERR."
  (list :yeah-error (format "Error: %s" (error-message-string err))))

(defun yeah-scheduler--resource-of (call)
  "Return the resource the CALL declares, or nil when it declares none.
The resource is the name of what the call touches.  A value that is not a
nonempty string is no resource: the registry refuses such a declaration, and
the scheduler does not hold a call back over a name it cannot read."
  (let ((resource (plist-get call :tool-resource)))
    (if (and (stringp resource) (> (length resource) 0))
        resource
      nil)))

(defun yeah-scheduler--resource-held-p (batch resource)
  "Return non-nil when RESOURCE is held by a running call of BATCH."
  (and resource (gethash resource (yeah-batch-resources batch)) t))

(defun yeah-scheduler--claim-resource (batch index call)
  "Hold the resource of CALL for the call at INDEX of BATCH.
The resource is held until the call settles."
  (let ((resource (yeah-scheduler--resource-of call)))
    (when resource
      (puthash resource index (yeah-batch-resources batch)))
    resource))

(defun yeah-scheduler--release-resource (batch index)
  "Release the resource of the call at INDEX of BATCH."
  (let* ((call (nth index (yeah-batch-calls batch)))
         (resource (yeah-scheduler--resource-of call)))
    (when resource
      (remhash resource (yeah-batch-resources batch)))))

(defun yeah-scheduler--timeout-result (call)
  "Return the failure of a call that crossed the timeout it declares.
The failure names the tool and the bound: the model has to see which
limit it crossed."
  (list :yeah-error
        (format "Error: the call of %S exceeded its timeout of %d seconds"
                (plist-get call :name)
                (plist-get call :timeout))))

(defun yeah-scheduler--output-limit-of (call)
  "Return the output limit of CALL, or nil when the call declares none.
The limit is the number of characters of the output of the call that
reach the model; the whole text of an output that does not fit goes into
a private artifact."
  (let ((limit (plist-get call :output-limit)))
    (if (and (integerp limit) (> limit 0)) limit nil)))

(defun yeah-scheduler--arm-timeout (batch index call)
  "Arm the timeout of CALL at INDEX in BATCH.
The timer closes the call when the bound is crossed: the kernel stops
waiting for a call that took longer than the tool declared, and the
failure names the bound.  A call that declares no timeout is never
closed by a timer."
  (let ((timeout (plist-get call :timeout)))
    (when (and timeout (plist-get call :async))
      (aset (yeah-batch-timers batch) index
            (run-at-time timeout nil
                         (lambda ()
                           (yeah-scheduler--settle
                            batch index
                            (yeah-scheduler--timeout-result call))))))))

(defun yeah-scheduler--cancel-timeout (batch index)
  "Cancel the timeout timer of the call at INDEX in BATCH.
A call that settled before its bound does not leave a timer behind."
  (let ((timers (yeah-batch-timers batch)))
    (when (and timers (< index (length timers)))
      (let ((timer (aref timers index)))
        (when timer
          (cancel-timer timer)
          (aset timers index nil))))))

(defun yeah-scheduler--settle (batch index result)
  "Settle the call at INDEX in BATCH with RESULT, unless it already settled.
The first result wins.  Duplicate callbacks are no-ops.  The resource the
call held is released here: the lock lasts from the start of the call until
the call settles.  The output of the call is bounded by the limit the call
declares, and the timer of the call is cancelled."
  (unless (aref (yeah-batch-settled-calls batch) index)
    (aset (yeah-batch-settled-calls batch) index t)
    (aset (yeah-batch-results batch) index
          (yeah-scheduler--normalize-result
           (yeah-result-bound
            result
            (yeah-scheduler--output-limit-of
             (nth index (yeah-batch-calls batch))))))
    (cl-decf (yeah-batch-running batch))
    (yeah-scheduler--release-resource batch index)
    (yeah-scheduler--cancel-timeout batch index)
    (when (and (yeah-batch-exclusive batch)
               (= (car (yeah-batch-exclusive batch)) index))
      (setf (yeah-batch-exclusive batch) nil))
    (yeah-scheduler--advance batch)))

(defun yeah-scheduler--start (batch index)
  "Start the call at INDEX in BATCH.
The resource the call declares is held from here until the call settles.  An
exclusive call takes the batch to itself while it runs.  A handler exception
becomes the call's failure result instead of escaping and leaving the batch
pending.  A call that declares a timeout is closed by a timer when it
crosses the bound."
  (let* ((call (nth index (yeah-batch-calls batch)))
         (handler (plist-get call :handler))
         (args (plist-get call :args)))
    (cl-incf (yeah-batch-running batch))
    (yeah-scheduler--claim-resource batch index call)
    (yeah-scheduler--arm-timeout batch index call)
    (when (and (eq (plist-get call :mode) 'exclusive)
               (plist-get call :async))
      (setf (yeah-batch-exclusive batch) (cons index call)))
    (if (plist-get call :async)
        (condition-case err
            (progn
              (funcall handler args
                       (lambda (result)
                         ;; The answer of an asynchronous tool arrives in the
                         ;; sentinel of its process.  An error of the harness
                         ;; must not reach that sentinel: it would kill the
                         ;; whole Emacs process, and the run would leave no
                         ;; record of itself.
                         (condition-case err
                             (yeah-scheduler--settle batch index result)
                           (error
                            (yeah-scheduler--settle
                             batch index
                             (yeah-scheduler--error-result err))))))
              (yeah-scheduler--advance batch)
              nil)
          (error
           (yeah-scheduler--settle batch index
                                   (yeah-scheduler--error-result err))
           nil))
      (condition-case err
          (let ((result (funcall handler args)))
            (yeah-scheduler--settle batch index result)
            t)
        (error
         (yeah-scheduler--settle batch index
                                 (yeah-scheduler--error-result err))
         nil)))))

(defun yeah-scheduler--first-exclusive (pending)
  "Return the first exclusive call of PENDING, or nil when there is none.
The value is the (INDEX . CALL) pair of that call."
  (cl-find-if (lambda (entry) (eq (plist-get (cdr entry) :mode) 'exclusive))
              pending))

(defun yeah-scheduler--before-gate (pending gate)
  "Return the calls of PENDING that come before GATE.
GATE is the first exclusive call of PENDING, or nil when there is none.  The
calls after the gate wait for it: an exclusive tool runs alone, and everything
else waits for it."
  (if gate
      (let (before
            (rest pending))
        (while (and rest (not (eq (car rest) gate)))
          (push (car rest) before)
          (setq rest (cdr rest)))
        (nreverse before))
    pending))

(defun yeah-scheduler--next-startable (batch)
  "Return the call of BATCH that may start now, or nil when none may.
A call that declares a resource waits while a running call holds that
resource.  A call that declares no resource is never held back by another
call.  An exclusive call waits for every running call, and the calls that
come after it wait for it: it runs alone.

The order of the waiting is finite.  A call waits for the calls that are
running and for nothing else, and a running call waits for nothing, so a
call that waits for a resource is waiting for calls that will end."
  (let* ((pending (yeah-batch-pending batch))
         (gate (yeah-scheduler--first-exclusive pending)))
    (or (cl-find-if (lambda (entry)
                      (not (yeah-scheduler--resource-held-p
                             batch (yeah-scheduler--resource-of (cdr entry)))))
                    (yeah-scheduler--before-gate pending gate))
        ;; the exclusive call runs alone: it starts when nothing else runs,
        ;; and then no resource is held, so its own resource is free
        (and gate
             (= (yeah-batch-running batch) 0)
             gate))))

(defun yeah-scheduler--advance (batch)
  "Start what may be started in BATCH, and finish it when nothing is left.
A call that declares a resource waits for the calls that hold it; a call that
declares no resource waits for nothing.  An exclusive call runs alone: it
starts when nothing else is running, and the calls that come after it wait
for it."
  (unless (yeah-batch-settled batch)
    (unless (yeah-batch-exclusive batch)
      (let ((entry (yeah-scheduler--next-startable batch)))
        (if entry
            (progn
              (setf (yeah-batch-pending batch)
                    (delq entry (yeah-batch-pending batch)))
              (yeah-scheduler--start batch (car entry)))
          (when (and (null (yeah-batch-pending batch))
                     (= (yeah-batch-running batch) 0))
            (setf (yeah-batch-settled batch) t)
            (when (yeah-batch-continuation batch)
              (funcall (yeah-batch-continuation batch)
                       (yeah-batch-results batch)))))))))

;;;###autoload
(defun yeah-scheduler-run (calls continuation)
  "Run CALLS and invoke CONTINUATION once when every call has settled.

Each call is a plist with :name, :args, :handler, :async and :mode
 (`shared' or `exclusive').  A call may declare the resource it touches under
`:tool-resource': two calls that declare one resource never run at the same
time, and the lock lasts from the start of a call until the call settles.  A
call may declare the limits of its tool: `:timeout' is the upper bound of
the work of the call in seconds, and the kernel closes the call when it
crosses the bound; `:output-limit' is the upper bound of the output of the
call in characters, and the model reads what fits while the whole text goes
into a private artifact.  A synchronous handler receives ARGS; an
asynchronous handler receives ARGS and a continuation.  Results are a vector
in call order containing strings or `(:yeah-error MESSAGE)' failures."
  (let ((batch (yeah-batch--make
                :calls calls
                :pending (let (pending)
                           (dotimes (index (length calls))
                             (push (cons index (nth index calls)) pending))
                           (nreverse pending))
                :results (make-vector (length calls) nil)
                :settled-calls (make-vector (length calls) nil)
                :resources (make-hash-table :test 'equal)
                :timers (make-vector (length calls) nil)
                :continuation continuation)))
    (yeah-scheduler--advance batch)
    batch))

(provide 'yeah-scheduler)
;;; yeah-scheduler.el ends here
