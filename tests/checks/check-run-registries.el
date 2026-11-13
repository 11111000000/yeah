;;; check-run-registries.el --- a run's tools are its own -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The tool registry used to be process-global: a tool one run registered
;; was advertised to the model of every other run.  A run now starts from
;; a snapshot of the shared registry, and a registration made while the
;; run is active lands in the run's own table.
;;
;; This check creates two run contexts, registers a tool while run A is
;; active, and proves: run A sees the tool, run B and the shared registry
;; do not, and the model-facing list of run A carries it while the list of
;; run B does not.

;;; Code:

(require 'yeah-run)
(require 'yeah-tools)

(let ((failures nil)
      (context-a (yeah-run-context-create :placement 'service))
      (context-b (yeah-run-context-create :placement 'service)))
  ;; a tool that enters only while run A is active
  (yeah-tools-with-registry (yeah-run-context-tools-registry context-a)
    (yeah-tools-register
     (list :name "run-a-only"
           :description "a tool of run A"
           :input nil
           :handler (lambda () "a"))))
  ;; run A sees it, run B does not, the shared registry does not
  (unless (let ((yeah-tools--registry-override
                 (car (yeah-run-context-tools-registry context-a)))
                (yeah-tools--order-override
                 (cdr (yeah-run-context-tools-registry context-a))))
            (yeah-tools-get "run-a-only"))
    (push "run A does not see its own tool" failures))
  (when (let ((yeah-tools--registry-override
               (car (yeah-run-context-tools-registry context-b)))
              (yeah-tools--order-override
               (cdr (yeah-run-context-tools-registry context-b))))
          (yeah-tools-get "run-a-only"))
    (push "run B sees the tool of run A" failures))
  (when (yeah-tools-get "run-a-only")
    (push "the shared registry gained the tool of run A" failures))
  ;; the model-facing lists differ
  (unless (member "run-a-only"
                  (let ((yeah-tools--registry-override
                         (car (yeah-run-context-tools-registry context-a)))
                        (yeah-tools--order-override
                         (cdr (yeah-run-context-tools-registry context-a))))
                    (yeah-tools-names)))
    (push "the model of run A is not offered its tool" failures))
  (when (member "run-a-only"
                (let ((yeah-tools--registry-override
                       (car (yeah-run-context-tools-registry context-b)))
                      (yeah-tools--order-override
                       (cdr (yeah-run-context-tools-registry context-b))))
                  (yeah-tools-names)))
    (push "the model of run B is offered the tool of run A" failures))
  (dolist (failure failures)
    (message "registry: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-run-registries.el ends here
