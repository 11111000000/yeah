;;; yeah-turn.el --- one turn of the model -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; One turn of the agent loop: ask the model, take the tool calls it asked
;; for, decide whether each of them may run, run them together, write what
;; happened into the append-only log, and hand the results back so that
;; the model can answer again.
;;
;; The turn does not know how the model is reached. It is handed a
;; TRANSPORT: a function of (PROMPT CALLBACK) that calls CALLBACK with the
;; model's answer. The shape of the answer is the one gptel uses, because
;; gptel is the transport:
;;
;;   a string
;;       the model has answered with text;
;;
;;   (tool-call . ((TOOL ARGS CB) ...))
;;       the model has asked for tools; CB continues the conversation once
;;       the result of the call is known.
;;
;; The transport in `lib/yeah-gptel.el' is the one that speaks gptel; the
;; transport in the checks is a fake. Nothing else in the kernel knows
;; that gptel exists.
;;
;; What the turn owns is the part that must not be given away: the
;; permission system decides whether a call may run, the registry decides
;; whether its arguments are well formed, the scheduler decides what runs
;; together, and the log remembers what happened. The model proposes; it
;; does not decide.

;;; Code:

(require 'cl-lib)
(require 'yeah-state)
(require 'yeah-loop)
(require 'yeah-tools)
(require 'yeah-perm)
(require 'yeah-session)
(require 'yeah-events)
(require 'yeah-approval)
(require 'yeah-result)
(require 'yeah-compact)
(require 'yeah-process)
(require 'yeah-scheduler)

;; A tool of the model is a gptel-tool struct when gptel is loaded, and a
;; plist with a :name key otherwise; the checks use the latter.
(declare-function gptel-tool-p "gptel" (object))
(declare-function gptel-tool-name "gptel" (tool))

(cl-defstruct (yeah-turn (:constructor yeah-turn--make))
  "One run of the agent loop.

SESSION is the session the run writes into. STATE is the state of the
machine. STATES is the list of states the run has been in, in order.
CALLS is the number of tool calls dispatched. TURNS is the number of
times the model was asked. DONE says whether the model has finished.
ERROR holds the reason when the run stopped for a reason of its own.
TOOLS-REGISTRY is the registry snapshot of this run, or nil for the
shared one."
  (session nil)
  (state 'idle)
  (states nil)
  (calls 0)
  (turns 0)
  (done nil)
  (done-notified nil)
  (error nil)
  (budget yeah-context-default-budget)
  (id nil)
  (cancelled nil)
  (on-done nil)
  (steer-source nil)
  (nudges 0)
  (max-nudges 0)
  (model-fsm nil)
  (input nil)
  (deadline-timer nil)
  (tools-registry nil)
  (tools-used nil)
  (transport nil)
  (answerer nil)
  (pending-answer nil)
  (pending-permissions nil))

(declare-function gptel-abort "gptel-request" (buffer))
(declare-function gptel-fsm-info "gptel-request" (fsm))

(defcustom yeah-turn-nudge-message
  "Continue the work you were doing: call the tools you still need. Do not start the task over. When the work is done, say what you did and stop."
  "Prompt sent as a visible completion nudge when enabled for a run."
  :type 'string
  :group 'yeah)

(defcustom yeah-turn-default-max-nudges 0
  "Default completion nudge budget.
Zero keeps ordinary runs uninterrupted: the run ends as soon as the model
answers with text.  A run that asks for supervision (a non-zero budget)
is nudged when the model describes its next step instead of taking it, or
when it reports a result that no tool backs; the nudge names the tools the
run has not called yet."
  :type 'integer
  :group 'yeah)

(defun yeah-turn--mark-done (turn &optional terminal-state)
  "Mark TURN done, optionally in TERMINAL-STATE, and notify exactly once."
  (when terminal-state
    (setf (yeah-turn-state turn) terminal-state)
    (setf (yeah-turn-states turn)
          (append (yeah-turn-states turn) (list terminal-state))))
  (setf (yeah-turn-done turn) t)
  (when-let ((timer (yeah-turn-deadline-timer turn)))
    (cancel-timer timer)
    (setf (yeah-turn-deadline-timer turn) nil))
  (unless (yeah-turn-done-notified turn)
    (setf (yeah-turn-done-notified turn) t)
    (when (functionp (yeah-turn-on-done turn))
      (funcall (yeah-turn-on-done turn) turn))))

(defun yeah-turn--tool-name (tool)
  "Return the name of the gptel-shaped TOOL."
  (cond ((and (fboundp 'gptel-tool-name) (gptel-tool-p tool))
         (gptel-tool-name tool))
        ((plist-get tool :name) (plist-get tool :name))
        (t (signal 'user-error
                   (list (format "yeah-turn: cannot read the name of a tool: %S"
                                 tool))))))

(defun yeah-turn--resource (args)
  "Return the resource the tool acts on: its first argument when that
argument names a thing, and the printed arguments otherwise. The rules
of the permission system match this, so `read' on a file is matched by
the path and not by a printed list of arguments."
  (or (and (listp args) (stringp (car args)) (car args))
      (format "%S" args)))

