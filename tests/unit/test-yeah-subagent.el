;;; test-yeah-subagent.el --- ERT tests for yeah-subagent -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; A sub-agent is a run of its own.  The tests below ask the delegation
;; for what it promises: the child runs for real, in its own session, with
;; only the tools it was granted; the parent is told what happened; the
;; depth is bounded; and the summary of a child is backed by the journal
;; of the child.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-subagent)
(require 'yeah-session)
(require 'yeah-tools)

(defun yeah-subagent-test--make-tmpdir ()
  "Create a fresh temp directory; return its absolute path."
  (file-name-as-directory
   (make-temp-file "yeah-subagent-" t)))

(defun yeah-subagent-test--cleanup (dir)
  "Best-effort cleanup of DIR, ignoring errors."
  (ignore-errors (delete-directory dir t t)))

(defun yeah-subagent-test--register-probe ()
  "Register the tool `probe', which answers with what it was given."
  (unless (yeah-tools-get "probe")
    (yeah-tools-register
     (list :name "probe"
           :description "A tool that records that it ran."
           :input (list (list :name "path" :type 'string))
           :handler (lambda (path) (format "probe saw %s" path))))))

(defun yeah-subagent-test--answering-transport (tool)
  "Return a transport that asks for TOOL and then answers."
  (lambda (_prompt callback)
    (funcall callback
             (list 'tool-call
                   (list (list :name tool)
                         (list "/tmp/probe-target")
                         (lambda (value)
                           (funcall callback (format "done: %s" value))))))))

(defun yeah-subagent-test--answer-transport ()
  "Return a transport that answers with text and asks for nothing."
  (lambda (_prompt callback)
    (funcall callback "the answer")))

(ert-deftest yeah-subagent-spawn-creates-child-session ()
  "The child of a parent has its own session, and its id carries the lineage."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "spawn-creates-child" tmpdir)))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (let* ((record (yeah-subagent-spawn parent "review" "Check the diff"
                                              :transport (yeah-subagent-test--answer-transport)))
                 (child-session (plist-get record :child-session)))
            (should (consp child-session))
            (should (string-match-p "spawn-creates-child\\.sub-"
                                    (plist-get child-session :id)))
            (should (file-exists-p (plist-get child-session :path)))))
      (yeah-subagent-reset-for-test)
      (yeah-subagent-test--cleanup tmpdir))))

(ert-deftest yeah-subagent-child-runs-for-real ()
  "The child runs a turn of its own and writes down what it did."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "child-runs" tmpdir)))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (let* ((record (yeah-subagent-spawn parent "explore" "Find the thing"
                                                 :transport (yeah-subagent-test--answer-transport)))
                 (child-session (plist-get record :child-session)))
            (yeah-subagent-wait (plist-get record :id))
            (should (eq (plist-get record :status) 'completed))
            (should (equal (plist-get record :result) "the answer"))
            (let ((types (mapcar (lambda (event) (plist-get event :type))
                                 (yeah-session-records child-session))))
              (should (member "user-message" types))
              (should (member "assistant-message" types)))))
      (yeah-subagent-reset-for-test)
      (yeah-subagent-test--cleanup tmpdir))))

(ert-deftest yeah-subagent-child-may-only-use-the-tools-it-was-granted ()
  "A tool the child was not granted is refused, and the refusal is written down."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "child-tools" tmpdir)))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (yeah-subagent-test--register-probe)
          (let* ((record (yeah-subagent-spawn
                          parent "explore" "Use the probe"
                          :transport (yeah-subagent-test--answering-transport "probe")
                          :tools '("read")))
                 (child-session (plist-get record :child-session)))
            (yeah-subagent-wait (plist-get record :id))
            (let ((decisions (seq-filter
                              (lambda (event)
                                (equal (plist-get event :type) "permission-decision"))
                              (yeah-session-records child-session))))
              (should (= 1 (length decisions)))
              (should (equal (plist-get (car decisions) :effect) "deny")))
            (let ((ends (seq-filter
                         (lambda (event)
                           (equal (plist-get event :type) "tool-end"))
                         (yeah-session-records child-session))))
              (should (= 1 (length ends)))
              (should-not (yeah-events-boolean-p (plist-get (car ends) :ok))))))
      (yeah-subagent-reset-for-test)
      (yeah-subagent-test--cleanup tmpdir))))

