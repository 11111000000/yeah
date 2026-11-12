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
;; Every call settles at most once.  Handler failures become structured
;; `(:yeah-error MESSAGE)' results, nil results are explicit failures, and
;; successful model-facing results are strings.  A duplicate asynchronous
;; callback cannot decrement the pending count or advance the batch twice.

;;; Code:

(require 'cl-lib)

(cl-defstruct (yeah-batch (:constructor yeah-batch--make))
  "One batch of tool calls.

CALLS are the calls to run.  INDEX is the next one to consider.  RUNNING is
the number of calls that have not settled.  RESULTS is a vector in call
order.  SETTLED-CALLS is the per-call once-only guard.  DEFERRED holds
exclusive calls in order.  EXCLUSIVE is the active exclusive call, if any.
CONTINUATION is called once after the whole batch settles.  SETTLED says
whether that has happened."
  (calls nil)
  (index 0)
  (running 0)
  (results nil)
  (settled-calls nil)
  (deferred nil)
  (exclusive nil)
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

(defun yeah-scheduler--settle (batch index result)
  "Settle the call at INDEX in BATCH with RESULT, unless it already settled.
The first result wins.  Duplicate callbacks are no-ops."
  (unless (aref (yeah-batch-settled-calls batch) index)
    (aset (yeah-batch-settled-calls batch) index t)
    (aset (yeah-batch-results batch) index
          (yeah-scheduler--normalize-result result))
    (cl-decf (yeah-batch-running batch))
    (when (and (yeah-batch-exclusive batch)
               (= (plist-get (yeah-batch-exclusive batch) :index) index))
      (setf (yeah-batch-exclusive batch) nil))
    (yeah-scheduler--advance batch)))

(defun yeah-scheduler--start (batch index)
  "Start the call at INDEX in BATCH.
A handler exception becomes the call's failure result instead of escaping
and leaving the batch pending."
  (let* ((call (nth index (yeah-batch-calls batch)))
         (handler (plist-get call :handler))
         (args (plist-get call :args)))
    (cl-incf (yeah-batch-running batch))
    (if (plist-get call :async)
        (condition-case err
            (progn
              (funcall handler args
                       (lambda (result)
                         (yeah-scheduler--settle batch index result)))
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

(defun yeah-scheduler--advance (batch)
  "Start what may be started in BATCH, and finish it when nothing is left."
  (unless (yeah-batch-settled batch)
    (cond
     ((yeah-batch-exclusive batch) nil)
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
  "Run CALLS and invoke CONTINUATION once when every call has settled.

Each call is a plist with :name, :args, :handler, :async and :mode
 (`shared' or `exclusive').  A synchronous handler receives ARGS; an
asynchronous handler receives ARGS and a continuation.  Results are a vector
in call order containing strings or `(:yeah-error MESSAGE)' failures."
  (let ((batch (yeah-batch--make
                :calls calls
                :results (make-vector (length calls) nil)
                :settled-calls (make-vector (length calls) nil)
                :continuation continuation)))
    (yeah-scheduler--advance batch)
    batch))

(provide 'yeah-scheduler)
;;; yeah-scheduler.el ends here
