;;; check-the-journal-names-the-model-of-a-child.el --- the journal names the model of a child -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A child of a delegation runs on the model of the preset that named it, and
;; not on the model of its parent.  The code proves it: the transport of the
;; child is built from the model of the preset.  The JOURNALS did not say it:
;; the spawn of a child carried no model, and the child never named the model
;; it runs on.  A reader of the journal of a run could not tell which model
;; answered the child -- and the client of the orchestrator, which is told the
;; model of a session (the event session-model), was told nothing about the
;; children of the run.
;;
;; This check measures three things:
;;
;;   1. the journal of the parent holds the spawn of the children, and every
;;      spawn names the model of the preset -- the model the child runs on;
;;   2. the journal of every child holds the record of where the child stands
;;      in the tree of the delegations, and that record names the same model;
;;   3. the two names are the model of the preset and not the model of the
;;      parent -- a child that ran on the model of its parent would be caught
;;      here.
;;
;; The model is a FAKE: the parent asks for the delegations and the children
;; answer after a delay.  No network and no key are needed.
;;
;; The seam of the control of the claim is the handover of the model: the
;; delegate hands the model of the preset to the spawn, and a delegate that
;; hands over another model must make the check fail by its own assertion.
;;
;; Exit codes: 0 -- the journals name the model of the children; 1 -- they do not.

;;; Code:

