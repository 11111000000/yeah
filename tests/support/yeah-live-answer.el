;;; yeah-live-answer.el --- what counts as an answer of a real model -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The live stands of this repository ask a real model and must decide whether
;; the provider answered.  The decision is not obvious:
;;
;;   - a model that reasons sends the empty string between its thinking and
;;     its answer; the empty string is the road to the answer, not the answer;
;;   - gptel sends the sentinel `t' while the answer is still coming;
;;   - a model that acts instead of talking answers with a tool call, and that
;;     is an answer: the model reached for a tool and the transport carried
;;     the call;
;;   - a request that ends in an error is the end of the road.
;;
;; Only text with content and a tool call are answers.  The decision lives in
;; the kernel (`lib/yeah-answer.el'), because the kernel has to make it too:
;; the run loop and the compaction of the context meet the same shapes.  This
;; file is the name that the stands of the tests have always used.

;;; Code:

(require 'yeah-answer)

(defun yeah-live-answer-shape (response)
  "Return the shape of RESPONSE.
The shape is one of the symbols `none', `empty', `text', `stream',
`reasoning', `tool-call', `tool-result', `error' and `unknown'."
  (yeah-answer-shape response))

(defun yeah-live-answer-answered-p (response)
  "Return non-nil when RESPONSE is an answer of the model.
Text with content and a tool call are answers: the model spoke, or it acted.
The empty string, the streaming sentinel, the reasoning and the result of an
earlier tool call are not: they are the road to the answer."
  (yeah-answer-answered-p response))

(defun yeah-live-answer-error (response)
  "Return the reason of an error RESPONSE, or nil."
  (yeah-answer-error response))

(defun yeah-live-answer-text (response)
  "Return the text of RESPONSE, or nil when it carries none."
  (yeah-answer-text response))

(provide 'yeah-live-answer)

;;; yeah-live-answer.el ends here
