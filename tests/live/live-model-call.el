;;; live-model-call.el --- a real model call through Yeah's transport -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The other checks of this repository never touch the network: they put a
;; fake model under the transport. This one does not. It asks a real model
;; through `yeah-gptel-request' — the one place where Yeah calls the model —
;; and checks that an answer comes back.
;;
;; It is not part of the suite, because it costs money and needs a key.
;; It is here so that the claim about the transport can be checked against
;; the world and not only against a fake.
;;
;; The configuration comes from the environment, so that no key is ever
;; written into this repository:
;;
;;   YEAH_TEST_KEY    the API key; without it the check skips
;;   YEAH_TEST_HOST   the API host, for example api.minimax.io
;;   YEAH_TEST_MODEL  the model, for example MiniMax-M3.1-Flash
;;
;; The gptel on the load path must be a version Yeah supports: see
;; `yeah-gptel--supported-versions'.  The OpenAI backend lives in
;; `gptel-openai' since gptel 0.9.8, and it is required here.
;;
;; What counts as an answer.  A model that reasons sends its thinking and,
;; between the thinking and the answer, an empty string: the empty string is
;; not an answer, and the check waits for the answer that follows it.  A
;; model that acts instead of talking answers with a tool call, and that is
;; an answer as well: the model reached for a tool and the transport carried
;; the call.  Only a request that ends in an error, or a model that says
;; nothing at all, fails the check.  The shape of the answer is printed, so
;; that a reader of a failed run knows what the provider said.
;;
;; Exit codes: 0 — an answer came back, or there was no key to ask with;
;; 1 — the model did not answer.

;;; Code:

(require 'gptel)
(require 'gptel-openai)
(require 'yeah-gptel)
(load (expand-file-name "../support/yeah-live-answer.el"
                        (file-name-directory (or load-file-name default-directory))))

(let* ((key (getenv "YEAH_TEST_KEY"))
       (host (or (getenv "YEAH_TEST_HOST") "api.minimax.io"))
       (model (or (getenv "YEAH_TEST_MODEL") "MiniMax-M3.1-Flash"))
       (answer nil)
       (shape nil)
       (reason nil)
       (status nil)
       (calls 0)
       (last 0.0))

  (unless key
    (message "live: skipped — no YEAH_TEST_KEY in the environment")
    (kill-emacs 0))

  (setq gptel-backend
        (gptel-make-openai "yeah-live"
          :host host
          :endpoint "/v1/chat/completions"
          :key key
          :models (list (intern model))))
  (setq gptel-model (intern model))

  (yeah-gptel-request
   "Answer with the single word: OK"
   (lambda (response &optional info)
     (setq calls (1+ calls))
     (setq last (float-time))
     (when (plist-get info :status)
       (setq status (plist-get info :status)))
     ;; The shape of the answer decides the verdict.  The empty string that a
     ;; model that reasons sends between its thinking and its answer is not an
     ;; answer, and the stand waits for the answer that follows it; a tool
     ;; call is an answer, because the model acted.
     (let ((kind (yeah-live-answer-shape response)))
       (cond
        ((eq kind 'text)
         (setq answer (yeah-live-answer-text response)
               shape 'text))
        ((eq kind 'tool-call)
         (setq shape 'tool-call))
        ((eq kind 'error)
         (setq shape 'error
               reason (yeah-live-answer-error response)))))))

  ;; The request is asynchronous: the answer arrives on the event loop.
  ;; The wait ends when the provider has been quiet for a moment after the
  ;; answer, or when the budget of the wait is spent.
  (let ((waited 0)
        (quiet 0))
    (while (and (< waited 90)
                (or (null shape)
                    (< quiet 3)))
      (accept-process-output nil 1)
      (setq waited (1+ waited))
      (setq quiet (if (and shape (> (- (float-time) last) 2))
                      (1+ quiet)
                    0))))

  (message "live: status=%S shape=%S calls=%d answer=%S reason=%S"
           status shape calls answer reason)
  (if (and shape (not (eq shape 'error)))
      (kill-emacs 0)
    (kill-emacs 1)))

;;; live-model-call.el ends here
