;;; yeah-acp.el --- ACP v1 agent-side handlers -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; This file provides agent-side Agent Client Protocol v1 (ACP)
;; handlers and a JSON-RPC 2.0 dispatcher. See
;; `docs/ARCHITECTURE.md' for the target protocol boundary and
;; `docs/PLAN.md' for the ACP delivery stage.
;;
;; The handlers take plists and return plists. They do not open
;; subprocesses or perform IO; stdio transport is outside this module.
;;
;; The wire keys are kebab-case on both sides (per
;; ELISP_BEST_PRACTICES.md §5.2 and §8.1). JSON-RPC 2.0
;; requires `jsonrpc', `id', `result' or `error' at the top
;; level of the response; we keep those camelCase because they
;; are the JSON-RPC standard, not ACP.
;;
;; The handlers provided here are:
;;   * yeah-acp-initialize      - handshake
;;   * yeah-acp-session-new     - generate a session id
;;   * yeah-acp-session-prompt  - acknowledge a prompt
;;   * yeah-acp-session-cancel  - acknowledge cancellation
;;   * yeah-acp-handle-message  - JSON-RPC dispatcher
;;   * yeah-acp-version         - version probe
;;
;; Prompt and cancel are placeholders: they do not execute prompts
;; or cancel agent runs.

;;; Code:

(require 'cl-lib)

(defgroup yeah-acp nil
  "Yeah — ACP v1 agent-side handlers."
  :group 'yeah)

(defconst yeah-acp--protocol-version "2025-01-01"
  "The ACP v1 protocol version Yeah speaks.
Bump only as part of an ACP wire-protocol transition.")

(defconst yeah-acp--agent-name "yeah"
  "The `agentInfo.name' Yeah reports to ACP clients.")

(defconst yeah-acp--agent-version "0.1.0-alpha"
  "The Yeah version reported to ACP clients on `initialize'.
Matches `VERSION' at the project root.")

(defun yeah-acp-version ()
  "Return the Yeah wire-version string.
Callers use this to probe the agent without parsing
`InitializeResponse'. The string matches the `agentInfo.version'
field on the wire."
  (declare (pure t) (side-effect-free t))
  yeah-acp--agent-version)

(defun yeah-acp-initialize (handshake)
  "Process an ACP `initialize' request and return an `InitializeResponse' plist.

HANDSHAKE is a plist carrying the client's `protocolVersion',
`clientInfo', and `clientCapabilities'. The response plist
contains the agent's `protocolVersion', `agentInfo', and
`agentCapabilities'. Signal `user-error' if HANDSHAKE does not
carry a `protocolVersion'."
  (unless (and (consp handshake)
               (plist-member handshake :protocolVersion))
    (signal 'user-error
            (list "yeah-acp-initialize: missing required field :protocolVersion")))
  (let ((client-version (plist-get handshake :protocolVersion)))
    (list :protocolVersion yeah-acp--protocol-version
            :agentInfo (list :name yeah-acp--agent-name
                             :version yeah-acp--agent-version)
            :agentCapabilities (list :loadSession t
                                      :prompt     t
                                      :cancel     t)
            :clientProtocolVersion client-version)))

(defun yeah-acp-session-new (_request)
  "Create a new ACP session id and return a `(:sessionId ID)' plist.

REQUEST is the `SessionNewRequest' plist. The id is generated
locally; no persistent session state is created."
  (list :sessionId (yeah-acp--make-session-id)))

(defun yeah-acp-session-prompt (request)
  "Acknowledge a `session/prompt' request and return a `(:messageId ID)' plist.

REQUEST is a `SessionPromptRequest' plist (`sessionId', `text').
This handler is a placeholder: it returns a generated message id
and does not execute the prompt."
  (unless (and (consp request)
               (plist-member request :sessionId)
               (plist-member request :text))
    (signal 'user-error
            (list "yeah-acp-session-prompt: missing :sessionId or :text")))
  (list :messageId (yeah-acp--make-message-id)))

