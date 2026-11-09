;;; check-gptel-request-shape.el --- canary for the transport seam -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The transport is a seam, and a seam is worth nothing unless both sides
;; agree on its shape. This check puts a fake gptel under the seam and
;; asserts that `yeah-gptel-request' speaks to it the way gptel speaks:
;; the prompt first, the callback as a keyword, and the answer back
;; through that callback.
;;
;; No network is touched and gptel need not be installed: the fake is
;; defined before the transport is loaded, and it stands in for gptel.
;;
;; Exit codes: 0 — the seam holds; 1 — it does not.

;;; Code:

;; The fake gptel: it records how it was called and answers at once.
(defvar yeah-check--gptel-calls nil
  "The calls the fake gptel received, newest first.")

(defun gptel-request (prompt &key callback &rest _ignored)
  "Stand in for gptel's request: record the call and answer at once."
  (push (list :prompt prompt :callback callback) yeah-check--gptel-calls)
  (when callback
    (funcall callback "the answer" nil))
  nil)

(require 'yeah-gptel)

(let ((failures nil)
      (answer nil))

  (unless (fboundp 'yeah-gptel-request)
    (push "there is no transport to check" failures))

  (when (fboundp 'yeah-gptel-request)
    (yeah-gptel-request "what is the question?"
                        (lambda (value &optional _info)
                          (setq answer value))))

  (unless (= 1 (length yeah-check--gptel-calls))
    (push "the transport did not reach gptel" failures))

  (unless (equal "what is the question?"
                 (plist-get (car yeah-check--gptel-calls) :prompt))
    (push "the prompt did not reach gptel unchanged" failures))

  (unless (functionp (plist-get (car yeah-check--gptel-calls) :callback))
    (push "the callback did not reach gptel" failures))

  (unless (equal answer "the answer")
    (push "the answer did not come back through the callback" failures))

  (dolist (failure failures)
    (message "transport: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-gptel-request-shape.el ends here
