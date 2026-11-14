;;; check-client-disconnect-during-permission.el --- a dead asker must not hang the run -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The service asks the client before an effect the rules do not name.
;; If the client disconnects without answering, the run must not wait
;; forever: the socket sentinel cancels it with the reason in the journal.
;; This check drives a fake model that asks for `write', waits for the
;; permission request, disconnects the client without answering, and
;; requires the journal to show the cancellation.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-service)
(require 'yeah-client)

(defun yeah-check--transport-source (target)
  "Return the source of the fake transport: it asks for one write to TARGET."
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
                                           :object-type 'plist
                                           :array-type 'list))
          (setq yeah-check--position (match-end 0)))))
    message))

(defun yeah-check--journal (data-home)
  "Return the service's journal under DATA-HOME as one string.
Lockfiles (.#name) are symlinks that may vanish while the service is
writing; they are not journal records."
  (mapconcat (lambda (file)
               (with-temp-buffer
                 (insert-file-contents file)
                 (buffer-string)))
             (seq-remove
              (lambda (file)
                (string-prefix-p ".#" (file-name-nondirectory file)))
              (directory-files-recursively data-home "\\.jsonl\\'"))
             "\n"))

(let ((failures nil)
      (data-home (make-temp-file "yeah-disconnect" t))
      (name (format "disconnect-%d" (random 1000000)))
      (buffer (generate-new-buffer "*yeah-disconnect*"))
      (connection nil))
  (unwind-protect
      (progn
        (yeah-service-start
         name
         (yeah-check--transport-source
          (expand-file-name "written.txt" data-home))
         data-home "#'yeah-check--transport" t nil)
        (let ((client (yeah-client-connect (yeah-service-socket-path name))))
          (setq connection (yeah-client-connection client))
          (with-current-buffer buffer
            (setq-local yeah-check--position (point-min)))
          (set-process-filter
           connection
           (lambda (_process chunk)
             (with-current-buffer buffer (insert chunk))))
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
            (yeah-client--send client
              (list :jsonrpc "2.0" :id 3 :method "session/prompt"
                    :params (list :sessionId session-id
                                  :prompt (vector (list :type "text"
                                                      :text "write it")))))
            ;; wait for the question, then die without answering
            (let ((request nil)
                  (deadline (+ (float-time) 15)))
              (while (and (null request) (< (float-time) deadline))
                (let ((message (yeah-check--next-message buffer 1)))
                  (when (and message
                             (equal (plist-get message :method)
                                    "session/request_permission"))
                    (setq request message))))
              (unless request
                (push "the service did not ask for permission" failures))
              (when request
                (delete-process connection)
                (setq connection nil)
                ;; the run must die with a reason, not hang
                (let ((cancelled nil)
                      (deadline (+ (float-time) 15)))
                  (while (and (not cancelled) (< (float-time) deadline))
                    (let ((journal (yeah-check--journal data-home)))
                      (when (string-match-p
                             "\"type\":\"cancel\".*the client disconnected"
                             journal)
                        (setq cancelled t)))
                    (unless cancelled
                      (accept-process-output nil 0.2)))
                  (unless cancelled
                    (push (format "the run was not cancelled after the client died:\n%s"
                                  (yeah-check--journal data-home))
                          failures))
                  (let ((journal (yeah-check--journal data-home)))
                    (when (string-match-p "\"tool\":\"write\".*\"ok\":true"
                                          journal)
                      (push "the write ran although nobody allowed it" failures))))))))
    (when connection (ignore-errors (delete-process connection)))
    (yeah-service-stop name)
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (kill-buffer buffer)))
  (dolist (failure failures)
    (message "disconnect: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0))))

;;; check-client-disconnect-during-permission.el ends here
