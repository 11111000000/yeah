;;; test-yeah-perm.el --- ERT tests for yeah-perm -*- lexical-binding: t; no-byte-compile: t -*-
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
(require 'yeah-tools)

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

(ert-deftest yeah-perm-profile-plan-denies-the-tools-that-change-the-world ()
  "The plan profile refuses the tools that change the world and says
nothing about the others."
  (let ((rules (yeah-perm-profile "plan")))
    (should (eq 'deny (yeah-perm-effect "edit" "/tmp/x" rules)))
    (should (eq 'deny (yeah-perm-effect "bash" "/bin/ls" rules)))
    (should (eq 'ask (yeah-perm-effect "read" "/tmp/x" rules)))))

(ert-deftest yeah-perm-profile-build-asks-for-the-tools-that-change-the-world ()
  "The build profile asks the person about the tools that change the
world and says nothing about the others."
  (let ((rules (yeah-perm-profile "build")))
    (should (eq 'ask (yeah-perm-effect "edit" "/tmp/x" rules)))
    (should (eq 'ask (yeah-perm-effect "read" "/tmp/x" rules)))))

(ert-deftest yeah-perm-profile-workspace-asks-for-the-tools-that-change-the-world ()
  "The workspace profile starts as ask-only; the route remembers the
person's workspace-wide answer."
  (let ((rules (yeah-perm-profile "workspace")))
    (should (eq 'ask (yeah-perm-effect "edit" "/tmp/x" rules)))
    (should (eq 'ask (yeah-perm-effect "read" "/tmp/x" rules)))))

(ert-deftest yeah-perm-profile-of-an-unknown-name-is-nil ()
  "A profile that does not exist is not a profile."
  (should-not (yeah-perm-profile "rewrite"))
	  (should (member "plan" (yeah-perm-profiles)))
	  (should (member "workspace" (yeah-perm-profiles)))
	  (should (member "build" (yeah-perm-profiles)))
  (should (member "auto" (yeah-perm-profiles))))

(ert-deftest yeah-perm-profile-auto-allows-everything ()
  "The auto profile allows every action: there is nobody to ask."
  (let ((rules (yeah-perm-profile "auto")))
    (should (eq 'allow (yeah-perm-effect "bash" "rm -rf /" rules)))
    (should (eq 'allow (yeah-perm-effect "edit" "/tmp/x" rules)))
    (should (eq 'allow (yeah-perm-effect "read" "/tmp/x" rules)))
    (should (eq 'allow (yeah-perm-effect "whatever" "whatever" rules)))))

(ert-deftest yeah-perm-a-rule-may-name-every-action ()
  "A rule with the wildcard action matches every action.
The rule of the profile that speaks about every action at once needs
the wildcard of the action, and the wildcard of the resource was
always there."
  (let ((rules (list (yeah-perm-rule-make "*" "*" 'allow))))
    (should (eq 'allow (yeah-perm-effect "bash" "anything" rules)))
    (should (eq 'allow (yeah-perm-effect "whatever" "anything" rules)))
    (should (eq 'ask (yeah-perm-effect "bash" "anything" nil)))))

(ert-deftest yeah-perm-profile-does-not-change-the-persistent-rules ()
  "A profile is a mode of work, not a policy of the person."
  (yeah-perm-rules-reset-for-test)
  (yeah-perm-profile "plan")
  (should (null (yeah-perm-rules-list))))

(ert-deftest yeah-perm-profile-asks-by-the-declaration-of-the-tool ()
  "The profile asks by the risk the tool declares and not by the name of the
tool: a tool that declares that it only looks is not named, a tool that
declares that it changes the world is named, and a tool that declares no
risk is named too, because a risk that is not known changes the world."
  (let (actions)
    (yeah-tools-register
     (list :name "tmp-only-looks"
           :description "A throwaway tool that declares that it only looks."
           :input nil
           :handler (lambda (&rest _args) nil)
           :risk "read"))
    (yeah-tools-register
     (list :name "tmp-changes-the-world"
           :description "A throwaway tool that declares that it changes the world."
           :input nil
           :handler (lambda (&rest _args) nil)
           :risk "write"))
    (yeah-tools-register
     (list :name "tmp-says-nothing"
           :description "A throwaway tool that declares no risk."
           :input nil
           :handler (lambda (&rest _args) nil)))
    (unwind-protect
        (setq actions (mapcar (lambda (rule) (plist-get rule :action))
                              (yeah-perm-profile "plan")))
      (yeah-tools-unregister "tmp-only-looks")
      (yeah-tools-unregister "tmp-changes-the-world")
      (yeah-tools-unregister "tmp-says-nothing"))
    (should-not (member "tmp-only-looks" actions))
    (should (member "tmp-changes-the-world" actions))
    (should (member "tmp-says-nothing" actions))))

(ert-deftest yeah-perm-asks-about-an-action-that-no-rule-names ()
  "A rule that names no action asks about it: the default of the rule is
`ask' and not `allow', and the refusal of the rule says so."
  (let ((rules (yeah-perm-profile "plan"))
        (err nil))
    (should (eq 'ask (yeah-perm-effect "tmp-no-such-tool" "*" rules)))
    (condition-case e
        (yeah-perm-evaluate "tmp-no-such-tool" "*" rules)
      (user-error (setq err e)))
    (should err)
    (should (string-prefix-p "ask: " (error-message-string err)))
    (should (eq 'ask (yeah-perm-effect "tmp-no-such-tool" "*" '())))))

(provide 'test-yeah-perm)
;;; test-yeah-perm.el ends here
