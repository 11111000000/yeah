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
  active-turn)

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
   :frozen-defaults frozen))

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
                (lambda (_turn)
                  (setf (yeah-control-active-turn control) nil)
                  (yeah-control--release-steering control)
                  (yeah-control--start-next control))
                (lambda (_turn)
                  (yeah-control--steering-batch control))
                input
                (plist-get (plist-get input :frozen) :deadline-seconds))))
          (unless (yeah-turn-done turn)
            (setf (yeah-control-active-turn control) turn))
          turn)))))

(defun yeah-control-ask (control prompt &optional frozen)
  "Queue PROMPT as an ordinary ask with FROZEN configuration.
Start it immediately when no turn is active."
  (yeah-input-enqueue (yeah-control-session control)
                      (yeah-control--frozen control 'ask prompt frozen))
  (unless (yeah-control-active-turn control)
    (yeah-control--start-next control))
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
  "Withdraw the pending input identified by ID from CONTROL."
  (yeah-input-withdraw (yeah-control-session control) id))

(defun yeah-control-done-p (control)
  "Return non-nil when CONTROL has no active turn."
  (null (yeah-control-active-turn control)))

(provide 'yeah-control)
;;; yeah-control.el ends here
