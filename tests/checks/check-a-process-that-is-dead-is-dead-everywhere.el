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
;;   3. the rule is not spread over the tree: no file of the tree probes
;;      the existence of the path of a process, no file of it defines a
;;      second rule of the life of a process -- neither by the shape of
;;      the name of a function nor by the trait of a file that decides
;;      the life of a process by itself --, the reader of the stat file
;;      of a process lives in one module of the kernel, and a file that
;;      asks the rule asks the state as well;
;;   4. the readings of the kernel still decide: the state of a living
;;      process is a letter, the state of a process that is gone is nil,
;;      and neither reading raises an error;
;;   5. the kernel asks the rule in both of its places: the socket of a
;;      zombie owner is swept away, a zombie owner is not adopted as if
;;      it lived, and the socket of a living owner is refused and still
;;      there.  The stand answers for the pids of its own -- the state of
;;      the zombie is the letter `Z' and the state of the living process
;;      is the letter `S' -- and the host is never asked about them.
;;
;; The third part names the file that breaks the rule.  A check that
;; cannot say who breaks the rule is a check that says "somebody".
;;
;; The third part of the wave 101 looked at two directories of the tree
;; -- `tests/checks/' and `lib/' -- and it knew a rule of the life of a
;; process by the shape of its name only: a function whose name ends in
;; `-alive-p' and whose arguments name a pid.  The falsifier of the
;; claim of the wave 101 is wider than that: "another file of the
;; repository defines the rule of the life of a process beside it".  A
;; second rule in `scripts/' or in `tests/support/', a second rule with
;; another name, and a second rule that decides the life of a process
;; without the shape of the name were all invisible to that guard, and
;; the promise of the claim was wider than its measurement.
;;
;; The guard of the third part is wider now, on both sides:
;;
;;   * it reads the code of the whole tree and not of two directories of
;;     it.  The files that are not code are left alone, and the reason
;;     is named: a document NAMES the rule of the life of a process --
;;     `spec.json', the records of the waves and the documents of
;;     `docs/' talk about it -- and a program DEFINES it.  A guard that
;;     reads a document for a rule of its own cries wolf;
;;   * it knows a rule of the life of a process by two shapes and not by
;;     one: by the name of a function (`-alive-p' and a process in its
;;     arguments), and by the trait of a file that decides the life of a
;;     process by itself -- a file that reads the state of a process and
;;     holds the letters that live (`S' and `R') decides the life of a
;;     process whatever its functions are called.
;;
;; Two files of the tree are named as the exceptions of the trait, and
;; the names are in the code and not in a guess:
;;
;;   * `lib/yeah-proc.el' is the rule itself;
;;   * the check that proves the rule holds the letters of the stand of
;;     the rule on purpose -- the stand is a table of the states of the
;;     rule, and a table of the letters that live is not a second rule.
;;
;; The rule about the stat file of a process keeps its old scope: it
;; holds for the kernel and not for the checks, because one check of
;; `tests/checks/' reads the stat file of a process by itself, and that
;; check is the subject of the claim of the wave 100.
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
;; The fifth part is the bite of the promise about the socket.  The
;; promise of the claim names two consequences of the rule: the socket
;; of a zombie owner is swept away, and a zombie owner is not adopted
;; as if it lived.  A stand that reads the code is not a stand of those
;; consequences: the stand of the fifth part asks the kernel itself, and
;; the kernel answers with what it does to a socket.  The reader of the
;; state of the process is the only thing the stand replaces, and it
;; replaces it with the letter of a zombie and with the letter of a
;; process that runs -- the rule of the kernel is the one under the
;; proof, and it is asked for its own verdict.
;;
;; Exit codes: 0 -- a dead process is dead everywhere; 1 -- it is not.

;;; Code:

