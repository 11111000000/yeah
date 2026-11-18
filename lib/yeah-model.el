;;; yeah-model.el --- the models a session may run on -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A session runs on a model, and the model is a property of the session: two
;; sessions of the same service may run on different models, and a client may
;; change the model of a session while it works.
;;
;; The catalog of the models is what the client may choose from, and it must
;; name the models that can really run: a model that the transport does not
;; know is a model the harness cannot use.  The catalog of the harness comes
;; first (`yeah-model-catalog'), and the models the transport knows follow it.
;; In the deployment the transport is gptel, and the models of the backend of
;; gptel are the models the plugin registered.
;;
;; The transport of the service is one transport for every session, and the
;; model of a session is bound around the call of that transport: the model in
;; force is a property of the call, and two sessions that work at the same
;; time do not see each other's model.  The transport keeps its shape -- it
;; takes a prompt and a callback -- and the model travels beside it.

;;; Code:

(require 'cl-lib)

(defgroup yeah-model nil
  "The models a session may run on."
  :group 'yeah)

(defvar yeah-model-catalog nil
  "The names of the models a session may run on.
Nil means the catalog is what the transport of the service knows: the
models of the backend of gptel.  A name in this list is offered to the
client whatever the transport knows, and it comes first in the catalog.")

(defvar yeah-model--current nil
  "The name of the model the run in force runs on.
It is bound around the call of the model transport: the transport of the
service is one for every session, and the model of a session is a property
of that session.")

(defun yeah-model--transport-names ()
  "Return the names of the models the transport of the service knows.
The transport is gptel, and the models of its backend are the models that
can really run.  A harness without gptel knows no models of its own."
  (when (and (boundp 'gptel-backend)
             (fboundp 'gptel-backend-models)
             gptel-backend)
    (mapcar #'symbol-name (gptel-backend-models gptel-backend))))

(defun yeah-model-names ()
  "Return the names of the models a session may run on, in order.
The catalog of the harness comes first, and the models the transport knows
follow it.  A name is in the list once."
  (delete-dups (append yeah-model-catalog (yeah-model--transport-names))))

(defun yeah-model-default ()
  "Return the name of the model a session runs on when nobody chose another.
The model the transport would use comes first, and the first model of the
catalog is the fallback: a session that nobody gave a model still runs on a
model the client can name."
  (or (and (boundp 'gptel-model)
           gptel-model
           (if (symbolp gptel-model) (symbol-name gptel-model) gptel-model))
      (car (yeah-model-names))))

(defun yeah-model-known-p (name)
  "Return non-nil when NAME names a model a session may run on."
  (and (stringp name) (member name (yeah-model-names))))

(defun yeah-model-symbol (name)
  "Return the symbol of the model NAME, as the transport of gptel knows it.
The name comes from the catalog, and the catalog names the models of the
backend: the symbol of such a name is the symbol the backend knows."
  (and (stringp name) (not (string-empty-p name)) (intern name)))

(defun yeah-model-current ()
  "Return the name of the model the run in force runs on, or nil."
  yeah-model--current)

(provide 'yeah-model)
;;; yeah-model.el ends here
