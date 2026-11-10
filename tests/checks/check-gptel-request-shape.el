;;; check-gptel-request-shape.el --- canary for the transport seam -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; A fake gptel records how the private adapter calls its public request API.
;; No network or installed gptel is required.

;;; Code:

(defvar gptel-version "0.9.9.6")
(defvar gptel-backend nil)
(defvar gptel-model nil)
(defvar gptel-tools nil)
(defvar gptel-use-tools nil)
(defvar gptel-use-context nil)
(defvar yeah-check--gptel-calls nil)

(defun gptel-make-tool (&rest slots)
  "Return fake tool SLOTS."
  slots)

(defun gptel-request (prompt &rest keys)
  "Record PROMPT and KEYS and answer through the supplied callback."
  (push (list :prompt prompt :keys keys :use-context gptel-use-context)
        yeah-check--gptel-calls)
  (when-let ((callback (plist-get keys :callback)))
    (funcall callback "the answer" nil))
  nil)

(require 'yeah-gptel)

(let ((failures nil)
      (answer nil))
  (yeah-gptel-request "what is the question?"
                      (lambda (value &optional _info)
                        (setq answer value)))
  (unless (= 1 (length yeah-check--gptel-calls))
    (push "the transport did not reach gptel" failures))
  (let ((call (car yeah-check--gptel-calls)))
    (unless (equal "what is the question?" (plist-get call :prompt))
      (push "the prompt did not reach gptel unchanged" failures))
    (unless (functionp (plist-get (plist-get call :keys) :callback))
      (push "the callback did not reach gptel" failures))
    (unless (equal yeah-gptel-prelude
                   (plist-get (plist-get call :keys) :system))
      (push "the private system prompt did not reach gptel" failures))
    (when (plist-get call :use-context)
      (push "ambient gptel editor context was not disabled" failures)))
  (unless (equal answer "the answer")
    (push "the answer did not come back through the callback" failures))
  (dolist (failure failures)
    (message "transport: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-gptel-request-shape.el ends here
