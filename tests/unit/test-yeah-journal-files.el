;;; test-yeah-journal-files.el --- ERT tests for the reader of journals -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; The reader of the journals of a data home meets two things that are not
;; journals: the lock file of Emacs, which exists only while a process holds
;; the journal open, and a file that vanishes between the scan and the read.
;; Both must not break the check that reads them, because a check that
;; crashes does not fail on its own assertion.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'files)
(require 'yeah-journal-files
         (expand-file-name "tests/support/yeah-journal-files.el"))

(defmacro yeah-journal-files-test--with-directory (variable &rest body)
  "Create a temporary directory as VARIABLE and run BODY."
  (declare (indent 1))
  `(let ((,variable (make-temp-file "yeah-journal-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,variable t))))

(defun yeah-journal-files-test--write (root relative content)
  "Write CONTENT below ROOT at RELATIVE and return its path."
  (let ((path (expand-file-name relative root)))
    (make-directory (file-name-directory path) t)
    (with-temp-file path
      (insert content))
    path))

(ert-deftest yeah-journal-files-the-lock-files-are-not-journals ()
  "A lock file of Emacs is not a journal and is not read as one.
The lock file of Emacs is a symlink next to the journal whose name starts
with `.#'; the reader skips it by its name, so a file with that name is
the same probe."
  (yeah-journal-files-test--with-directory root
    (yeah-journal-files-test--write root "sessions/session-1-a.jsonl" "{}\n")
    (yeah-journal-files-test--write root "sessions/.#session-1-a.jsonl" "")
    (let ((files (yeah-journal-files--files root)))
      (should (= 1 (length files)))
      (should (equal "session-1-a.jsonl"
                     (file-name-nondirectory (car files)))))))

(ert-deftest yeah-journal-files-a-file-that-vanished-is-not-a-journal ()
  "A file that disappears between the scan and the read reads as nothing."
  (yeah-journal-files-test--with-directory root
    (let ((path (yeah-journal-files-test--write root "sessions/gone.jsonl" "{}\n")))
      (delete-file path)
      (should (equal "" (yeah-journal-files--read path))))))

(ert-deftest yeah-journal-files-the-text-of-the-journals ()
  "The text of a data home is the text of its journals."
  (yeah-journal-files-test--with-directory root
    (yeah-journal-files-test--write root "sessions/session-1-a.jsonl" "{\"a\":1}\n")
    (yeah-journal-files-test--write root "sessions/session-1-b.jsonl" "{\"b\":2}\n")
    (let ((text (yeah-journal-files--text root)))
      (should (string-match-p "{\"a\":1}" text))
      (should (string-match-p "{\"b\":2}" text)))))

(ert-deftest yeah-journal-files-a-data-home-without-journals ()
  "A data home without journals has no text and no files."
  (yeah-journal-files-test--with-directory root
    (should (null (yeah-journal-files--files root)))
    (should (equal "" (yeah-journal-files--text root)))))

;;; test-yeah-journal-files.el ends here
