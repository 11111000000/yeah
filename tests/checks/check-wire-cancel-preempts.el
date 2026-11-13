;;; check-wire-cancel-preempts.el --- a cancel that stops a running prompt -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A real Emacs process serves ACP on a local socket.  The model is a FAKE
;; that never answers the first prompt, so the prompt stays active for as
;; long as the server runs.
;;
;; The client sends `session/prompt', waits until the server has really
;; started the turn (the journal event of the user message arrives as a
;; `session/update' notification), and then sends `session/cancel'.  The
;; prompt must answer with the cancelled stop reason instead of waiting
;; for a model that will never answer, the journal must record the
;; cancellation, and a later prompt must still work.
;;
;; No network is involved: the socket is a file in a temporary directory.

;;; Code:

(require 'cl-lib)
(require 'json)

(defvar yeah-check--position nil
  "Position in the client buffer after the last line consumed.")

(defun yeah-check--emacs ()
  "Return the Emacs program to run the server."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (expand-file-name "~/.nix-profile/bin/emacs")))

(defun yeah-check--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))

(defun yeah-check--start-server (data-home socket)
  "Start the ACP server process and return it with its output buffer.
The fake transport of the server never answers the first prompt and
answers every later prompt with text."
  (let ((buffer (generate-new-buffer "*yeah-cancel-server*")))
    (list (make-process
           :name "yeah-cancel-server"
           :buffer buffer
           :command
           (list (yeah-check--emacs) "-Q" "--batch"
                 "-L" (yeah-check--lib-directory)
                 "-l" "yeah-acp"
                 "--eval"
                 (format
                  (concat "(progn (setq yeah-data-home %S) "
                          "(defvar yeah-check--prompts 0) "
                          "(defun yeah-check--transport (prompt callback) "
                          "(setq yeah-check--prompts (1+ yeah-check--prompts)) "
                          "(if (= yeah-check--prompts 1) nil "
                          "(funcall callback \"done\"))) "
                          "(yeah-acp-serve-socket %S #'yeah-check--transport))")
                  data-home socket))
           :connection-type 'pipe
           :noquery t
           :filter (lambda (_process chunk)
                     (with-current-buffer buffer
                       (insert chunk))))
          buffer)))

(defun yeah-check--connect (socket)
  "Connect to the server on SOCKET and return the connection process.
The connection is retried until the server is listening."
  (let ((deadline (+ (float-time) 20))
        (connection nil))
    (while (and (null connection) (< (float-time) deadline))
      (setq connection
            (condition-case nil
                (make-network-process
                 :name "yeah-cancel-client"
                 :family 'local
                 :service socket
                 :noquery t
                 :filter (lambda (_process chunk)
                           (with-current-buffer yeah-check--buffer
                             (insert chunk))))
              (file-missing nil)))
      (unless connection
        (accept-process-output nil 0.05)))
    connection))

(defvar yeah-check--buffer nil
  "The buffer collecting the messages the client received.")

(defun yeah-check--send (connection object)
  "Send OBJECT as one JSON line to CONNECTION."
  (process-send-string connection (concat (json-serialize object) "\n")))