(defun yeah-turn--tick (turn label)
  "Move TURN on LABEL and record the state it moved to.
Return the new state. A transition that the machine does not have is a
bug in the turn, and the run stops with that reason."
  (let ((from (yeah-turn-state turn)))
    (condition-case err
        (let ((to (yeah-loop-tick from label)))
          (setf (yeah-turn-state turn) to)
          (setf (yeah-turn-states turn)
                (append (yeah-turn-states turn) (list to)))
          to)
      (user-error
       (yeah-turn--fail turn (error-message-string err))
       (yeah-turn-state turn)))))

(defun yeah-turn--fail (turn reason)
  "Stop TURN because of REASON, and say why in the log."
  (if (eq (yeah-turn-state turn) 'deciding)
      (yeah-turn--tick turn 'error)
    (unless (memq (yeah-turn-state turn) '(completed failed interrupted))
      (setf (yeah-turn-state turn) 'failed)
      (setf (yeah-turn-states turn)
            (append (yeah-turn-states turn) (list 'failed)))))
  (setf (yeah-turn-error turn) reason)
  (yeah-turn--mark-done turn)
  (when (yeah-turn-session turn)
    (yeah-events-write (yeah-turn-session turn) "error" :payload reason))
  reason)

(defun yeah-turn-resume-permission (turn request-id decision)
  "Answer the deferred permission request REQUEST-ID of TURN with DECISION.
The wire layer calls this when the client's answer arrives."
  (when-let ((resume (gethash request-id (yeah-turn-pending-permissions turn))))
    (remhash request-id (yeah-turn-pending-permissions turn))
    (funcall resume decision)))

(defun yeah-turn--decide (answerer spec name resource args)
  "Ask the ANSWERER whether the tool NAME may act on RESOURCE with ARGS.
Return (EFFECT . REFUSED): EFFECT is \"allow\", \"deny\" or \"defer\", and
REFUSED is the reason the call may not run, or nil when it may.
The answerer is either the rules or a person; the kernel does not
know which.  `finish' is always allowed: it is a control signal, not
an effect on the world."
  (cond
   ((null spec)
    (cons "deny" (format "there is no tool named %s" name)))
   ((equal name "finish")
    (cons "allow" nil))
   (t
    (let ((decision (funcall answerer
                             (yeah-approval-request name resource args))))
      (if (plist-get decision :defer)
          ;; The answerer asks the person over the wire; the call waits.
          (cons "defer" (plist-get decision :defer))
        (if (eq (plist-get decision :effect) :allow)
            (cons "allow" nil)
          (cons "deny" (or (plist-get decision :reason)
                            (format "the rules say %s" name)))))))))

(defun yeah-turn--prepare (turn answerer index call)
  "Prepare the tool CALL at INDEX of TURN for the batch.
Return a plist: :index is the position of the call, :name and :args are
what the tool is called with, :spec is the registry spec of the tool,
and :refused is the reason the call may not run, or nil.

The log says what happened: the model asked for the tool, the rules
were asked, and the rules answered."
  (let* ((name (yeah-turn--tool-name (nth 0 call)))
         (args (yeah-tools-normalize-args name (nth 1 call)))
         (spec (yeah-tools-get name))
         (resource (yeah-turn--resource args)))
    (let ((decision (yeah-turn--decide answerer spec name resource args)))
      (yeah-events-write (yeah-turn-session turn) "tool-request"
                         :tool name :args (format "%S" args))
      (yeah-events-write (yeah-turn-session turn) "permission-request"
                         :action name :resource resource)
      (yeah-events-write (yeah-turn-session turn) "permission-decision"
                         :action name :resource resource
                         :effect (car decision))
      (list :index index :name name :args args :spec spec
            :refused (and (not (equal "defer" (car decision))) (cdr decision))
            :deferred (and (equal "defer" (car decision)) (cdr decision))))))

(defun yeah-turn--continue-batch (turn calls results)
  "Continue TURN after tool CALLS and RESULTS, compacting first if needed.
Steering is delivered only after the entire batch has settled."
  (unless (yeah-turn-done turn)
    (let ((steering (and (functionp (yeah-turn-steer-source turn))
                         (funcall (yeah-turn-steer-source turn) turn))))
      (dolist (input steering)
        (yeah-events-write (yeah-turn-session turn) "steering"
                           :payload (plist-get input :prompt)))
      (pcase (yeah-turn-state turn)
        ('accumulating (yeah-turn--tick turn 'budget-ok))
        ('compacting (yeah-turn--tick turn 'compact-done)))
      (yeah-turn--tick turn 'continue)
      (let ((pending (yeah-turn-pending-answer turn)))
        (when pending
          ;; The model already said its last word while the tools were
          ;; running.  That answer ends the run now; asking again would
          ;; only repeat it.
          (setf (yeah-turn-pending-answer turn) nil)
          (yeah-turn--answer-text
           turn pending (yeah-turn-transport turn) (yeah-turn-answerer turn))
          (setq calls nil)))
      (let ((index 0)
            (clarification
             (mapconcat (lambda (input)
                          (concat "\n\nUser clarification: "
                                  (plist-get input :prompt)))
                        steering "")))
        (dolist (call calls)
          (let ((continue (nth 2 call))
                (value (concat (yeah-result-model-text (aref results index))
                               (if (zerop index) clarification ""))))
            (when continue
              (funcall continue value)))
          (setq index (1+ index)))))))

(defun yeah-turn--maybe-compact (turn transport calls results)
  "Compact TURN's session before continuing when its budget overflows."
  (if (yeah-context-overflow-p
       (yeah-context-project (yeah-turn-session turn))
       (yeah-turn-budget turn))
      (progn
        (yeah-turn--tick turn 'budget-overflow)
        (yeah-compact-run-async
         (yeah-turn-session turn)
         (* 4 (yeah-turn-budget turn))
         transport
         (lambda (result _info)
           (unless (yeah-turn-done turn)
             (if (plist-get result :error)
                 (yeah-turn--fail turn (plist-get result :error))
               (yeah-turn--continue-batch turn calls results))))
         (lambda () (not (yeah-turn-done turn)))))
    (yeah-turn--continue-batch turn calls results)))

(defun yeah-turn--prepare-batch (turn answerer calls)
  "Return the prepared slots of CALLS, in the order of the calls.
Each slot says what the tool is, what it is called with, and whether it
may run: :refused names the reason it may not, :deferred names the
question that waits for the person."
  (mapcar (lambda (index)
            (yeah-turn--prepare turn answerer index (nth index calls)))
          (number-sequence 0 (1- (length calls)))))

(defun yeah-turn--split-slots (prepared)
  "Return (RUNNABLE . REFUSED) for the PREPARED slots.
REFUSED holds an (INDEX . REASON) pair per call that may not run; every
other slot may run, including the ones waiting for the person."
  (let ((runnable nil) (refused nil))
    (dolist (slot prepared)
      (if (plist-get slot :refused)
          (push (cons (plist-get slot :index) (plist-get slot :refused))
                refused)
        (push slot runnable)))
    (cons (nreverse runnable) (nreverse refused))))

(defun yeah-turn--handler (turn slot)
  "Return the handler that runs SLOT's tool once it may.
A deferred call waits for the person's answer: the wire layer calls the
resume callback when the answer arrives, and the tool runs only if the
person allowed it."
  (lambda (args &optional done)
    (if (plist-get slot :deferred)
        (let ((request-id (plist-get slot :deferred)))
          (puthash request-id
                   (lambda (decision)
                     (if (eq (plist-get decision :effect) :allow)
                         (yeah-tools-dispatch (plist-get slot :name) args done)
                       (funcall done
                                (yeah-result-error
                                 (or (plist-get decision :reason)
                                     "the person refused")))))
                   (yeah-turn-pending-permissions turn)))
      (yeah-tools-dispatch (plist-get slot :name) args done))))

(defun yeah-turn--call-spec (turn slot)
  "Return the scheduler call of SLOT: the tool, its arguments, the
handler and the concurrency the tool asks for."
  (let ((spec (plist-get slot :spec)))
    (list :name (plist-get slot :name)
          :args (plist-get slot :args)
          :handler (yeah-turn--handler turn slot)
          :async (or (plist-get slot :deferred) (plist-get spec :async))
          :mode (yeah-tools-concurrency spec))))

(defun yeah-turn--finish-result (calls results)
  "Return the result of the `finish' call among CALLS, or nil."
  (let ((finish nil) (i 0))
    (dolist (call calls)
      (when (equal "finish" (yeah-turn--tool-name (nth 0 call)))
        (setq finish (aref results i)))
      (setq i (1+ i)))
    finish))

(defun yeah-turn--settle-batch (turn transport calls runnable results refused settled)
  "Record the settled batch of TURN and continue it.
The results are in the order of the CALLS, whatever order the calls
finished in: the log of a run is read the same way twice."
  (let ((i 0))
    (dolist (slot runnable)
      (aset results (plist-get slot :index) (aref settled i))
      (setq i (1+ i))))
  (let ((i 0))
    (dolist (call calls)
      (let ((result (aref results i)))
        (yeah-events-write
         (yeah-turn-session turn)
         "tool-end"
         :tool (yeah-turn--tool-name (nth 0 call))
         :ok (if (and (not (aref refused i))
                      (yeah-result-success-p result))
               t
             :false)
         :payload (yeah-result-model-text result)))
      (setq i (1+ i))))
  (let ((finish (yeah-turn--finish-result calls results)))
    (if finish
        (progn
          ;; `finish' is the model's completion signal: the run ends
          ;; with the summary, the model is not asked again.
          (yeah-events-write (yeah-turn-session turn) "finish"
                             :summary (yeah-result-model-text finish))
          (yeah-turn--tick turn 'tool-end)
          (yeah-turn--tick turn 'budget-ok)
          (yeah-turn--tick turn 'no-tool-calls)
          (yeah-turn--mark-done turn))
      (unless (yeah-turn-done turn)
        (yeah-turn--tick turn 'tool-end)))
    (yeah-turn--maybe-compact turn transport calls results)))

(defun yeah-turn--dispatch-batch (turn answerer calls &optional transport)
  "Dispatch CALLS together, and continue the turn when they have settled."
  (yeah-tools-with-registry (yeah-turn-tools-registry turn)
   (let* ((prepared (yeah-turn--prepare-batch turn answerer calls))
          (split (yeah-turn--split-slots prepared))
          (runnable (car split))
          (results (make-vector (length calls) nil))
          (refused (make-vector (length calls) nil)))
     (dolist (entry (cdr split))
       (aset refused (car entry) t)
       (aset results (car entry) (cdr entry)))
     (cl-incf (yeah-turn-calls turn) (length calls))
     (dolist (slot runnable)
       (let ((name (plist-get slot :name)))
         (unless (member name (yeah-turn-tools-used turn))
           (push name (yeah-turn-tools-used turn)))))
     (let ((yeah-process--current-run-id (yeah-turn-id turn)))
       (yeah-scheduler-run
        (mapcar (lambda (slot) (yeah-turn--call-spec turn slot)) runnable)
        (lambda (settled)
          (yeah-turn--settle-batch turn transport calls runnable
                                    results refused settled)))))))

(defun yeah-turn--answer-text (turn answer transport answerer)
  "Handle a text ANSWER from the model: record it, nudge it or end the run.
A plan, and a result that no tool backs, are nudged into the action; a
result that a tool backs ends the run."
  (yeah-turn--tick turn 'stream-end)
  (yeah-turn--tick turn 'no-tool-calls)
  (yeah-events-write (yeah-turn-session turn) "assistant-message"
                     :payload answer)
  (if (and (< (yeah-turn-nudges turn) (yeah-turn-max-nudges turn))
            (or (yeah-turn--plan-p answer)
                ;; A result that no tool backs is premature: the run
                ;; has not touched anything yet.  And a run that is
                ;; supervised ends through `finish', not through talk.
                (null (yeah-turn-tools-used turn))))
      (progn
        (cl-incf (yeah-turn-nudges turn))
        (let ((nudge (yeah-turn--nudge-text turn)))
          (yeah-events-write (yeah-turn-session turn) "nudge"
                             :payload nudge)
          (setf (yeah-turn-state turn) 'deciding)
          (setf (yeah-turn-states turn)
                (append (yeah-turn-states turn) (list 'deciding)))
          (yeah-turn--ask turn nudge transport answerer)))
    (yeah-turn--mark-done turn)))

(defun yeah-turn--answer (turn answer answerer &optional transport info)
  "Handle the model's ANSWER in TURN. The ANSWERER answers requests."
  (unless (yeah-turn-done turn)
    (when (and (listp info) (plist-get info :yeah-usage))
      (let* ((reported (plist-get info :yeah-usage))
             (input (plist-get reported :input))
             (output (plist-get reported :output)))
        (when (or (numberp input) (numberp output))
          (yeah-events-write (yeah-turn-session turn) "usage"
                             :input (if (numberp input) input 0)
                             :output (if (numberp output) output 0)))
        (let ((usage (yeah-context-usage
                      (yeah-context-project (yeah-turn-session turn)))))
          (yeah-context-calibrate
           (or (plist-get usage :raw-estimated)
               (plist-get usage :estimated))
           info))))
    (cond
     ((stringp answer)
      (if (yeah-loop-transition-p (yeah-turn-state turn) 'stream-end)
          (yeah-turn--answer-text turn answer transport answerer)
        ;; A late answer: the machine is waiting for tools, and this text
        ;; does not belong to the state it is in.  It waits for the tools
        ;; to settle and ends the run then, instead of breaking it.
        (setf (yeah-turn-pending-answer turn) answer)
        nil))
     ((and (consp answer) (memq (car answer) '(reasoning tool-result)))
      ;; Not the answer: the model is still thinking, or the tools were
      ;; run and their results are on their way. The answer comes later.
      nil)
     ((and (consp answer) (eq (car answer) 'tool-call))
      (yeah-turn--tick turn 'stream-end)
      (yeah-turn--tick turn 'tool-call)
      (yeah-turn--dispatch-batch turn answerer (cdr answer) transport))
     ((and (consp answer) (eq (car answer) 'error))
      (yeah-turn--fail turn (format "%s" (cdr answer))))
     (t
      (yeah-turn--fail turn (format "the model answered with %S" answer))))))

(defcustom yeah-turn-plan-regexp
  "\\b\\(I'll\\|I will\\|Let me\\|Now I'll\\|Next I\\|I'm going to\\|I am going to\\)"
  "Regexp matching an answer that only announces the next step.
A model that says `I'll read the file' has not done anything yet.  Such
an answer is a plan, not a result: the run nudges it into the action.
An answer that reports what was done is not a plan and ends the run."
  :type 'string
  :group 'yeah-turn)

(defun yeah-turn--plan-p (answer)
  "Return non-nil when ANSWER only announces the next step."
  (and (stringp answer)
       (not (string-blank-p answer))
       (string-match-p yeah-turn-plan-regexp answer)))

(defun yeah-turn--unused-tools (turn)
  "Return the tools of TURN's registry that this run has not called yet."
  (let* ((registry (yeah-turn-tools-registry turn))
         (names (if registry
                    (yeah-tools-with-registry registry (yeah-tools-names))
                  (yeah-tools-names)))
         (used (yeah-turn-tools-used turn)))
    (seq-remove (lambda (name) (member name used)) names)))

(defun yeah-turn--nudge-text (turn)
  "Return the nudge text for TURN.
The nudge names the tools the run has not called yet: a model that
describes its next step instead of taking it is answered with the step
itself, not with a reminder to continue."
  (let ((unused (yeah-turn--unused-tools turn)))
    (if (null unused)
        yeah-turn-nudge-message
      (format (concat "%s\n\nYou have not called these tools yet: %s. "
                      "Call one of them now, with the arguments it needs, "
                      "or call `finish' with a summary when the task is done "
                      "and verified. "
                      "Do not describe what you are about to do instead of "
                      "doing it.")
              yeah-turn-nudge-message
              (string-join unused ", ")))))

(defun yeah-turn--ask (turn prompt transport answerer)
  "Ask the model PROMPT with TRANSPORT, and continue TURN when it answers.
The ANSWERER is what answers a request for permission."
  (unless (yeah-turn-done turn)
    (setf (yeah-turn-transport turn) transport
          (yeah-turn-answerer turn) answerer)
    (when (eq (yeah-turn-state turn) 'idle)
      (yeah-turn--tick turn 'user-prompt))
    (cl-incf (yeah-turn-turns turn))
    (yeah-events-write (yeah-turn-session turn) "user-message"
                       :payload prompt)
    (setf (yeah-turn-model-fsm turn)
          (yeah-tools-with-registry (yeah-turn-tools-registry turn)
            (funcall transport prompt
                     (lambda (answer &optional info)
                       (yeah-turn--answer turn answer answerer transport info)))))))

;;;###autoload
(defun yeah-turn-cancel (turn &optional reason)
  "Cancel TURN and its managed processes, ignoring later callbacks.
Return non-nil when an active run was cancelled.  This does not roll back
completed effects or guarantee termination of process descendants."
  (unless (yeah-turn-done turn)
    (setf (yeah-turn-cancelled turn) t)
    (yeah-events-write (yeah-turn-session turn) "cancel"
                       :payload (or reason "cancelled by user"))
    (yeah-turn--mark-done turn 'interrupted)
    (when-let ((fsm (yeah-turn-model-fsm turn)))
      (when (and (fboundp 'gptel-fsm-info) (fboundp 'gptel-abort))
        (let ((buffer (plist-get (gptel-fsm-info fsm) :buffer)))
          (when (buffer-live-p buffer)
            (gptel-abort buffer)))))
    (when (yeah-turn-id turn)
      (yeah-process-cancel-run (yeah-turn-id turn)))
    t))

(defvar yeah-turn--next-id 0
  "Monotonic suffix for run identifiers.")

(defun yeah-turn--fresh-id ()
  "Return a new run identifier."
  (setq yeah-turn--next-id (1+ yeah-turn--next-id))
  (format "run-%d" yeah-turn--next-id))

;;;###autoload
(defun yeah-turn-run (session prompt &optional transport answerer budget
                              max-nudges on-done steer-source input deadline
                              registry)
  "Run the agent loop over SESSION with PROMPT and optional context BUDGET.
MAX-NUDGES bounds completion supervision.  ON-DONE is called once at a
terminal state.  STEER-SOURCE returns pending steering inputs for a batch.
INPUT is the frozen input plist captured at submission.  DEADLINE is an
optional whole-run timeout in seconds and is cancelled at terminal states.
REGISTRY is the registry snapshot of this run (from `yeah-tools-snapshot');
nil uses the shared registry."
  (let ((transport (or transport
                      (and (fboundp 'yeah-gptel-request) #'yeah-gptel-request)))
        (answerer (or answerer #'yeah-approval-policy-decision)))
    (unless transport
      (signal 'user-error
              (list "yeah-turn-run: no transport: gptel is not loaded and no \
transport was given")))
    (let ((turn (yeah-turn--make
                 :session session
                 :budget (or budget yeah-context-default-budget)
                 :id (or (plist-get input :id) (yeah-turn--fresh-id))
                 :max-nudges (or max-nudges yeah-turn-default-max-nudges)
                 :on-done on-done
                 :steer-source steer-source
                 :input input
                 :tools-registry registry
                 :pending-permissions (make-hash-table :test 'equal))))
      (when deadline
        (unless (and (numberp deadline) (> deadline 0))
          (signal 'user-error
                  (list "yeah-turn-run: deadline must be positive seconds")))
        (setf (yeah-turn-deadline-timer turn)
              (run-at-time deadline nil
                           (lambda ()
                             (yeah-turn-cancel turn "deadline exceeded")))))
      (yeah-turn--ask turn prompt transport answerer)
      turn)))

(provide 'yeah-turn)
;;; yeah-turn.el ends here
