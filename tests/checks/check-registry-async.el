;;; check-registry-async.el --- a tool a run registers is the run's own -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The dispatch of a tool batch binds the run's registry.  This check
;; proves that a tool which registers another tool while it runs lands in
;; the run's registry, not in the shared one.  A tool that registers from
;; its own asynchronous continuation (a timer or a process filter) escapes
;; the binding: that path is documented, not silently wrong.

;;; Code:

(require 'cl-lib)
(require 'yeah-run)
(require 'yeah-perm)
(require 'yeah-tools)

(defun yeah-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE holds, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 10))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(let ((failures nil)
      (context (yeah-run-context-create :placement 'service))
      (done nil))
  (unwind-protect
      (progn
        ;; a tool that registers another tool synchronously, inside its
        ;; handler: it must land in the registry of the run, not the shared one
        (yeah-tools-with-registry (yeah-run-context-tools-registry context)
          (yeah-tools-register
           (list :name "registers-another"
                 :description "Registers a tool while it runs."
                 :input nil
                 :handler (lambda ()
                            (yeah-tools-register
                             (list :name "another"
                                   :description "A tool that appeared."
                                   :input nil
                                   :handler (lambda () "x")))
                            "registered")))))
        ;; the run may use the tool
        (yeah-run-context-add-rule
         context (yeah-perm-rule-make "registers-another" "*" 'allow))
        ;; the model asks for it
        (let ((transport
               (lambda (_prompt callback)
                 (funcall callback
                          (list 'tool-call
                                (list (list :name "registers-another")
                                      (list)
                                      (lambda (value)
                                        (funcall callback "done"))))))))
          (let ((context* context))
            (setf (yeah-run-context-transport context*) transport)
            (let ((session (yeah-session-open "registry-async"
                                              (make-temp-file "yeah-reg" t))))
              (setf (yeah-run-context-session context*) session)
              (yeah-run-context-start context* "run it")
              (yeah-check--await
               (lambda ()
                 (and (yeah-run-context-turn context*)
                      (yeah-turn-done (yeah-run-context-turn context*))))
               10)
              (setq done t))))
        ;; the tool that appeared is the run's own
        (let ((in-run
               (yeah-tools-with-registry
                   (yeah-run-context-tools-registry context)
                 (yeah-tools-get "another")))
              (in-shared (yeah-tools-get "another")))
          (unless in-run
            (push "the tool did not land in the run's registry" failures))
          (when in-shared
            (push "the tool leaked into the shared registry" failures))))
    ;; cleanup: drop the tools from both registries
    (yeah-tools-with-registry (yeah-run-context-tools-registry context)
      (yeah-tools-unregister "registers-another")
      (yeah-tools-unregister "another"))
    (yeah-tools-unregister "registers-another")
    (yeah-tools-unregister "another")
    (dolist (failure failures)
      (message "registry-async: %s" failure))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-registry-async.el ends here
