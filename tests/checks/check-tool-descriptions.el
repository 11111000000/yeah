;;; check-tool-descriptions.el --- canary for the tool descriptions -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The model chooses a tool by its name and by its description.  Two of the
;; built-in tools are neighbours in that choice, and they must not overlap:
;; `read' reads a file from disk, `buffer-read' reads the content of a
;; live Emacs buffer.  When their descriptions say the same thing, the
;; model takes the wrong one, and the failure is invisible from the
;; outside: the run simply stops with the wrong text.
;;
;; The check asserts three things about the built-in tool surface:
;;
;;   1. every built-in tool has a nonempty description, and no two of them
;;      share one;
;;   2. `read' names a file on disk and never a live buffer, while
;;      `buffer-read' names a live buffer and never a file on disk: their
;;      vocabularies are disjoint, so neither description can be mistaken
;;      for the other;
;;   3. every other tool names the thing it works on, so that none of them
;;      can be mistaken for the reader of a file or of a buffer.
;;
;; The check reads the descriptions only: it starts no subprocess, opens no
;; buffer and needs no model.
;;
;; Exit codes: 0 -- the descriptions are unambiguous; 1 -- they are not.

;;; Code:

(require 'cl-lib)
(require 'yeah-builtins)

(defconst yeah-check--description-rules
  '(("read"        ("file" "disk" "path")   ("buffer" "live"))
    ("buffer-read" ("buffer" "live" "name") ("file" "disk" "path"))
    ("edit"        ("file" "tick")          ("buffer" "live"))
    ("write"       ("file")                ("buffer" "live"))
    ("glob"        ("file")                ("buffer" "live"))
    ("grep"        ("file")                ("buffer" "live"))
    ("bash"        ("command")             ("buffer" "live"))
    ("introspect"  ("documentation")       ("file" "disk" "buffer"))
    ("elisp-check" ("elisp")               ("buffer" "live"))
    ("diagnostics" ("flymake" "diagnostic") ("disk"))
    ("finish"      ("run")                 ("file" "disk" "buffer"))
    ("job-read"    ("job")                 nil)
    ("job-status"  ("status")              nil)
    ("job-cancel"  ("job")                 nil))
  "Each row is (TOOL REQUIRED-WORDS FORBIDDEN-WORDS) for the description
of TOOL.  A required word must occur in the description; a forbidden word
must not: it belongs to another tool and would blur the two.")

(defun yeah-check--mentions-p (text word)
  "Return non-nil when TEXT mentions WORD, ignoring the case of both."
  (and (stringp text)
       (string-match-p (regexp-quote word) (downcase text))))

(defun yeah-check--descriptions ()
  "Return an alist of the built-in tool name to its description."
  (mapcar (lambda (spec)
            (cons (plist-get spec :name) (plist-get spec :description)))
          (yeah-builtins-specs)))

(let ((failures nil)
      (descriptions (yeah-check--descriptions)))

  ;; --- every tool is described, and no two share one description -------
  (dolist (entry descriptions)
    (let ((name (car entry))
          (description (cdr entry)))
      (unless (and (stringp description) (> (length description) 0))
        (push (format "the tool %s has no description" name) failures))))
  (let ((owners (make-hash-table :test 'equal)))
    (dolist (entry descriptions)
      (let ((name (car entry))
            (description (cdr entry)))
        (when (stringp description)
          (let ((owner (gethash description owners)))
            (if owner
                (push (format "the tools %s and %s share one description"
                               owner name)
                      failures)
              (puthash description name owners)))))))

  ;; --- each description names the thing the tool works on ---------------
  (dolist (rule yeah-check--description-rules)
    (let* ((name (nth 0 rule))
           (required (nth 1 rule))
           (forbidden (nth 2 rule))
           (description (cdr (assoc name descriptions))))
      (cond
       ((null description)
        (push (format "the built-in tool %s is missing" name) failures))
       (t
        (dolist (word required)
          (unless (yeah-check--mentions-p description word)
            (push (format "the description of %s does not mention %s"
                           name word)
                  failures)))
        (dolist (word forbidden)
          (when (yeah-check--mentions-p description word)
            (push (format "the description of %s mentions %s, which belongs to another tool"
                           name word)
                  failures)))))))

  ;; --- the two neighbours are told apart --------------------------------
  (let ((read-description (cdr (assoc "read" descriptions)))
        (buffer-description (cdr (assoc "buffer-read" descriptions))))
    (when (and read-description buffer-description
               (string= read-description buffer-description))
      (push "read and buffer-read describe themselves the same way" failures))
    (when (and read-description
               (yeah-check--mentions-p read-description "buffer"))
      (push "the description of read mentions a buffer, which is what buffer-read reads"
            failures))
    (when (and buffer-description
               (yeah-check--mentions-p buffer-description "file"))
      (push "the description of buffer-read mentions a file, which is what read reads"
            failures)))

  (dolist (failure failures)
    (message "tool descriptions: %s" failure))
  (kill-emacs (if failures 1 0)))

;;; check-tool-descriptions.el ends here
