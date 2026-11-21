;;; check-a-killed-run-leaves-no-copy-behind.el --- a killed run leaves no copy behind -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The method works in a temporary directory of its own: `mathc-v5-<pid>-<n>'
;; in the temporary directory of the machine.  The method removes that
;; directory when it ends, and a killed process does not end: it leaves the
;; directory and everything in it.  The measurement of 2026-11-18: forty-eight
;; copies, about a gigabyte, left by the runs that were killed.
;;
;; This check covers the way out of that in the project: after the run the
;; gate removes the copies of the runs that are gone.  The name of a copy
;; holds the pid of the run that made it, and the sweep of the copies
;; touches only the copies whose run is gone.
;;
;; The check runs the real gate (through the wrapper of the project) with a
;; stand-in for the method (tests/support/yeah-fake-method.sh): the real
;; method takes minutes and writes the evidence trail of the project, and
;; a check must not do either.  The stand-in hangs on its first attempt, so
;; that the check can kill the run the way an unknown sender killed three
;; runs of the method on 2026-11-18, and answers on the second one.
;;
;; The check makes two copies of runs: the copy of the run that is killed
;; (the name of that copy carries the pid of the run, and the run dies
;; before the gate answers) and the copy of a run that is alive (the pid of
;; the check itself).  The gate must remove the first and leave the second:
;; a sweep that removes both would take the work of a run that is still
;; going.
;;
;; The control of the claim takes the sweep away from the gate: the copy of
;; the run that is killed stays, and the check fails by its own assertion.
;; The other control takes the pid away from the sweep: the copy of the
;; living run is removed as well, and the check fails by the other of its
;; assertions.
;;
;; No network is involved: the method is a stand-in, and the copies live in
;; the temporary directory of the machine.
;;
;; Exit codes: 0 -- the copy of the run that was killed was removed and the
;; copy of the living run stayed; 1 -- it was not.

;;; Code:

(require 'cl-lib)

(defvar yeah-copies--failures nil
  "The failures this check found.")

(defun yeah-copies--temp-base ()
  "Return the temporary directory the machine uses."
  (let ((tmp (getenv "TMPDIR")))
    (if (and tmp (not (string= tmp ""))) tmp "/tmp")))

(defun yeah-copies--make-copy (base pid)
  "Make the copy of a run with the pid PID in BASE, and return its path."
  (let ((dir (expand-file-name (format "mathc-v5-%d-0" pid) base)))
    (make-directory dir t)
    (with-temp-buffer
      (insert "copy\n")
      (write-region (point-min) (point-max)
                    (expand-file-name "marker" dir) nil 'silent))
    dir))

(defun yeah-copies--base-environment ()
  "Return the environment of this process as a list of NAME=VALUE strings.
The environment of Emacs is the one that the children inherit; when the
variable is empty the environment is read from the kernel, because a child
that gets no PATH finds no program at all."
  (or (and process-environment
           (append process-environment nil))
      (and (file-readable-p "/proc/self/environ")
           (with-temp-buffer
             (insert-file-contents "/proc/self/environ")
             (split-string (buffer-string) "\0" t)))
      '()))

(defun yeah-copies--environment (extra)
  "Return the environment of the children with the entries of EXTRA in it.
The entries of EXTRA win over the entries of the environment of this
process: a name that is set twice is a name that is set by accident."
  (let* ((names (mapcar (lambda (entry) (car (split-string entry "=")))
                        extra))
         (base (cl-remove-if (lambda (entry)
                               (member (car (split-string entry "=")) names))
                             (yeah-copies--base-environment))))
    (append base extra)))

(defun yeah-copies--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (< (float-time) deadline) (not (funcall predicate)))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-copies--await-exit (process timeout)
  "Wait for PROCESS to end, at most TIMEOUT seconds, and return its exit code.
Return nil when the process is still alive when the time is up."
  (let ((deadline (+ (float-time) timeout)))
    (while (and (process-live-p process) (< (float-time) deadline))
      (accept-process-output process 0.05))
    (unless (process-live-p process)
      (process-exit-status process))))

(defun yeah-copies--kill (pid)
  "Kill the process PID with SIGKILL and return non-nil when the signal was sent."
  (and pid (integerp pid) (> pid 0)
       (condition-case nil
           (progn (signal-process pid 'KILL) t)
         (error nil))))

(defun yeah-copies--read-attempts (path)
  "Return the attempts of the run in PATH as a list of alists, or nil.
The file holds one line per attempt: `run=N pid=P' for an attempt that
started and `done=N' for an attempt that ended.

The attempt is an alist and not a plist on purpose: `assq' reads an
alist, and `assq' on a plist answers nil without a word -- a silent
miss that looks like a run that never started."
  (when (file-exists-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (let (attempts)
        (dolist (line (split-string (buffer-string) "\n" t))
          (cond
           ((string-match "^run=\\([0-9]+\\) pid=\\([0-9]+\\)$" line)
            (push (list (cons :run (string-to-number (match-string 1 line)))
                        (cons :pid (string-to-number (match-string 2 line))))
                  attempts))
           ((string-match "^done=\\([0-9]+\\)$" line)
            (push (list (cons :done (string-to-number (match-string 1 line))))
                  attempts))))
        (when attempts (nreverse attempts))))))

(defun yeah-copies--start-gate (root fake dir base output)
  "Start the gate of the project at ROOT and return its process.
The gate runs the stand-in for the method FAKE, which writes its report
into DIR, and it sweeps the copies in BASE.  The output of the gate goes
into the buffer OUTPUT."
  (let ((environment
         (yeah-copies--environment
          (list (format "MATHC=%s" fake)
                (format "YEAH_FAKE_METHOD_DIR=%s" dir)
                (format "TMPDIR=%s" base)))))
    ;; The environment of a child is the environment of this process with
    ;; the entries of the check in it: a child that gets no PATH finds no
    ;; program at all.
    (let ((process-environment environment))
      (make-process
       :name "yeah-copies-gate"
       :command (list "bash" (expand-file-name "scripts/dev" root)
                      "gate" "--limit" "60" "--attempts" "2")
       :connection-type 'pipe
       :noquery t
       :filter (lambda (_process chunk)
                 (with-current-buffer output
                   (goto-char (point-max))
                   (insert chunk)))))))

(let* ((root (expand-file-name default-directory))
       (base (yeah-copies--temp-base))
       (fake (expand-file-name "tests/support/yeah-fake-method.sh" root))
       (dir (make-temp-file "yeah-copies" t))
       (attempts-file (expand-file-name "attempts" dir))
       (alive-copy (yeah-copies--make-copy base (emacs-pid)))
       (killed-copy nil)
       (killed 0)
       (attempts nil)
       (status nil)
       (gate-process nil)
       (output (get-buffer-create " *yeah gate*"))
       (output-text ""))
  (unwind-protect
      (progn
        (unless (file-directory-p "/proc")
          (push "the check cannot measure a process without /proc"
                yeah-copies--failures))
        (when (null yeah-copies--failures)
          ;; the gate starts the run of the stand-in and waits for it
          (setq gate-process
                (yeah-copies--start-gate root fake dir base output))
          ;; the run hangs on its first attempt and reports its pid
          (setq attempts
                (yeah-copies--await
                 (lambda ()
                   (let ((lines (yeah-copies--read-attempts attempts-file)))
                     (when (cl-some (lambda (attempt) (assq :run attempt)) lines)
                       lines)))
                 30))
          (unless attempts
            (push "the run of the gate never started" yeah-copies--failures))
          (when attempts
            (setq killed (cdr (assq :pid (car attempts))))
            (unless (and killed (> killed 0))
              (push "the first attempt of the run did not report its pid"
                    yeah-copies--failures)))
          ;; the copy of the run is made while the run is alive: that is
          ;; what a killed run leaves behind
          (when (and killed (> killed 0))
            (setq killed-copy (yeah-copies--make-copy base killed)))
          ;; the run is killed the way an unknown sender killed three runs
          ;; of the method on 2026-11-18
          (when (and killed (> killed 0))
            (unless (yeah-copies--kill killed)
              (push (format "the run could not be killed (pid %d)" killed)
                    yeah-copies--failures)))
          ;; the gate answers
          (setq status (yeah-copies--await-exit gate-process 90))
          (unless (and status (= status 0))
            (push (format "the gate answered %s, the answer of a run that held is 0"
                          (or status "nothing"))
                  yeah-copies--failures)))
        ;; the copy of the run that was killed is removed
        (when (and killed-copy (file-directory-p killed-copy))
          (push (format "the copy of the run that was killed stayed behind: %s"
                        killed-copy)
                yeah-copies--failures))
        ;; the copy of the run that is alive stays
        (unless (file-directory-p alive-copy)
          (push (format "the copy of the living run was removed: %s" alive-copy)
                yeah-copies--failures))
        ;; the output of the gate is read before the buffer is killed
        (setq output-text
              (if (buffer-live-p output)
                  (with-current-buffer output (buffer-string))
                "")))
    ;; the check leaves nothing behind
    (ignore-errors (delete-directory killed-copy t))
    (ignore-errors (delete-directory alive-copy t))
    (ignore-errors (delete-directory dir t))
    (when (buffer-live-p output) (kill-buffer output)))
  (dolist (failure yeah-copies--failures)
    (message "copies: %s" failure))
  (when yeah-copies--failures
    (message "gate output:\n%s" output-text))
  (if yeah-copies--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-killed-run-leaves-no-copy-behind.el ends here
