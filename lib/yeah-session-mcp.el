;;; yeah-session-mcp.el --- the MCP servers of a session -*- lexical-binding: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A client of ACP names the MCP servers it wants in `session/new' and in
;; `session/load'.  Until now the kernel checked that the array was an
;; array and threw it away: a client that named a server got a session
;; whose model could not use a single tool of it.
;;
;; This module connects to the servers the client names, asks them for
;; their tools, and turns those tools into ordinary entries of the
;; registry of the run of that session.  The permission system applies to
;; them as it applies to the local tools, because an imported tool is an
;; ordinary registry entry, and the model sees them among the others.
;;
;; Two transports are spoken: stdio and http.  A server of stdio is a
;; program the kernel starts, and a server of http is an address the kernel
;; asks over HTTP; the tools of both reach the model of the session the same
;; way.  The sse transport is not spoken: a server of another transport is
;; refused by name instead of being half-connected.

;;; Code:

(require 'cl-lib)
(require 'yeah-mcp-client)
(require 'yeah-tools)
(require 'yeah-wire)

(defgroup yeah-session-mcp nil
  "The MCP servers of a session."
  :group 'yeah)

(defcustom yeah-session-mcp-timeout 10
  "How long the kernel waits for the MCP servers of a session, in seconds.
A server that does not answer in this time is a server the session
cannot use: the session is refused rather than opened without the
tools the client asked for."
  :type 'number
  :group 'yeah-session-mcp)

(defun yeah-session-mcp--env (entries)
  "Return the environment variables of the MCP server ENTRIES.
ENTRIES is the `env' array of a server: a list of objects with a name
and a value."
  (mapcar (lambda (entry)
            (cons (plist-get entry :name) (plist-get entry :value)))
          (or entries '())))

(defun yeah-session-mcp--headers (entries)
  "Return the headers of the MCP server ENTRIES.
ENTRIES is the `headers' array of a server: a list of objects with a name
and a value.  The headers are the ones the client named, and a server of a
session often needs one of them to answer at all."
  (mapcar (lambda (entry)
            (cons (plist-get entry :name) (plist-get entry :value)))
          (or entries '())))

(defun yeah-session-mcp--stdio (name spec)
  "Return the description of the stdio MCP server NAME of SPEC."
  (let ((command (plist-get spec :command)))
    (unless (and (stringp command) (not (string-empty-p command)))
      (signal 'user-error
              (list (format "the MCP server %s needs a command" name))))
    (list :name name
          :transport :stdio
          :command command
          :args (copy-sequence (or (plist-get spec :args) '()))
          :env (yeah-session-mcp--env (plist-get spec :env)))))

(defun yeah-session-mcp--http (name spec)
  "Return the description of the http MCP server NAME of SPEC."
  (let ((url (plist-get spec :url)))
    (unless (and (stringp url) (not (string-empty-p url)))
      (signal 'user-error
              (list (format "the MCP server %s needs a url" name))))
    (list :name name
          :transport :http
          :url url
          :headers (yeah-session-mcp--headers (plist-get spec :headers)))))

(defun yeah-session-mcp--server (spec)
  "Return the description of the MCP server SPEC.
SPEC is one entry of the `mcpServers' array of a session request.
The stdio transport and the http transport are spoken: a client of ACP
names the server and the transport it speaks, and a server of another
transport is refused by name instead of being half-connected."
  (unless (listp spec)
    (signal 'user-error (list "an MCP server must be an object")))
  (let ((name (plist-get spec :name))
        (type (plist-get spec :type)))
    (unless (and (stringp name) (not (string-empty-p name)))
      (signal 'user-error (list "an MCP server needs a name")))
    (cond
     ((null type) (yeah-session-mcp--stdio name spec))
     ((equal type "stdio") (yeah-session-mcp--stdio name spec))
     ((equal type "http") (yeah-session-mcp--http name spec))
     (t (signal 'user-error
                (list (format "the MCP server %s speaks %s; Yeah speaks stdio and http only"
                              name type)))))))

(defun yeah-session-mcp--servers (spec)
  "Return the descriptions of the MCP servers of SPEC.
SPEC is the `mcpServers' array of a session request; nil and `:null'
mean that the client named no server."
  (cond ((null spec) nil)
        ((eq spec :null) nil)
        ((listp spec) (mapcar #'yeah-session-mcp--server spec))
        (t (signal 'user-error (list "mcpServers must be an array or null")))))

(defun yeah-session-mcp-names (spec)
  "Return the names of the MCP servers of SPEC.
The names are what the journal may hold: the command of a server and
its environment may hold secrets, and a secret is never written into
the log."
  (mapcar (lambda (server) (plist-get server :name))
          (yeah-session-mcp--servers spec)))

(defun yeah-session-mcp--ready-p (clients predicate)
  "Return non-nil when every client of CLIENTS satisfies PREDICATE."
  (cl-every predicate clients))

(defun yeah-session-mcp--wait (clients predicate timeout)
  "Wait until every client of CLIENTS satisfies PREDICATE or TIMEOUT passes.
Return non-nil when the predicate held for all of them."
  (yeah-wire-pump-until
   (lambda () (yeah-session-mcp--ready-p clients predicate))
   timeout))

(defun yeah-session-mcp--connect (server)
  "Connect to the MCP server SERVER and return the client."
  (if (eq (plist-get server :transport) :http)
      (yeah-mcp-client-connect-http
       (plist-get server :name)
       (plist-get server :url)
       (plist-get server :headers))
    (yeah-mcp-client-connect
     (plist-get server :name)
     (plist-get server :command)
     (plist-get server :args)
     (plist-get server :env))))

(defun yeah-session-mcp-connect (spec &optional timeout)
  "Connect to the MCP servers of SPEC and return their clients.
The handshake is the one of MCP: the server is asked to initialize
itself first, and only then for its tools.  A server that does not
answer in TIMEOUT seconds is a server the session cannot use: the
session is refused, and the refusal names the servers that stayed
silent.

Signal `user-error' when a server of SPEC is malformed, when it speaks
a transport that Yeah does not speak, or when it does not answer."
  (let* ((timeout (or timeout yeah-session-mcp-timeout))
         (servers (yeah-session-mcp--servers spec))
         (clients nil)
         (failed t))
    (unwind-protect
        (progn
          (dolist (server servers)
            (let ((client (yeah-session-mcp--connect server)))
              (push client clients)
              (yeah-mcp-client-initialize client)))
          (unless (yeah-session-mcp--wait
                   clients #'yeah-mcp-client-initialized-p timeout)
            (signal 'user-error
                    (list (format "the MCP servers %s did not answer the handshake in %s seconds"
                                  (string-join (mapcar #'yeah-mcp-client-name
                                                       clients)
                                               ", ")
                                  timeout))))
          (dolist (client clients)
            (yeah-mcp-client-list-tools client))
          (unless (yeah-session-mcp--wait
                   clients #'yeah-mcp-client-listed-p timeout)
            (signal 'user-error
                    (list (format "the MCP servers %s did not publish their tools in %s seconds"
                                  (string-join (mapcar #'yeah-mcp-client-name
                                                       clients)
                                               ", ")
                                  timeout))))
          (setq failed nil)
          (nreverse clients))
      (when failed
        (yeah-session-mcp-close clients)))))

(defun yeah-session-mcp-tools (clients)
  "Return the tool specifications of the MCP clients CLIENTS.
The tools are not registered: the caller puts them where they belong,
which is the registry of the run of the session that named the
servers."
  (apply #'append (mapcar #'yeah-mcp-client-tool-specs clients)))

(defun yeah-session-mcp-close (clients)
  "Close the MCP clients CLIENTS."
  (dolist (client clients)
    (yeah-mcp-client-close client))
  nil)

(provide 'yeah-session-mcp)
;;; yeah-session-mcp.el ends here
