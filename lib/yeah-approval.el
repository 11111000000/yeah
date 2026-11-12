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

;;; Code:

(require 'cl-lib)
(require 'yeah-perm)

(defconst yeah-approval--replies '(once always reject)
  "The answers a person may give to a request for permission.")

(defun yeah-approval-request (action resource)
  "Return a request for permission to run ACTION on RESOURCE."
  (list :action action :resource resource))

(defun yeah-approval-reply-p (reply)
  "Non-nil when REPLY is one of the answers a person may give."
  (memq reply yeah-approval--replies))

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
first: a tool the profile forbids is refused, and everything else is
left to the person."
  (let* ((rules (yeah-perm-profile profile))
         (action (plist-get request :action))
         (resource (plist-get request :resource))
         (effect (if rules
                     (yeah-perm-effect action resource rules)
                   'ask)))
    (if (eq effect 'deny)
        (list :effect :deny :reply :reject
              :reason (format "the %s profile does not allow %s" profile action))
      (funcall (or person #'yeah-approval-policy-decision) request))))

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

(provide 'yeah-approval)
;;; yeah-approval.el ends here
