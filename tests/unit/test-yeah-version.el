;;; test-yeah-version.el --- ERT tests for yeah-version -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;; The version token of a file is copied by a model, and a model that copies
;; 64 characters of hex loses some of them: the pilot of 2026-11-15 saw a
;; token of 64 characters come back with six characters missing, and the edit
;; refused a file that had not changed.  The token is therefore short.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-files)
(require 'yeah-version)

(defun yeah-version-test--with-file (content)
  "Write CONTENT into a temporary file and return its path."
  (let ((path (make-temp-file "yeah-version-test-" nil ".txt")))
    (with-temp-file path (insert content))
    path))

(ert-deftest yeah-version-a-token-is-short-enough-to-copy ()
  "The token of a text and of a file is short enough for a model to copy it
back unchanged, and it is a hexadecimal string."
  (let ((token (yeah-version-text "alpha beta")))
    (should (stringp token))
    (should (string-match-p "\\`[0-9a-f]+\\'" token))
    (should (<= (length token) 16))
    (should (>= (length token) 8)))
  (let ((path (yeah-version-test--with-file "alpha beta")))
    (unwind-protect
        (let ((token (yeah-version-file path)))
          (should (stringp token))
          (should (<= (length token) 16)))
      (when (file-exists-p path)
        (delete-file path)))))

(ert-deftest yeah-version-the-token-follows-the-text ()
  "The same text always gives the same token, and a change of the text gives
another one."
  (should (equal (yeah-version-text "alpha beta")
                 (yeah-version-text "alpha beta")))
  (should-not (equal (yeah-version-text "alpha beta")
                      (yeah-version-text "alpha gamma"))))

(ert-deftest yeah-version-the-token-of-a-file-is-the-token-of-a-read ()
  "The token that a read hands out is the token of the file, so that a model
can hand it back to the edit of that file."
  (let ((path (yeah-version-test--with-file "alpha beta")))
    (unwind-protect
        (let* ((result (yeah-files--read path 1 200))
               (version (plist-get (plist-get result :metadata) :version)))
          (should (stringp version))
          (should (equal version (yeah-version-file path))))
      (when (file-exists-p path)
        (delete-file path)))))

(provide 'test-yeah-version)
;;; test-yeah-version.el ends here
