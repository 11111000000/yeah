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
;;
;; The SCOPE of a rule says where the rule lives, and the CARRIER of a
;; scope is what holds it: the rules of a run live in the run, the rules
;; of a session live in the session, the rules of a project live in the
;; file of the project (`.yeah/rules.json' of the project) and the rules
;; of the user live in the file of the user (`rules.json' of the
;; configuration of the user).  The correspondence between a scope and
;; its carrier is written in one place (`yeah-perm--carriers'), and the
;; paths of the files come from one place as well.
;;
;; A rule that is written into a carrier is read back from it when the
;; permission is computed: a rule that is saved and never read is a
;; rule that does not exist.  A file that cannot be read is a refusal
;; that names the file and the reason, and not a silence.

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
of the user.  This is the one place the scopes are written: every
other place asks for them here and never writes the list again.")

(declare-function yeah-product-project-root "yeah-product" ())

(defun yeah-perm--project-root ()
  "Return the root of the project whose rules are read.
The product layer knows the root of the project (`yeah-product-project-root')
and the kernel asks it when the product layer is loaded.  A kernel that
runs without the product layer stands in the directory of the process."
  (if (fboundp 'yeah-product-project-root)
      (yeah-product-project-root)
    (file-truename default-directory)))

(defun yeah-perm--config-home ()
  "Return the directory that holds the configuration of the user.
The directory is the one of `XDG_CONFIG_HOME', and the one of the home
directory when the variable is not set."
  (let ((xdg (getenv "XDG_CONFIG_HOME")))
    (if (and xdg (not (string= xdg "")))
        (expand-file-name xdg)
      (expand-file-name ".config" (getenv "HOME")))))

(defun yeah-perm--project-rules-file ()
  "Return the file that holds the rules of the project.
The file is the `rules.json' of the `.yeah' directory of the project."
  (expand-file-name ".yeah/rules.json" (yeah-perm--project-root)))

(defun yeah-perm--user-rules-file ()
  "Return the file that holds the rules of the user.
The file is the `rules.json' of the `yeah' directory of the
configuration of the user."
  (expand-file-name "yeah/rules.json" (yeah-perm--config-home)))

(defconst yeah-perm--carriers
  '((:once once "the scope of the call itself" nil)
    (:run run "the rules of the run" nil)
    (:session session "the rules of the session" nil)
    (:project project "the rules of the project" yeah-perm--project-rules-file)
    (:global global "the rules of the user" yeah-perm--user-rules-file))
  "The scope, the carrier that holds its rules, what the carrier holds
and the file that holds them.

Every scope of the dictionary has exactly one carrier, and the
correspondence between a scope and its carrier lives here and nowhere
else: a path asks for the scope of its carrier and never writes the
table again.  The fourth element of an entry is the function that
returns the file of the carrier, and nil when the carrier keeps its
rules in the memory of the path that owns it: the rules of a run live
in the run and the rules of a session live in the session.

The scope `once' is the scope of the call itself: it holds no rule,
and a rule that carries it is refused by name.  The scopes are written
from the most specific one to the broadest one, and the rules are
collected the other way around, because the last matching rule wins.")

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

(defun yeah-perm--carrier-entry (scope)
  "Return the entry of the table that holds the rules of SCOPE, or nil."
  (seq-find (lambda (candidate) (eq (nth 0 candidate) scope))
            yeah-perm--carriers))

(defun yeah-perm-scope-of-carrier (carrier)
  "Return the scope the rules of CARRIER hold, or nil.
CARRIER is the name of a holder of rules: `once', `run', `session',
`project' or `global'."
  (let ((entry (seq-find (lambda (candidate) (eq (nth 1 candidate) carrier))
                          yeah-perm--carriers)))
    (and entry (nth 0 entry))))

