;;; yeah-emcp.el --- the emacs__* tool surface -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The tools Yeah publishes to external agents under the `emacs__*' namespace.
;; Every handler performs the real operation on the running Emacs.  The
;; published set is a trust decision: mutating tools are only published when
;; the operator allows them, and the MCP server never publishes a tool that
;; is not in the registry.

;;; Code:

(require 'cl-lib)
(require 'yeah-undo)

(declare-function project-current "project" (&optional maybe-prompt))
(declare-function project-root "project" (project))
(declare-function erase-region "subr" (start end))

(defgroup yeah-emcp nil
  "The emacs__* tool surface published by Yeah."
  :group 'yeah)

(defvar yeah-emcp--registry (make-hash-table :test 'equal :size 32)
  "Current global table mapping published tool ids to specification plists.
Each value has shape (:id ID :description DESC :input PARAMS
:output KIND :handler FN).")

(defvar yeah-emcp--order nil
  "List of tool ids in the order they were first registered.")

(defvar yeah-emcp--built-in-p nil
  "Non-nil after the built-in tools have been registered.")

(defconst yeah-emcp--read-only-tools
  '("emacs__buffer_list" "emacs__buffer_read"
    "emacs__describe_function" "emacs__describe_variable"
    "emacs__dired_list" "emacs__project_find_file"
    "emacs__magit_status")
  "Tools that only read state and are safe to publish by default.")

(defcustom yeah-emcp-publish-extra-tools nil
  "Extra tool ids published to external agents on top of the read-only set.
An empty list publishes only the read-only tools, which is the default.
Naming a tool id publishes it as well; the id must exist in the registry."
  :type '(repeat string)
  :group 'yeah-emcp)

(defsubst yeah-emcp--spec-p (spec)
  "Return non-nil when SPEC looks like a valid tool spec plist."
  (and (consp spec)
       (stringp (plist-get spec :id))
       (stringp (plist-get spec :description))
       (listp (plist-get spec :input))
       (functionp (plist-get spec :handler))))

(defun yeah-emcp-register-tool (spec)
  "Register SPEC in the emacs tool registry and return SPEC.
Signals `user-error' when SPEC is malformed or the id is taken."
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

(defun yeah-emcp--arg (args name &optional default)
  "Return argument NAME from the argument list ARGS, or DEFAULT."
  (let ((value (and (listp args) (plist-get args name))))
    (if (null value) default value)))

(defun yeah-emcp--buffer-list (args)
  "Return the names of live buffers matching the optional prefix."
  (let ((prefix (yeah-emcp--arg args :prefix)))
    (mapcar #'buffer-name
            (if prefix
                (seq-filter (lambda (buffer)
                              (string-prefix-p prefix (buffer-name buffer)))
                            (buffer-list))
              (buffer-list)))))

