;;; yeah-mode-model.el --- the fake model of the checks of a mode -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The check of the mode of a session needs a model that calls a tool that
;; changes the world: the `write' tool.  In the `plan' mode the write is
;; refused without a question, and in the `build' mode the client is asked
;; about it.  The model of this file is a FAKE.
;;
;;; The model writes one file per turn: every answer of the model asks for
;; the `write' tool, and the answer that ends the run comes from the
;; callback of that tool.  The transport of a turn is called once, and the
;; turn ends when the tool it asked for has answered.
;;
;; The file is loaded, not required: it defines the transport of the model
;; and the check names it.  The server process of the check loads it too, so
;; that the check and the server run the same model.

;;; Code:

(defvar yeah-mode-model--calls 0
  "How many times the fake model of the checks answered.")

(defun yeah-mode-model--finish ()
  "Return the answer that ends the run of the fake model.
The answer is a call of the `finish' tool: a supervised run does not end
with words (wave 53)."
  (list 'tool-call
        (list (list :name "finish")
              (list "the model of the check is done")
              (lambda (_value) nil))))

(defun yeah-mode-model--write (callback)
  "Return the answer that asks for the `write' tool.
The file is named by its relative name, so that it lands in the directory
of the session and not in the directory of the process.  The tool of the
call answers with the answer that ends the run: the turn of a model ends
when the tool it asked for has answered."
  (list 'tool-call
        (list (list :name "write")
              (list "written.txt" "written by the model of the check")
              (lambda (_value)
                (funcall callback (yeah-mode-model--finish))))))

(defun yeah-mode-model-transport (prompt callback)
  "Call the `write' tool and end the run.
PROMPT is what the turn asked; CALLBACK takes the answer in the shape
gptel uses.  The answer asks for the `write' tool, and the run ends when
that tool has answered, because a supervised run does not end with words
(wave 53)."
  (setq yeah-mode-model--calls (1+ yeah-mode-model--calls))
  (funcall callback (yeah-mode-model--write callback)))

(provide 'yeah-mode-model)

;;; yeah-mode-model.el ends here
