;;; test-yeah-placement.el --- ERT tests for the placements -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; The placements differ in the process, in who may answer, and in what
;; happens at the end.  They do not differ in what the run writes down.
;; The tests below ask the placement module what it promises: the three
;; names, the canonical projection, the headless allowlist, the exit code
;; and the journal of a run.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-placement)
(require 'yeah-session)

(defun yeah-placement-test--session ()
  "Return a session in a temporary directory."
  (yeah-session-open "placement" (make-temp-file "yeah-placement-test" t)))

(ert-deftest yeah-placement-placements-names-the-three-placements ()
  "The module knows the three places a run may live."
  (should (equal (yeah-placement-placements) '(attached service batch))))

(ert-deftest yeah-placement-allow-rules-allows-only-the-named-tools ()
  "The headless allowlist names the tools that may run, and nothing else."
  (let* ((rules (yeah-placement-allow-rules '("read" "glob")))
         (effect (lambda (action)
                   (yeah-perm-effect action "/tmp/x" rules))))
    (should (eq 'allow (funcall effect "read")))
    (should (eq 'allow (funcall effect "glob")))
    (should (eq 'ask (funcall effect "write")))))

(ert-deftest yeah-placement-exit-code-maps-the-terminal-states ()
  "A run that finished says so in its exit code."
  (should (= 0 (yeah-placement-exit-code 'completed)))
  (should (= 1 (yeah-placement-exit-code 'failed)))
  (should (= 4 (yeah-placement-exit-code 'interrupted)))
  (should (= 3 (yeah-placement-exit-code 'something-else))))

(ert-deftest yeah-placement-context-refuses-an-unknown-placement ()
  "A context names the placement it lives in."
  (should-error (yeah-placement-context 'nowhere)
                :type 'user-error))

(ert-deftest yeah-placement-canonical-events-drops-the-volatile-fields ()
  "The projection keeps what happened and drops what may differ."
  (let* ((session (yeah-placement-test--session))
         (events (yeah-placement-canonical-events session)))
    (should (equal events nil))
    (yeah-events-write session "user-message" :payload "hello")
    (let ((projection (yeah-placement-canonical-events session)))
      (should (equal (mapcar #'car projection) '("user-message")))
      (should (equal (cdr (car projection)) '(:payload "hello"))))))

(ert-deftest yeah-placement-batch-runs-a-task-and-writes-the-journal ()
  "The batch placement runs the task and leaves the journal behind."
  (let* ((root (make-temp-file "yeah-placement-project" t))
         (data-home (make-temp-file "yeah-placement-data" t))
         (yeah-data-home data-home)
         (context (yeah-placement-batch
                   "do the thing"
                   :root root
                   :transport (lambda (_prompt callback)
                                (funcall callback "the answer")))))
    (unwind-protect
        (progn
          (yeah-placement-await (yeah-run-context-turn context))
          (should (eq 'completed (yeah-turn-state (yeah-run-context-turn context))))
          (let* ((session (yeah-run-context-session context))
                 (records (yeah-session-records session)))
            (should (equal '("header" "user-message" "assistant-message")
                           (mapcar (lambda (record) (plist-get record :type))
                                   records)))))
      (ignore-errors (delete-directory root t))
      (ignore-errors (delete-directory data-home t)))))

(provide 'test-yeah-placement)
;;; test-yeah-placement.el ends here
