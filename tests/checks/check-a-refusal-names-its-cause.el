;;; check-a-refusal-names-its-cause.el --- the refusal names its cause -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it
;; under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The rule refuses when the declarations of the tools are not known, and a
;; refusal that names no cause cannot be acted on: the cause may be a
;; syntax error in a module of the kernel, and the person who reads the
;; refusal needs the name of the file and not only the fact that the
;; registry of the tools is absent.
;;
;; The check copies the `lib/' of the repository into a temporary directory,
;; breaks `yeah-result.el' in the copy, and asks the rule for the profile
;; `plan' there.  The load of the registry of the tools goes through
;; `lib/yeah-tools.el', and that module requires `yeah-result.el', so the
;; broken module is the cause of the refusal; the refusal must name it.
;;
;; The question is asked in a child process.  The rule and the registry are
;; modules of the kernel, and a module that is already loaded in this
;; Emacs cannot be loaded again from the copy: the answer of the child is
;; the only answer that can be about the copy.
;;
;; Only `lib/' is copied: the modules of the kernel are the subject of the
;; refusal, and the copy of the whole tree would carry the seventy-four
;; megabytes of the plugin of the orchestrator into every run of the gate.
;; The copy is deleted when the check is done, and the tree of the
;; repository is never written.
;;
;; Exit codes: 0 -- the refusal names its cause; 1 -- it does not, or the
;; rule did not refuse at all.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defconst yeah-check--child-source
  ";;; -*- lexical-binding: t; no-byte-compile: t -*-
(condition-case e
    (progn
      (require 'yeah-perm)
      (yeah-perm-profile \"plan\")
      (princ \"REFUSAL-NONE\"))
  (error
   (princ \"REFUSAL=\")
   (princ (error-message-string e))))
(kill-emacs 0)
"
  "The Elisp source of the child that asks the rule for the profile.")

(defun yeah-check--expect (ok message)
  "Record MESSAGE as a failure when OK is nil."
  (unless ok
    (push message yeah-check--failures)))

(defun yeah-check--root ()
  "Return the root of the repository."
  (or (locate-dominating-file default-directory "spec.json")
      (expand-file-name default-directory)))

(defun yeah-check--emacs ()
  "Return the Emacs program to run the child, or nil."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-check--copy (root)
  "Return a copy of the `lib/' of ROOT in a temporary directory.
The copy holds the modules of the kernel themselves, so the load path of the
copy is the copy."
  ;; The name of the copy is made and not the directory: `copy-directory'
  ;; makes the directory itself, and it refuses a directory that is
  ;; already there.
  (let ((copy (make-temp-name "yeah-refusal")))
    (copy-directory (expand-file-name "lib" root) copy nil nil t)
    copy))

(defun yeah-check--break (copy)
  "Break the module of the result in the copy COPY.
The module is left with a form that is not closed, so that the load of it
fails and the failure names the file."
  (with-temp-file (expand-file-name "yeah-result.el" copy)
    (insert "(defun yeah-result--broken ()\n")))

(defun yeah-check--ask (copy)
  "Return the answer of the rule in the copy COPY, as a string.
The child is a fresh Emacs: its load path holds the copy and nothing else
of this repository, so the rule that answers is the rule of the copy."
  (let ((script (expand-file-name "child.el" copy))
        (chunks nil)
        (process nil))
    (with-temp-file script
      (insert yeah-check--child-source))
    (setq process
          (make-process
           :name "yeah-refusal-child"
           :buffer nil
           :command (list (yeah-check--emacs) "-Q" "--batch"
                          "-L" copy "-l" script)
           :filter (lambda (_process chunk)
                     (push chunk chunks))))
    (let ((deadline (+ (float-time) 60)))
      (while (and (process-live-p process)
                  (< (float-time) deadline))
        (accept-process-output nil 0.1)))
    (when (process-live-p process)
      (ignore-errors (kill-process process)))
    (apply #'concat (nreverse chunks))))

(let ((root (yeah-check--root))
      (copy nil))
  (unwind-protect
      (progn
        (setq copy (yeah-check--copy root))
        (yeah-check--break copy)
        (let ((answer (yeah-check--ask copy)))
          ;; 1. The rule refuses: the declarations of the tools are not known.
          (yeah-check--expect
           (not (string-match-p "REFUSAL-NONE" answer))
           "the rule did not refuse: the safe behaviour of the rule is gone")
          ;; 2. The refusal names the cause of the refusal.
          (yeah-check--expect
           (string-match-p "yeah-result\\.el" answer)
           (format "the refusal does not name the cause: %s" answer))))
    (when copy
      (ignore-errors (delete-directory copy t t)))
    (dolist (failure yeah-check--failures)
      (message "refusal-cause: %s" failure))
    (if yeah-check--failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-a-refusal-names-its-cause.el ends here
