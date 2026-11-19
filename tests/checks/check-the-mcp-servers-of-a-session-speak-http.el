;;; check-the-mcp-servers-of-a-session-speak-http.el --- the MCP servers of a session speak HTTP -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The defect: the kernel spoke the stdio transport of MCP and no other, and
;; the orchestrator Paseo names its own MCP server over HTTP.  A client that
;; named such a server got a session that was refused by name, and no agent
;; of Yeah could run inside Paseo at all.
;;
;; This check starts a real ACP service on a socket, opens a session that
;; names an MCP server over HTTP, and proves three things on the wire:
;;
;; 1. `session/new' is answered, and not with an error, when the client names
;;    an MCP server over HTTP;
;; 2. the tools of the server reach the model: the model of the service finds
;;    the tool of the server among the tools of its run, and calls it;
;; 3. the call of the model reaches the server, and the header the client
;;    named reaches the server too.
;;
;; The server of the check is the shape of the server of Paseo: it keeps no
;; state, it answers with the stream of the events of MCP over HTTP, and it
;; names the pieces of the answer.  The model of the service is a fake (the
;; model is a FAKE).
;;
;; The verdict is decided by construction: the control of the claim takes the
;; answer of the server out of the transport, and the check then fails by its
;; own assertion.
;;
;; Exit codes: 0 -- the servers of HTTP speak to the model of the session;
;; 1 -- they did not.

;;; Code:

(require 'cl-lib)

(load (expand-file-name "tests/support/yeah-acp-mcp.el") nil t)
(load (expand-file-name "tests/support/yeah-mcp-http-server.el") nil t)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--answer-of (file)
  "Return the answer the model of the session wrote into FILE."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (buffer-string))))

(let* ((data-home (make-temp-file "yeah-mcp-http" t))
       (workspace (make-temp-file "yeah-mcp-http-work" t))
       (answer-file (expand-file-name "answer.txt" workspace))
       (text "the-text-the-model-gave")
       (name (format "yeah-mcp-http-%d" (random 1000000)))
       (server (yeah-mcp-http-server-start))
       (client nil)
       (questions nil)
       (updates nil))
  (unwind-protect
      (progn
        (yeah-acp-mcp--start name data-home)
        (let ((connection (yeah-acp-client-connect (yeah-service-socket-path name))))
          (setq client (nth 0 connection)
                questions (nth 1 connection)
                updates (nth 2 connection)))
        (let ((answer (yeah-acp-client-request client "initialize"
                                               (list :protocolVersion 1))))
          (unless (plist-get answer :result)
            (push "the handshake was not answered" yeah-check--failures)))
        ;; 1. the session is opened with an MCP server over HTTP
        (let* ((answer (yeah-acp-client-request
                        client "session/new"
                        (list :cwd workspace
                              :mcpServers (yeah-acp-mcp--http-servers
                                          (yeah-mcp-http-server-port server)))))
               (result (plist-get answer :result))
               (session-id (plist-get result :sessionId)))
          (when (plist-get answer :error)
            (push (format "the wire refused the session with an MCP server over HTTP: %S"
                          (plist-get answer :error))
                  yeah-check--failures))
          (unless (stringp session-id)
            (push "the session with an MCP server over HTTP was not answered with a session id"
                  yeah-check--failures))
          ;; 2 and 3: the model of the session uses the tool of the server
          (when session-id
            (let ((answer (yeah-acp-client-request
                           client "session/prompt"
                           (list :sessionId session-id
                                 :prompt
                                 (vector
                                  (list :type "text"
                                        :text
                                        (format "the answer of the MCP tool goes to the file %s; call the tool with the text %s"
                                                answer-file text))))))))
              (unless (plist-get answer :result)
                (push "the run of the session did not finish" yeah-check--failures)))
            (let ((written (yeah-check--answer-of answer-file)))
              (unless written
                (push "the model of the session did not use the tool of the server: no answer was written"
                      yeah-check--failures))
              (when written
                (unless (string-match-p "mcp--demo--echo" written)
                  (push (format "the tool of the MCP server did not reach the model of the session: %s"
                                written)
                        yeah-check--failures))
                (unless (string-match-p (format "echo: %s" text) written)
                  (push (format "the call of the model did not reach the MCP server: %s"
                                written)
                        yeah-check--failures))
                (unless (string-match-p
                         (format "env: %s" yeah-acp-mcp--token) written)
                  (push (format "the header the client named did not reach the MCP server: %s"
                                written)
                        yeah-check--failures))))
            ;; the client saw the call of the tool of the server
            (let ((calls (yeah-acp-client-tool-calls (funcall updates))))
              (unless (seq-some (lambda (call)
                                   (string-match-p "mcp--demo--echo"
                                                   (format "%s" (plist-get call :title))))
                                 calls)
                (push (format "the wire carried no call of the tool of the MCP server: %S"
                              (mapcar (lambda (call) (plist-get call :title)) calls))
                      yeah-check--failures)))))
    (when client (ignore-errors (yeah-client-close client)))
    (ignore-errors (yeah-service-stop name))
    (ignore-errors (yeah-mcp-http-server-stop server))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory workspace t)))
  (dolist (failure yeah-check--failures)
    (message "session-mcp-http: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0))))

;;; check-the-mcp-servers-of-a-session-speak-http.el ends here
