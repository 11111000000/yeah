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
;; The ERT suite calls the handlers directly; this check drives the JSON-RPC
;; dispatcher itself for every method of the v1 surface -- initialize,
;; session/new, session/load, session/prompt and session/cancel -- and asks
;; it to refuse a method it does not know and a request it cannot accept.
;; A dispatcher that answers an unknown method is worse than one that says
;; nothing: the client cannot tell a refusal from a result.
;;
;; The prompt route is asynchronous by contract: the dispatcher returns
;; nothing for it and the answer leaves later, carrying a stop reason.
;;
;; Exit codes: 0 -- the dispatcher routes and refuses correctly; 1 -- it does not.

;;; Code:

(require 'cl-lib)
(require 'yeah-acp)

(defvar yeah-check--emitted nil
  "Messages the ACP dispatcher emitted during the check.")

(defun yeah-check--parse (text)
  "Parse TEXT as a JSON object with plist and list types."
  (json-parse-string text :object-type 'plist :array-type 'list))

(defun yeah-check--response (method params)
  "Return the parsed JSON-RPC response for METHOD with PARAMS, or nil."
  (let* ((request (format "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"%s\",\"params\":%s}"
                           method params))
         (raw (yeah-acp-handle-message request)))
    (and raw (yeah-check--parse raw))))

(defun yeah-check--result (method params)
  "Return the result object of the response for METHOD with PARAMS."
  (plist-get (yeah-check--response method params) :result))

(defun yeah-check--answer-for (id)
  "Return the parsed message answering request ID, or nil."
  (let ((text (cl-find-if (lambda (line)
                            (equal id (plist-get (yeah-check--parse line) :id)))
                          yeah-check--emitted)))
    (and text (yeah-check--parse text))))

(defun yeah-check--run (cwd)
  "Drive the dispatcher over CWD and return a failure message, or nil."
  (let ((failure nil))
    (let ((result (yeah-check--result "initialize" "{\"protocolVersion\":1}")))
      (unless (and result (equal 1 (plist-get result :protocolVersion)))
        (setq failure "initialize was not answered with protocol version 1")))
    (let* ((session (yeah-check--result
                     "session/new"
                     (format "{\"cwd\":\"%s\",\"mcpServers\":null}" cwd)))
           (session-id (plist-get session :sessionId)))
      (unless (stringp session-id)
        (setq failure "session/new was not answered with a session id"))
      (let ((loaded (yeah-check--result
                     "session/load"
                     (format "{\"cwd\":\"%s\",\"sessionId\":\"%s\"}"
                             cwd session-id))))
        (unless loaded
          (setq failure "session/load was not answered")))
      (setq yeah-check--emitted nil)
      (let ((raw (yeah-acp-handle-message
                  (json-serialize
                   (list :jsonrpc "2.0"
                         :id 2
                         :method "session/prompt"
                         :params (list :sessionId session-id
                                       :prompt (vector (list :type "text"
                                                             :text "hi"))))))))
        (unless (null raw)
          (setq failure "session/prompt answered before the turn reached a terminal state")))
      (let* ((answer (yeah-check--answer-for 2))
             (stop (plist-get (plist-get answer :result) :stopReason)))
        (unless (equal "end_turn" stop)
          (setq failure
                (format "session/prompt was not answered with the end_turn stop reason: %S in %S"
                        stop yeah-check--emitted))))
      (let ((raw (yeah-acp-handle-message
                  (json-serialize
                   (list :jsonrpc "2.0"
                         :method "session/cancel"
                         :params (list :sessionId session-id))))))
        (unless (null raw)
          (setq failure (format "session/cancel answered a notification: %S" raw))))
      (let ((unknown (yeah-check--response "session/unknown" "{}")))
        (unless (and (plist-member unknown :error)
                     (= -32601 (plist-get (plist-get unknown :error) :code)))
          (setq failure "an unknown method was not refused with -32601")))
      (let ((invalid (yeah-check--response "session/new" "{}")))
        (unless (and (plist-member invalid :error)
                     (= -32602 (plist-get (plist-get invalid :error) :code)))
          (setq failure "an invalid request was not refused with -32602"))))
    failure))

(let* ((home (make-temp-file "yeah-acp-check" t))
       (cwd (file-truename home))
       (failure nil)
       yeah-data-home)
  (setq yeah-data-home home)
  (unwind-protect
      (progn
        (setq yeah-check--emitted nil
              yeah-acp--output-function
              (lambda (text) (push text yeah-check--emitted))
              yeah-acp--transport
              (lambda (_prompt callback) (funcall callback "the answer")))
        (setq failure (yeah-check--run cwd)))
    (yeah-acp--reset-for-test)
    (delete-directory home t t))
  (when failure
    (message "%s" failure)
    (kill-emacs 1)))

(kill-emacs 0)

;;; check-acp-dispatcher-routes-every-method.el ends here
