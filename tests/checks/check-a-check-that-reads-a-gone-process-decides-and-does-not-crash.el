;;; check-a-check-that-reads-a-gone-process-decides-and-does-not-crash.el --- a reader of a gone process decides -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The gate of 2026-11-21 read one line as the refutation of a claim that
;; holds.  The check of the pilot that ran out of time died on the
;; filesystem in the middle of the reading of the state of a process: the
;; check looked for the file of the process, the process died in the
;; moment between the look and the read, and the read failed with
;; `file-missing'.  Emacs aborted, the method read the crashed verifier as
;; an error and not as a proven control, and the gate named a refutation
;; where there was none.
;;
;; The reader of the processes of the system now lives in one place
;; (tests/support/yeah-proc.el) and it decides instead of dying: it
;; answers nil when the process is gone, and it catches the error of the
;; file and nothing else.  A reader that swallows every error is a reader
;; that is blind, and a blind reader decides nothing.
;;
;; This check is the proof of that repair, and it must be able to fail:
;;
;;   1. the state of a process that is gone is nil, and no error is raised;
;;   2. the ticks of a process that is gone are nil, and no error is raised;
;;   3. the state of a living process is a letter: the repair did not make
;;      the reader blind;
;;   4. the ticks of a living process are a number;
;;   5. the ticks of the reader are the ticks of the process: the check
;;      reads the file of its own process itself and compares the answer
;;      of the reader with that reading;
;;   6. the reader answers nil for a PID that names no process -- nil, a
;;      string, zero, a negative number -- and it raises no error for it;
;;   7. the checks that read a process hold no path of the tree of the
;;      processes: the reader of the support is the only one that names
;;      one, and each of them names the reader it must use.
;;
;; The first two assertions are the ones that fail on the code before the
;; repair: that code raised `file-missing' out of the reading.  The
;; sixth is the one that fails on a reader that builds the path of the
;; file out of a PID that is not a number: the error of the format is
;; not the error of the file, and such a reader dies instead of
;; deciding.
;;
;; The fifth is the one that keeps the fourth honest.  A reader that
;; answers zero for every process passes "the ticks are a number", and
;; the check of the silent server is then vacuous: the difference of the
;; ticks is zero, and zero does not pass the bound of a core.  The check
;; therefore reads the file of its own process itself, without the
;; reader, and compares.  The ticks of a process never go down, so the
;; answer of the reader must lie between the reading of the check before
;; it and the reading of the check after it -- an exact comparison that
;; no clock can make flaky, because the process of the check burns its
;; own CPU between the two readings.
;;
;; The seventh assertion names no path of the tree of the processes
;; itself, and the first six do not either: the only path this check
;; names is the file of its own process, and it names it to compare the
;; reader with the truth.
;;
;; Exit codes: 0 -- the reader decides; 1 -- it did not.

;;; Code:

(require 'cl-lib)

;; The reader under the proof is the one of the support.
(load (expand-file-name "tests/support/yeah-proc.el") nil t)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defconst yeah-check--readers
  '(("check-a-pilot-that-runs-out-of-time-leaves-no-server.el" . "yeah-proc--state")
    ("check-the-server-does-not-spin-when-the-provider-is-silent.el" . "yeah-proc--ticks"))
  "The checks that read a process, and the reader of the support each of them uses.")

(defconst yeah-check--gone-pid 999999999
  "A process id that names no process.
The kernel gives no process an id above its own limit, so this id is
free on every host.")

(defconst yeah-check--no-pids
  '(nil "42" 0 -1 3.5)
  "The process ids that name no process.
None of them is a positive whole number, and the reader has to answer
nil for every one of them instead of raising the error of the format
of the path.")

(defun yeah-check--root ()
  "Return the root of the repository: the directory that holds `spec.json'."
  (or (locate-dominating-file default-directory "spec.json")
      (expand-file-name default-directory)))

(defun yeah-check--text (path)
  "Return the text of the file PATH, or nil when it cannot be read."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents path)
        (buffer-string))
    (file-error nil)))

