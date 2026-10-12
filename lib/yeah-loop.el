;;; yeah-loop.el --- the 18 FSM transitions of the agent loop -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; This file defines the 18 transitions of the agent-loop FSM
;; (see `decisions/tick-state-machine.yaml' for the normative
;; contract). It also exposes `yeah-loop-tick': a one-step driver
;; that takes the current state and a "label" (the event) and
;; returns the next state or signals `user-error' if the label
;; is not a valid transition from the current state.
;;
;; The 18 transitions are derived from the state machine in
;; `specs/yeah-model.org' (forthcoming in Tier 4). Until that
;; spec is committed, the list is a stable working draft and
;; any change to it is a protected-policy transition.

;;; Code:

(require 'cl-lib)
(require 'yeah-state)

(defconst yeah-loop--raw-transitions
  '(;; happy path
    (idle           user-prompt     . deciding)
    (idle           tick-resume     . deciding)
    (deciding       stream-end      . post-decide)
    (post-decide    no-tool-calls   . completed)
    (post-decide    tool-call       . awaiting-tool)
    (post-decide    permission-ask  . awaiting-user-permission)
    (post-decide    ask-user        . awaiting-user-input)
    (awaiting-tool  tool-end        . accumulating)
    (accumulating   budget-ok       . post-decide)
    (accumulating   budget-overflow . compacting)
    (compacting     compact-done    . post-decide)
    (blocked-on-rate rate-relief    . deciding)
    ;; interrupt fan-in (two sources)
    (deciding       interrupt       . interrupted)
    (awaiting-tool  interrupt       . interrupted)
    ;; wait-state timeouts
    (awaiting-user-permission timeout . failed)
    (awaiting-user-permission answer  . post-decide)
    (awaiting-user-input     timeout . failed)
    (awaiting-user-input     answer  . post-decide))
  "The 18 raw transition cells.
Each cell has the shape (FROM LABEL . TO). The runtime
transition table is built from this list at load time so that
the count can be checked.")

(unless (= 18 (length yeah-loop--raw-transitions))
  (error "yeah-loop: transition count drift; expected 18, got %d"
         (length yeah-loop--raw-transitions)))

(defvar yeah-loop-transitions yeah-loop--raw-transitions
  "The 18 FSM transitions of the Yeah tick.

Each cell has the shape (FROM LABEL . TO). Adding or removing
a transition is a protected-policy transition under
`decisions/tick-state-machine@0'.")

(defun yeah-loop--find-transition (from label)
  "Return the destination state for the transition FROM
triggered by LABEL, or nil if no such transition exists."
  (catch 'found
    (dolist (cell yeah-loop-transitions nil)
      (when (and (eq (nth 0 cell) from)
                 (eq (nth 1 cell) label))
        (throw 'found (nthcdr 2 cell))))))

(defun yeah-loop-tick (from label)
  "One step of the agent loop.

Return the next state when LABEL is a valid transition from
FROM. Signal `user-error' otherwise. The function is pure:
no global state, no IO, no side effects.

FROM must satisfy `yeah-state-p'; LABEL must be a symbol."
  (unless (yeah-state-p from)
    (signal 'user-error (list (format "yeah-loop-tick: not a FSM state: %S" from))))
  (unless (symbolp label)
    (signal 'user-error (list (format "yeah-loop-tick: label must be a symbol, got %S" label))))
  (let ((to (yeah-loop--find-transition from label)))
    (unless to
      (signal 'user-error
              (list (format "yeah-loop-tick: no transition from %S on %S" from label))))
    to))

(defun yeah-loop-transition-count ()
  "Return the number of transitions in `yeah-loop-transitions'."
  (declare (pure t) (side-effect-free t))
  (length yeah-loop-transitions))

(provide 'yeah-loop)
;;; yeah-loop.el ends here
