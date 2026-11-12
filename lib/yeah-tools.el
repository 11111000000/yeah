;;; yeah-tools.el --- the in-process tool registry -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The Yeah agent loop calls "tools" by name. The tools themselves
;; are plain Elisp functions, registered against a name and a
;; declared `:input' shape. This file is the in-process registry
;; the loop dispatches against; it is the **kernel** counterpart to
;; `lib/yeah-emcp.el' (the MCP-server registry).
;;
;; Where `emcp' is for external MCP clients, the tools registry is
;; internal to the loop. The two registries have the same shape on
;; purpose: a tool that lives in both is registered once in each,
;; and the same handler function serves both sides.
;;
;; Public operations register/unregister/lookup tools and validate and
;; dispatch calls.  Built-in specifications are collected in
;; `lib/yeah-builtins.el'; handlers return structured results from
;; `lib/yeah-result.el' or legacy values accepted at the boundary.

;;; Code:

(require 'cl-lib)
(require 'yeah-builtins)

(defgroup yeah-tools nil
  "The Yeah in-process tool registry."
  :group 'yeah)

(defvar yeah-tools--registry (make-hash-table :test 'equal :size 16)
  "Current global table mapping tool names to specification plists.
Each value has shape (:name NAME :description DESC :input PARAMS :handler FN).
Run-scoped registries replace global sharing in the placement stage.")

(defvar yeah-tools--order nil
  "List of tool names in the order they were first registered.
Used by `yeah-tools-names' so the exposed order is stable.")

(defvar yeah-tools--built-in-p nil
  "Non-nil after `yeah-tools--ensure-built-ins' has run.")

