;;; check-runtime-never-blocks.el --- canary for the runtime -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A call that fails is tried again. A call that hangs is cut. A model
;; that asks for the same thing for ever is stopped. And none of it
;; holds the main loop.
;;
;; Exit codes: 0 — the runtime behaves; 1 — it does not.

;;; Code:

(require 'yeah-runtime)

(defvar yeah-check--failures nil
  "What the check found wrong.")

(defun yeah-check--fail (text)
  "Record TEXT as a failure."
  (push text yeah-check--failures))

(defun yeah-check--wait (done)
  "Let the event loop run until DONE is non-nil, or a minute passes."
  (let ((waited 0))
    (while (and (null done) (< waited 60))
      (accept-process-output nil 0.2)
      (setq waited (+ waited 0.2)))
    done))

(defun yeah-check--call (command retries timeout)
  "Run COMMAND through the runtime and return the outcome."
  (let ((outcome nil))
    (yeah-runtime-call command (lambda (result) (setq outcome result))
                       :retries retries :timeout timeout)
    (yeah-check--wait outcome)
    outcome))

(defun yeah-check--failing-call ()
  "A call that fails is tried again, and then gives up."
  (let ((outcome (yeah-check--call "exit 3" 2 10)))
    (unless outcome
      (yeah-check--fail "the failing call never came back"))
    (when outcome
      (when (plist-get outcome :ok)
        (yeah-check--fail (format "the failing call was called successful: %S" outcome)))
      (unless (= 3 (plist-get outcome :attempts))
        (yeah-check--fail (format "the call was tried %s times, expected 3"
                                  (plist-get outcome :attempts)))))))

(defun yeah-check--working-call ()
  "A call that succeeds is not tried again."
  (let ((outcome (yeah-check--call "printf hello" 2 10)))
    (unless (and outcome (plist-get outcome :ok))
      (yeah-check--fail (format "the call that should have worked did not: %S" outcome)))
    (when outcome
      (unless (= 1 (plist-get outcome :attempts))
        (yeah-check--fail (format "the call was tried %s times, expected 1"
                                  (plist-get outcome :attempts))))
      (unless (string-match-p "hello" (or (plist-get outcome :output) ""))
        (yeah-check--fail "the output of the call was lost")))))

(defun yeah-check--hanging-call ()
  "A call that hangs is cut."
  (let ((outcome (yeah-check--call "sleep 30" 0 1)))
    (unless outcome
      (yeah-check--fail "the hanging call was never cut"))
    (when outcome
      (unless (plist-get outcome :timeout)
        (yeah-check--fail (format "the hanging call was not marked as a timeout: %S"
                                  outcome))))))

(defun yeah-check--loop ()
  "Repeated mutation is a loop; repeated inspection is legitimate."
  (unless (yeah-runtime-doom-loop-p '((edit "/x") (edit "/x") (edit "/x")))
    (yeah-check--fail "the loop was not seen"))
  (when (yeah-runtime-doom-loop-p '((edit "/x") (edit "/y") (edit "/x")))
    (yeah-check--fail "a run that was not a loop was called a loop"))
  (when (yeah-runtime-doom-loop-p '((read "/x") (read "/x") (read "/x")))
    (yeah-check--fail "read-only inspection was called a loop"))
  (unless (null (yeah-runtime-doom-loop-p '((edit "/x") (edit "/y"))))
    (yeah-check--fail "two calls were called a loop")))

(yeah-check--failing-call)
(yeah-check--working-call)
(yeah-check--hanging-call)
(yeah-check--loop)

(dolist (failure yeah-check--failures)
  (message "runtime: %s" failure))
(if yeah-check--failures
    (kill-emacs 1)
  (kill-emacs 0))

;;; check-runtime-never-blocks.el ends here
