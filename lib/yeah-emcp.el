;;; yeah-emcp.el --- the emcp tool registry (first wave) -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The `emcp' MCP server publishes a stable tool surface under the
;; `emacs__*' namespace (see `decisions/emcp-mcp-server@0' and
;; `decisions/emcp-tool-surface@0'). This file is the tool
;; *registry*: it stores the tool specs (id, description, input
;; parameters, handler) and exposes four primitives:
;;
;;   * `yeah-emcp-tool-ids'    -- list of all registered tool ids
;;   * `yeah-emcp-tool-spec'   -- look up one tool's spec (or nil)
;;   * `yeah-emcp-handle-call' -- dispatch to a tool's handler
;;   * `yeah-emcp-register-tool' -- add a new tool to the registry
;;
;; In the first wave every handler is a **stub** that returns a
;; placeholder string documenting which tier will wire the real
;; implementation. Real wiring lands in Tier 3 (read-side tools)
;; and Tier 4 (eval / write-side tools).
;;
;; The registry is built once, on demand, the first time any
;; lookup primitive is called. There are no top-level side
;; effects on `require'; this keeps the file byte-compile clean
;; and lets tests call `yeah-emcp-register-tool' before the
;; built-ins are populated.

;;; Code:

(require 'cl-lib)

(defgroup yeah-emcp nil
  "The emcp MCP server tool registry."
  :group 'yeah)

(defvar yeah-emcp--registry (make-hash-table :test 'equal :size 32)
  "Hash table mapping tool id (string) to spec plist.
Each value has shape (:id ID :description DESC :input PARAMS
:handler FN). Rebind with `setq', not `let'.")

(defvar yeah-emcp--order nil
  "List of tool ids in the order they were first registered.
Used by `yeah-emcp-tool-ids' so the exposed order is stable.")

(defvar yeah-emcp--built-in-p nil
  "Non-nil after `yeah-emcp--ensure-built-ins' has populated the registry.")

(defsubst yeah-emcp--spec-p (spec)
  "Non-nil if SPEC looks like a valid tool spec plist."
  (and (consp spec)
       (stringp (plist-get spec :id))
       (stringp (plist-get spec :description))
       (listp (plist-get spec :input))
       (functionp (plist-get spec :handler))))

(defun yeah-emcp-register-tool (spec)
  "Register SPEC in the emcp registry.
SPEC is a plist with `:id' (string), `:description' (string),
`:input' (list of parameter name strings), and `:handler'
(a function). Returns SPEC.

Signals `user-error' if SPEC is malformed or if a tool with the
same `:id' is already registered."
  (unless (yeah-emcp--spec-p spec)
    (signal 'user-error
            (list (format "yeah-emcp-register-tool: malformed spec %S" spec))))
  (let ((id (plist-get spec :id)))
    (when (gethash id yeah-emcp--registry)
      (signal 'user-error
              (list (format "yeah-emcp-register-tool: %S already registered" id))))
    (puthash id spec yeah-emcp--registry)
    (unless (member id yeah-emcp--order)
      (setq yeah-emcp--order (append yeah-emcp--order (list id))))
    spec))

(defun yeah-emcp--make-stub (id tier)
  "Build a stub handler that documents which TIER will wire ID.
The returned function ignores its single argument; the
placeholder string records the target tier."
  (lambda (input)
    (ignore input)
    (format "%s: not yet wired; real handler lands in %s" id tier)))

(defun yeah-emcp--ensure-built-ins ()
  "Populate the registry with the first-wave tool ids, idempotently."
  (unless yeah-emcp--built-in-p
    (let ((entries
           (list
             (list "emacs__eval"
                   "Evaluate an Emacs Lisp expression and return its value as a string."
                   '("expr")
                   (yeah-emcp--make-stub "emacs__eval" "Tier 3"))
             (list "emacs__buffer_list"
                   "List live buffers, optionally filtered by a name prefix."
                   '("prefix")
                   (yeah-emcp--make-stub "emacs__buffer_list" "Tier 3"))
             (list "emacs__buffer_read"
                   "Return the contents of a buffer, optionally restricted to a range."
                   '("name" "start" "end")
                   (yeah-emcp--make-stub "emacs__buffer_read" "Tier 3"))
             (list "emacs__buffer_write"
                   "Replace or insert text in a buffer at a given position."
                   '("name" "start" "end" "text")
                   (yeah-emcp--make-stub "emacs__buffer_write" "Tier 4"))
             (list "emacs__magit_status"
                   "Return the current Magit status buffer as a string."
                   nil
                   (yeah-emcp--make-stub "emacs__magit_status" "Tier 4"))
             (list "emacs__describe_function"
                   "Return the help string of a function symbol."
                   '("symbol")
                   (yeah-emcp--make-stub "emacs__describe_function" "Tier 3"))
             (list "emacs__describe_variable"
                   "Return the help string of a variable symbol."
                   '("symbol")
                   (yeah-emcp--make-stub "emacs__describe_variable" "Tier 3"))
             (list "emacs__dired_list"
                   "List files in a directory (default: project root)."
                   '("directory")
                   (yeah-emcp--make-stub "emacs__dired_list" "Tier 4"))
             (list "emacs__project_find_file"
                   "Find a file by name within the current project."
                   '("name")
                   (yeah-emcp--make-stub "emacs__project_find_file" "Tier 4")))))
      (dolist (entry entries)
        (let* ((id   (nth 0 entry))
               (desc (nth 1 entry))
               (in   (nth 2 entry))
               (fn   (nth 3 entry))
               (spec (list :id id :description desc :input in :handler fn)))
          (yeah-emcp-register-tool spec))))
    (setq yeah-emcp--built-in-p t)))

(defun yeah-emcp-tool-ids ()
  "Return the list of all registered emcp tool ids, in registration order."
  (yeah-emcp--ensure-built-ins)
  yeah-emcp--order)

(defun yeah-emcp-tool-spec (id)
  "Return the spec plist for tool ID, or nil if no such tool is registered."
  (yeah-emcp--ensure-built-ins)
  (gethash id yeah-emcp--registry))

(defun yeah-emcp-handle-call (id args)
  "Dispatch a tool call: look up ID and call its handler with ARGS.
Returns the handler's return value (in the first wave, a string).
Signals `user-error' if ID is not registered."
  (let ((spec (yeah-emcp-tool-spec id)))
    (unless spec
      (signal 'user-error
              (list (format "yeah-emcp-handle-call: unknown tool id %S" id))))
    (let ((handler (plist-get spec :handler))
          (params  (plist-get spec :input)))
      (condition-case err
          (progn
            (unless (functionp handler)
              (signal 'user-error
                      (list (format
                              "yeah-emcp-handle-call: %S handler is not a function"
                              id))))
            (if (null params)
                (funcall handler nil)
              (funcall handler args)))
        (error
         (signal 'user-error
                 (list (format
                         "yeah-emcp-handle-call: %S raised: %S"
                         id err))))))))

(defun yeah-emcp--reset-for-test ()
  "Drop every registration; for tests only.
Not exported; documented here so test authors can find it."
  (clrhash yeah-emcp--registry)
  (setq yeah-emcp--order nil
        yeah-emcp--built-in-p nil))

(provide 'yeah-emcp)
;;; yeah-emcp.el ends here