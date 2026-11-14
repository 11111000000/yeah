;;; check-runtime-stays-responsive.el --- a big estimate does not freeze the loop -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The service Emacs is as single-threaded as the editor it serves: a long
;; synchronous computation blocks timers, process filters and the wire.
;; Token estimation used to walk the text character by character in Lisp,
;; so a large context froze the loop for seconds.
;;
;; This check estimates a 10 MiB text while a short timer is armed: the
;; timer must fire on time.  Against the per-character implementation the
;; estimate takes seconds and the timer fires seconds late; against the
;; C-speed `how-many' implementation it fires on time.
;;
;; The direct measurement of the estimate is the load-independent part:
;; 10 MiB take tens of milliseconds with `how-many' and seconds when the
;; text is walked in Lisp.  The timer bound is generous on purpose — a
;; loaded machine may be slow — but the estimate bound is not.

;;; Code:

(require 'yeah-context)

(let ((fired-at nil)
      (start (float-time))
      (big (make-string 10000000 ?a)))
  (run-with-timer 0.1 nil (lambda () (setq fired-at (float-time))))
  (let ((estimate-start (float-time)))
    (yeah-context-estimate-tokens big)
    (let ((elapsed (- (float-time) estimate-start)))
      (unless (< elapsed 1.0)
        (message "responsive: the estimate took %.3f s for 10 MiB" elapsed)
        (kill-emacs 1))
      (accept-process-output nil 3.0)
      (let ((slack (and fired-at (- fired-at start))))
        (unless (and fired-at (< slack 3.0))
          (message "responsive: the timer fired late (%s s)" slack)
          (kill-emacs 1))
        (kill-emacs 0)))))

;;; check-runtime-stays-responsive.el ends here
