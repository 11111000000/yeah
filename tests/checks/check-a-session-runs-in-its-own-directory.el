;;; check-a-session-runs-in-its-own-directory.el --- the tools of a session run in its own directory -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The defect: the tools of a session ran in the directory of the Emacs
;; process and not in the directory of the session.  The orchestrator sends
;; the directory of the task in `session/new', the core recorded it, and a
;; relative path of a tool was counted from somewhere else: the agent worked
;; in the directory of the installation of the orchestrator, where the files
;; of the task are not.
;;
;; This check starts a real ACP server over stdio, creates a session whose
;; `cwd' is a temporary directory with a file in it, lets the model of the
;; server read that file by its relative name, and proves that the tool of
;; the session saw the temporary directory: the text of the call carries the
;; content of the file.
;;
;; The verdict is decided by construction: the file exists in one directory
;; only, and the server of the check runs in another one.  The control of the
;; claim takes out the binding of the directory of the session -- the tools
;; run in the directory of the process again -- and the check then fails by
;; its own assertion: the tool of the session did not see the file.
;;
;; No network is involved: the model of the server is a fake that calls the
;; `read' tool and then the `finish' tool
;; (tests/support/yeah-session-cwd-model.el), and a safe read is allowed
;; without a question.
;;
;; Exit codes: 0 -- the tool of the session ran in the directory of the
;; session; 1 -- it did not.

;;; Code:

