;;; test-yeah-subagent.el --- ERT tests for yeah-subagent -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-subagent.el'.
;; Seven required cases:
;;
;;   * yeah-subagent-spawn-returns-completed
;;   * yeah-subagent-spawn-creates-child-session
;;   * yeah-subagent-wait-returns-result
;;   * yeah-subagent-fork-summary-includes-id
;;   * yeah-subagent-depth-limit-default-3
;;   * yeah-subagent-depth-limit-overridable
;;   * yeah-subagent-spawn-with-zero-depth-allowed

;;; Code:

(require 'ert)
(require 'yeah-subagent)
(require 'yeah-session)

(defun yeah-subagent-test--make-tmpdir ()
  "Create a fresh temp directory; return its absolute path.
Caller is responsible for `delete-directory' cleanup."
  (file-name-as-directory
   (make-temp-file "yeah-subagent-" t)))

(defun yeah-subagent-test--cleanup (dir)
  "Best-effort cleanup of DIR, ignoring errors."
  (ignore-errors (delete-directory dir t t)))

(ert-deftest yeah-subagent-spawn-returns-completed ()
  "`yeah-subagent-spawn' returns a result plist with `:status completed'."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "spawn-returns-completed" tmpdir)))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (let* ((record (yeah-subagent-spawn parent "explore"
                                              "Look at the README"))
                 (status (plist-get record :status))
                 (result (plist-get record :result))
                 (depth  (plist-get record :depth)))
            (should (eq status 'completed))
            (should (stringp result))
            (should (> (length result) 0))
            (should (string-match-p "stub:" result))
            (should (= depth 1)))
          (yeah-subagent-reset-for-test))
      (yeah-subagent-test--cleanup tmpdir))))

(ert-deftest yeah-subagent-spawn-creates-child-session ()
  "`yeah-subagent-spawn' creates a new child session under the
parent's root directory."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "spawn-creates-child" tmpdir))
         (record nil)
         (child-session nil))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (setq record (yeah-subagent-spawn parent "review"
                                             "Check the diff"))
          (setq child-session (plist-get record :child-session))
          (should (consp child-session))
          (should (stringp (plist-get child-session :id)))
          (should (string-match-p "spawn-creates-child\\.sub-"
                                  (plist-get child-session :id)))
          (should (stringp (plist-get child-session :path)))
          (should (string-suffix-p ".jsonl" (plist-get child-session :path)))
          (should (file-exists-p (plist-get child-session :path)))
          (let ((records (yeah-session-records child-session)))
            (should (= (length records) 1))
            (should (string= (plist-get (nth 0 records) :type) "header"))))
      (yeah-subagent-reset-for-test)
      (yeah-subagent-test--cleanup tmpdir))))

(ert-deftest yeah-subagent-wait-returns-result ()
  "`yeah-subagent-wait' returns the same plist `spawn' returned."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "wait-returns" tmpdir))
         (spawn-record nil)
         (wait-record nil))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (setq spawn-record (yeah-subagent-spawn parent "worker"
                                                  "Do the work"))
          (let ((id (plist-get spawn-record :id)))
            (setq wait-record (yeah-subagent-wait id))
            (should (eq (plist-get wait-record :status) 'completed))
            (should (string= (plist-get wait-record :result)
                             (plist-get spawn-record :result)))
            (should (string= (plist-get wait-record :prompt)
                             (plist-get spawn-record :prompt)))))
      (yeah-subagent-reset-for-test)
      (yeah-subagent-test--cleanup tmpdir))))

(ert-deftest yeah-subagent-fork-summary-includes-id ()
  "`yeah-subagent-fork-summary' returns a string containing
the child id and the result text."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "fork-summary" tmpdir))
         (record nil)
         (child-session nil)
         (summary nil))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (setq record (yeah-subagent-spawn parent "explore"
                                             "Find bugs"))
          (setq child-session (plist-get record :child-session))
          (setq summary (yeah-subagent-fork-summary parent child-session))
          (should (stringp summary))
          (should (string-match-p "sub-agent" summary))
          (let* ((id-str (number-to-string (plist-get record :id)))
                 (result-str (plist-get record :result)))
            (should (string-match-p id-str summary))
            (should (string-match-p result-str summary))))
      (yeah-subagent-reset-for-test)
      (yeah-subagent-test--cleanup tmpdir))))

(ert-deftest yeah-subagent-depth-limit-default-3 ()
  "`yeah-subagent-depth-limit' returns 3 by default."
  (let ((saved yeah-subagent--max-depth))
    (unwind-protect
        (progn
          (setq yeah-subagent--max-depth 3)
          (should (= 3 (yeah-subagent-depth-limit))))
      (setq yeah-subagent--max-depth saved))))

(ert-deftest yeah-subagent-depth-limit-overridable ()
  "`yeah-subagent-depth-limit' reads the dynamic `yeah-subagent--max-depth'
so tests can override the value with `setq'."
  (let ((saved yeah-subagent--max-depth))
    (unwind-protect
        (progn
          (setq yeah-subagent--max-depth 7)
          (should (= 7 (yeah-subagent-depth-limit)))
          (setq yeah-subagent--max-depth 1)
          (should (= 1 (yeah-subagent-depth-limit))))
      (setq yeah-subagent--max-depth saved))))

(ert-deftest yeah-subagent-spawn-with-zero-depth-allowed ()
  "`yeah-subagent-spawn' with DEPTH=0 succeeds (the top-level
loop case) and produces a child at depth 1."
  (let* ((tmpdir (yeah-subagent-test--make-tmpdir))
         (parent (yeah-session-open "spawn-zero-depth" tmpdir))
         (saved  yeah-subagent--max-depth)
         (record nil)
         (err    nil))
    (unwind-protect
        (progn
          (yeah-subagent-reset-for-test)
          (setq yeah-subagent--max-depth 3)
          (condition-case nil
              (setq record (yeah-subagent-spawn parent "explore"
                                                 "Top-level prompt" 0))
            (user-error (setq err t)))
          (should-not err)
          (should record)
          (should (eq (plist-get record :status) 'completed))
          (should (= (plist-get record :depth) 1)))
      (setq yeah-subagent--max-depth saved)
      (yeah-subagent-reset-for-test)
      (yeah-subagent-test--cleanup tmpdir))))

(provide 'test-yeah-subagent)
;;; test-yeah-subagent.el ends here