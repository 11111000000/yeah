;;; check-bridge-live-server.el --- the bridge against a live Emacs server -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The bridge to the buffers of an attached Emacs was only checked
;; against a stub program.  This check runs a real Emacs server (a
;; daemon with a unique name) and drives the bridge against it:
;;
;;   - the probe answers;
;;   - a live buffer created in the server is readable through the
;;     bridge, including an edit made after the first read (so the bridge
;;     sees the live state, not a snapshot);
;;   - an expression is evaluated in the server and its printed value
;;     comes back;
;;   - with a server that does not exist the bridge says "unavailable"
;;     instead of hanging;
;;   - the bridge tools enter the registry only when the operator asks
;;     for them, and then the registry call returns the live text.
;;
;; About the channel question (`emacsclient --eval' or a persistent
;; connection): a request/answer round trip against this server takes a
;; few milliseconds, and the bridge's whole surface today is request and
;; answer -- probe, evaluate, read a buffer.  Nothing the bridge does
;; today needs a persistent connection; one would matter for streaming
;; the live state of a buffer, which the bridge does not do.

;;; Code:

(require 'cl-lib)
(require 'yeah-bridge)
(require 'yeah-tools)

(defvar yeah-check--emacs
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (expand-file-name "~/.nix-profile/bin/emacs"))
  "The Emacs program that runs the server.")

(defvar yeah-check--emacsclient
  (let* ((dir (file-name-directory yeah-check--emacs))
         (candidate (expand-file-name "emacsclient" dir)))
    (or (and (file-executable-p candidate) candidate)
        (executable-find "emacsclient")
        candidate))
  "The emacsclient program that reaches the server.")

(defun yeah-check--daemon-start (name form)
  "Start an Emacs daemon named NAME, evaluating FORM at startup."
  (make-process
   :name "yeah-bridge-server"
   :command (list yeah-check--emacs
                  (concat "--daemon=" name)
                  "--eval" form)
   :connection-type 'pipe
   :noquery t))

(defun yeah-check--daemon-eval (name expression)
  "Evaluate EXPRESSION in the server NAME and return the printed result."
  (with-temp-buffer
    (let ((code (call-process yeah-check--emacsclient nil t nil
                              "-s" name "--eval" expression)))
      (list code (string-trim (buffer-string))))))

(defun yeah-check--daemon-alive-p (name)
  "Return non-nil when the server NAME answers the probe."
  (and (zerop (car (yeah-check--daemon-eval name "t"))) t))

(defun yeah-check--daemon-await (name)
  "Wait until the server NAME answers, at most 15 seconds."
  (let ((deadline (+ (float-time) 15)))
    (while (and (not (yeah-check--daemon-alive-p name))
                (< (float-time) deadline))
      (accept-process-output nil 0.1))
    (yeah-check--daemon-alive-p name)))

(defun yeah-check--daemon-stop (name)
  "Ask the server NAME to stop."
  (ignore-errors (yeah-check--daemon-eval name "(kill-emacs)")))

(defun yeah-check--bridge-read-until (name expected &optional timeout)
  "Read *yeah-live* of server NAME through the bridge until the text is
EXPECTED, retrying within TIMEOUT seconds (default 15).
A bridge call is killed after the bridge's own 2-second timeout, and on a
loaded machine a single call can lose that race; the check asks for live
state, not for one fast call, so it retries instead of reporting a slow
server as a broken bridge."
  (let ((deadline (+ (float-time) (or timeout 15)))
        (got nil))
    (while (and (not (equal got expected)) (< (float-time) deadline))
      (setq got (condition-case nil
                    (let ((yeah-bridge-program yeah-check--emacsclient)
                          (yeah-bridge-server name))
                      (yeah-bridge-buffer-read "*yeah-live*"))
                  (error nil)))
      (unless (equal got expected)
        (accept-process-output nil 0.2)))
    got))

(let ((failures nil)
      (name (format "yeah-bridge-live-%d" (random 1000000))))
  (unwind-protect
      (progn
        ;; a real server with a live buffer
        (yeah-check--daemon-start
         name
         "(with-current-buffer (get-buffer-create \"*yeah-live*\") (insert \"live text\"))")
        (unless (yeah-check--daemon-await name)
          (push "the Emacs server did not answer" failures))
        (unless (equal "live text"
                       (yeah-check--bridge-read-until name "live text"))
          (push "the bridge could not read the live buffer" failures))
        ;; the bridge sees an edit made after the first read: live state
        (yeah-check--daemon-eval
         name
         "(with-current-buffer \"*yeah-live*\" (goto-char (point-max)) (insert \" edited\"))")
        (unless (equal "live text edited"
                       (yeah-check--bridge-read-until name "live text edited"))
          (push "the bridge did not see the edit made after the first read"
                failures))
        ;; evaluation in the server
        (unless (equal "3" (condition-case nil
                               (let ((yeah-bridge-program yeah-check--emacsclient) (yeah-bridge-server name))
                                 (yeah-bridge-eval "(+ 1 2)"))
                             (error "ERROR")))
          (push "the bridge could not evaluate in the server" failures))
        ;; an absent server is reported, not hung on
        (when (yeah-check--daemon-alive-p "yeah-bridge-live-absent")
          (push "the bridge reported an absent server as available" failures))
        (unless (condition-case nil
                    (progn (let ((yeah-bridge-program yeah-check--emacsclient) (yeah-bridge-server "yeah-bridge-live-absent"))
                             (yeah-bridge-buffer-read "*yeah-live*"))
                           nil)
                  (error t))
          (push "the bridge did not signal an unavailable server" failures))
        ;; the registry: absent until the operator asks, then live
        (when (yeah-tools-get "bridge__buffer_read")
          (push "the bridge tools were registered without being asked" failures))
        (yeah-bridge-register)
        (unless (equal "live text edited"
                       (let ((yeah-bridge-program yeah-check--emacsclient) (yeah-bridge-server name))
                         (yeah-tools-call "bridge__buffer_read"
                                          (list "*yeah-live*"))))
          (push "the registry call did not return the live text" failures)))
    (yeah-check--daemon-stop name)
    (dolist (failure failures)
      (message "bridge: %s" failure))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-bridge-live-server.el ends here
