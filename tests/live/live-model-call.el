;;; live-model-call.el --- a real model call through Yeah's transport -*- lexical-binding: t; -*-
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
;; through `yeah-gptel-request' — the one place where Yeah calls the model
;; — and checks that an answer comes back.
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
;; Exit codes: 0 — an answer came back, or there was no key to ask with;
;; 1 — the model did not answer.

;;; Code:

(require 'gptel)
(require 'yeah-gptel)

(let ((key (getenv "YEAH_TEST_KEY"))
      (host (or (getenv "YEAH_TEST_HOST") "api.minimax.io"))
      (model (or (getenv "YEAH_TEST_MODEL") "MiniMax-M3.1-Flash")))

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

  (let ((answer nil)
        (status nil))
    (yeah-gptel-request
     "Answer with the single word: OK"
     (lambda (response &optional info)
       (when (stringp response)
         (setq answer response))
       (when (plist-get info :status)
         (setq status (plist-get info :status)))))
    ;; the request is asynchronous: the answer arrives on the event loop
    (let ((waited 0))
      (while (and (null answer) (< waited 60))
        (accept-process-output nil 1)
        (setq waited (1+ waited))))
    (message "live: status=%S answer=%S" status answer)
    (if (and answer (stringp answer) (not (string-empty-p answer)))
        (kill-emacs 0)
      (kill-emacs 1))))

;;; live-model-call.el ends here
