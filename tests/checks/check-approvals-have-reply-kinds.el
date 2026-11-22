;;; check-approvals-have-reply-kinds.el --- canary for the approvals -*- lexical-binding: t; no-byte-compile: t -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A person answers a request for permission once, for the session, for the
;; project, always or reject.  ONCE is for this call and is forgotten.
;; SESSION is for the carrier of the path that asks: the rules of the run
;; of an attached run, the rules of the session of an ACP session, and the
;; file of the user in the plain path, which has no session of its own.
;; PROJECT is for the file of the project and GLOBAL is for the file of the
;; user.  REJECT is for this call and is forgotten.
;;
;; The legacy name `always' is the answer `session': the scope of the path
;; that asks.  The wire name `allow-always' is read the same way.
;;
;; A run with nobody at the keyboard does not ask a question it cannot
;; answer: the policy answers from the rules, allowing what the rules
;; allow and refusing everything else.
;;
;; The check works in temporary directories: the configuration of the user
;; and the root of the project are bound to them, so the check writes
;; nothing into the machine of the person.
;;
;; Exit codes: 0 — the answers behave; 1 — they do not.

;;; Code:

(require 'yeah-approval)
(require 'yeah-perm)

(defun yeah-check--temp-directory (prefix)
  "Return a fresh temporary directory whose name starts with PREFIX."
  (let* ((file (make-temp-file prefix))
         (directory (file-name-concat (file-name-directory file)
                                      (file-name-nondirectory file))))
    (delete-file file)
    (make-directory directory t)
    directory))

(defun yeah-check--scope-of-rule ()
  "Return the scope of the rule that the process holds now, or nil."
  (plist-get (car (yeah-perm-rules-list)) :scope))

(defun yeah-check--rules-of-file (file)
  "Return the rules that FILE holds, or nil when there is no file."
  (when (file-exists-p file)
    (yeah-perm--read-rules-file file)))

(let ((failures nil)
      (request (yeah-approval-request "edit" "/tmp/file.el"))
      (project (yeah-check--temp-directory "yeah-approvals-project"))
      (config (yeah-check--temp-directory "yeah-approvals-config")))

  (unwind-protect
      (progn
        (let ((yeah-perm-config-home config))
          (cl-letf (((symbol-function 'yeah-product-project-root)
                      (lambda () project)))

            ;; --- the dictionary of the answers ---------------------------
            (let ((answers (yeah-approval-reply-kinds)))
              (unless (equal answers '(:once :session :project :global :reject))
                (push (format "the dictionary of the answers is %S, not the four scopes and the refusal"
                              answers)
                      failures))
              ;; the scope of the run is not an answer: the person is
              ;; never asked to make a rule that dies with the run.
              (when (memq :run answers)
                (push "the scope of the run is offered as an answer" failures)))

            ;; --- the legacy answer `always' is the answer `session' -----
            (unless (eq (yeah-approval-reply-canonical 'always) :session)
              (push "the legacy answer always is not the answer session" failures))
            (unless (eq (yeah-approval-reply-canonical :always) :session)
              (push "the legacy answer :always is not the answer session" failures))
            (let ((reply (yeah-approval-reply-from-wire "allow-always")))
              (unless (and reply
                           (eq (yeah-approval-reply-canonical reply) :session))
                (push "the legacy wire answer allow-always is not the answer session"
                      failures)))

            ;; --- the answers ----------------------------------------------
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
              ;; the legacy answer names the scope of the path that asks
              ;; and not the scope of the user: the plain path has no
              ;; session of its own, and its carrier is the file of the
              ;; user.
              (unless (eq :global (yeah-check--scope-of-rule))
                (push (format "the rule of the legacy answer carries the scope %S, not :global"
                              (yeah-check--scope-of-rule))
                      failures))
              ;; and the answer outlives the question: the rules now allow it
              (let ((later (yeah-approval-policy-decision request)))
                (unless (eq (plist-get later :effect) :allow)
                  (push "the answer always did not outlive the question" failures))))

            (yeah-perm-rules-reset-for-test)
            (let ((decision (yeah-approval-reply-decision request 'session)))
              (unless (eq (plist-get decision :effect) :allow)
                (push "the answer session did not allow the call" failures))
              (unless (= 1 (length (yeah-perm-rules-list)))
                (push "the answer session was not written into the rules" failures))
              (unless (eq :global (yeah-check--scope-of-rule))
                (push (format "the rule of the answer session carries the scope %S, not the scope of the carrier of the plain path"
                              (yeah-check--scope-of-rule))
                      failures)))

            (yeah-perm-rules-reset-for-test)
            (let ((decision (yeah-approval-reply-decision request 'project)))
              (unless (eq (plist-get decision :effect) :allow)
                (push "the answer project did not allow the call" failures))
              (unless (eq :project (plist-get decision :scope))
                (push (format "the answer project carries the scope %S, not :project"
                              (plist-get decision :scope))
                      failures))
              ;; the rule of the project is in the file of the project and
              ;; in no other carrier
              (unless (null (yeah-perm-rules-list))
                (push "the answer project wrote a rule into the rules of the process"
                      failures))
              (let ((file (yeah-perm--project-rules-file)))
                (unless (file-exists-p file)
                  (push "the answer project wrote no file of the project" failures))
                (when (file-exists-p file)
                  (let ((rules (yeah-perm--read-rules-file file)))
                    (unless (seq-find (lambda (rule)
                                        (eq :project (plist-get rule :scope)))
                                      rules)
                      (push "the file of the project holds no rule of the project"
                            failures)))))
              (unless (null (yeah-check--rules-of-file
                             (yeah-perm--user-rules-file)))
                (push "the rule of the project landed in the file of the user"
                      failures)))

            (yeah-perm-rules-reset-for-test)
            (let ((decision (yeah-approval-reply-decision request 'global)))
              (unless (eq (plist-get decision :effect) :allow)
                (push "the answer global did not allow the call" failures))
              (unless (= 1 (length (yeah-perm-rules-list)))
                (push "the answer global was not written into the rules" failures))
              (unless (eq :global (yeah-check--scope-of-rule))
                (push (format "the rule of the answer global carries the scope %S, not :global"
                              (yeah-check--scope-of-rule))
                      failures))
              ;; the rule of the user landed in the file of the user
              (let ((file (yeah-perm--user-rules-file)))
                (unless (file-exists-p file)
                  (push "the answer global wrote no file of the user" failures))
                (when (file-exists-p file)
                  (let ((rules (yeah-perm--read-rules-file file)))
                    (unless (seq-find (lambda (rule)
                                        (eq :global (plist-get rule :scope)))
                                      rules)
                      (push "the file of the user holds no rule of the user"
                            failures))))))

            ;; --- an answer that is not an answer ---------------------------
            (condition-case nil
                (progn
                  (yeah-approval-reply-decision request 'perhaps)
                  (push "an answer that is not an answer was accepted" failures))
              (user-error nil))

            ;; --- the policy of a run with nobody watching ------------------
            (yeah-perm-rules-reset-for-test)
            (let ((decision (yeah-approval-policy-decision request)))
              (unless (eq (plist-get decision :effect) :deny)
                (push "the policy allowed a call the rules do not name" failures)))

            (yeah-perm-rules-reset-for-test)
            (yeah-perm-rules-add (yeah-perm-rule-make "edit" "/tmp/file.el" 'allow))
            (let ((decision (yeah-approval-policy-decision request)))
              (unless (eq (plist-get decision :effect) :allow)
                (push "the policy refused a call the rules allow" failures)))

            ;; --- the person: the answerer asks, and the answer is written -
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

            ;; --- the check leaves no rule behind ---------------------------
            ;; The answer of the person became a rule of the scope of the user, and
            ;; that rule was written into the file of the user.  The check takes it
            ;; back: a test does not change the machine of the person, and a check
            ;; that leaves a rule behind decides the next run by the state of the
            ;; machine and not by the code.
            (yeah-perm-rules-reset-for-test)
            (unless (null (yeah-perm-rules-list))
              (push "the check left a rule behind" failures))
            (unless (null (yeah-perm-file-rules))
              (push "the check left a rule in the file of the user behind" failures)))))

    (ignore-errors (delete-directory project t))
    (ignore-errors (delete-directory config t)))

  (dolist (failure failures)
    (message "approvals: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-approvals-have-reply-kinds.el ends here
