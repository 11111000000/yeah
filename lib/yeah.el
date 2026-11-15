;;; yeah.el --- Yeah, the Emacs Agent Harness -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; Package-Requires: ((emacs "30.2") (gptel "0.9.9.5"))
;; Version: 0.3.0
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
(require 'yeah-service-ui)

(defun yeah--open-attached ()
  "Open an interactive Yeah session in the attached placement.
The attached path is the development path and the fallback of the service
path: the model runs in this Emacs, and the bridge stays off."
  (let ((latest (yeah-product-latest-session-id (yeah-product-project-root))))
    (yeah-product-open nil nil nil nil nil nil
                       (yeah-product--choose-profile)
                       (and latest
                            (yes-or-no-p (format "Resume the last session (%s)? " latest))
                            latest))))

;;;###autoload
(defun yeah ()
  "Open an interactive Yeah session for the current project.
The service placement is the default: the agent runs in a service Emacs
and this buffer is what answers it.  When the service cannot start, the
attached placement opens instead and says so.  An error that happens
while a service is already running is not hidden: it is the error of a
broken service, and the person must see it."
  (interactive)
  (condition-case err
      (yeah-service)
    (error
     (let ((process (gethash "default" yeah-service--processes)))
       (if (and process (process-live-p process))
           (signal (car err) (cdr err))
         (message "Yeah: the service did not start (%s); the attached placement opens instead."
                  (error-message-string err))
         (yeah--open-attached))))))

;;;###autoload
(defun yeah-attached ()
  "Open an interactive Yeah session in the attached placement.
This is the development path: the agent runs in this Emacs.  It is also
the fallback when the service cannot start."
  (interactive)
  (yeah--open-attached))

;;;###autoload
(defun yeah-ask (&optional prompt)
  "Send PROMPT to the current Yeah session, creating one when needed.
Interactively, open the full prompt composer."
  (interactive)
  (let ((buffer (if (and (derived-mode-p 'yeah-mode) yeah-product--control)
                    (current-buffer)
                  (if (derived-mode-p 'yeah-service-ui-mode)
                      (current-buffer)
                    (yeah)))))
    (with-current-buffer buffer
      (if prompt
          (if (derived-mode-p 'yeah-service-ui-mode)
              (yeah-service-ui--ask prompt)
            (yeah-product-ask prompt))
        (yeah-journal-ask-command)))))

(provide 'yeah)
;;; yeah.el ends here
