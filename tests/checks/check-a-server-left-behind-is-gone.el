;;; check-a-server-left-behind-is-gone.el --- the server does not outlive its owner -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The defect of 2026-11-18: the gate of the map kills a check that took
;; too long, and the check leaves a server behind.  A server that speaks
;; over stdio has a pipe to read, and the pipe ends when the owner dies.
;; A server that speaks over a socket has no such pipe: it waits for a
;; client that never comes, and when the owner of the check is killed the
;; server stays behind, holds the socket of the service and waits for
;; ever.  The measurement of the defect: the server was alive twelve
;; seconds after the owner of the check was killed, and the file of the
;; socket stayed on disk.
;;
;; This check starts a real service the way the harness starts it --
;; `yeah-service-start' in a process of its own -- waits until the
;; service really serves (its socket is on disk), kills the owner with
;; the signal the gate uses (SIGKILL: the owner gets no chance to clean
;; up) and proves that the server of the service is gone within ten
;; seconds.
;;
;; The check measures the subject the way the defect was measured: the
;; process of the server, by its pid, in the tree of the processes of the
;; system.  It does not ask the server whether it is alive: a server that
;; answers is a server that lives.  The state of the process decides it:
;; `S' and `R' are a process that runs, and `Z' is a zombie -- a process
;; that has died already and waits to be reaped, it burns no CPU and it
;; holds no client.  The rule is the one of the kernel
;; (`lib/yeah-proc.el'), and the tree of the processes cannot answer the
;; question: the directory of a zombie is there as well.
;;
;; The control of the claim takes out the watch of the server: the server
;; stops looking at the life of its owner, and the check then fails by
;; its own assertion -- the server is still alive ten seconds after its
;; owner was killed.  That is the defect, brought back by one line.
;;
;; No network is involved: the model of the service is a fake that never
;; answers, and the socket is a file in the private directory of the
;; runtime.
;;
;; Exit codes: 0 -- the server went with its owner; 1 -- it stayed behind.

;;; Code:

(require 'cl-lib)
(require 'yeah-proc)
(require 'yeah-service)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--emacs ()
  "Return the Emacs program that runs the owner of the service.
The owner runs the same Emacs as this one: the running binary when the
platform can name it, so the check works where `emacs' is not on PATH."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-check--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-service") "yeah-service.el")))

(defun yeah-check--owner-command (name data-home pid-file)
  "Return the argv of the owner of the service NAME.
The owner starts the service with DATA-HOME, writes the pid of the
service into PID-FILE and waits: the owner is the process that a gate
kills, and the service is the thing that must not stay behind."
  (list (yeah-check--emacs) "-Q" "--batch"
        "-L" (yeah-check--lib-directory)
        "-l" "yeah-service"
        "--eval"
        (format (concat "(progn "
                        "(defun yeah-check--transport (prompt callback) nil) "
                        "(let ((process (yeah-service-start %S nil %S "
                        "\"#'yeah-check--transport\" t nil))) "
                        "(with-temp-file %S "
                        "(insert (number-to-string (process-id process)))) "
                        "(while t (accept-process-output nil 0.2))))")
                name data-home pid-file)))

(defun yeah-check--read-pid (file)
  "Return the pid in FILE, or nil when the file holds no pid."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (let ((text (string-trim (buffer-string))))
        (and (string-match-p "\\`[0-9]+\\'" text)
             (string-to-number text))))))

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
   (lambda () (not (yeah-proc-alive-p (yeah-proc-state pid))))
   timeout))

(defun yeah-check--kill (pid)
  "Kill the process PID with the signal the gate uses.
SIGKILL gives the process no chance to clean up: that is the case the
defect is about.  Return non-nil when the signal was sent."
  (condition-case nil
      (signal-process pid 'KILL)
    (error nil)))

(let* ((name (format "orphan-%d" (random 1000000)))
       (data-home (make-temp-file "yeah-orphan" t))
       (pid-file (expand-file-name "service.pid" data-home))
       (socket (yeah-service-socket-path name))
       (owner nil)
       (service nil))
  (unwind-protect
      (progn
        (unless (file-directory-p "/proc")
          (push "the check cannot measure a process without /proc"
                yeah-check--failures))
        (when (null yeah-check--failures)
          (setq owner
                (make-process
                 :name "yeah-orphan-owner"
                 :command (yeah-check--owner-command name data-home pid-file)
                 :connection-type 'pipe
                 :noquery t
                 :filter (lambda (_process _chunk) nil)))
          ;; the owner starts the service and tells the pid of it
          (setq service
                (yeah-check--await
                 (lambda () (yeah-check--read-pid pid-file))
                 30))
          (unless service
            (push "the owner never started the service" yeah-check--failures))
          (when service
            ;; the service really serves: its socket is on disk
            (unless (yeah-check--await (lambda () (file-exists-p socket)) 20)
              (push (format "the service never bound its socket: %s" socket)
                    yeah-check--failures))
            ;; and the process of the service is alive
            (unless (yeah-proc-alive-p (yeah-proc-state service))
              (push (format "the service was not alive before its owner was killed (pid %d)"
                            service)
                    yeah-check--failures))
            ;; the gate kills the owner of the service
            (unless (yeah-check--kill (process-id owner))
              (push "the owner of the service could not be killed"
                    yeah-check--failures))
            ;; and the server of the service must go with it
            (unless (yeah-check--await-dead service 10)
              (push (format "the server of the service stayed behind after its owner was killed (pid %d)"
                            service)
                    yeah-check--failures))
            ;; and the socket of the service must not stay on disk
            (unless (yeah-check--await (lambda () (not (file-exists-p socket))) 10)
              (push (format "the socket of the service stayed behind: %s" socket)
                    yeah-check--failures)))))
    ;; the check leaves nothing behind
    (when (and service (yeah-proc-alive-p (yeah-proc-state service)))
      (yeah-check--kill service))
    (when (and owner (process-live-p owner))
      (yeah-check--kill (process-id owner)))
    (when (file-exists-p socket)
      (ignore-errors (delete-file socket)))
    (ignore-errors (delete-directory data-home t)))
  (dolist (failure yeah-check--failures)
    (message "orphan: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-server-left-behind-is-gone.el ends here
