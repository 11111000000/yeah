;;; check-service-ui-permission.el --- the person answers the service over the wire -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The service asks before an effect the rules do not name
;; (session/request_permission); the editor is what answers.  This check
;; drives a service whose model asks for `write' with no standing rules,
;; through the client's request path and the UI's own request handler,
;; with the prompter stubbed to the person's answer.  It proves: the
;; question is rendered into the session buffer with the tool and its
;; arguments, the answer the person gives reaches the service, and the
;; tool runs.  The refusal path is covered by check-wire-permission.el.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-service)
(require 'yeah-client)
(require 'yeah-service-ui)

(defun yeah-check--transport-source (target)
  "Return the source of the fake transport: it asks for one write to TARGET."
  (format "(defun yeah-check--transport (prompt callback)
      (funcall callback
               (list 'tool-call
                     (list (list :name \"write\")
                           (list %S \"content\")
                           (lambda (value) (funcall callback \"done\"))))))"
          target))

(defun yeah-check--await (probe &optional timeout)
  "Wait until (funcall PROBE) is non-nil, up to TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 15))))
    (while (and (not (funcall probe)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall probe)))

(let* ((failures nil)
       (data-home (make-temp-file "yeah-ui-perm" t))
       (name (format "ui-perm-%d" (random 1000000)))
       (buffer (generate-new-buffer "*Yeah service: ui-perm*"))
       (client nil)
       (initialized nil)
       (session-id nil)
       (answered nil)
       (yeah-service-ui-permission-prompter
        (lambda (title raw-input)
          (unless (and (string-match-p "write" title)
                       (listp raw-input)
                       (string-match-p "written\\.txt"
                                       (or (nth 0 raw-input) "")))
            (error "the question does not name the tool and its target: %S %S"
                   title raw-input))
          "allow-once")))
  (unwind-protect
      (progn
        (yeah-service-start
         name
         (yeah-check--transport-source
          (expand-file-name "written.txt" data-home))
         data-home "#'yeah-check--transport" t nil)
        (setq client
              (yeah-client-connect
               (yeah-service-socket-path name)
               :on-request
               (lambda (method params respond)
                 (yeah-service-ui--handle-request buffer method params
                                                  respond))))
        (yeah-client-request client "initialize"
                             (list :protocolVersion 1)
                             (lambda (_result error)
                               (unless error (setq initialized t))))
        (unless (yeah-check--await (lambda () initialized))
          (push "the service did not answer initialize" failures))
        (when initialized
          (yeah-client-request client "session/new"
                               (list :cwd data-home :mcpServers nil)
                               (lambda (result _error)
                                 (setq session-id
                                       (plist-get result :sessionId))))
          (unless (yeah-check--await (lambda () session-id))
            (push "the service did not open the session" failures)))
        (when session-id
          (yeah-client-request
           client "session/prompt"
           (list :sessionId session-id
                 :prompt (vector (list :type "text" :text "write it")))
           (lambda (result error)
             (setq answered (or error (plist-get result :stopReason)))))
          (unless (yeah-check--await (lambda () answered))
            (push "the prompt was not answered" failures)))
        ;; the question was rendered into the session buffer
        (unless (with-current-buffer buffer
                  (string-match-p
                   "\\[permission\\] write on .*written\\.txt"
                   (buffer-string)))
          (push (format "the session buffer does not show the question: %S"
                        (with-current-buffer buffer (buffer-string)))
                failures))
        ;; the person allowed, so the write ran
        (let ((journal
               (mapconcat
                (lambda (file)
                  (with-temp-buffer
                    (insert-file-contents file)
                    (buffer-string)))
                (directory-files-recursively data-home "\\.jsonl\\'")
                "\n")))
          (unless (string-match-p "\"tool\":\"write\".*\"ok\":true" journal)
            (push (format "the allowed write did not run:\n%s" journal)
                  failures))))
    (when client (yeah-client-close client))
    (yeah-service-stop name)
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (kill-buffer buffer)))
  (dolist (failure failures)
    (message "ui-perm: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-service-ui-permission.el ends here
