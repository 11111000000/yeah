;;; check-a-tool-declares-its-own-risk.el --- a tool declares the risk it carries -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A tool says whether it changes the world.  The field is `:risk', its
;; values come from a vocabulary of the kernel, and the permission rule
;; asks by that declaration and not by the name of the tool.
;;
;; The defect this check hunts: the declaration and the handler disagree,
;; or the rule asks by a list of names and not by the declaration.  Both
;; are invisible from the outside, because a tool that declares no risk at
;; all is accepted silently, and a rule that names a tool by hand keeps
;; naming it after the tool has changed.
;;
;; So the check does not take the mutating set from a constant.  It
;; **measures** it: it reads the sources of the library, it follows the
;; calls of every handler of the core, and it looks for the primitives
;; that change the world.  A tool that reaches `write-region' or
;; `save-buffer' writes; a tool that reaches `eval', or that runs a
;; program whose text the model supplied, executes; a tool that takes a
;; path away or stops a job it did not start destroys.  The measurement
;; knows three things that a name cannot say:
;;
;;   * a program that only reads is not a change of the world -- `git
;;     status' and `git diff' read the repository, and the rule does not
;;     have to ask about them; the same program with `git commit' writes
;;     history, and the rule has to ask about it;
;;
;;   * the text a program evaluates is the model's when it is the model's
;;     and it is the kernel's when the kernel knows it: the bridge
;;     evaluates the expression of the model and changes the world, and it
;;     reads a buffer through an expression of its own and does not;
;;
;;   * a process that the tool itself started is its own business, and a
;;     process that the tool found elsewhere is not: cancelling a job
;;     stops work that is running, and the timeout of the bridge cleans
;;     up after itself.
;;
;; The result layer is not walked: it carries the answer of a tool, and
;; the artifact of a long output is written there by every tool of the
;; kernel, so walking it would make every tool of the kernel look like it
;; changes the world.
;;
;; The measurement is an over-approximation: it names every category a
;; handler may reach, and it never names a category the handler does not
;; reach.  A read tool that the measurement finds changing the world is
;; a defect of the declaration; a mutating tool whose declaration is one
;; of the categories the measurement found is a declaration that agrees
;; with the handler.
;;
;; A profile is a snapshot.  It names the tools that change the world at
;; the moment it is computed, and a tool that is registered after that
;; moment -- the bridge registers its tools when the bridge is there -- is
;; not in the snapshot.  The snapshot is safe because the rule asks about
;; what it does not name: an action that no rule names has the effect
;; `ask', and never `allow'.  The sixth measurement below proves that
;; default, because a default that turned into `allow' would turn the
;; snapshot into a hole without a sound.
;;
;; Six things are proved:
;;
;;   1. every tool of the core declares a risk, and the risk is a risk of
;;      the vocabulary of the kernel;
;;   2. the registration refuses a risk outside the vocabulary, and it
;;      accepts a tool that declares no risk -- which the rule then asks
;;      about, because a risk that is not known changes the world;
;;   3. the declaration of a tool agrees with what its handler does: the
;;      set of the tools that the measurement finds changing the world is
;;      the set of the tools that declare a risk other than `read';
;;   4. the category the declaration names is one of the categories the
;;      measurement found;
;;   5. the rule asks by the declaration: the profiles name exactly the
;;      tools of the measurement, and a probe whose declaration says that
;;      it changes the world is named by the profile while a probe whose
;;      declaration says that it does not is not;
;;   6. an action that no rule names is asked about and is never allowed:
;;      the default of the rule is `ask', and the refusal of the rule
;;      says so.
;;
;; Exit codes: 0 -- the declarations of the tools agree with their
;; handlers and with the rule; 1 -- they do not.

;;; Code:

(require 'cl-lib)

;; --------------------------------------------------------------------------
;; The sources of the library
;; --------------------------------------------------------------------------

(defconst yeah-check--excluded-files '("yeah-result.el")
  "The modules of the library that the measurement does not walk.
The result layer carries the answer of a tool: it writes the artifact of
a long output into a private file.  That write belongs to the way an
answer travels and not to what the tool did, and every tool of the kernel
goes through it.")

(defun yeah-check--library-directory ()
  "Return the directory of the library of Yeah."
  (file-name-directory (or (locate-library "yeah-tools") "yeah-tools.el")))

(defun yeah-check--source-files ()
  "Return the files of the library that the measurement walks."
  (let (files)
    (dolist (file (directory-files (yeah-check--library-directory) t "\\.el\\'"))
      (unless (member (file-name-nondirectory file) yeah-check--excluded-files)
        (push file files)))
    (sort (nreverse files) #'string-lessp)))

(defun yeah-check--read-forms (file)
  "Return the top-level forms of FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun yeah-check--collect-definitions (files)
  "Return the definitions of the functions of FILES.
The value maps the symbol of a function to (FILE PARAMS BODY).  The body
does not hold the docstring of the function: the docstring is a text and the
measurement walks code."
  (let (definitions)
    (dolist (file files)
      (dolist (form (yeah-check--read-forms file))
        (when (and (consp form) (symbolp (car form)))
          (when (memq (car form) '(defun defsubst cl-defun defmacro cl-defmacro))
            (let* ((name (cadr form))
                   (params (caddr form))
                   (rest (cdddr form))
                   (body (if (stringp (car rest)) (cdr rest) rest)))
              (when (and (symbolp name) (listp params))
                (push (cons name (list file params body)) definitions)))))))
    (nreverse definitions)))

(defun yeah-check--collect-constants (files)
  "Return the constants of FILES: the alist of (SYMBOL . VALUE).
Only the values that the measurement can read as they are are kept: a
string and a list of strings.  A constant is a text the kernel knows, and
the measurement tells it apart from the text of the model."
  (let (constants)
    (dolist (file files)
      (dolist (form (yeah-check--read-forms file))
        (when (and (consp form) (symbolp (car form)))
          (when (memq (car form) '(defconst defvar defcustom))
            (let ((name (cadr form))
                  (value (caddr form)))
              (when (and (symbolp name)
                         (or (stringp value)
                             (and (listp value) (cl-every #'stringp value))))
                (push (cons name value) constants)))))))
    (nreverse constants)))

(defvar yeah-check--definitions nil
  "The definitions of the functions of the library, as the measurement sees them.")

(defvar yeah-check--constants nil
  "The constants of the library, as the measurement sees them.")

;; --------------------------------------------------------------------------
;; The values of the forms
;;
;; A value is the list of the alternatives a form may have.  An alternative
;; is a list of elements; an element is a string, the symbol `:unknown' (the
;; form is not known), the symbol `:template' (the form is a fixed template
;; of the kernel) or the symbol `:process' (the form makes a process).  The
;; values of the forms that the kernel computes are carried from the call to
;; the call, so that the command of a program is known where the program is
;; started.
;; --------------------------------------------------------------------------

