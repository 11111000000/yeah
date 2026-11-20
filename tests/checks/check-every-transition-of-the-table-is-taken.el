;;; check-every-transition-of-the-table-is-taken.el --- every cell of the table is taken -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The table of the machine (`lib/yeah-loop.el') names the moves a run can
;; make.  Nothing said that the runtime has a move for every cell of that
;; table: seven labels were called nowhere, and three states could not be
;; entered at all.  A cell that the runtime never takes is a promise the
;; machine does not keep, and a reader of the table cannot tell a promise
;; from a fact.
;;
;; Two things are checked here.
;;
;; 1. Every label of the table has a place in `lib/' where the run takes that
;;    move.  The check reads the sources of the kernel with the reader of
;;    Emacs and looks for the calls of `yeah-turn--tick' and for the label
;;    each of them takes: a label that is quoted anywhere in the arguments of
;;    such a call is a label the runtime takes.
;; 2. Every state of the machine is reachable from the first one through the
;;    cells of the table: a state in a part of the table that no path leads
;;    to is a state a run is never in.
;;
;; The check is static on purpose: it answers about the whole kernel at once,
;; and it answers the same way twice.  A dynamic check would need a run that
;; takes every move of the table, and there is no such run: a run that meets
;; no busy provider never takes `rate-blocked', and a run that never grows
;; long never takes `budget-overflow'.
;;
;; Exit codes: 0 -- every cell of the table is taken; 1 -- one is not.

;;; Code:

(require 'cl-lib)
(require 'yeah-loop)
(require 'yeah-state)

(defconst yeah-check--tick-function 'yeah-turn--tick
  "The function the runtime moves a run with.")

(defun yeah-check--root ()
  "Return the root of the project."
  (expand-file-name default-directory))

(defun yeah-check--fail (ok message)
  "Return MESSAGE when OK is nil, and nil when OK holds."
  (unless ok
    message))

(defun yeah-check--sources-of-the-kernel ()
  "Return the files of the kernel of the project."
  (let ((directory (expand-file-name "lib" (yeah-check--root))))
    (sort (mapcar (lambda (name) (expand-file-name name directory))
                  (directory-files directory nil "\\.el\\'"))
          #'string<)))

(defun yeah-check--forms-of (file)
  "Return the top-level forms of FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file))
      (nreverse forms))))

(defun yeah-check--quoted-symbols (form)
  "Return the quoted symbols in FORM."
  (cond ((and (consp form) (eq (car form) 'quote) (consp (cdr form)))
         (list (car (cdr form))))
        ((consp form)
         (let (symbols)
           (let ((tail form))
             (while (consp tail)
               (setq symbols (append symbols (yeah-check--quoted-symbols (car tail)))
                     tail (cdr tail))))
           symbols))
        (t nil)))

(defun yeah-check--labels-in (form)
  "Return the labels the runtime takes in FORM.

A call of `yeah-turn--tick' takes a label; the label is the quoted symbol
in the arguments of that call.  A call inside the arguments of another call
is a call of its own, and its label is a label of its own."
  (if (and (consp form) (eq (car form) yeah-check--tick-function))
      (append (yeah-check--quoted-symbols (cdr form))
              (yeah-check--labels-in (cdr form)))
    (when (consp form)
      (let (labels)
        (let ((tail form))
          (while (consp tail)
            (setq labels (append labels (yeah-check--labels-in (car tail)))
                  tail (cdr tail))))
        labels))))

(defun yeah-check--labels-taken-by-the-runtime ()
  "Return the labels the runtime takes, found in the sources of the kernel."
  (let (labels)
    (dolist (file (yeah-check--sources-of-the-kernel))
      (dolist (form (yeah-check--forms-of file))
        (setq labels (append labels (yeah-check--labels-in form)))))
    (delete-dups labels)))

(defun yeah-check--labels-of-the-table ()
  "Return the labels the table of the machine names."
  (delete-dups (mapcar (lambda (cell) (nth 1 cell)) yeah-loop-transitions)))

(defun yeah-check--every-label-of-the-table-is-taken ()
  "Every label of the table of the machine has a place in the runtime that takes it."
  (let* ((labels (yeah-check--labels-of-the-table))
         (taken (yeah-check--labels-taken-by-the-runtime))
         (missing (cl-set-difference labels taken)))
    (yeah-check--fail
     (null missing)
     (format "the table of the machine names %d move(s) that the runtime does not take: %S"
             (length missing) missing))))

(defun yeah-check--reachable-states ()
  "Return the states the table of the machine can reach from the first one."
  (let ((seen (list (car yeah-state-list)))
        (queue (list (car yeah-state-list))))
    (while queue
      (let ((from (pop queue)))
        (dolist (cell yeah-loop-transitions)
          (when (eq (nth 0 cell) from)
            (let ((to (nthcdr 2 cell)))
              (unless (memq to seen)
                (push to seen)
                (push to queue)))))))
    seen))

(defun yeah-check--every-state-of-the-machine-is-reachable ()
  "Every state of the machine is reachable from the first one through the table."
  (let* ((reachable (yeah-check--reachable-states))
         (unreachable (cl-set-difference yeah-state-list reachable)))
    (yeah-check--fail
     (null unreachable)
     (format "the table of the machine has %d state(s) that no path leads to: %S"
             (length unreachable) unreachable))))

(let ((failures (delq nil
                     (list (yeah-check--every-label-of-the-table-is-taken)
                           (yeah-check--every-state-of-the-machine-is-reachable)))))
  (dolist (failure failures)
    (message "table: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-every-transition-of-the-table-is-taken.el ends here
