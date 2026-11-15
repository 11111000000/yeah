;;; test-yeah-approval.el --- ERT tests for the approvals -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; The kernel asks; something answers.  The tests below ask what the
;; answerers promise: the policy answers from the rules, a person answers
;; once, always or reject, and a profile refuses what it forbids before
;; either of them is asked.
;;
;; The answerer may also answer later.  A question asked over a wire, or
;; to a person who is not at the keyboard yet, is answered when the answer
;; arrives: the adapter settles it exactly once, ignores a second answer,
;; refuses a question that is not answered in time, and forgets a question
;; whose run has ended.

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

(defun yeah-approval-test--request ()
  "Return a request for permission to edit a file."
  (yeah-approval-request "edit" "/tmp/x" nil "call-1"))

(ert-deftest yeah-approval-resolve-answers-an-ordinary-answerer-at-once ()
  "An answerer that answers at once is answered before the resolve returns."
  (let ((decision nil))
    (yeah-approval-resolve
     (lambda (_request) (list :effect :allow :reply :once))
     (yeah-approval-test--request)
     (lambda (answer) (setq decision answer)))
    (should (eq :allow (plist-get decision :effect)))
    (should (eq :once (plist-get decision :reply)))))

(ert-deftest yeah-approval-async-answerer-answers-later ()
  "An answerer that answers later settles the question when the answer comes."
  (let ((done nil)
        (decision nil))
    (yeah-approval-resolve
     (yeah-approval-async (lambda (_request answer) (setq done answer)))
     (yeah-approval-test--request)
     (lambda (answer) (setq decision answer)))
    (should-not decision)
    (should done)
    (funcall done (list :effect :allow :reply :once))
    (should (eq :allow (plist-get decision :effect)))))

(ert-deftest yeah-approval-async-answerer-settles-only-once ()
  "A second answer is ignored: the question is settled exactly once."
  (let* ((answers 0)
         (done nil))
    (yeah-approval-resolve
     (yeah-approval-async (lambda (_request answer) (setq done answer)))
     (yeah-approval-test--request)
     (lambda (_answer) (cl-incf answers)))
    (funcall done (list :effect :allow :reply :once))
    (funcall done (list :effect :deny :reply :reject))
    (should (= 1 answers))))

(ert-deftest yeah-approval-an-answer-after-the-run-ended-is-ignored ()
  "A question that is over does not call back when the answer arrives late."
  (let* ((answers 0)
         (done nil)
         (close
          (yeah-approval-resolve
           (yeah-approval-async (lambda (_request answer) (setq done answer)))
           (yeah-approval-test--request)
           (lambda (_answer) (cl-incf answers)))))
    (funcall close)
    (funcall done (list :effect :allow :reply :once))
    (should (= 0 answers))))

(ert-deftest yeah-approval-a-question-that-is-not-answered-in-time-is-refused ()
  "A question that waits too long is refused, and the refusal says why."
  (let ((decision nil))
    (yeah-approval-resolve
     (yeah-approval-async (lambda (_request _answer) nil) 0.01)
     (yeah-approval-test--request)
     (lambda (answer) (setq decision answer)))
    (should-not decision)
    (sit-for 0.1)
    (should (eq :deny (plist-get decision :effect)))
    (should (string-match-p "in time" (or (plist-get decision :reason) "")))))

(ert-deftest yeah-approval-a-decision-that-is-not-a-decision-is-refused ()
  "An answer that says nothing the kernel understands is a refusal."
  (let ((decision nil))
    (yeah-approval-resolve
     (lambda (_request) 'perhaps)
     (yeah-approval-test--request)
     (lambda (answer) (setq decision answer)))
    (should (eq :deny (plist-get decision :effect)))
    (should (plist-get decision :reason))))

(ert-deftest yeah-approval-an-answerer-that-fails-is-refused ()
  "An answerer that raises an error is a refusal, not a broken run."
  (let ((decision nil))
    (yeah-approval-resolve
     (lambda (_request) (signal 'user-error "the person is gone"))
     (yeah-approval-test--request)
     (lambda (answer) (setq decision answer)))
    (should (eq :deny (plist-get decision :effect)))
    (should (string-match-p "failed" (or (plist-get decision :reason) "")))))

(ert-deftest yeah-approval-async-needs-a-function-and-a-positive-timeout ()
  "The mark of an answerer that answers later is checked."
  (should-error (yeah-approval-async "not a function") :type 'user-error)
  (should-error (yeah-approval-async (lambda (_r _d) nil) 0)
                :type 'user-error)
  (should-error (yeah-approval-async (lambda (_r _d) nil) -1)
                :type 'user-error))

(provide 'test-yeah-approval)
;;; test-yeah-approval.el ends here
