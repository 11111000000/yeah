;;; yeah-acp-wire.el --- the wire of a real ACP server, for the checks -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The checks of the wire need the same thing again and again: a real ACP
;; server over stdio, a client that speaks to it, and the bytes the server
;; wrote.  This file is that machinery, and it is a file of its own: a
;; source that is written twice is a source that is wrong twice.
;;
;; The reader of the wire waits for the end of a line: a line that the pipe
;; cut in two does not lose its first half.  A message that was read once
;; stays in the list: a check looks for a message after it arrived, and not
;; in the moment it arrived.  The list of the messages is copied with
;; `reverse' and not turned over in place with `nreverse': the reader that
;; turns the list over leaves the variable at the cell that was its head,
;; and the second reading of the wire finds one message and not the wire.
;;
;; The model of the server is a file of its own and not a string in a
;; check: the server process loads it, and the check names it.  The file
;; that holds it is the one the caller names.

;;; Code:

(require 'cl-lib)
(require 'json)

(defvar yeah-acp-wire--buffer nil
  "The buffer that collects what the server sent.")

(defvar yeah-acp-wire--position nil
  "The position in the buffer of the server after the last line consumed.")

(defvar yeah-acp-wire--seen nil
  "The messages the server sent, in the order it sent them.
A message that was read once stays here: a check looks for it later.")

(defun yeah-acp-wire--emacs ()
  "Return the Emacs program that runs the server.
The server runs the same Emacs as this one: the running binary when the
platform can name it, so the check works where `emacs' is not on PATH."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-acp-wire--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))

(defun yeah-acp-wire--stdio-command (data-home model-file)
  "Return the argv of the ACP server that serves on stdio.
DATA-HOME is the data home of the server process; MODEL-FILE is the file
that holds the model the server talks to.  The transport of the model is
the function the name of the file names with `-transport' added: the file
`yeah-tool-call-model.el' holds `yeah-tool-call-model-transport'."
  (list (yeah-acp-wire--emacs) "-Q" "--batch"
        "-L" (yeah-acp-wire--lib-directory)
        "-l" "yeah-acp"
        "-l" model-file
        "--eval"
        (format (concat "(progn (setq yeah-data-home %S) "
                        "(yeah-acp-serve #'%s-transport))")
                data-home
                (file-name-base model-file))))

(defun yeah-acp-wire--start (command)
  "Start the server process with COMMAND and return it.
The output of the server is collected in one buffer, so that the client
reads the messages of the server in the order the server wrote them."
  (setq yeah-acp-wire--buffer (generate-new-buffer "*yeah-acp-wire*"))
  (with-current-buffer yeah-acp-wire--buffer
    (setq-local yeah-acp-wire--position (point-min)))
  (make-process :name "yeah-acp-wire"
                :buffer yeah-acp-wire--buffer
                :command command
                :connection-type 'pipe
                :noquery t
                :filter (lambda (_process chunk)
                          (with-current-buffer yeah-acp-wire--buffer
                            (insert chunk)))))

(defun yeah-acp-wire--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (< (float-time) deadline) (not (funcall predicate)))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-acp-wire--send (process object)
  "Send OBJECT as one JSON line to PROCESS."
  (process-send-string process (concat (json-serialize object) "\n")))

(defun yeah-acp-wire--messages ()
  "Return the messages the server sent, in the order it sent them.
A line that the server has not finished is not a message yet: the check
waits for the rest of it, and a line that is cut in two by the pipe does
not lose its first half.  A message that was read once stays in the list:
the check looks for it later."
  (with-current-buffer yeah-acp-wire--buffer
    (let ((start yeah-acp-wire--position)
          (end (point-max)))
      (goto-char yeah-acp-wire--position)
      (while (and (< (point) end)
                  (re-search-forward "\n" end t))
        (let ((line (buffer-substring-no-properties start (1- (point)))))
          (setq start (point))
          (setq yeah-acp-wire--position (point))
          (push (condition-case nil
                    (json-parse-string line :object-type 'plist
                                       :array-type 'list)
                  (error nil))
                yeah-acp-wire--seen)))))
  ;; The list of the messages is kept with the newest first, and the check
  ;; reads it in the order the server sent the messages.  `reverse' copies
  ;; the list; `nreverse' would turn it over in place and leave the
  ;; variable at the cell that was its head.
  (reverse yeah-acp-wire--seen))

(defun yeah-acp-wire--updates ()
  "Return the `session/update' notifications the server sent."
  (delq nil
        (mapcar (lambda (message)
                  (when (and message
                             (equal "session/update" (plist-get message :method)))
                    (plist-get message :params)))
                (yeah-acp-wire--messages))))

(defun yeah-acp-wire--await-result (id &optional timeout)
  "Wait for the answer with ID and return its result, or nil."
  (let ((result nil))
    (yeah-acp-wire--await
     (lambda ()
       (dolist (message (yeah-acp-wire--messages))
         (when (and message (equal id (plist-get message :id)))
           (setq result (plist-get message :result))))
       result)
     timeout)
    result))

(defun yeah-acp-wire--await-answer (id &optional timeout)
  "Wait for the message with ID and return it, or nil.
The message may be a response of the server or a request of it: the
server asks the client for permission with a request that carries an id."
  (let ((message nil))
    (yeah-acp-wire--await
     (lambda ()
       (dolist (candidate (yeah-acp-wire--messages))
         (when (and candidate (equal id (plist-get candidate :id)))
           (setq message candidate)))
       message)
     timeout)
    message))

(defun yeah-acp-wire--requests (method)
  "Return the requests of the server with METHOD, in the order they came."
  (delq nil
        (mapcar (lambda (message)
                  (when (and message
                             (equal method (plist-get message :method)))
                    message))
                (yeah-acp-wire--messages))))

(defun yeah-acp-wire--stop (process)
  "Stop the server PROCESS and drop the buffer of its wire."
  (when (and process (process-live-p process))
    (delete-process process))
  (when (buffer-live-p yeah-acp-wire--buffer)
    (kill-buffer yeah-acp-wire--buffer)))

(provide 'yeah-acp-wire)

;;; yeah-acp-wire.el ends here
