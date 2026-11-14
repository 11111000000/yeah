;;; live-service-path.el --- the primary path with a real model -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The primary deployment is a dedicated service Emacs driven over ACP.
;; Every offline canary uses a fake model; this check is the one that runs
;; the primary path against a real provider: a clean service Emacs gets
;; only the gptel configuration through its init form, the client asks for
;; a small file over the wire, approves the write through
;; session/request_permission, and the file must appear.
;;
;; Environment (never committed):
;;   YEAH_TEST_KEY    the provider key (read by the service, not by us)
;;   YEAH_TEST_HOST   the API host, for example api.minimax.io
;;   YEAH_TEST_MODEL  the model, for example MiniMax-M3.1-Flash
;;   EMACS            the Emacs binary (optional)
;;
;; Exit codes: 0 — the primary path works with a live model; 1 — it does
;; not; skipped with a message when no key is configured.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-service)
(require 'yeah-client)

(defun yeah-live-service--init-form ()
  "Return the init form that gives a clean service its model.
Only the load paths and the gptel backend are configured; the key is read
from the service's own environment, never from a command line."
  (format "(progn
            (dolist (dir (file-expand-wildcards
                          (expand-file-name \"~/.emacs.d/elpa/{gptel,transient,compat}-*\")))
              (add-to-list 'load-path dir))
            (require 'gptel)
            (require 'gptel-openai)
            (setq gptel-backend
                  (gptel-make-openai \"yeah-live-service\"
                    :host %S
                    :endpoint \"/v1/chat/completions\"
                    :key (getenv \"YEAH_TEST_KEY\")
                    :models (list (intern (or (getenv \"YEAH_TEST_MODEL\")
                                              \"MiniMax-M3.1-Flash\")))))
            (setq gptel-model (intern (or (getenv \"YEAH_TEST_MODEL\")
                                          \"MiniMax-M3.1-Flash\"))))"
          (or (getenv "YEAH_TEST_HOST") "api.minimax.io")))

(defun yeah-live-service--await (probe &optional timeout)
  "Wait until (funcall PROBE) is non-nil, up to TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 300))))
    (while (and (not (funcall probe)) (< (float-time) deadline))
      (accept-process-output nil 0.2))
    (funcall probe)))

(let ((failures nil))
  (unless (getenv "YEAH_TEST_KEY")
    (message "live service path: skipped — no YEAH_TEST_KEY in the environment")
    (kill-emacs 0))
  (let* ((directory (make-temp-file "yeah-live-service" t))
         (data-home (make-temp-file "yeah-live-service-data" t))
         (name (format "live-%d" (random 1000000)))
         (target (expand-file-name "answer.txt" directory))
         (client nil)
         (session-id nil)
         (answered nil)
         (asked nil))
    (unwind-protect
        (progn
          (yeah-service-start name (yeah-live-service--init-form)
                              data-home nil t nil)
          (setq client
                (yeah-client-connect
                 (yeah-service-socket-path name)
                 :timeout 30
                 :on-request
                 (lambda (method params respond)
                   (if (equal method "session/request_permission")
                       (progn
                         (setq asked t)
                         (funcall respond
                                  (list :outcome
                                        (list :optionId "allow-once"))))
                     (funcall respond nil)))))
          (yeah-client-request client "initialize"
                               (list :protocolVersion 1)
                               (lambda (_result _error) nil))
          (yeah-client-request client "session/new"
                               (list :cwd directory :mcpServers nil)
                               (lambda (result _error)
                                 (setq session-id
                                       (plist-get result :sessionId))))
          (unless (yeah-live-service--await (lambda () session-id) 30)
            (push "the service did not open a session" failures))
          (when session-id
            (yeah-client-request
             client "session/prompt"
             (list :sessionId session-id
                   :prompt
                   (vector (list :type "text"
                                 :text (format "Create the file %s with exactly this content: 42\nThen stop."
                                               target))))
             (lambda (result error)
               (setq answered (or error result))))
            (yeah-live-service--await
             (lambda () (or answered (file-exists-p target))) 300)
            (unless asked
              (push "the service never asked for the write permission" failures))
            (unless (file-exists-p target)
              (push (format "the model did not create the file; answer: %S"
                            answered)
                    failures))
            (when (file-exists-p target)
              (with-temp-buffer
                (insert-file-contents target)
                (unless (string-match-p "42" (buffer-string))
                  (push "the file has the wrong content" failures))))))
      (when client (yeah-client-close client))
      (yeah-service-stop name)
      (ignore-errors (delete-directory directory t))
      (ignore-errors (delete-directory data-home t)))
    (dolist (failure failures)
      (message "live service path: %s" failure))
    (if failures
        (kill-emacs 1)
      (message "live service path: the primary path works with a live model")
      (kill-emacs 0))))

;;; live-service-path.el ends here
