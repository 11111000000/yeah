;;; check-acp-dispatcher-routes-every-method.el --- canary for the ACP wire -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The ERT suite calls the handlers directly; only the initialize route is
;; exercised through the dispatcher. This check drives the dispatcher itself
;; for all four methods of the v1 surface, and asks it to refuse a method it
;; does not know. A dispatcher that answers an unknown method is worse than
;; one that says nothing: the client cannot tell a refusal from a result.
;;
;; Exit codes: 0 — the dispatcher routes and refuses correctly; 1 — it does not.

;;; Code:

(require 'yeah-acp)

(defun yeah-check--response (method params)
  "Return the parsed JSON-RPC response for METHOD with PARAMS."
  (let* ((request (format "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"%s\",\"params\":%s}"
                           method params))
         (raw (yeah-acp-handle-message request))
         (parsed (json-parse-string raw :object-type 'plist)))
    parsed))

(defun yeah-check--result (method params)
  "Return the result object of the response for METHOD with PARAMS."
  (plist-get (yeah-check--response method params) :result))

(let ((failure nil))

  (unless (plist-member (yeah-check--result "initialize"
                                           "{\"protocolVersion\":\"2025-01-01\"}")
                        :protocolVersion)
    (setq failure "initialize was not answered with a protocol version"))

  (unless (plist-member (yeah-check--result "session/new" "{}") :sessionId)
    (setq failure "session/new was not answered with a session id"))

  (unless (plist-member (yeah-check--result "session/prompt"
                                           "{\"sessionId\":\"s-1\",\"text\":\"hi\"}")
                        :messageId)
    (setq failure "session/prompt was not answered with a message id"))

  (let ((cancel (yeah-check--result "session/cancel" "{\"sessionId\":\"s-1\"}")))
    (unless (and cancel
                 (string= (plist-get cancel :status) "cancelled"))
      (setq failure "session/cancel was not acknowledged")))

  (let ((unknown (yeah-check--response "session/unknown" "{}")))
    (unless (and (plist-member unknown :error)
                 (= -32601 (plist-get (plist-get unknown :error) :code)))
      (setq failure "an unknown method was not refused with -32601")))

  (when failure
    (message "%s" failure)
    (kill-emacs 1)))

(kill-emacs 0)

;;; check-acp-dispatcher-routes-every-method.el ends here
