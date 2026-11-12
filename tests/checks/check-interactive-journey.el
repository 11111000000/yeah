;;; check-interactive-journey.el --- canary for the journey of a person -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The journey of a person, end to end and without a network: ask, watch
;; the work, steer, quit, restart, look at what is left, withdraw what is
;; not wanted, recover what is, and cancel a run that must stop.
;;
;; The model is a FAKE: a transport that asks for one tool and answers
;; when the tool has run, and a second transport that stays silent, so
;; that the run is still there to be steered and cancelled.
;;
;; Exit codes: 0 — the journey works; 1 — it does not.

;;; Code:

(require 'cl-lib)
(require 'yeah-control)
(require 'yeah-input)
(require 'yeah-session)
(require 'yeah-tools)
(require 'yeah-ui)

(defconst yeah-journey--expected-events
  '("header" "user-message" "tool-request" "permission-request"
    "permission-decision" "tool-end" "assistant-message")
  "The events of the work, in order.")

(defun yeah-journey--register-probe ()
  "Register the tool `probe'."
  (unless (yeah-tools-get "probe")
    (yeah-tools-register
     (list :name "probe"
           :description "A tool that records that it ran."
           :input (list (list :name "path" :type 'string))
           :handler (lambda (path) (format "probe saw %s" path))))))

(defun yeah-journey--working-transport ()
  "Return a transport that asks for `probe' and then answers."
  (lambda (_prompt callback)
    (funcall callback
             (list 'tool-call
                   (list (list :name "probe")
                         (list "/tmp/probe-target")
                         (lambda (value)
                           (funcall callback (format "done: %s" value))))))))

(defun yeah-journey--silent-transport ()
  "Return a transport that asks for the model and never answers."
  (lambda (_prompt _callback) nil))

(defun yeah-journey--types (records)
  "Return the type of every record in RECORDS."
  (mapcar (lambda (record) (plist-get record :type)) records))

(defun yeah-journey--control (session)
  "Return a controller for SESSION that asks a silent model and allows it."
  (yeah-control-new
   session
   (yeah-journey--silent-transport)
   (lambda (_request) (list :effect :allow :reply :once))))

(let ((failures nil)
      (root (make-temp-file "yeah-journey" t)))
  (unwind-protect
      (progn
        (yeah-journey--register-probe)

        ;; --- the work ---
        (let* ((session (yeah-session-open "journey" root))
               (control (yeah-control-new
                         session
                         (yeah-journey--working-transport)
                         (lambda (_request)
                           (list :effect :allow :reply :once)))))
          (yeah-control-ask control "do the thing")
          (let ((records (yeah-session-records session)))
            (unless (equal (yeah-journey--types records)
                           yeah-journey--expected-events)
              (push (format "the work wrote %S" (yeah-journey--types records))
                    failures))
            (let ((view (yeah-ui-view records)))
              (unless (equal (mapcar (lambda (entry) (plist-get entry :role))
                                     (plist-get view :transcript))
                             '("user" "assistant"))
                (push "the view does not show the conversation" failures))
              (unless (= 1 (length (plist-get view :calls)))
                (push "the view does not show the tool that ran" failures))))

        ;; --- the person steers a run that is still busy ---
        (let* ((session (yeah-session-open "busy" root))
               (control (yeah-journey--control session)))
          (yeah-control-ask control "a long task")
          (when (yeah-control-done-p control)
            (push "the run did not stay active" failures))
          (yeah-control-steer control "wait, do this instead")
          (yeah-control-ask control "and then this")
          (let ((pending (yeah-control-pending control)))
            (unless (= 2 (length pending))
              (push (format "the person left %d inputs pending, expected 2"
                            (length pending))
                    failures))
            (unless (eq 'steering (plist-get (car pending) :kind))
              (push "the queued input is not a steering" failures)))

          ;; --- the person quits and comes back ---
          (let* ((again (yeah-session-open "busy" root))
                 (control (yeah-journey--control again)))
            (unless (= 2 (length (yeah-control-pending control)))
              (push "the pending inputs did not survive the restart" failures))
            (when (not (yeah-control-done-p control))
              (push "the restart ran a pending input by itself" failures))

            ;; --- the person withdraws what is not wanted ---
            (let ((steering (seq-find (lambda (input)
                                        (eq 'steering (plist-get input :kind)))
                                      (yeah-control-pending control))))
              (unless steering
                (push "the steering did not survive the restart" failures))
              (when steering
                (yeah-control-withdraw control (plist-get steering :id))
                (unless (= 1 (length (yeah-control-pending control)))
                  (push "the withdrawal did not remove the steering" failures))))

            ;; --- the person recovers what is wanted ---
            (yeah-control-recover-next control)
            (when (yeah-control-done-p control)
              (push "the recovery did not start the pending input" failures))
            (yeah-control-cancel control "the journey is over")
            (when (not (yeah-control-done-p control))
              (push "the cancel did not stop the recovered run" failures))
            (unless (member "cancel"
                            (yeah-journey--types (yeah-session-records again)))
              (push "the cancel is not in the journal" failures))))

        ;; --- a cancel withdraws the steering it never delivered ---
        (let* ((session (yeah-session-open "cancel" root))
               (control (yeah-journey--control session)))
          (yeah-control-ask control "a long task")
          (yeah-control-steer control "wait, do this instead")
          (yeah-control-cancel control "the person changed their mind")
          (unless (member "input-withdrawn"
                          (yeah-journey--types (yeah-session-records session)))
            (push "the steering was not withdrawn when the run ended" failures))
          (unless (= 0 (length (yeah-control-pending control)))
            (push "the withdrawn steering is still pending" failures))))

    (dolist (failure failures)
      (message "journey: %s" failure))
    (ignore-errors (delete-directory root t))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0)))))

;;; check-interactive-journey.el ends here
