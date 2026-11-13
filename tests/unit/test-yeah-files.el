;;; test-yeah-files.el --- ERT tests for yeah-files -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-files)
(require 'yeah-tools)

(defmacro yeah-files-test--with-directory (variable &rest body)
  "Create a temporary directory as VARIABLE and run BODY."
  (declare (indent 1))
  `(let ((,variable (make-temp-file "yeah-files-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,variable t))))

(defun yeah-files-test--write (root relative content)
  "Write UTF-8 CONTENT below ROOT at RELATIVE and return its path."
  (let ((path (expand-file-name relative root)))
    (make-directory (file-name-directory path) t)
    (let ((coding-system-for-write 'utf-8-unix))
      (with-temp-file path
        (insert content)))
    path))

(defun yeah-files-test--call (name &rest args)
  "Call the handler for tool NAME with ARGS."
  (let ((spec (cl-find name (yeah-files-tools)
                       :key (lambda (candidate) (plist-get candidate :name))
                       :test #'string=)))
    (should spec)
    (apply (plist-get spec :handler) args)))

(defun yeah-files-test--error-p (result)
  "Return non-nil when RESULT is a structured tool error."
  (and (not (plist-get result :ok))
       (stringp (plist-get result :error))))

(ert-deftest yeah-files-tools-register-with-registry ()
  "All file tool specifications are accepted by the existing registry."
  (yeah-tools-reset-for-test)
  (unwind-protect
      (progn
        (dolist (name '("read" "glob" "grep"))
          (yeah-tools-unregister name))
        (dolist (spec (yeah-files-tools))
          (should (eq spec (yeah-tools-register spec)))
          (should (eq spec (yeah-tools-get (plist-get spec :name))))))
    (yeah-tools-reset-for-test)))

(ert-deftest yeah-files-read-honors-offset-limit-and-metadata ()
  "Read returns the requested complete lines and accurate metadata."
  (yeah-files-test--with-directory root
    (let* ((path (yeah-files-test--write
                  root "lines.txt" "zero\none\ntwo\nthree\n"))
           (result (yeah-files-test--call "read" path 2 2))
           (metadata (plist-get result :metadata)))
      (should (plist-get result :ok))
      (should (equal (plist-get result :content) "one\ntwo\n"))
      (should (equal (plist-get metadata :path) (file-truename path)))
      (should (= (plist-get metadata :offset) 2))
      (should (= (plist-get metadata :limit) 2))
      (should (= (plist-get metadata :total-lines) 4))
      (should (plist-get metadata :truncated))
      (should (plist-get result :truncated))
      (let* ((last (yeah-files-test--call "read" path 4 10))
             (last-metadata (plist-get last :metadata)))
        (should (equal (plist-get last :content) "three\n"))
        (should-not (plist-get last-metadata :truncated))))))

(ert-deftest yeah-files-read-preserves-utf8-and-newlines ()
  "Read retains UTF-8 text, CRLF newlines, and an unterminated last line."
  (yeah-files-test--with-directory root
    (let* ((path (yeah-files-test--write
                  root "utf8.txt" "α\r\nβ\r\n終"))
           (result (yeah-files-test--call "read" path 2 2))
           (metadata (plist-get result :metadata)))
      (should (plist-get result :ok))
      (should (equal (plist-get result :content) "β\r\n終"))
      (should (= (plist-get metadata :total-lines) 3))
      (should-not (plist-get metadata :truncated)))))

(ert-deftest yeah-files-read-rejects-invalid-ranges-and-files ()
  "Read failures are structured errors rather than false successes."
  (yeah-files-test--with-directory root
    (let ((path (yeah-files-test--write root "two.txt" "one\ntwo\n")))
      (should (yeah-files-test--error-p
               (yeah-files-test--call "read" path 0 1)))
      (should (yeah-files-test--error-p
               (yeah-files-test--call "read" path 1 0)))
      (should (yeah-files-test--error-p
               (yeah-files-test--call "read" path 3 1)))
      (should (yeah-files-test--error-p
               (yeah-files-test--call
                "read" (expand-file-name "missing.txt" root))))
      (should (yeah-files-test--error-p
               (yeah-files-test--call "read" root))))))

(ert-deftest yeah-files-glob-matches-relative-paths-and-skips-directories ()
  "Glob matches relative paths and prunes dependency and VCS directories."
  (yeah-files-test--with-directory root
    (yeah-files-test--write root "src/main.el" "main")
    (yeah-files-test--write root "src/lib/util.el" "util")
    (yeah-files-test--write root "README.md" "readme")
    (yeah-files-test--write root "node_modules/pkg/ignored.el" "ignored")
    (yeah-files-test--write root ".git/ignored.el" "ignored")
    (yeah-files-test--write root "build/ignored.el" "ignored")
    (let* ((result (yeah-files-test--call "glob" "\\.el\\'" root))
           (metadata (plist-get result :metadata)))
      (should (plist-get result :ok))
      (should (equal (plist-get result :content)
                     "src/lib/util.el\nsrc/main.el"))
      (should (= (plist-get metadata :count) 2))
      (should-not (plist-get metadata :truncated)))
    (let* ((limited (yeah-files-test--call "glob" "\\.el\\'" root 1))
           (metadata (plist-get limited :metadata)))
      (should (equal (plist-get limited :content) "src/lib/util.el"))
      (should (= (plist-get metadata :count) 1))
      (should (plist-get metadata :truncated)))))

(ert-deftest yeah-files-glob-rejects-invalid-regexp-and-directory ()
  "Glob reports malformed regexps and nonexistent directories."
  (yeah-files-test--with-directory root
    (should (yeah-files-test--error-p
             (yeah-files-test--call "glob" "[" root)))
    (should (yeah-files-test--error-p
             (yeah-files-test--call
              "glob" ".*" (expand-file-name "missing" root))))))

(ert-deftest yeah-files-grep-returns-bounded-utf8-results ()
  "Grep returns path:line:text output and stops after one extra match."
  (yeah-files-test--with-directory root
    (yeah-files-test--write root "a.txt" "alpha\nneedle α\nlast\n")
    (yeah-files-test--write root "b.el" "needle two\nneedle three\n")
    (yeah-files-test--write root "binary.dat" "needle\0hidden\n")
    (yeah-files-test--write root "node_modules/ignored.txt" "needle ignored\n")
    (let* ((result (yeah-files-test--call "grep" "needle" root))
           (metadata (plist-get result :metadata)))
      (should (plist-get result :ok))
      (should (equal (plist-get result :content)
                     (concat "a.txt:2:needle α\n"
                             "b.el:1:needle two\n"
                             "b.el:2:needle three\n")))
      (should (= (plist-get metadata :count) 3))
      (should-not (plist-get metadata :truncated)))
    (let* ((limited (yeah-files-test--call "grep" "needle" root 1))
           (metadata (plist-get limited :metadata)))
      (should (equal (plist-get limited :content) "a.txt:2:needle α\n"))
      (should (= (plist-get metadata :count) 1))
      (should (plist-get metadata :truncated)))
    (let ((empty (yeah-files-test--call "grep" "absent" root)))
      (should (plist-get empty :ok))
      (should (equal (plist-get empty :content) ""))
      (should (= (plist-get (plist-get empty :metadata) :count) 0)))))

(ert-deftest yeah-files-grep-skips-large-files ()
  "Grep does not load files above its size bound."
  (yeah-files-test--with-directory root
    (yeah-files-test--write root "a-small.txt" "needle\n")
    (yeah-files-test--write root "b-large.txt" "this line is too long: needle\n")
    (let ((yeah-files--grep-max-file-size 20))
      (let ((result (yeah-files-test--call "grep" "needle" root)))
        (should (equal (plist-get result :content) "a-small.txt:1:needle\n"))
        (should (= (plist-get (plist-get result :metadata) :count) 1))))))

(ert-deftest yeah-files-grep-rejects-invalid-regexp-directory-and-limit ()
  "Grep reports invalid input without starting a subprocess."
  (yeah-files-test--with-directory root
    (should (yeah-files-test--error-p
             (yeah-files-test--call "grep" "[" root)))
    (should (yeah-files-test--error-p
             (yeah-files-test--call
              "grep" "needle" (expand-file-name "missing" root))))
    (should (yeah-files-test--error-p
             (yeah-files-test--call "grep" "needle" root 0)))))

(ert-deftest yeah-files-read-shows-the-tick-to-the-model ()
  "A read of a file open in a buffer gives the model the modification tick."
  (let* ((root (make-temp-file "yeah-tick" t))
         (file (expand-file-name "a.el" root))
         (buffer nil))
    (unwind-protect
        (progn
          (with-temp-file file (insert "(print 1)\n"))
          (setq buffer (find-file-noselect file))
          (let* ((result (yeah-tools-call "read" (list file 1 10)))
                 (text (yeah-result-model-text result)))
            (should (string-match-p "tick" text))))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (ignore-errors (delete-directory root t t)))))

(provide 'test-yeah-files)
;;; test-yeah-files.el ends here
