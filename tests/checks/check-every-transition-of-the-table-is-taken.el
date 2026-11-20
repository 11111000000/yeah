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
;; make: thirty-one cells, seventeen labels and eleven states.  The promise is
;; that every one of those cells is a move the runtime really takes -- and not
;; that every label of the table is taken somewhere.
;;
;; The first version of this check (wave 78) answered a weaker question, and
;; the discriminator named the gap twice (waves 79 and 80): a label that is
;; taken *somewhere* does not say that the move is taken *from the state the
;; cell names*.  The version of wave 80 read the label of every place of a
;; tick and the guard around it, but it never read the *state* that the guard
;; allows: the two branches that read it were dead code (they took
;; `(cdr (cdr form))' where the arguments of a form are `(cdr form)'), so
;; every cell was witnessed by any place of the label, and a runtime that took
;; the move of `deciding' from `post-decide' instead passed.
;;
;; This check asks the question the claim asks.  Five things are checked.
;;
;; 1. The table is well formed: every cell is `(FROM LABEL . TO)', the states
;;    of the cell are states of the machine, the label is a symbol, and the
;;    machine makes the move of the cell.
;; 2. Every cell of the table is a move the runtime takes: the runtime takes
;;    the label of the cell in a place that lives, and the place is in the
;;    state the cell names.  The state of a place is read from the guard
;;    around it and from the moves that precede it in the same branch.
;; 3. Every place of the runtime takes the move of the machine from the
;;    states the machine has that move from: a place whose guard names the
;;    state is in exactly those states, and a place that takes a move the
;;    machine does not have from a state its guard admits is named.
;; 4. Every fan of the table -- a label the table gives to several states --
;;    is kept by the runtime: the runtime takes the fan from every state the
;;    table gives it to, the runtime takes it from no other state, and the
;;    fan ends the run in one state.  The fan is compared with the runtime
;;    and not with the table: a fan that the runtime narrows is a fan the
;;    runtime does not keep, and the table cannot see that.
;; 5. Every state of the machine is reachable from the first one through the
;;    cells of the table.
;;
;; The liveness of a place is the liveness of the *runtime*: a root is a
;; definition with the cookie of an autoload and a definition a top-level
;; form of the kernel calls.  A definition that only the tests or the scripts
;; call is dead for the runtime -- the tests run it and the runtime does not
;; -- and a move that sits in such a definition is not a move of the runtime.
;; The liveness for the tests is a property of its own, and this check does
;; not measure it.
;;
;; A guard that says nothing about the state is a case of its own, and the
;; check names it.  Such a place excludes no state and witnesses the cells
;; of its label weakly: the runtime takes the label, and the machine has
;; that move only from the state of the cell.  The check counts those cells
;; and names them, so that a reader sees how much of the proof rests on
;; them.  The same holds for a fan the runtime does not state the states of.
;;
;; The check is static on purpose: it answers about the whole kernel at once,
;; and it answers the same way twice.  A dynamic check would need a run that
;; takes every move of the table, and there is no such run: a run that meets
;; no busy provider never takes `rate-blocked', and a run that never grows
;; long never takes `budget-overflow'.
;;
;; The check never dies: an error of the check is a verdict and not the death
;; of the process, because a check that crashes has not bitten.
;;
;; Exit codes: 0 -- every cell of the table is a move of the runtime; 1 -- one
;; is not, or the check could not read the kernel.

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

(defun yeah-check--roots-of-the-runtime (definitions)
  "Return the definitions of the kernel the runtime may come in by.
A root is a definition with the cookie of an autoload, and a definition a
top-level form of the kernel calls.  A definition that only the tests or the
scripts call is not a root: the runtime does not run it, and a move that
sits in such a place is not a move of the runtime."
  (let ((known (make-hash-table :test #'eq))
        (roots nil))
    (dolist (definition definitions)
      (puthash (plist-get definition :name) t known))
    ;; The doors of the outside world: the autoloads.
    (dolist (definition definitions)
      (when (plist-get definition :autoload)
        (push (plist-get definition :name) roots)))
    ;; The doors of the top-level forms of the kernel itself: a form that is
    ;; not a definition runs when the module is loaded.
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
  (let* ((roots (yeah-check--roots-of-the-runtime definitions))
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

(defun yeah-check--union (sets)
  "Return the union of SETS, a list of sets.
A union of one set is that set: `cl-union' wants two lists at least, and a
check that asks it for one dies instead of answering."
  (cond ((null sets) nil)
        ((null (cdr sets)) (car sets))
        (t (apply #'cl-union sets))))

(defun yeah-check--intersection (sets)
  "Return the intersection of SETS, a list of sets.
An intersection of one set is that set: `cl-intersection' wants two lists at
least, and a check that asks it for one dies instead of answering."
  (cond ((null sets) nil)
        ((null (cdr sets)) (car sets))
        (t (apply #'cl-intersection sets))))

(defun yeah-check--quoted-states (form)
  "Return the states FORM names, or nil when FORM names no state.
A quoted symbol names one state and a quoted list names several: the guard
of a place says which states it allows, and the states it allows are the
ones it names."
  (when (and (consp form) (eq (car form) 'quote) (consp (cdr form)))
    (let ((thing (car (cdr form))))
      (cond ((symbolp thing) (list thing))
            ((and (consp thing) (cl-every #'symbolp thing)) thing)
            (t nil)))))

(defun yeah-check--other-argument (form)
  "Return the argument of FORM that is not the state of the run.
The arguments of a form are `(cdr form)': the state of the run stands in one
of them, and the states it is compared with stand in another one."
  (let ((args (cdr form)))
    (cond ((and (consp args)
                (yeah-check--mentions yeah-check--state-reader (car args)))
           (cadr args))
          ((and (consp (cdr args))
                (yeah-check--mentions yeah-check--state-reader (cadr args)))
           (car args))
          (t nil))))

(defun yeah-check--state-set (form)
  "Return the states FORM allows the run to be in, or nil when it says nothing.
A form that names the state of the run says which states it allows; a form
that does not name it says nothing and leaves the states to the machine.

The arguments of a form are `(cdr form)', and the branch that read them took
`(cdr (cdr form))' before: it looked for the comparison in the place of the
state, found nothing, and the state of the run was never read.  The state
stands in one argument and the states it is compared with in another one."
  (cond
   ((and (consp form) (eq (car form) 'quote))
    (yeah-check--quoted-states form))
   ((and (consp form) (eq (car form) 'eq)
         (yeah-check--mentions yeah-check--state-reader form))
    (yeah-check--quoted-states (yeah-check--other-argument form)))
   ((and (consp form) (eq (car form) 'memq)
         (yeah-check--mentions yeah-check--state-reader form))
    (yeah-check--quoted-states (yeah-check--other-argument form)))
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
            (yeah-check--union sets)
          (yeah-check--intersection sets)))))
   (t nil)))

(defun yeah-check--states-of-a-guard (guard)
  "Return the states GUARD admits, or nil when GUARD says nothing about them.
The tests of the guard that say nothing about the state leave the states to
the machine, and the tests that say something are intersected."
  (let (sets)
    (dolist (test guard)
      (let ((set (yeah-check--state-set test)))
        (when set (push set sets))))
    (yeah-check--intersection sets)))

(defun yeah-check--destination (state label)
  "Return the state the machine moves to from STATE on LABEL, or nil."
  (and (yeah-state-p state) (yeah-loop-transition-p state label)))

(defun yeah-check--state-at (states before)
  "Return the states the run is in after the moves BEFORE, and the moves the
machine does not have.

STATES is the set of the states a place admits, or nil when its guard says
nothing about the state.  BEFORE is a list of the sets of the labels of the
moves that precede the place in its branch.  A move that the machine does not
have is returned as a defect: the runtime takes a move the machine does not
have, and the run would break at it.

The answer is a plist and not two values: `multiple-value-bind' is not a
macro of Emacs and not a function of it, and a check that calls a name that
does not exist dies instead of answering."
  (let ((broken nil))
    (dolist (labels before)
      (when states
        (cond ((null labels)
               ;; A move whose label the runtime does not name narrows
               ;; nothing.
               (setq states nil))
              ((null (cdr labels))
               (let (next)
                 (dolist (state states)
                   (let ((to (yeah-check--destination state (car labels))))
                     (if to
                         (push to next)
                       (push (list state (car labels)) broken))))
                 (setq states (delete-dups next))))
              (t
               ;; A move whose label the runtime computes narrows nothing.
               (setq states nil)))))
    (list :states states :broken broken)))

(defun yeah-check--ticks-in-body (body definition acc guard before)
  "Walk BODY, a list of forms, and collect the tick calls into ACC.
GUARD is the list of the tests of the conditionals the body sits under.
BEFORE is the list of the sets of the labels of the moves that precede the
body in its branch: a tick that stands alone in the body happens before what
follows it."
  (let ((tail body) (out acc) (seen before))
    (while (consp tail)
      (let ((form (car tail)))
        (setq out (yeah-check--ticks-in form definition out guard seen))
        (when (and (consp form) (eq (car form) yeah-check--tick-function))
          ;; The labels of the move are one set, and the set goes into the
          ;; list of the sets as one element: `append' would spread the
          ;; labels of the move over the list and the list would hold a
          ;; symbol where a set belongs.
          (setq seen (append seen (list (yeah-check--label-of form))))))
      (setq tail (cdr tail)))
    out))

