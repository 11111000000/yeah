;;; check-service-init-file.el --- a clean service configures its model from one file -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The primary path starts the service clean: the person's full init is
;; not paid for, only the file that configures the model is loaded.  This
;; check writes such a file — it sets `yeah-acp-default-transport' to a
;; fake — starts a clean service pointing at it, and proves the model the
;; file chose is the model that answers.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-service)
(require 'yeah-client)

(let ((failures nil)
      (data-home (make-temp-file "yeah-init" t))
      (name (format "init-%d" (random 1000000)))
      (init-file (make-temp-file "yeah-service-init" nil ".el"))
      (answered nil))
  (unwind-protect
      (progn
        (with-temp-file init-file
          (insert "(setq yeah-acp-default-transport
                          (lambda (prompt callback)
                            (funcall callback
                                     (concat \"the init file answers: \" prompt))))"))
        ;; clean=t: the service has no init but this file, and no
        ;; transport is passed at start — the file is the whole
        ;; configuration
        (yeah-service-start name (format "(load %S)" init-file)
                            data-home nil t nil)
        (let ((client
               (yeah-client-connect (yeah-service-socket-path name))))
          (yeah-client-request client "initialize"
                               (list :protocolVersion 1)
                               (lambda (_result _error) nil))
          (yeah-client-request
           client "session/new"
           (list :cwd data-home :mcpServers nil)
           (lambda (result _error)
             (let ((session-id (plist-get result :sessionId)))
               (yeah-client-request
                client "session/prompt"
                (list :sessionId session-id
                      :prompt (vector (list :type "text" :text "hello")))
                (lambda (result error)
                  (setq answered (or error result)))))))
          (let ((deadline (+ (float-time) 15)))
            (while (and (null answered) (< (float-time) deadline))
              (accept-process-output nil 0.05)))
          (yeah-client-close client))
        (let ((journal
               (mapconcat
                (lambda (file)
                  (with-temp-buffer
                    (insert-file-contents file)
                    (buffer-string)))
                (directory-files-recursively data-home "\\.jsonl\\'")
                "\n")))
          (unless (string-match-p
                   "the init file answers: hello" journal)
            (push (format "the model of the init file did not answer:\n%s"
                          journal)
                  failures))))
    (yeah-service-stop name)
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-file init-file)))
  (dolist (failure failures)
    (message "service-init: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-service-init-file.el ends here
