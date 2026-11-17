;;; check-wire-speaks-acp.el --- the wire of Yeah speaks ACP -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A real Emacs process serves ACP on a local socket.  Two clients connect to
;; it, one after the other:
;;
;;   * the first announces nothing at `initialize'.  It must see plain ACP:
;;     every update names a kind that the ACP schema declares, the content
;;     of a chunk is one content block, and Yeah's own queue events do not
;;     reach it.
;;   * the second announces in the `_meta' of its capabilities that it
;;     understands Yeah's queue events.  The event that moves an input into
;;     the queue must reach that client.
;;
;; The model is a fake that never answers, so the prompt stays open and the
;; queue of the session can be watched.  The socket is a file in a temporary
;; directory: no network is involved.
;;
;; A second server answers at once: its model calls the `finish' tool and says
;; nothing else.  The summary of that run is the answer of the agent, and it
;; must reach the client as the message of the agent.  The call of the tool
;; must reach it too, with the arguments the tool was called with.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-acp-vocabulary)

(defvar yeah-check--position nil
  "Position in the client buffer after the last line consumed.")

(defvar yeah-check--aside nil
  "Messages read aside while waiting for another one.")

(defun yeah-check--emacs ()
  "Return the Emacs program to run the server."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-check--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))

(defun yeah-check--schema-path ()
  "Return the path of the ACP schema, or nil when it cannot be found."
  (seq-find
   (lambda (path) (file-readable-p path))
   (list (expand-file-name
          "../schemas/acp-v1.json"
          (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))
         (expand-file-name "schemas/acp-v1.json" default-directory))))

(defun yeah-check--acp-kinds ()
  "Return the update kinds the ACP schema declares.
The schema is the measure of the wire: a kind that is not in it is a kind
that a client which checks the wire refuses."
  (let* ((path (yeah-check--schema-path))
         (schema (when path
                   (with-temp-buffer
                     (insert-file-contents path)
                     (json-parse-string (buffer-string) :object-type 'alist
                                        :array-type 'list))))
         (definitions (cdr (assoc 'definitions schema)))
         (notification (cdr (assoc 'SessionUpdateNotification definitions)))
         (notification-properties (cdr (assoc 'properties notification)))
         (update (cdr (assoc 'update notification-properties)))
         (update-properties (cdr (assoc 'properties update)))
         (session-update (cdr (assoc 'sessionUpdate update-properties))))
    (cdr (assoc 'enum session-update))))

(defun yeah-check--start-server (data-home socket transport)
  "Start the ACP server process for DATA-HOME on SOCKET and return it.
TRANSPORT is the body of the fake transport of the server: `nil' leaves the
prompt open, and the body of a call to `finish' ends the run with the
summary of the agent."
  (make-process
   :name "yeah-acp-server"
   :command
   (list (yeah-check--emacs) "-Q" "--batch"
         "-L" (yeah-check--lib-directory)
         "-l" "yeah-acp"
         "--eval"
         (format
          (concat "(progn (setq yeah-data-home %S) "
                  "(setq yeah-input-directory %S) "
                  "(defun yeah-check--transport (prompt callback) %s) "
                  "(yeah-acp-serve-socket %S #'yeah-check--transport))")
          data-home
          (expand-file-name "pending/" data-home)
          transport
          socket))
   :connection-type 'pipe
   :noquery t
   :filter (lambda (_process _chunk) nil)))

(defun yeah-check--connect (socket)
  "Connect to the server on SOCKET and return the connection process.
The connection is retried until the server is listening."
  (let ((deadline (+ (float-time) 10))
        (connection nil))
    (while (and (null connection) (< (float-time) deadline))
      (setq connection
            (condition-case nil
                (make-network-process
                 :name "yeah-acp-client"
                 :family 'local
                 :service socket
                 :noquery t
                 :filter (lambda (_process chunk)
                           (with-current-buffer yeah-check--buffer
                             (insert chunk))))
              (file-missing nil)))
      (unless connection
        (accept-process-output nil 0.05)))
    connection))

(defvar yeah-check--buffer nil
  "The buffer collecting the messages the client received.")

(defun yeah-check--send (connection object)
  "Send OBJECT as one JSON line to CONNECTION."
  (process-send-string connection (concat (json-serialize object) "\n")))

(defun yeah-check--next-message (&optional timeout)
  "Return the next message the client received, or nil.
TIMEOUT defaults to 5 seconds."
  (let ((deadline (+ (float-time) (or timeout 5)))
        (message nil))
    (while (and (null message) (< (float-time) deadline))
      (accept-process-output nil 0.05)
      (with-current-buffer yeah-check--buffer
        (goto-char yeah-check--position)
        (when (re-search-forward "^\\(.+\\)\n" nil t)
          (setq message (json-parse-string (match-string 1)
                                          :object-type 'plist :array-type 'list))
          (setq yeah-check--position (match-end 0)))))
    message))

(defun yeah-check--await (predicate &optional timeout)
  "Return the next message that satisfies PREDICATE.
A message that does not satisfy it is kept aside and returned by
`yeah-check--collect'.  TIMEOUT defaults to 5 seconds."
  (let ((deadline (+ (float-time) (or timeout 5)))
        (message nil)
        (aside nil))
    (while (and (null message) (< (float-time) deadline))
      (let ((candidate (yeah-check--next-message 1)))
        (when candidate
          (if (funcall predicate candidate)
              (setq message candidate)
            (push candidate aside)))))
    (setq yeah-check--aside aside)
    message))

