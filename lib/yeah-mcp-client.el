;;; yeah-mcp-client.el --- MCP client for foreign tool servers -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A small MCP client: connect to a server over stdio, list its tools, call
;; them, and import them into Yeah's registry under a namespaced name.  The
;; permission system applies to imported tools exactly as it applies to local
;; ones, because the imported tool is an ordinary registry entry.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-tools)

(defgroup yeah-mcp-client nil
  "Yeah MCP client."
  :group 'yeah)

(cl-defstruct (yeah-mcp-client (:constructor yeah-mcp-client--make))
  "One connection to a foreign MCP server.
PROCESS is the server process.  PENDING maps request ids to callbacks.
INPUT holds the incomplete line being read.  TOOLS caches the tool
descriptions the server published.  INITIALIZED and LISTED say how far
the handshake with the server went: a server that answers the handshake
late is still a server that answered."
  name
  process
  pending
  counter
  input
  tools
  initialized
  listed)

(defun yeah-mcp-client--dispatch (client object)
  "Deliver parsed OBJECT to the pending callback of CLIENT."
  (let* ((id (plist-get object :id))
         (callback (and id (gethash id (yeah-mcp-client-pending client)))))
    (when callback
      (remhash id (yeah-mcp-client-pending client))
      (funcall callback object))))

(defun yeah-mcp-client--filter (client chunk)
  "Accumulate CHUNK from CLIENT and dispatch complete JSON lines."
  (let ((pending (concat (or (yeah-mcp-client-input client) "") chunk)))
    (let ((start 0) pos)
      (while (setq pos (string-search "\n" pending start))
        (let* ((line (substring pending start pos))
               (object (condition-case nil
                           (json-parse-string line :object-type 'plist
                                              :array-type 'list)
                         (error nil))))
          (when object
            (yeah-mcp-client--dispatch client object)))
        (setq start (1+ pos)))
      (setf (yeah-mcp-client-input client) (substring pending start)))))

(defun yeah-mcp-client--command (command args env)
  "Return the command line of the server: COMMAND with ARGS and the variables ENV.
ENV is an alist of pairs of a name and a value.  Emacs gives a process no
environment of its own, so the variables are set by the program `env',
which the harness has on every system it runs on.  The server inherits
the rest: a server that inherits nothing finds neither its own runtime
nor its home, and the client named only the variables it adds."
  (if env
      (append (list (or (executable-find "env") "env"))
              (mapcar (lambda (pair)
                        (format "%s=%s" (car pair) (cdr pair)))
                      env)
              (list command)
              args)
    (cons command args)))

(defun yeah-mcp-client-connect (name command &optional args env)
  "Connect to the MCP server COMMAND with ARGS and return the client.
NAME identifies the server in imported tool names.
ENV is an alist of the environment variables the server process gets on
top of the ones it inherits."
  (unless (commandp command)
    (signal 'user-error (list "yeah-mcp-client-connect: command must be a program")))
  (let* ((client (yeah-mcp-client--make
                   :name name
                   :pending (make-hash-table :test 'equal)
                   :counter 0
                   :tools nil))
         (process (make-process
                   :name (format "yeah-mcp-client-%s" name)
                   :command (yeah-mcp-client--command command args env)
                   :connection-type 'pipe
                   :noquery t
                   :filter (lambda (_process chunk)
                             (yeah-mcp-client--filter client chunk))
                   :sentinel (lambda (_process event)
                             (message "yeah-mcp-client: %s ended (%s)"
                                      name event)))))
    (setf (yeah-mcp-client-process client) process)
    client))

(defun yeah-mcp-client-close (client)
  "Close CLIENT's server process."
  (when-let ((process (yeah-mcp-client-process client)))
    (when (process-live-p process)
      (delete-process process)))
  client)

(defun yeah-mcp-client-request (client method params callback)
  "Send METHOD with PARAMS to CLIENT and deliver the answer to CALLBACK.
CALLBACK receives the parsed response object."
  (unless (functionp callback)
    (signal 'user-error (list "yeah-mcp-client-request: invalid callback")))
  (let* ((id (format "req-%d" (1+ (yeah-mcp-client-counter client))))
         (text (concat
                (json-serialize
                 (list :jsonrpc "2.0" :id id :method method :params params))
                "\n")))
    (setf (yeah-mcp-client-counter client) (1+ (yeah-mcp-client-counter client)))
    (puthash id callback (yeah-mcp-client-pending client))
    (process-send-string
     (yeah-mcp-client-process client)
     text)
    id))

(defun yeah-mcp-client-initialize (client &optional callback)
  "Send the MCP initialize handshake to CLIENT.
CALLBACK receives the parsed response, or nil when not given."
  (yeah-mcp-client-request
   client "initialize"
   (list :protocolVersion "2025-06-18"
         :capabilities (make-hash-table :test 'equal)
         :clientInfo (list :name "yeah" :version "0.1.0-alpha"))
   (lambda (object)
     (setf (yeah-mcp-client-initialized client) t)
     (when callback
       (funcall callback object)))))

(defun yeah-mcp-client-initialized-p (client)
  "Return non-nil when CLIENT answered the initialize handshake."
  (and (yeah-mcp-client-initialized client) t))

(defun yeah-mcp-client-list-tools (client &optional callback)
  "Ask CLIENT's server for its tools, cache them and deliver them to CALLBACK.
CALLBACK receives the parsed response object; the tool list is always cached."
  (yeah-mcp-client-request
   client "tools/list" nil
   (lambda (object)
     (let ((tools (plist-get (plist-get object :result) :tools)))
       (setf (yeah-mcp-client-tools client) (append tools nil))
       (setf (yeah-mcp-client-listed client) t)
       (when callback
         (funcall callback object))
       tools))))

(defun yeah-mcp-client-listed-p (client)
  "Return non-nil when CLIENT answered the request for its tools."
  (and (yeah-mcp-client-listed client) t))

(defun yeah-mcp-client-call-tool (client name arguments &optional callback)
  "Call tool NAME with the argument object ARGUMENTS on CLIENT's server.
CALLBACK receives the MCP result object."
  (yeah-mcp-client-request
   client "tools/call"
   (list :name name :arguments (or arguments nil))
   (or callback (lambda (_object) nil))))

(defun yeah-mcp-client--result-text (result)
  "Return the text of the first content block of RESULT.
CONTENT may be a JSON array (list) or a vector."
  (let* ((content (plist-get result :content))
         (block (cond ((vectorp content) (aref content 0))
                      ((listp content) (car content))
                      (t nil))))
    (or (plist-get block :text) "")))

(defun yeah-mcp-client--property-names (schema)
  "Return the names of the properties of SCHEMA, in a stable order.
The properties arrive as a plist when the answer of the server was read
as data, and as a hash table when a caller built them by hand; both
are read, because a tool that loses its properties is a tool the model
cannot give anything to."
  (let ((properties (plist-get schema :properties)))
    (cond ((hash-table-p properties)
           (sort (hash-table-keys properties) #'string<))
          ((and (listp properties) (keywordp (car properties)))
           ;; The order of the schema is the order of the arguments.  The name
           ;; of a keyword carries its colon, and the name of an argument does
           ;; not.
           (let (names)
             (while properties
               (push (string-remove-prefix ":" (symbol-name (car properties)))
                     names)
               (setq properties (cddr properties)))
             (nreverse names)))
          ((listp properties)
           (sort (mapcar (lambda (cell) (format "%s" (car cell))) properties)
                 #'string<))
          (t '()))))

(defun yeah-mcp-client--property-schema (schema name)
  "Return the schema of the property NAME of SCHEMA.
The properties of a schema arrive as a plist with keyword keys, as a hash
table, or as an alist; all three are read."
  (let ((properties (plist-get schema :properties)))
    (cond ((hash-table-p properties)
           (gethash name properties))
          ((listp properties)
           (or (plist-get properties (intern (concat ":" name)))
               (cdr (assoc name properties))))
          (t nil))))

(defun yeah-mcp-client--argument-type (schema)
  "Return the type Yeah gives the property SCHEMA.
The type of MCP is a string on the wire (`string', `integer', `boolean'),
and the type of a tool of Yeah is a symbol.  A property of a type that
Yeah does not know takes any value."
  (let ((type (plist-get schema :type)))
    (cond ((equal type "string") 'string)
          ((equal type "integer") 'integer)
          ((equal type "boolean") 'boolean)
          (t t))))

(defun yeah-mcp-client--input (schema)
  "Return the input parameters of the remote tool with SCHEMA.
The parameters are the ones of a tool of Yeah: a name and a type.  A
tool of a server is an ordinary tool of the registry, and the registry
knows no other shape."
  (mapcar (lambda (name)
            (list :name name
                  :type (yeah-mcp-client--argument-type
                         (yeah-mcp-client--property-schema schema name))))
          (yeah-mcp-client--property-names schema)))

(defun yeah-mcp-client--arguments-object (schema args)
  "Return the argument object built from ARGS using SCHEMA's property order.
The object is a hash table with string keys: that is a JSON object in
`json-serialize', while an alist of string keys is not -- the keys of an
alist must be symbols."
  (let ((object (make-hash-table :test #'equal))
        (index 0))
    (dolist (name (yeah-mcp-client--property-names schema))
      (when (< index (length args))
        (puthash name (nth index args) object))
      (setq index (1+ index)))
    object))

(defun yeah-mcp-client-tool-spec (client tool &optional prefix)
  "Return the specification of the remote TOOL of CLIENT.
The name of the tool is `mcp--<server>--<tool>'; PREFIX replaces the
server part.  The tool is asynchronous: the answer of the server comes
later, and the run waits for it."
  (let* ((remote (plist-get tool :name))
         (schema (plist-get tool :inputSchema))
         (local (format "mcp--%s--%s"
                        (or prefix (yeah-mcp-client-name client))
                        remote)))
    (list :name local
          :description (format "Remote MCP tool %s: %s"
                               remote (or (plist-get tool :description) ""))
          :input (yeah-mcp-client--input schema)
          :async t
          :concurrency 'shared
          :handler
          (lambda (args done)
            (yeah-mcp-client-call-tool
             client remote
             (yeah-mcp-client--arguments-object schema args)
             (lambda (object)
               (funcall done
                        (yeah-mcp-client--result-text
                         (plist-get object :result)))))))))

(defun yeah-mcp-client-tool-specs (client &optional prefix)
  "Return the specifications of the tools of CLIENT.
The tools are not registered anywhere: the caller decides where they
live, because a tool of a server of a session belongs to that session
and to no other."
  (mapcar (lambda (tool)
            (yeah-mcp-client-tool-spec client tool prefix))
          (yeah-mcp-client-tools client)))

(defun yeah-mcp-client-import-tools (client &optional prefix)
  "Import the tools of CLIENT into Yeah's registry.
Names are `mcp--<server>--<tool>'.  PREFIX replaces the server part.
Return the list of imported names."
  (let (imported)
    (dolist (spec (yeah-mcp-client-tool-specs client prefix))
      (yeah-tools-register spec)
      (push (plist-get spec :name) imported))
    (nreverse imported)))

(provide 'yeah-mcp-client)
;;; yeah-mcp-client.el ends here
