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
;;   5. the checks that read a process hold no path of the tree of the
;;      processes: the reader of the support is the only one that names
;;      one, and each of them names the reader it must use.
;;
;; The first two assertions are the ones that fail on the code before the
;; repair: that code raised `file-missing' out of the reading.
;;
;; The fifth assertion names no path of the tree of the processes itself,
;; and the first two do not either: the only path this check names is the
;; directory of the process that must not exist, and it names it to prove
;; that the process is really gone before it believes the reader.
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
  ;; 5. the checks that read a process read it through the reader of the
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
