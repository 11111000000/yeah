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
;; serves ACP on a Unix-domain socket, or on a loopback TCP port when the
;; platform has no Unix socket; a cancel is handled while a prompt is still
;; running.
;;
;; The service runs the same Emacs as the person: the program is resolved
;; when the service starts, and the running binary is the fallback, so a
;; service starts on a machine where `emacs' is not on PATH.

;;; Code:

(require 'cl-lib)
(require 'yeah-client)
(require 'yeah-life)
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

(defun yeah-service--emacs-program ()
  "Return the program that runs the service Emacs.

The service runs the SAME Emacs as the person: the binary that is
running now, when the platform can name it.  A program name that the
PATH does not carry would make the service impossible to start on a
machine where Emacs lives in a profile, so the running binary is the
fallback, and `EMACS' comes before it."
  (let ((configured (or yeah-service-emacs "emacs")))
    (cond
     ((or (file-name-absolute-p configured)
          (file-directory-p configured))
      configured)
     ((executable-find configured) (executable-find configured))
     ((and (getenv "EMACS") (file-executable-p (getenv "EMACS")))
      (getenv "EMACS"))
     ((file-executable-p "/proc/self/exe") "/proc/self/exe")
     ((file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
      (expand-file-name "~/.nix-profile/bin/emacs"))
     (t configured))))

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

(defun yeah-service--reserve-loopback-port ()
  "Return an unused loopback TCP port.
The probe binds the port briefly so the service child can bind the same
port without choosing a fixed, commonly occupied number."
  (let ((probe
         (make-network-process
          :name (format "yeah-service-port-%d" (random 1000000000))
          :server t
          :family 'ipv4
          :service 0
          :noquery t)))
    (unwind-protect
        (let ((port (process-contact probe :service)))
          (unless (and (integerp port) (> port 0) (<= port 65535))
            (signal 'user-error
                    (list "yeah-service-start: could not reserve a TCP port")))
          port)
      (when (process-live-p probe)
        (delete-process probe)))))

(defun yeah-service--write-port-file (socket port)
  "Publish PORT for SOCKET in the port file next to its socket path.
The file contains the port number only; it is not a credential."
  (let ((file (yeah-client-port-file socket)))
    (with-temp-file file
      (insert (number-to-string port)))
    (set-file-modes file #o600)
    file))

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
The service serves ACP on a Unix-domain socket, or on a loopback TCP port
when `yeah-client-network-family' selects `ipv4'.  In the TCP case the port
number is published in a `.port' file next to the socket path.  EXTRA-EVAL
is evaluated in the service before the server starts (to configure the
model backend); DATA-HOME is the service's data directory; TRANSPORT is a
form evaluating to the model transport of the service (nil uses the
default).  A service with the same name is not started twice.
CLEAN (the default) starts the service without the user's init; nil lets
the service inherit the user's configuration, including the gptel backend.
RULES is a list of permission rule plists: the standing permissions the
person grants the service, which is how a headless service may edit at
all.

The service watches a life socket of this process: when this process
ends, the service ends with it.  A service that outlived its owner would
hold its socket and wait for a client that never comes."
  (let ((existing (gethash name yeah-service--processes)))
    (when (and existing (process-live-p existing))
      (signal 'user-error
              (list (format "yeah-service-start: %S is already running" name)))))
  (let* ((socket (yeah-service--socket-path name))
         (life-tag (format "service-%s" name))
         (life (yeah-life-socket-path (yeah-service--socket-directory) life-tag))
         (family (yeah-client-effective-network-family))
         (port (when (eq family 'ipv4)
                 (yeah-service--reserve-loopback-port)))
         (server-form
          (if (eq family 'local)
              (format "(yeah-acp-serve-socket %S %s nil 'local %S)"
                      socket
                      (or transport "yeah-acp-default-transport")
                      life)
            (format "(yeah-acp-serve-socket %d %s nil 'ipv4 %S)"
                    port
                    (or transport "yeah-acp-default-transport")
                    life)))
         (buffer (generate-new-buffer (format " *yeah service %s*" name)))
         (process nil))
    ;; The service watches a life socket of this process: when this
    ;; process ends, the service ends with it.  A service that outlived
    ;; its owner would hold its socket and wait for a client that never
    ;; comes.
    (yeah-life-socket-sweep (yeah-service--socket-directory))
    (yeah-life-socket-create life)
    (setq process
          (make-process
           :name (format "yeah-service-%s" name)
           :buffer buffer
           :command
           (append (list (yeah-service--emacs-program))
                   (if clean (list "-Q" "--batch") (list "--batch"))
                   (list "-L" (yeah-service--lib-directory)
                         "-l" "yeah-acp"
                         "--eval"
                         (format "(progn %s %s %s %s)"
                                 (or extra-eval "")
                                 (if data-home
                                     (format "(setq yeah-data-home %S)" data-home)
                                   "")
                                 (yeah-service--rules-eval rules)
                                 server-form)))
           :connection-type 'pipe
           :noquery t))
    (when (eq family 'ipv4)
      (condition-case error
          (yeah-service--write-port-file socket port)
        (error
         (delete-process process)
         (signal (car error) (cdr error)))))
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
      (setq connection (yeah-client--open-connection socket))
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
      (ignore-errors (delete-file socket)))
    (let ((port-file (yeah-client-port-file socket)))
      (when (file-exists-p port-file)
        (ignore-errors (delete-file port-file)))))
  (yeah-life-socket-close
   (yeah-life-socket-path (yeah-service--socket-directory)
                          (format "service-%s" name)))
  t)

(provide 'yeah-service)
;;; yeah-service.el ends here
