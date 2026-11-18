;;; yeah-acp-tool-call.el --- the wire of a call of a tool, for the checks -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The checks of the kind of a call of a tool and of its named arguments need
;; the same thing: a real ACP server over stdio, a session with a directory of
;; its own, a model that calls a tool, and the wire the server wrote.  The
;; machinery of the wire is in `yeah-acp-wire'; this file is the part of it
;; that is about a call of a tool.
;;
;; The reader of the wire waits for the end of a line: a line that the pipe
;; cut in two does not lose its first half.  A message that was read once
;; stays in the list: the check looks for the call of the tool after it
;; arrived, and not in the moment it arrived.  The list of the messages is
;; copied with `reverse' and not turned over in place with `nreverse': the
;; reader that turns the list over leaves the variable at the cell that was
;; its head, and the second reading of the wire finds one message and not
;; the wire.

;;; Code:

(require 'cl-lib)

(defvar yeah-acp-tool-call--directory
  (file-name-directory (or load-file-name buffer-file-name default-directory))
  "The directory of this file: the files of the checks live next to it.
The support files are not on the load path, so a file that needs another
one loads it by its name next to itself.")

(load (expand-file-name "yeah-acp-wire.el" yeah-acp-tool-call--directory) nil t)

(defun yeah-acp-tool-call--model-file ()
  "Return the file that holds the fake model of the server.
The model is a file of its own and not a string in a check: the server
process loads it, and a source that is written twice is a source that is
wrong twice."
  (expand-file-name "tests/support/yeah-tool-call-model.el"))

(defun yeah-acp-tool-call--call-update (name)
  "Return the update that announced the call of the tool NAME, or nil.
The update is the one of the wire that carries the kind of the call and the
arguments it was called with.  `cl-find-if' returns the element it found and
not the value of its predicate: the element is the notification, and the
update is in it, so the update is taken out of it here."
  (let ((params
         (cl-find-if
          (lambda (params)
            (let ((update (plist-get params :update)))
              (and (equal "tool_call" (plist-get update :sessionUpdate))
                   (equal name (plist-get update :title)))))
          (yeah-acp-wire--updates))))
    (and params (plist-get params :update))))

(defun yeah-acp-tool-call--drive (workspace)
  "Run a server over WORKSPACE and return the call of the `read' tool.
WORKSPACE is the directory of the session: the model of the server reads the
file `marker.txt' of it by its relative name.  The result is the update of
the wire that announced the call, or nil when the server did not announce
it.  An error is raised when the server does not answer at all."
  (let* ((data-home (expand-file-name "data" workspace))
         (process nil)
         (update nil))
    (make-directory data-home t)
    (unwind-protect
        (progn
          (setq process (yeah-acp-wire--start
                         (yeah-acp-wire--stdio-command
                          data-home (yeah-acp-tool-call--model-file))))
          (yeah-acp-wire--send
           process
           (list :jsonrpc "2.0" :id 1 :method "initialize"
                 :params (list :protocolVersion 1 :clientCapabilities (list))))
          (unless (yeah-acp-wire--await-result 1 20)
            (error "the handshake was not answered"))
          (yeah-acp-wire--send
           process
           (list :jsonrpc "2.0" :id 2 :method "session/new"
                 :params (list :cwd workspace :mcpServers nil)))
          (let ((session (yeah-acp-wire--await-result 2 20)))
            (unless (plist-get session :sessionId)
              (error "the session was not created"))
            (yeah-acp-wire--send
             process
             (list :jsonrpc "2.0" :id 3 :method "session/prompt"
                   :params (list :sessionId (plist-get session :sessionId)
                                 :prompt (vector (list :type "text"
                                                       :text "read marker.txt")))))
            (yeah-acp-wire--await
             (lambda ()
               (setq update (yeah-acp-tool-call--call-update "read"))
               update)
             30)))
      (yeah-acp-wire--stop process))
    update))

(provide 'yeah-acp-tool-call)

;;; yeah-acp-tool-call.el ends here
