;;; check-emcp-registry-matches-schema.el --- canary for the tool surface -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The published tool surface has one source of truth: the registry in
;; lib/yeah-emcp.el and the schema in schemas/emcp-v1.json must name the
;; same tools, describe them the same way, and agree about which of them
;; the server publishes by default.  When they drift, an MCP client reads
;; a schema that promises a tool the server does not have, or the other
;; way round.
;;
;; Exit codes: 0 -- the registry and the schema agree; 1 -- they do not.

;;; Code:

(require 'cl-lib)
(require 'yeah-emcp)

(defun yeah-check--tool-field (tool key)
  "Return the field KEY of the schema tool object TOOL."
  (cdr (assoc key tool)))

(defun yeah-check--tool-input (tool)
  "Return the input parameter names of the schema tool TOOL as a list."
  (append (yeah-check--tool-field tool 'input) nil))

(defun yeah-check--schema-tools (schema)
  "Return the tool objects of the schema examples of SCHEMA."
  (append (cdr (assoc 'tools (cdr (assoc 'examples schema)))) nil))

(defun yeah-check--schema-published (schema)
  "Return the published ids of the schema examples of SCHEMA."
  (append (cdr (assoc 'published (cdr (assoc 'examples schema)))) nil))

(let* ((schema (with-temp-buffer
                 (insert-file-contents "schemas/emcp-v1.json")
                 (json-parse-string (buffer-string) :object-type 'alist)))
       (schema-tools (yeah-check--schema-tools schema))
       (schema-published (yeah-check--schema-published schema))
       (registered (yeah-emcp-tool-ids))
       (published (yeah-emcp-published-ids))
       (failure nil))

  (unless (equal (length schema-tools) (length registered))
    (setq failure (format "the schema names %d tools, the registry holds %d"
                          (length schema-tools) (length registered))))
  (unless (equal (sort (mapcar (lambda (tool) (yeah-check--tool-field tool 'id))
                                schema-tools) #'string<)
                 (sort (copy-sequence registered) #'string<))
    (setq failure (format "the schema and the registry name different tools: %S vs %S"
                          (mapcar (lambda (tool) (yeah-check--tool-field tool 'id))
                                  schema-tools)
                          registered)))
  (dolist (tool schema-tools)
    (let* ((id (yeah-check--tool-field tool 'id))
           (spec (and (stringp id) (yeah-emcp-tool-spec id))))
      (cond
       ((null spec)
        (setq failure (format "the schema names a tool the registry does not hold: %s" id)))
       ((not (equal (yeah-check--tool-field tool 'description)
                    (plist-get spec :description)))
        (setq failure (format "the schema and the registry describe %s differently" id)))
       ((not (equal (yeah-check--tool-input tool) (plist-get spec :input)))
        (setq failure (format "the schema and the registry disagree on the input of %s" id)))
       ((not (equal (yeah-check--tool-field tool 'output)
                    (plist-get spec :output)))
        (setq failure (format "the schema and the registry disagree on the output of %s" id))))))
  (unless (equal (sort (copy-sequence schema-published) #'string<)
                 (sort (copy-sequence published) #'string<))
    (setq failure (format "the schema and the registry publish different tools: %S vs %S"
                          schema-published published)))

  (when failure
    (message "%s" failure)
    (kill-emacs 1)))

(kill-emacs 0)

;;; check-emcp-registry-matches-schema.el ends here
