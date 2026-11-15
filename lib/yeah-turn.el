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
shared one.  WORK-STATE holds what the tools of this run have done, the
newest result first: the nudge that follows a silence of the model carries
it, so that the model continues instead of starting the work over.

PENDING-CALLS holds the tool calls that arrived while another batch was
running, in the order they arrived.  PENDING-RESULTS holds the batches that
have settled and whose results the model has not seen yet.  ACTIVE-KEYS holds
the keys of the calls that run or wait to run, so that the same call is never
run twice."
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
  (work-state nil)
  (transport nil)
  (answerer nil)
  (pending-answer nil)
  (pending-calls nil)
  (pending-results nil)
  (active-keys nil)
  (pending-permissions nil)
  (permissions 0)
  (settlements nil)
  (turn-event-id nil))

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
  ;; A question that is still waiting for its answer ends with the run:
  ;; an answer that arrives after this is ignored.
  (dolist (close (yeah-turn-settlements turn))
    (funcall close))
  (setf (yeah-turn-settlements turn) nil)
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

(defun yeah-turn--context (turn &optional tool-call-id parent-event-id)
  "Return explicit journal correlation for TURN and its current model turn."
  (append
   (list :run_id (yeah-turn-id turn)
         :turn_id (format "%s-turn-%d" (yeah-turn-id turn)
                          (max 1 (yeah-turn-turns turn))))
   (when tool-call-id
     (list :tool_call_id tool-call-id))
   (when parent-event-id
     (list :parent_event_id parent-event-id))))

(defun yeah-turn--write (turn type context &rest fields)
  "Write TYPE with FIELDS and explicit CONTEXT for TURN."
  (apply #'yeah-events-write-with-context
         (yeah-turn-session turn) type context fields))

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
    (yeah-turn--write turn "error"
                      (yeah-turn--context turn nil (yeah-turn-turn-event-id turn))
                      :payload reason))
  reason)

(defun yeah-turn-resume-permission (turn request-id decision)
  "Answer the deferred permission request REQUEST-ID of TURN with DECISION.
The first answer wins; a cancelled turn ignores a late answer."
  (when-let ((resume (gethash request-id (yeah-turn-pending-permissions turn))))
    (remhash request-id (yeah-turn-pending-permissions turn))
    (unless (yeah-turn-done turn)
      (funcall resume decision))))

(defun yeah-turn--fresh-permission-id (turn)
  "Return a fresh id for a question that waits for an answer."
  (cl-incf (yeah-turn-permissions turn))
  (format "%s-perm-%d" (yeah-turn-id turn) (yeah-turn-permissions turn)))

(defun yeah-turn--decision-of (decision name)
  "Return the (EFFECT DETAIL REPLY) of DECISION about the tool NAME.
A decision that defers is a deferral; a decision that allows says why it
needed no question; every other decision is a refusal that says why."
  (if (plist-get decision :defer)
      (list "defer" (plist-get decision :defer) nil)
    (if (eq (plist-get decision :effect) :allow)
        (list "allow" (plist-get decision :reason)
              (plist-get decision :reply))
      (list "deny" (or (plist-get decision :reason)
                       (format "the rules say %s" name))
            nil))))

