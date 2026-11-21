;;; check-a-process-that-is-dead-is-dead-everywhere.el --- a dead process is dead everywhere -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A process that has died is dead everywhere.  The wave 100 gave the
;; project one reader of the tree of the processes
;; (`lib/yeah-proc.el'): it answers nil for a process that is gone, and
;; it never dies on the filesystem.  The reading of the state and the
;; reading of the ticks are one reader now, but the question whether a
;; process lives was still asked in six checks and in the kernel by the
;; existence of the directory of the process in the tree of the
;; processes.  That question has the wrong answer: the directory of a
;; zombie is there as well, and a zombie is a process that has died
;; already and waits to be reaped.
;;
;; The defect of the kernel: `lib/yeah-life.el' holds the socket of a
;; service, and the name of the socket carries the pid of its owner.  A
;; zombie owner kept the socket, the sweep of the sockets did not take
;; it away, and the adoption of it refused with "belongs to a living
;; process" -- a service that could not start because of a process that
;; is dead.
;;
;; The rule of the life of a process is now one function of one letter:
;; the state of the process.  `S' and `R' are a process that runs, `Z'
;; is a zombie, and everything else -- the state nil of a process that
;; is not there at all included -- is a process that does not run.
;;
;; This check proves that promise in four parts:
;;
;;   1. the rule of the kernel is a function of the letter: `S' and `R'
;;      are alive, `Z' is dead, the state nil is dead, and every other
;;      letter is dead as well;
;;   2. the repair changes the verdict and not only the wording: the
;;      stand gives the old rule a tree of its own and the old rule
;;      calls a zombie alive -- the directory of a zombie is there --
;;      while the new rule calls it dead.  The stand is a table and not
;;      a measurement of the host: a zombie cannot be made to appear on
;;      purpose without a race, and the rule is a function of a letter,
;;      so the verdict can be measured on the letter alone;
;;   3. the rule is not spread over the tree: no check of `tests/checks/'
;;      and no module of `lib/' probes the existence of the path of a
;;      process, no file of them defines a second rule of the life of a
;;      process, the reader of the stat file of a process lives in one
;;      module of the kernel, and a file that asks the rule asks the
;;      state as well;
;;   4. the readings of the kernel still decide: the state of a living
;;      process is a letter, the state of a process that is gone is nil,
;;      and neither reading raises an error.
;;
;; The third part names the file that breaks the rule.  A check that
;; cannot say who breaks the rule is a check that says "somebody".
;;
;; One check of `tests/checks/' reads the stat file of a process by
;; itself: the check of the reader of wave 100 compares the answer of
;; the reader with the file of its own process, and that comparison is
;; the subject of its claim.  The rule of the third part is about the
;; kernel and about the decision of the life: the one reader of the
;; stat file lives in `lib/yeah-proc.el', and no other module of the
;; kernel reads that file.
;;
;; The bite of the check is the rule itself: a rule that calls a zombie
;; alive makes the first part of the check fail, and a check that goes
;; back to the directory of the process makes the third part fail, by
;; the name of the file that does it.
;;
;; Exit codes: 0 -- a dead process is dead everywhere; 1 -- it is not.

;;; Code:

(require 'cl-lib)

;; The rule under the proof is the one of the kernel.
(require 'yeah-proc)

(defvar yeah-dead--failures nil
  "The failures this check found.")

(defconst yeah-dead--gone-pid 999999999
  "A process id that names no process.
The kernel gives no process an id above its own limit, so this id is
free on every host.")

(defconst yeah-dead--states
  '(("S" . t)
    ("R" . t)
    ("Z" . nil)
    ("T" . nil)
    ("D" . nil)
    ("X" . nil))
  "The states of the rule of the life of a process: the letter and
whether a process in that state lives.

`S' and `R' are a process that runs.  `Z' is a zombie: it has died
already and waits to be reaped, it burns no CPU, it answers nobody and
it holds no client.  `T' is a process that is stopped, `D' is a process
that waits in an uninterruptible sleep, and `X' is a letter that the
kernel does not use: none of them is a process that runs, and a process
that does not run is dead as far as the life of a service is concerned.

The state of a process that is not there at all is nil, and nil is not
a letter: it is the answer of the reader, and the rule reads it as
dead.")

(defconst yeah-dead--stand
  '((101 . "S")
    (102 . "Z"))
  "The processes of the stand: a pid and the state of that process.
The first one runs and the second one is a zombie.

The stand is a table and not a measurement of the host: a zombie cannot
be made to appear on purpose without a race -- the kernel reaps a
child as soon as it reads its state -- and the rule of the life of a
process is a function of one letter, so the verdict of the rule can be
measured on the letter alone.")

(defconst yeah-dead--existence-probe
  "file-\\(?:directory\\|exists\\)-p[^)]*/proc/"
  "The shape of a probe for the existence of the path of a process.
The probe asks the tree of the processes whether the path of a process
is there, and the answer is wrong for a zombie: the directory of a
zombie is there as well.")

(defconst yeah-dead--stat-file
  "\"/proc/[^\"]*stat\""
  "The shape of a read of the stat file of a process.")

(defun yeah-dead--root ()
  "Return the root of the repository: the directory that holds `spec.json'."
  (or (locate-dominating-file default-directory "spec.json")
      (expand-file-name default-directory)))

