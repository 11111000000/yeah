;;; check-approvals-have-reply-kinds.el --- canary for the approvals -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A person answers a request for permission once, always or reject. ONCE
;; is for this call. ALWAYS is written into the rules, so it outlives the
;; question. REJECT is for this call and is forgotten.
;;
;; A run with nobody at the keyboard does not ask a question it cannot
;; answer: the policy answers from the rules, allowing what the rules
;; allow and refusing everything else.
;;
;; Exit codes: 0 — the answers behave; 1 — they do not.

;;; Code:

(require 'yeah-approval)
(require 'yeah-perm)

(let ((failures nil)
      (request (yeah-approval-request "edit" "/tmp/file.el")))

  ;; --- the three answers ------------------------------------------------
  (yeah-perm-rules-reset-for-test)
  (let ((decision (yeah-approval-reply-decision request 'once)))
    (unless (eq (plist-get decision :effect) :allow)
      (push "the answer once did not allow the call" failures))
    (unless (null (yeah-perm-rules-list))
      (push "the answer once was written into the rules" failures)))

  (yeah-perm-rules-reset-for-test)
  (let ((decision (yeah-approval-reply-decision request 'reject)))
    (unless (eq (plist-get decision :effect) :deny)
      (push "the answer reject did not refuse the call" failures))
    (unless (null (yeah-perm-rules-list))
      (push "the answer reject was written into the rules" failures)))

  (yeah-perm-rules-reset-for-test)
  (let ((decision (yeah-approval-reply-decision request 'always)))
    (unless (eq (plist-get decision :effect) :allow)
      (push "the answer always did not allow the call" failures))
    (unless (= 1 (length (yeah-perm-rules-list)))
      (push "the answer always was not written into the rules" failures))
    ;; and the answer outlives the question: the rules now allow it
    (let ((later (yeah-approval-policy-decision request)))
      (unless (eq (plist-get later :effect) :allow)
        (push "the answer always did not outlive the question" failures))))

  ;; --- an answer that is not an answer ----------------------------------
  (condition-case nil
      (progn
        (yeah-approval-reply-decision request 'perhaps)
        (push "an answer that is not an answer was accepted" failures))
    (user-error nil))

  ;; --- the policy of a run with nobody watching -------------------------
  (yeah-perm-rules-reset-for-test)
  (let ((decision (yeah-approval-policy-decision request)))
    (unless (eq (plist-get decision :effect) :deny)
      (push "the policy allowed a call the rules do not name" failures)))

  (yeah-perm-rules-reset-for-test)
  (yeah-perm-rules-add (yeah-perm-rule-make "edit" "/tmp/file.el" 'allow))
  (let ((decision (yeah-approval-policy-decision request)))
    (unless (eq (plist-get decision :effect) :allow)
      (push "the policy refused a call the rules allow" failures)))

  ;; --- the person: the answerer asks, and the answer is written --------
  (yeah-perm-rules-reset-for-test)
  (let* ((asked nil)
         (answerer (yeah-approval-person-answerer
                    (lambda (req) (setq asked req) 'always)))
         (decision (funcall answerer request)))
    (unless asked
      (push "the person was not asked" failures))
    (unless (eq (plist-get decision :effect) :allow)
      (push "the person allowed the call and the decision refused it" failures))
    (unless (= 1 (length (yeah-perm-rules-list)))
      (push "the answer of the person did not reach the rules" failures)))

  (dolist (failure failures)
    (message "approvals: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-approvals-have-reply-kinds.el ends here
