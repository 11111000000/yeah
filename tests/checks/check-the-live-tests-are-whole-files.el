;;; check-the-live-tests-are-whole-files.el --- the live tests are whole files -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The live tests of `tests/live' talk to a real provider and a real
;; machine.  They are the slowest checks of the project and the ones that
;; are skipped the most often, so a typo in one of them is found late --
;; when the provider is paid for and the machine is busy.
;;
;; This check reads every live test and names the ones that are not whole
;; files: a file that cannot be read to its end was cut in the middle, and
;; a file whose parentheses do not match was cut in the middle too.  It
;; also checks the header and the footer of the file, because a live test
;; without a header is a file that the reader of the repository cannot
;; place.
;;
;; The live tests are not compiled here.  Every one of them says
;; `no-byte-compile: t' and means it: a live test is loaded and run, not
;; compiled, and a compilation of it would say nothing about the code that
;; the provider is asked to run.  The check reads the files and writes
;; nothing: the repository after the check is the repository before it.
;;
;; Exit codes: 0 -- every live test is a whole file; 1 -- one of them is
;; not.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--root ()
  "Return the root of the project."
  (expand-file-name default-directory))

(defun yeah-check--live-tests ()
  "Return the paths of the live tests of the project."
  (sort (file-expand-wildcards (expand-file-name "tests/live/*.el" (yeah-check--root)))
        #'string<))

(defun yeah-check--read-forms (file)
  "Read the forms of FILE and return them.
The file is read to its end.  A file that ends in the middle of a form
raises an error, and the reader says where it stopped."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let (forms)
      (condition-case err
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil)
        (error (signal (car err) (cdr err))))
      (nreverse forms))))

(defun yeah-check--unbalanced (file)
  "Return the line of the unmatched parenthesis of FILE, or nil.
The file is read as a buffer: `check-parens' walks the text and stops at
the first parenthesis that does not match."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (condition-case nil
        (progn (check-parens) nil)
      (error (line-number-at-pos)))))

(defun yeah-check--first-line (file)
  "Return the first line of FILE, or the empty string."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (buffer-substring-no-properties
     (point-min)
     (line-end-position))))

(defun yeah-check--last-line (file)
  "Return the last line of FILE that holds something, or the empty string."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-max))
    (forward-line -1)
    (while (and (not (bobp)) (string-match-p "^[ \t]*$" (buffer-substring-no-properties
                                                       (point-at-bol) (point-at-eol))))
      (forward-line -1))
    (string-trim (buffer-substring-no-properties (point-at-bol) (point-at-eol)))))

(let ((tests (yeah-check--live-tests)))
  (if (null tests)
      (push "there is no live test to read" yeah-check--failures)
    (dolist (test tests)
      (let* ((name (file-name-nondirectory test))
             (header (yeah-check--first-line test))
             (footer (yeah-check--last-line test))
             (forms nil)
             (broken nil))
        (condition-case err
            (setq forms (yeah-check--read-forms test))
          (error (setq broken (error-message-string err))))
        (when broken
          (push (format "the live test %s is not a whole file: %s" name broken)
                yeah-check--failures))
        (unless forms
          (push (format "the live test %s is empty" name) yeah-check--failures))
        (let ((unbalanced (yeah-check--unbalanced test)))
          (when unbalanced
            (push (format "the live test %s has an unmatched parenthesis on line %d"
                          name unbalanced)
                  yeah-check--failures)))
        (unless (string-match-p (format "^;;; %s --- " (regexp-quote name)) header)
          (push (format "the live test %s has no header" name) yeah-check--failures))
        (unless (string-match-p (format "^;;; %s ends here$" (regexp-quote name)) footer)
          (push (format "the live test %s has no footer" name) yeah-check--failures)))))
  (dolist (failure yeah-check--failures)
    (message "live: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-live-tests-are-whole-files.el ends here
