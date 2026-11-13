;;; check-session-log-append-only.el --- canary for the session log -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The session log is append-only: a record that has been written is never
;; rewritten and never removed. The ERT suite checks the in-memory record
;; list; this check reads the FILE, because the file is what outlives the
;; process. A writer that overwrites instead of appending leaves the
;; in-memory list intact and loses the log.
;;
;; Exit codes: 0 — the log grew; 1 — it did not.

;;; Code:

(require 'yeah-session)

(defun yeah-check--lines (path)
  "Return the non-empty lines of the file at PATH."
  (with-temp-buffer
    (insert-file-contents path)
    (split-string (buffer-string) "\n" t)))

(defun yeah-check--records (path)
  "Return the parsed records of the JSONL file at PATH."
  (mapcar (lambda (line) (json-parse-string line :object-type 'plist))
          (yeah-check--lines path)))

(let* ((root (make-temp-file "yeah-session-check" t))
       (session (yeah-session-open "alpha" root))
       (path (yeah-session--path-for "alpha" root)))
  (yeah-session-append session (list :type "user" :payload "one"))
  (yeah-session-append session (list :type "assistant" :payload "two"))
  (yeah-session-append session (list :type "tool" :payload "three"))

  (let* ((records (yeah-check--records path))
         (types (mapcar (lambda (r) (plist-get r :type)) records))
         (ids (mapcar (lambda (r) (plist-get r :id)) records)))
    (unless (equal types '("header" "user" "assistant" "tool"))
      (message "the log does not hold every record: %S" types)
      (kill-emacs 1))
    (unless (equal ids (list (car ids) 1 2 3))
      (message "the record ids are not what the log says: %S" ids)
      (kill-emacs 1))))

(kill-emacs 0)

;;; check-session-log-append-only.el ends here
