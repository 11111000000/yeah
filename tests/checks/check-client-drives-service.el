;;; check-client-drives-service.el --- the editor client drives a service -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The editor is a client of a service Emacs.  This check starts a service
;; and drives it through the client library: the handshake, a session, a
;; prompt answered with the end_turn stop reason, and the session/update
;; notifications that stream the work.  The model is a FAKE, so no network
;; and no key are needed.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-service)
(require 'yeah-client)

(defun yeah-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE holds, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 8))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))


(defun yeah-check--emacs ()
  "Return the Emacs program that runs the service.
The service runs the same Emacs as this one: the running binary when the
platform can name it, so the check does not depend on the PATH of the
process that starts it."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-check--service-emacs ()
  "Bind the program of the service to the Emacs of this process."
  (setq yeah-service-emacs (yeah-check--emacs)))

(let ((failures nil)
  (yeah-check--service-emacs)
      (name (format "check-%d" (random 1000000)))
      (data-home (make-temp-file "yeah-client-data" t))
      (client nil))
  (unwind-protect
      (progn
        (yeah-service-start
         name
         (concat "(defun yeah-check--transport (prompt callback) "
                 "(funcall callback (list 'tool-call "
                 "(list (list :name \"finish\") (list \"done\") "
                 "(lambda (_value) nil)))))")
         data-home
         "#'yeah-check--transport")
        (let ((notifications nil))
          (setq client
                (yeah-client-connect
                 (yeah-service-socket-path name)
                 :on-notification (lambda (message)
                                    (push message notifications))))
          (unless (and client (process-live-p (yeah-client-connection client)))
            (push "the client did not connect" failures))
          (when client
            ;; the handshake
            (let ((init nil))
              (yeah-client-request
               client "initialize" (list :protocolVersion 1)
               (lambda (result _error) (setq init result)))
              (yeah-check--await (lambda () init))
              (unless (equal 1 (plist-get init :protocolVersion))
                (push (format "initialize answered %S" init) failures)))
            ;; a session and a prompt
            (let ((session-id nil))
              (yeah-client-request
               client "session/new"
               (list :cwd data-home :mcpServers nil)
               (lambda (result _error)
                 (setq session-id (plist-get result :sessionId))))
              (yeah-check--await (lambda () session-id))
              (unless (stringp session-id)
                (push "session/new did not return a session id" failures))
              (when session-id
                (let ((answer nil))
                  (yeah-client-request
                   client "session/prompt"
                   (list :sessionId session-id
                         :prompt (vector (list :type "text" :text "hi")))
                   (lambda (result _error) (setq answer result)))
                  (unless (yeah-check--await (lambda () answer) 8)
                    (push "the prompt was not answered" failures))
                  (unless (equal "end_turn" (plist-get answer :stopReason))
                    (push (format "the prompt answered with %S"
                                  (plist-get answer :stopReason))
                          failures))
                  ;; the streamed updates arrived
                  (unless (cl-some (lambda (message)
                                     (equal "session/update"
                                            (plist-get message :method)))
                                   notifications)
                    (push "no session/update notification arrived"
                          failures)))))))))
    (when client
      (yeah-client-close client))
    (yeah-service-stop name)
    (ignore-errors (delete-directory data-home t))
    (dolist (failure failures)
      (message "client: %s" failure))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0)))

;;; check-client-drives-service.el ends here
