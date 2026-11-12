;;; check-three-placements.el --- canary for the placements -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The same task, done in three placements: attached to this Emacs, in a
;; service Emacs of its own, and in a batch Emacs that has one task and
;; exits.  What is compared is not the words of the run but the events it
;; wrote down, in the canonical projection: the same task in three
;; placements must produce the same truth.
;;
;; The model is a FAKE (tests/support/scenario.el): the same file is loaded
;; by this check and by the two child processes, so the three runs really
;; do the same work.  No network is touched.
;;
;; Exit codes: 0 — the placements agree; 1 — they do not.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-bridge)
(require 'yeah-placement)
(require 'yeah-session)

(defconst yeah-check--scenario "tests/support/scenario.el"
  "The scenario of the check: the fake model and the tool it asks for.")

(defconst yeah-check--expected-events
  '("user-message" "tool-request" "permission-request"
    "permission-decision" "tool-end" "assistant-message")
  "The events the task of the check must produce, in order.")

(defun yeah-check--project ()
  "Return the directory of the project the task is about."
  (make-temp-file "yeah-placement-project" t))

(defun yeah-check--data-home ()
  "Return the directory the journals are written to."
  (make-temp-file "yeah-placement-data" t))

(defun yeah-check--sessions (root)
  "Return the session objects under the data home ROOT, by placement name."
  (let ((sessions nil)
        (directory (expand-file-name "yeah/projects" root)))
    (when (file-directory-p directory)
      (dolist (project (directory-files directory t))
        (let ((sessions-directory (expand-file-name "sessions" project)))
          (when (file-directory-p sessions-directory)
            (dolist (file (directory-files sessions-directory t "\\.jsonl\\'"))
              (push (cons (file-name-base file)
                          (yeah-session-open (file-name-base file) project))
                    sessions))))))
    (sort sessions (lambda (left right) (string< (car left) (car right))))))

(defun yeah-check--placement (id)
  "Return the placement name of the session ID."
  (car (split-string id "-")))

(defun yeah-check--canonical (session)
  "Return the canonical projection of the events of SESSION."
  (yeah-placement-canonical-events session))

(defun yeah-check--types (events)
  "Return the type of every event in EVENTS."
  (mapcar #'car events))

(defun yeah-check--await-process (process &optional timeout)
  "Wait for PROCESS to exit and return its exit code."
  (let ((deadline (+ (float-time) (or timeout 60)))
        (code nil))
    (while (and (process-live-p process) (< (float-time) deadline))
      (accept-process-output process 0.05))
    (when (process-live-p process)
      (kill-process process)
      (setq code 124))
    (or code (process-exit-status process))))

(defun yeah-check--child-output (process)
  "Return the output PROCESS wrote."
  (with-current-buffer (process-buffer process)
    (buffer-string)))

(defun yeah-check--run-child (starter prompt root allow)
  "Run a placement in a child Emacs and return the process and its code."
  (let* ((process (funcall starter prompt :root root :allow allow
                          :scenario yeah-check--scenario))
         (code (yeah-check--await-process process)))
    (list process code)))

(let ((failures nil)
      (project (yeah-check--project))
      (data-home (yeah-check--data-home))
      yeah-data-home)
  (setq yeah-data-home data-home)
  (unwind-protect
      (progn
        (load (expand-file-name yeah-check--scenario) nil t)

        ;; --- attached: this Emacs, the person is there ---
        (let* ((context (yeah-placement-attach
                         "do the thing"
                         :root project
                         :transport #'yeah-scenario-transport
                         :rules (yeah-placement-allow-rules '("probe"))))
               (turn (yeah-run-context-turn context)))
          (unless turn
            (push "the attached placement did not start a run" failures))
          (when turn
            (yeah-placement-await turn))
          (unless (eq 'completed (yeah-turn-state turn))
            (push (format "the attached placement ended in %S, not completed"
                          (yeah-turn-state turn))
                  failures)))

        ;; --- service: an Emacs of its own ---
        (let ((result (yeah-check--run-child
                       #'yeah-placement-service-start
                       "do the thing" project "probe")))
          (unless (eq 0 (nth 1 result))
            (push (format "the service placement exited with %S: %s"
                          (nth 1 result) (yeah-check--child-output (nth 0 result)))
                  failures)))

        ;; --- batch: an Emacs with one task ---
        (let ((result (yeah-check--run-child
                       #'yeah-placement-batch-start
                       "do the thing" project "probe")))
          (unless (eq 0 (nth 1 result))
            (push (format "the batch placement exited with %S: %s"
                          (nth 1 result) (yeah-check--child-output (nth 0 result)))
                  failures)))

        ;; --- the three truths are one truth ---
        (let* ((sessions (yeah-check--sessions data-home))
               (projections (mapcar (lambda (entry)
                                       (yeah-check--canonical (cdr entry)))
                                     sessions))
               (names (mapcar (lambda (entry) (yeah-check--placement (car entry)))
                              sessions)))
          (unless (equal names '("attached" "batch" "service"))
            (push (format "the three placements wrote the journals %S" names)
                  failures))
          (when (= 3 (length projections))
            (let ((attached (car projections))
                  (others (cdr projections)))
              (unless (equal (yeah-check--types attached)
                             yeah-check--expected-events)
                (push (format "the attached placement wrote %S"
                              (yeah-check--types attached))
                      failures))
              (dolist (other others)
                (unless (equal attached other)
                  (push (format "the placements disagree:\n  %S\n  %S"
                                attached other)
                        failures))))))

        ;; --- service cannot reach the buffers of the person ---
        (unless (null (yeah-tools-get "bridge__buffer_read"))
          (push "the bridge tool is registered without an operator decision"
                failures))))

    (dolist (failure failures)
      (message "placements: %s" failure))
    (ignore-errors (delete-directory project t))
    (ignore-errors (delete-directory data-home t))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-three-placements.el ends here
