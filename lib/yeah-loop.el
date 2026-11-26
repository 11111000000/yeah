;;; yeah-loop.el --- the FSM transitions of the agent loop -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; This file defines the transitions of the agent-loop FSM and exposes
;; `yeah-loop-tick', which returns the next state for a state/event
;; pair or signals `user-error' for an invalid transition.  The target
;; invariants are valid, bounded and recoverable transitions, not a permanent
;; transition count; see `docs/ARCHITECTURE.md' and `docs/PLAN.md'.
;;
;; The table is the contract of the machine, and the runtime keeps it: every
;; move the runtime makes is a cell of this table, and every label of this
;; table is a move the runtime makes (wave 77).  The table was not that
;; before: seven of its cells named events the runtime never had, and three
;; of its states could not be entered at all.

;;; Code:

(require 'cl-lib)
(require 'yeah-state)

(defconst yeah-loop--raw-transitions
  '((;; the run starts
     idle           user-prompt     . deciding)
     ;; the model is asked and answers
     (deciding       stream-end      . post-decide)
     ;; the answer of the model is read: it ends the run, it calls tools, or
     ;; the model is asked again
     (post-decide    no-tool-calls   . completed)
     (post-decide    tool-call       . awaiting-tool)
     (post-decide    continue        . deciding)
     (post-decide    nudge           . deciding)
     ;; the tools of the model run and settle
     (awaiting-tool  tool-end        . accumulating)
     (accumulating   budget-ok       . post-decide)
     (accumulating   budget-overflow . compacting)
     (compacting     compact-done    . post-decide)
     ;; the run waits for the person: a tool that may not run yet asks a
     ;; question, and the question waits for the answer
     (awaiting-tool  permission-ask  . awaiting-user-permission)
	     (awaiting-user-permission answer  . awaiting-tool)
	     (awaiting-user-permission parallel-tool-end . awaiting-user-permission)
	     (awaiting-user-permission timeout . awaiting-tool)
     ;; the run waits for the provider: it was busy, and the request is
     ;; asked again
     (deciding       rate-blocked    . blocked-on-rate)
     (blocked-on-rate rate-relief    . deciding)
     ;; a run that is not finished can fail in any state it lives in
     (idle             error         . failed)
     (deciding         error         . failed)
     (post-decide      error         . failed)
     (awaiting-tool    error         . failed)
     (awaiting-user-permission error . failed)
     (accumulating     error         . failed)
     (compacting       error         . failed)
     (blocked-on-rate  error         . failed)
     ;; and it can be cancelled in any state it lives in
     (idle             interrupt     . interrupted)
     (deciding         interrupt     . interrupted)
     (post-decide      interrupt     . interrupted)
     (awaiting-tool    interrupt     . interrupted)
     (awaiting-user-permission interrupt . interrupted)
     (accumulating     interrupt     . interrupted)
     (compacting       interrupt     . interrupted)
     (blocked-on-rate  interrupt     . interrupted))
  "The raw transition cells of the machine.
Each cell has the shape (FROM LABEL . TO). The runtime
transition table is built from this list at load time so that
the count can be checked.")

(unless (= 32 (length yeah-loop--raw-transitions))
  (error "yeah-loop: transition count drift; expected 32, got %d"
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
