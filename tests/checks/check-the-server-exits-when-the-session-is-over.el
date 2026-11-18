;;; check-the-server-exits-when-the-session-is-over.el --- the server ends with its session -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The defect: the process of the ACP server outlives the agent.  A client
;; that keeps the pipe of the server open after the last turn leaves a
;; process of Emacs behind, and nothing closes it.
;;
;; This check starts a real ACP server on stdio, drives a session through
;; a turn, ends the session with the request `session/close' -- and keeps the
;; pipe of the client open -- and proves that the process of the server is
;; gone within ten seconds.
;;
;; The method is the one the orchestrator calls: Paseo sends `session/close'
;; when it closes the session of the agent
;; (`packages/plugin/src/server/acp-internal/connection.ts:690-698'), and the
;; error of the answer is swallowed there (`.catch(() => undefined)`), so a
;; core that does not know the method keeps its session and its process alive
;; without a word.  The request is answered before the server stops: ACP says
;; `session/close' is a request, and a client that waits for the answer of a
;; request must get it.
;;
;; The verdict is decided by construction: the client sits on an open pipe
;; and waits for the death of the server, so the same input gives the same
;; verdict on every run.  The control of the claim takes out the way the
;; server ends when its session is over -- the server keeps serving after
;; the request -- and the check then fails by its own assertion: the
;; process is still alive ten seconds after the request.
;;
;; The second part of the check pins the other half of the rule: the server
;; over a socket serves many clients, so the end of the session of one
;; client must not end the server, and the session that is over must not
;; answer a prompt anymore.
;;
;; No network is involved: the model of the server is a fake that answers
;; at once with the `finish' tool, and the socket is a file in a temporary
;; directory.
;;
;; Exit codes: 0 -- the server ended with its session, and the server over
;; a socket kept serving its clients; 1 -- it did not.

;;; Code:

(require 'cl-lib)
(require 'json)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--buffer nil
  "The buffer that collects what the server sent.")

(defvar yeah-check--position nil
  "The position in the buffer of the server after the last line consumed.")

(defun yeah-check--emacs ()
  "Return the Emacs program that runs the server.
The server runs the same Emacs as this one: the running binary when the
platform can name it, so the check works where `emacs' is not on PATH."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-check--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))

(defun yeah-check--transport-source ()
  "Return the Elisp source of the fake transport of the server.
The model is a fake that answers at once with the `finish' tool: the
check needs no network and no key."
  (concat "(defun yeah-check--transport (prompt callback) "
          "(funcall callback (list 'tool-call "
          "(list (list :name \"finish\") (list \"done\") "
          "(lambda (_value) nil))))) "))

(defun yeah-check--stdio-command (data-home)
  "Return the argv of the ACP server that serves on stdio.
DATA-HOME is the data home of the server process."
  (list (yeah-check--emacs) "-Q" "--batch"
        "-L" (yeah-check--lib-directory)
        "-l" "yeah-acp"
        "--eval"
        (format (concat "(progn (setq yeah-data-home %S) %s "
                         "(yeah-acp-serve #'yeah-check--transport))")
                data-home (yeah-check--transport-source))))

(defun yeah-check--socket-command (data-home socket)
  "Return the argv of the ACP server that serves on SOCKET.
DATA-HOME is the data home of the server process."
  (list (yeah-check--emacs) "-Q" "--batch"
        "-L" (yeah-check--lib-directory)
        "-l" "yeah-acp"
        "--eval"
        (format (concat "(progn (setq yeah-data-home %S) %s "
                         "(yeah-acp-serve-socket %S #'yeah-check--transport))")
                data-home (yeah-check--transport-source) socket)))

(defun yeah-check--start (command)
  "Start the server process with COMMAND and return it.
The output of the server is collected in one buffer, so that the client
reads the messages of the server in the order the server wrote them."
  (setq yeah-check--buffer (generate-new-buffer "*yeah-server-exit*"))
  (with-current-buffer yeah-check--buffer
    (setq-local yeah-check--position (point-min)))
  (make-process :name "yeah-server-exit"
                :buffer yeah-check--buffer
                :command command
                :connection-type 'pipe
                :noquery t
                :filter (lambda (_process chunk)
                          (with-current-buffer yeah-check--buffer
                            (insert chunk)))))

(defun yeah-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (< (float-time) deadline) (not (funcall predicate)))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-check--send (process object)
  "Send OBJECT as one JSON line to PROCESS."
  (process-send-string process (concat (json-serialize object) "\n")))

(defun yeah-check--messages ()
  "Return the messages the server sent and that were not consumed yet.
A line that is not complete yet is not a message: the server writes a
message whole."
  (with-current-buffer yeah-check--buffer
    (goto-char yeah-check--position)
    (let (messages)
      (while (re-search-forward "^\\(.+\\)\n" nil t)
        (setq yeah-check--position (match-end 0))
        (push (condition-case nil
                  (json-parse-string (match-string 1) :object-type 'plist
                                     :array-type 'list)
                (error nil))
              messages))
      (nreverse messages))))

(defun yeah-check--await-result (id &optional timeout)
  "Wait for the answer with ID and return its result, or nil."
  (let ((result nil))
    (yeah-check--await
     (lambda ()
       (dolist (message (yeah-check--messages))
         (when (and message (equal id (plist-get message :id)))
           (setq result (plist-get message :result))))
       result)
     timeout)
    result))

(defun yeah-check--await-error (id &optional timeout)
  "Wait for the error with ID and return its message, or nil."
  (let ((failure nil))
    (yeah-check--await
     (lambda ()
       (dolist (message (yeah-check--messages))
         (when (and message (equal id (plist-get message :id)))
           (let ((error (plist-get message :error)))
             (when error
               (setq failure (if (listp error)
                                 (plist-get error :message)
                               error))))))
       failure)
     timeout)
    failure))

(defun yeah-check--close-session (process id session-id)
  "Ask PROCESS to close the session SESSION-ID and wait for the answer.
ID is the id of the request.  Return the answer of the server, or nil."
  (yeah-check--send
   process
   (list :jsonrpc "2.0" :id id :method "session/close"
         :params (list :sessionId session-id)))
  (yeah-check--await-result id 20))

(defun yeah-check--stdio-case (data-home)
  "Run the case of the server over stdio with DATA-HOME as its data home.
The client keeps the pipe open while it waits for the death of the
server: the pipe is what the defect is about."
  (let* ((process (yeah-check--start (yeah-check--stdio-command data-home)))
         (session-id nil))
    (unwind-protect
        (progn
          ;; the handshake
          (yeah-check--send
           process
           (list :jsonrpc "2.0" :id 1 :method "initialize"
                 :params (list :protocolVersion 1 :clientCapabilities (list))))
          (unless (yeah-check--await-result 1 20)
            (push "the handshake was not answered" yeah-check--failures))
          ;; a session
          (yeah-check--send
           process
           (list :jsonrpc "2.0" :id 2 :method "session/new"
                 :params (list :cwd data-home :mcpServers nil)))
          (let ((session (yeah-check--await-result 2 20)))
            (setq session-id (plist-get session :sessionId))
            (unless session-id
              (push "the session was not created" yeah-check--failures)))
          ;; a turn: the client has work to do, and the server answers it
          (when session-id
            (yeah-check--send
             process
             (list :jsonrpc "2.0" :id 3 :method "session/prompt"
                   :params (list :sessionId session-id
                                 :prompt (vector (list :type "text"
                                                       :text "hello")))))
            (let ((answer (yeah-check--await-result 3 30)))
              (unless (equal "end_turn" (plist-get answer :stopReason))
                (push (format "the turn did not end: %S" answer)
                      yeah-check--failures))))
          ;; the client closes the session, and keeps the pipe open
          (unless (yeah-check--close-session process 4 session-id)
            (push "the server did not answer the request that closes the session"
                  yeah-check--failures))
          ;; the process of the server must be gone within ten seconds
          (yeah-check--await (lambda () (not (process-live-p process))) 10)
          (when (process-live-p process)
            (push (format "the server is still alive ten seconds after the end of its session (pid %s)"
                          (process-id process))
                  yeah-check--failures))
          ;; the server ended and did not crash
          (unless (process-live-p process)
            (accept-process-output nil 0.2)
            (let ((status (process-exit-status process)))
              (when (and status (not (= 0 status)))
                (push (format "the server ended with the code %s instead of ending its session"
                              status)
                      yeah-check--failures)))))
      (when (process-live-p process)
        (ignore-errors (delete-process process))))))

(defun yeah-check--connect (socket)
  "Connect to the server on SOCKET and return the connection.
The connection is retried until the server is listening."
  (let ((deadline (+ (float-time) 10))
        (connection nil))
    (while (and (null connection) (< (float-time) deadline))
      (setq connection
            (condition-case nil
                (make-network-process
                 :name "yeah-server-exit-client"
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

(defun yeah-check--socket-case (data-home)
  "Run the case of the server over a socket with DATA-HOME as its data home.
The server serves many clients: the end of the session of one of them
must not end the server."
  (let* ((socket (expand-file-name "yeah-server-exit.sock" data-home))
         (process (yeah-check--start (yeah-check--socket-command data-home socket)))
         (connection nil))
    (unwind-protect
        (progn
          (setq connection (yeah-check--connect socket))
          (unless connection
            (push "the client could not reach the server over the socket"
                  yeah-check--failures))
          (when connection
            ;; the handshake
            (yeah-check--send
             connection
             (list :jsonrpc "2.0" :id 1 :method "initialize"
                   :params (list :protocolVersion 1 :clientCapabilities (list))))
            (unless (yeah-check--await-result 1 20)
              (push "the socket server did not answer the handshake"
                    yeah-check--failures))
            ;; a session
            (yeah-check--send
             connection
             (list :jsonrpc "2.0" :id 2 :method "session/new"
                   :params (list :cwd data-home :mcpServers nil)))
            (let* ((session (yeah-check--await-result 2 20))
                   (session-id (plist-get session :sessionId)))
              (unless session-id
                (push "the socket server did not create the session"
                      yeah-check--failures))
              ;; the client closes the session
              (unless (yeah-check--close-session connection 3 session-id)
                (push "the socket server did not answer the request that closes the session"
                      yeah-check--failures))
              ;; the server keeps serving: it is the server of many clients
              (yeah-check--await (lambda () nil) 3)
              (unless (process-live-p process)
                (push "the server over a socket ended with the session of one client"
                      yeah-check--failures))
              ;; and it still answers the client that is still there
              (yeah-check--send
               connection
               (list :jsonrpc "2.0" :id 4 :method "initialize"
                     :params (list :protocolVersion 1 :clientCapabilities (list))))
              (unless (yeah-check--await-result 4 20)
                (push "the server over a socket stopped serving its clients"
                      yeah-check--failures))
              ;; the session that is over does not answer a prompt anymore
              (yeah-check--send
               connection
               (list :jsonrpc "2.0" :id 5 :method "session/prompt"
                     :params (list :sessionId session-id
                                   :prompt (vector (list :type "text"
                                                         :text "hello")))))
              (let ((failure (yeah-check--await-error 5 20)))
                (unless failure
                  (push "the session that was over answered a prompt"
                        yeah-check--failures))))))
      (when connection
        (ignore-errors (delete-process connection)))
      (when (process-live-p process)
        (ignore-errors (delete-process process))))))

(let ((data-home (make-temp-file "yeah-server-exit" t))
      (socket-home (make-temp-file "yeah-server-exit-socket" t)))
  (unwind-protect
      (progn
        (yeah-check--stdio-case data-home)
        (yeah-check--socket-case socket-home))
    (dolist (failure yeah-check--failures)
      (message "server-exit: %s" failure))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory socket-home t))
    (if yeah-check--failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-the-server-exits-when-the-session-is-over.el ends here
