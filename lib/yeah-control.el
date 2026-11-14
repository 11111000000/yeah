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

;;; Code:

(require 'cl-lib)
(require 'yeah-turn)
(require 'yeah-events)
(require 'yeah-input)

(cl-defstruct (yeah-control (:constructor yeah-control--make))
  "Runtime control state for one session."
  session
  transport
  answerer
  budget
  max-nudges
  frozen-defaults
  active-turn
  completion-listeners)

(defun yeah-control-new (session &optional transport answerer budget max-nudges frozen)
  "Return a controller for SESSION without starting any work.
TRANSPORT, ANSWERER, BUDGET and MAX-NUDGES are frozen for subsequent inputs.
FROZEN is additional serializable configuration recorded with each input."
  (yeah-control--make
   :session session
   :transport (or transport
                  (and (fboundp 'yeah-gptel-request) #'yeah-gptel-request))
   :answerer (or answerer #'yeah-approval-policy-decision)
   :budget (or budget yeah-context-default-budget)
   :max-nudges (or max-nudges yeah-turn-default-max-nudges)
   :frozen-defaults frozen
   :completion-listeners (make-hash-table :test 'equal)))

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
Ordinary asks retain their FIFO positions."
  (let ((inputs nil))
    (dolist (input (yeah-input-pending (yeah-control-session control)))
      (when (eq 'steering (plist-get input :kind))
        (push (yeah-input-withdraw (yeah-control-session control)
                                   (plist-get input :id))
              inputs)))
    (nreverse inputs)))

(defun yeah-control--release-steering (control)
  "Withdraw the steering that the run which just ended never delivered.
A steering is addressed to one run.  When that run is over, the
steering is not handed to the next one: it is withdrawn, and the
withdrawal is written into the journal, so that the person can see
that their words were not used."
  (dolist (input (yeah-control--steering-batch control))
    (yeah-events-write (yeah-control-session control) "input-withdrawn"
                       :kind (format "%s" (or (plist-get input :kind) 'steering))
                       :reason "the run it was addressed to ended"))
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

(defun yeah-control--start-next (control)
  "Start the oldest pending ask in CONTROL when no turn is active.
A steering is not a task: it belongs to a run, and it is delivered at
a tool-batch boundary, never started on its own.
Return the active turn or nil when the queue holds no ask."
  (let ((active (yeah-control-active-turn control)))
    (when (and active (not (yeah-turn-done active)))
      (user-error "yeah-control: a turn is already active"))
    (let ((input (yeah-input-take (yeah-control-session control) 'ask)))
      (when input
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
                  (yeah-control--steering-batch control))
                input
                (plist-get (plist-get input :frozen) :deadline-seconds))))
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
        (yeah-input-enqueue
         (yeah-control-session control)
         (yeah-control--frozen control 'steering prompt frozen))
      (yeah-control-ask control prompt frozen)))
  (yeah-control-active-turn control))

(defun yeah-control-cancel (control &optional reason)
  "Cancel CONTROL's active turn, leaving pending inputs for subsequent runs."
  (when-let ((active (yeah-control-active-turn control)))
    (yeah-turn-cancel active reason)))

(defun yeah-control-recover-next (control)
  "Explicitly start the oldest pending input after a restart or cancellation."
  (yeah-control--start-next control))

(defun yeah-control-pending (control)
  "Return CONTROL's pending inputs without executing them."
  (yeah-input-pending (yeah-control-session control)))

(defun yeah-control-withdraw (control id)
  "Withdraw pending input ID and complete its runtime listeners as cancelled."
  (when-let ((input (yeah-input-withdraw (yeah-control-session control) id)))
    (yeah-control--notify-completion control input nil 'cancelled)
    input))

(defun yeah-control-done-p (control)
  "Return non-nil when CONTROL has no active turn."
  (null (yeah-control-active-turn control)))

(provide 'yeah-control)
;;; yeah-control.el ends here
