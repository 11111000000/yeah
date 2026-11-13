;;; check-subagent-depth-limit-is-enforced.el --- canary for the depth limit -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The ERT suite reads the depth limit; it does not assert that the limit is
;; enforced at the spawn. This check does: a spawn whose child would sit at
;; the limit must be refused.
;;
;; Exit codes: 0 — the limit holds; 1 — a spawn past it was accepted.

;;; Code:

(require 'yeah-subagent)
(require 'yeah-session)

(let* ((tmpdir (file-name-as-directory (make-temp-file "yeah-subagent-check" t)))
       (parent (yeah-session-open "depth" tmpdir))
       (outcome nil)
       (failure nil))
  (unwind-protect
      (progn
        (yeah-subagent-reset-for-test)
        (condition-case nil
            (progn
              (yeah-subagent-spawn parent "explore" "too deep"
                                   :depth (1- (yeah-subagent-depth-limit))
                                   :transport (lambda (_prompt callback)
                                                (funcall callback "the answer")))
              (setq outcome 'accepted))
          (user-error (setq outcome 'refused)))
        (unless (eq outcome 'refused)
          (setq failure "the depth limit was not enforced: the spawn was accepted"))
        ;; A spawn within the limit is accepted: the limit must bound the
        ;; tree and not forbid it.
        (condition-case nil
            (progn
              (yeah-subagent-spawn parent "explore" "deep enough"
                                   :depth (- (yeah-subagent-depth-limit) 2)
                                   :transport (lambda (_prompt callback)
                                                (funcall callback "the answer")))
              (setq outcome 'accepted))
          (user-error (setq outcome 'refused)))
        (unless (eq outcome 'accepted)
          (setq failure "a spawn within the depth limit was refused"))
        (yeah-subagent-reset-for-test))
    (ignore-errors (delete-directory tmpdir t t)))
  (when failure
    (message "%s" failure)
    (kill-emacs 1)))

(kill-emacs 0)

;;; check-subagent-depth-limit-is-enforced.el ends here
