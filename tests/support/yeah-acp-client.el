;;; yeah-acp-client.el --- the client of the checks of the wire -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The checks of the wire need a client that speaks to a real ACP server: it
;; opens a session, sends requests, answers the questions of the server about
;; a permission and reads the notifications of the server.
;;
;; The client is a file of its own: a source that is written twice is a
;; source that is wrong twice.  The questions and the notifications live in
;; the closure of the client -- a list that a function pushes into is the
;; list of that function, and not the list of the caller -- and the readers
;; of them are functions that return what has come.

;;; Code:

(require 'cl-lib)
(require 'yeah-client)

(defun yeah-acp-client-connect (socket)
  "Connect to the ACP server at SOCKET and return the client and two readers.
The result is the client, a function that returns the questions of the
server about a permission, and a function that returns the notifications of
the server.  The questions and the notifications live in the closure of the
client: a list that a function pushes into is the list of that function, and
not the list of the caller."
  (let (questions updates)
    (let ((client (yeah-client-connect
                   socket
                   :on-notification
                   (lambda (message) (push message updates))
                   :on-request
                   (lambda (method params respond)
                     (push (list :method method :params params) questions)
                     (funcall respond
                              (list :outcome (list :outcome "selected"
                                                   :optionId "allow-once")))))))
      (list client
            (lambda () (reverse questions))
            (lambda () (reverse updates))))))

(defun yeah-acp-client-request (client method params &optional timeout)
  "Send METHOD with PARAMS to CLIENT and wait for the answer of the server.
The answer is returned as a plist with `:result' and `:error'; a server
that did not answer at all gives a plist with neither."
  (let ((answer nil))
    (yeah-client-request client method params
      (lambda (result error)
        (setq answer (list :result result :error error))))
    (let ((deadline (+ (float-time) (or timeout 30))))
      (while (and (null answer) (< (float-time) deadline))
        (accept-process-output nil 0.05)))
    (or answer (list))))

(defun yeah-acp-client-tool-calls (updates)
  "Return the calls of the tools that the notifications UPDATES announced."
  (delq nil
        (mapcar (lambda (message)
                  (let ((update (plist-get (plist-get message :params) :update)))
                    (when (and update
                               (equal "tool_call" (plist-get update :sessionUpdate)))
                      update)))
                updates)))

(defun yeah-acp-client-update-of (updates kind)
  "Return the update of the kind KIND that the notifications UPDATES carry.
The update is inside the notification: the notification of ACP carries the
session and the update, and the update names what happened."
  (let ((params
         (cl-find-if
          (lambda (message)
            (let ((update (plist-get (plist-get message :params) :update)))
              (equal kind (plist-get update :sessionUpdate))))
          updates)))
    (and params (plist-get (plist-get params :params) :update))))

(provide 'yeah-acp-client)

;;; yeah-acp-client.el ends here
