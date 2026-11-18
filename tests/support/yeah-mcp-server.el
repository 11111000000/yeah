;;; yeah-mcp-server.el --- a small MCP server for the checks -*- lexical-binding: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A small MCP server for the checks of the MCP servers of a session.  It
;; speaks the newline-delimited JSON-RPC of MCP over stdio: it answers the
;; handshake, publishes one tool, and answers the calls of that tool.
;;
;; The tool is `echo': it answers with the text it was given and with the
;; value of the variable `YEAH_CHECK_ENV'.  A check that reads the answer
;; sees two things at once: the call of the model reached the server, and
;; the environment the client named reached the server too.
;;
;; The server is a script and not a function of the kernel: it runs in a
;; process of its own, the way a server of a client runs.
;;
;; The answers leave the process at once: the stdout of a batch Emacs is not
;; buffered a line at a time, the way the stdout of C is.  There is nothing to
;; flush and nothing to flush it with: Emacs 30 has neither `force-output' nor
;; `flush-output', neither as a function nor as a macro.

;;; Code:

(require 'json)

(defconst yeah-mcp-server--protocol-version "2025-06-18"
  "The MCP protocol version this server speaks.")

(defconst yeah-mcp-server--name "yeah-check"
  "The name this server gives itself.")

(defun yeah-mcp-server--emit (object)
  "Write OBJECT as one JSON line on standard output."
  (princ (json-serialize object))
  (terpri))

(defun yeah-mcp-server--response (id result)
  "Answer the request ID with RESULT."
  (yeah-mcp-server--emit (list :jsonrpc "2.0" :id id :result result)))

(defun yeah-mcp-server--error (id message)
  "Answer the request ID with the error MESSAGE."
  (yeah-mcp-server--emit
   (list :jsonrpc "2.0" :id id :error (list :code -32601 :message message))))

(defun yeah-mcp-server--tool ()
  "Return the description of the one tool of this server.
The properties of the schema are an object and the names of the required
ones are an array: that is the shape of the schema of MCP, and
`json-serialize' writes an object only for a hash table."
  (let ((properties (make-hash-table :test #'equal)))
    (puthash "text" (list :type "string") properties)
    (list :name "echo"
          :description "Answer with the text that was given and with the environment."
          :inputSchema (list :type "object"
                             :properties properties
                             :required (vector "text")))))

(defun yeah-mcp-server--argument (arguments name)
  "Return the value of the argument NAME of ARGUMENTS.
ARGUMENTS arrive as data: an object of the wire is read as a plist with
keyword keys, and a caller that built it by hand may send an alist.  Both
are read.  The key of the plist is a keyword, and a keyword of a name is
the name with a colon in front of it."
  (or (plist-get arguments (intern (concat ":" name)))
      (let ((cell (assoc name arguments)))
        (and cell (cdr cell)))))

(defun yeah-mcp-server--call (params)
  "Return the answer of the tool named in PARAMS."
  (let* ((arguments (plist-get params :arguments))
         (text (or (yeah-mcp-server--argument arguments "text") ""))
         (environment (getenv "YEAH_CHECK_ENV")))
    (list :content (vector (list :type "text"
                                 :text (format "echo: %s; env: %s"
                                               text (or environment "none"))))
          :isError :false)))

(defun yeah-mcp-server--dispatch (method params id)
  "Answer the request METHOD with PARAMS under the id ID."
  (pcase method
    ("initialize"
     (yeah-mcp-server--response
      id (list :protocolVersion yeah-mcp-server--protocol-version
               :capabilities (list :tools (list :listChanged :false))
               :serverInfo (list :name yeah-mcp-server--name :version "0.0.0"))))
    ("tools/list"
     (yeah-mcp-server--response id (list :tools (vector (yeah-mcp-server--tool)))))
    ("tools/call"
     (yeah-mcp-server--response id (yeah-mcp-server--call params)))
    (_ (yeah-mcp-server--error id (format "Method not found: %s" method)))))

(defun yeah-mcp-server--handle (line)
  "Answer the request in LINE."
  (let ((object (condition-case nil
                    (json-parse-string line :object-type 'plist :array-type 'list)
                  (error nil))))
    (when object
      (yeah-mcp-server--dispatch (plist-get object :method)
                                 (plist-get object :params)
                                 (plist-get object :id)))))

(defun yeah-mcp-server--read-line ()
  "Read one line from standard input, or nil at end of file."
  (condition-case nil
      (let ((line (read-string "")))
        (if (or (null line) (string= line "")) nil line))
    (error nil)))

;;;###autoload
(defun yeah-mcp-server-serve ()
  "Serve MCP on standard input until end of file."
  (let ((line nil))
    (while (setq line (yeah-mcp-server--read-line))
      (yeah-mcp-server--handle line)))
  nil)

(provide 'yeah-mcp-server)
;;; yeah-mcp-server.el ends here
