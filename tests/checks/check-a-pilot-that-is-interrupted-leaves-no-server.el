;;; check-a-pilot-that-is-interrupted-leaves-no-server.el --- an interrupted pilot leaves no server -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A live pilot is a long run of Yeah against a real provider.  It ends in
;; one of three ways: the work is done, the person stops it, or the limit
;; of its time passes.  In every one of the three cases the servers of the
;; pilot must go with it.  The measurement of the defect of 2026-11-18: the
;; server of the pilot of the self-development run was orphaned when the
;; pilot was interrupted, and it spun for three and a half hours, waiting
;; for a client that never came.
;;
;; This check starts a real pilot through `scripts/live-pilot' -- the
;; runner that owns the tree of the pilot -- interrupts the runner the way
;; a person interrupts it (SIGINT), and then proves three things: the
;; runner stopped, the runner answered the interruption as an interruption
;; (130), and the server of the pilot is gone within fifteen seconds of
;; the interruption.
;;
;; The check measures the subject the way the defect was measured: the
;; process of the server, by its pid, in `/proc'.  It does not ask the
;; server whether it is alive: a server that answers is a server that
;; lives.
;;
;; The file of the socket of the server is not a claim of this check: a
;; server that is killed by a signal does not run the clean-up that
;; removes the file, and the code removes a stale socket before it binds
;; the next one (lib/yeah-wire-socket.el).  The claim of the file of the
;; socket belongs to the wave that ends a server by itself.
;;
;; The control of the claim takes the stopping away from the runner: the
;; runner stops neither the tree of the pilot nor the group of the pilot,
;; and the check then fails by its own assertion -- the server of the
;; pilot is still alive after the interruption.  That is the defect,
;; brought back by two lines.
;;
;; No network is involved: the model of the server is a fake that never
;; answers, and the socket is a file in a private temporary directory.
;;
;; Exit codes: 0 -- the server of the pilot went with the pilot;
;; 1 -- it stayed behind.

;;; Code:

(require 'cl-lib)

(defvar yeah-pilot--failures nil
  "The failures this check found.")

(defun yeah-pilot--alive-p (pid)
  "Return non-nil when the process PID is alive."
  (and pid (integerp pid) (> pid 0)
       (file-directory-p (format "/proc/%d" pid))))

(defun yeah-pilot--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (< (float-time) deadline) (not (funcall predicate)))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-pilot--await-dead (pid timeout)
  "Return non-nil when the process PID is gone, at most TIMEOUT seconds."
  (yeah-pilot--await (lambda () (not (yeah-pilot--alive-p pid))) timeout))

(defun yeah-pilot--kill (pid)
  "Kill the process PID with SIGKILL and return non-nil when the signal was sent."
  (and pid (integerp pid) (> pid 0)
       (condition-case nil
           (progn (signal-process pid 'KILL) t)
         (error nil))))

(defun yeah-pilot--interrupt (pid)
  "Interrupt the process PID with SIGINT and return non-nil when the signal was sent."
  (and pid (integerp pid) (> pid 0)
       (condition-case nil
           (progn (signal-process pid 'INT) t)
         (error nil))))

(defun yeah-pilot--emacs ()
  "Return the Emacs program that runs the pilot of this check.
The path must mean the same thing in another process: `/proc/self/exe'
is the reader of it, and the reader is the runner, not the Emacs.  The
path of the binary is read once and is a name by itself."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (let ((self (car (file-attributes "/proc/self/exe"))))
        (and (stringp self) (file-executable-p self) self))
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-pilot--read-report (path)
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
       (report (make-temp-file "yeah-pilot-report"))
       (runner
        (let ((process-environment
               (cons (format "YEAH_PILOT_FIXTURE_REPORT=%s" report)
                     process-environment)))
          (make-process
           :name "yeah-pilot-runner"
           :command (list "bash" runner-bin "--limit" "120" "--"
                          (yeah-pilot--emacs) "-Q" "--batch"
                          "-L" (expand-file-name "lib" root)
                          "-l" fixture)
           :connection-type 'pipe
           :noquery t
           :filter (lambda (_process chunk)
                     (with-current-buffer (get-buffer-create " *yeah pilot*")
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
                yeah-pilot--failures))
        (when (null yeah-pilot--failures)
          ;; the pilot reports the server it started
          (setq fields (yeah-pilot--await (lambda () (yeah-pilot--read-report report)) 60))
          (unless fields
            (push "the pilot never reported the server it started"
                  yeah-pilot--failures))
          (when fields
            (setq pilot (string-to-number (or (cdr (assq 'pilot fields)) ""))
                  server (string-to-number (or (cdr (assq 'server fields)) ""))
                  socket (cdr (assq 'socket fields)))
            (unless (and (> pilot 0) (> server 0) socket)
              (push (format "the report of the pilot is not readable: %S" fields)
                    yeah-pilot--failures))
            (when (and (> pilot 0) (> server 0) socket)
              ;; the server serves while the pilot lives
              (unless (yeah-pilot--alive-p server)
                (push (format "the server of the pilot was not alive (pid %d)" server)
                      yeah-pilot--failures))
              ;; the person stops the pilot
              (unless (yeah-pilot--interrupt runner-pid)
                (push "the runner of the pilot could not be interrupted"
                      yeah-pilot--failures))
              ;; the runner must stop
              (unless (yeah-pilot--await-dead runner-pid 30)
                (push (format "the runner of the pilot did not stop after the interruption (pid %d)"
                              runner-pid)
                      yeah-pilot--failures))
              ;; and it must answer the interruption as an interruption
              (let ((status (and runner (process-exit-status runner))))
                (unless (and status (= status 130))
                  (push (format "the runner of the pilot answered %s to the interruption, the answer of an interruption is 130"
                                (or status "nothing"))
                        yeah-pilot--failures)))
              ;; and the server of the pilot must go with the pilot
              (unless (yeah-pilot--await-dead server 15)
                (push (format "the server of the pilot stayed behind after the pilot was interrupted (pid %d)"
                              server)
                      yeah-pilot--failures))))))
    ;; the check leaves nothing behind
    (yeah-pilot--kill server)
    (yeah-pilot--kill pilot)
    (yeah-pilot--kill runner-pid)
    (ignore-errors (delete-file report))
    (when (and socket (file-exists-p socket))
      (ignore-errors (delete-file socket)))
    (when (and socket (file-directory-p (file-name-directory socket)))
      (ignore-errors (delete-directory (file-name-directory socket) t))))
  (dolist (failure yeah-pilot--failures)
    (message "pilot: %s" failure))
  (when yeah-pilot--failures
    (with-current-buffer (get-buffer-create " *yeah pilot*")
      (message "pilot output:\n%s" (buffer-string))))
  (if yeah-pilot--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-pilot-that-is-interrupted-leaves-no-server.el ends here
