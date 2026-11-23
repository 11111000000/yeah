;;; check-two-children-run-in-one-turn-of-the-parent.el --- two children in one turn -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A turn of the parent may hold two children, not one: the model asks for a
;; delegation twice, and the turn of the parent goes on while both children
;; work.  The audit of wave 35 proved that several children in one turn work;
;; this check is the claim that the map binds, and it measures five things:
;;
;; 1. the turn of the parent is over and it ended through the call of
;;    `finish' -- the turn went on and did not wait for the children;
;; 2. the journal of the parent holds the spawn of TWO children, and their
;;    short ids differ -- the model must be able to tell them apart;
;; 3. both children are alive when the turn of the parent is over;
;; 4. both children end on their own, later;
;; 5. the finish of the parent comes after the two delegations -- the parent
;;    delegated twice IN ONE TURN and did not end between them.
;;
;; The model is a FAKE: the parent asks for the delegations and the children
;; answer after a delay.  No network and no key are needed.
;;
;; The preset of the children names `depth: 1' -- the child of the child is
;; refused -- and that is the seam of the control of the claim: a depth that
;; counts the children of the run refuses the second delegation of the turn,
;; and the check then fails by its own assertion (there is one child, not two).
;;
;; Exit codes: 0 -- two children ran in one turn of the parent; 1 -- they did not.

;;; Code:

(require 'cl-lib)
(require 'yeah-delegate)
(require 'yeah-session)
(require 'yeah-turn)

(defconst yeah-check--preset
  "---\nname: reviewer\ndescription: Reviews a diff and says what is wrong.\nmodel: cheap-model\ntools: read, grep\ndepth: 1\n---\n\nYou are a reviewer.\n"
  "The preset the children of the check are delegated to.")

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--directory ()
  "Return a directory with one preset in it."
  (let ((directory (make-temp-file "yeah-two-children" t)))
    (with-temp-buffer
      (insert yeah-check--preset)
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    directory))

(defun yeah-check--finish (summary)
  "Return a gptel-shaped call of the `finish' tool with SUMMARY.
A supervised run ends through this call and not through talk (wave 53)."
  (list 'tool-call
        (list (list :name "finish")
              (list summary)
              (lambda (_value) nil))))

(defun yeah-check--parent-answer (asked callback)
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
                               (yeah-check--parent-answer asked callback)))))
      (yeah-check--finish "the parent is done"))))

(defun yeah-check--parent-transport (asked)
  "Return the transport of the parent run.
ASKED counts the answers the parent gave; see `yeah-check--parent-answer'."
  (lambda (_prompt callback)
    (funcall callback
             (yeah-check--parent-answer asked callback))))

(defun yeah-check--spawns (session)
  "Return the records of the spawn of the children of the run of SESSION."
  (let ((spawns nil))
    (dolist (record (yeah-session-records session))
      (when (equal (plist-get record :type) "spawn")
        (push record spawns)))
    (nreverse spawns)))

(defun yeah-check--status (id)
  "Return the status of the child ID, as the delegate-result tool reports it."
  (plist-get (plist-get (yeah-delegate--result id) :metadata) :status))

(defun yeah-check--wait-for (predicate &optional timeout)
  "Wait until PREDICATE holds, up to TIMEOUT seconds.
Return the value of PREDICATE."
  (let ((deadline (+ (float-time) (or timeout 10))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-check--positions (types type)
  "Return the positions of TYPE in TYPES, in order."
  (let ((position 0)
        (found nil))
    (dolist (one types)
      (setq position (1+ position))
      (when (equal one type)
        (push position found)))
    (nreverse found)))

(let* ((directory (yeah-check--directory))
       (session (yeah-session-open "parent" directory))
       (asked nil)
       (yeah-agent-directories (list directory))
       (yeah-delegate--transport-factory
        (lambda (_model _system _tools)
          (lambda (_prompt callback)
            (run-at-time 1.5 nil
                         (lambda () (funcall callback "the child is done")))))))
  (unwind-protect
      (progn
        (yeah-delegate-register)
        (let ((turn (yeah-turn-run session "delegate the reviews twice"
                                     (yeah-check--parent-transport asked)
                                     (lambda (_request) (list :effect :allow :reply :once)))))
          ;; 1. the turn of the parent is over
          (unless (yeah-turn-done turn)
            (push "the turn of the parent did not end" yeah-check--failures))
          (unless (eq 'completed (yeah-turn-state turn))
            (push (format "the turn of the parent ended in %S, not completed"
                          (yeah-turn-state turn))
                  yeah-check--failures)))
        ;; 2. the journal of the parent holds the spawn of two children
        (let* ((spawns (yeah-check--spawns session))
               (ids (mapcar (lambda (record) (plist-get record :short-id)) spawns)))
          (unless (= 2 (length spawns))
            (push (format "the journal of the parent holds %d spawn(s) of a child, not two: %S"
                          (length spawns) ids)
                  yeah-check--failures))
          (unless (equal ids '("sub-1" "sub-2"))
            (push (format "the two children carry the short ids %S" ids)
                  yeah-check--failures))
          ;; 3. both children are alive when the turn of the parent is over
          (dolist (spawn spawns)
            (let ((id (plist-get spawn :child)))
              (unless (equal (yeah-check--status id) "running")
                (push (format "the child %s is %S when the turn of the parent is over, not running"
                              id (yeah-check--status id))
                      yeah-check--failures))))
          ;; 4. and both children end on their own
          (dolist (spawn spawns)
            (let ((id (plist-get spawn :child)))
              (unless (yeah-check--wait-for
                       (lambda () (equal (yeah-check--status id) "completed")))
                (push (format "the child %s did not end on its own: it is %S"
                              id (yeah-check--status id))
                      yeah-check--failures)))))
        ;; 5. the parent delegated twice in one turn: the finish comes after
        (let* ((types (mapcar (lambda (record) (plist-get record :type))
                              (yeah-session-records session)))
               (spawns-at (yeah-check--positions types "spawn"))
               (finish-at (yeah-check--positions types "finish")))
          (unless (and (= 2 (length spawns-at))
                       (= 1 (length finish-at))
                       (> (car finish-at) (cadr spawns-at)))
            (push (format "the journal of the parent holds the types %S: the spawns are at %S and the finish at %S"
                          types spawns-at finish-at)
                  yeah-check--failures))))
    (yeah-delegate-reset-for-test)
    (ignore-errors (delete-directory directory t)))
  (dolist (failure yeah-check--failures)
    (message "two-children: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-two-children-run-in-one-turn-of-the-parent.el ends here
