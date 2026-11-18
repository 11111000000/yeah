;;; yeah-hanging-check-fixture.el --- a check that never ends -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The gate of the map runs a check and waits for it.  A check that never
;; ends never lets the gate finish: the gate eats the wall clock of the
;; machine, the map stays empty, and nothing says why.  This fixture is
;; that check: it starts a child of its own -- Emacs gives every child of
;; `make-process' a process group of its own -- reports what it started,
;; and then waits for ever.
;;
;; The check that watches the gate (check-a-check-that-hangs-is-stopped.el)
;; runs this fixture through `scripts/dev check' with a short limit and
;; then watches what is left: the fixture must be gone, the child of the
;; fixture must be gone, and the gate must answer with the third answer --
;; unknown -- and not with a refutation.
;;
;; The fixture is not a check of the gate: it never ends by itself, so the
;; gate must not run it as a check of its own.

;;; Code:

(defun yeah-hang--emacs ()
  "Return the Emacs program that runs the child of the fixture."
  (or (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (executable-find "emacs")))

(defun yeah-hang--report (text)
  "Write TEXT into the report file that the owner of the fixture named."
  (let ((path (getenv "YEAH_HANG_FIXTURE_REPORT")))
    (when path
      (with-temp-file path (insert text)))))

(let* ((child
        (make-process
         :name "yeah-hang-child"
         :command
         (list (yeah-hang--emacs) "-Q" "--batch" "--eval" "(sleep-for 600)")
         :connection-type 'pipe
         :noquery t
         :filter (lambda (_process _chunk) nil))))
  ;; The report is written at once.  The gate stops the fixture at its limit,
  ;; and the limit is shorter than the boot of a child: a report that waits
  ;; for the child to settle is a report that the gate never reads.
  (yeah-hang--report
   (format "pid=%d\nchild=%d\n" (emacs-pid) (process-id child)))
  ;; The fixture waits for ever: it is the check that hangs.
  (while t (accept-process-output nil 0.5)))

;;; yeah-hanging-check-fixture.el ends here