(defsubst yeah-tools--type-check (value type)
  "Non-nil if VALUE matches the declared TYPE symbol."
  (pcase type
      ('string    (stringp value))
      ('integer   (integerp value))
      ('symbol    (symbolp value))
      ('boolean   (booleanp value))
      (_          nil)))

(defun yeah-tools--spec-p (spec)
  "Non-nil if SPEC looks like a valid tool spec plist."
  (and (consp spec)
       (stringp (plist-get spec :name))
       (> (length (plist-get spec :name)) 0)
       (stringp (plist-get spec :description))
       (listp (plist-get spec :input))
       (functionp (plist-get spec :handler))))

(defun yeah-tools-register (spec)
  "Register SPEC in the tools registry. Returns SPEC.

SPEC is a plist of shape

  (:name NAME :description DESC
   :input ((:name PARAM :type TYPE [:optional t]) ...)
   :handler FN
   [:concurrency MODE] [:async t])

where NAME is a string, DESC is a string, PARAM is a string, TYPE
is one of `string', `integer', `symbol', `boolean', and FN is a
function. Required parameters come first; optional ones come last.

Two more fields are optional and say how the tool is run:

  :concurrency  `shared' (the default) or `exclusive'. A shared tool
                may run alongside the other shared tools of the same
                answer; an exclusive tool runs alone, and everything
                else waits for it.
  :async        non-nil when the handler takes a continuation: it is
                called as (FN ARGS DONE) and calls DONE with the
                result. A tool that waits — on a process, on a timer —
                says so, and the scheduler does not block on it.

Signals `user-error' if SPEC is malformed or if a tool with the
same `:name' is already registered."
  (unless (yeah-tools--spec-p spec)
    (signal 'user-error
            (list (format "yeah-tools-register: malformed spec %S" spec))))
  (let ((name (plist-get spec :name)))
    (when (gethash name yeah-tools--registry)
      (signal 'user-error
              (list (format "yeah-tools-register: %S already registered" name))))
    (puthash name spec yeah-tools--registry)
    (unless (member name yeah-tools--order)
      (setq yeah-tools--order (append yeah-tools--order (list name))))
    spec))

(defun yeah-tools-concurrency (spec)
  "Return the concurrency mode of the tool SPEC: `shared' or `exclusive'.
The default is `shared': a tool that may run alongside the other shared
tools of the same answer. A tool that writes something nobody else may
touch at the same time declares itself `exclusive'."
  (let ((mode (plist-get spec :concurrency)))
    (if (memq mode '(shared exclusive)) mode 'shared)))

(defun yeah-tools-unregister (name)
  "Remove the tool registered under NAME. No-op if absent."
  (when (gethash name yeah-tools--registry)
    (remhash name yeah-tools--registry)
    (setq yeah-tools--order (cl-remove name yeah-tools--order :test 'equal)))
  nil)

(defun yeah-tools-get (name)
  "Return the spec plist for tool NAME, or nil if absent."
  (gethash name yeah-tools--registry))

(defun yeah-tools-names ()
  "Return the list of all registered tool names, in registration order."
  (yeah-tools--ensure-built-ins)
  yeah-tools--order)

(defun yeah-tools--required-count (params)
  "Return the number of required parameters in PARAMS."
  (let ((n 0))
    (dolist (p params)
        (unless (plist-get p :optional)
          (setq n (1+ n))))
    n))

(defun yeah-tools--check-args (name spec args)
  "Signal a `user-error' unless ARGS fit the input of the tool SPEC.
The count of the arguments, and the type of every one of them, must
match what the tool declared. This is the gate: a tool is never called
with arguments it did not ask for."
  (let* ((params (plist-get spec :input))
         (req (yeah-tools--required-count params))
         (max (length params))
         (err nil))
    (unless (and (>= (length args) req)
                 (<= (length args) max))
      (signal 'user-error
              (list (format
                      "yeah-tools-call: %S expected %d..%d args, got %d"
                      name req max (length args)))))
    (let ((idx 0))
      (while (and (null err) (< idx (length params)))
        (let* ((p (nth idx params))
               (pname (plist-get p :name))
               (ptype (plist-get p :type))
               (value (nth idx args)))
          (when (and value (not (yeah-tools--type-check value ptype)))
            (setq err (format "arg %d (%s) expected %s, got %S"
                              (1+ idx) pname ptype value))))
        (setq idx (1+ idx))))
    (when err
      (signal 'user-error
              (list (format "yeah-tools-call: %S: %s" name err))))))

(defun yeah-tools--validate-and-apply (name spec args)
  "Validate ARGS against SPEC for tool NAME, then call the handler.
Returns the handler's result. Signals `user-error' on count or
type mismatch."
  (yeah-tools--check-args name spec args)
  (apply (plist-get spec :handler) args))

(defun yeah-tools-dispatch (name args &optional done)
  "Run the tool NAME with ARGS and hand the result to DONE.

DONE is called with the result of the tool. A tool that is not
asynchronous answers at once; a tool that is asynchronous takes the
continuation itself and calls it when it has settled.

This is the way into the registry from outside it: the arguments are
checked here, and nowhere else."
  (let ((spec (yeah-tools-get name)))
    (unless spec
      (signal 'user-error
              (list (format "yeah-tools-dispatch: unknown tool name %S" name))))
    (yeah-tools--check-args name spec args)
    (if (plist-get spec :async)
        (funcall (plist-get spec :handler) args (or done #'ignore))
      (let ((result (apply (plist-get spec :handler) args)))
        (when done (funcall done result))
        result))))

(defun yeah-tools-call (name args)
  "Dispatch a tool call: look up NAME, validate ARGS, call handler.

Returns the handler's result. ARGS is a list of positional
arguments; its length must be between the count of required
parameters and the total count of parameters declared in the
spec. Each non-nil argument must satisfy the declared `:type'.

Signals `user-error' if NAME is not registered, if the arg count
is wrong, or if any arg fails the type check."
  (let ((spec (gethash name yeah-tools--registry)))
    (unless spec
      (signal 'user-error
              (list (format "yeah-tools-call: unknown tool name %S" name))))
    (unless (listp args)
      (signal 'user-error
              (list (format "yeah-tools-call: args must be a list, got %S"
                            (type-of args)))))
    (condition-case err
        (yeah-tools--validate-and-apply name spec args)
      (user-error
       (signal 'user-error
               (list (format "yeah-tools-call: %S raised: %S"
                             name err)))))))

(defun yeah-tools--ensure-built-ins ()
  "Populate the registry with the built-in tools, idempotently."
  (unless yeah-tools--built-in-p
    (dolist (spec (yeah-builtins-specs))
      (yeah-tools-register spec))
    (setq yeah-tools--built-in-p t)))

(defun yeah-tools-reset-for-test ()
  "Drop every registration; for tests only.
Not exported; documented here so test authors can find it.
After resetting, the built-in `read' tool is re-registered so the
registry is in the same state as after fresh `require'."
  (clrhash yeah-tools--registry)
  (setq yeah-tools--order nil
        yeah-tools--built-in-p nil)
  (yeah-tools--ensure-built-ins))

(yeah-tools--ensure-built-ins)

(provide 'yeah-tools)
;;; yeah-tools.el ends here