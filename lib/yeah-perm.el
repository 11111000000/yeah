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
;; Actions match exactly, or by the literal wildcard "*"; resources match
;; exactly or by the literal wildcard "*".  The last matching rule wins, and
;; no match defaults to `ask'.
;; Deny/ask signal `user-error'; callers such as approvals convert these to
;; decisions.
;;
;; Public operations construct/add/list rules, evaluate a query and record a
;; runtime decision.  An allow/always answer adds a persistent rule.  Other
;; decisions use `yeah-perm--session-log-fn' when installed; without that
;; hook the current implementation returns the decision plist unchanged.
;;
;; The global ruleset is the persistent policy of the person.  A run may
;; carry its own rules — `yeah-run-context' in `lib/yeah-run.el' does — and
;; `yeah-perm-effect' and `yeah-perm-evaluate' accept them as an argument,
;; so two runs in one Emacs do not share one truth.
;;
;; The profiles ask by the declaration of the tool and not by a list of
;; names: the tools that change the world are the tools that declare a
;; risk other than `read' (`lib/yeah-risk.el'), and a tool that declares
;; no risk changes the world as far as the rule knows.

;;; Code:

(require 'cl-lib)
(require 'yeah-risk)

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

(defconst yeah-perm--scopes
  '(:once :run :session :project :global)
  "The scopes a permission answer may name.
`once' is this call, `run' the rules of the run, `session' the rules of
the session, `project' the rules of the project and `global' the rules
of the process.  This is the one place the scopes are written: every
other place asks for them here and never writes the list again.")

(defconst yeah-perm--carriers
  '((:run run "the rules of the run")
    (:session session "the rules of the session")
    (:global global "the rules of the process"))
  "The scopes that have a carrier, the name of the carrier and what the
carrier holds.

`run' holds the rules of an attached run, `session' the rules of an ACP
session and `global' the rules of the process.  The correspondence
between a path and its scope lives here and nowhere else: a path asks
for the scope of its carrier and never writes the table again.  A scope
that has no carrier here -- `once' holds no rule and `project' has none
yet -- is refused by name, and the refusal says why.")

(defun yeah-perm--effect-p (x)
  "Non-nil if X is one of the three effect symbols."
  (memq x yeah-perm--effects))

(defun yeah-perm-scopes ()
  "Return the canonical scopes a permission answer may name."
  yeah-perm--scopes)

(defun yeah-perm-scope-p (scope)
  "Return non-nil when SCOPE is one of the canonical scopes."
  (and (memq scope yeah-perm--scopes) t))

(defun yeah-perm-scope-name (scope)
  "Return the plain name of SCOPE, without its colon.
The name is the way a scope is written into a record: the journal and the
interface spell the scope the same way, and the spelling is made here."
  (if (symbolp scope)
      (let ((name (symbol-name scope)))
        (if (string-prefix-p ":" name) (substring name 1) name))
    (format "%S" scope)))

(defun yeah-perm-scope-of-carrier (carrier)
  "Return the scope the rules of CARRIER hold, or nil.
CARRIER is the name of a holder of rules: `run', `session' or `global'."
  (let ((entry (seq-find (lambda (candidate) (eq (nth 1 candidate) carrier))
                          yeah-perm--carriers)))
    (and entry (nth 0 entry))))

(defun yeah-perm-carrier-of-scope (scope)
  "Return what holds the rules of SCOPE, or nil when nothing holds them.
The answer says what the carrier is, so that a refusal can say why."
  (let ((entry (seq-find (lambda (candidate) (eq (nth 0 candidate) scope))
                          yeah-perm--carriers)))
    (and entry (nth 2 entry))))

(defun yeah-perm--rule-p (rule)
  "Non-nil if RULE looks like a valid rule plist."
  (and (consp rule)
       (stringp (plist-get rule :action))
       (> (length (plist-get rule :action)) 0)
       (stringp (plist-get rule :resource))
       (yeah-perm--effect-p (plist-get rule :effect))))

(defun yeah-perm-rule-make (action resource effect &optional scope)
  "Build a permission rule plist.
ACTION and RESOURCE are strings (RESOURCE may be `\"*\"' as a
wildcard). EFFECT is one of the symbols `allow', `deny', `ask'.
SCOPE, when given, is the canonical scope the rule belongs to: the scope
says where the rule lives.  A rule without a scope keeps the meaning it
had -- it holds where it is written.
The returned plist has shape
`(:action ACTION :resource RESOURCE :effect EFFECT)' and carries
`:scope SCOPE' when a scope was given.
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
  (unless (or (null scope) (yeah-perm-scope-p scope))
    (signal 'user-error
            (list (format "yeah-perm-rule-make: scope must be one of %S, got %S"
                          yeah-perm--scopes scope))))
  (append (list :action action :resource resource :effect effect)
          (when scope (list :scope scope))))

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

(defun yeah-perm--mutating-tools ()
  "Return the names of the tools that change the world.
The set is computed from the declarations of the tools (`lib/yeah-risk.el')
and not from a list of names: a tool that says that it changes the world
is in the set, and a tool that declares no risk at all is in the set too,
because a risk that is not known changes the world.

The declarations must be known.  A profile that cannot name the tools that
change the world would allow all of them, and a rule that allows what it
does not know is not a rule."
  (unless (yeah-risk--known-p)
    (signal 'user-error
            (list "yeah-perm: the risks of the tools are not known: the registry of the tools is not loaded")))
  (yeah-risk-mutating-tools))

(defun yeah-perm-profiles ()
  "Return the names of the permission profiles."
  '("plan" "build" "auto"))

(defun yeah-perm-profile (name)
  "Return the rules of the permission profile NAME, or nil.

`plan' denies the tools that change the world: the agent may look, but
not touch.  `build' asks for them: the person decides each one, and
the profile decides nothing else.  `auto' allows them: there is nobody
to ask, and the mode says so before anybody is asked.  A profile is a
mode of work, not a policy of the person, so its rules are not added to
the persistent ruleset.

The rule asks by the declaration of the tool and not by a list of names:
the tools that change the world are the tools that declare a risk other
than `read', and a tool that declares no risk is one of them."
  (pcase name
    ("plan" (mapcar (lambda (tool) (yeah-perm-rule-make tool "*" 'deny))
                    (yeah-perm--mutating-tools)))
    ("build" (mapcar (lambda (tool) (yeah-perm-rule-make tool "*" 'ask))
                     (yeah-perm--mutating-tools)))
    ("auto" (list (yeah-perm-rule-make "*" "*" 'allow)))
    (_ nil)))

(defun yeah-perm-rules-append (rules rule)
  "Return RULES with RULE appended, without touching the global ruleset.
RULE must be a valid rule plist.  This is how a run keeps rules of its
own: the run asks with its own list, the person answers with the
global one."
  (unless (yeah-perm--rule-p rule)
    (signal 'user-error
            (list (format "yeah-perm-rules-append: malformed rule %S" rule))))
  (append rules (list rule)))

(defun yeah-perm-rules-reset-for-test ()
  "Drop every rule; for tests only.
Not exported; documented here so test authors can find it.
Matches the convention used by `yeah-emcp--reset-for-test' and
`yeah-tools-reset-for-test'."
  (setq yeah-perm--rules nil))

(defun yeah-perm--rule-matches-p (rule action resource)
  "Non-nil if RULE matches a query `(ACTION RESOURCE)'.
A rule matches when its action is exactly ACTION **or** the literal
wildcard `\"*\"', and its resource is exactly RESOURCE **or** the literal
wildcard `\"*\".  The wildcard of the action is the rule of the profile
that speaks about every action at once; a rule of the person that names
an action names one action."
  (declare (pure t) (side-effect-free t))
  (and (or (string= action (plist-get rule :action))
           (string= "*" (plist-get rule :action)))
       (or (string= resource (plist-get rule :resource))
           (string= "*" (plist-get rule :resource)))))

(defun yeah-perm-effect (action resource &optional rules)
  "Return the effect RULES give for `(ACTION RESOURCE)'.

RULES defaults to the current global ruleset.  The effect is one of
`:allow', `:deny' or `:ask'.  The last matching rule wins, and no match
means `:ask'.  This is the query without the signal: a caller that has
somewhere else to ask asks there."
  (let ((last-match nil)
        (rule nil)
        (rest (or rules yeah-perm--rules)))
    (while rest
      (setq rule (car rest))
      (when (yeah-perm--rule-matches-p rule action resource)
        (setq last-match rule))
      (setq rest (cdr rest)))
    (if last-match
        (plist-get last-match :effect)
      'ask)))

(defun yeah-perm-evaluate (action resource &optional rules)
  "Evaluate `(ACTION RESOURCE)' against the current ruleset.
RULES may name another ruleset; the current global one is used when it
is nil.  Scans the rule list in registration order; the **last**
matching rule wins. Returns `:allow' on the happy path.
On `:deny', raises `(user-error \"deny: <action> on <resource>\")'.
On `:ask', raises `(user-error \"ask: <action> on <resource>\")'.
When no rule matches, the default effect is `:ask'.

The matching algorithm is documented at the top of this file."
  (pcase (yeah-perm-effect action resource rules)
    ('allow :allow)
    ('deny
     (signal 'user-error
             (list (format "deny: %s on %s" action resource))))
    ('ask
     (signal 'user-error
             (list (format "ask: %s on %s" action resource))))
    (_
     (signal 'user-error
             (list (format "the rules say %s on %s" action resource))))))

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