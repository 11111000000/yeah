;;; yeah-state.el --- the agent FSM states -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; This file defines the agent's current state set and predicates for valid
;; and terminal states.  Transitions live in `lib/yeah-loop.el'.  The target
;; invariants are documented in `docs/ARCHITECTURE.md'; the number of states
;; is not itself an architectural invariant.

;;; Code:

(require 'cl-lib)

(defgroup yeah nil
  "Yeah — Emacs Agent Harness."
  :group 'tools)

;; Order is exposed for diagnostics but is not load-bearing for transitions.
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
  "The current states of the Yeah tick FSM.
Changes must preserve valid, bounded and recoverable transitions and be
reflected in `docs/ARCHITECTURE.md', `docs/PLAN.md' and the relevant checks.")

(defsubst yeah-state-p (object)
  "Non-nil if OBJECT is one of the states in `yeah-state-list'."
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
