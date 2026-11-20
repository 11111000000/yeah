;;; test-yeah-loop.el --- ERT tests for yeah-loop -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-loop.el'.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-state)
(require 'yeah-loop)

(defconst yeah-loop--test-non-terminal-states
  '(idle deciding post-decide awaiting-tool awaiting-user-permission
    accumulating compacting blocked-on-rate)
  "The states a run can live in and not be finished.")

(ert-deftest yeah-loop-transition-count-is-31 ()
  "The transition table has exactly 31 entries."
  (should (= 31 (yeah-loop-transition-count))))

(ert-deftest yeah-loop-tick-idle-on-user-prompt ()
  "user-prompt from idle goes to deciding."
  (should (eq (yeah-loop-tick 'idle 'user-prompt) 'deciding)))

(ert-deftest yeah-loop-tick-deciding-on-stream-end ()
  "stream-end from deciding goes to post-decide."
  (should (eq (yeah-loop-tick 'deciding 'stream-end) 'post-decide)))

(ert-deftest yeah-loop-tick-post-decide-fans-out ()
  "post-decide has four legal labels: no-tool-calls, tool-call,
continue and nudge."
  (should (eq (yeah-loop-tick 'post-decide 'no-tool-calls) 'completed))
  (should (eq (yeah-loop-tick 'post-decide 'tool-call)     'awaiting-tool))
  (should (eq (yeah-loop-tick 'post-decide 'continue)       'deciding))
  (should (eq (yeah-loop-tick 'post-decide 'nudge)          'deciding)))

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

(ert-deftest yeah-loop-tick-compacting-on-done ()
  "compact-done from compacting returns to post-decide."
  (should (eq (yeah-loop-tick 'compacting 'compact-done) 'post-decide)))

(ert-deftest yeah-loop-tick-interrupt-from-every-state-of-a-running-turn ()
  "A run that is not finished can be cancelled in any state it lives
in: the machine has an `interrupt' edge from each of them."
  (dolist (state yeah-loop--test-non-terminal-states)
    (should (eq (yeah-loop-tick state 'interrupt) 'interrupted))))

(ert-deftest yeah-loop-tick-error-from-every-state-of-a-running-turn ()
  "A run that is not finished can fail in any state it lives in."
  (dolist (state yeah-loop--test-non-terminal-states)
    (should (eq (yeah-loop-tick state 'error) 'failed))))

(ert-deftest yeah-loop-tick-interrupt-is-refused-from-a-finished-run ()
  "A finished run cannot be interrupted again: the terminal states
have no edge."
  (dolist (state '(completed failed interrupted))
    (let ((err nil))
      (condition-case nil
          (yeah-loop-tick state 'interrupt)
        (user-error (setq err t)))
      (should err))))

(ert-deftest yeah-loop-tick-permission-ask-makes-the-run-wait ()
  "A question that waits for the person puts the run into the state
of a run that waits for the person."
  (should (eq (yeah-loop-tick 'awaiting-tool 'permission-ask)
              'awaiting-user-permission)))

(ert-deftest yeah-loop-tick-answer-ends-the-wait ()
  "The answer of the person ends the wait: the tool of the answer runs
and the run waits for it."
  (should (eq (yeah-loop-tick 'awaiting-user-permission 'answer)
              'awaiting-tool))
  (should (eq (yeah-loop-tick 'awaiting-user-permission 'timeout)
              'awaiting-tool)))

(ert-deftest yeah-loop-tick-rate-block-recovers ()
  "A provider that is busy makes the run wait for it, and the answer
of the provider ends the wait."
  (should (eq (yeah-loop-tick 'deciding 'rate-blocked) 'blocked-on-rate))
  (should (eq (yeah-loop-tick 'blocked-on-rate 'rate-relief) 'deciding)))

(ert-deftest yeah-loop-every-state-of-the-machine-can-be-entered ()
  "Every state of the machine but the first is the destination of at
least one cell: a state that nothing leads into is a state the run is
never in."
  (dolist (state (delete 'idle yeah-state-list))
    (should (cl-some (lambda (cell) (eq (nthcdr 2 cell) state))
                     yeah-loop-transitions))))

(ert-deftest yeah-loop-every-state-of-the-machine-can-be-left ()
  "Every state of the machine that is not terminal has at least one
outgoing cell."
  (dolist (state yeah-loop--test-non-terminal-states)
    (should (cl-some (lambda (cell) (eq (nth 0 cell) state))
                     yeah-loop-transitions))))

(ert-deftest yeah-loop-no-label-is-declared-twice-for-one-state ()
  "One state has at most one cell per label: the table says one thing
about one event."
  (dolist (state yeah-state-list)
    (let (labels)
      (dolist (cell yeah-loop-transitions)
        (when (eq (nth 0 cell) state)
          (push (nth 1 cell) labels)))
      (should (= (length labels) (length (delete-dups labels)))))))

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
