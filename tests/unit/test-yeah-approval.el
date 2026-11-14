;;; test-yeah-approval.el --- ERT tests for the approvals -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; The kernel asks; something answers.  The tests below ask what the
;; answerers promise: the policy answers from the rules, a person answers
;; once, always or reject, and a profile refuses what it forbids before
;; either of them is asked.

;;; Code:

(require 'ert)
(require 'yeah-approval)
(require 'yeah-perm)

(ert-deftest yeah-approval-policy-allows-what-the-rules-allow ()
  "The policy answers from the rules."
  (yeah-perm-rules-reset-for-test)
  (yeah-perm-rules-add (yeah-perm-rule-make "read" "*" 'allow))
  (let ((decision (yeah-approval-policy-decision
                   (list :action "read" :resource "/tmp/x"))))
    (should (eq :allow (plist-get decision :effect)))
    (should (eq :once (plist-get decision :reply)))))

(ert-deftest yeah-approval-policy-refuses-what-it-does-not-know ()
  "A question nobody is there to answer is refused."
  (yeah-perm-rules-reset-for-test)
  (let ((decision (yeah-approval-policy-decision
                   (list :action "bash" :resource "/bin/ls"))))
    (should (eq :deny (plist-get decision :effect)))
    (should (eq :reject (plist-get decision :reply)))))

(ert-deftest yeah-approval-reply-decision-remembers-an-always ()
  "An `always' answer becomes a rule of the person."
  (unwind-protect
      (progn
        (yeah-perm-rules-reset-for-test)
        (let ((decision (yeah-approval-reply-decision
                         (list :action "read" :resource "/tmp/x") 'always)))
          (should (eq :allow (plist-get decision :effect)))
          (should (= 1 (length (yeah-perm-rules-list))))))
    ;; the rule of this test belongs to this test
    (yeah-perm-rules-reset-for-test)))

(ert-deftest yeah-approval-profile-refuses-before-anything-is-asked ()
  "The plan profile refuses the tools that change the world, and the
person is not asked about them."
  (let* ((asked nil)
         (answerer (yeah-approval-profile-answerer
                    "plan"
                    (lambda (request)
                      (setq asked request)
                      (list :effect :allow :reply :once))))
         (decision (funcall answerer (list :action "edit"
                                             :resource "/tmp/x"))))
    (should (eq :deny (plist-get decision :effect)))
    (should-not asked)))

(ert-deftest yeah-approval-profile-asks-the-person-about-the-rest ()
  "What the profile does not forbid is left to the person."
  (let* ((asked nil)
         (answerer (yeah-approval-profile-answerer
                    "plan"
                    (lambda (request)
                      (setq asked request)
                      (list :effect :allow :reply :once))))
         (decision (funcall answerer (list :action "git_status"
                                             :resource "/tmp/x"))))
    (should asked)
    (should (eq :allow (plist-get decision :effect)))))

(ert-deftest yeah-approval-a-safe-read-needs-no-question ()
  "A read that changes nothing is not asked about: the decision says why."
  (let* ((asked nil)
         (answerer (yeah-approval-profile-answerer
                    "plan"
                    (lambda (request)
                      (setq asked request)
                      (list :effect :allow :reply :once))))
         (decision (funcall answerer (list :action "read"
                                             :resource "/tmp/x"))))
    (should-not asked)
    (should (eq :allow (plist-get decision :effect)))
    (should (string-match-p "safe read" (or (plist-get decision :reason) "")))))

(provide 'test-yeah-approval)
;;; test-yeah-approval.el ends here
