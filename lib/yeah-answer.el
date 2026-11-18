;;; yeah-answer.el --- what counts as an answer of a model -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The transport of Yeah answers with the shapes of gptel, and the shapes do
;; not all mean the same thing:
;;
;;   - a model that reasons sends its thinking before its answer, and the
;;     thinking is not the answer: it is the road to the answer;
;;   - a model that acts instead of talking answers with a tool call, and that
;;     is an answer: the model reached for a tool and the transport carried
;;     the call;
;;   - the result of a tool that ran is on its way to the model, and it is
;;     not the answer either;
;;   - gptel sends the sentinel `t' when the stream is over;
;;   - a request that ends in an error is the end of the road.
;;
;; The decision lives here, in the kernel, and not in the stands that ask a
;; real model: the run loop has to make it, the compaction of the context has
;; to make it, and a stand that decides it alone cannot be checked offline.
;; The stands that used to decide it for themselves (`tests/support/
;; yeah-live-answer.el') are wrappers around this module now.

;;; Code:

(defun yeah-answer-shape (response)
  "Return the shape of RESPONSE.
The shape is one of the symbols `none', `empty', `text', `stream',
`reasoning', `tool-call', `tool-result', `error' and `unknown'."
  (cond
   ((null response) 'none)
   ((stringp response) (if (string-empty-p response) 'empty 'text))
   ((eq response t) 'stream)
   ((and (consp response)
         (memq (car response) '(reasoning tool-call tool-result)))
    (car response))
   ((and (consp response) (eq (car response) 'error)) 'error)
   (t 'unknown)))

(defun yeah-answer-answered-p (response)
  "Return non-nil when RESPONSE is an answer of the model.
Text with content and a tool call are answers: the model spoke, or it acted.
The empty string, the streaming sentinel, the reasoning and the result of an
earlier tool call are not: they are the road to the answer."
  (memq (yeah-answer-shape response) '(text tool-call)))

(defun yeah-answer-end-p (response)
  "Return non-nil when RESPONSE ends the request of the provider.
Everything but the road to the answer ends the request: the text that the
model wrote, the tool it called, the error of the provider and the sentinel
of a stream that is over.  The reasoning and the result of a tool that ran do
not end it: the answer comes after them."
  (not (memq (yeah-answer-shape response) '(reasoning tool-result))))

(defun yeah-answer-error (response)
  "Return the reason of an error RESPONSE, or nil."
  (when (eq (yeah-answer-shape response) 'error)
    (cdr response)))

(defun yeah-answer-text (response)
  "Return the text of RESPONSE, or nil when it carries none.
A text with content is the text of the answer; an empty answer carries none."
  (when (eq (yeah-answer-shape response) 'text)
    response))

(provide 'yeah-answer)

;;; yeah-answer.el ends here
