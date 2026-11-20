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
;;   * the PERSON, who answers once, always or reject. ONCE is for this
;;     call. ALWAYS is for this call and every later one of the same
;;     shape: the answer is written into the rules, and the rules are
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

(defconst yeah-approval--replies '(once always reject)
  "The answers a person may give to a request for permission.")

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

(defun yeah-approval-reply-p (reply)
  "Non-nil when REPLY is one of the answers a person may give."
  (memq reply yeah-approval--replies))

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

(defun yeah-approval-always-p (decision)
  "Return non-nil when DECISION is an answer that is to be remembered."
  (memq (plist-get decision :reply) '(always :always)))

(defun yeah-approval-remember-rule (request decision)
  "Return the rule that remembers DECISION for REQUEST, or nil.
An `always' answer becomes an allow rule for the exact action and the
exact resource of REQUEST; every other answer is forgotten."
  (when (and (eq (plist-get decision :effect) :allow)
             (yeah-approval-always-p decision))
    (yeah-perm-rule-make (plist-get request :action)
                         (plist-get request :resource)
                         'allow)))

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

(defun yeah-approval-reply-decision (request reply)
  "Answer REQUEST with REPLY, which is `once', `always' or `reject'.
ALWAYS is written into the rules, so that the answer outlives the
question. Return the decision."
  (unless (yeah-approval-reply-p reply)
    (signal 'user-error
            (list (format "yeah-approval: %S is not an answer" reply))))
  (pcase reply
    ('once
     (list :effect :allow :reply :once))
    ('reject
     (list :effect :deny :reply :reject))
    ('always
     (yeah-perm-rules-add
      (yeah-perm-rule-make (plist-get request :action)
                           (plist-get request :resource)
                           'allow))
     (list :effect :allow :reply :always))))

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
ANSWER is a function of the REQUEST; it returns the reply, which is
`once', `always' or `reject'."
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

(defun yeah-approval--deny (reason)
  "Return the refusal of a question that could not be answered.
REASON says why the question was refused."
  (list :effect :deny :reply :reject :reason reason))

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
                            "the answer did not come in time"))))))
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
