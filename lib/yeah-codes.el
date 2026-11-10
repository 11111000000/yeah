;;; yeah-codes.el --- experimental programmatic tool calling -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; This module is an EXPERIMENTAL restricted evaluator for programmatic tool
;; calling.  It is disabled by default and is not wired into the agent loop.
;; Its whitelist reduces the operations a form can express, but it is not a
;; security sandbox: Emacs Lisp `eval' still runs in the user's process.
;; Untrusted model code requires a separately designed process boundary.

;;; Code:

(require 'cl-lib)
(require 'yeah-tools)
(require 'yeah-perm)

(defgroup yeah-codes nil
  "Experimental Yeah programmatic tool calling."
  :group 'yeah)

(defcustom yeah-codes-enable-ptc nil
  "Enable the experimental PTC evaluator when non-nil.
This is not a security boundary and must not be enabled for untrusted model
code.  The default nil makes `yeah-codes-eval' refuse every request before
reading or evaluating any form."
  :type 'boolean
  :group 'yeah-codes)

(defvar yeah-codes--whitelist
  '("read" "edit" "grep" "glob" "bash" "webfetch" "text" "image" "console" "exit")
  "List of allowed PTC form names, in canonical order.
These names are metadata for the experimental evaluator, not capabilities
granted to untrusted code.  Mutate the list with `yeah-codes-allow' and
`yeah-codes-disallow'.")

(defun yeah-codes-whitelist ()
  "Return the allowed PTC form names in their canonical order.
Mutate the underlying list through `yeah-codes-allow' and
`yeah-codes-disallow', not by modifying the returned list."
  (declare (pure t) (side-effect-free t))
  yeah-codes--whitelist)

(defun yeah-codes--whitelist-member (name)
  "Non-nil if NAME (a string) is in `yeah-codes--whitelist'."
  (member name yeah-codes--whitelist))

(defun yeah-codes--string-p-or-error (name)
  "Signal `user-error' unless NAME is a non-empty string.
Return NAME when valid."
  (unless (stringp name)
    (signal 'user-error
            (list (format "yeah-codes: NAME must be a string, got %S"
                          (type-of name)))))
  (when (= (length name) 0)
    (signal 'user-error
            (list "yeah-codes: NAME must be a non-empty string")))
  name)

(defun yeah-codes-allow (name)
  "Add NAME to the PTC whitelist. Return the new whitelist.

Duplicates are silently absorbed; the whitelist is not
reordered. NAME must be a non-empty string; any other shape
raises `user-error'."
  (yeah-codes--string-p-or-error name)
  (unless (yeah-codes--whitelist-member name)
    (setq yeah-codes--whitelist
          (append yeah-codes--whitelist (list name))))
  yeah-codes--whitelist)

(defun yeah-codes-disallow (name)
  "Remove NAME from the PTC whitelist. Return the new whitelist.

No-op if NAME is absent. NAME must be a string; any other
shape raises `user-error'."
  (yeah-codes--string-p-or-error name)
  (setq yeah-codes--whitelist
        (cl-remove name yeah-codes--whitelist :test 'string=))
  yeah-codes--whitelist)

(defun yeah-codes--plist-name (form)
  "Return the `:name' string of FORM, or `user-error' if missing/wrong."
  (let ((name (plist-get form :name)))
    (unless (stringp name)
      (signal 'user-error
              (list (format "yeah-codes-eval: each form needs :name string, got %S"
                            form))))
    name))

(defun yeah-codes--read-form (code)
  "Parse CODE (a string) as a single body form. Raise `user-error'.

The body is wrapped in parens before `read' so that the
parser sees a list. Read errors of any flavour
(`scan-error', `end-of-file', `invalid-read-syntax',
`wrong-type-argument') are mapped to a single
`user-error' signal so nothing leaks past the boundary."
  (condition-case err
      (car (read (concat "(" code ")")))
    ((scan-error end-of-file invalid-read-syntax wrong-type-argument)
     (signal 'user-error
             (list (format "yeah-codes-eval: malformed form: %S (%S)"
                           code err))))))

(defun yeah-codes--json-roundtrip (value)
  "Return `read'/`prin1' round-trip of VALUE.

The result is `equal' to VALUE for every JSON-clean value:
atoms, lists, strings, numbers, and the standard t/nil.  The round trip
normalizes data returned by the evaluator; it is not an isolation boundary."
  (read (prin1-to-string value)))

(defun yeah-codes--input-binding (cell)
  "Return the (SYMBOL VALUE) binding cell for one INPUTS cell.

INPUTS cell has shape `(KEY . ANY)'. KEY is a string or
symbol; the result uses a symbol. VALUE is `prin1'/`read'
round-tripped so the boundary is JSON-clean. The result is
a two-element **list** `(NAME VALUE)', not a dotted pair; a
`let' binding list requires proper lists, not dotted pairs."
  (let* ((key (car cell))
         (sym (if (symbolp key) key
                (intern key)))
         (val (cdr cell)))
    (list sym (yeah-codes--json-roundtrip val))))


(defconst yeah-codes--core
  '(car cdr caar cadr cddr cdar cons list append length nth elt
    progn let let* if cond when unless and or not
    = < > <= >= + - * / % mod 1+ 1- max min abs
    princ prin1-to-string format message error
    string= string< string> string-join concat substring number-to-string
    list-length reverse copy-sequence append
    quote function tool)
  "Names the experimental evaluator may call directly.
Higher-order functions such as `mapcar' and `sort' are deliberately absent:
they would accept a quoted arbitrary function symbol and escape the call
whitelist.  Their absence closes a demonstrated bypass, but does not prove
that `eval' is a security boundary.

Tools are reached through ONE function and not by name: in Emacs Lisp a
`let' does not shadow the cell of a function, so a form that called `read'
directly would call the built-in `read' and not the tool of the registry.
The names of the tools are therefore data, and the registry checks them.")

(defun yeah-codes--tool-names ()
  "Return the names of the tools of the registry, as symbols."
  (mapcar #'intern (yeah-tools-names)))

(defun yeah-codes--rewrite (form)
  "Rewrite FORM so that a call of a tool goes through `tool'.

A call whose head is the name of a tool becomes
`(funcall tool \"NAME\" ARG ...)'. The model writes the call as it
would write it — the tools are reached by their names — and the
sandbox rewrites it, because in Emacs Lisp a `let' does not shadow the
cell of a function: a form that called `read' directly would call the
built-in `read' and not the tool of the registry.

The rewrite is ours, and it happens after the walk, so the model cannot
write the `funcall' itself: `funcall' is not among the allowed names."
  (cond
   ((not (consp form)) form)
   ;; a quoted form is data
   ((eq (car form) 'quote) form)
   ((memq (car form) (yeah-codes--tool-names))
    (append (list 'funcall 'tool (symbol-name (car form)))
            (cdr form)))
   (t (mapcar #'yeah-codes--rewrite form))))

(defun yeah-codes--permitted-p (form)
  "Return non-nil when FORM passes the restricted-call walk.
Every call head must be in `yeah-codes--core' or name a registry tool.
This syntactic check is only a restriction on expressible forms, not proof
of process, resource or side-effect isolation."
  (yeah-codes--walk form))

(defun yeah-codes--walk (form)
  "Walk FORM and report whether every call in it is allowed."
  (cond
   ((null form) t)
   ((symbolp form) t)
   ((numberp form) t)
   ((stringp form) t)
   ((keywordp form) t)
   ((vectorp form)
    (let ((ok t))
      (dotimes (i (length form))
        (unless (yeah-codes--walk (aref form i)) (setq ok nil)))
      ok))
   ((consp form)
    (let ((head (car form)))
      (cond
       ;; a quoted form is data: it is not walked into
       ((eq head 'quote) t)
       ((not (or (memq head yeah-codes--core)
                  (memq head (yeah-codes--tool-names))))
        nil)
       (t
        (let ((ok t))
          (dolist (cell form)
            (unless (yeah-codes--walk cell) (setq ok nil)))
          ok)))))
   ;; a character, or anything we do not understand: refused
   (t nil)))

(defun yeah-codes--tool-call (name &rest args)
  "Run the tool NAME with ARGS inside the evaluator.
The tool is called through the rules and the registry, exactly as a tool
called by the turn is: the evaluator does not get a way around the
permission system, and the name of the tool is checked by the registry
before anything runs."
  (unless (and (stringp name) (yeah-tools-get name))
    (signal 'user-error
            (list (format "yeah-codes: there is no tool named %S" name))))
  (let ((decision (condition-case err
                      (yeah-perm-evaluate name (format "%S" args))
                    (user-error (cons 'deny (error-message-string err))))))
    (unless (eq decision :allow)
      (signal 'user-error
              (list (format "yeah-codes: the rules do not allow %s" name))))
    (apply #'yeah-tools-call name (list args))))

(defun yeah-codes--tool-bindings ()
  "Return the binding list of the evaluator: the tools are reached through
the single function `tool', whose value the rewritten forms call with
`funcall'."
  (list (list 'tool (lambda (name &rest args)
                        (apply #'yeah-codes--tool-call name args)))))

(defun yeah-codes--eval-one (form inputs)
  "Evaluate one FORM. Return `(:name ... :result ... :ok t)'.

FORM is a plist (:name NAME :code CODE). INPUTS is the full
alist. NAME is whitelisted at the caller (`yeah-codes-eval').
CODE is parsed, wrapped in a `let' that binds INPUTS and the tools,
then `eval'd — but only after the body has been walked: a call that
is not a tool of the registry and not one of `yeah-codes--core' is
refused before a single form is evaluated. The result is
prin1/read round-tripped."
  (let* ((name (yeah-codes--plist-name form))
         (code (plist-get form :code))
         (bindings (mapcar #'yeah-codes--input-binding inputs))
         (body (yeah-codes--read-form code)))
    (unless (yeah-codes--permitted-p body)
      (signal 'user-error
              (list (format "yeah-codes: the form %s calls something outside the evaluator: %S"
                            name body))))
    (let ((result
           (eval `(let ,(append bindings (yeah-codes--tool-bindings))
                     ,(yeah-codes--rewrite body))
                 lexical-binding)))
      (list :name name
            :result (yeah-codes--json-roundtrip result)
            :ok t))))

(defun yeah-codes-eval (form-alist &optional inputs)
  "Evaluate FORM-ALIST only when `yeah-codes-enable-ptc' is non-nil.
Signal `user-error' before reading any form while PTC is disabled, as it is
by default.  This experimental evaluator is not a security boundary.

FORM-ALIST contains `(:name NAME :code CODE)' plists.  INPUTS is an alist of
lexical values.  Results are returned as `(:name NAME :result VALUE :ok t)'
plists after a `prin1'/`read' round trip.  Invalid names, malformed code and
calls outside the restricted core signal `user-error'."
  (unless yeah-codes-enable-ptc
    (signal 'user-error
            (list "yeah-codes-eval: experimental PTC is disabled; set `yeah-codes-enable-ptc' only for trusted code")))
  (unless (listp form-alist)
    (signal 'user-error
            (list (format "yeah-codes-eval: FORM-ALIST must be a list, got %S"
                          (type-of form-alist)))))
  (let ((err nil)
        (i 0))
    (while (and (null err) (< i (length form-alist)))
      (let* ((form (nth i form-alist))
             (name (and (consp form) (plist-get form :name))))
        (when (and (stringp name)
                   (not (yeah-codes--whitelist-member name)))
          (setq err (format "form #%d: %S is not in the whitelist"
                            (1+ i) name))))
      (setq i (1+ i)))
    (when err
      (signal 'user-error (list (concat "yeah-codes-eval: " err)))))
  (mapcar (lambda (form) (yeah-codes--eval-one form (or inputs '())))
          form-alist))

(defun yeah-codes-sandbox-available-p ()
  "Return non-nil when the optional `sandbox' feature is loaded.
This feature check does not make PTC safe and does not enable it.  Yeah does
not currently integrate `sandbox.el' or claim process isolation."
  (declare (pure t) (side-effect-free t))
  (featurep 'sandbox))

(provide 'yeah-codes)
;;; yeah-codes.el ends here
