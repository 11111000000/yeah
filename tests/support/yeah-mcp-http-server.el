;;; yeah-mcp-http-server.el --- an MCP server over HTTP for the checks -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The check of the MCP servers of a session over HTTP needs a server that
;; speaks the transport of MCP over HTTP: a POST, and an answer that is a
;; stream of events (SSE) and comes in pieces.
;;
;; The server of this file is the shape of the server of the orchestrator
;; Paseo: it keeps no state between the requests, it answers with the stream
;; of the events, and it names the pieces of the answer.  The check reads the
;; answer of the tool and sees two things at once: the call of the model
;; reached the server, and the header the client named reached the server
;; too.
;;
;; The server runs in the process of the check and not in a process of its
;; own: the check has to know the port, and the port of a process of its own
;; is a port the check has to wait for.

;;; Code:

(require 'json)

(defconst yeah-mcp-http-server--protocol-version "2025-06-18"
  "The MCP protocol version this server speaks.")

(defconst yeah-mcp-http-server--name "yeah-check-http"
  "The name this server gives itself.")

(defvar yeah-mcp-http-server--requests (make-hash-table :test 'eq)
  "The text of the request that each client of the server sent.")

(defun yeah-mcp-http-server--tool ()
  "Return the description of the one tool of this server.
The properties of the schema are an object and the names of the required
ones are an array: that is the shape of the schema of MCP, and
`json-serialize' writes an object only for a hash table."
  (let ((properties (make-hash-table :test #'equal)))
    (puthash "text" (list :type "string") properties)
    (list :name "echo"
          :description "Answer with the text that was given and with the header."
          :inputSchema (list :type "object"
                             :properties properties
                             :required (vector "text")))))

(defun yeah-mcp-http-server--argument (arguments name)
  "Return the value of the argument NAME of ARGUMENTS.
ARGUMENTS arrive as data: an object of the wire is read as a plist with
keyword keys, and a caller that built it by hand may send an alist.  Both
are read."
  (or (plist-get arguments (intern (concat ":" name)))
      (let ((cell (assoc name arguments)))
        (and cell (cdr cell)))))

(defun yeah-mcp-http-server--header (headers name)
  "Return the value of the header NAME of HEADERS, or nil."
  (cdr (assoc (downcase name) headers)))

(defun yeah-mcp-http-server--call (params headers)
  "Return the answer of the tool named in PARAMS.
The answer names the text the model gave and the header the client named:
the check reads the answer and sees that both arrived."
  (let* ((arguments (plist-get params :arguments))
         (text (or (yeah-mcp-http-server--argument arguments "text") ""))
         (token (or (yeah-mcp-http-server--header headers "x-check-token")
                    "none")))
    (list :content (vector (list :type "text"
                                 :text (format "echo: %s; env: %s"
                                               text token)))
          :isError :false)))

(defun yeah-mcp-http-server--response (id result)
  "Return the answer of the request ID with RESULT."
  (list :jsonrpc "2.0" :id id :result result))

(defun yeah-mcp-http-server--error (id message)
  "Answer the request ID with the error MESSAGE."
  (list :jsonrpc "2.0" :id id :error (list :code -32601 :message message)))

(defun yeah-mcp-http-server--dispatch (method params id headers)
  "Answer the request METHOD with PARAMS under the id ID."
  (pcase method
    ("initialize"
     (yeah-mcp-http-server--response
      id (list :protocolVersion yeah-mcp-http-server--protocol-version
               :capabilities (list :tools (list :listChanged :false))
               :serverInfo (list :name yeah-mcp-http-server--name :version "0.0.0"))))
    ("tools/list"
     (yeah-mcp-http-server--response id (list :tools (vector (yeah-mcp-http-server--tool)))))
    ("tools/call"
     (yeah-mcp-http-server--response id (yeah-mcp-http-server--call params headers)))
    (_ (yeah-mcp-http-server--error id (format "Method not found: %s" method)))))

(defun yeah-mcp-http-server--headers (lines)
  "Return the headers of the request LINES as an alist of a name and a value."
  (let (headers)
    (dolist (line lines)
      (when (string-match "^\\([^:]+\\):[ \t]*\\(.*\\)$" line)
        (push (cons (downcase (string-trim (match-string 1 line)))
                    (string-trim (match-string 2 line)))
              headers)))
    (nreverse headers)))

(defun yeah-mcp-http-server--answer (process headers body)
  "Answer the request BODY with the headers HEADERS to the client PROCESS."
  (let ((object (condition-case nil
                    (json-parse-string body :object-type 'plist :array-type 'list)
                  (error nil))))
    (when object
      (let* ((response (yeah-mcp-http-server--dispatch
                        (plist-get object :method)
                        (plist-get object :params)
                        (plist-get object :id)
                        headers))
             (event (format "event: message\ndata: %s\n\n" (json-serialize response)))
             (bytes (string-bytes event)))
        (process-send-string
         process
         (concat "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nTransfer-Encoding: chunked\r\n\r\n"
                 (format "%x\r\n" bytes) event "\r\n0\r\n\r\n"))))))

(defun yeah-mcp-http-server--filter (process chunk)
  "Read the CHUNK that the client PROCESS sent and answer it."
  (let* ((buffer (concat (gethash process yeah-mcp-http-server--requests) chunk))
         (end (string-search "\r\n\r\n" buffer)))
    (puthash process buffer yeah-mcp-http-server--requests)
    (when end
      (let* ((head (substring buffer 0 end))
             (lines (split-string head "\r\n"))
             (headers (yeah-mcp-http-server--headers (cdr lines)))
             (length (yeah-mcp-http-server--header headers "content-length"))
             (start (+ end 4))
             (size (if length (string-to-number length) 0)))
        (when (>= (length buffer) (+ start size))
          (remhash process yeah-mcp-http-server--requests)
          (yeah-mcp-http-server--answer
           process headers (substring buffer start (+ start size))))))))

(defun yeah-mcp-http-server-start ()
  "Start the MCP server of the checks and return the process that serves.
The server keeps no state between the requests, the way the server of the
orchestrator Paseo keeps none."
  (make-network-process
   :name "yeah-mcp-http-server"
   :server t
   :host "127.0.0.1"
   :service t
   :family 'ipv4
   :coding 'binary
   :noquery t
   :filter #'yeah-mcp-http-server--filter))

(defun yeah-mcp-http-server-port (server)
  "Return the port the server SERVER of the checks listens on."
  (process-contact server :service))

(defun yeah-mcp-http-server-stop (server)
  "Stop the server SERVER of the checks."
  (when (process-live-p server)
    (delete-process server)))

(provide 'yeah-mcp-http-server)
;;; yeah-mcp-http-server.el ends here
