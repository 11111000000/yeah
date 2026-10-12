;;; test-yeah-perm.el --- ERT tests for yeah-perm -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-perm.el'. The
;; positive tests exercise the happy paths (allow, wildcard,
;; last-matching-wins); the negative tests exercise the closest
;; plausible failure modes (deny raises, ask raises, no rule
;; defaults to ask).

;;; Code:

(require 'ert)
(require 'yeah-perm)

(ert-deftest yeah-perm-rule-make-returns-plist ()
  "`yeah-perm-rule-make' returns a plist with the three keys."
  (let ((rule (yeah-perm-rule-make "edit" "/tmp/foo.el" 'allow)))
    (should (consp rule))
    (should (string= "edit"        (plist-get rule :action)))
    (should (string= "/tmp/foo.el" (plist-get rule :resource)))
    (should (eq 'allow              (plist-get rule :effect)))))

(ert-deftest yeah-perm-rules-add-and-list ()
  "`yeah-perm-rules-add' appends; `yeah-perm-rules-list' returns
them in registration order."
  (yeah-perm-rules-reset-for-test)
  (let ((r1 (yeah-perm-rule-make "edit" "/tmp/foo.el" 'allow))
        (r2 (yeah-perm-rule-make "read" "/tmp/foo.el" 'ask))
        (r3 (yeah-perm-rule-make "shell" "*"             'deny)))
    (should (eq r1 (yeah-perm-rules-add r1)))
    (should (eq r2 (yeah-perm-rules-add r2)))
    (should (eq r3 (yeah-perm-rules-add r3)))
    (let ((got (yeah-perm-rules-list)))
      (should (= 3 (length got)))
      (should (eq r1 (nth 0 got)))
      (should (eq r2 (nth 1 got)))
      (should (eq r3 (nth 2 got))))))

(ert-deftest yeah-perm-evaluate-allow ()
  "`yeah-perm-evaluate' returns `:allow' when the last matching
rule has effect `allow'."
  (yeah-perm-rules-reset-for-test)
  (yeah-perm-rules-add (yeah-perm-rule-make "edit" "/tmp/foo.el" 'allow))
  (should (eq :allow (yeah-perm-evaluate "edit" "/tmp/foo.el"))))

(ert-deftest yeah-perm-evaluate-deny-errors ()
  "`yeah-perm-evaluate' raises `user-error' with message starting
\"deny: \" when the last matching rule has effect `deny'."
  (yeah-perm-rules-reset-for-test)
  (yeah-perm-rules-add (yeah-perm-rule-make "shell" "*" 'deny))
  (let ((err nil)
        (msg nil))
    (condition-case c
        (yeah-perm-evaluate "shell" "/bin/rm")
      (user-error
       (setq err t msg (cadr c))))
    (should err)
    (should (stringp msg))
    (should (string-prefix-p "deny: " msg))
    (should (string-match-p "shell"  msg))
    (should (string-match-p "/bin/rm" msg))))

(ert-deftest yeah-perm-evaluate-ask-errors ()
  "`yeah-perm-evaluate' raises `user-error' with message starting
\"ask: \" when the last matching rule has effect `ask'."
  (yeah-perm-rules-reset-for-test)
  (yeah-perm-rules-add (yeah-perm-rule-make "edit" "/tmp/foo.el" 'ask))
  (let ((err nil)
        (msg nil))
    (condition-case c
        (yeah-perm-evaluate "edit" "/tmp/foo.el")
      (user-error
       (setq err t msg (cadr c))))
    (should err)
    (should (stringp msg))
    (should (string-prefix-p "ask: " msg))
    (should (string-match-p "edit"         msg))
    (should (string-match-p "/tmp/foo.el"  msg))))

(ert-deftest yeah-perm-evaluate-wildcard-resource ()
  "A rule whose resource is `\"*\"' matches any resource for the
same action."
  (yeah-perm-rules-reset-for-test)
  (yeah-perm-rules-add (yeah-perm-rule-make "shell" "*" 'deny))
  (let ((err nil))
    (condition-case nil
        (yeah-perm-evaluate "shell" "/bin/ls")
      (user-error (setq err t)))
    (should err))
  (yeah-perm-rules-reset-for-test)
  (yeah-perm-rules-add (yeah-perm-rule-make "shell" "*" 'allow))
  (should (eq :allow (yeah-perm-evaluate "shell" "/bin/ls"))))

(ert-deftest yeah-perm-last-matching-rule-wins ()
  "When two rules match the same query, the one added **last**
wins (opencode v2 semantics)."
  (yeah-perm-rules-reset-for-test)
  (yeah-perm-rules-add (yeah-perm-rule-make "edit" "/tmp/foo.el" 'allow))
  (yeah-perm-rules-add (yeah-perm-rule-make "edit" "/tmp/foo.el" 'deny))
  (let ((err nil))
    (condition-case nil
        (yeah-perm-evaluate "edit" "/tmp/foo.el")
      (user-error (setq err t)))
    (should err))
  (yeah-perm-rules-reset-for-test)
  (yeah-perm-rules-add (yeah-perm-rule-make "edit" "/tmp/foo.el" 'deny))
  (yeah-perm-rules-add (yeah-perm-rule-make "edit" "/tmp/foo.el" 'allow))
  (should (eq :allow (yeah-perm-evaluate "edit" "/tmp/foo.el"))))

(ert-deftest yeah-perm-no-rule-defaults-to-ask ()
  "When no rule matches, the default effect is `:ask'; the
evaluator raises `user-error'."
  (yeah-perm-rules-reset-for-test)
  (let ((err nil)
        (msg nil))
    (condition-case c
        (yeah-perm-evaluate "shell" "/bin/rm")
      (user-error
       (setq err t msg (cadr c))))
    (should err)
    (should (string-prefix-p "ask: " msg))))

(provide 'test-yeah-perm)
;;; test-yeah-perm.el ends here