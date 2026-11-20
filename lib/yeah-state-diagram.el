;;; yeah-state-diagram.el --- the diagram of the state machine from the code -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The machine of the kernel is a table in the code, and not a drawing: the
;; states are the states of `yeah-state-list' and the arrows are the cells of
;; `yeah-loop--raw-transitions'.  The diagram of that machine is therefore
;; written out of the table and not drawn by hand -- the two cannot drift
;; apart, because the table is the only source of the diagram: the table
;; changed, the diagram is another one.
;;
;; The source of the diagram is PlantUML, and the file of it is
;; `site/diagrams/state-machine.puml'.  The writing of that file belongs to
;; `scripts/dev state-diagram'; this module knows how to say the diagram and
;; nothing else.
;;
;; The source is a function of the code and of nothing else: no date, no
;; hash, no order of its own.  The same code gives the same bytes, and the
;; bytes can be compared with the file of the repository.
;;
;; PlantUML reads an identifier of a state as letters, digits and `_' -- a
;; name with a dash in it (`post-decide') is not an identifier and the
;; diagram does not parse.  A name that PlantUML cannot read keeps its text
;; as the label of the state and gets an identifier of its own, and the
;; arrows of the diagram speak that identifier.  The names of the machine are
;; therefore in the diagram as they are, and the picture of the diagram shows
;; them as they are.

;;; Code:

(require 'yeah-state)
(require 'yeah-loop)

(defun yeah-state-diagram--identifier (state)
  "Return the PlantUML identifier of the state STATE.

A name that PlantUML reads as an identifier is the identifier itself;
every other name becomes its letters, its digits and its `_'."
  (replace-regexp-in-string "[^A-Za-z0-9_]" "_" (symbol-name state)))

(defun yeah-state-diagram--puml ()
  "Return the PlantUML source of the state machine of the kernel.

The states of the diagram are the states of `yeah-state-list', the arrows
are the cells of `yeah-loop--raw-transitions' in the order of the table,
and the state the machine starts in is the state the first cell of the
table comes from."
  (let* ((states yeah-state-list)
         (by-state (mapcar (lambda (state)
                             (cons state (yeah-state-diagram--identifier state)))
                           states))
         (start (and yeah-loop--raw-transitions
                      (nth 0 (car yeah-loop--raw-transitions))))
         (lines nil))
    ;; Two states that PlantUML cannot tell apart are one state in the
    ;; picture and two in the machine: the diagram would lie, and a diagram
    ;; that lies is not a diagram.
    (when (> (length states)
             (length (delete-dups (mapcar #'cdr by-state))))
      (error "yeah-state-diagram: two states of the machine have the same identifier"))
    (when (and start (not (assq start by-state)))
      (error "yeah-state-diagram: the state %S of the first cell is not a state of the machine" start))
    (push "@startuml state-machine" lines)
    (push "' The machine of the kernel: the states of `yeah-state-list' and the cells of `yeah-loop--raw-transitions'." lines)
    (dolist (state states)
      (let ((name (symbol-name state))
            (id (cdr (assq state by-state))))
        (push (if (string= name id)
                  (format "state %s" name)
                (format "state \"%s\" as %s" name id))
              lines)))
    (when start
      (push (format "[*] --> %s" (cdr (assq start by-state))) lines))
    (dolist (cell yeah-loop--raw-transitions)
      (push (format "%s --> %s : %s"
                    (cdr (assq (nth 0 cell) by-state))
                    (cdr (assq (nthcdr 2 cell) by-state))
                    (nth 1 cell))
            lines))
    (push "@enduml" lines)
    (concat (mapconcat #'identity (reverse lines) "\n") "\n")))

(defun yeah-state-diagram-print ()
  "Print the PlantUML source of the state machine of the kernel.

Nothing else is printed: the source of the diagram is the source and
nothing else, and a byte of noise in it is a byte of noise in the
diagram of the site."
  (princ (yeah-state-diagram--puml)))

(provide 'yeah-state-diagram)

;;; yeah-state-diagram.el ends here
