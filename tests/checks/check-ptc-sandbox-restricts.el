;;; check-ptc-sandbox-restricts.el --- canary for the PTC sandbox -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The Programmatic Tool Calling sandbox is supposed to be a sandbox. Two
;; properties follow from that, and this check asserts both:
;;
;;   1. a form whose `:name' is not on the whitelist is rejected;
;;   2. a form whose `:name' IS on the whitelist, but whose body calls
;;      something outside the whitelist, is rejected as well, and the file
;;      it tried to touch is still there.
;;
;; Property 2 does not hold today: the whitelist gates the NAME of the
;; binding, not the code inside the form, so a form named "read" can
;; delete a file. The check fails today, and that is the point: it is the
;; canary for the claim `ptc-sandbox-restricts-model-code`.
;;
;; Exit codes: 0 — the sandbox holds; 1 — it does not.

;;; Code:

(require 'yeah-codes)

(let* ((canary (expand-file-name "yeah-ptc-canary.txt" temporary-file-directory))
       (failure nil))

  ;; Property 1: an unwhitelisted name is refused.
  (condition-case nil
      (progn
        (yeah-codes-eval (list (list :name "not-whitelisted" :code "42")) nil)
        (setq failure 'the-unwhitelisted-name-was-accepted))
    (user-error nil))

  ;; Property 2: a whitelisted name carrying a call outside the whitelist
  ;; is refused, and the world outside is untouched.
  (write-file canary "alive")
  (ignore-errors
    (yeah-codes-eval
     (list (list :name "read"
                 :code (format "(delete-file \"%s\")" canary)))
     nil))
  (unless (file-exists-p canary)
    (setq failure 'the-model-code-was-executed))
  (when (file-exists-p canary)
    (delete-file canary))

  (if failure
      (progn
        (message "ptc sandbox: %s" failure)
        (kill-emacs 1))
    (kill-emacs 0)))

;;; check-ptc-sandbox-restricts.el ends here
