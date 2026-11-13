;;; check-service-socket-is-private.el --- the socket is not in a world-writable place -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Anyone who can connect to the service's socket drives the agent with
;; the person's permissions.  This check proves the socket lives under a
;; directory only this user can reach: under XDG_RUNTIME_DIR when there
;; is one, else under a 0700 directory in TMPDIR — never a bare /tmp
;; socket.

;;; Code:

(require 'cl-lib)
(require 'yeah-service)

(let ((failures nil))
  (let ((path (yeah-service-socket-path "probe")))
    ;; the socket is under XDG_RUNTIME_DIR or a private directory
    (if-let ((runtime (getenv "XDG_RUNTIME_DIR")))
        (unless (string-prefix-p (file-name-as-directory (expand-file-name runtime))
                                 path)
          (push (format "the socket is not under XDG_RUNTIME_DIR: %s" path)
                failures))
      (let ((dir (file-name-directory path)))
        (unless (string-match-p (format "yeah-%d/" (user-uid)) dir)
          (push (format "the socket is not in a user-named directory: %s" path)
                failures))
        (unless (equal (file-modes dir) #o700)
          (push (format "the socket directory is not private: %s has mode %o"
                        dir (file-modes dir))
                failures))))
    ;; never a bare TMPDIR socket
    (when (equal (file-name-directory path)
                 (file-name-as-directory
                  (expand-file-name (or (getenv "TMPDIR") "/tmp"))))
      (push (format "the socket sits bare in TMPDIR: %s" path) failures)))
  ;; a started service actually creates its socket there
  (let ((name (format "priv-%d" (random 1000000)))
        (data-home (make-temp-file "yeah-priv" t)))
    (unwind-protect
        (progn
          (yeah-service-start name nil data-home nil t nil)
          (let ((socket (yeah-service-socket-path name))
                (deadline (+ (float-time) 15)))
            (while (and (not (file-exists-p socket)) (< (float-time) deadline))
              (accept-process-output nil 0.05))
            (unless (file-exists-p socket)
              (push (format "the service did not create its socket: %s" socket)
                    failures))))
      (yeah-service-stop name)
      (ignore-errors (delete-directory data-home t))))
  (dolist (failure failures)
    (message "socket-private: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-service-socket-is-private.el ends here
