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
;; (lib/yeah-proc.el) and it decides instead of dying: it answers nil
;; when the process is gone, and it catches the error of the file and
;; nothing else.  A reader that swallows every error is a reader that
;; is blind, and a blind reader decides nothing.
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
;;      processes: the reader of the kernel is the only one that names
;;      one, and each of them names the reader it must use;
;;   8. no file of the tree of the checks reads the stat file of a
;;      process by itself -- the one file that may do it is named, and
;;      the guard that watches the tree is proved to bite.
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
;; The eighth assertion is the one that keeps the seventh honest.  The
;; seventh watched two named files, and a third check of `tests/checks/'
;; that read the stat file of a process by itself would have gone
;; unseen: the guard of a claim that is broken is a guard that watches
;; nothing.  The eighth walks the whole tree of the checks and of its
;; support, finds every file that reads the stat file of a process by
;; itself, and names it.
;;
;; The eighth assertion names its exception, and the exception is one
;; file: this check reads the stat file of its own process, and the
;; reading is the subject of the fifth assertion.  The exception is
;; named here and not implied, because a guard that skips what it does
;; not name skips everything.
;;
;; The eighth assertion must also be able to fail, and the eighth proves
;; that: it builds a tree of its own with a file that reads the stat
;; file of a process by itself and with a file that reads the binary of
;; the process, and it asks the guard about both.  The first one must be
;; named, and the second one must not: the binary of a process and the
;; environment of a process are paths of the tree of the processes, and
;; they are not the stat file of a process.  A guard that cannot tell
;; them apart refuses the wrong thing, and a false refusal with a false
;; subject is worse than no refusal at all.
;;
;; The eighth assertion reads the code of a file in the language the
;; file is written in: an Elisp file with the reader of the kernel, so
;; that a comment is not a literal, and any other file with the rule of
;; a script, so that a comment of a script is not a path either.  The
;; path of a script is a word and not a string, because the code of a
;; script may name the file of a process without any quote around it.
;;
;; The eighth assertion reads the code of the files that name a path of
;; the tree of the processes, and it leaves the other files alone: a
;; file that names no path of the tree cannot read a file of the tree.
;;
;; Exit codes: 0 -- the reader decides; 1 -- it did not.

;;; Code:

(require 'cl-lib)

;; The reader under the proof is the one of the kernel.
(require 'yeah-proc)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defconst yeah-check--readers
  '(("check-a-pilot-that-runs-out-of-time-leaves-no-server.el" . "yeah-proc-state")
    ("check-the-server-does-not-spin-when-the-provider-is-silent.el" . "yeah-proc-ticks"))
  "The checks that read a process, and the reader of the kernel each of them uses.")

(defconst yeah-check--stat-exceptions
  '(("tests/checks/check-a-check-that-reads-a-gone-process-decides-and-does-not-crash.el"
     . "the check reads the stat file of its own process to compare the answer of the reader of the kernel with the truth; the process of the check cannot die while it reads its own file"))
  "The files of the tree of the checks that may read the stat file of a process by themselves, and why.
Every one of them is named here, and the name is the whole of the
exception: a file that is not named here may not read the stat file of
a process by itself.  The exception is a file and not a rule, because a
rule that says \"the file that proves the claim\" is a rule that every
file can claim for itself.")

(defconst yeah-check--stat-shape
  "^/proc/.*/stat$"
  "The shape of the content of a literal that names the stat file of a process.
The content must name the file `stat' of the tree of the processes: the
binary of the process, the environment of the process and the directory
of the process are not the stat file of a process, and a guard that
cannot tell them apart refuses the wrong thing.")

