;;; check-bridge-keeps-the-answer.el --- the bridge does not lose the answer -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The bridge collects what the attached Emacs printed with a process
;; filter.  A process can exit before its last chunk reaches the
;; filter: the answer was then lost and the bridge reported success
;; with an empty output — the person saw an empty buffer that the
;; server had never emptied.
;;
;; The check used to race the subject: it kept a thread spinning to
;; make the parent late, read the buffer of the attached Emacs a
;; hundred and twenty times and failed only when the answer was
;; really lost.  Five runs of six bit and one did not (2026-11-16):
;; the claim came out `inconclusive' and the map came out `unknown'.
;; The check now commands the subject instead of racing it.  The
;; hooks it owns hold the answer of the child process until the
;; bridge asks for the pending output of a process that is gone —
;; the very condition of the defect — and the bridge must deliver
;; the answer all the same.  The same input gives the same verdict
;; every time, and the control of the claim (the drain of the bridge
;; removed) makes the check fail by its own assertion.

;;; Code:

(require 'yeah-bridge)

(defvar yeah-check--emacs
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS"))
           (getenv "EMACS"))
      (executable-find "emacs")
      (expand-file-name "~/.nix-profile/bin/emacs"))
  "The Emacs program that runs the server.")

(defvar yeah-check--emacsclient
  (let* ((dir (file-name-directory yeah-check--emacs))
         (candidate (expand-file-name "emacsclient" dir)))
    (or (and (file-executable-p candidate) candidate)
        (executable-find "emacsclient")
        candidate))
  "The emacsclient program that reaches the server.")

(defconst yeah-check--answer "live text"
  "The text the attached Emacs holds in the buffer of the check.")

(defvar yeah-check--hold-the-answer t
  "Whether the check holds the answer of the child until the bridge drains it.
The control of the claim of the determinism removes this one step: the
check then reads the buffer as it always did, the loss of the answer
is a race again, and the control of the bridge does not bite.")

(defvar yeah-check--held-chunk nil
  "The chunk of the child process that the filter has not delivered yet.")

(defvar yeah-check--held-filter nil
  "The filter of the bridge, kept to deliver the held chunk later.")

(defvar yeah-check--held-process nil
  "The process of the bridge, kept to deliver the held chunk later.")

(defun yeah-check--filter-of (args)
  "Return the filter of ARGS, or nil when ARGS names none."
  (let ((tail args)
        (filter nil))
    (while tail
      (when (eq (car tail) :filter)
        (setq filter (cadr tail)))
      (setq tail (cddr tail)))
    filter))

(defun yeah-check--without-filter (args)
  "Return ARGS without the :filter keyword and its value."
  (let ((rest nil)
        (tail args))
    (while tail
      (unless (eq (car tail) :filter)
        (setq rest (append rest (list (car tail) (cadr tail)))))
      (setq tail (cddr tail)))
    rest))

(defun yeah-check--around-make-process (orig-fun &rest args)
  "Create the process of the bridge, but hold what it prints.
The filter of the process keeps the chunk instead of handing it to
the bridge: the answer of the child reaches the bridge only when the
bridge asks for the pending output of a process that is gone."
  (let ((filter (yeah-check--filter-of args)))
    (if (and filter yeah-check--hold-the-answer)
        (progn
          (setq yeah-check--held-filter filter)
          (let ((process
                 (apply orig-fun
                        (append (yeah-check--without-filter args)
                                (list :filter
                                      (lambda (_process chunk)
                                        (setq yeah-check--held-chunk
                                              (concat yeah-check--held-chunk
                                                      chunk))))))))
            (setq yeah-check--held-process process)
            process))
      (apply orig-fun args))))

(defun yeah-check--around-accept-process-output (orig-fun &optional process &rest args)
  "Run the event loop of Emacs, and give the held answer to the bridge.
The answer of the child is delivered when the bridge asks for the
pending output of a process that is gone: the bridge reads the answer
of the child after its exit, which is the condition the defect is
about."
  (let ((result (apply orig-fun process (or args (list 0.05)))))
    (when (and yeah-check--hold-the-answer
               (null process)
               yeah-check--held-chunk
               yeah-check--held-filter)
      (let ((chunk yeah-check--held-chunk))
        (setq yeah-check--held-chunk nil)
        (funcall yeah-check--held-filter yeah-check--held-process chunk)))
    result))

(defun yeah-check--advise (symbol function)
  "Advise SYMBOL with FUNCTION.
Emacs 30 asks for the kind of the advice and the older Emacs does
not; the advice itself takes the original function as its first
argument in both."
  (if (>= emacs-major-version 30)
      (advice-add symbol :around function)
    (advice-add symbol function)))

(let ((failures nil)
      (name (format "yeah-bridge-keep-%d" (random 1000000))))
  (unwind-protect
      (progn
        (make-process
         :name "yeah-bridge-keep-server"
         :command (list yeah-check--emacs
                        (concat "--daemon=" name)
                        "--eval"
                        (format (concat "(with-current-buffer (get-buffer-create \"*yeah-live*\") "
                                        "(insert \"%s\"))")
                                yeah-check--answer))
         :connection-type 'pipe
         :noquery t)
        ;; wait for the server
        (let ((deadline (+ (float-time) 8)))
          (while (and (< (float-time) deadline)
                      (not (zerop (with-temp-buffer
                                    (call-process yeah-check--emacsclient nil t nil
                                                  "-s" name "--eval" "t")))))
            (accept-process-output nil 0.1)))
        ;; the hooks of the check: the answer of the child waits for the
        ;; bridge to ask for the pending output of a process that is gone
        (yeah-check--advise 'make-process #'yeah-check--around-make-process)
        (yeah-check--advise 'accept-process-output
                            #'yeah-check--around-accept-process-output)
        (unwind-protect
            (let ((text (condition-case err
                           (let ((yeah-bridge-program yeah-check--emacsclient)
                                 (yeah-bridge-server name))
                             (yeah-bridge-buffer-read "*yeah-live*"))
                         (error (format "ERROR: %S" err)))))
              (unless (equal yeah-check--answer text)
                (push (format "the bridge lost the answer: it answered %S" text)
                      failures)))
          (advice-remove 'make-process #'yeah-check--around-make-process)
          (advice-remove 'accept-process-output
                         #'yeah-check--around-accept-process-output)))
    ;; stop the server
    (ignore-errors
      (with-temp-buffer
        (call-process yeah-check--emacsclient nil t nil "-s" name "--eval" "(kill-emacs)")))
    (dolist (failure failures)
      (message "bridge-keep: %s" failure))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-bridge-keeps-the-answer.el ends here
