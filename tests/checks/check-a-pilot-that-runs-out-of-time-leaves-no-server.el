;;; check-a-pilot-that-runs-out-of-time-leaves-no-server.el --- a pilot that ran out of time leaves no server -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A live pilot ends in one of three ways: the work is done, the person
;; stops it, or the limit of its time passes.  The check
;; check-a-pilot-that-is-interrupted-leaves-no-server.el covers the
;; second way; this check covers the third.
;;
;; The limit of the pilot is the promise of the runner: the pilot is
;; stopped when the limit passes, the servers of the pilot go with it,
;; and the runner answers the third answer (unknown) and not a refutation.
;; The third answer is the answer of a method that could not tell: the
;; pilot did not fail, the limit of its time came, and nobody knows what
;; the pilot would have said.
;;
;; The check starts a real pilot through `scripts/live-pilot' with a
;; limit of ten seconds -- the fixture of the pilot waits for ever, so
;; the limit is what ends it -- and then proves three things: the pilot
;; reported a living server, the server is dead within fifteen seconds
;; of the limit, and the runner answered 3.
;;
;; The check measures the subject the way the defect was measured: the
;; process of the server, by its pid, in the tree of the processes of the
;; system.  It does not ask the server whether it is alive: a server that
;; answers is a server that lives.
;;
;; "Dead" is read from the STATE of the process, not from the clock.
;; The state of a process in its stat file is the letter that follows
;; the name of the process: `S' and `R' for a process that runs,
;; and `Z' for a zombie -- a process that has already died and waits to
;; be reaped.  A zombie burns no CPU, answers nobody and holds no
;; client: the server of the pilot is gone the moment it becomes one.
;; The reaping itself is not the subject of this claim -- it is the
;; business of the init of the host -- and waiting for it in seconds of
;; wall time made the check depend on the speed of the host: on the
;; night of 2026-11-19, under a host that was swapping, the check
;; waited fifteen seconds for the reaping of a process that had died
;; at once, and it refuted a claim that holds.  The repair of wave 75
;; measures the death of the server, and the wall time is only the
;; bound of the wait, not the measure of the subject.
;;
;; The control of the claim takes the limit away from the runner: the
;; runner waits for the pilot for ever, and the check then fails by its
;; own assertion -- the runner did not answer the third answer.  That is
;; the defect, brought back by one line.
;;
;; No network is involved: the model of the server is a fake that never
;; answers, and the socket is a file in a private temporary directory.
;;
;; Exit codes: 0 -- the server of the pilot went with the limit;
;; 1 -- it stayed behind, or the runner answered something else.

;;; Code:

(require 'cl-lib)

;; The reader of the state of a process is the one of the support: the
;; process of the server dies while the check reads it, and a reader that
;; dies on the filesystem does not decide on its own assertion.
(load (expand-file-name "tests/support/yeah-proc.el") nil t)

(defvar yeah-limit--failures nil
  "The failures this check found.")

(defun yeah-limit--alive-p (pid)
  "Return non-nil when the process PID is alive.
A zombie is not alive: it has died already and waits to be reaped, it
burns no CPU and answers nobody.  The answer comes from the state of
the process, so it does not depend on the speed of the host."
  (and pid (integerp pid) (> pid 0)
       (let ((state (yeah-proc--state pid)))
         (and state (not (string= state "Z"))))))

(defun yeah-limit--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (< (float-time) deadline) (not (funcall predicate)))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-limit--await-dead (pid timeout)
  "Return non-nil when the process PID is gone, at most TIMEOUT seconds."
  (yeah-limit--await (lambda () (not (yeah-limit--alive-p pid))) timeout))

(defun yeah-limit--kill (pid)
  "Kill the process PID with SIGKILL and return non-nil when the signal was sent."
  (and pid (integerp pid) (> pid 0)
       (condition-case nil
           (progn (signal-process pid 'KILL) t)
         (error nil))))

(defun yeah-limit--emacs ()
  "Return the Emacs program that runs the pilot of this check.
The path must mean the same thing in another process: the directory the
Emacs of this check was started from holds the program itself, and the
reader is the runner, not the Emacs.  The path of the binary is read
once and is a name by itself."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (let ((self (expand-file-name "emacs" invocation-directory)))
        (and (file-executable-p self) self))
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-limit--read-report (path)
  "Return the fields of the report in PATH as a plist, or nil.
The report holds one `key=value' line per field: the pid of the pilot,
the pid of the server and the path of the socket of the server."
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
       (runner-bin (expand-file-name "scripts/live-pilot" root))
       (fixture (expand-file-name "tests/support/yeah-pilot-fixture.el" root))
       (report (make-temp-file "yeah-limit-report"))
       (runner
        (let ((process-environment
               (cons (format "YEAH_PILOT_FIXTURE_REPORT=%s" report)
                     process-environment)))
          (make-process
           :name "yeah-limit-runner"
           :command (list "bash" runner-bin "--limit" "10" "--"
                          (yeah-limit--emacs) "-Q" "--batch"
                          "-L" (expand-file-name "lib" root)
                          "-l" fixture)
           :connection-type 'pipe
           :noquery t
           :filter (lambda (_process chunk)
                     (with-current-buffer (get-buffer-create " *yeah limit*")
                       (goto-char (point-max))
                       (insert chunk))))))
       (runner-pid (and runner (process-id runner)))
       (fields nil)
       (pilot 0)
       (server 0)
       (socket nil))
  (unwind-protect
      (progn
        (unless (file-directory-p "/proc")
          (push "the check cannot measure a process without /proc"
                yeah-limit--failures))
        (when (null yeah-limit--failures)
          ;; the pilot reports the server it started
          (setq fields (yeah-limit--await (lambda () (yeah-limit--read-report report)) 30))
          (unless fields
            (push "the pilot never reported the server it started"
                  yeah-limit--failures))
          (when fields
            (setq pilot (string-to-number (or (cdr (assq 'pilot fields)) ""))
                  server (string-to-number (or (cdr (assq 'server fields)) ""))
                  socket (cdr (assq 'socket fields)))
            (unless (and (> pilot 0) (> server 0) socket)
              (push (format "the report of the pilot is not readable: %S" fields)
                    yeah-limit--failures))
            (when (and (> pilot 0) (> server 0) socket)
              ;; the server serves while the pilot lives
              (unless (yeah-limit--alive-p server)
                (push (format "the server of the pilot was not alive (pid %d)" server)
                      yeah-limit--failures))
              ;; the limit of the pilot passes, and the pilot ends
              (unless (yeah-limit--await-dead runner-pid 30)
                (push (format "the runner of the pilot did not stop when the limit passed (pid %d)"
                              runner-pid)
                      yeah-limit--failures))
              ;; the runner answers the third answer: the method could not tell
              (let ((status (and runner (process-exit-status runner))))
                (unless (and status (= status 3))
                  (push (format "the runner of the pilot answered %s when the limit passed, the third answer is 3"
                                (or status "nothing"))
                        yeah-limit--failures)))
              ;; and the server of the pilot must go with the pilot: the
              ;; state of the process is the measure, and the seconds of
              ;; the wall clock are only the bound of the wait
              (unless (yeah-limit--await-dead server 15)
                (push (format "the server of the pilot was still alive fifteen seconds after the limit passed (pid %d, state %S)"
                              server
                              (or (yeah-proc--state server) "gone"))
                      yeah-limit--failures))))))
    ;; the check leaves nothing behind
    (yeah-limit--kill server)
    (yeah-limit--kill pilot)
    (yeah-limit--kill runner-pid)
    (ignore-errors (delete-file report))
    (when (and socket (file-exists-p socket))
      (ignore-errors (delete-file socket)))
    (when (and socket (file-directory-p (file-name-directory socket)))
      (ignore-errors (delete-directory (file-name-directory socket) t))))
  (dolist (failure yeah-limit--failures)
    (message "limit: %s" failure))
  (when yeah-limit--failures
    (with-current-buffer (get-buffer-create " *yeah limit*")
      (message "limit output:\n%s" (buffer-string))))
  (if yeah-limit--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-pilot-that-runs-out-of-time-leaves-no-server.el ends here