(defun yeah-check--collect (seconds)
  "Return every message the client received within SECONDS.
The messages read aside by `yeah-check--await' come first."
  (let ((deadline (+ (float-time) seconds))
        (messages (reverse yeah-check--aside)))
    (while (< (float-time) deadline)
      (let ((message (yeah-check--next-message 0.2)))
        (when message
          (push message messages))))
    (nreverse messages)))

(defun yeah-check--response (id)
  "Return a predicate matching the JSON-RPC response with ID."
  (lambda (message)
    (and (equal (plist-get message :id) id)
         (not (plist-get message :method)))))

(defun yeah-check--update (message)
  "Return the update object of MESSAGE, or nil."
  (plist-get (plist-get message :params) :update))

(defun yeah-check--update-kind (message)
  "Return the kind of the update of MESSAGE, or nil."
  (plist-get (yeah-check--update message) :sessionUpdate))

(defun yeah-check--drive (announce data-home)
  "Drive one client against the server and return what it saw.
ANNOUNCE says whether the client announces Yeah's queue events at
`initialize'.  DATA-HOME is the home of the service.  The result is a
plist with the updates the client received, the id of the input it queued
and the failures the client found."
  (let* ((connection (yeah-check--connect
                      (expand-file-name "yeah-acp.sock" data-home)))
         (params (list :protocolVersion yeah-acp-protocol-version))
         (session-id nil)
         (input-id nil)
         (updates nil)
         (failures nil))
    (unless connection
      (push "the client could not connect to the server" failures)
      (list :updates nil :input-id nil :failures failures))
    (unwind-protect
        (progn
          (setq yeah-check--buffer (generate-new-buffer "*yeah-acp-client*"))
          (with-current-buffer yeah-check--buffer
            (setq-local yeah-check--position (point-min)))
          (when announce
            (setq params
                  (plist-put params :clientCapabilities
                             (yeah-acp-queue-events-capabilities))))
          ;; --- the handshake ---
          (yeah-check--send
           connection
           (list :jsonrpc "2.0" :id 1 :method "initialize" :params params))
          (let ((response (yeah-check--await (yeah-check--response 1) 10)))
            (unless (equal yeah-acp-protocol-version
                           (plist-get (plist-get response :result)
                                      :protocolVersion))
              (push (format "the handshake did not answer: %S" response)
                    failures)))
          ;; --- a session and a prompt that the model never answers ---
          (yeah-check--send
           connection
           (list :jsonrpc "2.0" :id 2 :method "session/new"
                 :params (list :cwd data-home :mcpServers nil)))
          (let ((response (yeah-check--await (yeah-check--response 2) 10)))
            (setq session-id (plist-get (plist-get response :result) :sessionId))
            (unless (stringp session-id)
              (push (format "session/new did not answer: %S" response)
                    failures)))
          (yeah-check--send
           connection
           (list :jsonrpc "2.0" :id 3 :method "session/prompt"
                 :params (list :sessionId session-id
                               :prompt (vector (list :type "text"
                                                     :text "wait")))))
          (let ((started (yeah-check--await
                           (lambda (message)
                             (equal "user_message_chunk"
                                    (yeah-check--update-kind message)))
                           10)))
            (unless started
              (push "the server did not report the started prompt" failures))
            ;; the chunk that reported the prompt is part of what the client
            ;; saw: it is the update whose content this check reads.
            (when started
              (push started updates)))
          ;; --- a clarification that waits in the queue ---
          (yeah-check--send
           connection
           (list :jsonrpc "2.0" :id 4 :method "session/steer"
                 :params (list :sessionId session-id
                               :prompt "focus on the tests")))
          (let ((response (yeah-check--await (yeah-check--response 4) 10)))
            (setq input-id (plist-get (plist-get response :result) :inputId))
            (unless (stringp input-id)
              (push (format "session/steer did not answer with an input id: %S"
                            response)
                    failures)))
          (setq updates (append (reverse updates) (yeah-check--collect 2))))
      (when (and connection (process-live-p connection))
        (delete-process connection))
      (when (buffer-live-p yeah-check--buffer)
        (kill-buffer yeah-check--buffer)))
    (list :updates updates :input-id input-id :failures failures)))

