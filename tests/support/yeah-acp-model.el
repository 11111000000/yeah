;;; yeah-acp-model.el --- the wire of the model of a session, for the checks -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The check of the model of a session needs a service that knows the models
;; a session may run on, and a model that writes down the model it runs on.
;;
;; The catalog of the models is a property of the service: the service is
;; started with a catalog of two models, and the client chooses one of them
;; over the wire.  The catalog of the service is what the kernel offers the
;; client, and a model that is not in the catalog is refused.
;;
;; The server is a service on a socket and not a server on stdio: the client
;; of a service keeps reading while a run works, and that is the deployment
;; of the wire of Yeah.

;;; Code:

(require 'cl-lib)
(require 'yeah-client)
(require 'yeah-service)

(load (expand-file-name "yeah-acp-client.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil
      t)

(defconst yeah-acp-model--catalog '("model-a" "model-b")
  "The models a session of the service may run on.
The service is started with this catalog, and the kernel offers it to the
client: the models of the catalog are the models that can really run.")

(defun yeah-acp-model--model-file ()
  "Return the file that holds the fake model of the server."
  (expand-file-name "tests/support/yeah-session-model.el"))

(defun yeah-acp-model--model-source ()
  "Return the source of the fake model of the server.
The model is a file of its own and not a string in a check: the service
loads it in its own Emacs, and a source that is written twice is a source
that is wrong twice.  The catalog of the models is set beside it, because
the catalog is a property of the service."
  (with-temp-buffer
    (insert-file-contents (yeah-acp-model--model-file))
    (insert (format "\n(setq yeah-model-catalog '%S)\n" yeah-acp-model--catalog))
    (buffer-string)))

(defun yeah-acp-model--start (name data-home)
  "Start the service of the checks under NAME with the data home DATA-HOME.
The model of the service is the fake one of the checks, and the catalog of
the models is the one of the checks."
  (yeah-service-start name
                      (yeah-acp-model--model-source)
                      data-home
                      "#'yeah-session-model-transport"
                      t
                      nil))

(provide 'yeah-acp-model)

;;; yeah-acp-model.el ends here
