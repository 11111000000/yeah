;;; yeah-session-usage-model.el --- the fake model of the checks of the usage -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The check of the usage of a turn needs a model that says how many tokens it
;; spent, because that is the only source the kernel has: the kernel does not
;; count the tokens of a provider itself and it does not guess them.
;;
;; The model of this file is a FAKE.  It ends the run with the `finish' tool
;; and reports the tokens of the turn in the info of its answer, the way gptel
;; reports them.  The prompt names the tokens the model spent (`spend 1200'),
;; and the model reads the last number it names: the transcript of the run grows
;; in front of the prompt and never behind it, so the last number is the one of
;; this turn.  A prompt that says `quiet' makes the model answer without the
;; info: the kernel must not invent the tokens of a provider that said nothing.
;;
;; The file is loaded, not required: it defines the transport of the model and
;; the check names it.  The server process of the check loads it too, so that
;; the check and the server run the same model.

;;; Code:

(defvar yeah-session-usage-model--input 1200
  "The input tokens the fake model of the checks reports by default.")

(defvar yeah-session-usage-model--output 34
  "The output tokens the fake model of the checks reports.")

(defun yeah-session-usage-model--finish ()
  "Return the answer that ends the run of the fake model.
The answer is a call of the `finish' tool: a supervised run does not end
with words (wave 53)."
  (list 'tool-call
        (list (list :name "finish")
              (list "the model of the check is done")
              (lambda (_value) nil))))

(defun yeah-session-usage-model--tokens (prompt)
  "Return the tokens the model reports for PROMPT.
The prompt names the tokens the model spent; the last number it names is the
one of this turn, because the transcript of the run grows in front of the
prompt and never behind it."
  (let ((named nil)
        (start 0))
    (while (string-match "spend \\([0-9]+\\)" prompt start)
      (push (string-to-number (match-string 1 prompt)) named)
      (setq start (match-end 0)))
    (list :input (or (car named) yeah-session-usage-model--input)
          :output yeah-session-usage-model--output)))

(defun yeah-session-usage-model-transport (prompt callback)
  "End the run and report the tokens of the turn.
PROMPT is what the turn asked; CALLBACK takes the answer of the model and the
info of the turn.  The model reports the tokens it spent, and a prompt that
says `quiet' makes it answer without the info: the kernel must not guess the
tokens of a provider that said nothing.

A prompt that says `thinking' makes the model send its reasoning first, with
the same info: the transport of gptel hands the info of a request to every
shape of it, and the reasoning and the answer that follows it carry the same
tokens."
  (cond
   ((and (stringp prompt) (string-match-p "quiet" prompt))
    (funcall callback (yeah-session-usage-model--finish)))
   ((and (stringp prompt) (string-match-p "thinking" prompt))
    (let ((info (list :yeah-usage (yeah-session-usage-model--tokens prompt))))
      (funcall callback (cons 'reasoning "the model thinks about it") info)
      (funcall callback (yeah-session-usage-model--finish) info)))
   (t
    (funcall callback (yeah-session-usage-model--finish)
              (list :yeah-usage (yeah-session-usage-model--tokens prompt))))))

(provide 'yeah-session-usage-model)
;;; yeah-session-usage-model.el ends here
