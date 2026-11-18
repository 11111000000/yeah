;;; yeah-control.el --- queued human control of agent runs -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; A controller owns one session's active turn and persistent pending FIFO.
;; Inputs carry frozen configuration captured at submission.  Steering is
;; consumed only at tool-batch boundaries.  Loading pending work never starts
;; a model request; recovery is always explicit.
;;
;; The pending queue is written into the journal as it changes: an input that
;; enters the queue, starts a run, is recovered or is withdrawn is named in
;; the log by its id.  The editor's view of the queue is therefore a
;; projection of the records and not a second, invisible state.

;;; Code:

(require 'cl-lib)
(require 'yeah-turn)
(require 'yeah-events)
(require 'yeah-input)
(require 'yeah-tools)

(cl-defstruct (yeah-control (:constructor yeah-control--make))
  "Runtime control state for one session."
  session
  transport
  answerer
  budget
  max-nudges
  frozen-defaults
  tools
  active-turn
  completion-listeners)

(defun yeah-control-new (session &optional transport answerer budget max-nudges frozen tools)
  "Return a controller for SESSION without starting any work.
TRANSPORT, ANSWERER, BUDGET and MAX-NUDGES are frozen for subsequent inputs.
FROZEN is additional serializable configuration recorded with each input.
TOOLS are the tools of the session that the shared registry does not
hold: the tools of the MCP servers the client named.  They belong to
the runs of this session and to no other run."
  (yeah-control--make
   :session session
   :transport (or transport
                  (and (fboundp 'yeah-gptel-request) #'yeah-gptel-request))
   :answerer (or answerer #'yeah-approval-policy-decision)
   :budget (or budget yeah-context-default-budget)
   :max-nudges (or max-nudges yeah-turn-default-max-nudges)
   :frozen-defaults frozen
   :tools tools
   :completion-listeners (make-hash-table :test 'equal)))

(defun yeah-control--registry (control)
  "Return the registry snapshot of a run of CONTROL, or nil.
The tools of the session are the tools of the registry of its runs: a
session that named MCP servers has their tools, and the model sees them
among the others.  The snapshot is a copy of the shared registry, so
the tools of this session do not leak into the runs of the other
sessions."
  (let ((tools (yeah-control-tools control)))
    (when tools
      (let ((snapshot (yeah-tools-snapshot)))
        (yeah-tools-with-registry snapshot
          (dolist (spec tools)
            (unless (yeah-tools-get (plist-get spec :name))
              (yeah-tools-register spec))))
        snapshot))))

(defun yeah-control--frozen (control kind prompt frozen)
  "Build a new KIND input for PROMPT with FROZEN configuration."
  (list :kind kind
        :prompt prompt
        :frozen (append (list :budget (yeah-control-budget control)
                              :max-nudges (yeah-control-max-nudges control)
                              :submitted-at (time-to-seconds))
                        (yeah-control-frozen-defaults control)
                        frozen)))

(defun yeah-control--steering-batch (control)
  "Pop all currently queued steering inputs from CONTROL.
Ordinary asks retain their FIFO positions.

The batch itself writes nothing into the journal: the caller says what
happened to the inputs — delivered to a run, or withdrawn with it."
  (let ((inputs nil))
    (dolist (input (yeah-input-pending (yeah-control-session control)))
      (when (eq 'steering (plist-get input :kind))
        (let ((taken (yeah-input-withdraw (yeah-control-session control)
                                          (plist-get input :id))))
          (when taken
            (push taken inputs)))))
    (nreverse inputs)))

(defun yeah-control--deliver-steering (control)
  "Return the steering of CONTROL that a running turn may take now.
The inputs leave the queue because a run takes them: the journal says
`input-taken' for each of them."
  (mapc (lambda (input) (yeah-control--write-taken control input))
        (yeah-control--steering-batch control)))

(defun yeah-control--journal-kind (input)
  "Return the kind of INPUT as the string the journal holds."
  (format "%s" (or (plist-get input :kind) 'ask)))

(defun yeah-control--write-queued (control input)
  "Write the `input-queued' event of INPUT into the journal of CONTROL.
The frozen configuration of the input belongs to the event.  A frozen
configuration the journal cannot represent is left out of it: the queue
event still tells the truth about the queue, and the run it belongs to
must not stop because of it."
  (let* ((session (yeah-control-session control))
         (fields (list :input_id (plist-get input :id)
                       :input_kind (yeah-control--journal-kind input)
                       :prompt (plist-get input :prompt)))
         (frozen (plist-get input :frozen)))
    (if frozen
        (condition-case nil
            (apply #'yeah-events-write session "input-queued"
                   (append fields (list :frozen frozen)))
          (error
           (apply #'yeah-events-write session "input-queued" fields)))
      (apply #'yeah-events-write session "input-queued" fields))))

(defun yeah-control--write-taken (control input &optional recovered)
  "Write the `input-taken' event of INPUT into the journal of CONTROL.
A RECOVERED input was started explicitly by the person, after a restart
or a cancellation: the journal then says `input-recovered'."
  (yeah-events-write (yeah-control-session control)
                     (if recovered "input-recovered" "input-taken")
                     :input_id (plist-get input :id)
                     :input_kind (yeah-control--journal-kind input)))

(defun yeah-control--write-withdrawn (control input reason)
  "Write the `input-withdrawn' event of INPUT into the journal of CONTROL.
REASON says why the input left the queue.  The id of the input is part of
the event: a withdrawn input must leave the pending list of the editor."
  (yeah-events-write (yeah-control-session control) "input-withdrawn"
                     :input_id (plist-get input :id)
                     :kind (yeah-control--journal-kind input)
                     :reason reason))

(defun yeah-control--release-steering (control)
  "Withdraw the steering that the run which just ended never delivered.
A steering is addressed to one run.  When that run is over, the
steering is not handed to the next one: it is withdrawn, and the
withdrawal is written into the journal, so that the person can see
that their words were not used."
  (dolist (input (yeah-control--steering-batch control))
    (yeah-control--write-withdrawn
     control input "the run it was addressed to ended"))
  nil)

(defun yeah-control-add-completion-listener (control input-id callback)
  "Register runtime CALLBACK for INPUT-ID in CONTROL.
The callback is memory-only and is never included in frozen input data.
Multiple listeners run in registration order and are removed before running."
  (unless (and (stringp input-id) (not (string-empty-p input-id)))
    (signal 'user-error (list "yeah-control: INPUT-ID must be a nonempty string")))
  (unless (functionp callback)
    (signal 'user-error (list "yeah-control: CALLBACK must be a function")))
  (let ((listeners (or (yeah-control-completion-listeners control)
                       (setf (yeah-control-completion-listeners control)
                             (make-hash-table :test 'equal)))))
    (puthash input-id
             (append (gethash input-id listeners) (list callback))
             listeners))
  callback)

(defun yeah-control--notify-completion (control input &optional turn state)
  "Notify and remove INPUT's listeners with TURN and terminal STATE."
  (let* ((input-id (plist-get input :id))
         (listeners (yeah-control-completion-listeners control))
         (callbacks (and listeners (gethash input-id listeners)))
         (completion (list :input-id input-id :input input :turn turn
                           :state (or state (and turn (yeah-turn-state turn))))))
    (when listeners
      (remhash input-id listeners))
    (dolist (callback callbacks)
      (condition-case err
          (funcall callback completion)
        (error
         (message "yeah-control completion listener failed: %s"
                  (error-message-string err)))))
    completion))

(defun yeah-control--start-next (control &optional recovered)
  "Start the oldest pending ask in CONTROL when no turn is active.
A steering is not a task: it belongs to a run, and it is delivered at
a tool-batch boundary, never started on its own.
When RECOVERED is non-nil, the input was started explicitly by the
person and the journal says `input-recovered' instead of `input-taken'.
Return the active turn or nil when the queue holds no ask."
  (let ((active (yeah-control-active-turn control)))
    (when (and active (not (yeah-turn-done active)))
      (user-error "yeah-control: a turn is already active"))
    (let ((input (yeah-input-take (yeah-control-session control) 'ask)))
      (when input
        (yeah-control--write-taken control input recovered)
        (let ((turn
               (yeah-turn-run
                (yeah-control-session control)
                (plist-get input :prompt)
                (yeah-control-transport control)
                (yeah-control-answerer control)
                (or (plist-get (plist-get input :frozen) :budget)
                    (yeah-control-budget control))
                (or (plist-get (plist-get input :frozen) :max-nudges)
                    (yeah-control-max-nudges control))
                (lambda (finished)
                  (setf (yeah-control-active-turn control) nil)
                  (yeah-control--release-steering control)
                  (yeah-control--notify-completion control input finished)
                  (yeah-control--start-next control))
                (lambda (_turn)
                  (yeah-control--deliver-steering control))
                input
                (plist-get (plist-get input :frozen) :deadline-seconds)
                (yeah-control--registry control))))
          (unless (yeah-turn-done turn)
            (setf (yeah-control-active-turn control) turn))
          turn)))))

(defun yeah-control-submit (control prompt &optional frozen on-complete)
  "Queue PROMPT with FROZEN data and return its persistent input id.
ON-COMPLETE receives one plist of shape
`:input-id ID :input INPUT :turn TURN-OR-NIL :state STATE'.  It is runtime
state only, never serialized with INPUT.  A queued input has its own completion
notification, and withdrawing it reports state `cancelled' with a nil turn."
  (let ((input (yeah-input-enqueue
                (yeah-control-session control)
                (yeah-control--frozen control 'ask prompt frozen))))
    (yeah-control--write-queued control input)
    (when on-complete
      (yeah-control-add-completion-listener control (plist-get input :id)
                                            on-complete))
    (unless (yeah-control-active-turn control)
      (yeah-control--start-next control))
    (plist-get input :id)))

(defun yeah-control-ask (control prompt &optional frozen)
  "Queue PROMPT as an ordinary ask with FROZEN configuration.
Retain the original return value: CONTROL's active turn, or nil when all work
finished synchronously.  Use `yeah-control-submit' to obtain the input id."
  (yeah-control-submit control prompt frozen)
  (yeah-control-active-turn control))

(defun yeah-control-steer (control prompt &optional frozen)
  "Queue clarification for the active run, or an ordinary ask when idle.
Steering is delivered after the current tool batch, never between tools."
  (let ((active (yeah-control-active-turn control)))
    (if (and active (not (yeah-turn-done active)))
        (let ((input (yeah-input-enqueue
                      (yeah-control-session control)
                      (yeah-control--frozen control 'steering prompt frozen))))
          (yeah-control--write-queued control input)
          input)
      (yeah-control-ask control prompt frozen)))
  (yeah-control-active-turn control))

(defun yeah-control-cancel (control &optional reason)
  "Cancel CONTROL's active turn, leaving pending inputs for subsequent runs."
  (when-let ((active (yeah-control-active-turn control)))
    (yeah-turn-cancel active reason)))

(defun yeah-control-recover-next (control)
  "Explicitly start the oldest pending input after a restart or cancellation.
The journal says `input-recovered': the input was started by the person,
not by the automatic continuation of a run."
  (yeah-control--start-next control t))

(defun yeah-control-pending (control)
  "Return CONTROL's pending inputs without executing them."
  (yeah-input-pending (yeah-control-session control)))

(defun yeah-control-withdraw (control id)
  "Withdraw pending input ID and complete its runtime listeners as cancelled.
The journal records the withdrawal with the id of the input: the pending
list of the editor is a projection of the journal, and a withdrawn input
must leave it."
  (when-let ((input (yeah-input-withdraw (yeah-control-session control) id)))
    (yeah-control--write-withdrawn control input "withdrawn by the person")
    (yeah-control--notify-completion control input nil 'cancelled)
    input))

(defun yeah-control-done-p (control)
  "Return non-nil when CONTROL has no active turn."
  (null (yeah-control-active-turn control)))

(provide 'yeah-control)
;;; yeah-control.el ends here
