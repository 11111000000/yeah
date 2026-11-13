;;; yeah.el --- Yeah, the Emacs Agent Harness -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; Package-Requires: ((emacs "30.2") (gptel "0.9.9.5"))
;; Version: 0.1.0
;; URL: https://github.com/11111000000/yeah
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; `M-x yeah' opens an interactive agent session.  `M-x yeah-ask' sends a
;; prompt to the current session (creating one when needed).  `M-x yeah-doctor'
;; shows local diagnostics without printing credentials.

;;; Code:

(require 'yeah-product)

;;;###autoload
(defun yeah ()
  "Open an interactive Yeah session for the current project.
The session runs under a permission profile: `plan' refuses the tools
that change the world, `build' asks for them."
  (interactive)
  (let ((latest (yeah-product-latest-session-id (yeah-product-project-root))))
    (yeah-product-open nil nil nil nil nil nil
                       (yeah-product--choose-profile)
                       (and latest
                            (yes-or-no-p (format "Resume the last session (%s)? " latest))
                            latest))))

;;;###autoload
(defun yeah-ask (prompt)
  "Send PROMPT to the current Yeah session, creating one when needed."
  (interactive "sYeah ask: ")
  (let ((buffer (if (and (derived-mode-p 'yeah-mode) yeah-product--control)
                    (current-buffer)
                  (yeah-product-open))))
    (with-current-buffer buffer
      (yeah-product-ask prompt))))

(provide 'yeah)
;;; yeah.el ends here