(defun yeah-check--call (reader pid)
  "Call READER with PID and return a cons of the outcome and the answer.
The outcome is `ok' when the reader answered and `error' when it raised:
the error is kept, so a reader that dies is named and not hidden."
  (condition-case err
      (cons 'ok (funcall reader pid))
    (error (cons 'error err))))

(defun yeah-check--own-ticks (pid)
  "Return the ticks of CPU that the process PID has used, read here.
This is the reading of the check itself and not the reading of the
support: the file of the process is read directly, and the answer of
the reader of the support is compared with it.  The process of the
check does not die while it reads its own file, so this reading is
safe.  The answer is nil when the file cannot be read."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents (format "/proc/%d/stat" pid))
        (let* ((text (buffer-string))
               (close (cl-position ?\) text :from-end t))
               (fields (split-string (substring text (1+ close)) " " t)))
          ;; The fields after the name: state, ppid, pgrp, session, tty_nr,
          ;; tpgid, flags, minflt, cminflt, majflt, cmajflt, utime, stime.
          (+ (string-to-number (nth 11 fields))
             (string-to-number (nth 12 fields)))))
    (file-error nil)))

(defun yeah-check--ticks-ready (pid)
  "Return non-nil when the process PID has at least one tick of CPU.
The check compares the reader of the support with its own reading, and a
comparison against the ticks of a process that has none proves nothing:
a reader that answers zero for every process would pass it.  The wait
is bounded, and a process that burns no tick at all is a failure of
the check and not a pass."
  (let ((deadline (+ (float-time) 10)))
    (while (and (< (float-time) deadline)
                (let ((ticks (yeah-check--own-ticks pid)))
                  (or (null ticks) (< ticks 1))))
      (sleep-for 0.05))
    (let ((ticks (yeah-check--own-ticks pid)))
      (and (integerp ticks) (>= ticks 1)))))

(let* ((gone yeah-check--gone-pid)
       (self (emacs-pid)))
  ;; The id of the test must be free, or the first two assertions prove
  ;; nothing: a reader that answers nil for a living process would pass
  ;; them.
  (when (file-exists-p (format "/proc/%d" gone))
    (push (format "the process id %d of the test is not free" gone) yeah-check--failures))
  ;; 1. the state of a process that is gone
  (let ((result (yeah-check--call #'yeah-proc--state gone)))
    (cond
     ((not (eq 'ok (car result)))
      (push (format "the state of a process that is gone raised an error: %S" (cdr result))
            yeah-check--failures))
     ((not (null (cdr result)))
      (push (format "the state of a process that is gone is %S and not nil" (cdr result))
            yeah-check--failures))))
  ;; 2. the ticks of a process that is gone
  (let ((result (yeah-check--call #'yeah-proc--ticks gone)))
    (cond
     ((not (eq 'ok (car result)))
      (push (format "the ticks of a process that is gone raised an error: %S" (cdr result))
            yeah-check--failures))
     ((not (null (cdr result)))
      (push (format "the ticks of a process that is gone are %S and not nil" (cdr result))
            yeah-check--failures))))
  ;; 3. the state of a living process
  (let* ((result (yeah-check--call #'yeah-proc--state self))
         (state (and (eq 'ok (car result)) (cdr result))))
    (cond
     ((not (eq 'ok (car result)))
      (push (format "the state of this process raised an error: %S" (cdr result))
            yeah-check--failures))
     ((not (stringp state))
      (push (format "the state of this process is %S and not a letter" state)
            yeah-check--failures))
     ((not (= 1 (length state)))
      (push (format "the state of this process is %S and not one letter" state)
            yeah-check--failures))))
  ;; 4. the ticks of a living process
  (let* ((result (yeah-check--call #'yeah-proc--ticks self))
         (ticks (and (eq 'ok (car result)) (cdr result))))
    (cond
     ((not (eq 'ok (car result)))
      (push (format "the ticks of this process raised an error: %S" (cdr result))
            yeah-check--failures))
     ((not (numberp ticks))
      (push (format "the ticks of this process are %S and not a number" ticks)
            yeah-check--failures))))
  ;; 5. the ticks of the reader are the ticks of the process: the check
  ;;    reads the file of its own process itself and compares
  (unless (yeah-check--ticks-ready self)
    (push "the process of the check has no tick of CPU: the comparison of the ticks proves nothing"
          yeah-check--failures))
  (let* ((before (yeah-check--own-ticks self))
         (result (yeah-check--call #'yeah-proc--ticks self))
         (answer (and (eq 'ok (car result)) (cdr result)))
         (after (yeah-check--own-ticks self)))
    (cond
     ((not (integerp before))
      (push "the check cannot read the ticks of its own process: the comparison proves nothing"
            yeah-check--failures))
     ((numberp answer)
      ;; the ticks of a process never go down, so the answer of the
      ;; reader must lie between the two readings of the check
      (when (or (< answer before) (> answer after))
        (push (format "the ticks of the reader (%S) are not the ticks of the process: the reading of the check saw %S before the reading of the reader and %S after it"
                      answer before after)
              yeah-check--failures)))))
  ;; 6. the reader answers nil for a PID that names no process, and it
  ;;    raises no error for it
  (dolist (pid yeah-check--no-pids)
    (let ((result (yeah-check--call #'yeah-proc--state pid)))
      (cond
       ((not (eq 'ok (car result)))
        (push (format "the state of the process %S raised an error: %S" pid (cdr result))
              yeah-check--failures))
       ((not (null (cdr result)))
        (push (format "the state of the process %S is %S and not nil" pid (cdr result))
              yeah-check--failures))))
    (let ((result (yeah-check--call #'yeah-proc--ticks pid)))
      (cond
       ((not (eq 'ok (car result)))
        (push (format "the ticks of the process %S raised an error: %S" pid (cdr result))
              yeah-check--failures))
       ((not (null (cdr result)))
        (push (format "the ticks of the process %S are %S and not nil" pid (cdr result))
              yeah-check--failures)))))
  ;; 7. the checks that read a process read it through the reader of the
  ;;    support and not through a path of their own
  (dolist (entry yeah-check--readers)
    (let* ((name (car entry))
           (reader (cdr entry))
           (path (expand-file-name (format "tests/checks/%s" name) (yeah-check--root)))
           (text (yeah-check--text path)))
      (cond
       ((null text)
        (push (format "the check %s cannot be read" name) yeah-check--failures))
       ((string-match-p "/proc/" text)
        (push (format "the check %s names a path of the tree of the processes itself" name)
              yeah-check--failures))
       ((not (string-match-p (regexp-quote reader) text))
        (push (format "the check %s does not go through the reader of the support (%s)"
                      name reader)
              yeah-check--failures)))))
  (dolist (failure yeah-check--failures)
    (message "gone-process: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-check-that-reads-a-gone-process-decides-and-does-not-crash.el ends here