(defun yeah-dead--text (path)
  "Return the text of the file PATH, or nil when it cannot be read."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents path)
        (buffer-string))
    (file-error nil)))

(defun yeah-dead--call (reader pid)
  "Call READER with PID and return a cons of the outcome and the answer.
The outcome is `ok' when the reader answered and `error' when it raised:
the error is kept, so a reader that dies is named and not hidden."
  (condition-case err
      (cons 'ok (funcall reader pid))
    (error (cons 'error err))))

(defun yeah-dead--files (root)
  "Return the files of the tree that carry the rule, with their names.
The rule of the life of a process must not be spread over the checks
and over the kernel, so every one of them is read."
  (let (files)
    (dolist (pattern '("tests/checks/*.el" "lib/*.el"))
      (dolist (path (file-expand-wildcards (expand-file-name pattern root)))
        (push (cons (file-relative-name path root) path) files)))
    (nreverse files)))

(defun yeah-dead--stand-tree ()
  "Return the tree of the stand: a directory for every process of it.
Every process of the kernel has a directory in the tree of the
processes, and a zombie has one as well -- that is the whole of the
defect.  The tree of the stand is the tree the old rule reads."
  (let ((root (make-temp-file "yeah-dead-stand" t)))
    (dolist (entry yeah-dead--stand)
      (make-directory (expand-file-name (format "%d" (car entry)) root) t))
    root))

(defun yeah-dead--old-rule (pid root)
  "Return non-nil when the old rule calls the process PID alive.
The old rule asked whether the directory of the process is there.  The
stand gives the old rule a tree of its own: the root of the stand
stands for the root of the tree of the processes."
  (file-directory-p (expand-file-name (format "%d" pid) root)))

(defun yeah-dead--new-rule (pid)
  "Return non-nil when the rule of the kernel calls the process PID alive.
The state of the process of the stand is the state of the stand: the
rule of the kernel is a function of that letter alone."
  (yeah-proc-alive-p (cdr (assq pid yeah-dead--stand))))

(defun yeah-dead--local-rule (text)
  "Return the names of the functions of TEXT that decide the life of a pid.
A function that decides the life of a pid is a definition whose name
ends in `-alive-p' and whose arguments name a pid.  The rule of the
life of a process is one function of the kernel, and a second one is a
second answer to the same question."
  (let (names)
    (dolist (line (split-string text "\n" t))
      (when (string-match "(\\(?:cl-\\)?defun[ \t]+\\([A-Za-z0-9-]+\\)[ \t]+\\(([^)]*)\\)" line)
        (let ((name (match-string 1 line))
              (args (match-string 2 line)))
          (when (and (string-suffix-p "-alive-p" name)
                     (string-match-p "\\<pid\\>" args))
            (push name names)))))
    (nreverse names)))

(let* ((root (yeah-dead--root))
       (files (yeah-dead--files root)))
  ;; 1. the rule of the life of a process is a function of one letter
  (dolist (entry yeah-dead--states)
    (let* ((state (car entry))
           (lives (cdr entry))
           (answer (yeah-proc-alive-p state)))
      (unless (eq (if answer t nil) lives)
        (push (format "the rule says %s for the state %S, and it must say %s"
                      (if answer "alive" "dead") state (if lives "alive" "dead"))
              yeah-dead--failures))))
  (unless (null (yeah-proc-alive-p nil))
    (push "the rule says alive for the state nil, and a process that is not there is dead"
          yeah-dead--failures))
  ;; 2. the stand: the repair changes the verdict and not only the wording
  (let ((tree (yeah-dead--stand-tree)))
    (unwind-protect
        (dolist (entry yeah-dead--stand)
          (let* ((pid (car entry))
                 (state (cdr entry))
                 (old (yeah-dead--old-rule pid tree))
                 (new (yeah-dead--new-rule pid)))
            (if (string= state "Z")
                ;; a zombie: the old rule calls it alive, the new rule
                ;; calls it dead, and that is the whole of the repair
                (unless (and old (not new))
                  (push (format "the repair does not change the verdict for the zombie %d: the old rule says %s and the new rule says %s"
                                pid (if old "alive" "dead") (if new "alive" "dead"))
                        yeah-dead--failures))
              ;; a process that runs: the two rules must agree
              (unless (and old new)
                (push (format "the repair changes the verdict for the living process %d: the old rule says %s and the new rule says %s"
                              pid (if old "alive" "dead") (if new "alive" "dead"))
                      yeah-dead--failures)))))
      (ignore-errors (delete-directory tree t))))
  ;; 3. the rule is not spread over the tree
  (dolist (entry files)
    (let* ((name (car entry))
           (path (cdr entry))
           (text (yeah-dead--text path)))
      (cond
       ((null text)
        (push (format "the file %s cannot be read" name) yeah-dead--failures))
       (t
        ;; no file probes the existence of the path of a process
        (dolist (line (split-string text "\n" t))
          (when (string-match-p yeah-dead--existence-probe line)
            (push (format "the file %s asks whether the path of a process exists: the state of the process decides whether it lives, and the state is read through the reader of the kernel"
                          name)
                  yeah-dead--failures)))
        ;; no file defines a second rule of the life of a process
        (dolist (rule (yeah-dead--local-rule text))
          (push (format "the file %s defines the rule %s: the rule of the life of a process is one function of the kernel (%s)"
                        name rule "yeah-proc-alive-p")
                yeah-dead--failures))
        ;; the reader of the stat file of a process lives in one module
        ;; of the kernel
        (when (and (string-prefix-p "lib/" name)
                   (not (string= name "lib/yeah-proc.el"))
                   (string-match-p yeah-dead--stat-file text))
          (push (format "the file %s reads the stat file of a process: the reader of the tree of the processes lives in one module of the kernel (lib/yeah-proc.el)"
                        name)
                yeah-dead--failures))
        ;; a file that asks the rule asks the state as well
        (when (and (string-match-p "yeah-proc-alive-p" text)
                   (not (string-match-p "yeah-proc-state" text)))
          (push (format "the file %s asks the rule of the life of a process without asking the state of that process"
                        name)
                yeah-dead--failures))))))
  ;; 4. the readings of the kernel still decide
  (let ((result (yeah-dead--call #'yeah-proc-state (emacs-pid))))
    (cond
     ((not (eq 'ok (car result)))
      (push (format "the state of this process raised an error: %S" (cdr result))
            yeah-dead--failures))
     ((not (and (stringp (cdr result)) (= 1 (length (cdr result)))))
      (push (format "the state of this process is %S and not one letter" (cdr result))
            yeah-dead--failures))))
  (let ((result (yeah-dead--call #'yeah-proc-state yeah-dead--gone-pid)))
    (cond
     ((not (eq 'ok (car result)))
      (push (format "the state of a process that is gone raised an error: %S" (cdr result))
            yeah-dead--failures))
     ((not (null (cdr result)))
      (push (format "the state of a process that is gone is %S and not nil" (cdr result))
            yeah-dead--failures))))
  (dolist (failure yeah-dead--failures)
    (message "dead-process: %s" failure))
  (if yeah-dead--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-process-that-is-dead-is-dead-everywhere.el ends here
