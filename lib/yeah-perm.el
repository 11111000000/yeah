;;; yeah-perm.el --- the permission rule system -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The agent consults this module before invoking a tool.  A rule combines
;; an action string, a resource string and an effect (`allow', `deny', `ask').
;; Actions match exactly; resources match exactly or by the literal wildcard
;; "*".  The last matching rule wins, and no match defaults to `ask'.
;; Deny/ask signal `user-error'; callers such as approvals convert these to
;; decisions.
;;
;; Public operations construct/add/list rules, evaluate a query and record a
;; runtime decision.  An allow/always answer adds a persistent rule.  Other
;; decisions use `yeah-perm--session-log-fn' when installed; without that
;; hook the current implementation returns the decision plist unchanged.
;; Run-scoped rather than global rules are a later placement-stage item in
;; `docs/PLAN.md'.

;;; Code:

(require 'cl-lib)

(defgroup yeah-perm nil
  "The Yeah permission rule system."
  :group 'yeah)

(defvar yeah-perm--rules nil
  "Current global permission rules in registration order, newest last.
Run-scoped rules replace this global set in the placement stage.")

(defvar yeah-perm--session-log-fn nil
  "Optional function that records a session-scoped decision.
It receives `(:action ACT :resource RES :reply REPLY :save SAVE)'.  When nil,
`yeah-perm-record-decision' returns that decision plist unchanged.")

(defconst yeah-perm--effects '(allow deny ask)
  "The three effect symbols recognised by the permission system.")

(defun yeah-perm--effect-p (x)
  "Non-nil if X is one of the three effect symbols."
  (memq x yeah-perm--effects))

(defun yeah-perm--rule-p (rule)
  "Non-nil if RULE looks like a valid rule plist."
  (and (consp rule)
       (stringp (plist-get rule :action))
       (> (length (plist-get rule :action)) 0)
       (stringp (plist-get rule :resource))
       (yeah-perm--effect-p (plist-get rule :effect))))

(defun yeah-perm-rule-make (action resource effect)
  "Build a permission rule plist.
ACTION and RESOURCE are strings (RESOURCE may be `\"*\"' as a
wildcard). EFFECT is one of the symbols `allow', `deny', `ask'.
The returned plist has shape
`(:action ACTION :resource RESOURCE :effect EFFECT)'.
Signals `user-error' on a malformed argument."
  (unless (stringp action)
    (signal 'user-error
            (list (format "yeah-perm-rule-make: action must be a string, got %S"
                          (type-of action)))))
  (unless (stringp resource)
    (signal 'user-error
            (list (format "yeah-perm-rule-make: resource must be a string, got %S"
                          (type-of resource)))))
  (unless (yeah-perm--effect-p effect)
    (signal 'user-error
            (list (format "yeah-perm-rule-make: effect must be allow/deny/ask, got %S"
                          effect))))
  (list :action action :resource resource :effect effect))

(defun yeah-perm-rules-add (rule)
  "Append RULE to the current agent's permission ruleset.
Returns RULE. Signals `user-error' if RULE is malformed."
  (unless (yeah-perm--rule-p rule)
    (signal 'user-error
            (list (format "yeah-perm-rules-add: malformed rule %S" rule))))
  (setq yeah-perm--rules (append yeah-perm--rules (list rule)))
  rule)

(defun yeah-perm-rules-list ()
  "Return all current permission rules in registration order."
  yeah-perm--rules)

(defun yeah-perm-rules-reset-for-test ()
  "Drop every rule; for tests only.
Not exported; documented here so test authors can find it.
Matches the convention used by `yeah-emcp--reset-for-test' and
`yeah-tools-reset-for-test'."
  (setq yeah-perm--rules nil))

(defun yeah-perm--rule-matches-p (rule action resource)
  "Non-nil if RULE matches a query `(ACTION RESOURCE)'.
A rule matches when its action is exactly ACTION and its
resource is exactly RESOURCE **or** the literal wildcard
`\"*\"'. Action is never a wildcard."
  (declare (pure t) (side-effect-free t))
  (and (string= action (plist-get rule :action))
       (or (string= resource (plist-get rule :resource))
           (string= "*" (plist-get rule :resource)))))

(defun yeah-perm-evaluate (action resource)
  "Evaluate `(ACTION RESOURCE)' against the current ruleset.
Scans the rule list in registration order; the **last**
matching rule wins. Returns `:allow' on the happy path.
On `:deny', raises `(user-error \"deny: <action> on <resource>\")'.
On `:ask', raises `(user-error \"ask: <action> on <resource>\")'.
When no rule matches, the default effect is `:ask'.

The matching algorithm is documented at the top of this file."
  (let ((last-match nil)
        (rule nil)
        (rest nil))
    (setq rest yeah-perm--rules)
    (while rest
      (setq rule (car rest))
      (when (yeah-perm--rule-matches-p rule action resource)
        (setq last-match rule))
      (setq rest (cdr rest)))
    (let ((effect (if last-match
                      (plist-get last-match :effect)
                    'ask)))
      (pcase effect
        ('allow :allow)
        ('deny
         (signal 'user-error
                 (list (format "deny: %s on %s" action resource))))
        ('ask
         (signal 'user-error
                 (list (format "ask: %s on %s" action resource))))))))

(defun yeah-perm-record-decision (action resource reply save)
  "Record a runtime decision for `(ACTION RESOURCE)'.
REPLY is one of `allow', `deny', `ask'. SAVE is `nil' for
session-only, the symbol `always' to persist.

When REPLY is `allow' and SAVE is `always', add an allow rule through
`yeah-perm-rules-add'.  Otherwise pass the decision to
`yeah-perm--session-log-fn' when installed, or return its plist unchanged
when no session-log hook is configured."
  (unless (stringp action)
    (signal 'user-error
            (list (format "yeah-perm-record-decision: action must be a string, got %S"
                          (type-of action)))))
  (unless (stringp resource)
    (signal 'user-error
            (list (format "yeah-perm-record-decision: resource must be a string, got %S"
                          (type-of resource)))))
  (unless (yeah-perm--effect-p reply)
    (signal 'user-error
            (list (format "yeah-perm-record-decision: reply must be allow/deny/ask, got %S"
                          reply))))
  (unless (or (null save) (eq save 'always))
    (signal 'user-error
            (list (format "yeah-perm-record-decision: save must be nil or `always', got %S"
                          save))))
  (if (and (eq reply 'allow) (eq save 'always))
      (yeah-perm-rules-add
       (yeah-perm-rule-make action resource 'allow))
    (let ((decision (list :action action
                          :resource resource
                          :reply reply
                          :save save)))
      (if yeah-perm--session-log-fn
          (funcall yeah-perm--session-log-fn decision)
        decision))))

(provide 'yeah-perm)
;;; yeah-perm.el ends here