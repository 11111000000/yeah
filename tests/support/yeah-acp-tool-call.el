;;; yeah-acp-tool-call.el --- the wire of a call of a tool, for the checks -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The checks of the kind of a call of a tool and of its named arguments need
;; the same thing: a real ACP server over stdio, a session with a directory of
;; its own, a model that calls a tool, and the wire the server wrote.  This
;; file is that machinery, and it is a file of its own: a source that is
;; written twice is a source that is wrong twice.
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
(require 'json)

(defvar yeah-acp-tool-call--buffer nil
  "The buffer that collects what the server sent.")

(defvar yeah-acp-tool-call--position nil
  "The position in the buffer of the server after the last line consumed.")

(defvar yeah-acp-tool-call--seen nil
  "The messages the server sent, in the order it sent them.
A message that was read once stays here: the check looks for the call of
the tool after it arrived, and not in the moment it arrived.")

(defun yeah-acp-tool-call--emacs ()
  "Return the Emacs program that runs the server.
The server runs the same Emacs as this one: the running binary when the
platform can name it, so the check works where `emacs' is not on PATH."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-acp-tool-call--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))

(defun yeah-acp-tool-call--model-file ()
  "Return the file that holds the fake model of the server.
The model is a file of its own and not a string in a check: the server
process loads it, and a source that is written twice is a source that is
wrong twice."
  (expand-file-name "tests/support/yeah-tool-call-model.el"))

(defun yeah-acp-tool-call--stdio-command (data-home)
  "Return the argv of the ACP server that serves on stdio.
DATA-HOME is the data home of the server process."
  (list (yeah-acp-tool-call--emacs) "-Q" "--batch"
        "-L" (yeah-acp-tool-call--lib-directory)
        "-l" "yeah-acp"
        "-l" (yeah-acp-tool-call--model-file)
        "--eval"
        (format (concat "(progn (setq yeah-data-home %S) "
                        "(yeah-acp-serve #'yeah-tool-call-model-transport))")
                data-home)))

(defun yeah-acp-tool-call--start (command)
  "Start the server process with COMMAND and return it.
The output of the server is collected in one buffer, so that the client
reads the messages of the server in the order the server wrote them."
  (setq yeah-acp-tool-call--buffer (generate-new-buffer "*yeah-tool-call*"))
  (with-current-buffer yeah-acp-tool-call--buffer
    (setq-local yeah-acp-tool-call--position (point-min)))
  (make-process :name "yeah-tool-call"
                :buffer yeah-acp-tool-call--buffer
                :command command
                :connection-type 'pipe
                :noquery t
                :filter (lambda (_process chunk)
                          (with-current-buffer yeah-acp-tool-call--buffer
                            (insert chunk)))))

(defun yeah-acp-tool-call--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (< (float-time) deadline) (not (funcall predicate)))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-acp-tool-call--send (process object)
  "Send OBJECT as one JSON line to PROCESS."
  (process-send-string process (concat (json-serialize object) "\n")))

(defun yeah-acp-tool-call--messages ()
  "Return the messages the server sent, in the order it sent them.
A line that the server has not finished is not a message yet: the check
waits for the rest of it, and a line that is cut in two by the pipe does
not lose its first half.  A message that was read once stays in the list:
the check looks for it later."
  (with-current-buffer yeah-acp-tool-call--buffer
    (let ((start yeah-acp-tool-call--position)
          (end (point-max)))
      (goto-char yeah-acp-tool-call--position)
      (while (and (< (point) end)
                  (re-search-forward "\n" end t))
        (let ((line (buffer-substring-no-properties start (1- (point)))))
          (setq start (point))
          (setq yeah-acp-tool-call--position (point))
          (push (condition-case nil
                    (json-parse-string line :object-type 'plist
                                       :array-type 'list)
                  (error nil))
                yeah-acp-tool-call--seen)))))
  ;; The list of the messages is kept with the newest first, and the check
  ;; reads it in the order the server sent the messages.  `reverse' copies
  ;; the list; `nreverse' would turn it over in place and leave the
  ;; variable at the cell that was its head.
  (reverse yeah-acp-tool-call--seen))

(defun yeah-acp-tool-call--updates ()
  "Return the `session/update' notifications the server sent."
  (delq nil
        (mapcar (lambda (message)
                  (when (and message
                             (equal "session/update" (plist-get message :method)))
                    (plist-get message :params)))
                (yeah-acp-tool-call--messages))))

(defun yeah-acp-tool-call--await-result (id &optional timeout)
  "Wait for the answer with ID and return its result, or nil."
  (let ((result nil))
    (yeah-acp-tool-call--await
     (lambda ()
       (dolist (message (yeah-acp-tool-call--messages))
         (when (and message (equal id (plist-get message :id)))
           (setq result (plist-get message :result))))
       result)
     timeout)
    result))

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
          (yeah-acp-tool-call--updates))))
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
          (setq process (yeah-acp-tool-call--start
                         (yeah-acp-tool-call--stdio-command data-home)))
          (yeah-acp-tool-call--send
           process
           (list :jsonrpc "2.0" :id 1 :method "initialize"
                 :params (list :protocolVersion 1 :clientCapabilities (list))))
          (unless (yeah-acp-tool-call--await-result 1 20)
            (error "the handshake was not answered"))
          (yeah-acp-tool-call--send
           process
           (list :jsonrpc "2.0" :id 2 :method "session/new"
                 :params (list :cwd workspace :mcpServers nil)))
          (let ((session (yeah-acp-tool-call--await-result 2 20)))
            (unless (plist-get session :sessionId)
              (error "the session was not created"))
            (yeah-acp-tool-call--send
             process
             (list :jsonrpc "2.0" :id 3 :method "session/prompt"
                   :params (list :sessionId (plist-get session :sessionId)
                                 :prompt (vector (list :type "text"
                                                       :text "read marker.txt")))))
            (yeah-acp-tool-call--await
             (lambda ()
               (setq update (yeah-acp-tool-call--call-update "read"))
               update)
             30)))
      (when (and process (process-live-p process))
        (delete-process process))
      (when (buffer-live-p yeah-acp-tool-call--buffer)
        (kill-buffer yeah-acp-tool-call--buffer)))
    update))

(provide 'yeah-acp-tool-call)

;;; yeah-acp-tool-call.el ends here