(defun yeah-check--finish-transport (answer)
  "Return the body of a fake transport that ends the run with ANSWER.
The model of the check answers with the `finish' tool and nothing else:
the answer of the agent is then the summary of the run, and the summary is
what the client must see."
  (format "(funcall callback (list 'tool-call (list (list :name \"finish\") (list %S) (lambda (_value) nil))))"
          answer))

(defun yeah-check--drive-answer (data-home answer)
  "Drive one client against the server of DATA-HOME and return what it saw.
ANSWER is the text the model writes as the summary of the run.  The result
is a plist with the updates the client received and the failures the client
found."
  (let* ((connection (yeah-check--connect
                      (expand-file-name "yeah-acp.sock" data-home)))
         (params (list :protocolVersion yeah-acp-protocol-version))
         (session-id nil)
         (updates nil)
         (failures nil))
    (if (not connection)
        (progn
          (push "the client could not connect to the server" failures)
          (list :updates nil :failures failures))
      (unwind-protect
        (progn
          (setq yeah-check--buffer (generate-new-buffer "*yeah-acp-client*"))
          (with-current-buffer yeah-check--buffer
            (setq-local yeah-check--position (point-min)))
          ;; --- the handshake ---
          (yeah-check--send
           connection
           (list :jsonrpc "2.0" :id 1 :method "initialize" :params params))
          (let ((response (yeah-check--await (yeah-check--response 1) 10)))
            (unless (equal yeah-acp-protocol-version
                           (plist-get (plist-get response :result)
                                      :protocolVersion))
              (push (format "the handshake did not answer: %S" response)
                    failures)))
          ;; --- a session and a prompt the model finishes at once ---
          (yeah-check--send
           connection
           (list :jsonrpc "2.0" :id 2 :method "session/new"
                 :params (list :cwd data-home :mcpServers nil)))
          (let ((response (yeah-check--await (yeah-check--response 2) 10)))
            (setq session-id (plist-get (plist-get response :result) :sessionId))
            (unless (stringp session-id)
              (push (format "session/new did not answer: %S" response)
                    failures)))
          (yeah-check--send
           connection
           (list :jsonrpc "2.0" :id 3 :method "session/prompt"
                 :params (list :sessionId session-id
                               :prompt (vector (list :type "text"
                                                     :text "say it")))))
          ;; the words of the agent are the message of the agent
          (let ((chunk (yeah-check--await
                        (lambda (message)
                          (equal "agent_message_chunk"
                                 (yeah-check--update-kind message)))
                        20)))
            (unless chunk
              (push "the answer of the agent did not reach the client" failures))
            (when chunk
              (push chunk updates)))
          (setq updates (append (reverse updates) (yeah-check--collect 2))))
        (when (and connection (process-live-p connection))
          (delete-process connection))
        (when (buffer-live-p yeah-check--buffer)
          (kill-buffer yeah-check--buffer))))
    (list :updates updates :failures failures)))

(let ((yeah-check--failures nil)
      (kinds (yeah-check--acp-kinds))
      (data-home (make-temp-file "yeah-acp-data" t)))
  (unwind-protect
      (progn
        (unless kinds
          (push "the ACP schema does not declare the update kinds"
                yeah-check--failures))
        (when kinds
          (let ((socket (expand-file-name "yeah-acp.sock" data-home)))
            (yeah-check--start-server data-home socket nil)
            ;; --- the client that announced nothing sees plain ACP ---
            (let* ((seen (yeah-check--drive nil data-home))
                   (updates (plist-get seen :updates)))
              (dolist (failure (plist-get seen :failures))
                (push failure yeah-check--failures))
              (dolist (message updates)
                (let* ((update (yeah-check--update message))
                       (kind (yeah-check--update-kind message)))
                  (unless (member kind kinds)
                    (push (format "the client that announced nothing received the update %s"
                                  kind)
                          yeah-check--failures))
                  ;; the content of a chunk is one content block, not an array
                  (when (member kind '("user_message_chunk" "agent_message_chunk"))
                    (let ((content (plist-get update :content)))
                      (unless (and (listp content)
                                   (not (vectorp content))
                                   (equal "text" (plist-get content :type))
                                   (stringp (plist-get content :text)))
                        (push (format "the chunk did not carry one content block: %S"
                                      content)
                              yeah-check--failures))))))
              ;; the queue events of Yeah are not ACP and did not travel here
              (when (cl-some (lambda (message)
                                (string-prefix-p "input_"
                                                 (or (yeah-check--update-kind message)
                                                     "")))
                            updates)
                (push "the queue events reached a client that announced nothing"
                      yeah-check--failures)))
            ;; --- the client that asked for the queue events sees them ---
            (let* ((seen (yeah-check--drive t data-home))
                   (updates (plist-get seen :updates))
                   (input-id (plist-get seen :input-id)))
              (dolist (failure (plist-get seen :failures))
                (push failure yeah-check--failures))
              (unless (cl-some
                       (lambda (message)
                         (and (equal "input_queued"
                                     (yeah-check--update-kind message))
                              (equal input-id
                                     (plist-get (yeah-check--update message)
                                                :inputId))))
                       updates)
                (push (format "the queue event did not reach the client that asked for it: %S"
                              updates)
                      yeah-check--failures))
              ;; the kind of the queue event is not ACP: it is an extension
              (dolist (message updates)
                (let ((kind (yeah-check--update-kind message)))
                  (unless (or (member kind kinds)
                              (string-prefix-p "input_" (or kind "")))
                    (push (format "the update %s is neither ACP nor a queue event"
                                  kind)
                          yeah-check--failures)))))))
        ;; --- the answer of a finished run reaches the client ---
        (let* ((answer-home (make-temp-file "yeah-acp-answer" t))
               (answer "the answer of the agent")
               (socket (expand-file-name "yeah-acp.sock" answer-home)))
          (unwind-protect
              (progn
                (yeah-check--start-server
                 answer-home socket (yeah-check--finish-transport answer))
                (let* ((seen (yeah-check--drive-answer answer-home answer))
                       (updates (plist-get seen :updates)))
                  (dolist (failure (plist-get seen :failures))
                    (push failure yeah-check--failures))
                  ;; the words of the agent are the message of the agent
                  (unless (cl-some
                           (lambda (message)
                             (and (equal "agent_message_chunk"
                                         (yeah-check--update-kind message))
                                  (equal answer
                                         (plist-get
                                          (plist-get (yeah-check--update message)
                                                     :content)
                                          :text))))
                           updates)
                    (push (format "the answer of the agent did not reach the client: %S"
                                  updates)
                          yeah-check--failures))
                  ;; the call of a tool carries what it was called with
                  (let ((call (cl-find-if
                               (lambda (message)
                                 (equal "tool_call"
                                        (yeah-check--update-kind message)))
                               updates)))
                    (unless call
                      (push "the call of the tool did not reach the client"
                            yeah-check--failures))
                    (when call
                      (let ((raw (plist-get (yeah-check--update call) :rawInput)))
                        ;; the arguments of the call are the values themselves
                        (unless (and (or (listp raw) (vectorp raw))
                                     (equal answer (car raw)))
                          (push (format "the call of the tool did not carry its input: %S"
                                        raw)
                                yeah-check--failures)))))))
            (ignore-errors (delete-directory answer-home t))))
    (dolist (failure yeah-check--failures)
      (message "wire: %s" failure))
    (ignore-errors (delete-directory data-home t))
    (if yeah-check--failures
        (kill-emacs 1)
      (kill-emacs 0)))))

;;; check-wire-speaks-acp.el ends here
