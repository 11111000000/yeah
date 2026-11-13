;;; yeah-service.el --- a service Emacs running the Yeah harness -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The primary placement: a dedicated Emacs process runs the harness, so
;; the editing Emacs never shares a thread with a long turn.  This module
;; starts such a service, connects to it and stops it.  The service
;; serves ACP on a local socket (`yeah-acp-serve-socket'), where a cancel
;; is handled while a prompt is still running.

;;; Code:

(require 'cl-lib)
(require 'yeah-wire-socket)

(defgroup yeah-service nil
  "A service Emacs running the Yeah harness."
  :group 'yeah)

(defcustom yeah-service-emacs
  (or (executable-find "emacs")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))
      invocation-name)
  "The Emacs program that runs the service."
  :type 'string
  :group 'yeah-service)

(defvar yeah-service--processes (make-hash-table :test 'equal)
  "Map a service name to its process.")

(defun yeah-service--socket-directory ()
  "Return the user-private directory the service sockets live in.
Anyone who can connect to the socket drives the agent with the person's
permissions, so the socket never sits in a world-writable /tmp: it goes
under XDG_RUNTIME_DIR when there is one, else under a directory of this
user with mode 0700."
  (let ((dir (if-let ((runtime (getenv "XDG_RUNTIME_DIR")))
                 (expand-file-name "yeah" runtime)
               (expand-file-name (format "yeah-%d" (user-uid))
                                 (or (getenv "TMPDIR") "/tmp")))))
    (unless (file-directory-p dir)
      (make-directory dir t)
      (set-file-modes dir #o700))
    dir))

;;;###autoload
(defun yeah-service-socket-path (name)
  "Return the socket path of the service NAME."
  (expand-file-name (format "yeah-service-%s.sock" name)
                    (yeah-service--socket-directory)))

(defun yeah-service--socket-path (name)
  "Return the socket path of the service NAME."
  (yeah-service-socket-path name))

(defun yeah-service--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))

(defun yeah-service--rules-eval (rules)
  "Return the Elisp that installs RULES in the service.
RULES is a list of permission rule plists, as `yeah-perm-rule-make'
builds them; the service adds each of them to its own ruleset."
  (if (null rules)
      ""
    (format "(dolist (rule '%S) (yeah-perm-rules-add rule))" rules)))

;;;###autoload
(defun yeah-service-start (name &optional extra-eval data-home transport clean rules)
  "Start a service Emacs named NAME and return its process.
The service serves ACP on a local socket.  EXTRA-EVAL is evaluated in the
service before the server starts (to configure the model backend);
DATA-HOME is the service's data directory; TRANSPORT is a form evaluating
to the model transport of the service (nil uses the default).  A service
with the same name is not started twice.
CLEAN (the default) starts the service without the user's init; nil lets
the service inherit the user's configuration, including the gptel backend.
RULES is a list of permission rule plists: the standing permissions the
person grants the service, which is how a headless service may edit at
all."
  (let ((existing (gethash name yeah-service--processes)))
    (when (and existing (process-live-p existing))
      (signal 'user-error
              (list (format "yeah-service-start: %S is already running" name)))))
  (let* ((socket (yeah-service--socket-path name))
         (buffer (generate-new-buffer (format " *yeah service %s*" name)))
         (process
          (make-process
           :name (format "yeah-service-%s" name)
           :buffer buffer
           :command
           (append (list yeah-service-emacs)
                   (if clean (list "-Q" "--batch") (list "--batch"))
                   (list "-L" (yeah-service--lib-directory)
                         "-l" "yeah-acp"
                         "--eval"
                         (format "(progn %s %s %s (yeah-acp-serve-socket %S %s))"
                                 (or extra-eval "")
                                 (if data-home
                                     (format "(setq yeah-data-home %S)" data-home)
                                   "")
                                 (yeah-service--rules-eval rules)
                                 socket
                                 (or transport "yeah-acp-default-transport"))))
           :connection-type 'pipe
           :noquery t)))
    (puthash name process yeah-service--processes)
    process))

;;;###autoload
(defun yeah-service-connect (name &optional timeout)
  "Connect to the service NAME and return the connection process.
Waits up to TIMEOUT seconds (default 10) for the socket to appear."
  (let ((socket (yeah-service-socket-path-internal name))
        (deadline (+ (float-time) (or timeout 10)))
        (connection nil))
    (while (and (null connection) (< (float-time) deadline))
      (setq connection
            (condition-case nil
                (make-network-process
                 :name (format "yeah-service-client-%s" name)
                 :family 'local
                 :service socket
                 :noquery t)
              (file-missing nil)))
      (unless connection
        (accept-process-output nil 0.05)))
    connection))

(defun yeah-service-socket-path-internal (name)
  "Return the socket path of the service NAME."
  (yeah-service--socket-path name))

;;;###autoload
(defun yeah-service-stop (name)
  "Stop the service NAME and remove its socket."
  (when-let ((process (gethash name yeah-service--processes)))
    (when (process-live-p process)
      (delete-process process))
    (remhash name yeah-service--processes))
  (let ((socket (yeah-service--socket-path name)))
    (when (file-exists-p socket)
      (ignore-errors (delete-file socket))))
  t)

(provide 'yeah-service)
;;; yeah-service.el ends here
