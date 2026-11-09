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
;; same tools. When they drift, an MCP client reads a schema that promises
;; a tool the server does not have, or the other way round.
;;
;; Exit codes: 0 — the registry and the schema agree; 1 — they do not.

;;; Code:

(require 'yeah-emcp)

(let* ((schema (with-temp-buffer
                 (insert-file-contents "schemas/emcp-v1.json")
                 (json-parse-string (buffer-string) :object-type 'alist)))
       (examples (cdr (assoc 'examples schema)))
       (published (mapcar (lambda (tool) (cdr (assoc 'id tool)))
                          (cdr (assoc 'tools examples))))
       (registered (yeah-emcp-tool-ids)))
  (unless (equal (length published) (length registered))
    (message "the schema names %d tools, the registry holds %d: %S vs %S"
             (length published) (length registered) published registered)
    (kill-emacs 1))
  (unless (equal published registered)
    (message "the schema and the registry name different tools: %S vs %S"
             published registered)
    (kill-emacs 1)))

(kill-emacs 0)

;;; check-emcp-registry-matches-schema.el ends here
