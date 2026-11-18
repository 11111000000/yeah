;;; check-wire-check-decides-its-verdict-by-construction.el --- the check of the wire decides its verdict by construction -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The check of the wire used to be flaky: it read the chunks of the
;; wire with `nreverse', which turns the list over in place and left
;; the variable at the cell that was its head.  The second reading of
;; the wire found one chunk and not the wire, and the check reads the
;; wire many times, so its verdict depended on how many times it had
;; read the wire before.
;;
;; This check is the evidence of that repair.  It takes the control of
;; the claim of the text on the wire — the decoding of the UTF-8 bytes
;; taken out of the wire — and runs the check of the wire against it
;; twenty times in a copy of the repository.  Every one of the twenty
;; runs must fail by an assertion of the check, and every one of them
;; must fail in the same way: the same code of the exit and the same
;; words.  A run that crashes Emacs, a run that hangs, a run that passes
;; and a run that fails in another way are all failures of this check.
;;
;; The check of the wire must also pass on the whole wire, before the
;; control is applied: a check that fails whatever the subject does
;; proves nothing.

;;; Code:

(require 'json)
(require 'seq)

(defvar yeah-check--emacs
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS"))
           (getenv "EMACS"))
      (executable-find "emacs")
      (expand-file-name "~/.nix-profile/bin/emacs"))
  "The Emacs program that runs the check of the wire.")

(defvar yeah-check--root
  (or (locate-dominating-file (or load-file-name buffer-file-name default-directory)
                              "spec.json")
      default-directory)
  "The root of the repository: the directory that holds `spec.json'.
The check knows where it is by the specification it reads, and not by the
depth of its own file.")

(defvar yeah-check--runs 20
  "How many consecutive runs of the control the claim of the wire asks for.")

(defvar yeah-check--run-timeout 120
  "Seconds a run of the check of the wire may take.")

(defconst yeah-check--wire-check "tests/checks/check-wire-carries-the-text.el"
  "The check of the wire, the one this check runs.")

(defconst yeah-check--text-claim "the-text-on-the-wire-is-the-text-the-model-wrote"
  "The claim whose control this check runs.")

(defun yeah-check--field (object key)
  "Return the value of the field KEY of OBJECT, or nil when it has none.
The keys of a JSON object come as symbols from Emacs 30 and as strings
from the older Emacs: the check asks for both and finds the field
whichever way the specification was read."
  (and (listp object)
       (or (alist-get key object)
           (alist-get (symbol-name key) object nil #'string=))))

(defun yeah-check--control-of (claim-id)
  "Return the control of the claim CLAIM-ID, or nil when it has none.
The control is read from the standing specification: the check runs
the control that the claim declares, and not a copy of it."
  (let* ((json-object-type 'alist)
         (spec (json-read-file (expand-file-name "spec.json" yeah-check--root)))
         (claims (yeah-check--field spec 'claims))
         (claim (seq-find (lambda (entry) (equal (yeah-check--field entry 'id)
                                                 claim-id))
                           claims)))
    (and claim (yeah-check--field claim 'control))))

(defun yeah-check--copy-tree (source target)
  "Copy the tree of the directory SOURCE into the directory TARGET."
  (make-directory target t)
  (dolist (entry (directory-files source t directory-files-no-dot-files-regexp t))
    (let ((name (file-name-nondirectory entry)))
      (if (file-directory-p entry)
          (yeah-check--copy-tree entry (expand-file-name name target))
        (copy-file entry (expand-file-name name target))))))

(defun yeah-check--wire-command (directory)
  "Return the command that runs the check of the wire in DIRECTORY."
  (list yeah-check--emacs "-Q" "--batch"
        "-L" (expand-file-name "lib" directory)
        "-L" directory
        "-l" (expand-file-name yeah-check--wire-check directory)))

(defun yeah-check--run-wire-check (directory)
  "Run the check of the wire in DIRECTORY.
Return the code of the run and the words it printed.  The code of a
run that did not finish in time is the symbol `timeout'."
  (let* ((output "")
         (words (generate-new-buffer " *yeah-wire-check words*"))
         (process (make-process
                    :name "yeah-wire-check-run"
                    :command (yeah-check--wire-command directory)
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
                  :name "yeah-wire-control"
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

(defun yeah-check--verdict-of (words)
  "Return the verdict of a run of the check of the wire.
WORDS is what the run printed.  The verdict is the words of the check
itself: the lines that begin with `wire-text:'.  The rest of the output
is the noise of Emacs and of the server, and it says nothing about the
verdict of the check."
  (let (lines)
    (dolist (line (split-string words "\n" t))
      (when (string-prefix-p "wire-text:" line)
        (push line lines)))
    (mapconcat #'identity (nreverse lines) "\n")))

(defun yeah-check--failures ()
  "Run the check of the wire against the control of the claim.
Return the list of the failures of the check."
  (let ((failures nil)
        (control (yeah-check--control-of yeah-check--text-claim))
        (directory (make-temp-file "yeah-wire-control-" t)))
    (unwind-protect
        (progn
          (if (null control)
              (push "the claim of the text on the wire declares no control to run" failures)
            (yeah-check--copy-tree (expand-file-name "lib" yeah-check--root)
                                   (expand-file-name "lib" directory))
            (yeah-check--copy-tree (expand-file-name "tests" yeah-check--root)
                                   (expand-file-name "tests" directory))
            ;; the check of the wire passes on the whole wire
            (let ((run (yeah-check--run-wire-check yeah-check--root)))
              (unless (eq (car run) 0)
                (push (format "the check of the wire does not pass on the whole wire: %S"
                              (car run))
                      failures)))
            ;; the control of the claim, and twenty runs of the check against it
            (let ((code (yeah-check--apply-control control directory)))
              (unless (eq code 0)
                (push (format "the control of the claim of the text on the wire did not apply: %S"
                              code)
                      failures)))
            (let ((verdicts nil))
              (dotimes (run yeah-check--runs)
                (let* ((result (yeah-check--run-wire-check directory))
                       (code (car result))
                       (words (cdr result))
                       (verdict (yeah-check--verdict-of words)))
                  (cond
                   ((eq code 'timeout)
                    (push (format "the run %d of the control did not finish in %d seconds"
                                  (1+ run) yeah-check--run-timeout)
                          failures))
                   ((not (eq code 1))
                    (push (format "the run %d of the control ended with the code %S: the control did not bite by an assertion"
                                  (1+ run) code)
                          failures))
                   ((string-empty-p verdict)
                    (push (format "the run %d of the control did not fail by an assertion of the check: %S"
                                  (1+ run) words)
                          failures))
                   (t
                    (push (cons (1+ run) verdict) verdicts)))))
              (setq verdicts (nreverse verdicts))
              ;; every run must have decided in the same way
              (when verdicts
                (let ((first (cdr (car verdicts)))
                      (others nil))
                  (dolist (entry (cdr verdicts))
                    (unless (equal (cdr entry) first)
                      (push entry others)))
                  (when others
                    (push (format "the runs of the control did not decide the same way: %d of %d runs decided in another way than the first one: %S"
                                  (length others) yeah-check--runs
                                  (cdr (car others)))
                          failures)))))))
      (when (file-directory-p directory)
        (delete-directory directory t)))
    failures))

(let ((failures (yeah-check--failures)))
  (dolist (failure failures)
    (message "wire-verdict: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-wire-check-decides-its-verdict-by-construction.el ends here
