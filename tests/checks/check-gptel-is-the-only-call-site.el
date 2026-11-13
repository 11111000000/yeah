;;; check-gptel-is-the-only-call-site.el --- canary for the model call -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The model is called in exactly one place: `yeah-gptel-request' in
;; lib/yeah-gptel.el. Everything else — the turn, the REPL, the ACP
;; handlers — reaches the model through that function, so that there is
;; one answer to where the model is called, one place where the prompt
;; is assembled, and one place to look when the transport changes.
;;
;; The check reads the tree: no other module of lib/ may call gptel's
;; request API. A module that calls it directly is a second integration
;; point, and a second integration point is a second truth.
;;
;; Exit codes: 0 — one call site; 1 — more than one, or none at all.

;;; Code:

(require 'yeah-turn)
(require 'yeah-gptel)

(let ((failures nil))

  (unless (fboundp 'yeah-gptel-request)
    (push "there is no yeah-gptel-request: the model has no single call site"
          failures))

  (dolist (file (directory-files "lib" t "\\.el\\'"))
    (unless (string= (file-name-nondirectory file) "yeah-gptel.el")
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (search-forward "(gptel-request " nil t)
          (push (format "%s calls the model directly"
                        (file-name-nondirectory file))
                failures)))))

  (with-temp-buffer
    (insert-file-contents "lib/yeah-turn.el")
    (goto-char (point-min))
    (unless (search-forward "yeah-gptel-request" nil t)
      (push "the turn does not fall back on the gptel bridge" failures)))

  (dolist (failure failures)
    (message "gptel: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-gptel-is-the-only-call-site.el ends here