(defun yeah-check--ticks-in (form definition acc guard before)
  "Collect the tick calls of FORM into ACC.
DEFINITION is the name of the definition FORM belongs to, or nil.  GUARD is
the list of the tests of the conditionals the call sits under; a test that
says which state the run is in is what tells the check from which state the
run takes the move.  BEFORE is the list of the sets of the labels of the
moves that precede FORM in its branch."
  (cond
   ((and (consp form) (eq (car form) yeah-check--tick-function))
    (push (list :definition definition
                :call form
                :labels (yeah-check--label-of form)
                :guard guard
                :before before)
          acc)
    acc)
   ((consp form)
    (let ((head (car form)))
      (cond
       ((eq head 'if)
        (let* ((test (cadr form))
               (out (yeah-check--ticks-in-body (list (nth 2 form)) definition acc
                                             (append (list test) guard) before)))
          (if (nth 3 form)
              (yeah-check--ticks-in-body (list (nth 3 form)) definition out
                                         (append (list (list 'not test)) guard)
                                         before)
            out)))
       ((memq head '(when unless))
        (let* ((test (cadr form))
               (inner (if (eq head 'when) test (list 'not test))))
          (yeah-check--ticks-in-body (cddr form) definition acc
                                     (append (list inner) guard) before)))
       ((eq head 'cond)
        (let ((out acc) (tail (cdr form)))
          (while tail
            (let ((clause (car tail)))
              (when (consp clause)
                (setq out (yeah-check--ticks-in-body
                           (cdr clause) definition out
                           (append (list (car clause)) guard) before))))
            (setq tail (cdr tail)))
          out))
       ((memq head '(pcase cl-case))
        (let* ((subject (cadr form))
               (about-the-state
                (yeah-check--mentions yeah-check--state-reader subject))
               (out acc) (tail (cddr form)))
          (while tail
            (let ((clause (car tail)))
              (when (consp clause)
                (setq out (yeah-check--ticks-in-body
                           (cdr clause) definition out
                           (append (if about-the-state (list (car clause)) nil)
                                   guard) before))))
            (setq tail (cdr tail)))
          out))
       (t
        ;; A form of the runtime is walked by its elements: the head of the
        ;; form and every argument of it.  The tail of a form may be a dotted
        ;; pair, and a walk that went on after the last cell of it would read
        ;; a symbol as a list.
        (yeah-check--ticks-in-body form definition acc guard before)))))
   (t acc)))

(defun yeah-check--tick-sites ()
  "Return the places of the ticks of the kernel, with the state of each.
A place is a call of `yeah-turn--tick' in the code of the kernel.  The state
of the place is the state its guard admits, moved by the moves that precede
it in its branch, and a move the machine does not have is kept beside it."
  (let (sites)
    (dolist (file (yeah-check--sources-of-the-kernel))
      (dolist (entry (yeah-check--forms-of file))
        (let* ((form (plist-get entry :form))
               (name (yeah-check--definition-name form)))
          (setq sites (yeah-check--ticks-in
                       (if name (cddr form) form)
                       name sites nil nil)))))
    (nreverse
     (mapcar (lambda (site)
               (let ((result
                      (yeah-check--state-at
                       (yeah-check--states-of-a-guard (plist-get site :guard))
                       (plist-get site :before))))
                 ;; `plist-put' changes the list it is given and may give a
                 ;; new one back: the answer of the place is the list that
                 ;; the last call returned and not the list that went in.
                 (setq site (plist-put site :states (plist-get result :states)))
                 (setq site (plist-put site :broken (plist-get result :broken)))
                 site))
             sites))))

(defun yeah-check--cells ()
  "Return the cells of the table of the machine."
  yeah-loop-transitions)

(defun yeah-check--labels-of-the-table ()
  "Return the labels the table of the machine names."
  (delete-dups (mapcar (lambda (cell) (nth 1 cell)) (yeah-check--cells))))

(defun yeah-check--states-of-a-label (label)
  "Return the states the machine has the move LABEL from."
  (delete-dups (mapcar (lambda (cell) (nth 0 cell))
                       (seq-filter (lambda (cell) (eq (nth 1 cell) label))
                                   (yeah-check--cells)))))

(defun yeah-check--live-sites (live places)
  "Return the places PLACES that sit in a definition the runtime runs."
  (seq-filter (lambda (place)
                (or (null (plist-get place :definition))
                    (memq (plist-get place :definition) live)))
              places))

(defun yeah-check--the-table-is-well-formed ()
  "Every cell of the table is a cell the machine makes.
A cell is `(FROM LABEL . TO)': the states of the cell are states of the
machine, the label is a symbol, and the machine answers the move of the cell
with the state of the cell."
  (let (broken)
    (dolist (cell (yeah-check--cells))
      (let ((from (nth 0 cell))
            (label (nth 1 cell))
            (to (nthcdr 2 cell)))
        (cond
         ((not (yeah-state-p from))
          (push (list cell :the-state-the-cell-leads-from-is-not-a-state)
                broken))
         ((not (yeah-state-p to))
          (push (list cell :the-state-the-cell-leads-to-is-not-a-state)
                broken))
         ((not (symbolp label))
          (push (list cell :the-label-of-the-cell-is-not-a-symbol) broken))
         ((not (eq (yeah-loop-transition-p from label) to))
          (push (list cell :the-machine-goes-elsewhere) broken)))))
    (yeah-check--fail
     (null broken)
     (format "the table of the machine names %d cell(s) the machine does not make: %S"
             (length broken) broken))))

(defun yeah-check--every-cell-is-a-move-of-the-runtime (places)
  "Every cell of the table is a move the runtime takes.
The runtime takes the label of the cell in a place that lives, and the place
is in a state the machine has the move from: a place that takes the move of
the cell from another state takes a move the machine does not have from
there.

A place whose guard says nothing about the state excludes no state, and it
witnesses the cell weakly: the runtime takes the label, and the machine has
that move only from the state of the cell."
  (let (broken)
    (dolist (cell (yeah-check--cells))
      (let ((from (nth 0 cell))
            (label (nth 1 cell))
            (witnessed nil))
        (dolist (place places)
          (when (memq label (plist-get place :labels))
            (setq witnessed t)
            (let ((states (plist-get place :states)))
              (when (and states (not (memq from states)))
                (push (list cell
                            :the-runtime-takes-the-move-from-another-state
                            (plist-get place :definition)
                            (cl-set-difference states
                                               (yeah-check--states-of-a-label label)))
                      broken)))))
        (unless witnessed
          (push (list cell :the-runtime-does-not-take-the-move) broken))))
    (yeah-check--fail
     (null broken)
     (format "the table of the machine names %d cell(s) the runtime does not take: %S"
             (length broken) broken))))

(defun yeah-check--every-place-takes-the-move-the-machine-has (places)
  "Every place of the runtime takes the move of the machine from the states
the machine has that move from.
The state of a place is the state its guard admits, moved by the moves that
precede it in its branch.  A place that takes a move the machine does not
have is named, and so is a place that stands in a state the machine has no
move of that label from."
  (let (broken)
    (dolist (place places)
      (dolist (move (plist-get place :broken))
        (push (list :the-runtime-takes-a-move-the-machine-has-not
                    :place (plist-get place :definition)
                    :from (nth 0 move)
                    :label (nth 1 move))
              broken))
      (let ((states (plist-get place :states)))
        (when states
          (dolist (label (plist-get place :labels))
            (unless (cl-subsetp states (yeah-check--states-of-a-label label))
              (push (list :the-place-stands-in-a-state-the-machine-has-no-move-from
                          :place (plist-get place :definition)
                          :label label
                          :states (cl-set-difference
                                   states (yeah-check--states-of-a-label label)))
                    broken))))))
    (yeah-check--fail
     (null broken)
     (format "the runtime takes %d move(s) the machine does not have: %S"
             (length broken) broken))))

(defun yeah-check--coverage-of-a-fan (places label)
  "Return the states the runtime takes the fan LABEL from.
The coverage is what the runtime says: the states the guards of the places of
the fan admit.  A place whose guard says nothing about the state says
nothing, and the coverage of such a fan is not stated."
  (let (coverage)
    (dolist (place places)
      (when (memq label (plist-get place :labels))
        (dolist (state (plist-get place :states))
          (push state coverage))))
    (delete-dups coverage)))

(defun yeah-check--every-fan-is-kept-by-the-runtime (places)
  "Every fan of the table is kept by the runtime.
A fan is a label the table gives to several states.  The runtime takes the
fan in a place, and the guard of that place says from which states the run
may be when the fan is taken.  The states the runtime takes the fan from are
the states the machine has the move from: a fan the runtime narrows is a fan
the runtime does not keep.  The fan ends the run in one state."
  (let (broken)
    (dolist (label (yeah-check--labels-of-the-table))
      (let ((states (yeah-check--states-of-a-label label)))
        (when (> (length states) 1)
          (let ((coverage (yeah-check--coverage-of-a-fan places label)))
            (unless (or (null coverage)
                        (cl-subsetp states coverage))
              (push (list label :the-runtime-narrows-the-fan
                          (cl-set-difference states coverage))
                    broken)))
          (let ((destinations (delete-dups
                                (mapcar (lambda (cell) (nthcdr 2 cell))
                                        (seq-filter
                                         (lambda (cell) (eq (nth 1 cell) label))
                                         (yeah-check--cells))))))
            (unless (= 1 (length destinations))
              (push (list label :the-fan-does-not-end-in-one-state destinations)
                    broken))))))
    (yeah-check--fail
     (null broken)
     (format "the table of the machine names %d fan(s) the runtime does not keep: %S"
             (length broken) broken))))

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

(defun yeah-check--weak-cells (places)
  "Return the cells that rest on a guard that says nothing about the state.
A place whose guard names the state proves the cell it witnesses; a place
whose guard says nothing about the state does not name any state, and the
cell it witnesses rests on the machine alone."
  (let (weak)
    (dolist (cell (yeah-check--cells))
      (let ((from (nth 0 cell))
            (label (nth 1 cell))
            (strong nil))
        (dolist (place places)
          (when (memq label (plist-get place :labels))
            (let ((states (plist-get place :states)))
              (when (and states (memq from states))
                (setq strong t)))))
        (unless strong
          (push cell weak))))
    (nreverse weak)))

(defun yeah-check--unstated-fans (places)
  "Return the fans the runtime does not state the states of."
  (let (unstated)
    (dolist (label (yeah-check--labels-of-the-table))
      (when (and (> (length (yeah-check--states-of-a-label label)) 1)
                 (null (yeah-check--coverage-of-a-fan places label)))
        (push label unstated)))
    (nreverse unstated)))

(defun yeah-check--report (places all)
  "Say what the check measured.
PLACES are the places of the ticks the runtime runs, and ALL are the places
of the ticks of the kernel."
  (message "table: %d cell(s), %d label(s), %d state(s); %d place(s) of a tick in the kernel, %d of them live"
           (length (yeah-check--cells))
           (length (yeah-check--labels-of-the-table))
           (length yeah-state-list)
           (length all)
           (length places))
  (let ((weak (yeah-check--weak-cells places)))
    (message "table: %d cell(s) rest on a guard that says nothing about the state: %S"
             (length weak) weak))
  (let ((unstated (yeah-check--unstated-fans places)))
    (when unstated
      (message "table: the runtime does not say from which states it takes the fan(s): %S"
               unstated))))

(defun yeah-check--verdict ()
  "Return the failures of the check, or nil when the check passes.
An error of the check is a failure of the check and not the death of the
process: a check that dies has not bitten."
  (condition-case err
      (let* ((definitions (yeah-check--definitions-of-the-kernel))
             (live (yeah-check--live-definitions definitions))
             (all (yeah-check--tick-sites))
             (places (yeah-check--live-sites live all))
             (failures (delq nil
                             (list (yeah-check--the-table-is-well-formed)
                                   (yeah-check--every-cell-is-a-move-of-the-runtime
                                    places)
                                   (yeah-check--every-place-takes-the-move-the-machine-has
                                    places)
                                   (yeah-check--every-fan-is-kept-by-the-runtime
                                    places)
                                   (yeah-check--every-state-of-the-machine-is-reachable)))))
        (unless failures
          (yeah-check--report places all))
        failures)
    (error
     (list (format "the check could not read the kernel: %s"
                    (error-message-string err))))))

(let ((failures (yeah-check--verdict)))
  (dolist (failure failures)
    (message "table: %s" failure))
  (kill-emacs (if failures 1 0)))

;;; check-every-transition-of-the-table-is-taken.el ends here