(require 'cl-lib)
(require 'yeah-delegate)
(require 'yeah-model)
(require 'yeah-session)
(require 'yeah-turn)

(defconst yeah-model--preset
  "---\nname: reviewer\ndescription: Reviews a diff and says what is wrong.\nmodel: cheap-model\ntools: read, grep\ndepth: 1\n---\n\nYou are a reviewer.\n"
  "The preset the children of the check are delegated to.")

(defvar yeah-model--failures nil
  "The failures this check found.")

(defun yeah-model--directory ()
  "Return a directory with one preset in it."
  (let ((directory (make-temp-file "yeah-two-children" t)))
    (with-temp-buffer
      (insert yeah-model--preset)
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    directory))

(defun yeah-model--finish (summary)
  "Return a gptel-shaped call of the `finish' tool with SUMMARY.
A supervised run ends through this call and not through talk (wave 53)."
  (list 'tool-call
        (list (list :name "finish")
              (list summary)
              (lambda (_value) nil))))

(defun yeah-model--parent-answer (asked callback)
  "Return the next answer of the parent run.
ASKED counts the answers the parent gave already: the parent delegates twice,
with two different tasks, and ends the turn after that.  CALLBACK is the
callback of the transport: the continuation of a tool call calls it again,
and the model of the parent goes on where it left off."
  (let ((step (length asked)))
    (push step asked)
    (if (< step 2)
        (list 'tool-call
              (list (list :name "delegate")
                    (list "reviewer" (format "the task %d" step))
                    (lambda (_value)
                      (funcall callback
                               (yeah-model--parent-answer asked callback)))))
      (yeah-model--finish "the parent is done"))))

(defun yeah-model--parent-transport (asked)
  "Return the transport of the parent run.
ASKED counts the answers the parent gave; see `yeah-model--parent-answer'."
  (lambda (_prompt callback)
    (funcall callback
             (yeah-model--parent-answer asked callback))))

(defun yeah-model--records (session type)
  "Return the records of TYPE in the journal of SESSION."
  (let (found)
    (dolist (record (yeah-session-records session))
      (when (equal (plist-get record :type) type)
        (push record found)))
    (nreverse found)))

(defun yeah-model--spawns (session)
  "Return the records of the spawn of the children of the run of SESSION."
  (let ((spawns nil))
    (dolist (record (yeah-session-records session))
      (when (equal (plist-get record :type) "spawn")
        (push record spawns)))
    (nreverse spawns)))

(defun yeah-model--status (id)
  "Return the status of the child ID, as the delegate-result tool reports it."
  (plist-get (plist-get (yeah-delegate--result id) :metadata) :status))

(defun yeah-model--wait-for (predicate &optional timeout)
  "Wait until PREDICATE holds, up to TIMEOUT seconds.
Return the value of PREDICATE."
  (let ((deadline (+ (float-time) (or timeout 10))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-model--positions (types type)
  "Return the positions of TYPE in TYPES, in order."
  (let ((position 0)
        (found nil))
    (dolist (one types)
      (setq position (1+ position))
      (when (equal one type)
        (push position found)))
    (nreverse found)))

(let* ((directory (yeah-model--directory))
       (session (yeah-session-open "parent" directory))
       (asked nil)
       (models-seen nil)
       (yeah-agent-directories (list directory))
       (yeah-delegate--transport-factory
        (lambda (model _system _tools)
          (push model models-seen)
          (lambda (_prompt callback)
            (run-at-time 1.5 nil
                         (lambda () (funcall callback "the child is done")))))))
  (unwind-protect
      (progn
        (yeah-delegate-register)
        ;; The model in force for the parent is named here: the child runs
        ;; on the model of its preset, and not on the model of the parent.
        (let ((yeah-model--current "parent-model"))
          (let ((turn (yeah-turn-run session "delegate the reviews twice"
                                       (yeah-model--parent-transport asked)
                                       (lambda (_request) (list :effect :allow :reply :once)))))
          ;; 1. the turn of the parent is over
          (unless (yeah-turn-done turn)
            (push "the turn of the parent did not end" yeah-model--failures))
          (unless (eq 'completed (yeah-turn-state turn))
            (push (format "the turn of the parent ended in %S, not completed"
                          (yeah-turn-state turn))
                  yeah-model--failures)))
          ;; 1a. the transport of every child was built with the model of the
          ;; preset: the journal names the model that answered the child,
          ;; and not only the model the journal was told to name
          (let ((models (nreverse models-seen)))
            (unless (= 2 (length models))
              (push (format "the transports of %d child(ren) were built, and not two: %S"
                            (length models) models)
                    yeah-model--failures))
            (dolist (model models)
              (unless (equal model "cheap-model")
                (push (format "the transport of a child was built with the model %S, and the preset names cheap-model"
                              model)
                      yeah-model--failures)))
            (when (member "parent-model" models)
              (push (format "a child runs on the model of its parent: %S" models)
                    yeah-model--failures))))
        ;; 2. the journal of the parent holds the spawn of two children
        (let* ((spawns (yeah-model--spawns session))
               (ids (mapcar (lambda (record) (plist-get record :short-id)) spawns))
               (models (mapcar (lambda (record) (plist-get record :model)) spawns)))
          (unless (= 2 (length spawns))
            (push (format "the journal of the parent holds %d spawn(s) of a child, not two: %S"
                          (length spawns) ids)
                  yeah-model--failures))
          (unless (equal ids '("sub-1" "sub-2"))
            (push (format "the two children carry the short ids %S" ids)
                  yeah-model--failures))
          ;; the spawn of every child names the model of the preset
          (dolist (model models)
            (unless (equal model "cheap-model")
              (push (format "the spawn of a child names the model %S, and the preset names cheap-model"
                            model)
                    yeah-model--failures)))
          ;; 3. both children are alive when the turn of the parent is over
          (dolist (spawn spawns)
            (let ((id (plist-get spawn :child)))
              (unless (equal (yeah-model--status id) "running")
                (push (format "the child %s is %S when the turn of the parent is over, not running"
                              id (yeah-model--status id))
                      yeah-model--failures))))
          ;; 4. and both children end on their own
          (dolist (spawn spawns)
            (let ((id (plist-get spawn :child)))
              (unless (yeah-model--wait-for
                       (lambda () (equal (yeah-model--status id) "completed")))
                (push (format "the child %s did not end on its own: it is %S"
                              id (yeah-model--status id))
                      yeah-model--failures)))))
        ;; 4a. the journal of every child names the model of the preset
        (dolist (spawn (yeah-model--spawns session))
          (let* ((id (plist-get spawn :child))
                 (child (yeah-session-open id directory))
                 (starts (yeah-model--records child "child-start"))
                 (model (and (= 1 (length starts)) (plist-get (car starts) :model))))
            (unless (= 1 (length starts))
              (push (format "the journal of the child %s holds %d record(s) of where it stands, not one"
                            id (length starts))
                    yeah-model--failures))
            (unless (equal model "cheap-model")
              (push (format "the journal of the child %s names the model %S, and the preset names cheap-model"
                            id model)
                    yeah-model--failures))))
        ;; 5. the parent delegated twice in one turn: the finish comes after
        (let* ((types (mapcar (lambda (record) (plist-get record :type))
                              (yeah-session-records session)))
               (spawns-at (yeah-model--positions types "spawn"))
               (finish-at (yeah-model--positions types "finish")))
          (unless (and (= 2 (length spawns-at))
                       (= 1 (length finish-at))
                       (> (car finish-at) (cadr spawns-at)))
            (push (format "the journal of the parent holds the types %S: the spawns are at %S and the finish at %S"
                          types spawns-at finish-at)
                  yeah-model--failures))))
    (yeah-delegate-reset-for-test)
    (ignore-errors (delete-directory directory t)))
  (dolist (failure yeah-model--failures)
    (message "child-model: %s" failure))
  (if yeah-model--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-journal-names-the-model-of-a-child.el ends here