(defun yeah-turn--decide (turn slot answerer)
  "Ask ANSWERER whether the tool of SLOT may run.
Return (EFFECT DETAIL REPLY): EFFECT is allow, deny or defer, DETAIL is the
reason of the decision (the question that waits for the person when the
effect is defer), and REPLY is what the person answered (`:once' or
`:always').

An answerer marked by `yeah-approval-async' answers later: the effect is
defer and the detail is the id of the question that waits."
  (let ((name (plist-get slot :name))
        (spec (plist-get slot :spec)))
    (cond
     ((null spec)
      (list "deny" (format "there is no tool named %s" name) nil))
     ((equal name "finish")
      (list "allow" nil nil))
     ((yeah-approval-async-answerer-p answerer)
      (yeah-turn--ask-later turn slot answerer))
     (t
      (yeah-turn--decision-of
       (funcall answerer
                (yeah-approval-request
                 name (plist-get slot :resource)
                 (plist-get slot :args)
                 (plist-get slot :tool-call-id)))
       name)))))

(defun yeah-turn--write-decision (turn slot effect reply reason &optional parent)
  "Write the permission decision of SLOT into the log and return its id.
EFFECT is allow, deny or defer; REPLY is what the person answered and
REASON the reason of the decision.  PARENT is the event the decision
belongs to; it is the permission request unless the decision answers an
earlier deferral."
  (apply #'yeah-turn--write
         turn "permission-decision"
         (yeah-turn--context
          turn (plist-get slot :tool-call-id)
          (or parent (plist-get slot :permission-request-event-id)))
         (yeah-turn--decision-fields
          (plist-get slot :name)
          (plist-get slot :resource)
          effect reply reason)))

(defun yeah-turn--ask-later (turn slot answerer)
  "Ask the ANSWERER that answers later whether the tool of SLOT may run.
The answer arrives whenever it arrives: the question waits under a fresh
id and the tool waits with it.  Return the deferral of the question."
  (let ((request-id (yeah-turn--fresh-permission-id turn))
        (answer nil)
        (resume nil))
    (push (yeah-approval-resolve
           answerer
           (yeah-approval-request
            (plist-get slot :name)
            (plist-get slot :resource)
            (plist-get slot :args)
            (plist-get slot :tool-call-id))
           (lambda (decision)
             (if resume
                 (funcall resume decision)
               (setq answer decision))))
          (yeah-turn-settlements turn))
    (if answer
        ;; The answer came before the question was written down: it is an
        ;; ordinary answer, not a deferral.
        (yeah-turn--decision-of answer (plist-get slot :name))
      (progn
        (setq resume
              (lambda (decision)
                (yeah-turn-resume-permission turn request-id decision)))
        (list "defer" request-id nil)))))

(defun yeah-turn--answer-permission (turn slot decision)
  "Answer the deferred question of SLOT with DECISION.
The first answer wins: the decision is written into the log, and the tool
runs only when the answer allows it.  An answer that comes after the turn
ended is ignored, and an answer that is not a decision is a refusal."
  (unless (or (yeah-turn-done turn) (plist-get slot :answered))
    (unless (and (listp decision)
                 (or (plist-get decision :effect) (plist-get decision :defer)))
      (setq decision (list :effect :deny :reply :reject
                           :reason "the answer is not a decision")))
    (when (plist-get decision :defer)
      ;; The question waits again, but nobody is left to answer it.
      (setq decision (list :effect :deny :reply :reject
                           :reason "the question was deferred again")))
    (setf (plist-get slot :answered) t)
    (setf (plist-get slot :answer) decision)
    (yeah-turn--write-decision
     turn slot
     (if (eq (plist-get decision :effect) :allow) "allow" "deny")
     (plist-get decision :reply)
     (plist-get decision :reason)
     (plist-get slot :decision-event-id))
    (when-let ((done (plist-get slot :continuation)))
      (yeah-turn--run-or-refuse turn slot done decision))))

(defun yeah-turn--run-or-refuse (turn slot done decision)
  "Run the tool of SLOT when DECISION allows it, and refuse it otherwise.
DONE is the continuation of the tool call."
  (unless (yeah-turn-done turn)
    (if (eq (plist-get decision :effect) :allow)
        (yeah-tools-dispatch (plist-get slot :name)
                             (plist-get slot :args) done)
      (funcall done
               (yeah-result-error
                (or (plist-get decision :reason)
                    "the person refused"))))))

(defun yeah-turn--prepare-slot (turn index call)
  "Prepare the slot of CALL at INDEX and write its request into the log.
The question is not asked here: the request is in the log before anyone is
asked, so that an answer which comes later still finds it there.  The
returned slot owns stable ids shared by request, permission and tool-end."
  (let* ((name (yeah-turn--tool-name (nth 0 call)))
         (args (yeah-tools-normalize-args name (nth 1 call)))
         (spec (yeah-tools-get name))
         (resource (yeah-turn--resource args))
         (tool-call-id (format "%s-call-%d" (yeah-turn-id turn)
                               (+ (yeah-turn-calls turn) index 1)))
         (request-event-id
          (yeah-turn--write turn "tool-request"
                            (yeah-turn--context
                             turn tool-call-id (yeah-turn-turn-event-id turn))
                            :tool name :args (format "%S" args)))
         (permission-event-id
          (yeah-turn--write turn "permission-request"
                            (yeah-turn--context turn tool-call-id request-event-id)
                            :action name :resource resource
                            :arguments (yeah-turn--arguments args)))
         (slot (list :index index :name name :args args :spec spec
                     :resource resource :tool-call-id tool-call-id
                     :request-event-id request-event-id
                     :permission-request-event-id permission-event-id
                     :answered nil :answer nil :continuation nil)))
    (plist-put slot :resume
               (lambda (decision)
                 (yeah-turn--answer-permission turn slot decision)))
    slot))

(defun yeah-turn--prepare (turn answerer index call)
  "Prepare CALL at INDEX.
The request is written into the log before the question is asked, so that
an answer which comes later still finds the request there.  The returned
slot owns stable ids shared by request, permission and tool-end."
  (let* ((slot (yeah-turn--prepare-slot turn index call))
         (decision (yeah-turn--decide turn slot answerer))
         (effect (nth 0 decision))
         (detail (nth 1 decision))
         (reply (nth 2 decision)))
    (when (equal "defer" effect)
      ;; The question waits for an answer.  It is registered before the
      ;; tool starts, so that the answer finds it whenever it arrives.
      (puthash detail (plist-get slot :resume)
               (yeah-turn-pending-permissions turn)))
    (let ((decision-event-id
           (yeah-turn--write-decision
            turn slot effect reply
            (and (not (equal "defer" effect)) detail))))
      (plist-put slot :decision-event-id decision-event-id)
      (plist-put slot :refused (and (equal "deny" effect) detail))
      (plist-put slot :deferred (and (equal "defer" effect) detail))
      slot)))

(defun yeah-turn--arguments (args)
  "Return the JSON-safe arguments of a tool call."
  (apply #'vector (mapcar #'yeah-result-json-safe args)))

(defun yeah-turn--reply-name (reply)
  "Return the journal name of the answer REPLY.
The journal is JSON: a keyword or a symbol becomes its name."
  (cond ((null reply) nil)
        ((stringp reply) reply)
        ((symbolp reply) (symbol-name reply))
        (t (format "%S" reply))))

(defun yeah-turn--decision-fields (name resource effect reply reason)
  "Return the fields of the permission decision of a call.
REPLY is the answer of the person and REASON the reason of the decision;
both are left out when there is nothing to say."
  (let ((fields (list :action name :resource resource :effect effect)))
    (when reply (plist-put fields :reply (yeah-turn--reply-name reply)))
    (when reason (plist-put fields :reason reason))
    fields))

(defun yeah-turn--call-key (call)
  "Return the key that identifies CALL: its tool and its arguments.
Two calls with the same key ask for the same work; running one of them
twice would repeat a side effect."
  (list (yeah-turn--tool-name (nth 0 call))
        (nth 1 call)))

(defun yeah-turn--accept-calls (turn calls)
  "Accept CALLS into TURN and return the calls that are not running yet.
A call that already runs or already waits to run is dropped: the model
said it twice, and the second saying changes nothing.  The drop is in the
journal, so that a reader of the log can tell a repeated decision from a
decision that never came."
  (let (new)
    (dolist (call calls)
      (let ((key (yeah-turn--call-key call))
            (accepted nil))
        (unless (cl-member key (yeah-turn-active-keys turn) :test #'equal)
          (setq accepted t)
          (push call new)
          (push key (yeah-turn-active-keys turn)))
        ;; The model said the same thing twice.  The tool runs once, and the
        ;; second saying is in the log: a reader of the log must be able to
        ;; tell it from a decision that never came.
        (unless accepted
          (yeah-turn--note-drop turn call))))
    (nreverse new)))

(defun yeah-turn--note-drop (turn call)
  "Write into the log of TURN that CALL was dropped as a repeat.
The arguments are the arguments of the call that runs, and they are written
in the form the request of that call was written, so that a reader of the
journal matches the drop with the request it refuses."
  (when (yeah-turn-session turn)
    (let* ((name (yeah-turn--tool-name (nth 0 call)))
           (args (yeah-tools-normalize-args name (nth 1 call))))
      (yeah-turn--write turn "tool-dropped"
                        (yeah-turn--context
                         turn nil (yeah-turn-turn-event-id turn))
                        :tool name
                        :reason "the same call is already running"
                        :args (format "%S" args)))))

(defun yeah-turn--release-calls (turn calls)
  "Forget the keys of CALLS: they have settled and may run again."
  (dolist (call calls)
    (let ((key (yeah-turn--call-key call)))
      (setf (yeah-turn-active-keys turn)
            (cl-delete key (yeah-turn-active-keys turn) :test #'equal)))))

(defun yeah-turn--take-results (turn)
  "Return the batches of TURN that have settled, and forget them."
  (let ((batches (reverse (yeah-turn-pending-results turn))))
    (setf (yeah-turn-pending-results turn) nil)
    batches))

(defun yeah-turn--take-calls (turn answerer transport calls)
  "Take the tool calls CALLS that a response of the model brought.
A batch that arrives while the turn is deciding runs at once.  A batch
that arrives while another one is running waits: the calls that are not
running yet are kept, and they run when the running batch has settled.
The turn is not broken by such a decision: the machine has no transition
for a decision that arrives while the tools run, and the decision is not
lost either."
  (let ((new (yeah-turn--accept-calls turn calls)))
    (cond
     ((null new)
      nil)
     ((eq (yeah-turn-state turn) 'deciding)
      (yeah-turn--tick turn 'stream-end)
      (yeah-turn--tick turn 'tool-call)
      (yeah-turn--dispatch-batch turn answerer new transport))
     (t
      (setf (yeah-turn-pending-calls turn)
            (append (yeah-turn-pending-calls turn) (list new)))
      nil))))

(defun yeah-turn--dispatch-next (turn transport)
  "Dispatch the next batch of calls that waits in TURN."
  (let ((calls (car (yeah-turn-pending-calls turn))))
    (setf (yeah-turn-pending-calls turn)
          (cdr (yeah-turn-pending-calls turn)))
    (yeah-turn--dispatch-batch turn (yeah-turn-answerer turn) calls transport)))

(defun yeah-turn--deliver-results (batches steering)
  "Deliver the results of BATCHES to the model of the turn.
STEERING is what the person said while the tools ran; it rides with the
first result."
  (let ((batch-index 0)
        (clarification
         (mapconcat (lambda (input)
                      (concat "\n\nUser clarification: "
                              (plist-get input :prompt)))
                    steering "")))
    (dolist (batch batches)
      (let ((calls (car batch))
            (results (cdr batch))
            (index 0))
        (dolist (call calls)
          (let ((continue (nth 2 call))
                (value (concat (yeah-result-model-text (aref results index))
                               (if (zerop batch-index) clarification ""))))
            (when continue
              (funcall continue value)))
          (setq index (1+ index)))
        (setq batch-index (1+ batch-index))))))

(defun yeah-turn--continue-batch (turn)
  "Continue TURN after the tools it dispatched have settled.
The results of every batch that has settled are delivered to the model
together: the model continues when all of them are known.  Steering is
delivered only after the entire batch has settled."
  (unless (yeah-turn-done turn)
    (let ((steering (and (functionp (yeah-turn-steer-source turn))
                         (funcall (yeah-turn-steer-source turn) turn))))
      (dolist (input steering)
        (yeah-turn--write turn "steering"
                          (yeah-turn--context
                           turn nil (yeah-turn-turn-event-id turn))
                          :payload (plist-get input :prompt)))
      (pcase (yeah-turn-state turn)
        ('accumulating (yeah-turn--tick turn 'budget-ok))
        ('compacting (yeah-turn--tick turn 'compact-done)))
      (yeah-turn--tick turn 'continue)
      (let ((answered nil)
            (pending (yeah-turn-pending-answer turn)))
        (when pending
          ;; The model already said its last word while the tools were
          ;; running.  That answer ends the run now; asking again would
          ;; only repeat it.
          (setf (yeah-turn-pending-answer turn) nil)
          (setq answered t)
          (yeah-turn--answer-text
           turn pending (yeah-turn-transport turn) (yeah-turn-answerer turn)))
        (cond
         (answered
          ;; The run ends with the answer of the model; the results of the
          ;; tools are of no use to anybody now.
          (setf (yeah-turn-pending-results turn) nil))
         ((yeah-turn-pending-calls turn)
          ;; A decision arrived while the results were being prepared: it
          ;; runs now, and the results of every batch reach the model
          ;; together.
          (yeah-turn--tick turn 'stream-end)
          (yeah-turn--tick turn 'tool-call)
          (yeah-turn--dispatch-next turn (yeah-turn-transport turn)))
         (t
          (yeah-turn--deliver-results (yeah-turn--take-results turn) steering)))))))

(defun yeah-turn--maybe-compact (turn transport)
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
               (yeah-turn--continue-batch turn))))
         (lambda () (not (yeah-turn-done turn)))))
    (yeah-turn--continue-batch turn)))

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
person allowed it.  An answer that arrived before the tool started is
applied at once."
  (lambda (args &optional done)
    (unless (yeah-turn-done turn)
      (if (plist-get slot :deferred)
          (if (plist-get slot :answered)
              (yeah-turn--run-or-refuse turn slot done (plist-get slot :answer))
            (setf (plist-get slot :continuation) done))
        (yeah-tools-dispatch (plist-get slot :name) args done)))))

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

(defun yeah-turn--settle-batch (turn transport calls prepared runnable
                                      results refused settled)
  "Record the settled batch of TURN and continue it in CALLS request order.
PREPARED supplies stable ids and structured result details for every tool-end.
A batch that arrived while this one was running runs now, and the model sees
the results of every batch together."
  (let ((i 0))
    (dolist (slot runnable)
      (aset results (plist-get slot :index) (aref settled i))
      (setq i (1+ i))))
  (dolist (slot prepared)
    (let* ((index (plist-get slot :index))
           (result (aref results index))
           (fields
            (list :tool (plist-get slot :name)
                  :ok (if (and (not (aref refused index))
                               (yeah-result-success-p result))
                          t
                        :false)
                  :payload (yeah-result-model-text result)))
           (details (yeah-result-details result)))
      (when details
        (setq fields (append fields (list :details details))))
      (apply #'yeah-turn--write
             turn "tool-end"
             (yeah-turn--context
              turn (plist-get slot :tool-call-id)
              (plist-get slot :request-event-id))
             fields)
      (yeah-turn--remember-work turn (plist-get slot :name) result)))
  (yeah-turn--release-calls turn calls)
  (setf (yeah-turn-pending-results turn)
        (append (yeah-turn-pending-results turn) (list (cons calls results))))
  (let ((finish (yeah-turn--finish-result calls results)))
    (cond
     (finish
      (let ((finish-slot
             (cl-find-if (lambda (slot)
                           (equal "finish" (plist-get slot :name)))
                         prepared)))
        (yeah-turn--write
         turn "finish"
         (if finish-slot
             (yeah-turn--context
              turn (plist-get finish-slot :tool-call-id)
              (plist-get finish-slot :request-event-id))
           (yeah-turn--context turn nil (yeah-turn-turn-event-id turn)))
         :summary (yeah-result-model-text finish))
        (yeah-turn--tick turn 'tool-end)
        (yeah-turn--tick turn 'budget-ok)
        (yeah-turn--tick turn 'no-tool-calls)
        (yeah-turn--mark-done turn)))
     ((yeah-turn-pending-calls turn)
      ;; A batch that arrived while this one was running waits no longer:
      ;; it runs now.  The state stays `awaiting-tool', and the results of
      ;; both batches reach the model together.
      (yeah-turn--dispatch-next turn transport))
     (t
      (unless (yeah-turn-done turn)
        (yeah-turn--tick turn 'tool-end))
      (yeah-turn--maybe-compact turn transport)))))

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
          (yeah-turn--settle-batch turn transport calls prepared runnable
                                    results refused settled)))))))

