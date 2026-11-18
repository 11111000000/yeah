;;; yeah-check-server-fixture.el --- a check that starts a server and waits -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The gate of the map kills a check that took too long, and the check
;; leaves a server behind.  This fixture is that server: it starts a real
;; ACP server on a local socket, reports what it started, and then waits
;; for ever.  The check that watches the gate
;; (check-a-check-that-is-killed-leaves-no-server.el) kills the owner of
;; the server the way the gate kills it, and then watches what the server
;; does.
;;
;; The fixture is not a check of the gate: it never ends by itself, so the
;; gate must not run it as a check of its own.

;;; Code:

(require 'yeah-acp)

(defun yeah-check-fixture--emacs ()
  "Return the Emacs program that runs the server of the fixture."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-check-fixture--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))

(defun yeah-check-fixture--report (text)
  "Write TEXT into the report file that the owner of the fixture named."
  (let ((path (getenv "YEAH_CHECK_FIXTURE_REPORT")))
    (when path
      (with-temp-file path (insert text)))))

(let* ((data-home (make-temp-file "yeah-fixture" t))
       (socket (expand-file-name "server.sock" data-home))
       (server
        (make-process
         :name "yeah-fixture-server"
         :command
         (list (yeah-check-fixture--emacs) "-Q" "--batch"
               "-L" (yeah-check-fixture--lib-directory)
               "-l" "yeah-acp"
               "--eval"
               (format (concat "(progn (setq yeah-data-home %S) "
                               "(defun yeah-fixture-transport (prompt callback) nil) "
                               "(yeah-acp-serve-socket %S #'yeah-fixture-transport))")
                       data-home socket))
         :connection-type 'pipe
         :noquery t
         :filter (lambda (_process _chunk) nil)))
       (deadline (+ (float-time) 20)))
  ;; The server is ready when it binds its socket: it watches the life of
  ;; its owner before it binds, so a socket on disk means the watch is on.
  (while (and (not (file-exists-p socket)) (< (float-time) deadline))
    (accept-process-output nil 0.05))
  (yeah-check-fixture--report
   (format "pid=%d\nserver=%d\nsocket=%s\n"
           (emacs-pid) (process-id server) socket))
  ;; The fixture waits for ever: it is the check that kills it.
  (while t (accept-process-output nil 0.5)))

;;; yeah-check-server-fixture.el ends here
