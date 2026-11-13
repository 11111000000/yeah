;;; check-service-ui.el --- the editor drives a service through the UI -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The primary-path entry is a buffer that drives a service Emacs.  This
;; check starts a service with a fake model, opens the UI buffer, sends a
;; prompt through it and reads the buffer back: the question, the streamed
;; answer and the terminal stop reason are all there.  No network and no
;; key are needed.

;;; Code:

(require 'cl-lib)
(require 'yeah-service)
(require 'yeah-client)
(require 'yeah-service-ui)

(defun yeah-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE holds, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 15))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(let ((failures nil)
      (name (format "check-%d" (random 1000000)))
      (data-home (make-temp-file "yeah-service-ui" t))
      (client nil))
  (unwind-protect
      (progn
        (yeah-service-start
         name
         (concat "(defun yeah-check--transport (prompt callback) "
                 "(funcall callback \"the answer\"))")
         data-home
         "#'yeah-check--transport"
         t)
        (setq client
              (yeah-client-connect
               (yeah-service-socket-path name)))
        (let ((session-id nil))
          (yeah-client-request
           client "session/new"
           (list :cwd data-home :mcpServers nil)
           (lambda (result _error)
             (setq session-id (plist-get result :sessionId))))
          (yeah-check--await (lambda () session-id))
          (unless (stringp session-id)
            (push "the service did not create a session" failures))
          (when session-id
            (with-current-buffer (generate-new-buffer "*yeah-service-ui-test*")
              (yeah-service-ui-mode)
              (setq yeah-service-ui--client client
                    yeah-service-ui--session-id session-id)
              (let ((buffer (current-buffer)))
                (set-process-filter
                 (yeah-client-connection client)
                 (lambda (process chunk)
                   (yeah-client--filter client process chunk)))
                (setf (yeah-client-on-notification client)
                      (lambda (message)
                        (when (equal (plist-get message :method) "session/update")
                          (yeah-service-ui--render-update buffer message)))))
              (yeah-service-ui--ask "hi")
              (yeah-check--await
               (lambda ()
                 (string-match-p "end_turn" (buffer-string)))
               15)
              (let ((text (buffer-string)))
                (unless (string-match-p "> hi" text)
                  (push "the question is not in the buffer" failures))
                (unless (string-match-p "the answer" text)
                  (push "the answer is not in the buffer" failures))
                (unless (string-match-p "end_turn" text)
                  (push "the stop reason is not in the buffer" failures)))))))
    (when client
      (yeah-client-close client))
    (yeah-service-stop name)
    (ignore-errors (delete-directory data-home t))
    (dolist (failure failures)
      (message "service-ui: %s" failure))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-service-ui.el ends here