(require 'cl-lib)
(require 'json)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--buffer nil
  "The buffer that collects what the server sent.")

(defvar yeah-check--position nil
  "The position in the buffer of the server after the last line consumed.")

(defvar yeah-check--seen nil
  "The messages the server sent, in the order it sent them.
A message that was read once stays here: the check looks for the answer of
the read tool after it arrived, and not in the moment it arrived.")

(defconst yeah-check--marker "the marker of the session"
  "The text of the file that lives in the directory of the session.")

(defun yeah-check--emacs ()
  "Return the Emacs program that runs the server.
The server runs the same Emacs as this one: the running binary when the
platform can name it, so the check works where `emacs' is not on PATH."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-check--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))

(defun yeah-check--model-file ()
  "Return the file that holds the fake model of the server.
The model is a file of its own and not a string in this check: the server
process loads it, and a source that is written twice is a source that is
wrong twice."
  (expand-file-name "tests/support/yeah-session-cwd-model.el"))

(defun yeah-check--stdio-command (data-home)
  "Return the argv of the ACP server that serves on stdio.
DATA-HOME is the data home of the server process."
  (list (yeah-check--emacs) "-Q" "--batch"
        "-L" (yeah-check--lib-directory)
        "-l" "yeah-acp"
        "-l" (yeah-check--model-file)
        "--eval"
        (format (concat "(progn (setq yeah-data-home %S) "
                        "(yeah-acp-serve #'yeah-session-cwd-model-transport))")
                data-home)))

(defun yeah-check--start (command)
  "Start the server process with COMMAND and return it.
The output of the server is collected in one buffer, so that the client
reads the messages of the server in the order the server wrote them."
  (setq yeah-check--buffer (generate-new-buffer "*yeah-session-cwd*"))
  (with-current-buffer yeah-check--buffer
    (setq-local yeah-check--position (point-min)))
  (make-process :name "yeah-session-cwd"
                :buffer yeah-check--buffer
                :command command
                :connection-type 'pipe
                :noquery t
                :filter (lambda (_process chunk)
                          (with-current-buffer yeah-check--buffer
                            (insert chunk)))))

(defun yeah-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (< (float-time) deadline) (not (funcall predicate)))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-check--send (process object)
  "Send OBJECT as one JSON line to PROCESS."
  (process-send-string process (concat (json-serialize object) "\n")))

(defun yeah-check--messages ()
  "Return the messages the server sent, in the order it sent them.
A line that the server has not finished is not a message yet: the check
waits for the rest of it, and a line that is cut in two by the pipe does
not lose its first half.  A message that was read once stays in the list:
the check looks for it later."
  (with-current-buffer yeah-check--buffer
    (let ((start yeah-check--position)
          (end (point-max)))
      (goto-char yeah-check--position)
      (while (and (< (point) end)
                  (re-search-forward "\n" end t))
        (let ((line (buffer-substring-no-properties start (1- (point)))))
          (setq start (point))
          (setq yeah-check--position (point))
          (push (condition-case nil
                    (json-parse-string line :object-type 'plist
                                       :array-type 'list)
                  (error nil))
                yeah-check--seen)))))
  ;; The list of the messages is kept with the newest first, and the check
  ;; reads it in the order the server sent the messages.  `reverse' copies
  ;; the list; `nreverse' would turn it over in place and leave the
  ;; variable at the cell that was its head.
  (reverse yeah-check--seen))

(defun yeah-check--updates ()
  "Return the `session/update' notifications the server sent."
  (delq nil
        (mapcar (lambda (message)
                  (when (and message
                             (equal "session/update" (plist-get message :method)))
                    (plist-get message :params)))
                (yeah-check--messages))))

(defun yeah-check--await-result (id &optional timeout)
  "Wait for the answer with ID and return its result, or nil."
  (let ((result nil))
    (yeah-check--await
     (lambda ()
       (dolist (message (yeah-check--messages))
         (when (and message (equal id (plist-get message :id)))
           (setq result (plist-get message :result))))
       result)
     timeout)
    result))

(defun yeah-check--read-result ()
  "Return the text of the result of the call of the `read' tool, or nil.
The call of the tool is named by the update that announced it, and its
result travels in the update that completed it."
  (let* ((announcement
          (cl-find-if
           (lambda (params)
             (let ((update (plist-get params :update)))
               (and (equal "tool_call" (plist-get update :sessionUpdate))
                    (equal "read" (plist-get update :title)))))
           (yeah-check--updates)))
         (call-id (and announcement
                       (plist-get (plist-get announcement :update)
                                  :toolCallId)))
         (completion
          (and call-id
               (cl-find-if
                (lambda (params)
                  (let ((update (plist-get params :update)))
                    (and (equal "tool_call_update"
                                (plist-get update :sessionUpdate))
                         (equal call-id (plist-get update :toolCallId)))))
                (yeah-check--updates))))
         (content (plist-get (plist-get completion :update) :content))
         (block (and (listp content) (car content))))
    (and block
         (plist-get block :text))))

(defun yeah-check--probe (process workspace)
  "Return the text the `read' tool of the session of WORKSPACE answered.
PROCESS is the server of the check.  An error is raised when the server
does not answer at all."
  (yeah-check--send
   process
   (list :jsonrpc "2.0" :id 1 :method "initialize"
         :params (list :protocolVersion 1 :clientCapabilities (list))))
  (unless (yeah-check--await-result 1 20)
    (error "the handshake was not answered"))
  (yeah-check--send
   process
   (list :jsonrpc "2.0" :id 2 :method "session/new"
         :params (list :cwd workspace :mcpServers nil)))
  (let* ((session (yeah-check--await-result 2 20))
         (session-id (plist-get session :sessionId)))
    (unless session-id
      (error "the session was not created"))
    (yeah-check--send
     process
     (list :jsonrpc "2.0" :id 3 :method "session/prompt"
           :params (list :sessionId session-id
                         :prompt (vector (list :type "text"
                                               :text "read marker.txt")))))
    (let ((text nil))
      (yeah-check--await
       (lambda ()
         (setq text (yeah-check--read-result))
         text)
       30)
      text)))

(let* ((workspace (make-temp-file "yeah-session-cwd" t))
       (data-home (expand-file-name "data" workspace))
       (process nil))
  (make-directory data-home t)
  (with-temp-file (expand-file-name "marker.txt" workspace)
    (insert yeah-check--marker))
  (unwind-protect
      (let ((text nil))
        (setq process (yeah-check--start (yeah-check--stdio-command data-home)))
        (setq text
              (condition-case err
                  (yeah-check--probe process workspace)
                (error
                 (format "the session of the check did not run: %s"
                         (error-message-string err)))))
        (unless (and text
                     (string-match-p (regexp-quote yeah-check--marker) text))
          (push (format "the tool of the session did not run in the directory of the session: it answered %S"
                        (or text "nothing"))
                yeah-check--failures)))
    (dolist (failure yeah-check--failures)
      (message "session-cwd: %s" failure))
    (ignore-errors (delete-directory workspace t))
    (if yeah-check--failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-a-session-runs-in-its-own-directory.el ends here
