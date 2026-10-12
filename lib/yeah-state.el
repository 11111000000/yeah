;;; yeah-state.el --- the 10 FSM states -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The agent loop is a deterministic finite state machine with
;; exactly 10 states (see `decisions/tick-state-machine.yaml`).
;; This file defines the state set and the predicate that
;; distinguishes terminal states from non-terminal ones. The
;; transitions themselves live in `lib/yeah-loop.el`; this file
;; is data only.

;;; Code:

(require 'cl-lib)

(defgroup yeah nil
  "Yeah — Y(eah) Emacs Agent Harness."
  :group 'tools)

;; The 10 states. Order is meaningful: the first four are the
;; "happy path"; the next four are the "wait" states; the last
;; three are the "terminal" states. The order is exposed for
;; diagnostics (e.g. printing the FSM trace) but is not load-bearing
;; for the state machine itself.
(defconst yeah-state-list
  '(idle
    deciding
    post-decide
    awaiting-tool
    awaiting-user-permission
    awaiting-user-input
    accumulating
    compacting
    blocked-on-rate
    interrupted
    completed
    failed)
  "The 12 states of the Yeah tick FSM.

See `decisions/tick-state-machine.yaml' (revision 2) for the
normative contract. Adding or removing a state is a
protected-policy transition. Revision 0 of the decision said
10 states; revision 1 added `post-decide'; revision 2 added
`accumulating' to match the transition table in
`lib/yeah-loop.el'.")

(defsubst yeah-state-p (object)
  "Non-nil if OBJECT is one of the 10 FSM states."
  (and (symbolp object)
       (memq object yeah-state-list)))

(defvar yeah-state--table nil
  "Hash table mapping state symbols to plist metadata.
Used by `yeah-state-describe' and by the validator. Not used
by the loop itself.")

(defun yeah-state--init-table ()
  "Populate `yeah-state--table' with metadata for each state.
Idempotent."
  (interactive)
  (unless (hash-table-p yeah-state--table)
    (setq yeah-state--table (make-hash-table :test 'eq :size 16)))
  (puthash 'idle                    '(:category :happy  :terminal nil) yeah-state--table)
  (puthash 'deciding                '(:category :happy  :terminal nil) yeah-state--table)
  (puthash 'post-decide             '(:category :happy  :terminal nil) yeah-state--table)
  (puthash 'awaiting-tool           '(:category :happy  :terminal nil) yeah-state--table)
  (puthash 'awaiting-user-permission '(:category :wait   :terminal nil) yeah-state--table)
  (puthash 'awaiting-user-input     '(:category :wait   :terminal nil) yeah-state--table)
  (puthash 'accumulating            '(:category :happy  :terminal nil) yeah-state--table)
  (puthash 'compacting              '(:category :wait   :terminal nil) yeah-state--table)
  (puthash 'blocked-on-rate         '(:category :wait   :terminal nil) yeah-state--table)
  (puthash 'interrupted             '(:category :term   :terminal t)   yeah-state--table)
  (puthash 'completed               '(:category :term   :terminal t)   yeah-state--table)
  (puthash 'failed                  '(:category :term   :terminal t)   yeah-state--table)
  (dolist (state yeah-state-list)
    (unless (gethash state yeah-state--table)
      (error "yeah-state: missing metadata for state %S" state))))

(defun yeah-state-terminal-p (state)
  "Non-nil if STATE is a terminal state of the FSM.
Terminal states are `interrupted', `completed', `failed'.
All other states are non-terminal."
  (declare (pure t) (side-effect-free t))
  (unless (yeah-state-p state)
    (error "yeah-state-terminal-p: %S is not a FSM state" state))
  (eq (plist-get (gethash state yeah-state--table) :terminal) t))

(defun yeah-state-describe (state)
  "Return a one-line human description of STATE."
  (declare (pure t) (side-effect-free t))
  (unless (yeah-state-p state)
    (error "yeah-state-describe: %S is not a FSM state" state))
  (let* ((meta (gethash state yeah-state--table))
         (category (plist-get meta :category)))
    (format "%s [%s%s]"
            state
            category
            (if (eq (plist-get meta :terminal) t) ", terminal" ""))))

(provide 'yeah-state)
;;; yeah-state.el ends here
