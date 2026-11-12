;;; test-yeah-agent.el --- ERT tests for the agent presets -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; An agent preset is a file, not code.  The tests below write two of them
;; — one Markdown, one Org — and ask the module what it promises: the
;; header is read, the body is not read until the preset is used, and the
;; tools of a preset are the names a child may use.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-agent)

(defconst yeah-agent-test--markdown
  "---\nname: reviewer\ndescription: Reviews a diff and says what is wrong.\nmodel: cheap\ntools: read, grep, diagnostics\ndepth: 1\n---\n\nYou are a reviewer.\n"
  "A Markdown preset.")

(defconst yeah-agent-test--org
  "#+NAME: scout\n#+DESCRIPTION: Finds the place where the thing lives.\n#+TOOLS: read, grep\n#+DEPTH: 2\n\nYou are a scout.\n"
  "An Org preset.")

(defun yeah-agent-test--directory ()
  "Return a directory with two presets in it."
  (let ((directory (make-temp-file "yeah-agent-test" t)))
    (with-temp-buffer
      (insert yeah-agent-test--markdown)
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    (with-temp-buffer
      (insert yeah-agent-test--org)
      (write-region (point-min) (point-max)
                    (expand-file-name "scout.org" directory)))
    directory))

(defun yeah-agent-test--with-directory (body)
  "Run BODY with a directory of presets, and clean up after it."
  (let ((directory (yeah-agent-test--directory)))
    (unwind-protect
        (funcall body directory)
      (ignore-errors (delete-directory directory t)))))

(ert-deftest yeah-agent-discovers-a-markdown-preset ()
  "The header of a Markdown preset is read."
  (yeah-agent-test--with-directory
    (lambda (directory)
      (let ((presets (yeah-agent-discover (list directory))))
        (should (= 2 (length presets)))
        (let ((reviewer (assoc "reviewer"
                               (mapcar (lambda (preset)
                                         (cons (plist-get preset :name) preset))
                                       presets))))
          (should reviewer)
          (should (equal (plist-get (cdr reviewer) :description)
                         "Reviews a diff and says what is wrong."))
          (should (equal (plist-get (cdr reviewer) :model) "cheap"))
          (should (equal (plist-get (cdr reviewer) :tools)
                         '("read" "grep" "diagnostics")))
          (should (equal (plist-get (cdr reviewer) :depth) "1")))))))

(ert-deftest yeah-agent-discovers-an-org-preset ()
  "The header of an Org preset is read."
  (yeah-agent-test--with-directory
    (lambda (directory)
      (let ((scout (cdr (assoc "scout"
                                (mapcar (lambda (preset)
                                          (cons (plist-get preset :name) preset))
                                        (yeah-agent-discover (list directory)))))))
        (should scout)
        (should (equal (plist-get scout :description)
                       "Finds the place where the thing lives."))
        (should (equal (plist-get scout :tools) '("read" "grep")))
        (should (equal (plist-get scout :depth) "2"))))))

(ert-deftest yeah-agent-discovery-does-not-read-the-body ()
  "Discovery reads the header only: the body is read when the preset is used."
  (yeah-agent-test--with-directory
    (lambda (directory)
      (dolist (preset (yeah-agent-discover (list directory)))
        (should-not (plist-get preset :prompt))))))

(ert-deftest yeah-agent-load-reads-the-prompt ()
  "The body of a preset is the prompt of the preset."
  (yeah-agent-test--with-directory
    (lambda (directory)
      (should (equal (plist-get (yeah-agent-load "reviewer" (list directory))
                                :prompt)
                     "You are a reviewer."))
      (should (equal (plist-get (yeah-agent-load "scout" (list directory))
                                :prompt)
                     "You are a scout.")))))

(ert-deftest yeah-agent-load-refuses-an-unknown-preset ()
  "A preset that does not exist is not a preset."
  (yeah-agent-test--with-directory
    (lambda (directory)
      (should-not (yeah-agent-load "nobody" (list directory)))
      (should-not (yeah-agent-find "nobody" (list directory))))))

(ert-deftest yeah-agent-names-lists-the-presets ()
  "The names of the presets are what a caller may ask for."
  (yeah-agent-test--with-directory
    (lambda (directory)
      (should (equal (yeah-agent-names) nil))
      (let ((yeah-agent-directories (list directory)))
        (should (equal (yeah-agent-names) '("reviewer" "scout")))))))

(provide 'test-yeah-agent)
;;; test-yeah-agent.el ends here
