;;; check-a-check-that-is-killed-leaves-no-server.el --- the gate leaves no server behind -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The gate of the map kills a check that took too long.  The check dies,
;; and the servers it started must die with it: a server that outlives
;; its owner holds the socket it serves on and waits for a client that
;; never comes.  The measurement of the defect of 2026-11-18: the server
;; of a killed check was alive ten seconds after the check was killed,
;; and the file of its socket stayed on disk.
;;
;; This check starts a real check -- the fixture that starts a server and
;; waits for ever -- through `scripts/dev check', which is the way the
;; gate starts a check, kills the owner of that server the way the gate
;; kills it (SIGKILL: the owner gets no chance to clean up), and then
;; proves two things: the server is gone within ten seconds, and the
;; socket of the server is gone with it.
;;
;; The check measures the subject the way the defect was measured: the
;; process of the server, by its pid, in `/proc'.  It does not ask the
;; server whether it is alive: a server that answers is a server that
;; lives.
;;
;; The control of the claim takes the watch of the server out: the server
;; stops looking at the life of its owner, and the check then fails by
;; its own assertion -- the server is still alive ten seconds after the
;; owner was killed.  That is the defect, brought back by one line.
;;
;; No network is involved: the model of the server is a fake that never
;; answers, and the socket is a file in a private temporary directory.
;;
;; Exit codes: 0 -- the server of the check went with the check;
;; 1 -- it stayed behind.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--alive-p (pid)
  "Return non-nil when the process PID is alive."
  (and pid (integerp pid) (> pid 0)
       (file-directory-p (format "/proc/%d" pid))))

(defun yeah-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (< (float-time) deadline) (not (funcall predicate)))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-check--await-dead (pid timeout)
  "Return non-nil when the process PID is gone, at most TIMEOUT seconds."
  (yeah-check--await (lambda () (not (yeah-check--alive-p pid))) timeout))

(defun yeah-check--kill (pid)
  "Kill the process PID with the signal the gate uses.
SIGKILL gives the process no chance to clean up: that is the case the
defect is about.  Return non-nil when the signal was sent."
  (condition-case nil
      (signal-process pid 'KILL)
    (error nil)))

(defun yeah-check--read-report (path)
  "Return the fields of the report in PATH as a plist, or nil.
The report holds one `key=value' line per field: the pid of the owner,
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
       (fixture (expand-file-name "tests/support/yeah-check-server-fixture.el" root))
       (dev (expand-file-name "scripts/dev" root))
       (report (make-temp-file "yeah-gate-report"))
       (gate
        (let ((process-environment
               (cons (format "YEAH_CHECK_FIXTURE_REPORT=%s" report)
                     process-environment)))
          (make-process
           :name "yeah-gate"
           :command (list "bash" dev "check" fixture)
           :connection-type 'pipe
           :noquery t
           :filter (lambda (_process chunk)
                     (with-current-buffer (get-buffer-create " *yeah gate*")
                       (goto-char (point-max))
                       (insert chunk))))))
       (fields nil)
       (owner 0)
       (server 0))
  (unwind-protect
      (progn
        (unless (file-directory-p "/proc")
          (push "the check cannot measure a process without /proc"
                yeah-check--failures))
        (when (null yeah-check--failures)
          ;; the fixture reports the server it started
          (setq fields (yeah-check--await (lambda () (yeah-check--read-report report)) 60))
          (unless fields
            (push "the fixture never reported the server it started"
                  yeah-check--failures))
          (when fields
            (let ((socket (cdr (assq 'socket fields))))
              (setq owner (string-to-number (or (cdr (assq 'pid fields)) ""))
                    server (string-to-number (or (cdr (assq 'server fields)) "")))
              (unless (and owner (> owner 0) server (> server 0) socket)
                (push (format "the report of the fixture is not readable: %S" fields)
                      yeah-check--failures))
              (when (and owner (> owner 0) server (> server 0) socket)
                ;; the server of the fixture serves while its owner lives
                (unless (yeah-check--alive-p server)
                  (push (format "the server of the check was not alive (pid %d)" server)
                        yeah-check--failures))
                ;; the gate kills the owner of the server
                (unless (yeah-check--kill owner)
                  (push "the owner of the server could not be killed"
                        yeah-check--failures))
                ;; and the server of the check must go with it
                (unless (yeah-check--await-dead server 10)
                  (push (format "the server of the check stayed behind after its owner was killed (pid %d)"
                                server)
                        yeah-check--failures))
                ;; and the socket of the server must not stay on disk
                (unless (yeah-check--await (lambda () (not (file-exists-p socket))) 10)
                  (push (format "the socket of the server stayed behind: %s" socket)
                        yeah-check--failures)))))))
    ;; the check leaves nothing behind: the gate, the owner of the server
    ;; and the server itself
    (yeah-check--kill (and gate (process-id gate)))
    (yeah-check--kill owner)
    (yeah-check--kill server)
    (ignore-errors (delete-file report)))
  (dolist (failure yeah-check--failures)
    (message "gate: %s" failure))
  (when yeah-check--failures
    (with-current-buffer (get-buffer-create " *yeah gate*")
      (message "gate output:\n%s" (buffer-string))))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-check-that-is-killed-leaves-no-server.el ends here
