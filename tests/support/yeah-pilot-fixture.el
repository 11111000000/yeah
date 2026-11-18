;;; yeah-pilot-fixture.el --- a pilot that starts a server and waits -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A pilot is a live run of Yeah against a real provider: it starts an
;; Emacs, and the Emacs starts the servers of the session.  The defect
;; of 2026-11-18: the server of the pilot of the self-development run
;; was orphaned when the pilot was interrupted, and it held the socket it
;; served on and waited for a client that never came.
;;
;; This fixture is that pilot: it starts a real ACP server on a local
;; socket, reports what it started, and then waits for ever -- the way a
;; pilot waits for the model.  The check that watches the runner
;; (check-a-pilot-that-is-interrupted-leaves-no-server.el) interrupts
;; the pilot through the runner that owns it, and then watches what the
;; server does.
;;
;; The server of this fixture watches no life socket on purpose.  A
;; server that watches the life of its owner ends by itself, and that
;; is the claim of wave 55; the claim of this wave is about the runner,
;; and the runner is the only thing that can stop this server.  The life
;; socket is taken out of the environment of the server for that reason:
;; the server of this fixture is the hard case, and a check that passes
;; on the easy case proves nothing.
;;
;; The fixture is not a check of the gate: it never ends by itself, so
;; the gate must not run it as a check of its own.

;;; Code:

(require 'cl-lib)
(require 'yeah-acp)

(defun yeah-pilot--emacs ()
  "Return the Emacs program that runs the server of the fixture."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-pilot--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))

(defun yeah-pilot--report (text)
  "Write TEXT into the report file that the owner of the fixture named."
  (let ((path (getenv "YEAH_PILOT_FIXTURE_REPORT")))
    (when path
      (with-temp-file path (insert text)))))

(let* ((data-home (make-temp-file "yeah-pilot" t))
       (socket (expand-file-name "server.sock" data-home))
       (server
        (let ((process-environment
               ;; The server of this fixture watches no life socket: the
               ;; runner that owns the tree is the only thing that can
               ;; stop it.
               (cl-remove-if
                (lambda (entry) (string-prefix-p "YEAH_LIFE_SOCKET=" entry))
                process-environment)))
          (make-process
           :name "yeah-pilot-server"
           :command
           (list (yeah-pilot--emacs) "-Q" "--batch"
                 "-L" (yeah-pilot--lib-directory)
                 "-l" "yeah-acp"
                 "--eval"
                 (format (concat "(progn (setq yeah-data-home %S) "
                                 "(defun yeah-pilot-transport (prompt callback) nil) "
                                 "(yeah-acp-serve-socket %S #'yeah-pilot-transport))")
                         data-home socket))
           :connection-type 'pipe
           :noquery t
           :filter (lambda (_process _chunk) nil))))
       (deadline (+ (float-time) 20)))
  ;; The server is ready when it binds its socket.
  (while (and (not (file-exists-p socket)) (< (float-time) deadline))
    (accept-process-output nil 0.05))
  (yeah-pilot--report
   (format "pilot=%d\nserver=%d\nsocket=%s\n"
           (emacs-pid) (process-id server) socket))
  ;; The fixture waits for ever: it is the pilot that is interrupted.
  (while t (accept-process-output nil 0.5)))

;;; yeah-pilot-fixture.el ends here
