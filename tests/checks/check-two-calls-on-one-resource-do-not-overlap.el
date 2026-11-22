;;; check-two-calls-on-one-resource-do-not-overlap.el --- the lock of the resource -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A tool says what it touches: the field is `:resource', and the name in it
;; is a lock.  Two calls that declare one resource never run at the same
;; time, and the lock lasts from the start of a call until the call settles.
;;
;; The defect this check hunts: the declaration is a word in the
;; specification and nothing else.  A registry that takes `:resource' and
;; drops it, a turn that builds a call without it and a scheduler that does
;; not read it all look the same from the outside: two calls that touch one
;; file run at the same time, and the second one reads a half-written file.
;;
;; The check runs REAL TURNS with a fake model, so that the whole path is
;; covered: the registry holds the declaration, the turn builds the call out
;; of the registry, and the scheduler decides what runs together.  A check
;; that drove the scheduler alone would pass even when the turn dropped the
;; declaration on the way.
;;
;; Six things are proved:
;;
;;   1. two calls that declare one resource do not overlap: the second one
;;      starts after the first one has settled;
;;   2. two calls that declare DIFFERENT resources do overlap: a lock that
;;      held everything back would satisfy the first proof and would be a
;;      total lock, and a false refusal with a false subject is worse than
;;      no refusal at all;
;;   3. a call that declares no resource is not held back by another call:
;;      the lock is switched on by the declaration;
;;   4. the declaration reaches the scheduler: the call the turn builds out
;;      of the registry carries the resource, and the turns of the three
;;      proofs above run through that call;
;;   5. the registration refuses a declaration that is not a nonempty
;;      string, and the refusal names the tool;
;;   6. every tool that changes the world declares a resource.  The set of
;;      the tools that change the world is MEASURED, not taken from a
;;      constant: it is read from the declarations of the registry.
;;
;; The sixth proof is a measurement and not a list: a tool that changes the
;; world is in the set because it says so, and a tool that declares no risk
;; is in it as well, because a risk that is not known changes the world.
;; The tools that only read are not in the set, and they declare nothing: a
;; reader needs no lock.
;;
;; The probes wait on a timer, which is what a tool that waits does.  The
;; event loop is pumped in small steps, because a timer that is started
;; inside another timer is only reached by a later turn of the loop.
;;
;; Exit codes: 0 -- the calls on one resource do not overlap; 1 -- they do.

;;; Code:

(require 'cl-lib)
(require 'yeah-perm)
(require 'yeah-risk)
(require 'yeah-scheduler)
(require 'yeah-session)
(require 'yeah-tools)
(require 'yeah-turn)

(defun yeah-check--pump ()
  "Let the event loop run for a while, in small steps.
A timer that is started inside another timer is only reached by a later
turn of the loop, so the loop is pumped rather than slept through."
  (dotimes (_ 40) (sleep-for 0.05)))

(defun yeah-check--probe (name resource events delay)
  "Return the specification of a probe tool named NAME.
RESOURCE is the resource the probe declares, or nil when it declares none.
EVENTS is the cell that holds the list of what happened, in the order it
happened.  The probe waits DELAY seconds before it answers, so that two
calls of one batch can overlap, or not.
The probe declares the risk `read': it changes nothing, and a tool that
only reads declares no resource."
  (list :name name
        :description "A probe of the lock of the resource."
        :input nil
        :async t
        :risk "read"
        :resource resource
        :handler (lambda (_args done)
                   (setf (car events)
                         (cons (concat name "-start") (car events)))
                   (run-with-timer delay nil
                                   (lambda ()
                                     (setf (car events)
                                           (cons (concat name "-finish")
                                                 (car events)))
                                     (funcall done (format "%s is done" name)))))))

(defun yeah-check--run-turn (calls events)
  "Run one turn whose model asks for CALLS, and return what happened.
CALLS is the list of the names of the probe tools.  EVENTS is the cell that
holds what the probes recorded.  The model of the fake transport asks for all
of the calls in one answer, so that they are one batch of the scheduler: the
lock is about the calls of one batch.
The value is the list of the events of the batch, in the order they
happened."
  (let* ((root (make-temp-file "yeah-resource-lock" t))
         (session (yeah-session-open "resource-lock" root)))
    (unwind-protect
        (progn
          (dolist (name calls)
            (yeah-perm-rules-add (yeah-perm-rule-make name "*" 'allow)))
          (yeah-turn-run
           session "probe the lock of the resource"
           (lambda (_prompt callback)
             (funcall callback
                      (cons 'tool-call
                            (mapcar (lambda (name)
                                      (list (list :name name)
                                            nil
                                            (lambda (_value)
                                              ;; the model answers with a
                                              ;; text when the tools are done,
                                              ;; and the run ends there
                                              (funcall callback "the probes are done"))))
                                    calls))))
           ;; The run is not supervised: the subject of this check is the lock
           ;; of the resource and not the path of the completion.
           nil 60000 0)
          (yeah-check--pump)
          (reverse (car events)))
      (ignore-errors (delete-directory root t t)))))

(let ((failures nil))

  ;; --- 1. two calls on one resource do not overlap ------------------------
  (let ((events (list nil)))
    (yeah-tools-register
     (yeah-check--probe "probe-lock-a" "probe-lock-resource" events 0.15))
    (yeah-tools-register
     (yeah-check--probe "probe-lock-b" "probe-lock-resource" events 0.15))
    (let ((order (yeah-check--run-turn '("probe-lock-a" "probe-lock-b") events)))
      (unless (equal order '("probe-lock-a-start" "probe-lock-a-finish"
                              "probe-lock-b-start" "probe-lock-b-finish"))
        (push (format "the two calls on one resource overlapped: %S" order)
              failures))))

  ;; --- 2. two calls on two resources do overlap --------------------------
  (let ((events (list nil)))
    (yeah-tools-register
     (yeah-check--probe "probe-diff-a" "probe-resource-a" events 0.15))
    (yeah-tools-register
     (yeah-check--probe "probe-diff-b" "probe-resource-b" events 0.15))
    (let ((order (yeah-check--run-turn '("probe-diff-a" "probe-diff-b") events)))
      (unless (equal (list (nth 0 order) (nth 1 order))
                     '("probe-diff-a-start" "probe-diff-b-start"))
        (push (format "the calls on two resources did not overlap: %S" order)
              failures))))

  ;; --- 3. a call that declares nothing is not held back ------------------
  (let ((events (list nil)))
    (yeah-tools-register
     (yeah-check--probe "probe-free-locked" "probe-free-resource" events 0.15))
    (yeah-tools-register
     (yeah-check--probe "probe-free-plain" nil events 0.15))
    (let ((order (yeah-check--run-turn '("probe-free-locked" "probe-free-plain") events)))
      (unless (equal (list (nth 0 order) (nth 1 order))
                     '("probe-free-locked-start" "probe-free-plain-start"))
        (push (format "the call that declares nothing was held back: %S" order)
              failures))))

  ;; --- 4. the declaration reaches the scheduler --------------------------
  ;; The call the turn builds out of the registry carries the resource.  The
  ;; three proofs above run through that call: a turn that dropped the
  ;; declaration would let the calls of one resource overlap.
  (let* ((spec (yeah-tools-get "probe-lock-a"))
         (call (yeah-turn--call-spec nil (list :name "probe-lock-a"
                                               :args nil
                                               :spec spec)))
         (resource (plist-get call :tool-resource)))
    (unless (equal resource "probe-lock-resource")
      (push (format "the call of the scheduler carries the resource %S"
                    resource)
            failures)))

  ;; --- 5. the registration refuses a declaration that is not a string ---
  (dolist (bad (list 42 "" :file))
    (let ((refusal nil))
      (condition-case err
          (yeah-tools-register
           (list :name "probe-bad-resource" :description "probe"
                 :input nil :resource bad
                 :handler (lambda () "never")))
        (user-error (setq refusal err)))
      (unless refusal
        (push (format "the registry took the resource %S" bad) failures))
      (when refusal
        (unless (string-match-p "probe-bad-resource"
                                 (error-message-string refusal))
          (push (format "the refusal of the resource %S named no tool: %s"
                        bad (error-message-string refusal))
                failures)))))

  ;; --- 6. every tool that changes the world declares a resource ---------
  ;; The set of the tools that change the world is measured: it comes from
  ;; the declarations of the registry and not from a list of names.
  (dolist (name (yeah-risk-mutating-tools))
    (unless (yeah-tools-resource (yeah-tools-get name))
      (push (format "the tool %S changes the world and declares no resource"
                    name)
            failures)))

  (dolist (failure failures)
    (message "resource lock: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-two-calls-on-one-resource-do-not-overlap.el ends here
