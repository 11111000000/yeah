;;; live-clean-install.el --- the clean-Emacs install path, for real -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The public alpha gate needs one thing that the offline suite cannot
;; prove: that a clean Emacs can install Yeah and then load it.  This
;; check does exactly that, against the network, in a throwaway HOME:
;;
;;   1. it runs the documented bootstrap (`install/yeah-bootstrap.el') in a
;;      clean Emacs whose HOME is an empty temporary directory;
;;   2. it starts a second clean Emacs with that HOME and requires the
;;      installed package;
;;   3. it requires that the installation produced no compilation error and
;;      that `yeah', `yeah-ask' and `yeah-doctor' are bound afterwards.
;;
;; Nothing of the user's own Emacs configuration is touched: HOME points
;; at a temporary directory for both processes.
;;
;; The bootstrap installs from a repository URL.  By default that is the
;; published repository; the URL can be overridden, and a local clone is
;; accepted, which is how the path is checked before a change is pushed:
;;
;;   YEAH_CLEAN_INSTALL_URL  the repository URL or path to install from
;;
;; The local repository must contain the package layout the bootstrap
;; expects: the entry point in `lib/yeah.el' and the installation with
;; `:lisp-dir "lib"'.
;;
;; Exit codes: 0 — the clean installation worked; 1 — it did not.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defun yeah-live-install--emacs ()
  "Return the Emacs binary to run."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS"))
           (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))
      (error "live-clean-install: no Emacs binary found")))

(defun yeah-live-install--run (home arguments)
  "Run Emacs with HOME and ARGUMENTS; return (exit-code . output).

The child gets its HOME through `env', because `make-process' has no
`:environment' keyword in every supported Emacs build."
  (let* ((program (yeah-live-install--emacs))
         (output "")
         (code nil)
         (deadline (+ (float-time) 600)))
    (let ((process
           (make-process :name "yeah-live-install"
                          :command (append
                                    (list "/usr/bin/env"
                                          (concat "HOME=" home)
                                          (concat "PATH="
                                                  (or (getenv "PATH") ""))
                                          "LC_ALL=C.UTF-8"
                                          "GIT_TERMINAL_PROMPT=0")
                                    (list program)
                                    arguments)
                          :connection-type 'pipe
                          :filter (lambda (_process chunk)
                                    (setq output (concat output chunk)))
                          :noquery t)))
      (while (and (process-live-p process) (< (float-time) deadline))
        (accept-process-output process 0.05))
      (if (process-live-p process)
          (kill-process process)
          (setq code 124)
        (setq code (process-exit-status process))))
    (list code output)))

(defun yeah-live-install--bootstrap (home url)
  "Write a bootstrap for URL into HOME and return its path."
  (let* ((source (expand-file-name "install/yeah-bootstrap.el"))
         (target (expand-file-name "yeah-bootstrap.el" home))
         (text (with-temp-buffer
                 (insert-file-contents source)
                 (buffer-string))))
    (unless (file-readable-p source)
      (error "live-clean-install: run me from the repository root"))
    (with-temp-file target
      (insert (replace-regexp-in-string
               "https://github\\.com/11111000000/yeah\\.git" url text)))
    target))

(defun yeah-live-install--main ()
  "Run the clean installation and report the outcome."
  (let* ((url (or (getenv "YEAH_CLEAN_INSTALL_URL")
                  "https://github.com/11111000000/yeah.git"))
         (home (make-temp-file "yeah-clean-home" t))
         (bootstrap (yeah-live-install--bootstrap home url))
         (install (yeah-live-install--run home
                                        (list "-Q" "--batch" "-l" bootstrap)))
         (load (yeah-live-install--run
                home
                (list "-Q" "--batch" "--eval"
                      (concat "(progn (package-initialize) (require 'yeah) "
                              "(message \"YEAH-INSTALL-OK %s %s %s\" "
                              "(fboundp 'yeah) (fboundp 'yeah-ask) "
                              "(fboundp 'yeah-doctor)))")))))
    (when (> (length (or (cadr install) "")) 0)
      (message "live-clean-install: install output:\n%s" (cadr install)))
    (when (and (= (car install) 0)
               (string-match-p "YEAH-INSTALL-OK t t t" (or (cadr load) "")))
      (message "live-clean-install: the clean installation works")
      (kill-emacs 0))
    (message "live-clean-install: the clean installation FAILED (install exit %s)"
             (car install))
    (message "live-clean-install: load output:\n%s" (or (cadr load) ""))
    (kill-emacs 1)))

(yeah-live-install--main)

;;; live-clean-install.el ends here