(defun yeah-check--next-message (&optional timeout)
  "Return the next message the client received, or nil.
TIMEOUT defaults to 10 seconds."
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

(defun yeah-check--await (predicate &optional timeout)
  "Return the next message that satisfies PREDICATE.
Messages that do not satisfy it are skipped.  TIMEOUT defaults to 10
seconds."
  (let ((deadline (+ (float-time) (or timeout 10)))
        (message nil))
    (while (and (null message) (< (float-time) deadline))
      (let ((candidate (yeah-check--next-message 1)))
        (when (and candidate (funcall predicate candidate))
          (setq message candidate))))
    message))

(defun yeah-check--response (id)
  "Return a predicate matching the JSON-RPC response with ID."
  (lambda (message)
    (and (equal (plist-get message :id) id)
         (not (plist-get message :method)))))

(defun yeah-check--journal-cancelled-p (data-home)
  "Return non-nil when a journal under DATA-HOME records a cancellation."
  (let ((found nil))
    (when (file-directory-p data-home)
      (dolist (file (directory-files-recursively data-home "\\.jsonl\\'"))
        (when (and (not found)
                   (string-match-p "\"type\"[[:space:]]*:[[:space:]]*\"cancel\""
                                   (with-temp-buffer
                                     (insert-file-contents file)
                                     (buffer-string))))
          (setq found t))))
    found))

(let ((failures nil)
      (data-home (make-temp-file "yeah-cancel-data" t))
      (socket nil)
      (server-output nil))
  (unwind-protect
      (progn
        (setq socket (expand-file-name "yeah-acp.sock" data-home))
        (setq yeah-check--buffer (generate-new-buffer "*yeah-cancel-client*"))
        (with-current-buffer yeah-check--buffer
          (setq-local yeah-check--position (point-min)))
        (let* ((started (yeah-check--start-server data-home socket))
               (server (nth 0 started))
               (connection (yeah-check--connect socket))
               (session-id nil))
          (setq server-output (nth 1 started))
          (unless connection
            (push "the client could not connect to the server" failures))
          (unwind-protect
              (when connection
                ;; --- the handshake ---
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :id 1 :method "initialize"
                       :params (list :protocolVersion 1)))
                (let ((response (yeah-check--await (yeah-check--response 1))))
                  (unless (equal 1 (plist-get (plist-get response :result)
                                              :protocolVersion))
                    (push (format "ACP initialize did not answer: %S" response)
                          failures)))
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :id 2 :method "session/new"
                       :params (list :cwd data-home :mcpServers nil)))
                (let ((response (yeah-check--await (yeah-check--response 2))))
                  (setq session-id (plist-get (plist-get response :result)
                                              :sessionId))
                  (unless (stringp session-id)
                    (push (format "ACP session/new did not answer: %S" response)
                          failures)))
                (when session-id
                ;; --- a prompt that the model never answers ---
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :id 3 :method "session/prompt"
                       :params (list :sessionId session-id
                                     :prompt (vector (list :type "text"
                                                           :text "wait")))))
                (let ((started (yeah-check--await
                                (lambda (message)
                                  (equal (plist-get message :method)
                                         "session/update"))
                                10)))
                  (unless started
                    (push "the server did not report the started prompt"
                          failures)))
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :method "session/cancel"
                       :params (list :sessionId session-id)))
                (let ((response (yeah-check--await (yeah-check--response 3) 10)))
                  (unless (equal "cancelled"
                                 (plist-get (plist-get response :result)
                                            :stopReason))
                    (push (format "the prompt was not cancelled: %S" response)
                          failures)))
                (unless (yeah-check--journal-cancelled-p data-home)
                  (push "the journal does not record the cancellation" failures))

                ;; --- the server is still usable ---
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :id 4 :method "session/prompt"
                       :params (list :sessionId session-id
                                     :prompt (vector (list :type "text"
                                                           :text "again")))))
                (let ((response (yeah-check--await (yeah-check--response 4) 10)))
                  (unless (equal "end_turn"
                                 (plist-get (plist-get response :result)
                                            :stopReason))
                    (push (format "the next prompt did not complete: %S"
                                  response)
                          failures)))))
            (when connection
              (ignore-errors (delete-process connection)))
            (when (process-live-p server)
              (ignore-errors (delete-process server))))))

    (dolist (failure failures)
      (message "cancel: %s" failure))
    (when (and failures server-output)
      (with-current-buffer server-output
        (message "cancel: the server said:\n%s" (buffer-string))))
    (when failures
      (dolist (file (ignore-errors
                      (directory-files-recursively data-home "\\.jsonl\\'")))
        (message "cancel: journal %s:\n%s" file
                 (with-temp-buffer
                   (insert-file-contents file)
                   (buffer-string)))))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-file socket))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-wire-cancel-preempts.el ends here
