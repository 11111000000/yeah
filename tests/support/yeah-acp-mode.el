;;; yeah-acp-mode.el --- the wire of the mode of a session, for the checks -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The check of the mode of a session needs a client that speaks to a real
;; ACP server: it opens a session, changes the mode of the session, asks
;; the session to do something that changes the world, and answers the
;; question about the permission when the server asks one.  The client
;; itself lives in `yeah-acp-client.el': a source that is written twice is
;; a source that is wrong twice.
;;
;; The server is a service on a socket and not a server on stdio: a server on
;; stdio reads its input between the requests, so the answer of the client
;; to a question about a permission would come after the run it belongs to
;; had ended.  A service on a socket keeps reading while a run works, and
;; that is the deployment of the wire of Yeah.
;;
;; The model of the server writes a file by its relative name, so that the
;; file lands in the directory of the session: a session that may change the
;; world leaves a file behind, and a session that may not leaves none.

;;; Code:

(require 'cl-lib)
(require 'yeah-client)
(require 'yeah-service)

(load (expand-file-name "yeah-acp-client.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil
      t)

(defun yeah-acp-mode--model-file ()
  "Return the file that holds the fake model of the server."
  (expand-file-name "tests/support/yeah-mode-model.el"))

(defun yeah-acp-mode--model-source ()
  "Return the source of the fake model of the server.
The model is a file of its own and not a string in a check: the service
loads it in its own Emacs, and a source that is written twice is a source
that is wrong twice."
  (with-temp-buffer
    (insert-file-contents (yeah-acp-mode--model-file))
    (buffer-string)))

(defun yeah-acp-mode--start (name data-home)
  "Start the service of the checks under NAME with the data home DATA-HOME.
The model of the service is the fake one of the checks."
  (yeah-service-start name
                      (yeah-acp-mode--model-source)
                      data-home
                      "#'yeah-mode-model-transport"
                      t
                      nil))

(provide 'yeah-acp-mode)

;;; yeah-acp-mode.el ends here
