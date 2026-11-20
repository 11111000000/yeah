;;; test-yeah-state.el --- ERT tests for yeah-state -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-state.el'. The
;; positive tests exercise the happy paths; the negative tests
;; exercise the closest plausible failure modes.

;;; Code:

(require 'ert)
(require 'yeah-state)

(yeah-state--init-table)

(ert-deftest yeah-state-list-has-exactly-11-states ()
  "The state list must contain exactly the 11 states of the machine.
Every one of them is a state the machine can be in: the table of
`lib/yeah-loop.el' leads into each of them and out of each of them."
  (let ((expected '(idle deciding post-decide awaiting-tool
                    awaiting-user-permission
                    accumulating compacting blocked-on-rate
                    interrupted completed failed))
        (got yeah-state-list))
    (should (= (length got) 11))
    (should (equal got expected))))

(ert-deftest yeah-state-p-recognises-all-states ()
  "`yeah-state-p' returns non-nil for every state of the machine."
  (dolist (state yeah-state-list)
    (should (yeah-state-p state))))

(ert-deftest yeah-state-p-rejects-the-state-that-was-removed ()
  "The state `awaiting-user-input' is no state of the machine.
It named an event the kernel does not have: the run waits for the
person in `awaiting-user-permission' (wave 77)."
  (should-not (yeah-state-p 'awaiting-user-input)))

(ert-deftest yeah-state-p-rejects-symbols-outside-the-set ()
  "`yeah-state-p' returns nil for any other symbol, including
plausible names that are not in the contract."
  (dolist (bad '(running waiting starting idle2 awaiting_perm
                nil t :idle "idle"))
    (should-not (yeah-state-p bad))))

(ert-deftest yeah-state-terminal-p-returns-t-for-three-states ()
  "`interrupted', `completed', `failed' are the terminal states."
  (should (yeah-state-terminal-p 'interrupted))
  (should (yeah-state-terminal-p 'completed))
  (should (yeah-state-terminal-p 'failed)))

(ert-deftest yeah-state-terminal-p-returns-nil-for-eight-states ()
  "The eight non-terminal states are not terminal."
  (dolist (state '(idle deciding post-decide awaiting-tool
                   awaiting-user-permission
                   accumulating compacting blocked-on-rate))
    (should-not (yeah-state-terminal-p state))))

(ert-deftest yeah-state-terminal-p-rejects-non-states ()
  "`yeah-state-terminal-p' signals an error for non-states."
  (let ((err nil))
    (condition-case nil
        (yeah-state-terminal-p 'not-a-state)
      (error (setq err t)))
    (should err)))

(ert-deftest yeah-state-describe-returns-non-empty-for-all-states ()
  "`yeah-state-describe' returns a non-empty string for every state."
  (dolist (state yeah-state-list)
    (let ((s (yeah-state-describe state)))
      (should (stringp s))
      (should (> (length s) 0))
      (should (string-match-p (symbol-name state) s)))))

(ert-deftest yeah-state-describe-marks-terminals ()
  "Terminal states are tagged in their description."
  (should (string-match-p "terminal"
                          (yeah-state-describe 'interrupted)))
  (should (string-match-p "terminal"
                          (yeah-state-describe 'completed)))
  (should (string-match-p "terminal"
                          (yeah-state-describe 'failed)))
  (should-not (string-match-p "terminal"
                              (yeah-state-describe 'idle))))

(provide 'test-yeah-state)
;;; test-yeah-state.el ends here