(defun yeah-emcp--buffer-read (args)
  "Return the text of the buffer named in ARGS, optionally a region."
  (let* ((name (yeah-emcp--arg args :name))
         (buffer (and name (get-buffer name))))
    (unless (buffer-live-p buffer)
      (signal 'user-error (list (format "no live buffer named %s" name))))
    (with-current-buffer buffer
      (save-restriction
        (let ((start (or (yeah-emcp--arg args :start) (point-min)))
              (end (or (yeah-emcp--arg args :end) (point-max))))
          (buffer-substring-no-properties start end))))))

(defun yeah-emcp--buffer-write (args)
  "Replace a region of the buffer named in ARGS with text."
  (let* ((name (yeah-emcp--arg args :name))
         (buffer (and name (get-buffer name)))
         (text (or (yeah-emcp--arg args :text) ""))
         (start (yeah-emcp--arg args :start))
         (end (yeah-emcp--arg args :end)))
    (unless (buffer-live-p buffer)
      (signal 'user-error (list (format "no live buffer named %s" name))))
    (with-current-buffer buffer
      (yeah-undo-around-buffer
       buffer
       (lambda ()
         (let ((from (or start (point-min)))
               (to (or end (point-max))))
           (save-restriction
             (narrow-to-region from to)
             (erase-region (point-min) (point-max))
             (goto-char (point-min))
             (insert text))))))
    (format "wrote %d characters into %s" (length text) name)))

(defun yeah-emcp--describe-function (args)
  "Return the documentation of the function named in ARGS."
  (let* ((name (yeah-emcp--arg args :symbol))
         (symbol (and name (intern-soft name))))
    (unless (fboundp symbol)
      (signal 'user-error (list (format "no function named %s" name))))
    (or (documentation symbol 'function)
        (format "no documentation for %s" name))))

(defun yeah-emcp--describe-variable (args)
  "Return the documentation of the variable named in ARGS."
  (let* ((name (yeah-emcp--arg args :symbol))
         (symbol (and name (intern-soft name))))
    (unless (boundp symbol)
      (signal 'user-error (list (format "no variable named %s" name))))
    (or (documentation-property symbol 'variable-documentation)
        (format "no documentation for %s" name))))

(defun yeah-emcp--dired-list (args)
  "Return the entries of the directory named in ARGS."
  (let* ((directory (expand-file-name
                     (or (yeah-emcp--arg args :directory) default-directory)))
         (entries (directory-files directory)))
    (mapcar #'file-name-nondirectory
            (seq-remove (lambda (name) (string-prefix-p "." name)) entries))))

(defun yeah-emcp--project-find-file (args)
  "Return the path of the file named in ARGS under the current project."
  (let* ((name (yeah-emcp--arg args :name))
         (root (if (fboundp 'project-current)
                    (let ((project (project-current nil)))
                      (if project (project-root project) default-directory))
                  default-directory)))
    (unless name
      (signal 'user-error (list "emacs__project_find_file needs a name")))
    (let ((found (directory-files-recursively
                  (file-truename root) "" nil
                  (lambda (path)
                    (and (file-regular-p path)
                         (equal (file-name-nondirectory path) name))))))
      (or (car (sort found #'string<)) ""))))

(defun yeah-emcp--magit-status (args)
  "Return the Magit status of the current repository, or an explanation."
  (ignore args)
  (if (and (fboundp 'magit-status) (fboundp 'magit-mode-get-buffers))
      (with-current-buffer (car (magit-mode-get-buffers))
        (buffer-substring-no-properties (point-min) (point-max)))
    "Magit is not available in this Emacs."))

(defun yeah-emcp--eval (args)
  "Evaluate the Lisp expression named in ARGS and return its printed value."
  (let* ((expr (yeah-emcp--arg args :expr))
         (value (eval (car (read (format "(%s)" expr))) t)))
    (format "%S" value)))

(defun yeah-emcp--ensure-built-ins ()
  "Register the built-in emacs tools, idempotently."
  (unless yeah-emcp--built-in-p
    (dolist (entry
             (list (list "emacs__buffer_list"
                         "List live buffers, optionally filtered by a name prefix."
                         '("prefix") "string" #'yeah-emcp--buffer-list)
                   (list "emacs__buffer_read"
                         "Return the contents of a buffer, optionally restricted to a range."
                         '("name" "start" "end") "buffer-string"
                         #'yeah-emcp--buffer-read)
                   (list "emacs__buffer_write"
                         "Replace or insert text in a buffer at a given position."
                         '("name" "start" "end" "text") "string"
                         #'yeah-emcp--buffer-write)
                   (list "emacs__magit_status"
                         "Return the current Magit status buffer as a string."
                         nil "buffer-string" #'yeah-emcp--magit-status)
                   (list "emacs__describe_function"
                         "Return the help string of a function symbol."
                         '("symbol") "string" #'yeah-emcp--describe-function)
                   (list "emacs__describe_variable"
                         "Return the help string of a variable symbol."
                         '("symbol") "string" #'yeah-emcp--describe-variable)
                   (list "emacs__dired_list"
                         "List files in a directory (default: project root)."
                         '("directory") "string" #'yeah-emcp--dired-list)
                   (list "emacs__project_find_file"
                         "Find a file by name within the current project."
                         '("name") "string" #'yeah-emcp--project-find-file)
                   (list "emacs__eval"
                         "Evaluate an Emacs Lisp expression and return its value as a string."
                         '("expr") "string" #'yeah-emcp--eval)))
      (yeah-emcp-register-tool
       (list :id (nth 0 entry)
             :description (nth 1 entry)
             :input (nth 2 entry)
             :output (nth 3 entry)
             :handler (nth 4 entry))))
    (setq yeah-emcp--built-in-p t)))

(defun yeah-emcp-tool-ids ()
  "Return the registered tool ids in registration order."
  (yeah-emcp--ensure-built-ins)
  yeah-emcp--order)

(defun yeah-emcp-tool-spec (id)
  "Return the spec plist for tool ID, or nil."
  (yeah-emcp--ensure-built-ins)
  (gethash id yeah-emcp--registry))

(defun yeah-emcp-published-ids ()
  "Return the ids that may be published to external agents.
Only read-only tools are published unless the operator widens the surface
through `yeah-emcp-publish-extra-tools'."
  (seq-filter (lambda (id)
                (or (member id yeah-emcp--read-only-tools)
                    (member id yeah-emcp-publish-extra-tools)))
              (yeah-emcp-tool-ids)))

(defun yeah-emcp-handle-call (id args)
  "Call tool ID with the argument list ARGS and return its result."
  (let ((spec (yeah-emcp-tool-spec id)))
    (unless spec
      (signal 'user-error
              (list (format "yeah-emcp-handle-call: unknown tool id %S" id))))
    (let ((handler (plist-get spec :handler)))
      (condition-case err
          (funcall handler (or args '()))
        (error
         (signal 'user-error
                 (list (format "yeah-emcp-handle-call: %S raised: %S" id err))))))))

(defun yeah-emcp--reset-for-test ()
  "Drop every registration for tests."
  (clrhash yeah-emcp--registry)
  (setq yeah-emcp--order nil
        yeah-emcp--built-in-p nil))

(provide 'yeah-emcp)
;;; yeah-emcp.el ends here
