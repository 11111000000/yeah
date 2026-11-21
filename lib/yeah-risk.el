;;; yeah-risk.el --- the risk a tool carries -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A tool says whether it changes the world.  The field is `:risk' and its
;; values come from a vocabulary of the kernel: "read", "write", "execute"
;; and "destroy".  A tool that declares no risk has a risk that is not
;; known -- the tools of a server of MCP come from outside and declare
;; nothing -- and a risk that is not known is a risk that changes the
;; world: the rule asks, and the absence of a declaration never makes the
;; rule softer.
;;
;; This module owns the vocabulary and the question "does this tool change
;; the world?".  It does not know the tools: the registry of
;; `lib/yeah-tools.el' installs the source of the declarations.  The late
;; binding is not a decoration: the permission rule asks by the
;; declarations, the declarations live in the registry, and the registry
;; requires the modules that require the permission rule.  A module that
;; required both ends of that circle would not load at all.
;;
;; Public operations: `yeah-risk-known-p' answers whether a value is in the
;; vocabulary, `yeah-risk-of' answers the risk of a tool,
;; `yeah-risk-mutating-p' answers whether a risk changes the world,
;; `yeah-risk-mutating-tools' answers which tools change the world, and
;; `yeah-risk-failure' answers why the registry of the tools is not there.

;;; Code:

(require 'cl-lib)

(defgroup yeah-risk nil
  "The risk a tool of Yeah carries."
  :group 'yeah)

(defconst yeah-risk--vocabulary '("read" "write" "execute" "destroy")
  "The risks a tool of Yeah may declare.
A tool that only looks declares \"read\"; a tool that changes what exists
declares \"write\"; a tool that runs code or a program declares
\"execute\"; a tool that takes something away declares \"destroy\".")

(defvar yeah-risk--source nil
  "Function of no arguments that returns the declarations of the tools.
The value is an alist of (NAME . RISK); the risk of a tool that declares
none is nil.  The registry of `lib/yeah-tools.el' installs this function,
so that this module does not have to know the registry.")

(defvar yeah-risk--failure nil
  "The error of the last load of the registry of the tools, or nil.
The registry of the tools is loaded on demand, and a registry that
cannot be loaded leaves the declarations unknown.  The error of that load
is kept here and not thrown away: a refusal that does not name its cause
is a refusal that the person cannot act on.")

(defun yeah-risk-known-p (risk)
  "Return non-nil when RISK is a risk of the vocabulary of the kernel.
RISK is a string; a value that is not a string is not known, and neither
is a value outside `yeah-risk--vocabulary'."
  (and (stringp risk)
       (cl-member risk yeah-risk--vocabulary :test #'equal) t))

(defun yeah-risk--install-source (source)
  "Install SOURCE as the source of the declarations of the tools.
SOURCE is a function of no arguments that returns the alist of
(NAME . RISK).  Returns SOURCE."
  (setq yeah-risk--source source)
  source)

(defun yeah-risk--known-p ()
  "Return non-nil when the declarations of the tools are known.
The registry of the tools is loaded on demand: the modules of the kernel
require this one, so the load cannot happen at the top level of this file.
A registry that cannot be loaded leaves the declarations unknown, and an
unknown declaration is a risk that changes the world.  The error of that
load is kept, and `yeah-risk-failure' names it."
  (unless yeah-risk--source
    (condition-case err
        (progn
          (require 'yeah-tools)
          (setq yeah-risk--failure nil))
      (error (setq yeah-risk--failure err))))
  (and yeah-risk--source t))

(defun yeah-risk-failure ()
  "Return the error of the last load of the registry of the tools, or nil.
The error is the one that the load of `lib/yeah-tools.el' raised, and it is
nil when the registry loaded or when it was never loaded.  The rule names it
in its refusal, so that the cause of the refusal is not hidden behind a
sentence about the registry."
  yeah-risk--failure)

(defun yeah-risk--declarations ()
  "Return the declarations of the tools: the alist of (NAME . RISK).
The risk of a tool that declares none is nil, and nil is a risk that
changes the world."
  (if (yeah-risk--known-p)
      (or (funcall yeah-risk--source) nil)
    nil))

(defun yeah-risk-of (name)
  "Return the risk the tool NAME declares, or nil when it declares none.
A tool of a server of MCP comes from outside and declares no risk; the
answer is nil, and nil is a risk that changes the world."
  (let ((declaration (assoc name (yeah-risk--declarations))))
    (and declaration (cdr declaration))))

(defun yeah-risk-mutating-p (risk)
  "Return non-nil when RISK changes the world.
The risk \"read\" changes nothing; every other risk does, and a risk that
is not known does as well: the rule asks by the declaration, and a
declaration that is missing must never make the rule softer."
  (not (and (stringp risk) (string= risk "read"))))

(defun yeah-risk-mutating-tools ()
  "Return the names of the tools that change the world.
The set is computed from the declarations of the tools and not from a list
of names: a tool that changes the world is in it because it says so, and a
tool that declares no risk is in it because nothing says that it does not."
  (let (mutating)
    (dolist (declaration (yeah-risk--declarations))
      (when (yeah-risk-mutating-p (cdr declaration))
        (push (car declaration) mutating)))
    (nreverse mutating)))

(provide 'yeah-risk)
;;; yeah-risk.el ends here
