;;; yeah-session-model.el --- the fake model of the checks of the model -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The check of the model of a session needs a model that writes down the
;; model it runs on: the model of a session is bound around the call of the
;; transport, and the model of this file reads that binding and writes the
;; name it found into a file of the session.  The model of this file is a
;; FAKE.
;;
;; The file is written by its relative name, so that it lands in the
;; directory of the session and not in the directory of the process: the
;; check reads the file in the directory of the session and learns the model
;; the run really used.
;;
;; The file is loaded, not required: it defines the transport of the model
;; and the check names it.  The server process of the check loads it too, so
;; that the check and the server run the same model.

;;; Code:

(require 'yeah-model)

(defvar yeah-session-model--calls 0
  "How many times the fake model of the checks answered.")

(defun yeah-session-model--finish ()
  "Return the answer that ends the run of the fake model.
The answer is a call of the `finish' tool: a supervised run does not end
with words (wave 53)."
  (list 'tool-call
        (list (list :name "finish")
              (list "the model of the check is done")
              (lambda (_value) nil))))

(defun yeah-session-model--write (callback)
  "Return the answer that asks for the `write' tool with the model in force.
The file is named by its relative name, so that it lands in the directory
of the session and not in the directory of the process.  The content of the
file is the name of the model the run is on.  The tool of the call answers
with the answer that ends the run: the turn of a model ends when the tool
it asked for has answered."
  (list 'tool-call
        (list (list :name "write")
              (list "model-used.txt" (or (yeah-model-current) "no-model"))
              (lambda (_value)
                (funcall callback (yeah-session-model--finish))))))

(defun yeah-session-model-transport (prompt callback)
  "Write down the model in force and end the run.
PROMPT is what the turn asked; CALLBACK takes the answer in the shape
gptel uses.  The answer asks for the `write' tool, and the run ends when
that tool has answered, because a supervised run does not end with words
(wave 53)."
  (setq yeah-session-model--calls (1+ yeah-session-model--calls))
  (funcall callback (yeah-session-model--write callback)))

(provide 'yeah-session-model)

;;; yeah-session-model.el ends here
