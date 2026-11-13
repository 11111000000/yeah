;;; check-service-lifecycle.el --- a service Emacs answers a prompt -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The primary placement is a dedicated Emacs process.  This check starts
;; such a service, connects to it as a client, and drives one prompt over
;; the socket: the answer comes back with the end_turn stop reason, and
;; the journal of the service records the turn.  The model is a FAKE, so
;; no network and no key are needed.  The service is stopped afterwards.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-service)

(defvar yeah-check--buffer nil
  "The buffer collecting the messages the client received.")

(defvar yeah-check--position nil
  "Position in the client buffer after the last line consumed.")

(defun yeah-check--send (connection object)
  "Send OBJECT as one JSON line to CONNECTION."
  (process-send-string connection (concat (json-serialize object) "\n")))

(defun yeah-check--next-message (&optional timeout)
  "Return the next message the client received, or nil."
  (let ((deadline (+ (float-time) (or timeout 10)))
        (message nil))
    (while (and (null message) (< (float-time) deadline))
      (accept-process-output nil 0.05)
      (with-current-buffer yeah-check--buffer
        (goto-char yeah-check--position)
        (when (re-search-forward "^\\(.+\\)\n" nil t)
          (setq message (json-parse-string (match-string 1)
                                          :object-type 'plist :array-type 'list))
          (setq yeah-check--position (match-end 0)))))
    message))

(defun yeah-check--response (id)
  "Return a predicate matching the JSON-RPC response with ID."
  (lambda (message)
    (and (equal (plist-get message :id) id)
         (not (plist-get message :method)))))

(defun yeah-check--await (predicate &optional timeout)
  "Return the next message that satisfies PREDICATE."
  (let ((deadline (+ (float-time) (or timeout 10)))
        (message nil))
    (while (and (null message) (< (float-time) deadline))
      (let ((candidate (yeah-check--next-message 1)))
        (when (and candidate (funcall predicate candidate))
          (setq message candidate))))
    message))

(let ((failures nil)
      (name (format "check-%d" (random 1000000)))
      (data-home (make-temp-file "yeah-service-data" t))
      (connection nil))
  (unwind-protect
      (progn
        (setq yeah-check--buffer (generate-new-buffer "*yeah-service-client*"))
        (with-current-buffer yeah-check--buffer
          (setq-local yeah-check--position (point-min)))
        ;; start a service with a fake model
        (yeah-service-start
         name
         (concat "(defun yeah-check--transport (prompt callback) "
                 "(funcall callback \"done\"))")
         data-home
         "#'yeah-check--transport")
        (setq connection (yeah-service-connect name 15))
        (unless connection
          (push "the client could not connect to the service" failures))
        (when connection
          (set-process-filter
           connection
           (lambda (_process chunk)
             (with-current-buffer yeah-check--buffer
               (insert chunk))))
          ;; the handshake
          (yeah-check--send
           connection
           (list :jsonrpc "2.0" :id 1 :method "initialize"
                 :params (list :protocolVersion 1)))
          (unless (equal 1 (plist-get
                            (plist-get (yeah-check--await
                                        (yeah-check--response 1))
                                       :result)
                            :protocolVersion))
            (push "the service did not answer the handshake" failures))
          ;; a session
          (yeah-check--send
           connection
           (list :jsonrpc "2.0" :id 2 :method "session/new"
                 :params (list :cwd data-home :mcpServers nil)))
          (let ((session-id (plist-get
                             (plist-get (yeah-check--await
                                         (yeah-check--response 2))
                                        :result)
                             :sessionId)))
            (unless (stringp session-id)
              (push "the service did not create a session" failures))
            (when session-id
              ;; a prompt
              (yeah-check--send
               connection
               (list :jsonrpc "2.0" :id 3 :method "session/prompt"
                     :params (list :sessionId session-id
                                   :prompt (vector (list :type "text"
                                                         :text "hi")))))
              (let ((answer (yeah-check--await (yeah-check--response 3) 15)))
                (unless (equal "end_turn"
                               (plist-get (plist-get answer :result)
                                          :stopReason))
                  (push (format "the prompt answered with %S"
                                (plist-get (plist-get answer :result)
                                           :stopReason))
                        failures)))
              ;; the journal of the service records the turn
              (let ((journal (car (directory-files-recursively
                                   data-home "\\.jsonl\\'"))))
                (unless (and journal
                             (string-match-p "assistant-message"
                                             (with-temp-buffer
                                               (insert-file-contents journal)
                                               (buffer-string))))
                  (push "the service journal has no assistant message"
                        failures)))))))
    (when connection
      (ignore-errors (delete-process connection)))
    (yeah-service-stop name)
    (ignore-errors (delete-directory data-home t))
    (dolist (failure failures)
      (message "service: %s" failure))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-service-lifecycle.el ends here
