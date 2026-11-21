;;; check-a-check-that-hangs-is-stopped.el --- the gate stops a check that hangs -*- lexical-binding: t; no-byte-compile: t -*-
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
;; machine, the map stays empty, and nothing says why.  The gate of the
;; method answers such a run with the third answer -- unknown -- and not
;; with a refutation, but only if the gate can say that it did not tell.
;;
;; This check runs a check that hangs -- the fixture that starts a child
;; and waits for ever -- through `scripts/dev check', the way the gate
;; starts a check, with a limit of five seconds, and then proves four
;; things: the fixture was stopped, the child of the fixture was stopped
;; as well, the gate waited for the limit before it stopped the fixture,
;; and the gate answered with the third answer and not with a pass.
;;
;; The measure of the subject is the process itself, by its pid, in the
;; tree of the processes of the system.  The check does not ask the
;; fixture whether it is alive: a process that answers is a process that
;; lives.  The state of the process decides it: `S' and `R' are a
;; process that runs, and `Z' is a zombie -- a process that has died
;; already and waits to be reaped.  The rule is the one of the kernel
;; (`lib/yeah-proc.el').
;;
;; The control of the claim takes the stop out of the timer of the gate:
;; the timer fires, but it does not stop the command, and the check then
;; fails by its own assertion -- the check that hangs was not stopped.
;;
;; No network is involved: the fixture waits for ever, and the child of
;; the fixture is an Emacs that waits for ever.
;;
;; Exit codes: 0 -- the gate stopped the check that hangs and said so;
;; 1 -- it did not.

;;; Code:

(require 'cl-lib)
(require 'yeah-proc)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (< (float-time) deadline) (not (funcall predicate)))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-check--await-dead (pid timeout)
  "Return non-nil when the process PID is gone, at most TIMEOUT seconds.
The process is gone when the state of it says so: a zombie is gone, it
has died already and waits to be reaped."
  (yeah-check--await
   (lambda () (not (yeah-proc--alive-p (yeah-proc--state pid))))
   timeout))

(defun yeah-check--kill-group (pid signal)
  "Send SIGNAL to the process group of PID.
The group is the one of the process that was started: Emacs gives every
child of `make-process' a group of its own.  Return non-nil when the
signal was sent.
The arguments of `call-process' are strings, one by one: a list of
arguments is not a list of strings, and a call that cannot be made says
so instead of failing quietly."
  (let ((kill-bin (or (executable-find "kill") "/bin/kill")))
    (condition-case err
        (zerop (call-process kill-bin nil nil nil
                             (concat "-" signal) "--" (format "-%d" pid)))
      (error (message "hang: the signal %s to the group %d was not sent: %S"
                      signal pid err)
             nil))))

(defun yeah-check--read-report (path)
  "Return the fields of the report in PATH as a plist, or nil.
The report holds one `key=value' line per field: the pid of the fixture
and the pid of the child of the fixture."
  (when (file-exists-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (let (fields)
        (dolist (line (split-string (buffer-string) "\n" t))
          (when (string-match "^\\([a-z]+\\)=\\(.*\\)$" line)
            (push (cons (intern (match-string 1 line))
                        (match-string 2 line))
                  fields)))
        (when fields (nreverse fields))))))

(let* ((root (expand-file-name default-directory))
       (fixture (expand-file-name "tests/support/yeah-hanging-check-fixture.el" root))
       (dev (expand-file-name "scripts/dev" root))
       (limit 5)
       (report (make-temp-file "yeah-hang-report"))
       (output (get-buffer-create " *yeah hang*"))
       (gate
        (let ((process-environment
               (cons (format "YEAH_HANG_FIXTURE_REPORT=%s" report)
                     (cons (format "YEAH_CHECK_TIMEOUT=%d" limit)
                           process-environment))))
          (make-process
           :name "yeah-hang"
           :command (list "bash" dev "check" fixture)
           :connection-type 'pipe
           :noquery t
           :filter (lambda (_process chunk)
                     (with-current-buffer output
                       (goto-char (point-max))
                       (insert chunk))))))
       (fields nil)
       (fixture-pid nil)
       (child-pid nil)
       (started (float-time)))
  (unwind-protect
      (progn
        (unless (file-directory-p "/proc")
          (push "the check cannot measure a process without /proc"
                yeah-check--failures))
        (when (null yeah-check--failures)
          ;; the fixture reports what it started
          (setq fields (yeah-check--await (lambda () (yeah-check--read-report report)) 60))
          (unless fields
            (push "the fixture never reported what it started"
                  yeah-check--failures))
          (when fields
            (let ((pid (string-to-number (or (cdr (assq 'pid fields)) "")))
                  (child (string-to-number (or (cdr (assq 'child fields)) ""))))
              (unless (and (> pid 0) (> child 0))
                (push (format "the report of the fixture is not readable: %S" fields)
                      yeah-check--failures))
              (when (and (> pid 0) (> child 0))
                (setq fixture-pid pid
                      child-pid child)
                ;; the fixture is alive while the gate waits for it
                (unless (yeah-proc--alive-p (yeah-proc--state pid))
                  (push (format "the fixture was not alive (pid %d)" pid)
                        yeah-check--failures))
                ;; and the child it started is alive as well
                (unless (yeah-proc--alive-p (yeah-proc--state child))
                  (push (format "the fixture started no live child (pid %d)" child)
                        yeah-check--failures))
                ;; the gate waits for the limit, and then stops the check
                (unless (yeah-check--await-dead pid 15)
                  (push (format "the check that hangs was not stopped (pid %d)" pid)
                        yeah-check--failures))
                ;; the fixture was alive for the whole limit: the gate did
                ;; not stop it early, it waited and then stopped it
                (let ((waited (- (float-time) started)))
                  (when (< waited (- limit 1))
                    (push (format "the gate stopped the check after %.1f seconds, the limit is %d"
                                  waited limit)
                          yeah-check--failures)))
                ;; the child of the fixture must go with it
                (unless (yeah-check--await-dead child 15)
                  (push (format "the child of the check that hangs stayed behind (pid %d)"
                                child)
                        yeah-check--failures))
                ;; and the gate must answer with the third answer
                (unless (yeah-check--await (lambda () (not (process-live-p gate))) 15)
                  (push "the gate did not finish the run of the check that hangs"
                        yeah-check--failures))
                (when (not (process-live-p gate))
                  (unless (= 3 (process-exit-status gate))
                    (push (format "the gate answered %d to the check that hangs, the third answer is 3"
                                  (process-exit-status gate))
                          yeah-check--failures)))
                ;; and it must say why
                (unless (with-current-buffer output
                          (goto-char (point-min))
                          (re-search-forward (format "passed the limit of %d" limit) nil t))
                  (push "the gate did not say that the check passed its limit"
                        yeah-check--failures)))))))
    ;; the check leaves nothing behind
    (when (and gate (process-live-p gate))
      (yeah-check--kill-group (process-id gate) "TERM")
      (yeah-check--await (lambda () (not (process-live-p gate))) 5)
      (when (process-live-p gate)
        (yeah-check--kill-group (process-id gate) "KILL")))
    ;; a check that fails must not leave the check that hangs behind either
    (dolist (pid (nreverse (delq nil (list child-pid fixture-pid))))
      (when (yeah-proc--alive-p (yeah-proc--state pid))
        (yeah-check--kill-group pid "TERM")
        (yeah-check--await
         (lambda () (not (yeah-proc--alive-p (yeah-proc--state pid))))
         3)
        (when (yeah-proc--alive-p (yeah-proc--state pid))
          (yeah-check--kill-group pid "KILL"))))
    (ignore-errors (delete-file report)))
  (dolist (failure yeah-check--failures)
    (message "hang: %s" failure))
  (when yeah-check--failures
    (with-current-buffer output
      (message "gate output:\n%s" (buffer-string))))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-check-that-hangs-is-stopped.el ends here
