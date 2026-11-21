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
;; The version of wave 82 read the state of a place and compared the fans with
;; the runtime.  The discriminator of that wave named three gaps of the proof
;; (the findings F9, F10 and F11 of wave 85), and this version closes them.
;;
;; 1. The state of a place was read from the guard around it alone.  A guard
;;    that says nothing about the state left the place blind, and the runtime
;;    took the move of `tool-end' from `accumulating' without the check
;;    seeing it.  The state of a place is now read from the guard *and* from
;;    the moves that precede it in the same branch: the runtime sets the state
;;    of a run to the state the machine moves to, so the state after a move is
;;    known even where the guard says nothing.
;; 2. A name of a function counted as a call of it: `(function f)' and `'f'
;;    put the function into the graph of the runtime, and a definition that
;;    only a `defconst' names was live for the runtime.  A call is a symbol in
;;    the head of a form; a name is a name, and it calls nothing.  A name in
;;    the first argument of `funcall' or of `apply' is a call, because the
;;    runtime calls the value there.
;; 3. A state that a local variable held was not read at all: the guard
;;    around the place said nothing, the place dropped out of every check,
;;    and the check passed.  A local variable that is bound to the state of
;;    the run names the state now.
;;
;; The version of wave 88 closed two more holes of the proof (the findings F19
;; and F20 of the discriminator of that wave).  The code of the kernel did not
;; change: both holes were in the proof.
;;
;; 1. A place that stands in no definition of the kernel counted as live
;;    (F19).  A top-level form of the kernel is not the code of a run: a tick
;;    that stands in the body of a constant that nobody calls is a move the
;;    runtime does not take, and the check counted it as a witness of the
;;    cell of that move.  Such a place is dead for the runtime now, and the
;;    check names the places of that kind apart, so that a reader sees how
;;    many there are.
;; 2. A place whose label the check cannot read dropped out of every verdict
;;    (F20).  The label of such a place names no cell of the table, is
;;    checked against no state, and breaks the chain of the moves around it,
;;    so a runtime that took a move the machine does not have passed the
;;    check and the report of the check said less than it said before.  A
;;    place whose label cannot be read is a defect of its own now, and the
;;    check names it by its file and its line.
;;
;; The version of wave 90 closed four more holes of the proof (the finding F23
;; of the discriminator of the waves 87 to 89, and the three classes of escape
;; that the review of the wave found beside it).  The code of the kernel did not
;; change again: the hole was in the proof.
;;
;; 1. A name in a quoted list counted as a call (F23).  The walk of the calls
;;    went into the operands of a `quote', and the head of the quoted list
;;    became a call: a definition that only a quoted list named was a root of
;;    the runtime, and the move inside it was a move of the runtime.  The
;;    doctrine of this check says the opposite -- a name is not a call -- and
;;    the code of the walk said otherwise.  The walk does not go into data
;;    now: the operands of a `quote' are names, the designator of a `function'
;;    is a name, and the parameters of a `lambda' are names.  The body of a
;;    `lambda' is code wherever it stands, also under a `function', and a name
;;    in the first argument of a `funcall' or of an `apply' is still a call,
;;    because the runtime calls the value there.
;;
;; 2. A name in a list of names counted as a call.  The walk of the calls read
;;    the names of the bindings of a `let' as calls, and the same held of the
;;    variable of the spec of a `dolist', of the pattern of a `pcase' and of
;;    the types of the handlers of a `condition-case'.  A name in a list of
;;    names calls nothing: the runtime reads the names and it does not run
;;    them, and a definition that only such a list names is dead for the
;;    runtime.  The walk does not go into the names now: the values of the
;;    bindings, the collection of the spec, the subject of a `pcase', the
;;    bodies of the clauses and the bodies of the handlers are code, and the
;;    walk goes into them.
;;
;; 3. A tick in a quoted form counted as a place.  The walk of the places read
;;    the operands of a `quote' as code, and a tick that stood in a quoted
;;    form was a place of the runtime: the runtime does not run a quoted form,
;;    so such a place witnesses nothing at all.  The walk does not go into
;;    data now: a tick in a `quote' is no place, and the parts that are
;;    unquoted in a `backquote' are the only code of it.
;;
;; 4. The name of a type and the names of the slots counted as calls.  The
;;    description of a `cl-defstruct' is a list of names, and the walk of the
;;    calls read the head of it as a call: a definition whose name only the
;;    description of a struct named was a root of the runtime, and the move
;;    inside it was a move of the runtime.  The walk does not go into the
;;    names now: the name of the type, the names of its options and the names
;;    of its slots are names, the value of a slot is code, and the walk goes
;;    into it.  The obsolete `defstruct' is the same position: it expands into
;;    a `cl-defstruct' and the walk reads it the same way.
;;
;;    The name of a derived mode and the name of its parent are names as
;;    well, and the walk reads the position of a `define-derived-mode' by rule
;;    now: the name of the mode, the name of its parent, the name of the mode
;;    line and the doc string are names and data, the value of a keyword is
;;    code, and the body of the mode is code.  No escape of the runtime was
;;    open in that position -- the name of a mode stands in a symbol, and the
;;    walk reads a symbol as no call -- and the rule is written down because
;;    the walk reads the positions it knows, and a position it does not know
;;    is read as a call.
;;
;; The walk reads the positions it knows, and a position it does not know is
;; read as a call.  The kernel holds no other such position today, and the
;; positions of the family that it does not hold are named here: the keys of
;; the clauses of a `case' are data, the names of the bindings of a
;; `destructuring-bind' and of a `multiple-value-bind' are names, the
;; specializer of a `cl-defmethod' is data, and the doc string of a
;; `cl-defgeneric' is data.  The names of a `defalias' stand in a `quote',
;; and the walk reads a quoted form as data.  The name of a `defvar' and of a
;; `defconst' and of a `defcustom' is a symbol and not a list, and the walk
;; cannot read it as a call.  A kernel that grows one of the positions above
;; would need the walk to learn it, and the objection of the wave names that
;; gap.
;;
;; The version of wave 93 closed the last hole of the walk of the calls (the
;; finding F27 of the discriminator of the waves 90 to 92).  The code of the
;; kernel did not change: the hole was in the proof again.
;;
;; 1. The walk read every symbol in the head of a form as a call of the
;;    runtime, whatever the head was.  A head that is a macro or a special
;;    form is not a call of an ordinary function: the arguments of such a form
;;    are the positions of a name and of a code, and the walk has to know them.
;;    The walk asked no one and walked every argument of every form as code, so
;;    a name in the position of a name was read as a call: the name of a
;;    binding of a `when-let', the name of a local function of a `cl-labels',
;;    the name of a parameter of a `defun', the pattern of a `pcase-let' and the
;;    name of a variable of a `setq'.  A definition that only such a name
;;    reached was live for the runtime, and a move that stood in it was a move
;;    of the runtime.
;; 2. The walk asks Emacs now what the head of a form is.  Emacs 30 has no
;;    variable `special-forms' and no function `macro-function-p' any more:
;;    `special-form-p' says whether a head is a special form and `macrop' says
;;    whether it is a macro.  The files of the kernel are not loaded when the
;;    check runs, and a macro the kernel defines is a macro all the same, so
;;    the check reads the macros of the kernel out of the files themselves.
;; 3. The positions of the forms are declared in one table, and the table is
;;    measured and not asserted: the list of the special forms of Emacs is read
;;    out of the obarray of Emacs, every macro the kernel defines is read out of
;;    the files of the kernel, and every form the walk met in the code of the
;;    kernel is read out of the walk itself.  Every one of them stands in the
;;    table, and a head that does not stand in it is a defect of its own, which
;;    the check names by its file and its line.  A kernel that grows a macro the
;;    table does not know makes the check fail and says what it does not know.
;; 4. The probe of the positions of the walk is a check of its own, and it lies
;;    in the tree: it holds the walk to the answer of every form of the family,
;;    and the answers are written down and not computed by the walk, for a
;;    probe that computes its own expectation proves nothing.  The probe fails
;;    with the error of the defect when the defect is put back, which is the
;;    promise of wave 90 that the tree did not keep.
;;
;; The report is compared with the numbers the check measured on the kernel
;; of 2026-11-20 as well: a measurement that got smaller is a proof that got
;; weaker, and a weaker proof must not pass as if it were the same one.
;;
;; This check asks the question the claim asks.  Six things are checked.
;;
;; 1. The table is well formed: every cell is `(FROM LABEL . TO)', the states
;;    of the cell are states of the machine, the label is a symbol, and the
;;    machine makes the move of the cell.
;; 2. Every cell of the table is a move the runtime takes: the runtime takes
;;    the label of the cell in a place that lives, and the place is in the
;;    state the cell names.  The state of a place is read from the guard
;;    around it and from the moves that precede it in the same branch.  A
;;    place the runtime does not run witnesses nothing at all: a cell whose
;;    only place is dead is a move the runtime does not take.
;; 3. Every place of the runtime takes the move of the machine from the
;;    states the machine has that move from: a place whose guard names the
;;    state is in exactly those states, and a place that takes a move the
;;    machine does not have from a state its guard admits is named.
;; 4. Every place of the runtime names the move it takes: a place whose label
;;    the check cannot read is a defect of its own, because the runtime takes
;;    a move there that the check cannot name and the machine may not have.
;; 5. Every fan of the table -- a label the table gives to several states --
;;    is kept by the runtime: the runtime takes the fan from every state the
;;    table gives it to, the runtime takes it from no other state, and the
;;    fan ends the run in one state.  The fan is compared with the runtime
;;    and not with the table: a fan that the runtime narrows is a fan the
;;    runtime does not keep, and the table cannot see that.  A fan whose
;;    coverage is not fully stated is not judged: a coverage that is read in
;;    part proves nothing about the states that are missing from it, and the
;;    report says how much of it was read.
;; 6. Every state of the machine is reachable from the first one through the
;;    cells of the table, and the numbers the check measured are the numbers
;;    it measured before.
;;
;; The liveness of a place is the liveness of the *runtime*: a root is a
;; definition with the cookie of an autoload and a definition a top-level
;; form of the kernel calls.  A definition that only the tests or the scripts
;; call is dead for the runtime -- the tests run it and the runtime does not
;; -- and a move that sits in such a definition is not a move of the runtime.
;; A definition that only a *name* reaches is dead for the runtime as well:
;; the name is not a call, and the runtime does not run what nobody calls.
;; A place that stands in no definition at all is dead for the runtime too:
;; a top-level form of the kernel is not the code of a run, and the runtime
;; runs the moves of a run inside the definitions it calls and nowhere else.
;; The liveness for the tests is a property of its own, and this check does
;; not measure it.
;;
;; A place that says nothing about the state is a case of its own, and the
;; check names it.  Such a place excludes no state and witnesses the cells
;; of its label weakly: the runtime takes the label, and the machine has
;; that move only from the state of the cell.  The check counts those places,
;; counts the labels that have no place at all that names the state, and
;; names both of them by their file and their line, so that a reader sees
;; how much of the proof rests on them.  The same holds for a fan the runtime
;; does not state the states of.  A place the runtime does not run is not a
;; weak witness either: it witnesses nothing, and a cell whose only place is
;; such a place is a move the runtime does not take.
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

(defconst yeah-check--callers-of-a-value
  '(funcall apply)
  "The forms that call the function that stands in their first argument.")

(defconst yeah-check--backquote-symbols
  (list (intern "`") 'backquote)
  "The symbols that stand for a backquote in a form.