(defconst yeah-check--script-stat-shape
  "/proc/[^[:space:]\"']*/stat\\([^[:alnum:]_]\\|$\\)"
  "The shape of a word of the code of a script that names the stat file of a process.
The word of a script is not a string: the code of a script may name
the file of a process without any quote around it, and a guard that
watches the strings of a script only watches the half of the code.")

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
reader of the kernel: the file of the process is read directly, and the answer of
the reader of the kernel is compared with it.  The process of the
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
The check compares the reader of the kernel with its own reading, and a
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

(defun yeah-check--tree-files (root)
  "Return the files of the tree of the checks and of its support, with their names.
The name of a file is its path from ROOT: the guard of the eighth
assertion watches the tree and not two files of it."
  (let (files)
    (dolist (dir '("tests/checks" "tests/support"))
      (let ((path (expand-file-name dir root)))
        (when (file-directory-p path)
          (dolist (entry (directory-files path t directory-files-no-dot-files-regexp t))
            (when (file-regular-p entry)
              (push (cons (file-relative-name entry root) entry) files))))))
    (nreverse files)))

(defun yeah-check--script-code (text kind)
  "Return TEXT without the comments of a script.
KIND is `shell' or `c-like'.  A comment of the shell begins with a `#'
that starts a word, and a comment of the language of the browser begins
with `//' or with `/*'.  A quoted string is not a comment: the scan
knows the quotes, and a path that a comment names is not a read."
  (let ((code nil)
        (quote nil)
        (escaped nil)
        (comment nil)
        (index 0)
        (size (length text)))
    (while (< index size)
      (let ((char (aref text index)))
        (cond
         ((eq comment 'line)
          (if (= char ?\n)
              (progn (setq comment nil) (push char code))
            (setq index (1+ index))))
         ((eq comment 'block)
          (if (and (= char ?\*)
                   (< (1+ index) size)
                   (= (aref text (1+ index)) ?/))
              (progn (setq comment nil) (setq index (+ index 2)))
            (setq index (1+ index))))
         (escaped
          (setq escaped nil)
          (push char code)
          (setq index (1+ index)))
         ((and quote (= char ?\\))
          (setq escaped t)
          (push char code)
          (setq index (1+ index)))
         ((and quote (= char quote))
          (setq quote nil)
          (push char code)
          (setq index (1+ index)))
         ((null quote)
          (cond
           ((or (= char ?\") (= char ?\'))
            (setq quote char)
            (push char code)
            (setq index (1+ index)))
           ((and (eq kind 'shell)
                 (= char ?\#)
                 (or (null code) (memq (car code) '(?\s ?\t ?\n))))
            (setq comment 'line)
            (setq index (1+ index)))
           ((and (eq kind 'c-like)
                 (= char ?/)
                 (< (1+ index) size)
                 (= (aref text (1+ index)) ?/))
            (setq comment 'line)
            (setq index (+ index 2)))
           ((and (eq kind 'c-like)
                 (= char ?/)
                 (< (1+ index) size)
                 (= (aref text (1+ index)) ?*))
            (setq comment 'block)
            (setq index (+ index 2)))
           (t
            (push char code)
            (setq index (1+ index)))))
         (t
          (push char code)
          (setq index (1+ index))))))
    (apply #'string (nreverse code))))

(defun yeah-check--collect-literals (form out)
  "Add the string literals of FORM to OUT and return the result.
A form of the reader of the kernel is a tree, and the literals of the
tree are the literals of the code of the file."
  (cond
   ((stringp form) (cons form out))
   ((not (consp form)) out)
   (t
    (let ((tail form)
          (acc out))
      (while (consp tail)
        (setq acc (yeah-check--collect-literals (car tail) acc))
        (setq tail (cdr tail)))
      (if tail
          (yeah-check--collect-literals tail acc)
        acc)))))

(defun yeah-check--text-literals (text)
  "Return the string literals of TEXT, read out of its text.
The literals of a file that does not parse are read this way: such a
file cannot be loaded either, and a guard that stops watching a file
that cannot be loaded is a guard that watches nothing."
  (let (literals
        (start 0))
    (while (string-match "\"[^\"]*\"" text start)
      (let ((begin (match-beginning 0))
            (end (match-end 0)))
        (push (substring text (1+ begin) (1- end)) literals)
        (setq start end)))
    (nreverse literals)))

(defun yeah-check--elisp-stat-reads (text)
  "Return the literals of the code of TEXT that name the stat file of a process.
The file is read with the reader of the kernel: a comment is not a
literal, and a literal of the code is a literal of the file.  A file
that does not parse is read out of its text instead, so that the guard
keeps watching it."
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert text)
    (goto-char (point-min))
    (let (literals)
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (setq literals (yeah-check--collect-literals form literals))))
        (end-of-file nil)
        (error (setq literals (yeah-check--text-literals text))))
      (delq nil (mapcar (lambda (literal)
                          (when (string-match-p yeah-check--stat-shape literal)
                            literal))
                        literals)))))

(defun yeah-check--script-stat-reads (text kind)
  "Return the paths of the stat file of a process that the code of TEXT names.
The code of a script is the text without its comments, and the comments
are cut by the rule of the script.  A path of a script is a word and not
a string: the code of a script may name the file of a process without
any quote around it."
  (let ((code (yeah-check--script-code text kind)))
    (when (string-match-p yeah-check--script-stat-shape code)
      (list (match-string 0 code)))))

(defun yeah-check--stat-reads (name text)
  "Return the literals of TEXT that name the stat file of a process.
NAME is the name of the file and TEXT is its text.  The file is read in
the language it is written in: an Elisp file with the reader of the
kernel, and any other file with the rule of a script."
  (cond
   ((string-suffix-p ".el" name)
    (yeah-check--elisp-stat-reads text))
   ((or (string-suffix-p ".ts" name)
        (string-suffix-p ".mjs" name)
        (string-suffix-p ".js" name))
    (yeah-check--script-stat-reads text 'c-like))
   (t
    (yeah-check--script-stat-reads text 'shell))))

(defun yeah-check--raw-readers (root)
  "Return the names of the files that read the stat file of a process by themselves.
ROOT is the root of the repository.  The files of the tree of the checks
and of its support are read, the ones that are named as exceptions are
left alone, and the rest are named when they read the stat file of a
process by themselves."
  (let (readers)
    (dolist (entry (yeah-check--tree-files root))
      (let ((name (car entry))
            (text (yeah-check--text (cdr entry))))
        (cond
         ((null text)
          (push (format "the file %s cannot be read" name) yeah-check--failures))
         ((assoc name yeah-check--stat-exceptions) nil)
         ;; A file that names no path of the tree of the processes
         ;; cannot read a file of the tree of the processes.  The guard
         ;; reads the code of the files that do name one, and the files
         ;; that name none are left alone.
         ((not (string-match-p "/proc" text)) nil)
         ((yeah-check--stat-reads name text)
          (push name readers)))))
    (nreverse readers)))

(defun yeah-check--stand-tree ()
  "Return the root of the stand: a tree of the checks with three files in it.
The first file reads the stat file of a process by itself, and the
second one reads the binary of the process.  The first one must be named
by the guard, and the second one must not.  The third file carries the
name of the file that proves the claim and reads the stat file as well:
the guard must not name it, because the exception of that file is named."
  (let* ((root (make-temp-file "yeah-check-stand"))
         (dir (expand-file-name "tests/checks" root)))
    (delete-file root)
    (make-directory dir t)
    (with-temp-file (expand-file-name "check-the-forgery.el" dir)
      (insert ";;; check-the-forgery.el --- the forgery of the guard -*- lexical-binding: t; -*-\n"
              ";; The forgery reads the stat file of a process by itself.\n"
              "(insert-file-contents (format \"/proc/%d/stat\" 1))\n"))
    (with-temp-file (expand-file-name "check-the-binary.el" dir)
      (insert ";;; check-the-binary.el --- the binary of the process -*- lexical-binding: t; -*-\n"
              ";; The binary of the process is not the stat file of a process.\n"
              "(file-executable-p \"/proc/self/exe\")\n"))
    (with-temp-file (expand-file-name "check-a-check-that-reads-a-gone-process-decides-and-does-not-crash.el" dir)
      (insert ";;; check-a-check-that-reads-a-gone-process-decides-and-does-not-crash.el --- the exception -*- lexical-binding: t; -*-\n"
              ";; The file that proves the claim reads the stat file of its own process.\n"
              "(insert-file-contents (format \"/proc/%d/stat\" 1))\n"))
    root))

(let* ((gone yeah-check--gone-pid)
       (self (emacs-pid)))
  ;; The id of the test must be free, or the first two assertions prove
  ;; nothing: a reader that answers nil for a living process would pass
  ;; them.  The reader of the kernel says whether the id names a
  ;; process: a process that the kernel has not reaped yet has a state
  ;; as well.  The reader must answer here without an error, and the
  ;; check says so by name when it does not.
  (let ((result (yeah-check--call #'yeah-proc-state gone)))
    (cond
     ((not (eq 'ok (car result)))
      (push (format "the reader raised an error for the process id %d of the test: %S"
                    gone (cdr result))
            yeah-check--failures))
     ((not (null (cdr result)))
      (push (format "the process id %d of the test is not free" gone) yeah-check--failures))))
  ;; 1. the state of a process that is gone
  (let ((result (yeah-check--call #'yeah-proc-state gone)))
    (cond
     ((not (eq 'ok (car result)))
      (push (format "the state of a process that is gone raised an error: %S" (cdr result))
            yeah-check--failures))
     ((not (null (cdr result)))
      (push (format "the state of a process that is gone is %S and not nil" (cdr result))
            yeah-check--failures))))
  ;; 2. the ticks of a process that is gone
  (let ((result (yeah-check--call #'yeah-proc-ticks gone)))
    (cond
     ((not (eq 'ok (car result)))
      (push (format "the ticks of a process that is gone raised an error: %S" (cdr result))
            yeah-check--failures))
     ((not (null (cdr result)))
      (push (format "the ticks of a process that is gone are %S and not nil" (cdr result))
            yeah-check--failures))))
  ;; 3. the state of a living process
  (let* ((result (yeah-check--call #'yeah-proc-state self))
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
  (let* ((result (yeah-check--call #'yeah-proc-ticks self))
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
         (result (yeah-check--call #'yeah-proc-ticks self))
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
    (let ((result (yeah-check--call #'yeah-proc-state pid)))
      (cond
       ((not (eq 'ok (car result)))
        (push (format "the state of the process %S raised an error: %S" pid (cdr result))
              yeah-check--failures))
       ((not (null (cdr result)))
        (push (format "the state of the process %S is %S and not nil" pid (cdr result))
              yeah-check--failures))))
    (let ((result (yeah-check--call #'yeah-proc-ticks pid)))
      (cond
       ((not (eq 'ok (car result)))
        (push (format "the ticks of the process %S raised an error: %S" pid (cdr result))
              yeah-check--failures))
       ((not (null (cdr result)))
        (push (format "the ticks of the process %S are %S and not nil" pid (cdr result))
              yeah-check--failures)))))
  ;; 7. the checks that read a process read it through the reader of the
  ;;    kernel and not through a path of their own
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
        (push (format "the check %s does not go through the reader of the kernel (%s)"
                      name reader)
              yeah-check--failures)))))
  ;; 8. no file of the tree of the checks reads the stat file of a
  ;;    process by itself, and the guard that watches the tree bites
  (dolist (name (yeah-check--raw-readers (yeah-check--root)))
    (push (format "the file %s reads the stat file of a process by itself: the reader of the tree of the processes lives in one module of the kernel (lib/yeah-proc.el), and the files that may read it are named in the list of the exceptions"
                  name)
          yeah-check--failures))
  (let ((stand (yeah-check--stand-tree)))
    (unwind-protect
        (let ((named (yeah-check--raw-readers stand)))
          (unless (member "tests/checks/check-the-forgery.el" named)
            (push (format "the guard does not name the file that reads the stat file of a process by itself: %S" named)
                  yeah-check--failures))
          (when (member "tests/checks/check-the-binary.el" named)
            (push "the guard names the file that reads the binary of the process: the stat file of a process is not every path of the tree of the processes"
                  yeah-check--failures))
          (when (member "tests/checks/check-a-check-that-reads-a-gone-process-decides-and-does-not-crash.el" named)
            (push "the guard names the file that proves the claim: the exception of the file that proves the claim is named, and a guard that skips what it does not name skips everything"
                  yeah-check--failures)))
      (ignore-errors (delete-directory stand t))))
  (dolist (failure yeah-check--failures)
    (message "gone-process: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-check-that-reads-a-gone-process-decides-and-does-not-crash.el ends here
