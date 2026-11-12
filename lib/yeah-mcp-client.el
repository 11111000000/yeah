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
descriptions the server published."
  name
  process
  pending
  counter
  input
  tools)

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

(defun yeah-mcp-client-connect (name command &optional args)
  "Connect to the MCP server COMMAND with ARGS and return the client.
NAME identifies the server in imported tool names."
  (unless (commandp command)
    (signal 'user-error (list "yeah-mcp-client-connect: command must be a program")))
  (let* ((client (yeah-mcp-client--make
                   :name name
                   :pending (make-hash-table :test 'equal)
                   :counter 0
                   :tools nil))
         (process (make-process
                   :name (format "yeah-mcp-client-%s" name)
                   :command (cons command args)
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
  (let* ((id (format "req-%d" (1+ (yeah-mcp-client-counter client)))))
    (setf (yeah-mcp-client-counter client) (1+ (yeah-mcp-client-counter client)))
    (puthash id callback (yeah-mcp-client-pending client))
    (process-send-string
     (yeah-mcp-client-process client)
     (concat
      (json-serialize
       (list :jsonrpc "2.0" :id id :method method :params params))
      "\n"))
    id))

(defun yeah-mcp-client-initialize (client &optional callback)
  "Send the MCP initialize handshake to CLIENT.
CALLBACK receives the parsed response, or nil when not given."
  (yeah-mcp-client-request
   client "initialize"
   (list :protocolVersion "2025-06-18"
         :capabilities (make-hash-table :test 'equal)
         :clientInfo (list :name "yeah" :version "0.1.0-alpha"))
   (or callback (lambda (_object) nil))))

(defun yeah-mcp-client-list-tools (client &optional callback)
  "Ask CLIENT's server for its tools, cache them and deliver them to CALLBACK.
CALLBACK receives the parsed response object; the tool list is always cached."
  (yeah-mcp-client-request
   client "tools/list" nil
   (lambda (object)
     (let ((tools (plist-get (plist-get object :result) :tools)))
       (setf (yeah-mcp-client-tools client) (append tools nil))
       (when callback
         (funcall callback object))
       tools))))

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

(defun yeah-mcp-client--arguments-object (schema args)
  "Return an argument alist built from ARGS using SCHEMA's property order."
  (let ((object nil)
        (properties (plist-get schema :properties))
        (index 0))
    (when (hash-table-p properties)
      (let ((names (sort (hash-table-keys properties) #'string<)))
        (dolist (name names)
          (when (< index (length args))
            (setq object (cons (cons name (nth index args)) object)))
          (setq index (1+ index)))))
    (nreverse object)))

(defun yeah-mcp-client-import-tools (client &optional prefix)
  "Import the tools of CLIENT into Yeah's registry.
Names are `mcp--<server>--<tool>'.  PREFIX replaces the server part.
Return the list of imported names."
  (let ((imported nil))
    (dolist (tool (yeah-mcp-client-tools client))
      (let* ((remote (plist-get tool :name))
             (schema (plist-get tool :inputSchema))
             (local (format "mcp--%s--%s"
                            (or prefix (yeah-mcp-client-name client))
                            remote)))
        (yeah-tools-register
         (list :name local
               :description (format "Remote MCP tool %s: %s"
                                    remote (plist-get tool :description))
               :input (mapcar (lambda (key)
                                (format "%s" key))
                              (let ((properties (plist-get schema :properties)))
                                (if (hash-table-p properties)
                                    (sort (hash-table-keys properties) #'string<)
                                  '())))
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
                              (plist-get object :result))))))))
        (push local imported)))
    (nreverse imported)))

(provide 'yeah-mcp-client)
;;; yeah-mcp-client.el ends here
