;;; check-every-transition-of-the-table-is-taken.el --- every cell of the table is a move of the runtime -*- lexical-binding: t; no-byte-compile: t -*-
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
;; The first version of this check (wave 78) answered a weaker question: it
;; proved that every *label* of the table has a place in the runtime where the
;; move is taken, and that every state of the machine is reachable.  A
;; discriminator showed that the answer was weaker than the name of the claim:
;; the check stayed green when the table lost the edge that lets a run in
;; `compacting' fail, and the runtime of that table refuses to move a run that
;; is compacting into `failed'.  A label that is taken *somewhere* does not
;; say that the move is taken *from the state the table names*.
;;
;; This check asks the question the claim asks: is every **cell** of the table
;; a move the runtime really walks?  Five things are checked.
;;
;; 1. Every cell of the table is a move the machine makes: the machine's own
;;    function takes the cell from its state and brings the run to the state
;;    the cell names.
;; 2. Every label of the table has a **live** place in the runtime: a call of
;;    `yeah-turn--tick' in the position of the label, inside a definition the
;;    kernel really runs.  A label that is taken only in a function nobody
;;    calls is not taken.
;; 3. Every **fan** of the table -- a label the table gives to several states
;;    -- covers exactly the states a run can live in, and ends the run in one
;;    state.  The runtime fails and cancels a run from whatever state it lives
;;    in, and the machine must have that edge from every one of those states.
;; 4. Every cell of the table is walked: the cells of the labels with one
;;    state are walked because the machine has no other cell for that label,
;;    and the cells of the fans are walked because of (3).
;; 5. Every state of the machine is reachable from the first one through the
;;    cells of the table.
;;
;; The check is static on purpose: it answers about the whole kernel at once,
;; and it answers the same way twice.  A dynamic check would need a run that
;; takes every move of the table, and there is no such run: a run that meets
;; no busy provider never takes `rate-blocked', and a run that never grows
;; long never takes `budget-overflow'.
;;
;; Exit codes: 0 -- every cell of the table is a move of the runtime; 1 -- one
;; is not.

;;; Code:

(require 'cl-lib)
(require 'yeah-loop)
(require 'yeah-state)

(defconst yeah-check--tick-function 'yeah-turn--tick
  "The function the runtime moves a run with.")

(defconst yeah-check--state-reader 'yeah-turn-state
  "The accessor that reads the state of a run.")

(defconst yeah-check--definition-forms
  '(defun defmacro defsubst cl-defun cl-defmacro define-minor-mode)
  "The forms of the kernel that define a function.")

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

(defun yeah-check--files-under (relative)
  "Return the files under the directory RELATIVE of the project."
  (let ((directory (expand-file-name relative (yeah-check--root))))
    (when (file-directory-p directory)
      (sort (mapcar (lambda (name) (expand-file-name name directory))
                    (directory-files directory t "\\.el\\'"))
            #'string<))))

(defun yeah-check--skip-comments-and-space ()
  "Move the point past the whitespace and the line comments.
A comment of Elisp runs to the end of its line, and the buffer of the reader
has no syntax table of its own: the skip is done here and not by the mode."
  (let ((moved t))
    (while moved
      (setq moved nil)
      (skip-chars-forward " \t\n\r\f")
      (when (looking-at ";")
        (goto-char (line-end-position))
        (setq moved t)))))

(defun yeah-check--forms-of (file)
  "Return the top-level forms of FILE, each with the line it starts at.
The line matters: the cookie `;;;###autoload' stands above a definition, and
a definition with that cookie is a door the outside world may come in by."
  (with-temp-buffer
    (insert-file-contents file)
    (let (forms)
      (condition-case nil
          (while t
            (yeah-check--skip-comments-and-space)
            (let ((start (point)))
              (push (list :line (line-number-at-pos start)
                          :form (read (current-buffer)))
                    forms)))
        (end-of-file))
      (nreverse forms))))

(defun yeah-check--autoload-lines (file)
  "Return the lines of FILE that carry the cookie of an autoload."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((lines nil) (number 0))
      (while (not (eobp))
        (setq number (1+ number))
        (when (string-match-p ";;;###autoload"
                               (buffer-substring-no-properties
                                (line-beginning-position) (line-end-position)))
          (push number lines))
        (forward-line 1))
      (nreverse lines))))

