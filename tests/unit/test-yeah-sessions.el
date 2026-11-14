;;; test-yeah-sessions.el --- ERT tests for session projections -*- lexical-binding: t; no-byte-compile: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;; Session-list metadata and truthful cost projections from real JSONL files.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'json)
(require 'yeah-sessions)
(require 'yeah-ui-fixtures
         (expand-file-name "tests/support/yeah-ui-fixtures.el"))

(defun yeah-sessions-test--write (root id records)
  "Write RECORDS as session ID under ROOT and return the file path."
  (let ((path (expand-file-name (format "sessions/%s.jsonl" id) root)))
    (make-directory (file-name-directory path) t)
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file path
        (dolist (record records)
          (let ((wire (copy-tree record)))
            (dolist (key '(:run_id :turn_id :tool_call_id :parent_event_id))
              (when (null (plist-get wire key))
                (setq wire (plist-put wire key :null))))
            (insert (json-serialize wire) "\n")))))
    path))

(ert-deftest yeah-sessions-index-adds-list-metadata-and-keeps-old-keys ()
  (let* ((root (make-temp-file "yeah-sessions-index-" t))
         (alpha (list (yeah-ui-fixture-header
                       :session_id "alpha" :title "Alpha title"
                       :model "fake-model" :placement "service" :profile "build")
                      (yeah-ui-fixture-event 1 "user-message"
                                             :session_id "alpha" :payload "question")
                      (yeah-ui-fixture-event 2 "assistant-message"
                                             :session_id "alpha" :payload "answer")))
         (beta (list (yeah-ui-fixture-header :session_id "beta")
                     (yeah-ui-fixture-event 1 "user-message"
                                            :session_id "beta" :payload "Beta question")
                     (yeah-ui-fixture-event 2 "tool-request"
                                            :session_id "beta" :tool_call_id "call-beta"
                                            :tool "probe" :args ["target"]))))
    (unwind-protect
        (let ((alpha-path (yeah-sessions-test--write root "alpha" alpha))
              (expected nil))
          (yeah-sessions-test--write root "beta" beta)
          (setq expected (yeah-sessions-index root))
          (should (equal (mapcar (lambda (entry) (plist-get entry :id)) expected)
                         '("alpha" "beta")))
          (let ((first (nth 0 expected))
                (second (nth 1 expected)))
            (should (= 3 (plist-get first :records)))
            (should (plist-get first :cost))
            (should (equal (plist-get first :mtime)
                           (file-attribute-modification-time
                            (file-attributes alpha-path))))
            (should (equal (plist-get first :title) "Alpha title"))
            (should (eq (plist-get first :last-status) 'completed))
            (should (eq (plist-get first :status) 'completed))
            (should (equal (plist-get first :model) "fake-model"))
            (should (equal (plist-get first :placement) "service"))
            (should (equal (plist-get first :profile) "build"))
            (should (equal (plist-get second :title) "Beta question"))
            (should (eq (plist-get second :last-status) 'running)))
          (should (equal (yeah-sessions-index root) expected))
          (should (equal (sort (directory-files
                                (expand-file-name "sessions" root) nil nil t)
                               #'string<)
                         '("." ".." "alpha.jsonl" "beta.jsonl"))))
      (ignore-errors (delete-directory root t t)))))

(ert-deftest yeah-sessions-cost-keeps-unknown-provider-usage-unknown ()
  (let ((cost (yeah-sessions-cost (yeah-ui-fixture-without-usage))))
    (should-not (plist-get cost :reported-input))
    (should-not (plist-get cost :reported-output))
    (should-not (plist-get cost :reported-p))
    (should (> (plist-get cost :estimated) 0))
    (should (= (plist-get cost :total) (plist-get cost :estimated)))))

(ert-deftest yeah-sessions-cost-separates-reported-and-estimated-tokens ()
  (let* ((records (append (yeah-ui-fixture-without-usage)
                          (list (yeah-ui-fixture-event 3 "usage"
                                                       :input 100 :output 20))))
         (cost (yeah-sessions-cost records)))
    (should (= 100 (plist-get cost :reported-input)))
    (should (= 20 (plist-get cost :reported-output)))
    (should (eq (plist-get cost :reported-p) t))
    (should (> (plist-get cost :estimated) 0))
    (should (= (plist-get cost :total)
               (+ 120 (plist-get cost :estimated))))))

(provide 'test-yeah-sessions)
;;; test-yeah-sessions.el ends here