(defun yeah-perm-carrier-of-scope (scope)
  "Return what holds the rules of SCOPE, or nil when nothing holds them.
The answer says what the carrier is, so that a refusal can say why."
  (let ((entry (yeah-perm--carrier-entry scope)))
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
  "Return the rules of the process in registration order.
The rules of the process are the rules that the Emacs holds in its
memory.  They are not the carrier of a scope: the scope `global' is the
file of the user.  The rules that decide for the person are the rules
of the process and the rules of the carriers that keep their rules in
a file (`yeah-perm-effective-rules')."
  yeah-perm--rules)

(defun yeah-perm--refusal-cause ()
  "Return the cause of the refusal of the rule, as a string.
The cause is the error of the load of the registry of the tools, and it is
named here: a refusal that does not name its cause is a refusal that the
person cannot act on.  The answer is the empty string when there is no cause
to name."
  (let ((failure (yeah-risk-failure)))
    (if failure
        (format ": %s: %s" (car-safe failure) (error-message-string failure))
      "")))

(defun yeah-perm--mutating-tools ()
  "Return the names of the tools that change the world.
The set is computed from the declarations of the tools (`lib/yeah-risk.el')
and not from a list of names: a tool that says that it changes the world
is in the set, and a tool that declares no risk at all is in the set too,
because a risk that is not known changes the world.

The declarations must be known.  A profile that cannot name the tools that
change the world would allow all of them, and a rule that allows what it
does not know is not a rule.  The refusal names the cause of the missing
declarations, so that the person can act on the cause and not only on the
refusal."
  (unless (yeah-risk--known-p)
    (signal 'user-error
            (list (format "yeah-perm: the risks of the tools are not known: the registry of the tools is not loaded%s"
                          (yeah-perm--refusal-cause)))))
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

(defun yeah-perm--rule->json (rule)
  "Return RULE as the JSON object of a rules file.
The object carries the action, the resource, the effect and the scope:
a rule in a file says where it lives.  The effect and the scope are
spelled as the words the kernel uses for them."
  (list :action (plist-get rule :action)
        :resource (plist-get rule :resource)
        :effect (symbol-name (plist-get rule :effect))
        :scope (yeah-perm-scope-name (plist-get rule :scope))))

(defun yeah-perm--rule-from-json (object file)
  "Return the rule that the JSON object OBJECT holds, or refuse.
FILE is the file the object was read from: the refusal names it, and it
names the reason as well."
  (unless (and (listp object)
               (stringp (plist-get object :action))
               (stringp (plist-get object :resource))
               (stringp (plist-get object :effect))
               (stringp (plist-get object :scope)))
    (signal 'user-error
            (list (format "yeah-perm: the rules file %s is broken: %S is not a rule"
                          file object))))
  (let* ((effect-name (plist-get object :effect))
         (scope-name (plist-get object :scope)))
    (unless (member effect-name (mapcar #'symbol-name yeah-perm--effects))
      (signal 'user-error
              (list (format "yeah-perm: the rules file %s is broken: %S is not an effect of the rules"
                            file effect-name))))
    (unless (member scope-name (mapcar #'yeah-perm-scope-name yeah-perm--scopes))
      (signal 'user-error
              (list (format "yeah-perm: the rules file %s is broken: %S is not a scope"
                            file scope-name))))
    (list :action (plist-get object :action)
          :resource (plist-get object :resource)
          :effect (intern effect-name nil)
          :scope (intern (concat ":" scope-name) nil))))

(defun yeah-perm--read-rules-file (file)
  "Return the rules that FILE holds, or nil when there is no file.
A file that is not there is a file of no rules and not an error.  A
file that cannot be read is a refusal that names the file and the
reason: a rule that cannot be read is never ignored."
  (if (not (file-exists-p file))
      nil
    (let* ((text (condition-case err
                     (with-temp-buffer
                       (insert-file-contents file)
                       (buffer-string))
                   (error
                    (signal 'user-error
                            (list (format "yeah-perm: the rules file %s cannot be read: %s"
                                          file (error-message-string err)))))))
           (parsed (condition-case err
                       (json-parse-string text :object-type 'plist :array-type 'list)
                     (error
                      (signal 'user-error
                              (list (format "yeah-perm: the rules file %s is broken: %s"
                                            file (error-message-string err))))))))
      (unless (listp parsed)
        (signal 'user-error
                (list (format "yeah-perm: the rules file %s is broken: it does not hold a list of rules"
                              file))))
      (mapcar (lambda (object) (yeah-perm--rule-from-json object file)) parsed))))

(defun yeah-perm--rules->json (rules)
  "Return RULES as the text of a rules file.
The text is an array of objects, one rule per line: the file is read by
a person as well as by the kernel."
  (if (null rules)
      "[]"
    (concat "[\n  "
            (string-join (mapcar (lambda (rule)
                                   (json-serialize (yeah-perm--rule->json rule)))
                                 rules)
                         ",\n  ")
            "\n]")))

(defun yeah-perm--write-rules-file (file rules)
  "Write RULES into FILE and return FILE.
The file is written atomically: the rules go into a temporary file of
the same directory and the temporary file takes the place of the file.
A reader of the file never sees half of it."
  (let* ((directory (file-name-directory file))
         (temporary nil))
    (make-directory directory t)
    (setq temporary (make-temp-file (expand-file-name "yeah-rules-" directory)))
    (unwind-protect
        (progn
          (with-temp-file temporary
            (insert (yeah-perm--rules->json rules) "\n"))
          (rename-file temporary file t))
      (when (file-exists-p temporary)
        (delete-file temporary)))))

(defun yeah-perm-file-rules ()
  "Return the rules of the carriers that keep their rules in a file.
The broadest carrier comes first: the last matching rule wins, and the
rules of a project are narrower than the rules of the user.
A file that is broken is a refusal that names the file: a rule that
cannot be read is never ignored."
  (let ((rules nil))
    (dolist (entry (reverse yeah-perm--carriers))
      (when-let ((file (nth 3 entry)))
        (setq rules (append rules (yeah-perm--read-rules-file (funcall file))))))
    rules))

(defun yeah-perm-effective-rules ()
  "Return the rules that decide for the person.
The rules of the carriers that keep their rules in a file come first:
they are the standing policy of the user and of the project.  The
rules of the process come last: they are the rules that the Emacs
holds in its memory, and they are the freshest."
  (append (yeah-perm-file-rules) (yeah-perm-rules-list)))

(defun yeah-perm-rule-store (rule &optional carrier store)
  "Store RULE in the carrier of the scope that RULE carries.
CARRIER is the carrier of the path that stores the rule, and STORE is
the function that stores a rule in it.  A carrier that keeps its rules
in a file is written here.
A scope that has no carrier, and a scope whose carrier the path does
not hold, are refused by name: the rule is never written into the
carrier of another scope.  Return RULE."
  (let* ((scope (plist-get rule :scope))
         (entry (yeah-perm--carrier-entry scope)))
    (cond
     ((null entry)
      (signal 'user-error
              (list (format "yeah-perm-rule-store: the scope %s has no carrier: nothing holds the rules of that scope"
                            scope))))
     ((nth 3 entry)
      (let ((file (funcall (nth 3 entry)))
            (rules (yeah-perm--read-rules-file file)))
        (unless (member rule rules)
          (setq rules (append rules (list rule))))
        (yeah-perm--write-rules-file file rules))
      rule)
     ((and carrier store (eq (nth 1 entry) carrier))
      (funcall store rule))
     (t
      (signal 'user-error
              (list (format "yeah-perm-rule-store: the scope %s has no carrier here: %s"
                            scope (nth 2 entry))))))))

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

RULES defaults to the rules that decide for the person: the rules of
the process and the rules of the carriers that keep their rules in a
file (`yeah-perm-effective-rules').  The effect is one of `:allow',
`:deny' or `:ask'.  The last matching rule wins, and no match means
`:ask'.  This is the query without the signal: a caller that has
somewhere else to ask asks there."
  (let ((last-match nil)
        (rule nil)
        (rest (or rules (yeah-perm-effective-rules))))
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