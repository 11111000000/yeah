;;; check-yeah-opens-the-service.el --- the entry point opens the service -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The service placement is the default of the product: `M-x yeah' opens it,
;; and the attached placement stays reachable by name (`yeah-attached') as the
;; development path and the fallback.
;;
;; The check asks the entry point twice: once when the service answers, and
;; once when the service cannot start.  The service must be asked first, and
;; the attached path must open ONLY when the service failed.  A silent
;; fallback would hide a broken service behind a working session, so the
;; fallback has to happen in the open.
;;
;; Exit codes: 0 — the entry point behaves; 1 — it does not.

;;; Code:

(require 'cl-lib)
(require 'yeah)

(let ((failures nil)
      (service-calls 0)
      (attached-calls 0))
  ;; --- the service answers: it is the placement that opens
  (cl-letf (((symbol-function 'yeah-service)
             (lambda (&optional _name)
               (setq service-calls (1+ service-calls))))
            ((symbol-function 'yeah--open-attached)
             (lambda ()
               (setq attached-calls (1+ attached-calls)))))
    (yeah))
  (unless (= 1 service-calls)
    (push (format "the service was asked %d times, not once" service-calls)
          failures))
  (unless (= 0 attached-calls)
    (push (format "the attached placement opened %d times while the service answered"
                  attached-calls)
          failures))

  ;; --- the service cannot start: the attached path opens instead
  (setq service-calls 0
        attached-calls 0)
  (cl-letf (((symbol-function 'yeah-service)
             (lambda (&optional _name)
               (signal 'user-error "the service cannot start")))
            ((symbol-function 'yeah--open-attached)
             (lambda ()
               (setq attached-calls (1+ attached-calls)))))
    (let ((inhibit-message t))
      (yeah)))
  (unless (= 1 attached-calls)
    (push (format "the attached placement opened %d times after the service failed, not once"
                  attached-calls)
          failures))

  ;; --- the attached path is reachable by name
  (unless (fboundp 'yeah-attached)
    (push "there is no yeah-attached command" failures))
  (let ((attached-calls 0))
    (cl-letf (((symbol-function 'yeah--open-attached)
               (lambda ()
                 (setq attached-calls (1+ attached-calls)))))
      (yeah-attached))
    (unless (= 1 attached-calls)
      (push (format "yeah-attached opened the attached path %d times, not once"
                    attached-calls)
            failures)))
  (when failures
    (dolist (failure (reverse failures))
      (message "check-yeah-opens-the-service: %s" failure))
    (kill-emacs 1)))

;;; check-yeah-opens-the-service.el ends here
