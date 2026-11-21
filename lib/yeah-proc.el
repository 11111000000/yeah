;;; yeah-proc.el --- the state and the ticks of a process, read without a race -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A check that measures a process reads the stat file of that process in
;; the tree of the processes of the system.  The process may die between
;; the moment the check looks for the file and the moment the check reads
;; it, and the read then fails with `file-missing'.
;;
;; A check that dies on the filesystem does not die on its own assertion:
;; the method reads the crashed verifier as an error and not as a proven
;; control, and a false refusal with a false subject is worse than no
;; refusal at all.  The gate of 2026-11-21 read one such crash as the
;; refutation of a claim that holds.
;;
;; This module is the one reader of that file, for the kernel and for the
;; checks of the project.  Both of its readers answer nil when the
;; process is gone, and neither of them raises an error.  They catch the
;; error of the file and nothing else: a reader that swallows every error
;; is a reader that is blind, and a blind reader decides nothing.
;;
;; The reader does not look for the file before it reads it.  The
;; existence of a file is not a promise that it is still there, and the
;; check that trusts that promise is the check that crashed.
;;
;; The question whether a process lives has its answer in the state of the
;; process, and the state is one letter.  `S' and `R' are a process that
;; runs, `Z' is a zombie -- a process that is dead and waits to be
;; reaped -- and every other letter is a process that does not run.  A
;; process that is not there has no state at all, and the answer is nil:
;; nil is not a letter and not the number zero.
;;
;; The rule of the life of a process lives here and not in its callers.
;; The tree of the processes cannot answer the question: the directory of
;; a zombie is there as well, and a caller that asks for that directory
;; calls a zombie alive.  A service whose owner is a zombie then holds a
;; socket that nobody may take, and the service cannot start.  A caller
;; that repeats the rule repeats the mistake with it, so the rule is
;; asked here: `(yeah-proc-alive-p (yeah-proc-state pid))'.

;;; Code:

(require 'cl-lib)

(defun yeah-proc--stat-text (pid)
  "Return the text of the stat file of the process PID, or nil.
The answer is nil when the file is gone: the process died while it was
read.  Only the error of the file is caught -- `file-missing' is a kind
of `file-error' -- and nothing else is.

A PID that is not a positive whole number names no process, and the
answer is nil for it too.  The error of the format of the path is not
the error of the file: a reader that raises it does not decide, it
dies.  The reader decides on every PID it is given."
  (when (and (integerp pid) (> pid 0))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents (format "/proc/%d/stat" pid))
          (buffer-string))
      (file-error nil))))

(defun yeah-proc-state (pid)
  "Return the state field of the process PID, or nil when the process is gone.
The state is the letter that follows the name of the process in the stat
file: `S' and `R' for a process that runs, `Z' for a zombie -- a process
that is dead and waits to be reaped -- and so on.  The name of the
process is in parentheses and may hold spaces and parentheses of its own,
so the state is read after the LAST closing parenthesis of the line."
  (let ((text (yeah-proc--stat-text pid)))
    (when (and text (string-match ".*) \\([A-Za-z]\\)" text))
      (match-string 1 text))))

(defun yeah-proc-alive-p (state)
  "Return non-nil when a process in STATE lives.
The state is the letter of the state field of the stat file of a
process.  `S' and `R' are a process that runs, and every other letter
is a process that does not run.

A zombie is dead: it has died already, it burns no CPU, it answers
nobody, and it holds no client.  The letter of the state is the only
thing that tells it from a process that is still there -- the directory
of the process in the tree of the processes tells nothing, because the
directory of a zombie is there as well.

The state nil is the state of a process that is not there at all, and
such a process does not live.  A letter that is not `S' and not `R' is
a process that does not run, and a process that does not run is dead as
far as the life of a service is concerned."
  (and (stringp state)
       (or (string= state "S")
           (string= state "R"))))

(defun yeah-proc--number (field)
  "Return the number in FIELD, or nil when FIELD holds no number.
A field that is not a number is not a zero: a reader that turns it into
a zero decides about a process it knows nothing about."
  (when (and (stringp field) (string-match-p "\\`[0-9]+\\'" field))
    (string-to-number field)))

(defun yeah-proc-ticks (pid)
  "Return the ticks of CPU that the process PID has used, or nil.
The ticks of the stat file are the user time and the system time of the
process, in the units of the clock of the kernel.  The answer is nil
when the process is gone: a process that is not there has no ticks, and
nil is not the number zero."
  (let ((text (yeah-proc--stat-text pid)))
    (when text
      (let ((close (cl-position ?\) text :from-end t)))
        (when close
          (let ((fields (split-string (substring text (1+ close)) " " t)))
            ;; The fields after the name: state, ppid, pgrp, session, tty_nr,
            ;; tpgid, flags, minflt, cminflt, majflt, cmajflt, utime, stime.
            (let ((utime (yeah-proc--number (nth 11 fields)))
                  (stime (yeah-proc--number (nth 12 fields))))
              (when (and utime stime)
                (+ utime stime)))))))))

(provide 'yeah-proc)

;;; yeah-proc.el ends here
