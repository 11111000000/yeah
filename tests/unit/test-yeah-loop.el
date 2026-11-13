;;; test-yeah-loop.el --- ERT tests for yeah-loop -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-loop.el'.

;;; Code:

(require 'ert)
(require 'yeah-state)
(require 'yeah-loop)

(ert-deftest yeah-loop-transition-count-is-20 ()
  "The transition table has exactly 20 entries."
  (should (= 20 (yeah-loop-transition-count))))

(ert-deftest yeah-loop-tick-idle-on-user-prompt ()
  "user-prompt from idle goes to deciding."
  (should (eq (yeah-loop-tick 'idle 'user-prompt) 'deciding)))

(ert-deftest yeah-loop-tick-deciding-on-stream-end ()
  "stream-end from deciding goes to post-decide."
  (should (eq (yeah-loop-tick 'deciding 'stream-end) 'post-decide)))

(ert-deftest yeah-loop-tick-post-decide-fans-out ()
  "post-decide has five legal labels: no-tool-calls, tool-call,
permission-ask, ask-user, continue."
  (should (eq (yeah-loop-tick 'post-decide 'no-tool-calls)  'completed))
  (should (eq (yeah-loop-tick 'post-decide 'tool-call)      'awaiting-tool))
  (should (eq (yeah-loop-tick 'post-decide 'permission-ask) 'awaiting-user-permission))
  (should (eq (yeah-loop-tick 'post-decide 'ask-user)        'awaiting-user-input))
  (should (eq (yeah-loop-tick 'post-decide 'continue)        'deciding)))

(ert-deftest yeah-loop-tick-deciding-on-error ()
  "error from deciding goes to failed: the model answered with
something the turn cannot use, and the run failed rather than
pretending it finished."
  (should (eq (yeah-loop-tick 'deciding 'error) 'failed)))

(ert-deftest yeah-loop-tick-post-decide-on-continue ()
  "continue from post-decide goes back to deciding: the model is
asked again, with the results of what was dispatched. Without this
transition the machine can run one model turn and no more."
  (should (eq (yeah-loop-tick 'post-decide 'continue) 'deciding)))

(ert-deftest yeah-loop-tick-awaiting-tool-on-tool-end ()
  "tool-end from awaiting-tool goes to accumulating."
  (should (eq (yeah-loop-tick 'awaiting-tool 'tool-end) 'accumulating)))

(ert-deftest yeah-loop-tick-accumulating-on-budget-ok ()
  "budget-ok from accumulating goes back to post-decide."
  (should (eq (yeah-loop-tick 'accumulating 'budget-ok) 'post-decide)))

(ert-deftest yeah-loop-tick-accumulating-on-overflow ()
  "budget-overflow from accumulating goes to compacting."
  (should (eq (yeah-loop-tick 'accumulating 'budget-overflow) 'compacting)))

(ert-deftest yeah-loop-tick-interrupt-from-active-states ()
  "interrupt is a valid label from `deciding' and `awaiting-tool'.
It is not valid from `idle' (the run hasn't started)."
  (should (eq (yeah-loop-tick 'deciding      'interrupt) 'interrupted))
  (should (eq (yeah-loop-tick 'awaiting-tool 'interrupt) 'interrupted)))

(ert-deftest yeah-loop-tick-compacting-on-done ()
  "compact-done from compacting returns to post-decide."
  (should (eq (yeah-loop-tick 'compacting 'compact-done) 'post-decide)))

(ert-deftest yeah-loop-tick-rate-block-recovers ()
  "rate-relief from blocked-on-rate resumes at deciding."
  (should (eq (yeah-loop-tick 'blocked-on-rate 'rate-relief) 'deciding)))

;; --- Negative fixtures ---

(ert-deftest yeah-loop-tick-rejects-undefined-label ()
  "An undefined label raises `user-error'."
  (let ((err nil))
    (condition-case nil
        (yeah-loop-tick 'idle 'not-a-real-label)
      (user-error (setq err t)))
    (should err)))

(ert-deftest yeah-loop-tick-rejects-wrong-from-state ()
  "A label that is valid in *some* state but not the current one
raises `user-error'."
  (let ((err nil))
    (condition-case nil
        (yeah-loop-tick 'idle 'stream-end)  ; stream-end only from deciding
      (user-error (setq err t)))
    (should err)))

(ert-deftest yeah-loop-tick-rejects-non-state-from ()
  "A non-state `from' raises `user-error'."
  (let ((err nil))
    (condition-case nil
        (yeah-loop-tick 'not-a-state 'user-prompt)
      (user-error (setq err t)))
    (should err)))

(ert-deftest yeah-loop-tick-rejects-non-symbol-label ()
  "A non-symbol label raises `user-error'."
  (let ((err nil))
    (condition-case nil
        (yeah-loop-tick 'idle "user-prompt")
      (user-error (setq err t)))
    (should err)))

(provide 'test-yeah-loop)
;;; test-yeah-loop.el ends here
