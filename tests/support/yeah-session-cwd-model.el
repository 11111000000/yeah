;;; yeah-session-cwd-model.el --- the fake model of the session directory check -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The check of the directory of a session needs a model that acts in the
;; directory of the session and not in the directory of the process.  The
;; model of this file is a FAKE: it asks for the `read' tool with a relative
;; name and then ends the run with the `finish' tool.
;;
;; The file is loaded, not required: it defines the transport of the model
;; and the check names it.  The server process of the check loads it too, so
;; that the check and the server run the same model.

;;; Code:

(defvar yeah-session-cwd-model--calls 0
  "How many times the fake model of the check answered.")

(defun yeah-session-cwd-model--finish ()
  "Return the answer that ends the run of the fake model.
The answer is a call of the `finish' tool: a supervised run does not end
with words (wave 53)."
  (list 'tool-call
        (list (list :name "finish")
              (list "the model of the check is done")
              (lambda (_value) nil))))

(defun yeah-session-cwd-model-transport (prompt callback)
  "Read the file of the session by its relative name and end the run.
PROMPT is what the turn asked; CALLBACK takes the answer in the shape
gptel uses.  The first answer asks for the `read' tool with the relative
name `marker.txt': the tool must find the file in the directory of the
session.  The second answer ends the run through the `finish' tool, because
a supervised run does not end with words (wave 53)."
  (setq yeah-session-cwd-model--calls (1+ yeah-session-cwd-model--calls))
  (if (= yeah-session-cwd-model--calls 1)
      (funcall callback
               (list 'tool-call
                     (list (list :name "read")
                           (list "marker.txt")
                           (lambda (_value)
                             (funcall callback
                                      (yeah-session-cwd-model--finish))))))
    (funcall callback (yeah-session-cwd-model--finish))))

(provide 'yeah-session-cwd-model)

;;; yeah-session-cwd-model.el ends here