The reader of Emacs gives a backquote the symbol whose name is a backquote and
not the symbol `backquote', and the check reads the forms of the kernel with
the reader, so it has to know both of the symbols.")

(defconst yeah-check--unquote-symbols
  (list (intern ",") (intern ",@") 'unquote 'unquote-splicing)
  "The symbols that stand for an unquote in a form.
The reader of Emacs gives an unquote the symbol whose name is a comma and not
the symbol `unquote', and the check reads the forms of the kernel with the
reader, so it has to know both of the symbols.")

(defconst yeah-check--names-of-a-value
  (append '(quote function) yeah-check--backquote-symbols)
  "The heads of the forms that name a value and do not call it.")

(defconst yeah-check--derived-mode-keywords
  '(:group :syntax-table :abbrev-table :after-hook :interactive)
  "The keywords of the arguments of a `define-derived-mode'.
The walk goes into the value of such a keyword, for the form of an
`:after-hook' is run by the mode.  A name that stands in the value of a
keyword is a name and not a call.")

(defconst yeah-check--positions-of-the-known-forms
  (append
   '((and . :code)
    (atomic-change-group . :code)
    (catch . :code)
    (cl-decf . :code)
    (cl-defgeneric . :defgeneric)
    (cl-defmethod . :defmethod)
    (cl-defstruct . :slots)
    (cl-defun . :definition)
    (cl-flet . :local-functions)
    (cl-incf . :code)
    (cl-labels . :local-functions)
    (cl-loop . :code)
    (cond . :code)
    (condition-case . :handlers)
    (declare . :data)
    (declare-function . :data)
    (defconst . :variable)
    (defcustom . :variable)
    (defface . :data)
    (defgroup . :data)
    (define-derived-mode . :derived-mode)
    (define-minor-mode . :minor-mode)
    (defmacro . :definition)
    (defstruct . :slots)
    (defsubst . :definition)
    (defun . :definition)
    (defvar . :variable)
    (defvar-local . :variable)
    (destructuring-bind . :destructuring)
    (dolist . :loop)
    (dotimes . :loop)
    (easy-menu-define . :data)
    (function . :function)
    (if . :code)
    (if-let . :bindings)
    (ignore-errors . :code)
    (inline . :code)
    (interactive . :code)
    (lambda . :lambda)
    (let . :bindings)
    (let* . :bindings)
    (multiple-value-bind . :destructuring)
    (or . :code)
    (pcase . :clauses)
    (pcase-let . :pcase-bindings)
    (pcase-let* . :pcase-bindings)
    (pop . :code)
    (prog1 . :code)
    (progn . :code)
    (push . :code)
    (quote . :data)
    (save-excursion . :code)
    (save-match-data . :code)
    (save-current-buffer . :code)
    (save-restriction . :code)
    (setf . :code)
    (setq . :setq)
    (setq-local . :setq)
    (unless . :code)
    (unwind-protect . :code)
    (when . :code)
    (when-let . :bindings)
    (while . :code)
    (with-current-buffer . :code)
    (with-silent-modifications . :code)
    (with-temp-buffer . :code)
    (with-temp-file . :code)
    (*when-let . :bindings)
    (case . :clauses)
    (yeah-session-with . :code)
    (yeah-todo-with-session . :code)
    (yeah-tools-with-registry . :code))
   ;; The reader of Emacs gives a backquote the symbol whose name is a
   ;; backquote, and the reader of a macro of the kernel gives the name of
   ;; the macro.  A backquote is a macro of Emacs, and the table knows it.
   (list (cons (intern "`") :backquote)
         (cons 'backquote :backquote)))
  "The positions of the forms of the kernel that the walk of the code knows.

The car of a pair is the head of a form and the cdr is the kind of its
positions.  Every macro and every special form that the kernel uses stands in
this table, and a macro or a special form that does not stand in it is a
defect of its own: the walk cannot say which of the arguments of such a form
is code and which is a name, and the check names the form by its file and its
line instead of reading a name as a call.

The kinds are these.

  :code            -- every argument of the form is code.
  :data            -- every argument of the form is data.
  :name            -- the first argument is a name and the rest is code.
  :setq            -- the arguments are pairs of a name and a value: the names
                      are names and the values are code.
  :variable        -- the first argument is a name, the second is code, and
                      the rest of the arguments are data.
  :definition      -- the first argument is a name, the second is a list of
                      names, and the rest of the arguments are code.
  :minor-mode      -- the first argument is a name, the second is a string,
                      and the rest of the arguments are code.
  :bindings        -- the first argument is a list of bindings, and each of
                      them is a name and a value: the names are names and the
                      values are code.  The rest of the arguments are code.
  :loop            -- the first argument is the spec of a loop: a name, a
                      collection and a result.  The collection and the result
                      are code, and the rest of the arguments are code.
  :clauses         -- the first argument is code, and the rest of the
                      arguments are clauses: the first element of a clause is
                      a pattern (data) and the rest of it is code.
  :pcase-bindings  -- the first argument is a list of bindings, and each of
                      them is a pattern and a value: the patterns are data and
                      the values are code.  The rest of the arguments are code.
  :local-functions -- the first argument is a list of definitions of local
                      functions: the name of a function and its parameters
                      are names, and its body is code.  The rest of the
                      arguments are code.
  :handlers        -- the first argument is a name, the second is code, and
                      the rest of the arguments are handlers: the type of a
                      handler is data and the rest of it is code.
  :destructuring   -- the first argument is a pattern (data), the second is
                      code, and the rest of the arguments are code.
  :defmethod       -- the first argument is a name, the second is a
                      specializer (data), and the rest of the arguments are
                      code.
  :defgeneric      -- every argument of the form is data.
  :slots           -- the name of the type, the names of its options and the
                      names of its slots are names, and the values of the
                      slots are code.
  :derived-mode    -- the name of the mode, the name of its parent, the name
                      of its mode line and its doc string are data, the value
                      of a keyword is code, and the body of the mode is code.
  :function        -- the designator of a `function' is a name, and the body
                      of a `lambda' under it is code.
  :lambda          -- the parameters of a `lambda' are names, and its body is
                      code.")

(defconst yeah-check--expected-measurement
  '((:cells . 31)
    (:labels . 17)
    (:states . 11)
    (:places . 23)
    (:live-places . 23)
    (:places-without-a-definition . 0)
    (:places-of-a-dead-definition . 0)
    (:places-naming-the-state . 14)
    (:places-not-naming-the-state . 9)
    (:labels-without-a-place-that-names-the-state . 8)
    (:cells-resting-on-a-silent-place . 15)
    (:fans . 2)
    (:fans-with-a-stated-coverage . 1)
    (:fans-with-a-complete-coverage . 1))
  "The numbers the check measured on the kernel of 2026-11-20.
Every number of the report of the check is here, so that a measurement that
got smaller cannot pass as if it were the same one: a proof that rests on
less is a weaker proof, and the check says so instead of staying quiet.
A number changes when the kernel changes on purpose, and the constant is
changed then and not before.")

(defvar yeah-check--macros-of-the-kernel nil
  "The names of the macros the kernel defines.
The files of the kernel are not loaded when the check runs, and the check reads
them all the same: a macro that the kernel defines is a macro all the same,
and the walk of the code must know the positions of it.")

(defvar yeah-check--unknown-forms (make-hash-table :test #'eq)
  "The heads of the forms of the kernel whose positions the walk does not know.
A form the walk cannot read is a defect of its own, and the check names it by
its file and its line.")

(defvar yeah-check--known-forms (make-hash-table :test #'eq)
  "The heads of the macros and of the special forms that the walk met.
This is the measurement of the table of the positions: the walk met every one
of these heads in the code of the kernel, and the table of the positions knows
the positions of each of them.")

(defun yeah-check--definitions-of-the-macros ()
  "Return the definitions of the macros of the kernel, with their file and line."
  (let (definitions)
    (dolist (file (yeah-check--sources-of-the-kernel))
      (dolist (entry (yeah-check--forms-of file))
        (let ((form (plist-get entry :form)))
          (when (eq (car-safe form) 'defmacro)
            (push (list :name (cadr form)
                        :file file
                        :line (plist-get entry :line))
                  definitions)))))
    definitions))

(defun yeah-check--macros-defined-by-the-kernel ()
  "Return the names of the macros the kernel defines."
  (mapcar (lambda (definition) (plist-get definition :name))
          (yeah-check--definitions-of-the-macros)))

(defun yeah-check--macro-p (symbol)
  "Return non-nil when SYMBOL is a macro.
A macro of Emacs is a function that carries the marker of a macro, and a macro
of the kernel is a macro the kernel defines: the files of the kernel are not
loaded when the check runs, and the check reads them all the same."
  (or (and (fboundp symbol) (macrop (symbol-function symbol)))
      (memq symbol yeah-check--macros-of-the-kernel)))

(defun yeah-check--kind-of-a-head (head)
  "Return the kind of the positions of the form whose head is HEAD.
The kind is nil when HEAD is an ordinary function: every argument of such a
form is code.  The kind is :unknown when HEAD is a macro or a special form
that the table of the positions does not know."
  (and (symbolp head)
       (or (cdr (assq head yeah-check--positions-of-the-known-forms))
           (and (or (yeah-check--macro-p head) (special-form-p head))
                :unknown))))

(defun yeah-check--note-a-head (head)
  "Note the head HEAD of a form the walk met in the code of the kernel.
A head that is a macro or a special form is a position the walk must know, and
the check measures the table of the positions against the kernel: a head the
table does not know is a defect of its own."
  (when (and (symbolp head)
             (or (yeah-check--macro-p head) (special-form-p head)))
    (puthash head t yeah-check--known-forms)
    (when (eq (yeah-check--kind-of-a-head head) :unknown)
      (puthash head t yeah-check--unknown-forms))))

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

(defun yeah-check--called-value (form)
  "Return the symbol FORM calls as a value, or nil.
A value that is called is a symbol, a quoted symbol or a function designator."
  (cond ((symbolp form) form)
        ((and (consp form) (memq (car form) '(quote function))
              (consp (cdr form)) (symbolp (car (cdr form))))
         (car (cdr form)))
        (t nil)))

(defun yeah-check--calls-in-body (body table)
  "Add to TABLE the symbols the forms of BODY call.
BODY is a list of forms and each of them is walked on its own: a list of forms
is not a form, and the head of such a list is the head of its first form and
not the head of a call."
  (dolist (form body)
    (yeah-check--calls-in-1 form table))
  table)

(defun yeah-check--values-of-bindings (bindings)
  "Return the values of BINDINGS: the parts of them that are code.
A binding is a name and a value: the name is a name and the value is code."
  (let (values)
    (dolist (binding bindings)
      (when (consp binding)
        (push (cadr binding) values)))
    (nreverse values)))

(defun yeah-check--code-of-a-loop (spec)
  "Return the parts of the spec of a loop that are code.
The spec of a loop is a name, a collection and a result: the collection and the
result are code, and the name is a name."
  (if (consp spec)
      (let (parts)
        (push (cadr spec) parts)
        (when (caddr spec)
          (push (caddr spec) parts))
        (nreverse parts))
    nil))

(defun yeah-check--bodies-of-clauses (clauses)
  "Return the bodies of CLAUSES: the parts of them that are code.
The first element of a clause is a pattern, and a pattern is data."
  (let (bodies)
    (dolist (clause clauses)
      (when (consp clause)
        (dolist (form (cdr clause))
          (push form bodies))))
    (nreverse bodies)))

(defun yeah-check--bodies-of-handlers (handlers)
  "Return the bodies of HANDLERS: the parts of them that are code.
The type of a handler is data, and the rest of it is code."
  (let (bodies)
    (dolist (handler handlers)
      (when (consp handler)
        (dolist (form (cdr handler))
          (push form bodies))))
    (nreverse bodies)))

(defun yeah-check--values-of-slots (form)
  "Return the values of the slots of the `cl-defstruct' FORM.
The name of the type, the names of its options and the names of its slots are
names, and the value of a slot is code."
  (let ((tail (cdr form))
        (values))
    ;; The name of the type and the names of its options stand in the first
    ;; element of the form, and they are names.
    (when (and (consp tail) (consp (car tail)))
      (setq tail (cdr tail)))
    ;; The doc string of the type is data, and the slots stand after it.
    (when (and (consp tail) (stringp (car tail)))
      (setq tail (cdr tail)))
    (while (consp tail)
      (let ((slot (car tail)))
        (when (consp slot)
          (push (cadr slot) values)))
      (setq tail (cdr tail)))
    (nreverse values)))

(defun yeah-check--code-of-a-defmethod (form)
  "Return the parts of the `cl-defmethod' FORM that are code.
The name of the method and its specializer are data, and the body of the
method is code.  The qualifiers of a method stand between its name and its
specializer, and they are data as well."
  (let ((tail (cddr form))
        (parts))
    ;; The qualifiers of the method stand between its name and its specializer.
    (while (and (consp tail) (keywordp (car tail)))
      (setq tail (cdr tail)))
    ;; The specializer of the method is data.
    (when (consp tail)
      (setq tail (cdr tail)))
    ;; The body of the method is code.
    (dolist (form tail)
      (push form parts))
    (nreverse parts)))

(defun yeah-check--code-of-a-derived-mode (form)
  "Return the parts of the `define-derived-mode' FORM that are code.
The name of the mode, the name of its parent, the name of its mode line and its
doc string are data, the value of a keyword is code, and the body of the mode
is code."
  (let ((tail (cdddr form))
        (parts))
    ;; The name of the mode line and the doc string are strings: they are data
    ;; and not code.
    (while (and (consp tail) (stringp (car tail)))
      (setq tail (cdr tail)))
    ;; The value of a keyword is code.
    (while (and (consp tail)
                (consp (car tail))
                (memq (caar tail) yeah-check--derived-mode-keywords))
      (push (cadr (car tail)) parts)
      (setq tail (cddr tail)))
    ;; The body of the mode is code.
    (dolist (form tail)
      (push form parts))
    (nreverse parts)))

(defun yeah-check--code-of-a-function (form)
  "Return the parts of the `function' FORM that are code.
The designator of a `function' is a name, and the body of a `lambda' under it
is code."
  (let ((designator (cadr form)))
    (if (and (consp designator) (eq (car designator) 'lambda))
        (cddr designator)
      nil)))

(defun yeah-check--arguments-of (form)
  "Return the arguments of FORM as a list of parts.
A form with a dotted tail has a symbol in the place of its last argument, and
the tail is a part of the form like any other."
  (let ((parts nil)
        (tail (cdr form)))
    (while (consp tail)
      (push (car tail) parts)
      (setq tail (cdr tail)))
    (when tail
      (push tail parts))
    (nreverse parts)))

(defun yeah-check--parts-of-a-form (form)
  "Return the parts of FORM: its head and its arguments.
A form that calls a function has a head that names it, and a list of forms has a
head that is the first of them.  The walk of the head as a form does the same in
both cases: the name of a function calls nothing, and the first form of a body
is a form of the code that the runtime runs."
  (cons (car form) (yeah-check--arguments-of form)))

(defun yeah-check--local-functions-of (form)
  "Return the local functions of the `cl-labels' or of the `cl-flet' FORM.
A local function is a name, a list of parameters and a body."
  (let (definitions)
    (dolist (definition (cadr form))
      (when (consp definition)
        (push definition definitions)))
    (nreverse definitions)))

(defun yeah-check--local-function-is-called-p (definition definitions form)
  "Return non-nil when the runtime calls the local function DEFINITION.
The runtime calls it when its name stands in the code of the form: a call of
it, a call of it from a neighbouring local function, or its name as a value
that the runtime calls.  A name that stands nowhere is the name of a function
that the runtime never calls, and the body of it is not code the runtime runs."
  (let ((name (car definition)))
    (or (yeah-check--mentions name (cddr form))
        (cl-some (lambda (other)
                   (yeah-check--mentions name (cddr other)))
                 definitions))))

(defun yeah-check--bodies-of-the-called-local-functions (form)
  "Return the bodies of the local functions of FORM that the runtime calls.
A local function that nothing calls is not code the runtime runs, and the walk
does not go into its body: a tick that stands in it is no place of the runtime,
and a definition that only such a body calls is not called by the runtime.
The name of a local function that the runtime calls is a name in the code of
the form, and the walk reads it there and not here."
  (let ((definitions (yeah-check--local-functions-of form))
        (bodies nil))
    (dolist (definition definitions)
      (when (yeah-check--local-function-is-called-p definition definitions form)
        (dolist (body (cddr definition))
          (push body bodies))))
    (nreverse bodies)))

(defun yeah-check--code-parts (kind form)
  "Return the parts of FORM that are code, by the kind KIND of its positions.
Every part of the answer is code, and the parts of the form that are not in
the answer are names or data."
  (cond
   ((eq kind :code) (yeah-check--arguments-of form))
   ((eq kind :data) nil)
   ((eq kind :setq)
    (let (parts)
      (let ((tail (cdr form)))
        (while (consp tail)
          (push (cadr tail) parts)
          (setq tail (cddr tail)))
        (nreverse parts))))
   ((eq kind :variable) (list (caddr form)))
   ((eq kind :definition) (cddr (cdr form)))
   ((eq kind :minor-mode) (cddr form))
   ((eq kind :bindings)
    (append (yeah-check--values-of-bindings (cadr form)) (cddr form)))
   ((eq kind :loop)
    (append (yeah-check--code-of-a-loop (cadr form)) (cddr form)))
   ((eq kind :clauses)
    (append (list (cadr form))
            (yeah-check--bodies-of-clauses (cddr form))))
   ((eq kind :pcase-bindings)
    (append (yeah-check--values-of-bindings (cadr form))
            (cddr form)))
   ((eq kind :local-functions)
    (append (yeah-check--bodies-of-the-called-local-functions form)
            (cddr form)))
   ((eq kind :handlers)
    (append (list (caddr form))
            (yeah-check--bodies-of-handlers (cdddr form))))
   ((eq kind :destructuring)
    (append (list (caddr form)) (cdddr form)))
   ((eq kind :defmethod) (yeah-check--code-of-a-defmethod form))
   ((eq kind :defgeneric) nil)
   ((eq kind :slots) (yeah-check--values-of-slots form))
   ((eq kind :derived-mode) (yeah-check--code-of-a-derived-mode form))
   ((eq kind :function) (yeah-check--code-of-a-function form))
   ((eq kind :lambda) (cddr form))
   ;; The operands of a backquote are data, and the parts that are unquoted
   ;; in them are code: the walk of the data finds them, and the walk of the
   ;; code does not go into a backquote at all.
   ((eq kind :backquote) nil)
   (t (yeah-check--arguments-of form))))

(defun yeah-check--calls-in-data (form table)
  "Add to TABLE the symbols the unquoted parts of FORM call.
FORM is data: the runtime does not run it, and a name in it calls nothing.  The
parts that are unquoted in it are the code that the runtime runs, and the walk
goes into them."
  (cond
   ((consp form)
    (let ((head (car form)))
      (if (memq head yeah-check--unquote-symbols)
          (yeah-check--calls-in-1 (cadr form) table)
        (let ((out table) (tail form))
          (while (consp tail)
            (setq out (yeah-check--calls-in-data (car tail) out))
            (setq tail (cdr tail)))
          (when tail
            (setq out (yeah-check--calls-in-data tail out)))
          out))))
   ((vectorp form)
    (let ((out table) (index 0))
      (while (< index (length form))
        (setq out (yeah-check--calls-in-data (aref form index) out))
        (setq index (1+ index)))
      out))
   (t table)))

(defun yeah-check--calls-in-1 (form table)
  "Add to TABLE the symbols FORM calls.
A call is a symbol in the head of a form.  A function designator and a quoted
symbol are names and not calls: a name calls nothing, and a definition that
only a name reaches is dead for the runtime.  A name in the first argument of
`funcall' or of `apply' is a call, because the runtime calls the value there.

The walk goes into every subform, and not into the head of a form only: the
body of a `let' or of a `cl-letf' is a call of the runtime like any other,
and a walk that stopped at the head would lose it.  A pair with a dot is a
form too, and its tail is walked apart from its head.

The walk does not go into data (the finding F23 of the discriminator of the
waves 87 to 89).  A quoted form is a list of names and not code, and a name
in it calls nothing: the walk of the operands of a `quote' stopped, and a
definition that only a quoted list names is dead for the runtime.  A
backquoted form is data as well, and the parts that are unquoted in it are the
code that the runtime runs.  The designator of a `function' is a name and not
code as well, and the parameters of a `lambda' are names and not code either.
The body of a `lambda' is code wherever it stands, also under a `function'.

A list of names is a list of names and not code, wherever it stands: the
parameters of a `lambda', the names of the bindings of a `let', the variable
of the spec of a `dolist', the pattern of a `pcase' and the types of the
handlers of a `condition-case'.  The runtime reads the names and does not run
them, and a definition that only such a list names is dead for the runtime.
The values of the bindings, the collection of the spec, the subject of a
`pcase', the body of the clause and the body of the handler are code, and the
walk goes into them.

The description of the slots of a `cl-defstruct' is a list of names as well:
the name of the type, the names of the options and the names of the slots are
names, and the value of a slot is code.  The obsolete `defstruct' is the same
position.  The name of a derived mode and the name of its parent are names
too, and the value of a keyword of a `define-derived-mode' and the body of the
mode are code.

The walk asks Emacs what the head of a form is (the finding F27 of the
discriminator of the waves 90 to 92).  A head that is an ordinary function is a
call, and every argument of such a form is code.  A head that is a macro or a
special form is not a call in that sense: the positions of such a form are the
positions of a name and of a code, and the walk has to know them.  The table
`yeah-check--positions-of-the-known-forms' declares the positions of every
macro and every special form that the kernel uses, and a macro or a special
form that does not stand in it is a defect of its own: the walk cannot say
which of the arguments of the form is a name, and the check names the form by
its file and its line instead of reading a name as a call.

The names go into a table and not into a list: a list that the walk passes
down would lose the names that the walk adds, because the caller keeps the
head of the list and not the new cell."
  (cond
   ((consp form)
    (let ((head (car form)))
      (when (symbolp head)
        (unless (memq head yeah-check--names-of-a-value)
          (puthash head t table))
        (when (memq head yeah-check--callers-of-a-value)
          (let ((called (yeah-check--called-value (cadr form))))
            (when called
              (puthash called t table))))
        (yeah-check--note-a-head head))
      (cond
       ;; A backquoted form is data as well, and the parts that are unquoted
       ;; in it are the code that the runtime runs.
       ((memq head yeah-check--backquote-symbols)
        (yeah-check--calls-in-data (cdr form) table))
       (t
        (let ((kind (yeah-check--kind-of-a-head head)))
          (cond
           ;; An ordinary function: every argument of the form is code.
           ((null kind)
            (yeah-check--calls-in-body (yeah-check--parts-of-a-form form) table))
           ;; A macro or a special form that the table of the positions does
           ;; not know: the walk cannot say which of the arguments is code and
           ;; which is a name, and the check names the form by its file and its
           ;; line instead of reading a name as a call.
           ((eq kind :unknown)
            (yeah-check--calls-in-body (yeah-check--parts-of-a-form form) table))
           (t
            (dolist (part (yeah-check--code-parts kind form))
              (yeah-check--calls-in-1 part table)))))))))
   ((vectorp form)
    (let ((index 0))
      (while (< index (length form))
        (yeah-check--calls-in-1 (aref form index) table)
        (setq index (1+ index)))))
   (t nil))
  table)

(defun yeah-check--calls-in (form)
  "Return the symbols FORM calls, without repeats."
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
sits in such a place is not a move of the runtime.  A definition that a
top-level form only *names* is not a root either: a name calls nothing."
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

(defun yeah-check--names-the-state (form aliases)
  "Return non-nil when FORM reads the state of the run.
The accessor that reads the state names it, and so does a local variable that
holds it: `(let ((state (yeah-turn-state turn))) (eq state 'deciding))' says
the same as `(eq (yeah-turn-state turn) 'deciding)'.  ALIASES are the names
that hold the state where FORM is read."
  (or (yeah-check--mentions yeah-check--state-reader form)
      (seq-some (lambda (alias) (yeah-check--mentions alias form)) aliases)))

(defun yeah-check--other-argument (form aliases)
  "Return the argument of FORM that is not the state of the run.
The arguments of a form are `(cdr form)': the state of the run stands in one
of them, and the states it is compared with stand in another one."
  (let ((args (cdr form)))
    (cond ((and (consp args)
                (yeah-check--names-the-state (car args) aliases))
           (cadr args))
          ((and (consp (cdr args))
                (yeah-check--names-the-state (cadr args) aliases))
           (car args))
          (t nil))))

(defun yeah-check--state-set (form aliases)
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
         (yeah-check--names-the-state form aliases))
    (yeah-check--quoted-states (yeah-check--other-argument form aliases)))
   ((and (consp form) (eq (car form) 'memq)
         (yeah-check--names-the-state form aliases))
    (yeah-check--quoted-states (yeah-check--other-argument form aliases)))
   ((and (consp form) (eq (car form) 'not))
    (let ((set (yeah-check--state-set (cadr form) aliases)))
      (and set (cl-set-difference yeah-state-list set))))
   ((and (consp form) (memq (car form) '(or and)))
    (let (sets)
      (dolist (operand (cdr form))
        (let ((set (yeah-check--state-set operand aliases)))
          (when set (push set sets))))
      (when sets
        (if (eq (car form) 'or)
            (yeah-check--union sets)
          (yeah-check--intersection sets)))))
   (t nil)))

(defun yeah-check--states-of-a-guard (guard aliases)
  "Return the states GUARD admits, or nil when GUARD says nothing about them.
The tests of the guard that say nothing about the state leave the states to the
machine, and the tests that say something are intersected."
  (let (sets)
    (dolist (test guard)
      (let ((set (yeah-check--state-set test aliases)))
        (when set (push set sets))))
    (yeah-check--intersection sets)))

(defun yeah-check--destination (state label)
  "Return the state the machine moves to from STATE on LABEL, or nil."
  (and (yeah-state-p state) (yeah-loop-transition-p state label)))

(defun yeah-check--destination-of (label)
  "Return the state the machine moves to on LABEL, or nil.
The destination is nil when the label has no cell in the table and when it has
several: the machine moves to one state on every label of the table, and a
label with two destinations says nothing about the state after it."
  (let (destinations)
    (dolist (cell (yeah-check--cells))
      (when (eq (nth 1 cell) label)
        (push (nthcdr 2 cell) destinations)))
    (setq destinations (delete-dups destinations))
    (when (= 1 (length destinations))
      (car destinations))))

(defun yeah-check--destinations-of (labels)
  "Return the state the machine moves to on the labels LABELS, or nil.
The labels of a move the runtime computes are read as a set, and the state
after such a move is known when every label of the set leads to one state."
  (let (destinations)
    (dolist (label labels)
      (let ((destination (yeah-check--destination-of label)))
        (when destination
          (push destination destinations))))
    (setq destinations (delete-dups destinations))
    (when (= 1 (length destinations))
      (car destinations))))

(defun yeah-check--state-at (states before)
  "Return the states the run is in at the place, and the moves the machine does
not have.

STATES is the set of the states the guard of the place admits, or nil when the
guard says nothing about the state.  BEFORE is a list of the sets of the labels
of the moves that precede the place in its branch.  A move that the machine
does not have is returned as a defect: the runtime takes a move the machine
does not have, and the run would break at it.

The state of a place is read from the moves that precede it in the same branch.
The runtime sets the state of a run to the state the machine moves to
(`yeah-turn--tick' does it), and every label of the table leads to one state
and to one only, so the state after a move is known even where the guard
says nothing about the state.  The guard of a place says the state of the
block the place sits in, and the moves of the block come after that state: the
chain is the more precise of the two, and it is the one that names the state
of the place.  A place with no move before it in its branch is named by its
guard alone.

Every move of the chain must be a move the machine has from the state the
move before it left the run in, and a label the table does not name at all is
a move the machine does not have.

The answer is a plist and not two values: `multiple-value-bind' is not a
macro of Emacs and not a function of it, and a check that calls a name that
does not exist dies instead of answering."
  (let (broken
        (state nil)
        (previous nil))
    (dolist (labels before)
      ;; A label the table does not name is a move the machine does not have.
      (dolist (label labels)
        (when (null (yeah-check--states-of-a-label label))
          (push (list nil label) broken)))
      ;; The move must be a move the machine has from the state the move
      ;; before it left the run in.
      (when previous
        (dolist (label labels)
          (unless (yeah-check--destination previous label)
            (push (list previous label) broken))))
      ;; The state the move leaves the run in is the state the machine moves
      ;; to, and every label of the table leads to one state and to one only.
      (let ((destination (yeah-check--destinations-of labels)))
        (setq previous destination)
        (setq state (and destination (list destination)))))
    (list :states (if before (or state states) states)
          :broken broken)))

(defun yeah-check--ticks-in-body (body definition acc guard before aliases)
  "Walk BODY, a list of forms, and collect the tick calls into ACC.
GUARD is the list of the tests of the conditionals the body sits under.
BEFORE is the list of the sets of the labels of the moves that precede the
body in its branch: a tick that stands alone in the body happens before what
follows it.  ALIASES are the names that hold the state of the run where the
body is read."
  (let ((tail body) (out acc) (seen before))
    (while (consp tail)
      (let ((form (car tail)))
        (setq out (yeah-check--ticks-in form definition out guard seen aliases))
        (when (and (consp form) (eq (car form) yeah-check--tick-function))
          ;; The labels of the move are one set, and the set goes into the
          ;; list of the sets as one element: `append' would spread the
          ;; labels of the move over the list and the list would hold a
          ;; symbol where a set belongs.
          (setq seen (append seen (list (yeah-check--label-of form))))))
      (setq tail (cdr tail)))
    out))

(defun yeah-check--state-aliases (bindings aliases)
  "Return the names of BINDINGS that are bound to the state of the run.
ALIASES are the names that hold the state where BINDINGS are read: a binding
whose value is the state of the run names the state under its own name."
  (let (names)
    (dolist (binding bindings)
      (when (and (consp binding)
                 (symbolp (car binding))
                 (yeah-check--names-the-state (cadr binding) aliases))
        (push (car binding) names)))
    (nreverse names)))

(defun yeah-check--ticks-in-a-let (form definition acc guard before aliases)
  "Walk the bindings and the body of the `let' FORM.
A local variable that is bound to the state of the run names the state: the
guard around a place that reads such a variable says which state the run is
in.  The bindings of a `let' are read in the scope outside it, and the
bindings of a `let*' one after another.

The bindings of a `let' are the first element of its body, and not the whole
of it: `(cdr form)' holds the bindings *and* the forms of the body.  A walk
that took every element of it for a binding walked the body twice -- once as
a binding of the `let' and once as its body -- and the second walk lost the
guard of the body, so the place was counted twice and its state was read
from nothing.  A `let' whose first element is not a list of bindings has no
bindings at all."
  (let* ((star (eq (car form) 'let*))
         (bindings (let ((first (cdr form)))
                     (if (consp first) (car first) nil)))
         (out acc)
         (inner aliases))
    (if star
        (dolist (binding bindings)
          (when (consp binding)
            (let ((name (car binding))
                  (value (cadr binding)))
              (setq out (yeah-check--ticks-in-body
                         (list value) definition out guard before inner))
              (when (and (symbolp name)
                         (yeah-check--names-the-state value inner))
                (setq inner (cons name inner))))))
      (progn
        (setq inner (append inner (yeah-check--state-aliases bindings aliases)))
        (dolist (binding bindings)
          (when (consp binding)
            (setq out (yeah-check--ticks-in-body
                       (list (cadr binding)) definition out guard before aliases))))))
    (yeah-check--ticks-in-body (cddr form) definition out guard before inner)))

(defun yeah-check--ticks-in-data (form definition acc guard before aliases)
  "Collect the tick calls of the unquoted parts of FORM into ACC.
FORM is data: the runtime does not run it, and a tick that stands in it is no
tick of the runtime.  The parts that are unquoted in it are the code that the
runtime runs, and the walk goes into them."
  (cond
   ((consp form)
    (let ((head (car form)))
      (if (memq head yeah-check--unquote-symbols)
          (yeah-check--ticks-in (cadr form) definition acc guard before aliases)
        (let ((out acc) (tail form))
          (while (consp tail)
            (setq out (yeah-check--ticks-in-data
                       (car tail) definition out guard before aliases))
            (setq tail (cdr tail)))
          (when tail
            (setq out (yeah-check--ticks-in-data
                       tail definition out guard before aliases)))
          out))))
   ((vectorp form)
    (let ((out acc) (index 0))
      (while (< index (length form))
        (setq out (yeah-check--ticks-in-data
                   (aref form index) definition out guard before aliases))
        (setq index (1+ index)))
      out))
   (t acc)))

(defun yeah-check--ticks-in (form definition acc guard before aliases)
  "Collect the tick calls of FORM into ACC.
DEFINITION is the name of the definition FORM belongs to, or nil.  GUARD is
the list of the tests of the conditionals the call sits under; a test that
says which state the run is in is what tells the check from which state the
run takes the move.  BEFORE is the list of the sets of the labels of the
moves that precede FORM in its branch.  ALIASES are the names that hold the
state of the run where FORM is read.

A tick that stands in data is no tick of the runtime: the walk does not go into
a `quote', and the parts that are unquoted in a `backquote' are the only code
of it.  The designator of a `function' is a name and not code, and the body of
a `lambda' is code wherever it stands, also under a `function'."
  (cond
   ((and (consp form) (eq (car form) yeah-check--tick-function))
    (let ((labels (yeah-check--label-of form)))
      (push (list :definition definition
                  :call form
                  :labels labels
                  ;; A label the check cannot read names no cell of the
                  ;; table, is compared with no state, and breaks the chain
                  ;; of the moves around it.  Such a place is a defect of its
                  ;; own, and the check names it.
                  :readable (not (null labels))
                  :guard guard
                  :aliases aliases
                  :before before)
            acc))
    acc)
   ((consp form)
    (let ((head (car form)))
      (yeah-check--note-a-head head)
      (cond
       ((memq head yeah-check--backquote-symbols)
        ;; A backquoted form is data as well, and the parts that are unquoted
        ;; in it are the code that the runtime runs.
        (yeah-check--ticks-in-data (cdr form) definition acc guard before aliases))
       ((eq head 'if)
        (let* ((test (cadr form))
               (out (yeah-check--ticks-in-body (list (nth 2 form)) definition acc
                                             (append (list test) guard) before
                                             aliases)))
          (if (nth 3 form)
              (yeah-check--ticks-in-body (list (nth 3 form)) definition out
                                         (append (list (list 'not test)) guard)
                                         before aliases)
            out)))
       ((memq head '(when unless))
        (let* ((test (cadr form))
               (inner (if (eq head 'when) test (list 'not test))))
          (yeah-check--ticks-in-body (cddr form) definition acc
                                     (append (list inner) guard) before aliases)))
       ((eq head 'cond)
        (let ((out acc) (tail (cdr form)))
          (while tail
            (let ((clause (car tail)))
              (when (consp clause)
                (setq out (yeah-check--ticks-in-body
                           (cdr clause) definition out
                           (append (list (car clause)) guard) before aliases))))
            (setq tail (cdr tail)))
          out))
       ((memq head '(pcase cl-case))
        (let* ((subject (cadr form))
               (about-the-state
                (yeah-check--names-the-state subject aliases))
               (out acc) (tail (cddr form)))
          (while tail
            (let ((clause (car tail)))
              (when (consp clause)
                ;; The pattern of a clause is data and not code: it names the
                ;; branch and it runs nothing.  The pattern of a clause is its
                ;; first element and its body is the rest of it: a keyword
                ;; clause names the branch in its first element.
                (setq out (yeah-check--ticks-in-body
                           (cdr clause) definition out
                           (append (if about-the-state (list (car clause)) nil)
                                   guard) before aliases))))
            (setq tail (cdr tail)))
          out))
       ((memq head '(let let*))
        (yeah-check--ticks-in-a-let form definition acc guard before aliases))
       ((memq head '(and or))
        ;; The operands of `and' and of `or' are short-circuited: the state
        ;; after one of them is not the state before the next one.
        (let ((out acc) (tail (cdr form)))
          (while tail
            (setq out (yeah-check--ticks-in-body
                       (list (car tail)) definition out guard before aliases))
            (setq tail (cdr tail)))
          out))
       ((memq head '(dolist dotimes while))
        ;; The body of a loop runs again with the state the loop began with:
        ;; the moves in it do not precede the code after the loop.  The body
        ;; of a loop starts after its own head and its own binding: the
        ;; third element of the form, and not the fourth one.
        (yeah-check--ticks-in-body (cddr form) definition acc guard before
                                   aliases))
       (t
        ;; A form of the runtime is walked by the table of the positions.
        ;; An ordinary function is walked by its arguments, and every argument
        ;; of it is code.  A macro or a special form is walked by the
        ;; positions the table declares, and a form the table does not know is
        ;; a defect of its own: the check names it by its file and its line.
        (let ((kind (yeah-check--kind-of-a-head head)))
          (cond
           ((null kind)
            (yeah-check--ticks-in-body (yeah-check--arguments-of form) definition
                                       acc guard before aliases))
           ((eq kind :unknown)
            (yeah-check--ticks-in-body (yeah-check--arguments-of form) definition
                                       acc guard before aliases))
           (t
            ;; The parts of the form are walked one after the other, and the
            ;; places they hold are collected into the list the walk gives
            ;; back: the list is the state of the walk, and a walk that threw
            ;; it away would find no place at all.
            (let ((out acc))
              (dolist (part (yeah-check--code-parts kind form))
                (setq out (yeah-check--ticks-in part definition out guard before aliases)))
              out))))))))
   (t acc)))

(defun yeah-check--tick-lines (file)
  "Return the lines of FILE that hold a call of the tick function.
The lines are the lines of the calls in the order the calls stand in the
file, and the places of the file are in the same order."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((lines nil)
          (needle (format "(%s " yeah-check--tick-function)))
      (goto-char (point-min))
      (while (search-forward needle nil t)
        (push (line-number-at-pos (match-beginning 0)) lines))
      (nreverse lines))))

(defun yeah-check--sites-with-lines (file places)
  "Return PLACES with the file and the line of every place.
The line of a place is the line of its call in the source of FILE, and it is
nil when the number of the calls of the file and the number of its places
differ: the check does not guess a line it cannot prove."
  (let ((lines (yeah-check--tick-lines file)))
    (if (= (length lines) (length places))
        (let (out)
          (while places
            (let ((place (car places))
                  (line (car lines)))
              ;; `plist-put' takes one property at a time.
              (setq place (plist-put place :file file))
              (push (plist-put place :line line) out))
            (setq places (cdr places))
            (setq lines (cdr lines)))
          (nreverse out))
      (mapcar (lambda (place) (plist-put place :file file)) places))))

(defun yeah-check--tick-sites ()
  "Return the places of the ticks of the kernel, with the state of each.
A place is a call of `yeah-turn--tick' in the code of the kernel.  The state
of the place is the state its guard admits, moved by the moves that precede
it in its branch, and a move the machine does not have is kept beside it."
  (let (sites)
    (dolist (file (yeah-check--sources-of-the-kernel))
      (let (here)
        (dolist (entry (yeah-check--forms-of file))
          (let* ((form (plist-get entry :form))
                 (name (yeah-check--definition-name form)))
            (setq here (yeah-check--ticks-in
                        (if name (cddr form) form)
                        name here nil nil nil))))
        (setq sites (append sites (yeah-check--sites-with-lines file (nreverse here))))))
    (nreverse
     (mapcar (lambda (site)
               (let ((result
                      (yeah-check--state-at
                       (yeah-check--states-of-a-guard
                        (plist-get site :guard)
                        (plist-get site :aliases))
                       (plist-get site :before))))
                 ;; `plist-put' changes the list it is given and may give a
                 ;; new one back: the answer of the place is the list that
                 ;; the last call returned and not the list that went in.
                 (setq site (plist-put site :states (plist-get result :states)))
                 (setq site (plist-put site :broken (plist-get result :broken)))
                 site))
             sites))))

(defun yeah-check--at-of-a-place (place)
  "Return where PLACE stands: the file of the kernel and the line of the call.
A place is named by its file and its line, so that a reader of the report
sees where the proof of the table rests."
  (let ((file (plist-get place :file)))
    (if file
        (format "%s:%s"
                (file-relative-name file (yeah-check--root))
                (or (plist-get place :line) "?"))
      "?")))

(defun yeah-check--name-of-a-place (place)
  "Return the name of PLACE: the definition it sits in, the move it takes and
the line of the call in the source of the kernel."
  (list (plist-get place :definition)
        (plist-get place :labels)
        (yeah-check--at-of-a-place place)))

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

(defun yeah-check--fans-of-the-table ()
  "Return the labels the table gives to several states."
  (seq-filter (lambda (label) (> (length (yeah-check--states-of-a-label label)) 1))
              (yeah-check--labels-of-the-table)))

(defun yeah-check--live-sites (live places)
  "Return the places PLACES that sit in a definition the runtime runs.
A place that stands in no definition of the kernel is dead for the runtime
as well: a top-level form of the kernel is not the code of a run, and the
runtime runs the moves of a run inside the definitions it calls.  A tick
that stands in the body of a constant that nobody calls is a move the
runtime does not take, and it witnesses nothing."
  (seq-filter (lambda (place)
                (let ((definition (plist-get place :definition)))
                  (and definition (memq definition live))))
              places))

(defun yeah-check--places-without-a-definition (all)
  "Return the places of ALL that stand in no definition of the kernel.
A top-level form of the kernel is not a definition of a function, and a move
that stands in one is a move the runtime does not take.  The check names the
places of that kind apart, so that a reader sees how many there are."
  (seq-filter (lambda (place) (null (plist-get place :definition))) all))

(defun yeah-check--places-of-a-dead-definition (live all)
  "Return the places of ALL that stand in a definition the runtime does not run.
A definition that only a name, a test or a script reaches is dead for the
runtime, and a move that stands in it is not a move of the runtime."
  (seq-filter (lambda (place)
                (let ((definition (plist-get place :definition)))
                  (and definition (not (memq definition live)))))
              all))

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

(defun yeah-check--every-cell-is-a-move-of-the-runtime (places all)
  "Every cell of the table is a move the runtime takes.
The runtime takes the label of the cell in a place that lives, and some place
of that label stands in a state the cell names: the runtime takes the move
from the state of the cell.

PLACES are the places the runtime runs.  A place the runtime does not run
witnesses nothing: a definition that only a name reaches is dead for the
runtime, and a cell whose only place is dead is a move the runtime does not
take.  ALL are all the places of the kernel, and a cell that nobody takes is
named together with the places that take its label, so that a reader sees
where the move the runtime does not take stands.

A label the table gives to several states is a fan, and the runtime takes a
fan in several places: one place may stand in the states of one cell of the
fan and another in the states of another one.  A place of a fan that stands
in states the machine has no move of that label from is a defect of its own,
and the check names it apart.

A place that says nothing about the state excludes no state: it witnesses
the cell of its label weakly, and the check counts those places and says how
much of the proof rests on them."
  (let (broken)
    (dolist (cell (yeah-check--cells))
      (let ((from (nth 0 cell))
            (label (nth 1 cell))
            (witnessed nil)
            (weakly nil))
        ;; Every place of the label is read before the cell is judged: a place
        ;; that comes after the witness is a place of the label as well.
        (dolist (place places)
          (when (memq label (plist-get place :labels))
            (let ((states (plist-get place :states)))
              (cond ((null states) (setq weakly t))
                    ((memq from states) (setq witnessed t))))))
        (unless (or witnessed weakly)
          (push (list cell
                      :the-runtime-does-not-take-the-move
                      :the-places-that-take-the-label
                      (mapcar #'yeah-check--name-of-a-place
                              (seq-filter (lambda (place)
                                            (memq label (plist-get place :labels)))
                                          all)))
                broken))))
    ;; The verdict stands outside the walk over the cells: `dolist' answers nil
    ;; whatever its body says, and a verdict inside it would be lost.
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
move of that label from.

A label the table does not name at all is a move the machine does not have,
and the place that takes it is named whatever the state of the place is: the
runtime takes a move that the machine cannot make."
  (let (broken)
    (dolist (place places)
      (dolist (move (plist-get place :broken))
        (push (list :the-runtime-takes-a-move-the-machine-has-not
                    :place (plist-get place :definition)
                    :from (nth 0 move)
                    :label (nth 1 move))
              broken))
      (dolist (label (plist-get place :labels))
        (when (null (yeah-check--states-of-a-label label))
          (push (list :the-runtime-takes-a-move-the-machine-has-not
                      :place (plist-get place :definition)
                      :from nil
                      :label label)
                broken)))
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

(defun yeah-check--every-place-names-its-move (places)
  "Every place of the runtime names the move it takes.
The label of a place is the third argument of the call of the tick, and the
check reads it as the set of the labels the computation names.  A place whose
label the check cannot read is a defect of its own: the runtime takes a move
there that the check cannot name, and the machine may not have it at all.
Such a place witnesses no cell, is compared with no state, and breaks the
chain of the moves around it, so the check names it by its file and its line
instead of staying quiet about it."
  (let (broken)
    (dolist (place places)
      (unless (plist-get place :readable)
        (push (list :the-runtime-takes-a-move-the-check-cannot-read
                    :place (plist-get place :definition)
                    :at (yeah-check--at-of-a-place place)
                    :the-call (plist-get place :call))
              broken)))
    (yeah-check--fail
     (null broken)
     (format "the runtime takes %d move(s) the check cannot read: %S"
             (length broken) broken))))

(defun yeah-check--coverage-of-a-fan (places label)
  "Return the states the runtime takes the fan LABEL from.
The coverage is what the runtime says: the states the guards of the places of
the fan admit.  A place that says nothing about the state says nothing, and
the coverage of such a fan is not stated."
  (let (coverage)
    (dolist (place places)
      (when (memq label (plist-get place :labels))
        (dolist (state (plist-get place :states))
          (push state coverage))))
    (delete-dups coverage)))

(defun yeah-check--fan-is-fully-stated (places label)
  "Return non-nil when every place of the fan LABEL names the state of the run.
A place that says nothing about the state leaves the coverage of the fan
incomplete: the runtime may take the fan from a state the check cannot see.
The check accuses the runtime of narrowing a fan only when it has read the
whole coverage of the fan: a coverage that is read in part proves nothing
about the states that are missing from it."
  (let ((complete t))
    (dolist (place places)
      (when (memq label (plist-get place :labels))
        (unless (plist-get place :states)
          (setq complete nil))))
    complete))

(defun yeah-check--every-fan-is-kept-by-the-runtime (places)
  "Every fan of the table is kept by the runtime.
A fan is a label the table gives to several states.  The runtime takes the
fan in a place, and the state of that place says from which states the run
may be when the fan is taken.  The states the runtime takes the fan from are
the states the machine has the move from: a fan the runtime narrows is a fan
the runtime does not keep, and the fan the runtime takes from a state the
machine does not give it to is a fan the runtime keeps too wide.  The fan
ends the run in one state.

A fan whose coverage is not fully stated is not judged here: the check says
in its report how much of the coverage it read."
  (let (broken)
    (dolist (label (yeah-check--labels-of-the-table))
      (let ((states (yeah-check--states-of-a-label label)))
        (when (> (length states) 1)
          (let ((coverage (yeah-check--coverage-of-a-fan places label)))
            (when (yeah-check--fan-is-fully-stated places label)
              (unless (cl-subsetp states coverage)
                (push (list label :the-runtime-narrows-the-fan
                            (cl-set-difference states coverage))
                      broken))
              (unless (cl-subsetp coverage states)
                (push (list label :the-runtime-takes-the-fan-from-another-state
                            (cl-set-difference coverage states))
                      broken))))
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

(defun yeah-check--silent-places (places)
  "Return the places that say nothing about the state.
A place whose guard names the state proves the cell it witnesses; a place
whose guard says nothing about the state and which no move precedes in its
branch names no state at all, and the cell it witnesses rests on the machine
alone."
  (seq-filter (lambda (place) (null (plist-get place :states))) places))

(defun yeah-check--dark-labels (places)
  "Return the labels of the table that no place names the state of.
A label that no place localizes is a label the runtime does not say where it
takes: the proof for such a label rests on the machine alone."
  (let (dark)
    (dolist (label (yeah-check--labels-of-the-table))
      (let ((stated nil))
        (dolist (place places)
          (when (and (memq label (plist-get place :labels))
                     (plist-get place :states))
            (setq stated t)))
        (unless stated
          (push label dark))))
    (nreverse dark)))

(defun yeah-check--weak-cells (places)
  "Return the cells that rest on a place that says nothing about the state.
A place that names the state proves the cell it witnesses; a place that says
nothing about the state names no state, and the cell it witnesses rests on
the machine alone."
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
    (dolist (label (yeah-check--fans-of-the-table))
      (when (null (yeah-check--coverage-of-a-fan places label))
        (push label unstated)))
    (nreverse unstated)))

(defun yeah-check--measurement (live places all)
  "Return the numbers the check measured, as a plist.
PLACES are the places the runtime runs, ALL are all the places of the ticks of
the kernel, and LIVE are the definitions the runtime runs.
Every number of the report of the check is here, so that the report and the
verdict speak of the same measurement."
  (let* ((silent (yeah-check--silent-places places))
         (dark (yeah-check--dark-labels places))
         (weak (yeah-check--weak-cells places))
         (fans (yeah-check--fans-of-the-table))
         (unstated (yeah-check--unstated-fans places))
         (complete (seq-filter (lambda (label)
                                 (yeah-check--fan-is-fully-stated places label))
                               fans)))
    (list :cells (length (yeah-check--cells))
          :labels (length (yeah-check--labels-of-the-table))
          :states (length yeah-state-list)
          :places (length all)
          :live-places (length places)
          :places-without-a-definition
          (length (yeah-check--places-without-a-definition all))
          :places-of-a-dead-definition
          (length (yeah-check--places-of-a-dead-definition live all))
          :places-naming-the-state (- (length places) (length silent))
          :places-not-naming-the-state (length silent)
          :labels-without-a-place-that-names-the-state (length dark)
          :cells-resting-on-a-silent-place (length weak)
          :fans (length fans)
          :fans-with-a-stated-coverage (- (length fans) (length unstated))
          :fans-with-a-complete-coverage (length complete))))

(defun yeah-check--the-measurement-is-the-expected-one (measured)
  "Return a failure when MEASURED is not the measurement the check expects.
The numbers of the measurement are the numbers of the report, and the report
is compared with the numbers the check measured on the kernel of 2026-11-20.
A measurement that got smaller is a proof that got weaker: the check says so
instead of reporting a smaller proof as if it were the same one.  A number
changes when the kernel changes on purpose, and the constant is changed then."
  (let (broken)
    (dolist (pair yeah-check--expected-measurement)
      (let* ((name (car pair))
             (expected (cdr pair))
             (got (plist-get measured name)))
        (unless (eql expected got)
          (push (list name :expected expected :measured got) broken))))
    (yeah-check--fail
     (null broken)
     (format "the check measured the table differently than it measured it before: %S"
             broken))))

(defun yeah-check--report (live places all)
  "Say what the check measured.
PLACES are the places of the ticks the runtime runs, ALL are the places of
the ticks of the kernel, and LIVE are the definitions the runtime runs."
  (let* ((measured (yeah-check--measurement live places all))
         (silent (yeah-check--silent-places places))
         (dark (yeah-check--dark-labels places))
         (weak (yeah-check--weak-cells places))
         (unstated (yeah-check--unstated-fans places))
         (without (yeah-check--places-without-a-definition all))
         (dead (yeah-check--places-of-a-dead-definition live all)))
    (message "table: %d cell(s), %d label(s), %d state(s); %d place(s) of a tick in the kernel, %d of them live"
             (plist-get measured :cells)
             (plist-get measured :labels)
             (plist-get measured :states)
             (plist-get measured :places)
             (plist-get measured :live-places))
    (message "table: %d of the %d place(s) name the state of the run, %d do not: %S"
             (plist-get measured :places-naming-the-state)
             (plist-get measured :places)
             (plist-get measured :places-not-naming-the-state)
             (mapcar #'yeah-check--name-of-a-place silent))
    (message "table: %d of the %d label(s) of the table have no place that names the state: %S"
             (plist-get measured :labels-without-a-place-that-names-the-state)
             (plist-get measured :labels) dark)
    (message "table: %d cell(s) rest on a place that says nothing about the state: %S"
             (plist-get measured :cells-resting-on-a-silent-place) weak)
    (message "table: %d of the %d fan(s) of the table has a stated coverage, %d of them a complete one, %d does not: %S"
             (plist-get measured :fans-with-a-stated-coverage)
             (plist-get measured :fans)
             (plist-get measured :fans-with-a-complete-coverage)
             (length unstated)
             unstated)
    (message "table: %d place(s) of a tick stand outside a definition of the kernel: %S"
             (length without)
             (mapcar #'yeah-check--name-of-a-place without))
    (message "table: %d place(s) of a tick stand in a definition the runtime does not run: %S"
             (length dead)
             (mapcar #'yeah-check--name-of-a-place dead))))

(defun yeah-check--a-delimiter-p (char)
  "Return non-nil when CHAR ends a name.
A name in the head of a form ends at a delimiter, and a `(' that a longer name
follows is not the head of a form."
  (or (null char)
      (memq char '(?\s ?\t ?\n ?\r ?\f ?\( ?\) ?\' ?\` ?\, ?\; ?\" ?\[ ?\]))))

(defun yeah-check--lines-of-a-head (file head)
  "Return the lines of FILE where a form with the head HEAD stands.
A form with the head HEAD is a list whose first element is HEAD, and the line
is the line where the list stands.  A `(' that stands in a string or in a
comment is not a form, and the check does not name it.

The file is read once, from its beginning to its end, and the walk of the text
does not go back: a walk that went back would read the file again and again,
and a check of a kernel of forty files would take minutes instead of seconds."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((lines nil)
          (pos (point-min))
          (needle (concat "(" (symbol-name head))))
      (while (progn (goto-char pos)
                    (search-forward needle nil t))
        (let ((start (match-beginning 0))
              (end (match-end 0))
              (state (syntax-ppss (match-beginning 0))))
          ;; The name of the head ends where the match ends, and the form
          ;; stands in code and not in a string or in a comment.
          (when (and (yeah-check--a-delimiter-p (char-after end))
                     (not (nth 3 state))
                     (not (nth 4 state)))
            (push (line-number-at-pos start) lines))
          (setq pos (1+ start))))
      (nreverse lines))))

(defun yeah-check--places-of-an-unknown-form (head)
  "Return the places of the kernel where a form with the head HEAD stands.
A place is the file of the kernel and the line of the form, and the check
names a form whose positions it does not know by its file and its line."
  (let (places)
    (dolist (file (yeah-check--sources-of-the-kernel))
      (dolist (line (yeah-check--lines-of-a-head file head))
        (push (list :head head
                    :at (format "%s:%s"
                                (file-relative-name file (yeah-check--root))
                                line))
              places)))
    places))

(defun yeah-check--special-forms-of-emacs ()
  "Return the special forms of Emacs.
Emacs 30 has no variable `special-forms' any more: the list of the special
forms is the list `special-form-p' answers for, and the check reads that list
out of the obarray of Emacs instead of writing it down.  A list that the check
wrote down would be the list of the special forms of the day it wrote it, and
a special form that Emacs added after that would not be in it, and the table of
the positions would not know it."
  (let (forms)
    (mapatoms (lambda (symbol)
                (when (special-form-p symbol)
                  (push symbol forms))))
    (sort forms #'string<)))

(defun yeah-check--every-special-form-of-emacs-is-known ()
  "Every special form of Emacs stands in the table of the positions.
Emacs 30 has no variable `special-forms' any more: the list of the special
forms is the list `special-form-p' answers for, and the check reads that list
out of the obarray of Emacs instead of writing it down.  A list that the check
wrote down would be the list of the special forms of the day it wrote it, and
a special form that Emacs added after that would not be in it, and the table of
the positions would not know it."
  (let (broken)
    (dolist (name (yeah-check--special-forms-of-emacs))
      (unless (assq name yeah-check--positions-of-the-known-forms)
        (push (list name :the-table-does-not-know-this-special-form) broken)))
    (yeah-check--fail
     (null broken)
     (format "the table of the positions does not know %d special form(s) of Emacs: %S"
             (length broken) broken))))

(defun yeah-check--every-macro-of-the-kernel-is-known ()
  "Every macro the kernel defines stands in the table of the positions.
A macro the kernel defines and the table does not know is a defect of its own:
the walk cannot say which of the arguments of a call of it is a name, and the
check names the macro by the file and the line where the kernel defines it."
  (let (broken)
    (dolist (entry (yeah-check--definitions-of-the-macros))
      (unless (assq (plist-get entry :name) yeah-check--positions-of-the-known-forms)
        (push (list :the-table-does-not-know-this-macro
                    :macro (plist-get entry :name)
                    :at (format "%s:%s"
                                (file-relative-name (plist-get entry :file)
                                                    (yeah-check--root))
                                (plist-get entry :line)))
              broken)))
    (yeah-check--fail
     (null broken)
     (format "the table of the positions does not know %d macro(s) of the kernel: %S"
             (length broken) broken))))

(defun yeah-check--every-form-the-walk-met-is-known ()
  "Every macro and every special form the walk met stands in the table.
This is the measurement of the table of the positions: the walk of the code met
every one of these heads in the code of the kernel, and a head the table does
not know is a defect of its own, which the check names by its file and its
line."
  (let (broken)
    (maphash
     (lambda (head _value)
       (unless (assq head yeah-check--positions-of-the-known-forms)
         (push (list :the-walk-met-a-form-the-table-does-not-know
                     :head head
                     :at (mapcar (lambda (place) (plist-get place :at))
                                 (yeah-check--places-of-an-unknown-form head)))
               broken)))
     yeah-check--known-forms)
    (yeah-check--fail
     (null broken)
     (format "the walk met %d form(s) whose positions the table does not know: %S"
             (length broken) broken))))

(defun yeah-check--report-the-table-of-the-positions ()
  "Say how many forms the walk met and how many of them the table knows."
  (message "table: the walk met %d macro(s) and special form(s) in the kernel, and the table of the positions knows %d of them"
           (hash-table-count yeah-check--known-forms)
           (- (hash-table-count yeah-check--known-forms)
              (hash-table-count yeah-check--unknown-forms))))

(defmacro yeah-check--probe-macro (&rest body)
  "A macro that the table of the positions does not know.
The probe needs a macro that the table does not know, so that it can hold the
walk to naming a form whose positions it does not know."
  (cons 'progn body))

(defconst yeah-check--probe-cases
  '(((quote probe-dead) nil)
    ((function probe-dead) nil)
    ((function (lambda (probe-dead) (probe-live))) (probe-live))
    ((defvar probe-dead (probe-live)) (defvar probe-live))
    ((define-minor-mode probe-dead "the doc string" (probe-live))
     (define-minor-mode probe-live))
    ((lambda (probe-dead) (probe-live)) (lambda probe-live))
    ((let ((probe-dead 1)) (probe-live)) (let probe-live))
    ((let* ((probe-dead 1)) (probe-live)) (let* probe-live))
    ((when-let ((probe-dead 1)) (probe-live)) (when-let probe-live))
    ((if-let ((probe-dead 1)) (probe-live)) (if-let probe-live))
    ((*when-let ((probe-dead 1)) (probe-live)) (*when-let probe-live))
    ((dolist (probe-dead (probe-live)) (probe-live2)) (dolist probe-live probe-live2))
    ((dotimes (probe-dead (probe-live)) (probe-live2)) (dotimes probe-live probe-live2))
    ((pcase probe-live ((probe-dead) (probe-live2))) (pcase probe-live2))
    ((case probe-live (probe-dead (probe-live2))) (case probe-live2))
    ((pcase-let ((probe-dead (probe-live))) (probe-live2))
     (pcase-let probe-live probe-live2))
    ((pcase-let* ((probe-dead (probe-live))) (probe-live2))
     (pcase-let* probe-live probe-live2))
    ((cl-flet ((probe-dead (a) (probe-live))) (probe-live2))
     (cl-flet probe-live2))
    ((cl-labels ((probe-dead (a) (probe-live))) nil) (cl-labels))
    ((cl-labels ((probe-dead (a) (probe-live))) (probe-dead))
     (cl-labels probe-dead probe-live))
    ((cl-labels ((probe-dead (a) (probe-live))) (probe-live2))
     (cl-labels probe-live2))
    ((condition-case probe-dead (probe-live) (error (probe-live2)))
     (condition-case probe-live probe-live2))
    ((destructuring-bind (probe-dead) (probe-live) (probe-live2))
     (destructuring-bind probe-live probe-live2))
    ((multiple-value-bind (probe-dead) (probe-live) (probe-live2))
     (multiple-value-bind probe-live probe-live2))
    ((cl-defmethod probe-dead ((probe-dead2)) (probe-live)) (cl-defmethod probe-live))
    ((cl-defgeneric probe-dead (probe-dead2) "the doc string") (cl-defgeneric))
    ((cl-defstruct (probe-dead (:constructor probe-live))
                   (probe-slot (probe-live2)))
     (cl-defstruct probe-live2))
    ((defstruct (probe-dead) (probe-slot (probe-live))) (defstruct probe-live))
    ((define-derived-mode probe-dead parent "the doc string"
       :group 'probe-group
       (probe-live))
     (define-derived-mode probe-live))
    ((defun probe-dead (probe-dead2) (probe-live)) (defun probe-live))
    ((defmacro probe-dead (probe-dead2) (probe-live)) (defmacro probe-live))
    ((setq probe-dead (probe-live)) (setq probe-live))
    ((setq-local probe-dead (probe-live)) (setq-local probe-live))
    ((declare (indent 1)) (declare))
    ((with-temp-buffer (probe-live)) (with-temp-buffer probe-live))
    ((inline (probe-live)) (inline probe-live))
    ((and (probe-live) (probe-live2)) (and probe-live probe-live2))
    ((if (probe-live) (probe-live2) (probe-live)) (if probe-live probe-live2))
    ((when (probe-live) (probe-live2)) (when probe-live probe-live2))
    ((unless (probe-live) (probe-live2)) (unless probe-live probe-live2))
    ((cond ((probe-live) (probe-live2))) (cond probe-live probe-live2))
    ((while (probe-live) (probe-live2)) (while probe-live probe-live2))
    ((progn (probe-live)) (progn probe-live))
    ((funcall 'probe-dead) (funcall probe-dead))
    ((yeah-session-with (probe-live) (probe-live2))
     (yeah-session-with probe-live probe-live2))
    ((yeah-tools-with-registry (probe-live) (probe-live2))
     (yeah-tools-with-registry probe-live probe-live2))
    ((yeah-todo-with-session (probe-live) (probe-live2))
     (yeah-todo-with-session probe-live probe-live2))
    ((`(probe-live ,(probe-live2))) (probe-live2)))
  "The forms the probe of the positions of the walk holds the walk to.
Every form of the list stands a name in the position of a name, and the walk
must not call it: `probe-dead' is a name in every one of them, and the walk
calls nothing but the names of the forms that are code.  The second element of
a pair is the answer the walk has to give, and it is written down here and not
computed by the walk: a probe that computes its own expectation proves
nothing.

The answer is a set of names and not a list: the walk collects the names in a
table, and the order of a table is not the order of the code.  A name that the
walk finds in a position of a name is a defect, and the probe names it.")

(defconst yeah-check--probe-tick-cases
  '(((let ((probe-dead 1)) (yeah-turn--tick probe-turn 'probe-label)) . 1)
    ((when-let ((probe-dead 1)) (yeah-turn--tick probe-turn 'probe-label)) . 1)
    ((quote (yeah-turn--tick probe-turn 'probe-label)) . 0)
    ((cl-defmethod probe-dead ((probe-dead2))
                  (yeah-turn--tick probe-turn 'probe-label)) . 1)
    ((pcase-let ((probe-dead (yeah-turn--tick probe-turn 'probe-label)))
       (probe-live)) . 1)
    ((defun probe-dead (probe-dead2)
          (yeah-turn--tick probe-turn 'probe-label)) . 1)
    ((cl-labels ((witness () (yeah-turn--tick probe-turn 'probe-label))) nil) . 0)
    ((cl-labels ((witness () (yeah-turn--tick probe-turn 'probe-label)))
       (witness)) . 1)
    ((cl-labels ((witness () (other))
                 (other () (yeah-turn--tick probe-turn 'probe-label)))
       (witness)) . 1)
    ((cl-labels ((witness () (yeah-turn--tick probe-turn 'probe-label)))
       (funcall 'witness)) . 1))
  "The forms the probe of the places of the walk holds the walk to.
Every form of the list stands a tick in the code of it, and the number on the
right is the number of the places of the runtime the walk has to find in it.
A tick in the body of a local function that the runtime calls is a place, and a
tick in the body of a local function that nobody calls is no place at all: the
runtime does not run the body of a function it never calls.")

(defun yeah-check--sorted-names (names)
  "Return NAMES as a sorted list of the names in it, without the nils.
The sort is destructive, and the names of the probe stand in a constant: the
sort gets a copy of the list and not the list itself."
  (sort (copy-sequence (delq nil names)) #'string<))

(defun yeah-check--the-probe-passes ()
  "The probe of the positions of the walk passes.
The probe is a real check and not a comment: it feeds the walk the positions of
the family and it holds the walk to the answer of each of them.  A defect that
is put back -- a name in the position of a name read as a call, or a form whose
positions the walk does not know -- makes the probe fail with the error of the
defect."
  (let (failures
        (yeah-check--unknown-forms (make-hash-table :test #'eq))
        (yeah-check--known-forms (make-hash-table :test #'eq)))
    ;; The walk of the calls: a name in the position of a name calls nothing.
    (dolist (entry yeah-check--probe-cases)
      (let* ((form (car entry))
             (expected (car (cdr entry)))
             (got (yeah-check--calls-in form)))
        (unless (equal (yeah-check--sorted-names got)
                       (yeah-check--sorted-names expected))
          (push (list :the-probe-of-the-positions-failed
                      :form form
                      :expected expected
                      :measured got)
                failures))))
    ;; The walk of the places: a tick in the code of a form is a place of the
    ;; runtime, and a tick in a name is no place at all.
    (dolist (entry yeah-check--probe-tick-cases)
      (let* ((form (car entry))
             (expected (cdr entry))
             (places (yeah-check--ticks-in form 'probe-definition nil nil nil nil)))
        (unless (= expected (length places))
          (push (list :the-probe-of-the-places-failed
                      :form form
                      :expected expected
                      :measured (length places))
                failures))))
    ;; A form whose positions the walk does not know is a defect of its own,
    ;; and the walk has to name it.
    ;; The form is quoted and not expanded: the probe macro is a macro the
    ;; table does not know, and the walk has to meet it as a form of the code.
    (yeah-check--calls-in '(yeah-check--probe-macro (probe-live)))
    (unless (gethash 'yeah-check--probe-macro yeah-check--unknown-forms)
      (push (list :the-probe-did-not-name-the-form-the-walk-does-not-know
                  :head 'yeah-check--probe-macro)
            failures))
    (yeah-check--fail
     (null failures)
     (format "the probe of the positions of the walk failed: %S" failures))))

(defun yeah-check--verdict ()
  "Return the failures of the check, or nil when the check passes.
An error of the check is a failure of the check and not the death of the
process: a check that dies has not bitten."
  (condition-case err
      (let* ((yeah-check--macros-of-the-kernel
              (yeah-check--macros-defined-by-the-kernel))
             (definitions (yeah-check--definitions-of-the-kernel))
             (live (yeah-check--live-definitions definitions))
             (all (yeah-check--tick-sites))
             (places (yeah-check--live-sites live all))
             (measured (yeah-check--measurement live places all))
             (failures (delq nil
                             (list (yeah-check--the-table-is-well-formed)
                                   (yeah-check--every-cell-is-a-move-of-the-runtime
                                    places all)
                                   (yeah-check--every-place-takes-the-move-the-machine-has
                                    places)
                                   (yeah-check--every-place-names-its-move
                                    places)
                                   (yeah-check--every-fan-is-kept-by-the-runtime
                                    places)
                                   (yeah-check--every-state-of-the-machine-is-reachable)
                                   (yeah-check--the-measurement-is-the-expected-one
                                    measured)
                                   ;; The table of the positions of the forms is
                                   ;; measured against the kernel and not
                                   ;; asserted: a macro of the kernel that the
                                   ;; table does not know is a defect of its
                                   ;; own, and a form the walk met in the code
                                   ;; and the table does not know is a defect
                                   ;; of its own.
                                   (yeah-check--every-special-form-of-emacs-is-known)
                                   (yeah-check--every-macro-of-the-kernel-is-known)
                                   (yeah-check--every-form-the-walk-met-is-known)
                                   ;; The probe of the positions of the walk is
                                   ;; a check of its own: it holds the walk to
                                   ;; the answer of every form of the family,
                                   ;; and it fails with the error of the defect
                                   ;; when the defect is put back.
                                   (yeah-check--the-probe-passes)))))
        (unless failures
          (yeah-check--report live places all)
          (yeah-check--report-the-table-of-the-positions))
        failures)
    (error
     (list (format "the check could not read the kernel: %s"
                    (error-message-string err))))))

(let ((failures (yeah-check--verdict)))
  (dolist (failure failures)
    (message "table: %s" failure))
  (kill-emacs (if failures 1 0)))

;;; check-every-transition-of-the-table-is-taken.el ends here
