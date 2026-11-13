;;; check-client-sees-service-death.el --- the client notices the service is gone -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A dead service that looks alive is the worst failure of the primary
;; path: the person types into a buffer nobody answers.  This check starts
;; a service, connects a client with an on-close callback, kills the
;; service, and proves the callback fires — the editor's line "the service
;; is gone" is built on it.

;;; Code:

(require 'cl-lib)
(require 'yeah-service)
(require 'yeah-client)

(let ((failures nil)
      (data-home (make-temp-file "yeah-death" t))
      (name (format "death-%d" (random 1000000)))
      (closed nil))
  (unwind-protect
      (progn
        (yeah-service-start name nil data-home nil t nil)
        (let ((client
               (yeah-client-connect (yeah-service-socket-path name)
                                    :on-close (lambda (_client)
                                                (setq closed t)))))
          ;; a deliberate close by the client is not a death
          (yeah-client-close client)
          (let ((deadline (+ (float-time) 5)))
            (while (and (not closed) (< (float-time) deadline))
              (accept-process-output nil 0.05)))
          (when closed
            (push "the client's own close was reported as a death" failures))
          ;; now the death: kill the service behind a fresh connection
          (let ((client2
                 (yeah-client-connect (yeah-service-socket-path name)
                                      :on-close (lambda (_client)
                                                  (setq closed t)))))
            (when-let ((process (gethash name yeah-service--processes)))
              (delete-process process))
            (let ((deadline (+ (float-time) 10)))
              (while (and (not closed) (< (float-time) deadline))
                (accept-process-output nil 0.05)))
            (unless closed
              (push "the client did not notice the service died" failures))
            (yeah-client-close client2))))
    (yeah-service-stop name)
    (ignore-errors (delete-directory data-home t)))
  (dolist (failure failures)
    (message "client-death: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-client-sees-service-death.el ends here
