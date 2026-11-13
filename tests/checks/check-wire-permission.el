;;; check-wire-permission.el --- the wire asks the person before an effect -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A headless service cannot ask the person: without the wire permission
;; protocol, a tool the rules do not name is denied outright.  This check
;; proves the wire asks the client first: the service sends
;; `session/request_permission', the client answers, and the tool runs or
;; is refused accordingly.  The model is a FAKE that asks for the `write'
;; tool, which the empty ruleset does not decide.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-service)
(require 'yeah-client)

(defun yeah-check--transport-source (target)
  "Return the source of the fake transport: it asks for one write to TARGET.
The target is unique per drive: a fixed path would make the second drive
fail with \"file exists\", which is not a refusal."
  (format "(defun yeah-check--transport (prompt callback)
      (funcall callback
               (list 'tool-call
                     (list (list :name \"write\")
                           (list %S \"content\")
                           (lambda (value) (funcall callback \"done\"))))))"
          target))

(defvar yeah-check--position nil)

(defun yeah-check--next-message (buffer &optional timeout)
  "Return the next JSON line in BUFFER, or nil."
  (let ((deadline (+ (float-time) (or timeout 10)))
        (message nil))
    (while (and (null message) (< (float-time) deadline))
      (accept-process-output nil 0.05)
      (with-current-buffer buffer
        (goto-char yeah-check--position)
        (when (re-search-forward "^\\(.+\\)\n" nil t)
          (setq message (json-parse-string (match-string 1)
                                          :object-type 'plist :array-type 'list))
          (setq yeah-check--position (match-end 0)))))
    message))

(defun yeah-check--drive (answer-option)
  "Drive a service through one prompt whose write is answered with
ANSWER-OPTION (\"allow-once\" or \"reject-once\"), and return the tool's
outcome."
  (let* ((data-home (make-temp-file "yeah-wire-perm" t))
         (name (format "perm-%d" (random 1000000)))
         (buffer (generate-new-buffer "*yeah-wire-perm*"))
         (connection nil)
         (client nil)
         (answer nil)
         (journal nil)
         (tool-result nil))
    (unwind-protect        (progn
          (yeah-service-start
           name
           (yeah-check--transport-source
            (expand-file-name "written.txt" data-home))
           data-home "#'yeah-check--transport" t nil)
          (setq client
                (yeah-client-connect
                 (yeah-service-socket-path name)))
          (setq connection (yeah-client-connection client))
          (with-current-buffer buffer
            (setq-local yeah-check--position (point-min)))
          (set-process-filter
           connection
           (lambda (_process chunk)
             (with-current-buffer buffer (insert chunk))))
          ;; handshake + session
          (yeah-client--send client
            (list :jsonrpc "2.0" :id 1 :method "initialize"
                  :params (list :protocolVersion 1)))
          (yeah-check--next-message buffer)
          (yeah-client--send client
            (list :jsonrpc "2.0" :id 2 :method "session/new"
                  :params (list :cwd data-home :mcpServers nil)))
          (let ((session-id
                 (plist-get (plist-get (yeah-check--next-message buffer) :result)
                            :sessionId)))
            ;; the prompt
            (yeah-client--send client
              (list :jsonrpc "2.0" :id 3 :method "session/prompt"
                    :params (list :sessionId session-id
                                  :prompt (vector (list :type "text" :text "write it")))))
            ;; the permission request arrives; answer it
            (let ((request nil))
              (let ((deadline (+ (float-time) 15)))
                (while (and (null request) (< (float-time) deadline))
                  (let ((message (yeah-check--next-message buffer 1)))
                    (when (and message
                               (equal (plist-get message :method)
                                      "session/request_permission"))
                      (setq request message)))))
              (unless request
                (error "the service did not ask for permission"))
              (let ((request-id (plist-get request :id)))
                ;; answer the request
                (yeah-client--send client
                  (list :jsonrpc "2.0" :id request-id
                        :result (list :outcome
                                      (if (equal answer-option "reject-once")
                                          (list :outcome "cancelled")
                                        (list :optionId answer-option))))))
              ;; the prompt's answer
              (let ((deadline (+ (float-time) 15)))
                (while (and (null answer) (< (float-time) deadline))
                  (let ((message (yeah-check--next-message buffer 1)))
                    (when (and message (equal (plist-get message :id) 3))
                      (setq answer message)))))
              (with-temp-buffer
                (insert-file-contents
                 (car (directory-files-recursively data-home "\\.jsonl\\'")))
                (let ((text (buffer-string)))
                  (setq journal text)
                  (setq tool-result
                        (cond
                         ((string-match-p "\"tool\":\"write\".*\"ok\":true" text)
                          "allowed")
                         ((string-match-p "\"tool\":\"write\".*\"ok\":false" text)
                          "refused"))))))))
      (when connection (ignore-errors (delete-process connection)))
      (yeah-service-stop name)
      (ignore-errors (delete-directory data-home t)))
    (list tool-result journal)))

(let ((failures nil)
      (allowed-run (yeah-check--drive "allow-once"))
      (refused-run (yeah-check--drive "reject-once")))
  (let ((allowed (nth 0 allowed-run))
        (refused (nth 0 refused-run)))
    (unless (equal allowed "allowed")
      (push (format "the allowed write did not run: %S" allowed) failures))
    (unless (equal refused "refused")
      (push (format "the refused write ran: %S" refused) failures))
    (dolist (failure failures)
      (message "wire-perm: %s" failure))
    (when failures
      (message "wire-perm: the allow journal:\n%s" (nth 1 allowed-run))
      (message "wire-perm: the reject journal:\n%s" (nth 1 refused-run))))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-wire-permission.el ends here