(defun yeah-turn--answer-text (turn answer transport answerer)
  "Handle a text ANSWER from the model: record it, nudge it or end the run.
A plan, an answer that says nothing, and a result that no tool backs, are
nudged into the action; a result that a tool backs ends the run."
  (yeah-turn--write turn "assistant-message"
                    (yeah-turn--context
                     turn nil (yeah-turn-turn-event-id turn))
                    :payload answer)
  (if (and (yeah-turn--silent-p answer)
           (= (yeah-turn-max-nudges turn) 0))
      ;; Without supervision there is no nudge to give, and an answer that
      ;; says nothing is no answer at all: the run fails instead of ending
      ;; as if the work were done.
      (yeah-turn--fail turn
                       "the model answered with an empty message and the run is not done")
    (progn
      (yeah-turn--tick turn 'stream-end)
      (yeah-turn--tick turn 'no-tool-calls)
      (if (and (< (yeah-turn-nudges turn) (yeah-turn-max-nudges turn))
                (or (yeah-turn--plan-p answer)
                    ;; An answer that says nothing is not a result: the
                    ;; model has not advanced, and the run nudges it into
                    ;; the action instead of taking the silence for the
                    ;; work.
                    (yeah-turn--silent-p answer)
                    ;; A result that no tool backs is premature: the run
                    ;; has not touched anything yet.  And a run that is
                    ;; supervised ends through `finish', not through talk.
                    (null (yeah-turn-tools-used turn))))
          (progn
            (cl-incf (yeah-turn-nudges turn))
            (let ((nudge (yeah-turn--nudge-text turn answer)))
              (yeah-turn--write turn "nudge"
                                (yeah-turn--context
                                 turn nil (yeah-turn-turn-event-id turn))
                                :payload nudge)
              (setf (yeah-turn-state turn) 'deciding)
              (setf (yeah-turn-states turn)
                    (append (yeah-turn-states turn) (list 'deciding)))
              (yeah-turn--ask turn nudge transport answerer)))
        (progn
          ;; A supervised run that ends without the model finishing must
          ;; say so: the nudge budget is spent and the model still
          ;; describes its next step.  Ending as if it were done would be
          ;; a false success.
          (when (and (> (yeah-turn-max-nudges turn) 0)
                     (or (yeah-turn--plan-p answer)
                         (yeah-turn--silent-p answer)
                         (null (yeah-turn-tools-used turn))))
            (yeah-turn--write turn "unfinished"
                              (yeah-turn--context
                               turn nil (yeah-turn-turn-event-id turn))
                              :payload (if (yeah-turn--silent-p answer)
                                           (format "the model answered with an empty message %d times and the run ended without an effect"
                                                   (yeah-turn-nudges turn))
                                         (format "the model described its next step %d times and the run ended without an effect"
                                                 (yeah-turn-nudges turn)))
                              :reason "the nudge budget was spent"))
          (yeah-turn--mark-done turn))))))

(defun yeah-turn--answer (turn answer answerer &optional transport info)
  "Handle the model's ANSWER in TURN. The ANSWERER answers requests."
  (unless (yeah-turn-done turn)
    (when (and (listp info) (plist-get info :yeah-usage))
      (let* ((reported (plist-get info :yeah-usage))
             (input (plist-get reported :input))
             (output (plist-get reported :output)))
        (when (or (numberp input) (numberp output))
          (yeah-turn--write turn "usage"
                            (yeah-turn--context
                             turn nil (yeah-turn-turn-event-id turn))
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
      (yeah-turn--take-calls turn answerer transport (cdr answer)))
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

(defun yeah-turn--silent-p (answer)
  "Return non-nil when ANSWER says nothing at all.
An empty answer is not a result: the model has not advanced, and a run that
takes it for a result ends without the effect and looks done."
  (and (stringp answer)
       (string-blank-p answer)))

(defun yeah-turn--unused-tools (turn)
  "Return the tools of TURN's registry that this run has not called yet."
  (let* ((registry (yeah-turn-tools-registry turn))
         (names (if registry
                    (yeah-tools-with-registry registry (yeah-tools-names))
                  (yeah-tools-names)))
         (used (yeah-turn-tools-used turn)))
    (seq-remove (lambda (name) (member name used)) names)))

(defconst yeah-turn--work-state-limit 3
  "How many results of the tools the nudge that follows a silence carries.
Three results are enough to show what the run has done; more of them would
crowd out the instruction to continue.")

(defun yeah-turn--remember-work (turn name result)
  "Remember that the tool NAME of TURN returned RESULT.
The state of the work is what the nudge that follows a silence of the model
carries: a model that is told to call a tool it has already called starts
the work over."
  (push (cons name (yeah-result-model-text result))
        (yeah-turn-work-state turn))
  (setf (yeah-turn-work-state turn)
        (nthcdr (max 0 (- (length (yeah-turn-work-state turn))
                           yeah-turn--work-state-limit))
                (yeah-turn-work-state turn))))

(defun yeah-turn--shorten (text)
  "Return TEXT cut to a length that a nudge can carry."
  (if (and (stringp text) (> (length text) 400))
      (concat (substring text 0 400) " [...]")
    (or text "")))

(defun yeah-turn--work-state-text (turn)
  "Return the text that tells the model what this run has already done."
  (let ((state (yeah-turn-work-state turn)))
    (if (null state)
        ""
      (concat "You have already called these tools, with these results:\n"
              (mapconcat
               (lambda (entry)
                 (format "  %s -> %s" (car entry)
                         (yeah-turn--shorten (cdr entry))))
               state
               "\n")
              "\n"))))

(defconst yeah-turn--path-regexp
  "\\(?:[A-Za-z0-9_.-]+/\\)?[A-Za-z0-9_.-]+\\.[A-Za-z0-9_]+\\b"
  "Regexp matching a file name in an answer of the model.")

(defun yeah-turn--answer-path (answer)
  "Return the file name the model names in ANSWER, or nil.
Used to name the exact call a narration nudge should ask for."
  (and (stringp answer)
       (let ((case-fold-search nil))
         (when (string-match yeah-turn--path-regexp answer)
           (match-string 0 answer)))))

(defun yeah-turn--unused-path-tool (turn)
  "Return the first tool of TURN that the run has not called and that
takes a path argument, or nil.  The narration nudge names this tool
because it is the cheapest safe way to touch the project for real."
  (let* ((registry (yeah-turn-tools-registry turn))
         (unused (yeah-turn--unused-tools turn)))
    (seq-find
     (lambda (name)
       (let ((spec (if registry
                       (yeah-tools-with-registry registry
                         (yeah-tools-get name))
                     (yeah-tools-get name))))
         (and spec
              (seq-some (lambda (arg)
                          (and (listp arg)
                               (member (plist-get arg :name)
                                       '("path" "file" "directory" "pattern"))))
                        (plist-get spec :input)))))
     unused)))

(defun yeah-turn--nudge-text (turn &optional answer)
  "Return the nudge text for TURN after the model answered ANSWER.
The nudge names the tools the run has not called yet and, when one of
them takes a path, the exact call to make: a model that describes its
next step is answered with the step itself, and a second nudge says
that the next answer must contain the call, not a plan.

A silence is not a plan: the model said nothing, and the run does not
know what it meant to do next.  The nudge of a silence carries the state
of the work instead — the tools the run called and what they returned —
and it does not name an unused tool as the next call, because a model
that is told to repeat a call starts the work over."
  (if (yeah-turn--silent-p answer)
      (concat "Your last answer was empty: you have said nothing, and the task is not done.\n\n"
              (yeah-turn--work-state-text turn)
              (concat "Continue the work from there: do not repeat the calls you have "
                      "already made with the same arguments. "
                      "When the work is done, call `finish' with a summary.\n\n"))
    (let* ((unused (yeah-turn--unused-tools turn))
           (tool (yeah-turn--unused-path-tool turn))
           (path (yeah-turn--answer-path answer))
           (repeated (> (yeah-turn-nudges turn) 1)))
      (concat
       (when repeated
         "You have already been asked to act: your next answer must contain the tool call, not a plan.\n\n")
       (if (null unused)
           yeah-turn-nudge-message
         (format (concat "%s\n\nYou have not called these tools yet: %s. "
                         "Call one of them now, with the arguments it needs, "
                         "or call `finish' with a summary when the task is done "
                         "and verified. "
                         "Do not describe what you are about to do instead of "
                         "doing it.")
                 yeah-turn-nudge-message
                 (string-join unused ", ")))
       (cond
        ((and tool path)
         (format (concat "\n\nMake this call now: `%s' on %s. "
                         "Your next answer must be the tool call, not a plan.")
                 tool path))
        (tool
         (format (concat "\n\nMake this call now: `%s', with the `path' argument. "
                         "Your next answer must be the tool call, not a plan.")
                 tool))
        (t ""))))))

(defun yeah-turn--ask (turn prompt transport answerer)
  "Ask the model PROMPT with TRANSPORT, and continue TURN when it answers.
The ANSWERER is what answers a request for permission."
  (unless (yeah-turn-done turn)
    (setf (yeah-turn-transport turn) transport
          (yeah-turn-answerer turn) answerer)
    (when (eq (yeah-turn-state turn) 'idle)
      (yeah-turn--tick turn 'user-prompt))
    (cl-incf (yeah-turn-turns turn))
    (setf (yeah-turn-turn-event-id turn)
          (yeah-turn--write turn "user-message" (yeah-turn--context turn)
                            :payload prompt))
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
    (yeah-turn--write turn "cancel"
                      (yeah-turn--context
                       turn nil (yeah-turn-turn-event-id turn))
                      :payload (or reason "cancelled by user"))
    (when-let ((pending (yeah-turn-pending-permissions turn)))
      (clrhash pending))
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
