;;; check-bridge-check-decides-the-race-by-construction.el --- the check of the bridge decides the race by construction -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The check of the bridge used to race the subject: it kept a thread
;; spinning to make the parent late, read the buffer of the attached
;; Emacs a hundred and twenty times, and failed only when the answer
;; was really lost.  Five runs of six bit and one did not (2026-11-16):
;; the claim of the bridge came out `inconclusive' and the map came
;; out `unknown'.  An evidence that decides its verdict by a race
;; cannot be read.
;;
;; This check is the evidence of that repair.  It takes the control of
;; the claim of the bridge — the drain of the bridge removed — and runs
;; the check of the bridge against it ten times in a copy of the
;; repository.  Every one of the ten runs must fail by an assertion of
;; the check: the same code, the same verdict, ten times in a row.  A
;; run that crashes Emacs, a run that hangs and a run that passes are
;; all failures of this check.
;;
;; The check of the bridge must also pass on the whole bridge, before
;; the control is applied: a check that fails whatever the subject does
;; proves nothing.

;;; Code:

(require 'json)
(require 'seq)

(defvar yeah-check--emacs
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS"))
           (getenv "EMACS"))
      (executable-find "emacs")
      (expand-file-name "~/.nix-profile/bin/emacs"))
  "The Emacs program that runs the check of the bridge.")

(defvar yeah-check--root
  (or (locate-dominating-file (or load-file-name buffer-file-name default-directory)
                              "spec.json")
      default-directory)
  "The root of the repository: the directory that holds `spec.json'.
The check knows where it is by the specification it reads, and not by
the depth of its own file.")

(defvar yeah-check--runs 10
  "How many consecutive runs of the control the claim of the bridge asks for.")

(defvar yeah-check--run-timeout 120
  "Seconds a run of the check of the bridge may take.")

(defconst yeah-check--bridge-check "tests/checks/check-bridge-keeps-the-answer.el"
  "The check of the bridge, the one this check runs.")

(defun yeah-check--control-of (claim-id)
  "Return the control of the claim CLAIM-ID, or nil when it has none.
The control is read from the standing specification: the check runs
the control that the claim declares, and not a copy of it."
  (let* ((json-object-type 'alist)
         (spec (json-read-file (expand-file-name "spec.json" yeah-check--root)))
         (claims (alist-get "claims" spec))
         (claim (seq-find (lambda (entry) (equal (alist-get "id" entry) claim-id))
                           claims)))
    (and claim (alist-get "control" claim))))

(defun yeah-check--copy-tree (source target)
  "Copy the tree of the directory SOURCE into the directory TARGET."
  (make-directory target t)
  (dolist (entry (directory-files source t directory-files-no-dot-files-regexp t))
    (let ((name (file-name-nondirectory entry)))
      (if (file-directory-p entry)
          (yeah-check--copy-tree entry (expand-file-name name target))
        (file-copy-file entry (expand-file-name name target))))))

(defun yeah-check--bridge-command (directory)
  "Return the command that runs the check of the bridge in DIRECTORY."
  (list yeah-check--emacs "-Q" "--batch"
        "-L" (expand-file-name "lib" directory)
        "-L" directory
        "-l" (expand-file-name yeah-check--bridge-check directory)))

(defun yeah-check--run-bridge-check (directory)
  "Run the check of the bridge in DIRECTORY.
Return the code of the run and the words it printed.  The code of a
run that did not finish in time is the symbol `timeout'."
  (let ((output "")
        (words (generate-new-buffer " *yeah-bridge-check words*"))
        (process (make-process
                  :name "yeah-bridge-check-run"
                  :command (yeah-check--bridge-command directory)
                  :connection-type 'pipe
                  :noquery t
                  :coding '(utf-8 . utf-8)
                  :filter (lambda (_process chunk)
                            (setq output (concat output chunk)))
                  :stderr words)))
    (unwind-protect
        (let ((deadline (+ (float-time) yeah-check--run-timeout)))
          (while (and (process-live-p process)
                      (< (float-time) deadline))
            (accept-process-output process 0.1))
          (if (process-live-p process)
              (progn
                (ignore-errors (kill-process process))
                (cons 'timeout output))
            (cons (process-exit-status process)
                  (concat output (with-current-buffer words (buffer-string))))))
      (when (buffer-live-p words)
        (kill-buffer words)))))

(defun yeah-check--apply-control (control directory)
  "Run the shell command CONTROL in DIRECTORY and return its code."
  (let ((process (make-process
                  :name "yeah-bridge-control"
                  :command (list "sh" "-c"
                                 (format "cd %s && %s"
                                         (shell-quote-argument directory)
                                         control))
                  :connection-type 'pipe
                  :noquery t
                  :coding '(utf-8 . utf-8))))
    (unwind-protect
        (progn
          (while (process-live-p process)
            (accept-process-output process 0.1))
          (process-exit-status process))
      (when (process-live-p process)
        (ignore-errors (kill-process process))))))

(defun yeah-check--failures ()
  "Run the check of the bridge against the control of the claim.
Return the list of the failures of the check."
  (let ((failures nil)
        (control (yeah-check--control-of "bridge-keeps-the-answer"))
        (directory (make-temp-file "yeah-bridge-control-" t)))
    (unwind-protect
        (progn
          (if (null control)
              (push "the claim of the bridge declares no control to run" failures)
            (yeah-check--copy-tree (expand-file-name "lib" yeah-check--root)
                                   (expand-file-name "lib" directory))
            (yeah-check--copy-tree (expand-file-name "tests" yeah-check--root)
                                   (expand-file-name "tests" directory))
            ;; the check of the bridge passes on the whole bridge
            (let ((run (yeah-check--run-bridge-check yeah-check--root)))
              (unless (eq (car run) 0)
                (push (format "the check of the bridge does not pass on the whole bridge: %S"
                              (car run))
                      failures)))
            ;; the control of the claim, and ten runs of the check against it
            (let ((code (yeah-check--apply-control control directory)))
              (unless (eq code 0)
                (push (format "the control of the claim of the bridge did not apply: %S"
                              code)
                      failures)))
            (dotimes (run yeah-check--runs)
              (let* ((result (yeah-check--run-bridge-check directory))
                     (code (car result))
                     (words (cdr result)))
                (cond
                 ((eq code 'timeout)
                  (push (format "the run %d of the control did not finish in %d seconds"
                                (1+ run) yeah-check--run-timeout)
                        failures))
                 ((not (eq code 1))
                  (push (format "the run %d of the control ended with the code %S: the control did not bite by an assertion"
                                (1+ run) code)
                        failures))
                 ((not (string-match-p "bridge-keep:" words))
                  (push (format "the run %d of the control did not fail by an assertion of the check: %S"
                                (1+ run) words)
                        failures)))))))
      (when (file-directory-p directory)
        (delete-directory directory t)))
    failures))

(let ((failures (yeah-check--failures)))
  (dolist (failure failures)
    (message "bridge-race: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-bridge-check-decides-the-race-by-construction.el ends here
