;;; yeah-mcp.el --- MCP server over stdio -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Model Context Protocol server exposing the `emacs__*' tools of
;; `lib/yeah-emcp.el' over newline-delimited JSON-RPC 2.0 on stdio.  The
;; published surface is read-only unless the operator widens it.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-emcp)
(require 'yeah-wire)
(require 'yeah-wire-socket)

(defgroup yeah-mcp nil
  "Yeah MCP server."
  :group 'yeah)

(defconst yeah-mcp--protocol-version "2025-06-18"
  "MCP protocol version spoken by Yeah.")

(defconst yeah-mcp--server-name "yeah")

(defconst yeah-mcp--server-version "0.1.0-alpha")

(defvar yeah-mcp--output-function #'yeah-mcp--print-line
  "Function receiving one serialized JSON message per call.")

(defun yeah-mcp--print-line (text)
  "Write TEXT and a newline to standard output."
  (princ text)
  (terpri))

(defun yeah-mcp--emit (object)
  "Serialize OBJECT and pass it to `yeah-mcp--output-function'."
  (funcall yeah-mcp--output-function (json-serialize object)))

(defun yeah-mcp--response (id result)
  "Return a JSON-RPC response string for ID and RESULT."
  (json-serialize (list :jsonrpc "2.0" :id id :result result)))

(defun yeah-mcp--error (id code message)
  "Return a JSON-RPC error response string for ID, CODE and MESSAGE."
  (json-serialize (list :jsonrpc "2.0" :id id
                         :error (list :code code :message message))))

(defun yeah-mcp--schema-properties (spec)
  "Return the JSON schema properties of tool SPEC."
  (let ((properties (make-hash-table :test 'equal)))
    (dolist (param (plist-get spec :input))
      (puthash param
               (list :type "string"
                     :description (format "the %s argument" param))
               properties))
    properties))

(defun yeah-mcp--tool-schema (spec)
  "Return the MCP input schema for tool SPEC."
  (list :type "object"
        :properties (yeah-mcp--schema-properties spec)
        :required (vconcat (plist-get spec :input))))

(defun yeah-mcp--tool-description (id)
  "Return the MCP description of the published tool ID."
  (let ((spec (yeah-emcp-tool-spec id)))
    (list :name id
          :description (plist-get spec :description)
          :inputSchema (yeah-mcp--tool-schema spec))))

(defun yeah-mcp--tools ()
  "Return the published tool descriptions."
  (mapcar #'yeah-mcp--tool-description (yeah-emcp-published-ids)))

(defun yeah-mcp--arguments-from-hash (table)
  "Return the argument list of the hash TABLE."
  (let ((args nil))
    (maphash
     (lambda (key value)
       (setq args (append args (list (intern key) value))))
     table)
    args))

(defun yeah-mcp--arguments-from-list (cells)
  "Return the argument list of the alist CELLS."
  (let ((args nil))
    (dolist (cell cells)
      (when (and (consp cell) (stringp (car cell)))
        (setq args (append args (list (intern (car cell)) (cdr cell))))))
    args))

(defun yeah-mcp--arguments (object)
  "Return the MCP argument OBJECT as a list of keys and values."
  (cond
   ((hash-table-p object) (yeah-mcp--arguments-from-hash object))
   ((listp object) (yeah-mcp--arguments-from-list object))
   (t nil)))

(defun yeah-mcp--call (params)
  "Run the tool named in PARAMS and return the MCP result object."
  (let ((name (plist-get params :name)))
    (unless (and name (yeah-emcp-tool-spec name))
      (signal 'user-error (list (format "unknown tool: %s" name))))
    (let ((arguments (yeah-mcp--arguments (plist-get params :arguments))))
      (condition-case err
          (let ((text (yeah-emcp-handle-call name arguments)))
            (list :content (vector (list :type "text" :text (format "%s" text)))
                  :isError :false))
        (error
         (list :content (vector (list :type "text"
                                     :text (error-message-string err)))
               :isError t))))))

(defun yeah-mcp--initialize-result ()
  "Return the MCP initialize result object."
  (list :protocolVersion yeah-mcp--protocol-version
        :capabilities (list :tools (make-hash-table :test 'equal))
        :serverInfo (list :name yeah-mcp--server-name
                           :version yeah-mcp--server-version)))

(defun yeah-mcp--dispatch (method params id)
  "Dispatch MCP METHOD with PARAMS and request ID."
  (cond
   ((equal method "initialize")
    (yeah-mcp--response id (yeah-mcp--initialize-result)))
   ((equal method "ping")
    (yeah-mcp--response id (make-hash-table :test 'equal)))
   ((equal method "tools/list")
    (yeah-mcp--response id (list :tools (vconcat (yeah-mcp--tools)))))
   ((equal method "tools/call")
    (yeah-mcp--response id (yeah-mcp--call params)))
   (t
    (yeah-mcp--error id -32601 (format "Method not found: %s" method)))))

(defun yeah-mcp--parse (json-string)
  "Parse JSON-STRING into a plist."
  (json-parse-string json-string :object-type 'plist :array-type 'list))

(defun yeah-mcp-handle-message (json-string)
  "Handle one MCP JSON-RPC message and return a response string or nil."
  (let ((parsed (condition-case nil
                    (yeah-mcp--parse json-string)
                  (error nil))))
    (if (null parsed)
        (yeah-mcp--error nil -32700 "Parse error")
      (let* ((method (plist-get parsed :method))
             (id (plist-get parsed :id))
             (params (or (plist-get parsed :params) '())))
        (cond
         ((not (stringp method))
          (yeah-mcp--error id -32600 "Invalid Request: no method"))
         ((null id) nil)
         (t
          (condition-case err
              (yeah-mcp--dispatch method params id)
            (user-error
             (yeah-mcp--error id -32602 (error-message-string err))))))))))

(defun yeah-mcp--read-line ()
  "Read one line from standard input, or nil at end of file."
  (yeah-wire-read-line))

;;;###autoload
(defun yeah-mcp-serve (&optional output-function)
  "Serve MCP over standard input/output until EOF.
OUTPUT-FUNCTION receives serialized JSON messages and defaults to stdout.
Between requests the server lets pending work settle so answers leave
without waiting for the next request."
  (setq yeah-mcp--output-function (or output-function #'yeah-mcp--print-line))
  (catch 'eof
    (while t
      (let ((line (yeah-mcp--read-line)))
        (unless line
          (throw 'eof nil))
        (unless (string-blank-p line)
          (let ((response (yeah-mcp-handle-message line)))
            (when response
              (funcall yeah-mcp--output-function response)))
          (yeah-wire-pump-until (lambda () t) 0.05)))))
  nil)

;;;###autoload
(defun yeah-mcp-serve-socket (service &optional family)
  "Serve MCP on the local socket SERVICE until the server stops.
FAMILY is `local' for a Unix socket and `ipv4' for a loopback TCP port.
Each connection is answered on its own connection."
  (yeah-wire-socket-serve
   service
   (lambda (line respond &optional _connection)
     (let ((response (yeah-mcp-handle-message line)))
       (when response
         (funcall respond response))))
   family))

(provide 'yeah-mcp)
;;; yeah-mcp.el ends here
