;;; yeah-acp-mcp.el --- the wire of the MCP servers of a session, for the checks -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The check of the MCP servers of a session needs a client that names a
;; server when it opens the session, and a service whose model calls a tool
;; of that server.
;;
;; The server of the checks is a small MCP server of its own
;; (`tests/support/yeah-mcp-server.el'): it speaks the real protocol over
;; stdio, publishes one tool, and answers with what it was given and with
;; the environment the client named.
;;
;; The server is a service on a socket and not a server on stdio: the client
;; of a service keeps reading while a run works, and that is the deployment
;; of the wire of Yeah.

;;; Code:

(require 'cl-lib)
(require 'yeah-client)
(require 'yeah-service)

(load (expand-file-name "yeah-acp-client.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil
      t)

(defconst yeah-acp-mcp--server-name "demo"
  "The name the client of the checks gives the MCP server.
The name is part of the name of the imported tools: the tools of the
server of the checks are `mcp--demo--<tool>'.")

(defconst yeah-acp-mcp--environment "the-environment-of-the-check"
  "The value of the variable the client of the checks names.
The server of the checks answers with it, and the check reads the answer:
the environment of the server is the one the client named.")

(defun yeah-acp-mcp--emacs ()
  "Return the Emacs program the MCP server of the checks runs on."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (expand-file-name "~/.nix-profile/bin/emacs")))

(defun yeah-acp-mcp--server-file ()
  "Return the file that holds the MCP server of the checks."
  (expand-file-name "tests/support/yeah-mcp-server.el"))

(defun yeah-acp-mcp--servers ()
  "Return the `mcpServers' array the client of the checks sends.
The array is a vector, and so are the `args' and the `env' of the server:
`json-serialize' does not serialize a list as an array -- it reads a list
as a plist and refuses a list of strings -- and the wire carries arrays."
  (vector (list :name yeah-acp-mcp--server-name
                :command (yeah-acp-mcp--emacs)
                :args (vector "-Q" "--batch"
                              "-l" (yeah-acp-mcp--server-file)
                              "--eval" "(yeah-mcp-server-serve)")
                :env (vector (list :name "YEAH_CHECK_ENV"
                                   :value yeah-acp-mcp--environment)))))

(defun yeah-acp-mcp--model-file ()
  "Return the file that holds the fake model of the server."
  (expand-file-name "tests/support/yeah-session-mcp-model.el"))

(defun yeah-acp-mcp--model-source ()
  "Return the source of the fake model of the server.
The model is a file of its own and not a string in a check: the service
loads it in its own Emacs, and a source that is written twice is a source
that is written twice."
  (with-temp-buffer
    (insert-file-contents (yeah-acp-mcp--model-file))
    (buffer-string)))

(defun yeah-acp-mcp--start (name data-home)
  "Start the service of the checks under NAME with the data home DATA-HOME.
The model of the service is the fake one of the checks."
  (yeah-service-start name
                      (yeah-acp-mcp--model-source)
                      data-home
                      "#'yeah-session-mcp-model-transport"
                      t
                      nil))

(provide 'yeah-acp-mcp)
;;; yeah-acp-mcp.el ends here