(defun yeah-check--definition-name (form)
  "Return the name FORM defines, or nil when FORM defines no function."
  (and (consp form)
       (memq (car form) yeah-check--definition-forms)
       (cadr form)))

(defun yeah-check--mentions (symbol form)
  "Return non-nil when FORM mentions SYMBOL."
  (cond ((eq form symbol) t)
        ((consp form)
         (let ((tail form) (hit nil))
           (while (and (consp tail) (not hit))
             (setq hit (yeah-check--mentions symbol (car tail)))
             (setq tail (cdr tail)))
           hit))
        ((vectorp form)
         (let ((index 0) (hit nil))
           (while (and (< index (length form)) (not hit))
             (setq hit (yeah-check--mentions symbol (aref form index)))
             (setq index (1+ index)))
           hit))
        (t nil)))

(defun yeah-check--calls-in-1 (form table)
  "Add to TABLE the symbols FORM calls or names.
A call is a symbol in the head of a form; a function designator and a quoted
symbol are names too, and the runtime reaches a function through both.

The walk goes into every subform, and not into the head of a form only: the
body of a `let' or of a `cl-letf' is a call of the runtime like any other,
and a walk that stopped at the head would lose it.  A pair with a dot is a
form too, and its tail is walked apart from its head.

The names go into a table and not into a list: a list that the walk passes
down would lose the names that the walk adds, because the caller keeps the
head of the list and not the new cell."
  (cond
   ((consp form)
    (when (symbolp (car form))
      (puthash (car form) t table)
      (when (memq (car form) '(function quote))
        (when (and (consp (cdr form)) (symbolp (car (cdr form))))
          (puthash (car (cdr form)) t table))))
    (let ((tail form))
      (while (consp tail)
        (yeah-check--calls-in-1 (car tail) table)
        (setq tail (cdr tail)))
      (when tail
        (yeah-check--calls-in-1 tail table))))
   ((vectorp form)
    (let ((index 0))
      (while (< index (length form))
        (yeah-check--calls-in-1 (aref form index) table)
        (setq index (1+ index))))))
  table)

(defun yeah-check--calls-in (form)
  "Return the symbols FORM calls or names, without repeats."
  (let ((table (make-hash-table :test (quote eq))))
    (yeah-check--calls-in-1 form table)
    (let (names)
      (maphash (lambda (name _value) (push name names)) table)
      names)))

(defun yeah-check--definitions-of-the-kernel ()
  "Return the definitions of the kernel, each with its name and its body."
  (let (definitions)
    (dolist (file (yeah-check--sources-of-the-kernel))
      (let ((autoloads (yeah-check--autoload-lines file)))
        (dolist (entry (yeah-check--forms-of file))
          (let* ((form (plist-get entry :form))
                 (name (yeah-check--definition-name form))
                 (line (plist-get entry :line)))
            (when name
              (push (list :name name
                          :file file
                          :line line
                          :body (cddr form)
                          :autoload (cl-some (lambda (n) (<= 1 (- line n) 2))
                                             autoloads))
                    definitions))))))
    definitions))

(defun yeah-check--definition-by-name (definitions name)
  "Return the definition NAME of DEFINITIONS, or nil."
  (cl-find-if (lambda (definition) (eq (plist-get definition :name) name))
              definitions))

(defun yeah-check--roots-of-the-kernel (definitions)
  "Return the definitions of the kernel the outside world may come in by.
A root is a definition with the cookie of an autoload, a definition the tests
and the scripts call, and a definition a top-level form of the kernel calls."
  (let ((known (make-hash-table :test #'eq))
        (roots nil))
    (dolist (definition definitions)
      (puthash (plist-get definition :name) t known))
    ;; The doors of the outside world: the autoloads.
    (dolist (definition definitions)
      (when (plist-get definition :autoload)
        (push (plist-get definition :name) roots)))
    ;; The doors of the tests and the scripts.
    (dolist (file (append (yeah-check--files-under "tests")
                           (yeah-check--files-under "scripts")))
      (dolist (entry (yeah-check--forms-of file))
        (dolist (name (yeah-check--calls-in (plist-get entry :form)))
          (when (gethash name known)
            (push name roots)))))
    ;; The doors of the top-level forms of the kernel itself.
    (dolist (file (yeah-check--sources-of-the-kernel))
      (dolist (entry (yeah-check--forms-of file))
        (unless (yeah-check--definition-name (plist-get entry :form))
          (dolist (name (yeah-check--calls-in (plist-get entry :form)))
            (when (gethash name known)
              (push name roots))))))
    (delete-dups roots)))

(defun yeah-check--live-definitions (definitions)
  "Return the names of the definitions of the kernel the runtime runs.
A definition is live when a root calls it, or when a live definition calls
it.  A definition nobody calls is a place the runtime never goes, and a move
that sits in such a place is not taken."
  (let* ((roots (yeah-check--roots-of-the-kernel definitions))
         (seen (make-hash-table :test #'eq))
         (queue nil))
    (dolist (root roots)
      (puthash root t seen)
      (push root queue))
    (while queue
      (let* ((name (pop queue))
             (definition (yeah-check--definition-by-name definitions name)))
        (when definition
          (dolist (called (yeah-check--calls-in (plist-get definition :body)))
            (unless (gethash called seen)
              (when (yeah-check--definition-by-name definitions called)
                (puthash called t seen)
                (push called queue)))))))
    (let (live)
      (maphash (lambda (name _value) (push name live)) seen)
      live)))

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

(defun yeah-check--label-of (call)
  "Return the labels the tick call CALL takes.
The label is the third element of the call: the runtime moves a run with
`(yeah-turn--tick TURN LABEL)'.  A label the runtime computes is read as the
set of the labels that the computation names."
  (let ((form (nth 2 call)))
    (cond ((null form) nil)
          ((and (consp form) (eq (car form) 'quote) (consp (cdr form)))
           (list (car (cdr form))))
          ((consp form) (yeah-check--quoted-symbols form))
          (t nil))))

(defun yeah-check--ticks-in-body (body definition acc guard)
  "Walk BODY, a list of forms, and collect the tick calls into ACC.
GUARD is the list of the tests of the conditionals the body sits under."
  (let ((tail body) (out acc))
    (while tail
      (setq out (yeah-check--ticks-in (car tail) definition out guard))
      (setq tail (cdr tail)))
    out))

(defun yeah-check--ticks-in (form definition acc guard)
  "Collect the tick calls of FORM into ACC.
DEFINITION is the name of the definition FORM belongs to, or nil.  GUARD is the
list of the tests of the conditionals the call sits under; a test that says
which state the run is in is what tells the check from which state the run
takes the move."
  (cond
   ((and (consp form) (eq (car form) yeah-check--tick-function))
    (push (list :definition definition :call form :guard guard) acc)
    acc)
   ((consp form)
    (let ((head (car form)))
      (cond
       ((eq head 'if)
        (let* ((test (cadr form))
               (out (yeah-check--ticks-in-body (list (nth 2 form)) definition acc
                                             (append (list test) guard))))
          (if (nth 3 form)
              (yeah-check--ticks-in-body (list (nth 3 form)) definition out
                                        (append (list (list 'not test)) guard))
            out)))
       ((memq head '(when unless))
        (let* ((test (cadr form))
               (inner (if (eq head 'when) test (list 'not test))))
          (yeah-check--ticks-in-body (cddr form) definition acc
                                     (append (list inner) guard))))
       ((eq head 'cond)
        (let ((out acc) (tail (cdr form)))
          (while tail
            (let ((clause (car tail)))
              (when (consp clause)
                (setq out (yeah-check--ticks-in-body
                           (cdr clause) definition out
                           (append (list (car clause)) guard)))))
            (setq tail (cdr tail)))
          out))
       ((memq head '(pcase cl-case))
        (let* ((subject (cadr form))
               (about-the-state
                (yeah-check--mentions yeah-check--state-reader subject))
               (out acc) (tail (cdr form)))
          (while tail
            (let ((clause (car tail)))
              (when (consp clause)
                (setq out (yeah-check--ticks-in-body
                           (cdr clause) definition out
                           (append (if about-the-state (list (car clause)) nil)
                                   guard)))))
            (setq tail (cdr tail)))
          out))
       (t
        (let ((tail form) (out acc))
          (while (consp tail)
            (setq out (yeah-check--ticks-in (car tail) definition out guard))
            (setq tail (cdr tail)))
          out)))))
   (t acc)))

(defun yeah-check--tick-sites ()
  "Return the tick calls of the kernel with the definition each of them sits in."
  (let (sites)
    (dolist (file (yeah-check--sources-of-the-kernel))
      (dolist (entry (yeah-check--forms-of file))
        (let* ((form (plist-get entry :form))
               (name (yeah-check--definition-name form)))
          (setq sites (yeah-check--ticks-in
                       (if name (cddr form) form)
                       name sites nil)))))
    (nreverse sites)))

(defun yeah-check--state-set (form)
  "Return the states FORM allows the run to be in, or nil when it says nothing.
A form that names the state of the run says which states it allows; a form
that does not name it says nothing and leaves the states to the machine."
  (cond
   ((and (consp form) (eq (car form) 'quote)
         (consp (cdr form)) (symbolp (car (cdr form))))
    (list (car (cdr form))))
   ((and (consp form) (eq (car form) 'eq)
         (yeah-check--mentions yeah-check--state-reader form))
    (let ((rest (cdr (cdr form))))
      (when (and (consp rest) (eq (car rest) 'quote))
        (list (car (cdr rest))))))
   ((and (consp form) (eq (car form) 'memq)
         (yeah-check--mentions yeah-check--state-reader form))
    (let ((rest (cdr (cdr form))))
      (when (and (consp rest) (eq (car rest) 'quote))
        (cdr (cdr rest)))))
   ((and (consp form) (eq (car form) 'not))
    (let ((set (yeah-check--state-set (cadr form))))
      (and set (cl-set-difference yeah-state-list set))))
   ((and (consp form) (memq (car form) '(or and)))
    (let (sets)
      (dolist (operand (cdr form))
        (let ((set (yeah-check--state-set operand)))
          (when set (push set sets))))
      (when sets
        (if (eq (car form) 'or)
            (apply #'cl-union sets)
          (apply #'cl-intersection sets)))))
   (t nil)))

(defun yeah-check--constraint-of-a-site (site)
  "Return the states the guard of SITE allows, or nil when it says nothing.
A guard that says nothing about the state of the run leaves the states to the
machine, and the check does not read a state out of it."
  (let (sets)
    (dolist (test (plist-get site :guard))
      (let ((set (yeah-check--state-set test)))
        (when set (push set sets))))
    (when sets
      (apply #'cl-intersection sets))))

(defun yeah-check--cells ()
  "Return the cells of the table of the machine."
  yeah-loop-transitions)

(defun yeah-check--labels-of-the-table ()
  "Return the labels the table of the machine names."
  (delete-dups (mapcar (lambda (cell) (nth 1 cell)) (yeah-check--cells))))

(defun yeah-check--states-of-a-label (label)
  "Return the states the table gives the edge LABEL to."
  (delete-dups (mapcar (lambda (cell) (nth 0 cell))
                       (seq-filter (lambda (cell) (eq (nth 1 cell) label))
                                   (yeah-check--cells)))))

(defun yeah-check--running-states ()
  "Return the states a run can live in: the states the table has an edge from.
A state without an outgoing edge is a state the run is finished in."
  (delete-dups (mapcar (lambda (cell) (nth 0 cell)) (yeah-check--cells))))

(defun yeah-check--live-sites (live)
  "Return the tick sites that sit in a definition the runtime runs."
  (seq-filter (lambda (site)
                (or (null (plist-get site :definition))
                    (memq (plist-get site :definition) live)))
              (yeah-check--tick-sites)))

(defun yeah-check--every-cell-is-a-move-of-the-machine ()
  "Every cell of the table is a move the machine makes."
  (let (broken)
    (dolist (cell (yeah-check--cells))
      (let ((from (nth 0 cell))
            (label (nth 1 cell))
            (to (nthcdr 2 cell)))
        (condition-case nil
            (unless (eq (yeah-loop-tick from label) to)
              (push (list cell :the-machine-goes-elsewhere) broken))
          (user-error
           (push (list cell :the-machine-refuses-the-move) broken)))))
    (yeah-check--fail
     (null broken)
     (format "the table of the machine names %d cell(s) the machine does not make: %S"
             (length broken) broken))))

(defun yeah-check--every-label-of-the-table-is-taken (live)
  "Every label of the table has a live place in the runtime that takes it."
  (let ((sites (yeah-check--live-sites live))
        (missing nil))
    (dolist (label (yeah-check--labels-of-the-table))
      (unless (cl-some (lambda (site) (memq label (yeah-check--label-of
                                                   (plist-get site :call))))
                       sites)
        (push label missing)))
    (yeah-check--fail
     (null missing)
     (format "the table of the machine names %d move(s) that the runtime does not take: %S"
             (length missing) missing))))

(defun yeah-check--every-fan-covers-the-running-states (live)
  "Every fan of the table covers exactly the states a run can live in.
A fan is a label the table gives to several states: the runtime takes it from
whatever state the run lives in, and the machine must have that edge from
every one of those states and from no other.  The fan ends the run in one
state, and the runtime must not ask for a move the machine does not have."
  (let ((sites (yeah-check--live-sites live))
        (running (yeah-check--running-states))
        (broken nil))
    (dolist (label (yeah-check--labels-of-the-table))
      (let ((states (yeah-check--states-of-a-label label)))
        (when (> (length states) 1)
          (unless (and (null (cl-set-difference states running))
                       (null (cl-set-difference running states)))
            (push (list label :the-fan-does-not-cover-the-running-states states)
                  broken))
          (let ((destinations (delete-dups
                                (mapcar (lambda (cell) (nthcdr 2 cell))
                                        (seq-filter (lambda (cell)
                                                      (eq (nth 1 cell) label))
                                                    (yeah-check--cells))))))
            (unless (= 1 (length destinations))
              (push (list label :the-fan-does-not-end-in-one-state destinations)
                    broken)))
          (dolist (site sites)
            (when (memq label (yeah-check--label-of (plist-get site :call)))
              (let ((allowed (yeah-check--constraint-of-a-site site)))
                (when (and allowed
                           (not (cl-subsetp allowed
                                           (yeah-check--states-of-a-label label))))
                  (push (list label
                              :the-runtime-asks-for-a-move-the-machine-has-not
                              (cl-set-difference allowed
                                                 (yeah-check--states-of-a-label label)))
                        broken))))))))
    (yeah-check--fail
     (null broken)
     (format "the table of the machine names %d fan(s) the runtime does not keep: %S"
             (length broken) broken))))

(defun yeah-check--every-cell-of-the-table-is-walked (live)
  "Every cell of the table is a move the runtime walks.
A label the table gives to one state has one cell, and the runtime takes that
label: the machine has no other cell for it, so the runtime walks that one.
A fan covers every state a run can live in, and the runtime takes the fan
too, so every cell of the fan is walked as well."
  (let ((sites (yeah-check--live-sites live))
        (walked nil))
    (dolist (label (yeah-check--labels-of-the-table))
      (when (cl-some (lambda (site) (memq label (yeah-check--label-of
                                                   (plist-get site :call))))
                     sites)
        (dolist (cell (seq-filter (lambda (cell) (eq (nth 1 cell) label))
                                  (yeah-check--cells)))
          (push cell walked))))
    (let ((missing (cl-set-difference (yeah-check--cells) walked)))
      (yeah-check--fail
       (null missing)
       (format "the table of the machine names %d cell(s) the runtime never walks: %S"
               (length missing) missing)))))

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

(let* ((definitions (yeah-check--definitions-of-the-kernel))
       (live (yeah-check--live-definitions definitions))
       (failures (delq nil
                       (list (yeah-check--every-cell-is-a-move-of-the-machine)
                             (yeah-check--every-label-of-the-table-is-taken live)
                             (yeah-check--every-fan-covers-the-running-states live)
                             (yeah-check--every-cell-of-the-table-is-walked live)
                             (yeah-check--every-state-of-the-machine-is-reachable)))))
  (dolist (failure failures)
    (message "table: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-every-transition-of-the-table-is-taken.el ends here
