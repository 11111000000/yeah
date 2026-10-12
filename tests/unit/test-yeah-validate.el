;;; test-yeah-validate.el --- ERT tests for yeah-validate -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'yeah-validate)

(defun yeah-test--resolve-root ()
  "Return the project root for the current test run."
  (let* ((here (or load-file-name buffer-file-name
                      (expand-file-name "tests/unit/test-yeah-validate.el")))
         (tests-dir (file-name-directory here))
         (root-dir (expand-file-name "../.." tests-dir)))
    (file-name-as-directory root-dir)))

(defun yeah-test--with-root (root thunk)
  "Run THUNK with the validator's view of the world rooted at ROOT."
  (let ((default-directory root))
    (setq yeah-validate--decisions-dir    "decisions"
          yeah-validate--obligations-dir  "obligations"
          yeah-validate--attestations-dir "attestations"
          yeah-validate--kernel-dir       "lib")
    (funcall thunk)))

(ert-deftest yeah-validate-runs-on-tree-without-issues ()
  "The current tree (in this repo) is a known-good state."
  (let* ((root (yeah-test--resolve-root))
         (report (yeah-test--with-root root #'yeah-validate-run))
         (all-pass (plist-get report :pass)))
    (should all-pass)))

(ert-deftest yeah-validate-rejects-decision-missing-field ()
  "A decision file missing a required field is reported as fail."
  (let* ((tmpdir (file-name-as-directory
                  (make-temp-file "yeah-validate-" t)))
         (decisions-dir (expand-file-name "decisions" tmpdir))
         (obligations-dir (expand-file-name "obligations" tmpdir))
         (attestations-dir (expand-file-name "attestations" tmpdir))
         (kernel-dir (expand-file-name "lib" tmpdir))
         (bad (expand-file-name "bad-decision.yaml" decisions-dir)))
    (make-directory decisions-dir t)
    (make-directory obligations-dir t)
    (make-directory attestations-dir t)
    (make-directory kernel-dir t)
    (with-temp-file (expand-file-name "yeah-state.el" kernel-dir)
      (insert ";; minimal stub for the validator's filesystem check\n"))
    (with-temp-file (expand-file-name "yeah-loop.el" kernel-dir)
      (insert ";; minimal stub for the validator's filesystem check\n"))
    (with-temp-file bad
      (insert "---
schema: yeah/0.0.0-alpha
id: bad-decision
revision: 0
state: active
intent: |
  This decision is missing the commitment, axiom_link, and scope
  fields that the validator requires.
---
"))
    (let* ((report (yeah-test--with-root tmpdir #'yeah-validate-run))
           (results (plist-get report :results))
           (all-pass (plist-get report :pass)))
      (should-not all-pass)
      (should (cl-some (lambda (r) (string-match-p "missing required field"
                                                  (cdr r)))
                       results)))
    (delete-directory tmpdir t t)))

(provide 'test-yeah-validate)
;;; test-yeah-validate.el ends here