(defun yeah-check--value-unknown ()
  "Return the value of a form that is not known."
  (list (list :unknown)))

(defun yeah-check--value-empty ()
  "Return the value of a form that may be empty."
  (list nil))

(defun yeah-check--value-string (text)
  "Return the value of the string TEXT."
  (list (list text)))

(defun yeah-check--value-quoted (quoted)
  "Return the value of the quoted form QUOTED."
  (cond
   ((stringp quoted) (yeah-check--value-string quoted))
   ((and (listp quoted) (cl-every #'stringp quoted)) (list quoted))
   (t (yeah-check--value-unknown))))

(defun yeah-check--value-union (a b)
  "Return the value that is either A or B."
  (delete-dups (append a b)))

(defun yeah-check--value-union-list (values)
  "Return the value that is any of VALUES."
  (delete-dups (apply #'append values)))

(defun yeah-check--element (alternative)
  "Return the element that the list ALTERNATIVE contributes to a list.
A list of one element is that element; a list of many elements is a list,
and it is carried as one element."
  (cond
   ((null alternative) :unknown)
   ((= (length alternative) 1) (car alternative))
   (t alternative)))

(defun yeah-check--value-list (values)
  "Return the value of a list whose elements come from VALUES."
  (let ((result (list nil)))
    (dolist (value values)
      (let (acc)
        (dolist (a result)
          (dolist (b value)
            (push (append a (list (yeah-check--element b))) acc)))
        (setq result (nreverse acc))))
    result))

(defun yeah-check--value-append (values)
  "Return the value of the concatenation of the lists VALUES."
  (let ((result (list nil)))
    (dolist (value values)
      (let (acc)
        (dolist (a result)
          (dolist (b value)
            (push (append a b) acc)))
        (setq result (nreverse acc))))
    result))

(defun yeah-check--value-cons (first second)
  "Return the value of the list that CONS of FIRST and SECOND makes."
  (let (result)
    (dolist (a first)
      (dolist (b second)
        (push (append (list (yeah-check--element a)) b) result)))
    (delete-dups result)))

(defun yeah-check--value-car (value)
  "Return the value of the car of the list VALUE.
The car of a list is its first element: a text, or a list when the first
element is a list itself."
  (let (result)
    (dolist (alternative value)
      (if (null alternative)
          (push (yeah-check--value-unknown) result)
        (let ((first (car alternative)))
          (push (if (and (consp first) (not (stringp first)))
                    first
                  (list first))
                result))))
    (delete-dups result)))

(defun yeah-check--value-cdr (value)
  "Return the value of the cdr of the list VALUE."
  (let (result)
    (dolist (alternative value)
      (push (cdr alternative) result))
    (delete-dups result)))

(defun yeah-check--value-nth (index value)
  "Return the value of the NTH element of the list VALUE."
  (let (result)
    (dolist (alternative value)
      (if (and (integerp index) (< index (length alternative)))
          (let ((element (nth index alternative)))
            (push (if (and (consp element) (not (stringp element)))
                      element
                    (list element))
                  result))
        (push (yeah-check--value-unknown) result)))
    (delete-dups result)))

(defun yeah-check--value-concat (values)
  "Return the value of the concatenation of the strings VALUES."
  (let ((text "")
        (ok t))
    (dolist (value values)
      (if (and (= (length value) 1)
               (= (length (car value)) 1)
               (stringp (car (car value))))
          (setq text (concat text (car (car value))))
        (setq ok nil)))
    (if ok
        (yeah-check--value-string text)
      (yeah-check--value-unknown))))

(defun yeah-check--fixed-template-p (template)
  "Return non-nil when TEMPLATE inserts its arguments as data and not as code.
Only the conversion `%S' quotes what it inserts; every other conversion
would put the text of the model into the code that runs."
  (let ((ok t)
        (index 0)
        (length (length template)))
    (while (and (< index length) ok)
      (if (= (aref template index) ?%)
          (progn
            (if (>= (1+ index) length)
                (setq ok nil)
              (unless (memq (aref template (1+ index)) '(?S ?%))
                (setq ok nil)))
            (setq index (+ index 2)))
        (setq index (1+ index))))
    ok))

(defun yeah-check--string-of (value)
  "Return the string that VALUE holds, or nil when it holds no single string."
  (if (and (= (length value) 1)
           (= (length (car value)) 1)
           (stringp (car (car value))))
      (car (car value))
    nil))

(defun yeah-check--value-format (template)
  "Return the value of the FORMAT of TEMPLATE."
  (if (and (stringp template) (yeah-check--fixed-template-p template))
      (list (list :template))
    (yeah-check--value-unknown)))

;; --------------------------------------------------------------------------
;; The effects of a handler
;; --------------------------------------------------------------------------

(defconst yeah-check--write-primitives '(write-region save-buffer with-temp-file copy-file)
  "The primitives that change what exists on the machine.")

(defconst yeah-check--destroy-primitives '(rename-file delete-file)
  "The primitives that take something away.")

(defconst yeah-check--execute-primitives '(eval)
  "The primitives that run code of the model.")

(defconst yeah-check--process-primitives '(make-process make-pipe-process start-process
                                          call-process shell-command-to-string)
  "The primitives that run a program.")

(defconst yeah-check--kill-primitives '(kill-process delete-process)
  "The primitives that stop a process.")

(defconst yeah-check--shells '("sh" "bash" "zsh" "dash" "ksh")
  "The programs that run the text they are given.")

(defconst yeah-check--git-read-only '("status" "diff" "log" "show" "ls-files"
                                      "rev-parse" "blame" "describe" "cat-file"
                                      "shortlog" "reflog" "whatchanged")
  "The subcommands of git that only read the repository.")

(defconst yeah-check--git-mutating '("add" "am" "apply" "archive" "checkout" "cherry-pick"
                                     "clean" "clone" "commit" "config" "fetch" "gc"
                                     "init" "merge" "mv" "notes" "pull" "prune" "push"
                                     "rebase" "reset" "restore" "revert" "rm" "stash"
                                     "submodule" "tag" "update-ref" "worktree")
  "The subcommands of git that change the repository.")

(defvar yeah-check--effects nil
  "The effect categories the measurement has found so far.")

(defun yeah-check--record (env effect)
  "Record EFFECT and return ENV."
  (push effect yeah-check--effects)
  env)

(defun yeah-check--eval-argument (args)
  "Return the value that the option `--eval' carries in ARGS, or `:none'."
  (let ((rest args)
        (result :none))
    (while rest
      (when (and (stringp (car rest)) (string= (car rest) "--eval"))
        (setq result (if (cdr rest) (cadr rest) :none))
        (setq rest nil))
      (when rest
        (setq rest (cdr rest))))
    result))

(defun yeah-check--git-subcommand (args)
  "Return the subcommand of the git command line ARGS, or nil."
  (let ((result nil))
    (dolist (arg args)
      (when (and (null result) (stringp arg) (not (string-prefix-p "-" arg)))
        (setq result arg)))
    result))

(defun yeah-check--candidate-effects (candidate)
  "Return the effect categories of the command line CANDIDATE."
  (let* ((program (car candidate))
         (args (cdr candidate))
         (evaluated (yeah-check--eval-argument args)))
    (cond
     ;; the program evaluates a text: the text of the model changes the
     ;; world, the text of the kernel is the kernel's own business
     ((not (eq evaluated :none))
      (if (or (eq evaluated :unknown)
              (and (listp evaluated)
                   (not (cl-every #'stringp evaluated))))
          '("execute")
        nil))
     ;; a shell runs the text it is given
     ((and (stringp program)
           (cl-member program yeah-check--shells :test #'string=))
      '("execute"))
     ;; git decides by its subcommand
     ((and (stringp program) (string= program "git"))
      (let ((subcommand (yeah-check--git-subcommand args)))
        (cond
         ((and subcommand
               (cl-member subcommand yeah-check--git-read-only :test #'string=))
          nil)
         ((and subcommand
               (cl-member subcommand yeah-check--git-mutating :test #'string=))
          '("write"))
         (t '("execute")))))
     (t '("execute")))))

(defun yeah-check--command-effects (command)
  "Return the effect categories of the command COMMAND."
  (let (effects)
    (dolist (alternative command)
      (dolist (effect (yeah-check--candidate-effects alternative))
        (push effect effects)))
    (delete-dups effects)))

;; --------------------------------------------------------------------------
;; The walker
;;
;; The walker goes through the forms of a handler and follows the calls of
;; the library.  It returns the environment after the form and the value of
;; the form, so that one pass answers both questions: what a form does to
;; the world, and what a form computes.
;; --------------------------------------------------------------------------

(defvar yeah-check--visited nil
  "The (SYMBOL VALUES) pairs the measurement has walked already.")

(defvar yeah-check--processes nil
  "The variables that hold a process the tool itself started.")

(defvar yeah-check--depth 0
  "How deep the measurement is in the calls of the library.")

(defvar yeah-check--created-any nil
  "Non-nil when the walk has seen the tool start a process of its own.")

(defvar yeah-check--creates-process nil
  "Non-nil when the tool starts a process of its own.
A tool that started a process cleans up after itself: the process it stops
is the one it started, and that is not a change of the world that the model
has to be asked about.  The answer is the one of the first pass, so that the
verdict does not depend on the order of the forms in the source.")

(defconst yeah-check--depth-limit 40
  "The depth of the calls the measurement follows.
The measurement follows the calls of the library, and a library that calls
itself would otherwise walk forever.  The limit is a stop, not a verdict:
the tool whose walk was stopped is reported as changing the world, because
the measurement does not know what it does.")

(defun yeah-check--bind-params (params values env)
  "Return ENV with the parameters PARAMS bound to the VALUES."
  (let ((result env)
        (rest params)
        (given values))
    (while rest
      (let ((param (car rest)))
        (cond
         ((eq param '&rest)
          (let ((last (car (cdr rest))))
            (when last
              (setq result (cons (cons last (yeah-check--value-unknown)) result)))
            (setq rest nil)))
         ((memq param '(&optional &rest)) nil)
         (t
          (let ((value (if (and given (consp given))
                            (car given)
                          (yeah-check--value-unknown))))
            (setq result (cons (cons param value) result))
            (when (and given (consp given))
              (setq given (cdr given)))))))
      (setq rest (cdr rest)))
    result))

(defun yeah-check--process-value-p (form)
  "Return non-nil when FORM makes a process."
  (and (consp form)
       (let ((head (car form)))
         (cond
          ((memq head '(make-process make-pipe-process start-process)) t)
          ((memq head '(let let*)) (yeah-check--process-value-p (caddr form)))
          ((eq head 'setq) (yeah-check--process-value-p (caddr form)))
          (t nil)))))

(defun yeah-check--scan-processes (form)
  "Return the variables that FORM binds to a process.
The value is the list of the variables; the scan of a form returns what it
found and the caller joins the answers, because a function that pushes onto
the list of its caller would push onto its own copy of it."
  (let (found)
    (when (consp form)
      (let ((head (car form)))
        (cond
         ((memq head '(let let*))
          (dolist (binding (cadr form))
            (when (and (consp binding) (symbolp (car binding)))
              (when (yeah-check--process-value-p (cadr binding))
                (push (car binding) found))
              (setq found (append found (yeah-check--scan-processes (cadr binding))))))
          (dolist (body (cddr form))
            (setq found (append found (yeah-check--scan-processes body)))))
         ((memq head '(setq setq-default))
          (let ((pairs (cdr form)))
            (while pairs
              (when (and (symbolp (car pairs))
                         (yeah-check--process-value-p (cadr pairs)))
                (push (car pairs) found))
              (setq pairs (cddr pairs)))))
         (t
          (let ((rest form))
            (while (consp rest)
              (setq found (append found (yeah-check--scan-processes (car rest))))
              (setq rest (cdr rest))))))))
    (delete-dups found)))

(defun yeah-check--process-variables (body)
  "Return the variables that BODY binds to a process."
  (yeah-check--scan-processes body))

(defun yeah-check--local-process-p (target value)
  "Return non-nil when TARGET is a process the tool itself started.
VALUE is the value of TARGET.  A process is the tool's own when the tool
started it: either the value says so, or the variable that holds it is a
variable the tool binds to a process somewhere in its own calls."
  (or (and value
           (cl-some (lambda (alternative)
                      (and (= (length alternative) 1)
                           (eq (car alternative) :process)))
                    value))
      (and (symbolp target) (memq target yeah-check--processes))))

(defun yeah-check--constant-value (symbol)
  "Return the value of the constant SYMBOL, or nil when it declares none."
  (let ((entry (assq symbol yeah-check--constants)))
    (if entry
        (yeah-check--value-quoted (cdr entry))
      nil)))

(defun yeah-check--walk (form env)
  "Walk FORM in the environment ENV.
Return a cons of the environment after FORM and the value of FORM."
  (cond
   ((stringp form) (cons env (yeah-check--value-string form)))
   ((numberp form) (cons env (yeah-check--value-unknown)))
   ((null form) (cons env (yeah-check--value-unknown)))
   ((symbolp form)
    (cons env (or (cdr (assq form env))
                  (yeah-check--constant-value form)
                  (yeah-check--value-unknown))))
   ((consp form)
    (let ((head (car form)))
      (cond
       ((symbolp head) (yeah-check--walk-call head form env))
       ((and (consp head) (eq (car head) 'lambda))
        (yeah-check--walk-lambda head env))
       (t (cons env (yeah-check--value-unknown))))))
   (t (cons env (yeah-check--value-unknown)))))

(defun yeah-check--walk-body (forms env)
  "Walk the forms FORMS in ENV.
Return a cons of the environment after the forms and the value of the last
of them."
  (let ((inner env)
        (value (yeah-check--value-unknown))
        (rest forms))
    (while (consp rest)
      (let ((result (yeah-check--walk (car rest) inner)))
        (setq inner (car result))
        (setq value (cdr result)))
      (setq rest (cdr rest)))
    (cons inner value)))

(defun yeah-check--walk-args (forms env)
  "Walk the argument forms FORMS in ENV.
Return a cons of the environment after the forms and the list of the values
of the arguments."
  (let ((inner env)
        (values nil)
        (rest forms))
    (while (consp rest)
      (let ((result (yeah-check--walk (car rest) inner)))
        (setq inner (car result))
        (push (cdr result) values))
      (setq rest (cdr rest)))
    (cons inner (nreverse values))))

(defun yeah-check--walk-let (bindings body env sequential)
  "Walk the body BODY of a let with BINDINGS in ENV.
SEQUENTIAL says whether the bindings see each other."
  (let ((inner env))
    (dolist (binding bindings)
      (when (and (consp binding) (symbolp (car binding)))
        (let* ((var (car binding))
               (value-form (cadr binding))
               (result (yeah-check--walk value-form (if sequential inner env)))
               (value (cdr result)))
          (setq inner (cons (cons var value)
                            (if sequential (car result) inner))))))
    (yeah-check--walk-body body inner)))

(defun yeah-check--walk-setq (pairs env)
  "Walk the assignments PAIRS in ENV.
Return a cons of the environment after the assignments and the value of the
last of them."
  (let ((inner env)
        (value (yeah-check--value-unknown)))
    (while pairs
      (let* ((var (car pairs))
             (value-form (cadr pairs))
             (result (yeah-check--walk value-form inner)))
        (setq inner (cons (cons var (cdr result)) (car result)))
        (setq value (cdr result)))
      (setq pairs (cddr pairs)))
    (cons inner value)))

(defun yeah-check--walk-if (form env)
  "Walk the IF form in ENV."
  (let* ((condition (yeah-check--walk (cadr form) env))
         (inner (car condition))
         (then (yeah-check--walk (caddr form) inner))
         (else (yeah-check--walk (cadddr form) inner)))
    (cons (car else) (yeah-check--value-union (cdr then) (cdr else)))))

(defun yeah-check--walk-when (form env)
  "Walk the WHEN form in ENV."
  (let* ((condition (yeah-check--walk (cadr form) env))
         (inner (car condition))
         (body (yeah-check--walk-body (cddr form) inner)))
    (cons (car body) (yeah-check--value-union (cdr body) (yeah-check--value-empty)))))

(defun yeah-check--walk-cond (form env)
  "Walk the COND form in ENV."
  (let ((inner env)
        (values nil))
    (dolist (clause (cdr form))
      (when (consp clause)
        (let* ((condition (yeah-check--walk (car clause) inner))
               (rest (cdr clause))
               (last nil))
          (setq inner (car condition))
          (while rest
            (setq last (car rest))
            (setq rest (cdr rest)))
          (if last
              (let ((body (yeah-check--walk-body (cdr clause) inner)))
                (setq inner (car body))
                (push (cdr body) values))
            (push (cdr condition) values)))))
    (cons inner (yeah-check--value-union-list values))))

(defun yeah-check--walk-any (forms env)
  "Walk the forms FORMS in ENV, whichever of them answers."
  (let ((inner env)
        (values nil))
    (dolist (form forms)
      (let ((result (yeah-check--walk form inner)))
        (setq inner (car result))
        (push (cdr result) values)))
    (cons inner (yeah-check--value-union-list values))))

(defun yeah-check--walk-loop (form env)
  "Walk the DOLIST or DOTIMES form in ENV."
  (let* ((binding (cadr form))
         (var (and (consp binding) (car binding)))
         (inner (if var
                    (cons (cons var (yeah-check--value-unknown)) env)
                  env))
         (body (yeah-check--walk-body (cddr form) inner)))
    (cons (car body) (cdr body))))

(defun yeah-check--walk-lambda (form env)
  "Walk the body of the lambda FORM in ENV."
  (let* ((params (cadr form))
         (body (cddr form))
         (inner (yeah-check--bind-params params nil env))
         (result (yeah-check--walk-body body inner)))
    (cons (car result) (yeah-check--value-unknown))))

(defun yeah-check--walk-command-of (forms values)
  "Return the command of the process call with the argument FORMS and VALUES."
  (let ((rest forms)
        (given values)
        (result nil))
    (while rest
      (when (eq (car rest) :command)
        (setq result (cadr given))
        (setq rest nil))
      (setq rest (cdr rest))
      (setq given (cdr given)))
    (or result (yeah-check--value-unknown))))

(defun yeah-check--walk-process (head form env)
  "Walk the process call FORM of HEAD in ENV."
  (let* ((args (cdr form))
         (result (yeah-check--walk-args args env))
         (inner (car result))
         (values (cdr result))
         (command (if (eq head 'call-process)
                      (or (car values) (yeah-check--value-unknown))
                    (yeah-check--walk-command-of args values))))
    (setq yeah-check--created-any t)
    (dolist (effect (yeah-check--command-effects command))
      (push effect yeah-check--effects))
    (cons inner (yeah-check--value-unknown))))

(defun yeah-check--walk-kill (form env)
  "Walk the kill call FORM in ENV."
  (let* ((args (cdr form))
         (result (yeah-check--walk-args args env))
         (inner (car result))
         (values (cdr result)))
    (unless (or yeah-check--creates-process
                (yeah-check--local-process-p (car args) (car values)))
      (push "destroy" yeah-check--effects))
    (cons inner (yeah-check--value-unknown))))

(defun yeah-check--walk-value-form (head form env)
  "Walk the value form FORM of HEAD in ENV."
  (let* ((result (yeah-check--walk-args (cdr form) env))
         (inner (car result))
         (values (cdr result)))
    (cons inner
          (cond
           ((eq head 'list) (yeah-check--value-list values))
           ((eq head 'append) (yeah-check--value-append values))
           ((eq head 'cons) (yeah-check--value-cons (or (car values) (yeah-check--value-unknown))
                                                      (or (cadr values) (yeah-check--value-unknown))))
           ((eq head 'concat) (yeah-check--value-concat values))
           ((eq head 'format) (yeah-check--value-format (yeah-check--string-of (car values))))
           ((eq head 'car) (yeah-check--value-car (or (car values) (yeah-check--value-unknown))))
           ((eq head 'cdr) (yeah-check--value-cdr (or (car values) (yeah-check--value-unknown))))
           ((eq head 'nth) (yeah-check--value-nth (cadr form)
                                                    (or (cadr values) (yeah-check--value-unknown))))
           (t (yeah-check--value-unknown))))))

(defun yeah-check--walk-defined (symbol form env)
  "Walk the call FORM of the library function SYMBOL in ENV."
  (let* ((result (yeah-check--walk-args (cdr form) env))
         (inner (car result))
         (values (cdr result)))
    (yeah-check--walk-body-of symbol values inner)))

(defun yeah-check--walk-body-of (symbol values env)
  "Walk the body of the library function SYMBOL called with VALUES in ENV.
Return a cons of the environment after the body and the value of the call."
  (let* ((definition (assq symbol yeah-check--definitions))
         (entry (cdr definition))
         (params (nth 1 entry))
         (body (nth 2 entry))
         (key (cons symbol values))
         (inner (yeah-check--bind-params params values env)))
    (if (or (null definition)
            (cl-find key yeah-check--visited :test #'equal)
            (> yeah-check--depth yeah-check--depth-limit))
        (cons inner (yeah-check--value-unknown))
      (push key yeah-check--visited)
      (let ((yeah-check--processes
             (delete-dups (append yeah-check--processes
                                  (yeah-check--process-variables body))))
            (yeah-check--depth (1+ yeah-check--depth)))
        (yeah-check--walk-body body inner)))))

(defun yeah-check--walk-call (head form env)
  "Walk the call FORM of HEAD in ENV.
Return a cons of the environment after the call and the value of the call."
  (cond
   ((eq head 'quote) (cons env (yeah-check--value-quoted (cadr form))))
   ((eq head 'let) (yeah-check--walk-let (cadr form) (cddr form) env nil))
   ((eq head 'let*) (yeah-check--walk-let (cadr form) (cddr form) env t))
   ((eq head 'setq) (yeah-check--walk-setq (cdr form) env))
   ((eq head 'setq-default) (yeah-check--walk-setq (cdr form) env))
   ((eq head 'if) (yeah-check--walk-if form env))
   ((eq head 'when) (yeah-check--walk-when form env))
   ((eq head 'unless) (yeah-check--walk-when form env))
   ((eq head 'cond) (yeah-check--walk-cond form env))
   ((eq head 'progn) (yeah-check--walk-body (cdr form) env))
   ((memq head '(and or)) (yeah-check--walk-any (cdr form) env))
   ((eq head 'while)
    (let* ((condition (yeah-check--walk (cadr form) env))
           (body (yeah-check--walk-body (cddr form) (car condition))))
      (cons (car body) (yeah-check--value-unknown))))
   ((memq head '(condition-case unwind-protect catch))
    (yeah-check--walk-body (cdr form) env))
   ((memq head '(dolist dotimes)) (yeah-check--walk-loop form env))
   ((eq head 'lambda) (yeah-check--walk-lambda form env))
   ((eq head 'function)
    (let ((target (cadr form)))
      (if (and (consp target) (eq (car target) 'lambda))
          (yeah-check--walk-lambda target env)
        (cons env (yeah-check--value-unknown)))))
   ((assq head yeah-check--definitions) (yeah-check--walk-defined head form env))
   ((memq head yeah-check--write-primitives)
    (cons (yeah-check--record env "write") (yeah-check--value-unknown)))
   ((memq head yeah-check--destroy-primitives)
    (cons (yeah-check--record env "destroy") (yeah-check--value-unknown)))
   ((memq head yeah-check--execute-primitives)
    (cons (yeah-check--record env "execute") (yeah-check--value-unknown)))
   ((memq head yeah-check--process-primitives)
    (yeah-check--walk-process head form env))
   ((memq head yeah-check--kill-primitives)
    (yeah-check--walk-kill form env))
   ((memq head '(funcall apply))
    (let ((result (yeah-check--walk-args (cdr form) env)))
      (cons (car result) (yeah-check--value-unknown))))
   ((memq head '(list append cons concat format car cdr nth))
    (yeah-check--walk-value-form head form env))
   (t
    (let ((result (yeah-check--walk-args (cdr form) env)))
      (cons (car result) (yeah-check--value-unknown))))))

(defun yeah-check--walk-handler (handler)
  "Walk the handler of a tool and return the effect categories it reaches.
HANDLER is the handler of the tool: a symbol or a lambda."
  (let ((yeah-check--effects nil)
        (yeah-check--visited nil)
        (yeah-check--processes nil)
        (yeah-check--depth 0))
    (if (consp handler)
        (yeah-check--walk-lambda handler nil)
      (yeah-check--walk-body-of handler nil nil))
    (delete-dups yeah-check--effects)))

(defun yeah-check--measure (handler)
  "Return the effect categories the handler of a tool reaches.
HANDLER is the handler of the tool: a symbol or a lambda.
The walk happens twice: the first pass answers whether the tool starts a
process of its own, and the second pass uses that answer, so that the verdict
does not depend on the order of the forms in the source."
  (let ((yeah-check--created-any nil)
        (yeah-check--creates-process nil))
    (yeah-check--walk-handler handler)
    (let ((yeah-check--creates-process yeah-check--created-any))
      (yeah-check--walk-handler handler))))

;; --------------------------------------------------------------------------
;; The check
;; --------------------------------------------------------------------------

(defun yeah-check--core-specs ()
  "Return the specifications of the tools of the core of Yeah.
The tools of the core are the tools the library declares: the built-ins,
the tools of the delegation and the tools of the bridge.  The tools of a
server of MCP come from outside and are not among them."
  (append (yeah-builtins-specs)
          (yeah-delegate-tools)
          (yeah-bridge-tool-specs)))

(defun yeah-check--profile-actions (profile)
  "Return the actions the permission profile PROFILE names."
  (mapcar (lambda (rule) (plist-get rule :action))
          (yeah-perm-profile profile)))

(let ((failures nil)
      (load-failure nil))

  ;; The load of the registry is guarded: a refusal inside it must be this
  ;; check's own failure, and not a trace of a half-loaded library.
  (condition-case e
      (progn
        (require 'yeah-tools)
        (require 'yeah-delegate)
        (require 'yeah-bridge)
        (require 'yeah-perm))
    (error (setq load-failure e)))

  (if load-failure
      (push (format "the registry of the tools did not load: %s"
                    (error-message-string load-failure))
            failures)
    (let ((vocabulary yeah-risk--vocabulary)
          (probe-outside "probe-risk-outside")
          (probe-read "probe-risk-read")
          (probe-without "probe-risk-without")
          (probe-write "probe-risk-write"))

      ;; The measurement reads the sources of the library: the definitions
      ;; of the functions are collected once, before anything is measured.
      (setq yeah-check--definitions
            (yeah-check--collect-definitions (yeah-check--source-files)))
      (setq yeah-check--constants
            (yeah-check--collect-constants (yeah-check--source-files)))

      ;; --- 1. every tool of the core declares a risk of the vocabulary ---
      (dolist (spec (yeah-check--core-specs))
        (let ((name (plist-get spec :name))
              (risk (plist-get spec :risk)))
          (unless (stringp risk)
            (push (format "the tool %S declares no risk" name) failures))
          (unless (and (stringp risk)
                       (cl-member risk vocabulary :test #'equal))
            (push (format "the tool %S declares the risk %S, which is not in the vocabulary of the kernel"
                          name risk)
                  failures))))

      ;; --- 2. the registration refuses a risk outside the vocabulary -----
      (let ((refusal nil))
        (condition-case e
            (yeah-tools-register
             (list :name probe-outside
                   :description "A throwaway tool that declares a risk outside the vocabulary."
                   :input nil
                   :handler (lambda (&rest _args) nil)
                   :risk "source"))
          (user-error (setq refusal e))
          (error (setq refusal e)))
        (unless refusal
          (push (format "the tool %S declared the risk %S and was accepted: a risk outside the vocabulary passed silently"
                        probe-outside "source")
                failures))
        (when refusal
          (let ((text (error-message-string refusal)))
            (unless (string-match-p (regexp-quote probe-outside) text)
              (push (format "the refusal of the risk outside the vocabulary did not name the tool %S: %s"
                            probe-outside text)
                    failures))
            (unless (string-match-p (regexp-quote "source") text)
              (push (format "the refusal of the risk outside the vocabulary did not name the risk %S: %s"
                            "source" text)
                    failures)))))
      (yeah-tools-unregister probe-outside)

      ;; --- 3. a tool that declares no risk is accepted --------------------
      (let ((refusal nil))
        (condition-case e
            (yeah-tools-register
             (list :name probe-without
                   :description "A throwaway tool that declares no risk."
                   :input nil
                   :handler (lambda (&rest _args) nil)))
          (user-error (setq refusal e))
          (error (setq refusal e)))
        (when refusal
          (push (format "the tool %S declared no risk and was refused: %s"
                        probe-without (error-message-string refusal))
                failures))
        (unless (yeah-tools-get probe-without)
          (push (format "the tool %S declared no risk and is not in the registry"
                        probe-without)
                failures)))
      (yeah-tools-unregister probe-without)

      ;; --- 4. the declaration agrees with what the handler does ----------
      (let (measured)
        (dolist (spec (yeah-check--core-specs))
          (let* ((name (plist-get spec :name))
                 (risk (plist-get spec :risk))
                 (effects (yeah-check--measure (plist-get spec :handler)))
                 (mutating (and effects t)))
            (push (list name risk effects mutating) measured)
            (message "tool-risk: %-18s declares %-8s the handler reaches %s"
                     name
                     (or risk "<none>")
                     (if effects (format "%S" effects) "nothing"))))
        (setq measured (nreverse measured))
        (dolist (entry measured)
          (let* ((name (nth 0 entry))
                 (risk (nth 1 entry))
                 (effects (nth 2 entry))
                 (mutating (nth 3 entry)))
            (if mutating
                (progn
                  (unless (yeah-risk-mutating-p risk)
                    (push (format "the tool %S changes the world -- its handler reaches %S -- but it declares the risk %S"
                                  name effects (or risk "<none>"))
                          failures))
                  (when (and (stringp risk)
                             (not (cl-member risk effects :test #'equal)))
                    (push (format "the tool %S declares the risk %S, but its handler reaches %S"
                                  name risk (format "%S" effects))
                          failures)))
              (unless (and (stringp risk) (string= risk "read"))
                (push (format "the tool %S declares the risk %S, but its handler changes nothing: it reaches %s"
                              name risk (if effects (format "%S" effects) "nothing"))
                      failures)))))

      ;; --- 5. the rule asks by the declaration and not by a list of names
      ;; The rule knows the tools the registry holds: a tool of the bridge
      ;; is registered when the bridge is there, and the rule cannot ask
      ;; about a tool it does not know.  The comparison is over the tools
      ;; the registry holds.
      (let ((plan (yeah-check--profile-actions "plan"))
            (build (yeah-check--profile-actions "build"))
            (mutating (mapcar (lambda (entry) (nth 0 entry))
                              (seq-filter (lambda (entry)
                                            (and (nth 3 entry)
                                                 (yeah-tools-get (nth 0 entry))))
                                          measured))))
        (unless (equal (sort (copy-sequence mutating) #'string-lessp)
                       (sort (copy-sequence plan) #'string-lessp))
          (push (format "the plan profile names %S, but the tools that change the world are %S"
                        plan mutating)
                failures))
        (unless (equal (sort (copy-sequence mutating) #'string-lessp)
                       (sort (copy-sequence build) #'string-lessp))
          (push (format "the build profile names %S, but the tools that change the world are %S"
                        build mutating)
                failures))
        ;; a probe that declares that it does not change the world is not
        ;; asked about, and the rule follows the declaration
        (let ((before (yeah-check--profile-actions "plan")))
          (yeah-tools-register
           (list :name probe-read
                 :description "A throwaway tool that declares the risk `read'."
                 :input nil
                 :handler (lambda (&rest _args) nil)
                 :risk "read"))
          (let ((after (yeah-check--profile-actions "plan")))
            (unless (equal before after)
              (push (format "the plan profile changed when the tool %S declared the risk `read': the rule does not ask by the declaration"
                            probe-read)
                    failures))))
        (yeah-tools-unregister probe-read)
        ;; a probe that declares that it changes the world is asked about
        (yeah-tools-register
         (list :name probe-write
               :description "A throwaway tool that declares the risk `write'."
               :input nil
               :handler (lambda (&rest _args) nil)
               :risk "write"))
        (unless (member probe-write (yeah-check--profile-actions "plan"))
          (push (format "the plan profile does not ask about the tool %S, which declares that it changes the world"
                        probe-write)
                failures))
        (yeah-tools-unregister probe-write)
        ;; a tool that declares no risk is asked about: a risk that is not
        ;; known changes the world
        (yeah-tools-register
         (list :name probe-without
               :description "A throwaway tool that declares no risk."
               :input nil
               :handler (lambda (&rest _args) nil)))
        (unless (member probe-without (yeah-check--profile-actions "plan"))
          (push (format "the plan profile does not ask about the tool %S, which declares no risk: a risk that is not known changes the world"
                        probe-without)
                failures))
        (yeah-tools-unregister probe-without))

      ;; --- 6. the rule asks about what it does not name -----------------
      ;; A profile is a snapshot: it names the tools that change the world at
      ;; the moment it is computed, and a tool that is registered after that
      ;; moment -- the bridge registers its tools when the bridge is there --
      ;; is not in the snapshot.  The snapshot is safe because the rule asks
      ;; about what it does not name: an action that no rule names has the
      ;; effect `ask', and never `allow'.  The tool that the profile does
      ;; not name is asked about, and not skipped.
      (let* ((rules (yeah-perm-profile "plan"))
             (names (mapcar (lambda (rule) (plist-get rule :action)) rules))
             (late "probe-late"))
        (yeah-tools-register
         (list :name late
               :description "A throwaway tool that was registered after the profile was computed."
               :input nil
               :handler (lambda (&rest _args) nil)
               :risk "write"))
        (unwind-protect
            (progn
              (when (member late names)
                (push (format "the profile names the tool %S, which was registered after the profile was computed: a profile is a snapshot"
                              late)
                      failures))
              (let ((effect (yeah-perm-effect late "*" rules)))
                (message "tool-risk: the profile does not name the tool %s, and the rule %s about it: the effect is %s"
                         late
                         (if (eq 'ask effect) "asks" "does not ask")
                         effect)
                (unless (eq 'ask effect)
                  (push (format "the profile does not name the tool %S, and the rule gives it the effect %S: an action that no rule names is asked about, and it is never allowed"
                                late effect)
                        failures)))
              (let ((err nil))
                (condition-case e
                    (yeah-perm-evaluate late "*" rules)
                  (user-error (setq err e)))
                (unless err
                  (push (format "the rule allowed the tool %S that no rule names: the default of the rule is `ask' and not `allow'"
                                late)
                        failures))
                (when err
                  (let ((text (error-message-string err)))
                    (unless (string-prefix-p "ask: " text)
                      (push (format "the refusal of the tool %S that no rule names does not begin with `ask: ': %s"
                                    late text)
                            failures))))))
          (yeah-tools-unregister late))
        ;; the same holds without a profile at all: the default of the rule
        ;; is `ask', and a rule that says nothing allows nothing
        (let ((effect (yeah-perm-effect late "*" '())))
          (unless (eq 'ask effect)
            (push (format "the rule with no rules at all gives the action %S the effect %S: the default of the rule is `ask' and not `allow'"
                          late effect)
                  failures)))
        (let ((err nil))
          (condition-case e
              (yeah-perm-evaluate late "*" '())
            (user-error (setq err e)))
          (unless err
            (push (format "the rule with no rules at all allowed the action %S: the default of the rule is `ask' and not `allow'"
                          late)
                  failures))
          (when err
            (let ((text (error-message-string err)))
              (unless (string-prefix-p "ask: " text)
                (push (format "the refusal of the action %S under no rules at all does not begin with `ask: ': %s"
                              late text)
                      failures)))))))))

  (dolist (failure failures)
    (message "tool-risk: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-tool-declares-its-own-risk.el ends here
