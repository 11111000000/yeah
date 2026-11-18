;;; yeah-tool-call-model.el --- the fake model of the checks of a call -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The checks of the kind of a call and of its named arguments need a model
;; that calls a tool.  The model of this file is a FAKE: it asks for the
;; `read' tool with a relative name and then ends the run with the `finish'
;; tool.
;;
;; The file is loaded, not required: it defines the transport of the model
;; and the check names it.  The server process of the check loads it too, so
;; that the check and the server run the same model.

;;; Code:

(defvar yeah-tool-call-model--calls 0
  "How many times the fake model of the checks answered.")

(defun yeah-tool-call-model--finish ()
  "Return the answer that ends the run of the fake model.
The answer is a call of the `finish' tool: a supervised run does not end
with words (wave 53)."
  (list 'tool-call
        (list (list :name "finish")
              (list "the model of the check is done")
              (lambda (_value) nil))))

(defun yeah-tool-call-model-transport (prompt callback)
  "Read the file of the session by its relative name and end the run.
PROMPT is what the turn asked; CALLBACK takes the answer in the shape
gptel uses.  The first answer asks for the `read' tool with the relative
name `marker.txt': the call of the tool is what the wire of the check
reads.  The second answer ends the run through the `finish' tool, because
a supervised run does not end with words (wave 53)."
  (setq yeah-tool-call-model--calls (1+ yeah-tool-call-model--calls))
  (if (= yeah-tool-call-model--calls 1)
      (funcall callback
               (list 'tool-call
                     (list (list :name "read")
                           (list "marker.txt")
                           (lambda (_value)
                             (funcall callback
                                      (yeah-tool-call-model--finish))))))
    (funcall callback (yeah-tool-call-model--finish))))

(provide 'yeah-tool-call-model)

;;; yeah-tool-call-model.el ends here
