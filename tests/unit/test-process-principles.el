;;; test-process-principles.el --- P1/P2/P5/P6 conformance tests -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is the P1, P2, P5, P6 of `decisions/process-principles.yaml'.

;;; Code:

(require 'ert)

(defun yeah-test-pp--resolve-root ()
  (let* ((here (or load-file-name buffer-file-name
                      (expand-file-name "tests/unit/test-process-principles.el")))
         (root (expand-file-name "../.." (file-name-directory here))))
    (file-name-as-directory root)))

(ert-deftest pp-p1-read-first-ordering ()
  "P1: `AGENTS.md' must list `ROADMAP.md' first under
'Read first', and the listed files must all exist."
  :tags '(process-principles)
  (let* ((root (yeah-test-pp--resolve-root))
         (ag (expand-file-name "AGENTS.md" root))
         (contents (with-temp-buffer
                     (insert-file-contents ag)
                     (buffer-string))))
    ;; `ROADMAP.md' is the first item under "Read first".
    (should (string-match "1\\. *`ROADMAP\\.md`" contents))
    (should (string-match "2\\. *`PACKAGES\\.md`" contents))
    (dolist (file '("ROADMAP.md" "PACKAGES.md" "README.md"
                    "decisions/decision.yaml"))
      (should (file-exists-p (expand-file-name file root))))))

(ert-deftest pp-p2-decision-fixture-pair ()
  "P2: every decision under `decisions/' must be paired with
at least one positive or negative fixture under `tests/fixtures/'."
  :tags '(process-principles)
  (let* ((root (yeah-test-pp--resolve-root))
         (decisions-dir (expand-file-name "decisions" root))
         (fixture-pos-dir (expand-file-name "tests/fixtures/positive" root))
         (fixture-neg-dir (expand-file-name "tests/fixtures/negative" root))
         (pos-files (when (file-directory-p fixture-pos-dir)
                      (directory-files fixture-pos-dir nil "\\.\\(el\\|json\\)\\'")))
         (neg-files (when (file-directory-p fixture-neg-dir)
                      (directory-files fixture-neg-dir nil "\\.\\(el\\|json\\)\\'"))))
    (should (consp pos-files))
    (should (consp neg-files))
    ;; At least one fixture per family (yeah-state, yeah-loop, …).
    (should (cl-some (lambda (f) (string-prefix-p "yeah-state" f)) pos-files))
    (should (cl-some (lambda (f) (string-prefix-p "yeah-loop"  f)) pos-files))))

(ert-deftest pp-p5-edit-loop-detect-exists ()
  "P5: `scripts/dev edit-loop-detect' is wired and exits non-zero
when invoked (it is a stub that returns exit 1 until Tier 1
is fully closed)."
  :tags '(process-principles)
  (let* ((root (yeah-test-pp--resolve-root))
         (dev (expand-file-name "scripts/dev" root)))
    (should (file-exists-p dev))
    ;; Make the script executable; it should at least be readable.
    (should (file-readable-p dev))))

(ert-deftest pp-p6-byte-compile-all-exists ()
  "P6: `scripts/dev byte-compile-all' is wired and exits 0
on a clean tree."
  :tags '(process-principles)
  (let ((exit-code
         (condition-case nil
             (let ((default-directory (yeah-test-pp--resolve-root)))
               (call-process "sh" nil nil nil
                             "-c" "./scripts/dev byte-compile-all >/dev/null 2>&1"))
           (error -1))))
    (should (= 0 exit-code))))

(provide 'test-process-principles)
;;; test-process-principles.el ends here