(require 'cl-lib)

;; The rule under the proof is the one of the kernel.
(require 'yeah-proc)
(require 'yeah-life)

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

(defconst yeah-dead--zombie-pid 999999999
  "The process id of the zombie of the stand.
The stand answers for this id and the host is never asked about it: the
id is above the limit of the kernel, so no process of the host has it,
and the letter the stand gives it is the letter of a zombie.")

(defconst yeah-dead--living-pid 999999998
  "The process id of the living process of the stand.
The stand answers for this id with the letter of a process that runs.")

(defun yeah-dead--stand-state (pid)
  "Return the state of the process PID of the stand.
The zombie is `Z' and the living process is `S', and every other pid is
a process that is not there at all.  The host is never asked: the stand
is a table and not a measurement of the host."
  (cond ((eq pid yeah-dead--zombie-pid) "Z")
        ((eq pid yeah-dead--living-pid) "S")
        (t nil)))

(defun yeah-dead--life-socket (directory tag pid)
  "Return the path of the life socket of the owner PID in DIRECTORY.
The name of the socket of the kernel carries the pid of its owner, and
the stand uses the same shape: the sweep and the adoption read the pid
of the owner out of the name of the file."
  (expand-file-name (format "yeah-life-%s-%d.sock" tag pid) directory))

(defun yeah-dead--life-directory ()
  "Return a fresh directory for the sockets of the stand.
The stand writes nothing into the tree of the repository: the sockets
of the stand are files of a directory of its own.  The directory is
private: `make-temp-file' with the flag of a directory gives one."
  (make-temp-file "yeah-dead-life" t))

(defun yeah-dead--processes-named (name)
  "Return the live processes whose name is NAME.
The stand takes a socket and leaves a server behind: the servers it
started are found and stopped again, and the server of the check itself
is not among them."
  (delq nil
        (mapcar (lambda (process)
                  (and (process-live-p process)
                       (equal name (process-name process))
                       process))
                (process-list))))

(defconst yeah-dead--stat-file
  "\"/proc/[^\"]*stat\""
  "The shape of a read of the stat file of a process.")

(defconst yeah-dead--code-extensions
  '("el" "sh" "ts" "mjs" "js")
  "The extensions of the files of the tree that hold code.
The guard of the rule reads these files and the other files of the tree
are left alone.  The reason is named: a document names the rule of the
life of a process and a program defines it, and a guard that reads a
document for a rule of its own cries wolf.")

(defconst yeah-dead--the-rule "lib/yeah-proc.el"
  "The file of the kernel that holds the rule of the life of a process.
The rule lives here and nowhere else, and this file is the one file of
the tree that the guard of the rule allows to decide the life of a
process.")

(defconst yeah-dead--the-stand-of-the-rule
  "tests/checks/check-a-process-that-is-dead-is-dead-everywhere.el"
  "The check that proves the rule of the life of a process.
The check holds the letters of the stand of the rule on purpose: the
stand is a table of the states of the rule, and a table of the letters
that live is not a second rule.  The file is named here and not left to
a guess.")

(defun yeah-dead--root ()
  "Return the root of the repository: the directory that holds `spec.json'."
  (expand-file-name
   (or (locate-dominating-file default-directory "spec.json")
       default-directory)))

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

(defun yeah-dead--code-files (root)
  "Return the files of the tree that hold code, with their names.
The rule of the life of a process must not be spread over the tree: a
second rule in `scripts/' or in `tests/support/' is a second rule as
well, and the guard of the wave 101 looked at two directories only.

The walk is the walk of Emacs (`directory-files-recursively') and not a
walk of our own: a walk of our own calls a function of Elisp for every
file of the tree, the interpreter counts the nesting of every one of
those calls, and a directory of a hundred files is enough to reach the
limit of the nesting."
  (let (files)
    (dolist (extension yeah-dead--code-extensions)
      (dolist (path (directory-files-recursively
                     root (concat "\\." extension "\\'") nil
                     (lambda (directory)
                       (not (string-prefix-p "." (file-name-nondirectory directory))))))
        (push (cons (file-relative-name path root) path) files)))
    (sort files (lambda (one other) (string< (car one) (car other))))))

(defun yeah-dead--code-text (path)
  "Return the code of the file PATH, without its comments.
A comment names the rule of the life of a process, and a comment does
not define it.  The comments of the files of the tree are the lines
that begin with `;;', with `#' and with `//'."
  (with-temp-buffer
    (insert-file-contents path)
    (let (lines)
      (dolist (line (split-string (buffer-string) "\n" t))
        (let ((trimmed (string-trim line)))
          (unless (or (string-prefix-p ";" trimmed)
                      (string-prefix-p "#" trimmed)
                      (string-prefix-p "//" trimmed))
            (push line lines))))
      (mapconcat #'identity (nreverse lines) "\n"))))

(defun yeah-dead--reads-a-process-state (text)
  "Return non-nil when TEXT reads the state of a process.
The state of a process is read through the reader of the kernel
(`yeah-proc-state'), or out of the stat file of the process, or it is
named as the state of a pid."
  (or (string-match-p "yeah-proc-state" text)
      (string-match-p "/proc/[^ \t\n\"']*stat" text)
      (and (string-match-p "\\<state\\>" text)
           (string-match-p "\\<pid\\>" text))))

(defun yeah-dead--holds-the-letters-of-life (text)
  "Return non-nil when TEXT holds the letters that live.
The letters are the letters of the state of a process that runs: `S'
and `R'.  They are written as letters of a string in Elisp, and as the
letters of a pattern of a case in the shell."
  (or (string-match-p "\"S\"" text)
      (string-match-p "\"R\"" text)
      (string-match-p "'S'" text)
      (string-match-p "'R'" text)
      (string-match-p "S|R" text)))

(defun yeah-dead--decides-the-life (text)
  "Return non-nil when TEXT decides the life of a process by itself.
The trait of a second rule is two things in one file: the file reads
the state of a process, and the file holds the letters that live.  A
file that does both decides the life of a process by itself, whatever
its functions are called."
  (and (yeah-dead--reads-a-process-state text)
       (yeah-dead--holds-the-letters-of-life text)))

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
                     (string-match-p "\\<pid\\>\\|\\bprocess" args))
            (push name names)))))
    (nreverse names)))

