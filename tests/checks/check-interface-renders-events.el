;;; check-interface-renders-events.el --- canary for the interface -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The interface reads one thing: the event stream. What the person sees
;; and what the log says must not be two different stories, so the view
;; is built from the records of the log and nothing else.
;;
;; The check runs a turn against a fake model, reads the log, and asks
;; the view what it would show: the transcript, the tool call and its
;; state, the approvals that are still waiting, and what the run cost.
;;
;; Exit codes: 0 — the view shows the run; 1 — it does not.

;;; Code:

(require 'yeah-ui)
(require 'yeah-turn)
(require 'yeah-tools)
(require 'yeah-perm)
(require 'yeah-session)

(defun yeah-check--run (root)
  "Run a turn with a fake model and return the view of its log."
  (let ((session (yeah-session-open "view" root))
        (ran (list nil))
        (asked 0))
    (yeah-tools-reset-for-test)
    (yeah-perm-rules-reset-for-test)
    (yeah-tools-register
     (list :name "probe"
           :description "A tool that records that it ran."
           :input (list (list :name "path" :type 'string))
           :handler (lambda (path)
                      (setf (car ran) path)
                      (format "probe ran on %s" path))))
    (yeah-perm-rules-add (yeah-perm-rule-make "probe" "*" 'allow))
    (let ((transport
           (lambda (prompt callback)
             (setq asked (1+ asked))
             (if (= asked 1)
                 (funcall callback
                          (list 'tool-call
                                (list (list :name "probe")
                                      (list "/tmp/probe-target")
                                      (lambda (value)
                                        (funcall callback
                                                 (format "done: %s" value))))))
               (funcall callback "the model is done")))))
      (yeah-turn-run session "do the thing" transport))
    (yeah-ui-view
     (yeah-session-records (yeah-session-open "view" root)))))

(defun yeah-check--deferred-view (root)
  "Return the view of a real turn waiting on a deferred permission."
  (let ((session (yeah-session-open "deferred-view" root)))
    (yeah-tools-reset-for-test)
    (yeah-perm-rules-reset-for-test)
    (yeah-tools-register
     (list :name "probe"
           :description "A tool that must wait for the person."
           :input (list (list :name "path" :type 'string))
           :handler (lambda (_path) "the tool ran")))
    (yeah-turn-run
     session "wait for permission"
     (lambda (_prompt callback)
       (funcall callback
                (list 'tool-call
                      (list (list :name "probe") '("/tmp/deferred")
                            (lambda (_value) nil)))))
     (lambda (_request) (list :defer "request-1")))
    (yeah-ui-view (yeah-session-records session))))

(let ((failures nil)
      (view (yeah-check--run (make-temp-file "yeah-ui-check" t)))
      (deferred-view
       (yeah-check--deferred-view (make-temp-file "yeah-ui-deferred-check" t))))

  ;; the transcript: what was said, in the order it was said
  (let ((transcript (plist-get view :transcript)))
    (unless (= 2 (length transcript))
      (push (format "the transcript holds %d messages, expected 2"
                    (length transcript))
            failures))
    (when (>= (length transcript) 2)
      (unless (equal (plist-get (nth 0 transcript) :role) "user")
        (push "the transcript does not start with the person" failures))
      (unless (equal (plist-get (nth 0 transcript) :text) "do the thing")
        (push "the transcript does not hold what was asked" failures))
      (unless (equal (plist-get (nth 1 transcript) :role) "assistant")
        (push "the transcript does not end with the model" failures))))

  ;; the calls: what the model asked, and what became of it
  (let ((calls (plist-get view :calls)))
    (unless (= 1 (length calls))
      (push (format "the view holds %d calls, expected 1" (length calls))
            failures))
    (when (>= (length calls) 1)
      (unless (equal (plist-get (car calls) :tool) "probe")
        (push "the view does not show the tool that ran" failures))
      (unless (eq (plist-get (car calls) :state) 'done)
        (push "the view does not show the call as finished" failures))
      (unless (plist-get (car calls) :ok)
        (push "the view does not show the call as successful" failures))))

  ;; the approvals: none are waiting, the rules answered
  (unless (null (plist-get view :pending))
    (push (format "the view waits for %d approvals that were answered"
                  (length (plist-get view :pending)))
          failures))

  ;; a real deferred decision remains pending instead of becoming a refusal
  (let ((pending (plist-get deferred-view :pending-approvals))
        (calls (plist-get deferred-view :calls)))
    (unless (and (= 1 (length pending))
                 (eq 'deferred (plist-get (car pending) :state)))
      (push (format "the deferred permission is not pending: %S" pending)
            failures))
    (unless (and (= 1 (length calls))
                 (eq 'awaiting-approval (plist-get (car calls) :state)))
      (push "the deferred tool is not waiting for approval" failures))
    (unless (eq 'awaiting-approval
                (plist-get (plist-get deferred-view :status) :state))
      (push "the deferred run does not report its waiting state" failures)))

  ;; provider silence is unknown, not zero; the estimate is separate
  (let ((usage (plist-get view :usage)))
    (when (or (plist-get usage :input)
              (plist-get usage :output)
              (plist-get usage :reported-p))
      (push (format "the view reports provider usage it cannot know: %S" usage)
            failures))
    (unless (and (numberp (plist-get usage :estimated))
                 (> (plist-get usage :estimated) 0))
      (push (format "the view has no separate estimate: %S" usage) failures)))

  ;; the new shape exists alongside the compatibility fields
  (dolist (key '(:session :status :blocks :pending-approvals :pending-inputs
                 :usage :capabilities :transcript :calls :pending))
    (unless (plist-member view key)
      (push (format "the view is missing %S" key) failures)))

  (dolist (failure failures)
    (message "interface: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-interface-renders-events.el ends here
