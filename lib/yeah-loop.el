;;; yeah-loop.el --- the 20 FSM transitions of the agent loop -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; This file defines the current 20 transitions of the agent-loop FSM and
;; exposes `yeah-loop-tick', which returns the next state for a state/event
;; pair or signals `user-error' for an invalid transition.  The target
;; invariants are valid, bounded and recoverable transitions, not a permanent
;; transition count; see `docs/ARCHITECTURE.md' and `docs/PLAN.md'.

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
    ;; the model is asked again, with the results of what was dispatched
    (post-decide    continue        . deciding)
    ;; the model answered with nothing usable: the run failed
    (deciding       error           . failed)
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
  "The 20 raw transition cells.
Each cell has the shape (FROM LABEL . TO). The runtime
transition table is built from this list at load time so that
the count can be checked.")

(unless (= 20 (length yeah-loop--raw-transitions))
  (error "yeah-loop: transition count drift; expected 20, got %d"
         (length yeah-loop--raw-transitions)))

(defvar yeah-loop-transitions yeah-loop--raw-transitions
  "The current FSM transition cells, each with shape (FROM LABEL . TO).
Changes must keep the run bounded and recoverable and be reflected in
`docs/ARCHITECTURE.md', `docs/PLAN.md' and the relevant checks.")

(defun yeah-loop--find-transition (from label)
  "Return the destination state for the transition FROM
triggered by LABEL, or nil if no such transition exists."
  (catch 'found
    (dolist (cell yeah-loop-transitions nil)
      (when (and (eq (nth 0 cell) from)
                 (eq (nth 1 cell) label))
        (throw 'found (nthcdr 2 cell))))))

(defun yeah-loop-transition-p (from label)
  "Return non-nil when FROM has a transition on LABEL."
  (and (yeah-state-p from)
       (symbolp label)
       (yeah-loop--find-transition from label)))

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
