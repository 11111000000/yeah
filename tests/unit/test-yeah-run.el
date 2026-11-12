;;; test-yeah-run.el --- ERT tests for the run context -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; The run context is what a placement hands to the kernel: the session, the
;; transport, the answerer, the rules.  The tests below ask two things of
;; it: that two runs in one Emacs do not share one truth, and that the
;; policy of a run answers from its own rules and asks the person only for
;; what the rules do not decide.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-perm)
(require 'yeah-run)
(require 'yeah-session)

(defmacro yeah-run-test--with-rules (rules &rest body)
  "Run BODY with the global ruleset replaced by RULES."
  (declare (indent 1))
  `(let ((yeah-perm--rules ,rules))
     ,@body))

(defun yeah-run-test--session ()
  "Return a session in a temporary directory."
  (yeah-session-open "run" (make-temp-file "yeah-run-test" t)))

(defun yeah-run-test--transport (answers)
  "Return a transport that answers with the strings in ANSWERS."
  (let ((answers answers))
    (lambda (_prompt callback)
      (funcall callback (car answers))
      (setq answers (cdr answers)))))

(ert-deftest yeah-run-context-create-refuses-an-unknown-placement ()
  "A context names the placement it lives in."
  (should-error (yeah-run-context-create :placement 'nowhere)
                :type 'user-error))

(ert-deftest yeah-run-context-rules-start-as-a-copy-of-the-global-rules ()
  "The rules of a run are its own: changing them leaves the global ones alone."
  (yeah-run-test--with-rules
      (list (yeah-perm-rule-make "read" "*" 'allow))
    (let ((context (yeah-run-context-create :placement 'attached)))
      (should (equal (yeah-run-context-rules context)
                     (list (yeah-perm-rule-make "read" "*" 'allow))))
      (should-not (eq (yeah-run-context-rules context) yeah-perm--rules))
      (yeah-run-context-add-rule
       context (yeah-perm-rule-make "write" "*" 'allow))
      (should (= 2 (length (yeah-run-context-rules context))))
      (should (= 1 (length yeah-perm--rules))))))

(ert-deftest yeah-run-context-policy-allows-what-the-rules-allow ()
  "The rules of the run decide first."
  (let* ((context (yeah-run-context-create
                    :placement 'batch
                    :rules (list (yeah-perm-rule-make "read" "*" 'allow))))
         (answerer (yeah-run-context-policy context))
         (decision (funcall answerer (list :action "read" :resource "/tmp/x"))))
    (should (eq :allow (plist-get decision :effect)))))

(ert-deftest yeah-run-context-policy-denies-what-the-rules-deny ()
  "A rule that denies is a refusal, not a question."
  (let* ((context (yeah-run-context-create
                    :placement 'batch
                    :rules (list (yeah-perm-rule-make "read" "*" 'deny))))
         (answerer (yeah-run-context-policy context))
         (decision (funcall answerer (list :action "read" :resource "/tmp/x"))))
    (should (eq :deny (plist-get decision :effect)))))

(ert-deftest yeah-run-context-policy-asks-the-person-for-the-rest ()
  "What the rules do not name is asked of the person, when there is one."
  (let* ((asked nil)
         (context (yeah-run-context-create
                   :placement 'attached
                   :answerer (lambda (request)
                               (setq asked request)
                               (list :effect :allow :reply :once))))
         (answerer (yeah-run-context-policy context))
         (decision (funcall answerer (list :action "read"
                                            :resource "/tmp/x"))))
    (should asked)
    (should (eq :allow (plist-get decision :effect)))))

(ert-deftest yeah-run-context-policy-refuses-when-nobody-is-there ()
  "With nobody to ask, the answer is a refusal that says so."
  (let* ((context (yeah-run-context-create :placement 'batch))
         (answerer (yeah-run-context-policy context))
         (decision (funcall answerer (list :action "read"
                                            :resource "/tmp/x"))))
    (should (eq :deny (plist-get decision :effect)))
    (should (string-match-p "nobody answers"
                            (or (plist-get decision :reason) "")))))

(ert-deftest yeah-run-context-start-runs-the-turn-of-the-context ()
  "The transport, the rules and the session of the context reach the turn."
  (let* ((session (yeah-run-test--session))
         (context (yeah-run-context-create
                   :placement 'batch
                   :session session
                   :transport (yeah-run-test--transport '("the answer"))
                   :rules (list (yeah-perm-rule-make "read" "*" 'allow)))))
    (yeah-run-context-start context "the task")
    (let ((turn (yeah-run-context-turn context)))
      (should turn)
      (should (eq 'completed (yeah-turn-state turn)))
      (should (equal '("the task" "the answer")
                     (mapcar (lambda (record)
                               (plist-get record :payload))
                             (seq-filter (lambda (record)
                                           (member (plist-get record :type)
                                                   '("user-message"
                                                     "assistant-message")))
                                         (yeah-session-records session))))))))

(ert-deftest yeah-run-context-cancel-marks-the-context ()
  "A cancelled context stays cancelled: a cancelled run is not restarted."
  (let* ((session (yeah-run-test--session))
         (context (yeah-run-context-create
                   :placement 'batch
                   :session session
                   :transport (lambda (_prompt _callback) nil))))
    (should-not (yeah-run-context-cancelled-p context))
    (yeah-run-context-cancel context "because")
    (should (yeah-run-context-cancelled-p context))
    (should-error (yeah-run-context-start context "the task")
                  :type 'user-error)))

(provide 'test-yeah-run)
;;; test-yeah-run.el ends here