(let* ((root (yeah-dead--root))
       (files (yeah-dead--code-files root)))
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
        ;; no file defines a second rule of the life of a process by the
        ;; shape of the name of a function
        (dolist (rule (yeah-dead--local-rule text))
          (push (format "the file %s defines the rule %s: the rule of the life of a process is one function of the kernel (%s)"
                        name rule "yeah-proc-alive-p")
                yeah-dead--failures))
        ;; no file of the tree decides the life of a process by itself:
        ;; a file that reads the state of a process and holds the letters
        ;; that live decides the life of a process whatever its functions
        ;; are called.  The two files that are allowed to do that are
        ;; named: the rule of the kernel and the stand of the rule.
        (unless (or (string= name yeah-dead--the-rule)
                    (string= name yeah-dead--the-stand-of-the-rule))
          (when (yeah-dead--decides-the-life (yeah-dead--code-text path))
            (push (format "the file %s decides the life of a process by itself: the rule of the life of a process is one function of the kernel (%s)"
                          name "yeah-proc-alive-p")
                  yeah-dead--failures)))
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
  ;; 5. the kernel asks the rule in both of its places
  ;;
  ;; The stand replaces the reader of the state of the process and nothing
  ;; else: the rule of the kernel is asked for its own verdict, and the
  ;; two places of the kernel are asked with a zombie and with a process
  ;; that runs.
  (let* ((directory (yeah-dead--life-directory))
         (owned yeah-life--owned)
         (servers (yeah-dead--processes-named "yeah-life")))
    (unwind-protect
        (cl-letf (((symbol-function 'yeah-proc-state) #'yeah-dead--stand-state))
          ;; 5a. the sweep takes the socket of a zombie and keeps the
          ;;     socket of a living owner
          (let ((zombie (yeah-dead--life-socket directory "sweep" yeah-dead--zombie-pid))
                (living (yeah-dead--life-socket directory "sweep" yeah-dead--living-pid)))
            (with-temp-file zombie (insert ""))
            (with-temp-file living (insert ""))
            (yeah-life-socket-sweep directory)
            (when (file-exists-p zombie)
              (push (format "the socket %s of a zombie owner was not swept away: a zombie owner is dead, and the socket of a dead owner is taken away"
                            (file-name-nondirectory zombie))
                    yeah-dead--failures))
            (unless (file-exists-p living)
              (push (format "the socket %s of a living owner was swept away: the life of a socket is not worth the risk of killing a living owner"
                            (file-name-nondirectory living))
                    yeah-dead--failures)))
          ;; 5b. the adoption takes the socket of a zombie owner
          (let ((zombie (yeah-dead--life-socket directory "adopt" yeah-dead--zombie-pid))
                (living (yeah-dead--life-socket directory "adopt" yeah-dead--living-pid))
                (result nil))
            (with-temp-file zombie (insert ""))
            (with-temp-file living (insert ""))
            (setq result (yeah-dead--call #'yeah-life-adopt zombie))
            (unless (eq 'ok (car result))
              (push (format "the socket %s of a zombie owner was refused: %S, and a zombie owner is not adopted as if it lived"
                            (file-name-nondirectory zombie) (cdr result))
                    yeah-dead--failures))
            (unless (file-exists-p zombie)
              (push (format "the socket %s of a zombie owner was not taken by the adoption" (file-name-nondirectory zombie))
                    yeah-dead--failures))
            ;; 5c. the adoption refuses the socket of a living owner, and
            ;;     the socket of a living owner is still there
            (setq result (yeah-dead--call #'yeah-life-adopt living))
            (if (eq 'ok (car result))
                (push (format "the socket %s of a living owner was adopted: the life of a socket is not worth the risk of killing a living owner"
                              (file-name-nondirectory living))
                      yeah-dead--failures)
              (unless (string-match-p "belongs to a living process"
                                      (error-message-string (cdr result)))
                (push (format "the socket %s of a living owner was refused with the words %S and not with the words of the rule"
                              (file-name-nondirectory living)
                              (error-message-string (cdr result)))
                      yeah-dead--failures)))
            (unless (file-exists-p living)
              (push (format "the socket %s of a living owner was taken away by the adoption that refused it"
                            (file-name-nondirectory living))
                    yeah-dead--failures))))
      ;; the stand leaves the check as it found it: the socket of the
      ;; check is still owned, and the servers of the stand are stopped
      (setq yeah-life--owned owned)
      (dolist (process (delete-dups (delete servers (yeah-dead--processes-named "yeah-life"))))
        (ignore-errors (delete-process process)))
      (ignore-errors (delete-directory directory t))))
  (dolist (failure yeah-dead--failures)
    (message "dead-process: %s" failure))
  (if yeah-dead--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-process-that-is-dead-is-dead-everywhere.el ends here