(defun yeah-acp-session-cancel (request)
  "Acknowledge a `session/cancel' request.

REQUEST is a `SessionCancelRequest' plist (`sessionId'). The
returned plist has shape `(:status \"cancelled\" :sessionId ID)'.
This handler is a placeholder: it returns an acknowledgement but
does not cancel an agent run."
  (unless (and (consp request)
               (plist-member request :sessionId))
    (signal 'user-error
            (list "yeah-acp-session-cancel: missing :sessionId")))
  (list :status "cancelled"
        :sessionId (plist-get request :sessionId)))

(defun yeah-acp-handle-message (json-string)
  "Parse JSON-STRING as a JSON-RPC 2.0 message and return the response string.

Routes to `yeah-acp-initialize', `yeah-acp-session-new',
`yeah-acp-session-prompt', or `yeah-acp-session-cancel' based
on the `method' field. Returns a JSON-RPC 2.0 response object
serialised as JSON:

  * `result' on success;
  * `error' (with `code' and `message') on parse failure,
    invalid request, or unknown method.

Notifications (no `id' field) return the JSON-RPC 204 No Content
response and have no `result'."
  (let* ((parsed
          (condition-case nil
              (json-parse-string json-string :object-type 'plist)
            (json-parse-error
             (list :error (list :code -32700
                                :message "Parse error")))))
         (parse-error (plist-get parsed :error)))
    (if parse-error
        (yeah-acp--jsonrpc-error-response nil -32700 "Parse error")
      (let* ((method (plist-get parsed :method))
             (id     (plist-get parsed :id))
             (params (or (plist-get parsed :params) '())))
        (cond
         ((null method)
          (yeah-acp--jsonrpc-error-response id -32600 "Invalid Request: no method"))
         ((not (stringp method))
          (yeah-acp--jsonrpc-error-response id -32600 "Invalid Request: method must be string"))
         ((string= method "initialize")
          (condition-case err
              (let* ((result (yeah-acp-initialize params))
                     (response (list :jsonrpc "2.0" :id id :result result)))
                (json-serialize response))
            (user-error
             (yeah-acp--jsonrpc-error-response
              id -32602
              (cadr err)))))
         ((string= method "session/new")
          (condition-case err
              (let* ((result (yeah-acp-session-new params))
                     (response (list :jsonrpc "2.0" :id id :result result)))
                (json-serialize response))
            (user-error
             (yeah-acp--jsonrpc-error-response
              id -32602
              (cadr err)))))
         ((string= method "session/prompt")
          (condition-case err
              (let* ((result (yeah-acp-session-prompt params))
                     (response (list :jsonrpc "2.0" :id id :result result)))
                (json-serialize response))
            (user-error
             (yeah-acp--jsonrpc-error-response
              id -32602
              (cadr err)))))
         ((string= method "session/cancel")
          (condition-case err
              (let* ((result (yeah-acp-session-cancel params))
                     (response (list :jsonrpc "2.0" :id id :result result)))
                (json-serialize response))
            (user-error
             (yeah-acp--jsonrpc-error-response
              id -32602
              (cadr err)))))
         (t
          (yeah-acp--jsonrpc-error-response
           id -32601
           (format "Method not found: %s" method))))))))

(defun yeah-acp--jsonrpc-error-response (id code message)
  "Build a JSON-RPC 2.0 error response string.
ID is the request id (or nil for parse errors).
CODE is the JSON-RPC error code.
MESSAGE is the human-readable error message."
  (let ((response (list :jsonrpc "2.0"
                        :error (list :code code :message message))))
    (when id (setq response (plist-put response :id id)))
    (json-serialize response)))

(defvar yeah-acp--counter 0
  "Module-private monotonic counter for session and message id generation.")

(defun yeah-acp--next-counter ()
  "Return a process-unique counter for id generation.
Used by `yeah-acp--make-session-id' and
`yeah-acp--make-message-id'."
  (setq yeah-acp--counter (1+ yeah-acp--counter))
  yeah-acp--counter)

(defun yeah-acp--make-session-id ()
  "Return a fresh session id of the shape `s-<counter>-<random>'."
  (format "s-%d-%x" (yeah-acp--next-counter) (random #x1000000)))

(defun yeah-acp--make-message-id ()
  "Return a fresh message id of the shape `m-<counter>-<random>'."
  (format "m-%d-%x" (yeah-acp--next-counter) (random #x1000000)))

(provide 'yeah-acp)
;;; yeah-acp.el ends here