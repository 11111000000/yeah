;;; yeah-diagram-files.el --- one reader for the diagrams of the site -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The diagrams of the site are written by hand, and every check of them
;; asks the same questions: is the file there, does every name of a file
;; point at a line that carries a definition, and does the picture say
;; what it is supposed to say.  One reader answers those questions for
;; every check: two copies of the reader are two readers that drift
;; apart, and a check that reads the picture its own way measures
;; something else than the other one.
;;
;; The reader answers five things:
;;
;;   * `yeah-diagram--text' reads the file;
;;   * `yeah-diagram--lines-of' counts the lines of a file and keeps the
;;     empty ones, because the number of a line is the place of it;
;;   * `yeah-diagram--content-lines' returns the lines of the *drawing*:
;;     a quoted title is split at the newlines that PlantUML writes as
;;     `\n', and the comment of the diagram is not a line of the drawing
;;     -- a word that is only in the comment is not a claim of the
;;     picture;
;;   * `yeah-diagram--references' returns every name of the form
;;     `file:line' of the diagram, and `yeah-diagram--reference-defect'
;;     says what is wrong with such a name;
;;   * `yeah-diagram--says-p' says whether the drawing says a word.
;;
;; The tree of the repository is never written: this reader only reads.

;;; Code:

(require 'cl-lib)

(defconst yeah-diagram--reference-pattern
  "[A-Za-z0-9._][A-Za-z0-9._/-]*\\.[A-Za-z0-9]+:[0-9]+"
  "The pattern of a name of the form `file:line' in a diagram.")

(defconst yeah-diagram--path-pattern
  "[A-Za-z0-9._-][A-Za-z0-9._/-]*\\.[A-Za-z0-9]+(:[0-9]+)?"
  "The pattern of a name of a file in a diagram, with a line or without.")

(defun yeah-diagram--text (path)
  "Return the text of the file at PATH."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(defun yeah-diagram--lines-of (path)
  "Return the number of the lines of the file at PATH and the lines.
The empty lines are kept: the number of a line is the place of it, and
the place of an empty line is a place like any other.  The newline at
the end of the file does not open a line of its own."
  (with-temp-buffer
    (insert-file-contents path)
    (let* ((lines (split-string (buffer-string) "\n"))
           (last (car (last lines))))
      (cons (if (string-empty-p last) (1- (length lines)) (length lines))
            lines))))

(defconst yeah-diagram--definition-pattern
  "\\`[(]\\(cl-\\)?\\(defun\\|defmacro\\|defsubst\\|defcustom\\|defconst\\|defvar\\|defstruct\\|defface\\|define-derived-mode\\|define-minor-mode\\)[ \t(]"
  "The pattern of a line that carries a definition.")

(defun yeah-diagram--definition-p (text)
  "Return non-nil when TEXT carries a definition.
A definition is the opening of a `defun', a `defvar', a `defconst', a
`cl-defun' or a `cl-defstruct': the name of a thing the picture names
is a name of the code, and a line that carries code and no definition
names no definition.  An empty line carries no code, and a line that
holds nothing but a comment carries no code either."
  (let ((trimmed (string-trim text)))
    (and (not (string-empty-p trimmed))
         (string-match yeah-diagram--definition-pattern trimmed))))

(defun yeah-diagram--strings (line)
  "Return the quoted strings of LINE."
  (let (strings)
    (while (string-match "\"\\([^\"]*\\)\"" line)
      (push (match-string 1 line) strings)
      (setq line (substring line (match-end 0))))
    (nreverse strings)))

(defun yeah-diagram--content-lines (text)
  "Return the lines of the drawing of the diagram in TEXT.
A quoted string of the diagram is a title, and a title of several lines
is split at the newlines that PlantUML writes as `\\n'.  The physical
line that holds the string is not a line of the drawing: the drawing is
the text of the title and the lines around it.  A physical line without
a quoted string is a line of the drawing as it is.

The comment of the diagram is not a line of the drawing: a word that is
only in the comment is not a claim of the picture."
  (let (lines)
    (dolist (line (split-string text "\n" t))
      (unless (string-prefix-p "'" (string-trim line))
        (let ((strings (yeah-diagram--strings line)))
          (if strings
              (dolist (string strings)
                (dolist (fragment (split-string string (regexp-quote "\\n") t))
                  (unless (string-empty-p (string-trim fragment))
                    (push (string-trim fragment) lines))))
            (push (string-trim line) lines)))))
    (nreverse lines)))

(defun yeah-diagram--references (text)
  "Return the references of the diagram in TEXT.
A reference is a path of this repository and the number of a line of
it.

The newlines that PlantUML writes inside a title as `\\n' are read as
the line breaks they are: the path of a reference that follows such a
newline begins at the beginning of a line, and not in the middle of the
word `\\n'."
  (let (references)
    (setq text (replace-regexp-in-string "\\\\n" "\n" text))
    (while (string-match yeah-diagram--reference-pattern text)
      ;; The place of the scan is taken before anything else is matched:
      ;; a match of another string overwrites the match data of the
      ;; scan, and a scan that reads the wrong place reads one name
      ;; again and again.
      (let* ((reference (match-string 0 text))
             (end (match-end 0))
             (colon (string-match ":[0-9]+$" reference)))
        (push (list (substring reference 0 colon)
                    (string-to-number (substring reference (1+ colon))))
              references)
        (setq text (substring text end))))
    (nreverse references)))

(defun yeah-diagram--reference-defect (root file line)
  "Return the defect of the reference FILE:LINE in the tree at ROOT, or nil.
A reference of a `.el' file must point at a line that carries a
definition: a name of the picture is a name of the code, and a line
that carries no definition names no code.  A reference of any other
file must point at a line that is there."
  (cond
   ((string-prefix-p "/" file)
    (format "the diagram names %s:%d, and a name of the diagram must be a path of this repository"
            file line))
   ((not (file-exists-p (expand-file-name file root)))
    (format "the diagram names %s:%d, and there is no such file" file line))
   ((not (file-readable-p (expand-file-name file root)))
    (format "the diagram names %s:%d, and the file cannot be read" file line))
   (t
    (let* ((content (yeah-diagram--lines-of (expand-file-name file root)))
           (count (car content))
           (lines (cdr content)))
      (cond
       ((or (< line 1) (> line count))
        (format "the diagram names %s:%d, and the file has %d line(s)" file line count))
       ((and (string-suffix-p ".el" file)
             (not (yeah-diagram--definition-p (nth (1- line) lines))))
        (format "the diagram names %s:%d, and that line carries no definition" file line))
       (t nil))))))

(defun yeah-diagram--says-p (lines word)
  "Return non-nil when one of LINES says WORD as a whole word.
The names of the files are taken out of the lines before the word is
looked for: the picture says `service placement', and the reference
`lib/yeah-service.el:127' is not the picture saying `service'.

The case matters: the picture says `ACP' and the word `acp' is not the
word `ACP'.  The search of Emacs folds the case by itself, and a folded
search would let a picture that says `Batch process' answer for the
word `batch'."
  (let ((pattern (concat "\\<" (regexp-quote word) "\\>")))
    (let ((case-fold-search nil))
      (cl-some
       (lambda (line)
         (string-match-p
          pattern
          (replace-regexp-in-string yeah-diagram--path-pattern " " line)))
       lines))))

(provide 'yeah-diagram-files)
;;; yeah-diagram-files.el ends here
