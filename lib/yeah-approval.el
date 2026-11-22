;;; yeah-approval.el --- asking, and answering -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A run of the agent may have a person at the keyboard or may not. Both
;; are normal, and the kernel must not know which it is: it asks, and
;; something answers. The something is the ANSWERER, and it is handed to
;; the kernel the way the transport is handed to it.
;;
;; There are two kinds of answerer:
;;
;;   * the POLICY, which answers from the rules. It is the answerer of a
;;     run with nobody watching: it allows what the rules allow and
;;     refuses everything else. A run without a person does not ask a
;;     question it cannot answer; it answers it from the rules.
;;
;;   * the PERSON, who answers once, for the session, for the project,
;;     always or reject. ONCE is for this call and is forgotten. SESSION
;;     is for the carrier of the path that asks: the rules of the run,
;;     the rules of the session, or the rules of the process. PROJECT is
;;     for the file of the project and ALWAYS is for the file of the
;;     user: the answer is written into the rules, and the rules are
;;     what the policy reads. REJECT is for this call, and it is not
;;     remembered.
;;
;; So the two kinds are not two truths about what may happen: the person
;; answers, the answer is written into the rules, and the rules are the
;; only thing the kernel ever consults.
;;
;; A SAFE READ is the third thing the kernel knows: an action that only
;; looks.  A safe read needs no question — there is nothing in it to
;; approve — but the rules still decide what they name, and an explicit
;; refusal of a safe read stays a refusal.  The safe read answers itself,
;; and it says why in the decision, so the journal shows the reason the
;; person was not asked.
;;
;; The answerer may also answer LATER.  A question asked over a wire, or
;; to a person who is not at the keyboard yet, is answered when the
;; answer arrives and not when it is asked.  `yeah-approval-async' marks
;; such an answerer: it is a function of (REQUEST DONE) that calls DONE
;; with the decision whenever it has one.  `yeah-approval-resolve' takes
;; either shape of answerer and settles the question exactly once: a
;; second answer is ignored, and a failure, a decision that is not a
;; decision, or a question that is not answered in time becomes a
;; refusal that says why.

;;; Code:

(require 'cl-lib)
(require 'yeah-perm)

(defconst yeah-approval--reply-kinds
  '(:once :session :project :global :reject)
  "The answers a person may give to a request for permission.

The answers are the scopes of a rule and the refusal: `once' is this
call, `session' is the carrier of the path that asks, `project' is the
file of the project and `global' is the file of the user.  The scope
`run' is not an answer: the person is never asked to make a rule that
dies with the run.

This is the one canonical enumeration of the answers: every surface of
the kernel converts its own names into these, and none of them writes
the list again.")

(defconst yeah-approval--legacy-replies
  '(("always" . "session"))
  "The old names of the answers and the answers they name now.

The name `always' is the old name of the answer `session': the scope of
the path that asks.  The wire name `allow-always' is read the same way.

The reason is the scope.  The claims `an-answer-carries-a-scope' and
`a-scope-decides-where-the-rule-lives' give the old answer the scope of
the path that asks: the file of the user in the plain path, the run in
the attached path, the session of the ACP path.  Reading `always' as the
scope `global' would move the rule of the attached path out of the run
and into the file of the user: a change of behaviour that no document
asks for.

The alias is written here, next to the dictionary, and nowhere else.")

(defconst yeah-approval--carrier 'global
  "The carrier of the rules a plain answer writes: the rules of the
process.  The scope of that carrier is the scope of a plain answer.")

(defun yeah-approval-reply-kinds ()
  "Return the canonical answers a person may give."
  yeah-approval--reply-kinds)

(defun yeah-approval--kind-name (kind)
  "Return the name of the canonical kind KIND, without its colon."
  (let ((name (symbol-name kind)))
    (if (string-prefix-p ":" name)
        (substring name 1)
      name)))

(defun yeah-approval--reply-of-name (name)
  "Return the reply the name NAME spells, as it is spelled, or nil.
The dictionary is read here and written nowhere else.  A legacy name
spells the reply it used to spell: the name `always' spells the reply
`always', and the answer it names now is `session'."
  (or (seq-find (lambda (kind) (equal name (yeah-approval--kind-name kind)))
                yeah-approval--reply-kinds)
      (and (seq-find (lambda (pair) (equal name (car pair)))
                     yeah-approval--legacy-replies)
           (intern (concat ":" name) nil))))

(defun yeah-approval--kind-of-name (name)
  "Return the canonical answer the name NAME spells, or nil.
The dictionary is read here and written nowhere else.  A legacy name
spells the answer it used to spell: the name `always' spells the answer
`session'."
  (let ((reply (yeah-approval--reply-of-name name)))
    (when reply
      (if (memq reply yeah-approval--reply-kinds)
          reply
        ;; A legacy name: the answer it names now is written next to it.
        (let ((entry (seq-find (lambda (pair) (equal name (car pair)))
                               yeah-approval--legacy-replies)))
          (yeah-approval--kind-of-name (cdr entry)))))))

(defun yeah-approval-reply-canonical (reply)
  "Return the canonical answer of REPLY, or nil when it names no answer.
REPLY may be spelled as a symbol or as a keyword; the canonical answer
is the keyword.  The dictionary is read here and written nowhere else."
  (when (symbolp reply)
    (yeah-approval--kind-of-name (yeah-approval--kind-name reply))))

(defun yeah-approval-reply-p (reply)
  "Non-nil when REPLY is one of the answers a person may give."
  (and (yeah-approval-reply-canonical reply) t))

(defun yeah-approval--remembered-kinds ()
  "Return the answers that are written into the rules.
The answer of this call remembers nothing and the refusal remembers
nothing either; every other answer is remembered.  The answers are
taken from the one dictionary, and this module writes no list of them."
  (seq-remove (lambda (answer) (or (eq answer :once) (eq answer :reject)))
              yeah-approval--reply-kinds))

(defun yeah-approval-effect-of (answer)
  "Return the effect the answer ANSWER has.
The refusal refuses; every other answer allows.  ANSWER is an answer,
spelled as it is given."
  (if (eq (yeah-approval-reply-canonical answer) :reject) :deny :allow))

(defun yeah-approval-label (answer)
  "Return the words the surfaces of the kernel use for ANSWER.
The words are the ones of the plan: one time, this session, this
project, always, and the refusal.  The names are written here, next to
the dictionary of the answers, and nowhere else."
  (pcase (yeah-approval--kind-name answer)
    ("once" "Allow once")
    ("session" "Allow for this session")
    ("project" "Allow for this project")
    ("global" "Allow always")
    ("reject" "Reject")
    (_ (format "Allow %s" (yeah-approval--kind-name answer)))))

(defun yeah-approval-reply-on-wire (effect kind)
  "Return the wire name of the answer EFFECT with the canonical kind KIND.
EFFECT is `:allow' or `:deny' and KIND the answer, spelled as it is
given.  The wire spells the answers in its own words; the name is
derived from the answer, and no list of names is written here."
  (if (eq effect :allow)
      (concat "allow-" (yeah-approval--kind-name kind))
    "reject-once"))

(defun yeah-approval-reply-from-wire (name)
  "Return the reply the wire answer NAME spells, or nil.
The wire names the answers in its own words; the converter reads the
canonical dictionary and writes no list of names of its own.  A legacy
name spells the reply it used to spell: the wire name `allow-always'
spells the reply `always', which is the answer `session'."
  (when (stringp name)
    (cond
     ((string-prefix-p "allow-" name)
      (yeah-approval--reply-of-name (substring name (length "allow-"))))
     ((string-prefix-p "reject-" name) :reject)
     (t nil))))

(defun yeah-approval-scope-of (kind carrier)
  "Return the scope the answer KIND has in CARRIER.
KIND is an answer, spelled as it is given: the legacy name `always' is
the answer `session'.  An answer that remembers nothing is the scope of
this call, an answer that remembers a rule has the scope of the carrier
that holds it, and a refusal carries no scope at all.
CARRIER is the name of a holder of rules: `run', `session' or `global'."
  (pcase (yeah-approval-reply-canonical kind)
    (:once :once)
    (:session (yeah-perm-scope-of-carrier carrier))
    (:project :project)
    (:global :global)
    (_ nil)))

(defun yeah-approval-scope-decision (decision carrier)
  "Return DECISION with the scope its answer names in CARRIER.
CARRIER is the holder of the rules of the path: `run', `session' or
`global'.  The scope of an answer is the scope the answer names: the
answer `once' is the scope of this call, the answer `session' is the
scope of the carrier of the path that asks, and the answers `project'
and `global' are the scopes of the file of the project and of the file
of the user -- a file is reachable from every path.  A refusal carries
no scope at all.  A question that waits is not an answer and carries no
scope.

A decision that names a scope of its own must name the scope its
answer names: a decision that claims another scope comes back as a
refusal: the refusal names the scope and says why, and the scope is
never routed silently into the carrier of another path."
  (let* ((answer (yeah-approval-reply-canonical (plist-get decision :reply)))
         (named (plist-get decision :scope))
         (carrier-scope (yeah-perm-scope-of-carrier carrier))
         (scope (cond
                 ((plist-get decision :defer) nil)
                 (answer (yeah-approval-scope-of answer carrier))
                 (t nil))))
    (cond
     ;; A decision that is not an answer carries no scope.
     ((and (null named) (null answer)) decision)
     ;; The answer `session' needs a carrier that holds rules.
     ((and (eq answer :session) (null carrier-scope))
      (list :effect :deny :reply :reject
            :reason (format "the carrier %s holds no rules" carrier)))
     ;; A refusal carries no scope.
     ((null scope) decision)
     ;; The scope the decision names must be the scope its answer names.
     ((and named (not (eq named scope)))
      (list :effect :deny :reply :reject
            :reason (format "the scope %s is not the scope the answer names: %s"
                             named
                             (format "the answer names the scope of the carrier %s"
                                     carrier))))
     ((eq scope :once) (plist-put (copy-sequence decision) :scope :once))
     (t (plist-put (copy-sequence decision) :scope scope)))))

(defun yeah-approval-request (action resource &optional args tool-call-id)
  "Return a request for permission to run ACTION on RESOURCE.
ARGS, when given, are the arguments the tool would run with.  TOOL-CALL-ID
correlates the request with its journal events without changing the existing
`:action', `:resource', `:args' or deferred-answer contracts."
  (append (list :action action :resource resource)
          (when args
            (list :args args))
          (when tool-call-id
            (list :tool-call-id tool-call-id))))

(defconst yeah-approval-safe-read-actions
  '("read" "glob" "grep" "introspect" "buffer-read" "elisp-check"
    "diagnostics" "job-status" "job-read")
  "Read-oriented actions that need no question from the person.
A safe read only looks: it changes nothing.  The rules still decide what
they name, and an explicit refusal of a safe read stays a refusal.")

(defun yeah-approval-safe-read-p (request)
  "Return non-nil when REQUEST names a known safe read."
  (and (stringp (plist-get request :action))
       (member (plist-get request :action) yeah-approval-safe-read-actions)
       t))

(defun yeah-approval-safe-read-decision (request)
  "Return the decision of a safe read of REQUEST, or nil.
The decision allows the read and says why it needed no question: a read
changes nothing, so there is nothing to ask about."
  (when (yeah-approval-safe-read-p request)
    (list :effect :allow :reply :once
          :reason (format "%s is a safe read: it changes nothing"
                          (plist-get request :action)))))

(defun yeah-approval-remembers-p (decision)
  "Return non-nil when DECISION is an answer that is to be remembered.
The answer of this call is forgotten and the refusal is forgotten as
well; every other answer is written into the rules.  The answers are
read from the one dictionary of the answers: this module writes no list
of them of its own."
  (let ((answer (yeah-approval-reply-canonical (plist-get decision :reply))))
    (and (memq answer (yeah-approval--remembered-kinds)) t)))

(defun yeah-approval-remember-rule (request decision &optional scope)
  "Return the rule that remembers DECISION for REQUEST, or nil.
An answer that names a scope becomes an allow rule for the exact action
and the exact resource of REQUEST; every other answer is forgotten.
SCOPE, when given, is the canonical scope the rule belongs to; the scope
of DECISION is used when it is not.  The rule says where it lives."
  (when (and (eq (plist-get decision :effect) :allow)
             (yeah-approval-remembers-p decision))
    (yeah-perm-rule-make (plist-get request :action)
                         (plist-get request :resource)
                         'allow
                         (or scope (plist-get decision :scope)))))

(defun yeah-approval-policy-decision (request)
  "Answer REQUEST from the rules.
This is the answerer of a run with nobody at the keyboard: it allows
what the rules allow and refuses everything else. A question that
nobody is there to answer is answered by the rules, and the rules
refuse what they do not name."
  (let ((action (plist-get request :action))
        (resource (plist-get request :resource)))
    (condition-case err
        (if (eq (yeah-perm-evaluate action resource) :allow)
            (list :effect :allow :reply :once)
          (list :effect :deny :reply :reject :reason
                (format "the rules say %s" (plist-get request :action))))
      (user-error
       (list :effect :deny :reply :reject :reason (error-message-string err))))))

(defun yeah-approval--decision-of (answer reply)
  "Return the decision of the answer ANSWER, spelled as REPLY.
ANSWER is the canonical answer and REPLY the answer as the person gave
it: the legacy name `always' is the answer `session', and the decision
carries the name it was given."
  (cond
   ((null answer) nil)
   ((eq answer :reject) (list :effect :deny :reply :reject
                               :reason "rejected by the person"))
   (t (list :effect :allow :reply reply))))

(defun yeah-approval-reply-decision (request reply)
  "Answer REQUEST with REPLY, which is one of the answers.
The answers are `once', `session', `project', `global' and `reject'; the
legacy name `always' is the answer `session'.  The answer carries the
scope of the path that asks: the rule of the answer `session' is written
into the carrier of the plain path, the rule of the answer `project'
into the file of the project and the rule of the answer `global' into
the file of the user.  The rule the answer writes carries the same
scope: the rule is written into the carrier of its scope, and the rules
of the process keep it in the memory of the Emacs as well when it is
the rule of the person.  Return the decision."
  (let ((answer (yeah-approval-reply-canonical reply)))
    (unless answer
      (signal 'user-error
              (list (format "yeah-approval: %S is not an answer" reply))))
    (let* ((decision (yeah-approval--decision-of answer reply))
           (scoped (yeah-approval-scope-decision decision yeah-approval--carrier)))
      (when (yeah-approval-remembers-p scoped)
        (let ((rule (yeah-approval-remember-rule request scoped)))
          ;; The rules of the process keep the rule in the memory of the
          ;; Emacs when the rule is the rule of the person.  The rule of
          ;; the project belongs to the project: it is read from the file
          ;; of the project and from no other carrier.
          (when (eq (plist-get rule :scope)
                     (yeah-perm-scope-of-carrier yeah-approval--carrier))
            (yeah-perm-rules-add rule))
          ;; The carrier of the scope holds the rule: the file of the
          ;; user for the scope of the person, the file of the project
          ;; for the scope of the project.
          (yeah-perm-rule-store rule yeah-approval--carrier nil)))
      scoped)))

(defun yeah-approval-profile-decision (profile request &optional person)
  "Answer REQUEST under the permission profile PROFILE.

PERSON answers what the profile does not decide.  The profile decides
first: a tool the profile forbids is refused, a tool the profile allows
is allowed without a question, and everything else is left to the
person.  A safe read needs no question: when there is a person to ask,
the read answers itself and says why."
  (let* ((rules (yeah-perm-profile profile))
         (action (plist-get request :action))
         (resource (plist-get request :resource))
         (effect (if rules
                     (yeah-perm-effect action resource rules)
                   'ask)))
    (cond
     ((eq effect 'deny)
      (list :effect :deny :reply :reject
            :reason (format "the %s profile does not allow %s" profile action)))
     ((eq effect 'allow)
      (list :effect :allow :reply :once
            :reason (format "the %s profile allows %s without a question"
                            profile action)))
     (person
      (or (yeah-approval-safe-read-decision request)
          (funcall person request)))
     (t
      (funcall (or person #'yeah-approval-policy-decision) request)))))

(defun yeah-approval-profile-answerer (profile &optional person)
  "Return an answerer that answers under the permission profile PROFILE.
PERSON answers what the profile does not decide."
  (lambda (request)
    (yeah-approval-profile-decision profile request person)))

(defun yeah-approval-person-answerer (answer)
  "Return an answerer that asks the person through ANSWER.
ANSWER is a function of the REQUEST; it returns the reply, which is one
of the answers: `once', `session', `project', `global' or `reject'."
  (lambda (request)
    (let ((reply (funcall answer request)))
      (unless (yeah-approval-reply-p reply)
        (signal 'user-error
                (list (format "yeah-approval: %S is not an answer" reply))))
      (yeah-approval-reply-decision request reply))))

(cl-defstruct (yeah-approval-async-answerer
               (:constructor yeah-approval-async-answerer--make))
  "An answerer that answers later.

FUNCTION is a function of (REQUEST DONE): it asks the question and calls
DONE with the decision whenever the answer arrives.  TIMEOUT is an
optional positive number of seconds: a question that is not answered in
time is refused."
  function
  timeout)

(defun yeah-approval-async (answerer &optional timeout)
  "Mark ANSWERER as an answerer that answers later, and return it.

ANSWERER is a function of (REQUEST DONE): it asks the question and calls
DONE with the decision whenever the answer arrives.  TIMEOUT is an
optional positive number of seconds; a question that is not answered in
time is refused.  Without a timeout the deadline of the run is the bound.

The marked answerer is what `yeah-approval-resolve' takes: an ordinary
answerer and a marked one answer the same request."
  (unless (functionp answerer)
    (signal 'user-error
            (list "yeah-approval-async: ANSWERER must be a function")))
  (when (and timeout (not (and (numberp timeout) (> timeout 0))))
    (signal 'user-error
            (list "yeah-approval-async: TIMEOUT must be positive seconds")))
  (yeah-approval-async-answerer--make :function answerer :timeout timeout))

(defun yeah-approval--deny (reason &optional timeout)
  "Return the refusal of a question that could not be answered.
REASON says why the question was refused.  TIMEOUT says that the answer did
not come in time: the run that waits for the answer tells that in its state,
and the two are told apart."
  (let ((decision (list :effect :deny :reply :reject :reason reason)))
    (when timeout
      (plist-put decision :timeout t))
    decision))

(defun yeah-approval--decision-p (decision)
  "Return non-nil when DECISION is a decision the kernel understands.
A decision allows the call, refuses it, or defers it to an answer that
comes later."
  (and (listp decision)
       (or (memq (plist-get decision :effect) '(:allow :deny))
           (plist-get decision :defer))))

(defun yeah-approval-resolve (answerer request callback)
  "Answer REQUEST through ANSWERER and call CALLBACK with the decision.
CALLBACK is called exactly once, with the decision of the answer.

ANSWERER is either an ordinary answerer — a function of REQUEST that
answers at once — or one marked by `yeah-approval-async': a function of
(REQUEST DONE) that calls DONE with the decision whenever the answer
arrives.  A second answer is ignored.  An answerer that fails, a
decision that is not a decision, and a question that is not answered
within the timeout of a marked answerer become refusals that say why.

Return a function that ends the question: after it is called, an answer
that arrives later is ignored and CALLBACK is not called again.  An
ordinary answerer is answered before this function returns."
  (unless (functionp callback)
    (signal 'user-error
            (list "yeah-approval-resolve: CALLBACK must be a function")))
  (let ((settled nil)
        (closed nil)
        (timer nil))
    (cl-labels
        ((finish (decision)
          (unless (or settled closed)
            (setq settled t)
            (when timer
              (cancel-timer timer)
              (setq timer nil))
            (unless (yeah-approval--decision-p decision)
              (setq decision
                    (yeah-approval--deny
                     (format "the answerer returned %S" decision))))
            (funcall callback decision)))
         (close ()
          (setq closed t)
          (when timer
            (cancel-timer timer)
            (setq timer nil))))
      (cond
       ((yeah-approval-async-answerer-p answerer)
        (when-let ((timeout (yeah-approval-async-answerer-timeout answerer)))
          (setq timer
                (run-at-time
                 timeout nil
                 (lambda ()
                   (finish (yeah-approval--deny
                            "the answer did not come in time" t))))))
        (condition-case err
            (funcall (yeah-approval-async-answerer-function answerer)
                     request #'finish)
          (error
           (if settled
               (signal (car err) (cdr err))
             (finish (yeah-approval--deny
                      (format "the answerer failed: %s"
                              (error-message-string err))))))))
       ((functionp answerer)
        (let ((decision nil))
          (condition-case err
              (setq decision (funcall answerer request))
            (error
             (setq decision
                   (yeah-approval--deny
                    (format "the answerer failed: %s"
                            (error-message-string err))))))
          (finish decision)))
       (t
        (finish (yeah-approval--deny "there is no answerer"))))
      (lambda () (close)))))

(provide 'yeah-approval)
;;; yeah-approval.el ends here