(ert-deftest yeah-subagent-child-may-use-a-granted-tool ()
  "A tool the child was granted runs."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "child-granted" tmpdir)))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (yeah-subagent-test--register-probe)
          (let* ((record (yeah-subagent-spawn
                          parent "explore" "Use the probe"
                          :transport (yeah-subagent-test--answering-transport "probe")
                          :tools '("probe")))
                 (child-session (plist-get record :child-session)))
            (yeah-subagent-wait (plist-get record :id))
            (let ((ends (seq-filter
                         (lambda (event)
                           (equal (plist-get event :type) "tool-end"))
                         (yeah-session-records child-session))))
              (should (= 1 (length ends)))
              (should (yeah-events-boolean-p (plist-get (car ends) :ok))))))
      (yeah-subagent-reset-for-test)
      (yeah-subagent-test--cleanup tmpdir))))

(ert-deftest yeah-subagent-parent-is-told-what-happened ()
  "The journal of the parent carries the spawn and the end of the child."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "parent-told" tmpdir)))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (let* ((record (yeah-subagent-spawn parent "explore" "Find the thing"
                                                 :transport (yeah-subagent-test--answer-transport)))
                 (child-id (plist-get record :child-session)))
            (yeah-subagent-wait (plist-get record :id))
            (let ((types (mapcar (lambda (event) (plist-get event :type))
                                 (yeah-session-records parent))))
              (should (member "spawn" types))
              (should (member "child-end" types))
              (let ((end (seq-find (lambda (event)
                                     (equal (plist-get event :type) "child-end"))
                                   (yeah-session-records parent))))
                (should (equal (plist-get end :child) (plist-get child-id :id)))
                (should (equal (plist-get end :summary) "the answer"))))))
      (yeah-subagent-reset-for-test)
      (yeah-subagent-test--cleanup tmpdir))))

(ert-deftest yeah-subagent-depth-limit-is-enforced ()
  "A child beyond the depth limit is refused."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "depth-limit" tmpdir))
         (saved yeah-subagent--max-depth))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (setq yeah-subagent--max-depth 2)
          (should-error
           (yeah-subagent-spawn parent "explore" "Too deep" :depth 2
                                :transport (yeah-subagent-test--answer-transport))
           :type 'user-error)
          (should (= 2 (yeah-subagent-depth-limit))))
      (setq yeah-subagent--max-depth saved)
      (yeah-subagent-reset-for-test)
      (yeah-subagent-test--cleanup tmpdir))))

(ert-deftest yeah-subagent-depth-limit-default-3 ()
  "The depth limit is three by default."
  (should (= 3 (yeah-subagent-depth-limit))))

(ert-deftest yeah-subagent-fork-summary-is-backed-by-the-journal ()
  "The summary of a child says what the child answered."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "fork-summary" tmpdir)))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (let* ((record (yeah-subagent-spawn parent "explore" "Find bugs"
                                                 :transport (yeah-subagent-test--answer-transport)))
                 (child-session (plist-get record :child-session)))
            (yeah-subagent-wait (plist-get record :id))
            (let ((summary (yeah-subagent-fork-summary parent child-session)))
              (should (stringp summary))
              (should (string-match-p "sub-agent" summary))
              (should (string-match-p "the answer" summary)))))
      (yeah-subagent-reset-for-test)
      (yeah-subagent-test--cleanup tmpdir))))

(ert-deftest yeah-subagent-cancel-stops-the-child ()
  "A child that is cancelled says so, and its work stops."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "cancel" tmpdir)))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (let* ((record (yeah-subagent-spawn parent "explore" "Wait forever"
                                                 :transport (lambda (_prompt _callback) nil)))
                 (child-id (plist-get record :id)))
            (should (yeah-subagent-cancel child-id "the parent changed its mind"))
            (should (eq 'interrupted (yeah-turn-state (plist-get record :turn))))
            (should (eq 'failed (plist-get record :status)))))
      (yeah-subagent-reset-for-test)
      (yeah-subagent-test--cleanup tmpdir))))

(ert-deftest yeah-subagent-children-are-listed ()
  "The children of a session are the children it spawned."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "children" tmpdir)))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (yeah-subagent-spawn parent "explore" "One"
                               :transport (yeah-subagent-test--answer-transport))
          (yeah-subagent-spawn parent "review" "Two"
                               :transport (yeah-subagent-test--answer-transport))
          (let ((children (yeah-subagent-children parent)))
            (should (= 2 (length children)))
            (should (equal (mapcar (lambda (child) (plist-get child :role))
                                    children)
                           '("explore" "review")))))
      (yeah-subagent-reset-for-test)
      (yeah-subagent-test--cleanup tmpdir))))

(provide 'test-yeah-subagent)
;;; test-yeah-subagent.el ends here
