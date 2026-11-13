;;; yeah-run.el --- the context of one run -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; One run owns its session, its transport, its answerer, its rules, its
;; budget and its deadline.  The kernel used to carry most of that in
;; global variables, which meant two runs in one Emacs shared one truth:
;; one run's "always" became another run's rule, and one run's cancel
;; stopped another run's processes.
;;
;; A run context is the bundle.  The placement creates one, the run reads
;; from it, and nothing outside it has to be consulted.  The rules of a
;; context start as a copy of the persistent rules of the person; they may
;; be widened by the run, and the persistent set changes only when a
;; person answers "always" — a decision about the person, not about the
;; run.
;;
;; The answerer of a context is a policy: the rules of the context decide,
;; and what the rules do not name is asked of the person, when there is a
;; person to ask.  With nobody to ask, the answer is a refusal.

;;; Code:

(require 'cl-lib)
(require 'yeah-approval)
(require 'yeah-perm)
(require 'yeah-turn)

(defgroup yeah-run nil
  "The context of one run."
  :group 'yeah)

(cl-defstruct (yeah-run-context (:constructor yeah-run-context--make))
  "Everything one run owns.

ID names the run.  PLACEMENT says where the run lives: `attached',
`service' or `batch'.  SESSION is the session the run writes into.
TRANSPORT is the function of (PROMPT CALLBACK) that reaches the model.
ANSWERER answers a request for permission that the rules did not
decide.  RULES are the permission rules of this run.  BUDGET is the
context budget.  DEADLINE is a whole-run timeout in seconds.
INPUT is the frozen input captured at submission.  STEER-SOURCE returns
the pending inputs of the person.  ON-DONE is called once at a terminal
state.  MAX-NUDGES bounds completion supervision.
TOOLS-REGISTRY is the registry snapshot of this run: a tool one run
registers does not appear in another."
  (id nil)
  (placement nil)
  (session nil)
  (transport nil)
  (answerer nil)
  (rules nil)
  (budget nil)
  (deadline nil)
  (input nil)
  (steer-source nil)
  (on-done nil)
  (max-nudges nil)
  (turn nil)
  (cancelled nil)
  (tools-registry nil))

(defvar yeah-run--counter 0
  "Monotonic suffix for run identifiers.")

(defun yeah-run--fresh-id ()
  "Return a new run identifier."
  (setq yeah-run--counter (1+ yeah-run--counter))
  (format "run-%d" yeah-run--counter))

(cl-defun yeah-run-context-create (&key placement session transport answerer
                                    rules budget deadline input
                                    steer-source on-done max-nudges id)
  "Return a run context for one run.

PLACEMENT names where the run lives.  SESSION is the session it writes
into.  TRANSPORT reaches the model.  ANSWERER answers the requests the
rules do not decide.  RULES are the permission rules of the run; when
they are nil the run starts from a copy of the persistent rules.
BUDGET, DEADLINE, INPUT, STEER-SOURCE, ON-DONE and MAX-NUDGES are the
rest of what the run needs."
  (let ((context (yeah-run-context--make
                  :id (or id (yeah-run--fresh-id))
                  :placement placement
                  :session session
                  :transport transport
                  :answerer answerer
                  :rules (or rules (copy-sequence yeah-perm--rules))
                  :budget budget
                  :deadline deadline
                  :input input
                  :steer-source steer-source
                  :on-done on-done
                  :max-nudges max-nudges
                  :tools-registry (yeah-tools-snapshot))))
    (unless (memq placement '(attached service batch))
      (signal 'user-error
              (list (format "yeah-run-context-create: unknown placement %S"
                            placement))))
    context))

(defun yeah-run-context-add-rule (context rule)
  "Add RULE to the rules of CONTEXT and return CONTEXT.
The persistent rules of the person are not touched: a run may widen its
own reach for the length of the run."
  (setf (yeah-run-context-rules context)
        (yeah-perm-rules-append (yeah-run-context-rules context) rule))
  context)

(defun yeah-run-context-policy (context)
  "Return the answerer of CONTEXT.

The rules of the context decide.  What they do not name is asked of the
answerer of the context, when there is one; with nobody to ask, the
answer is a refusal that says so."
  (let ((person (yeah-run-context-answerer context)))
    (lambda (request)
      (let* ((action (plist-get request :action))
             (resource (plist-get request :resource))
             (effect (yeah-perm-effect action resource
                                       (yeah-run-context-rules context))))
        (pcase effect
          ('allow
           (list :effect :allow :reply :once))
          ('deny
           (list :effect :deny :reply :reject
                 :reason (format "the rules deny %s on %s" action resource)))
          (_
           (if person
               (funcall person request)
             (list :effect :deny :reply :reject
                   :reason (format "the rules ask about %s on %s and nobody answers"
                                   action resource)))))))))

(defun yeah-run-context-start (context prompt)
  "Start the run of CONTEXT with PROMPT and return the turn.

The transport, the answerer, the budget, the deadline and the frozen
input all come from CONTEXT: the kernel is told once, and the run owns
the rest."
  (when (yeah-run-context-cancelled context)
    (signal 'user-error
            (list "yeah-run-context-start: the run was cancelled before it started")))
  (let ((turn (yeah-turn-run
               (yeah-run-context-session context)
               prompt
               (yeah-run-context-transport context)
               (yeah-run-context-policy context)
               (yeah-run-context-budget context)
               (yeah-run-context-max-nudges context)
               (lambda (finished)
                 (when-let ((done (yeah-run-context-on-done context)))
                   (funcall done finished)))
               (yeah-run-context-steer-source context)
               (yeah-run-context-input context)
               (yeah-run-context-deadline context)
               (yeah-run-context-tools-registry context))))
    (setf (yeah-run-context-turn context) turn)
    turn))

(defun yeah-run-context-cancel (context &optional reason)
  "Cancel the run of CONTEXT because of REASON.
Return non-nil when a running turn was cancelled.  The context stays
cancelled: a cancelled run is not restarted."
  (setf (yeah-run-context-cancelled context) t)
  (if-let ((turn (yeah-run-context-turn context)))
      (yeah-turn-cancel turn reason)
    nil))

(defun yeah-run-context-cancelled-p (context)
  "Return non-nil when the run of CONTEXT was cancelled."
  (and (yeah-run-context-cancelled context) t))

(provide 'yeah-run)
;;; yeah-run.el ends here
