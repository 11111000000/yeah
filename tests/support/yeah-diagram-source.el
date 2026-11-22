;;; yeah-diagram-source.el --- the reader of the sources of the diagrams -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The sources of the diagrams of the site are written by hand, and every
;; block of them names the files of the kernel that implement the block, as
;; `file:line'.  A name that nobody wrote any more is a dead end for the
;; reader: the block says what it is made of, and the file it names is not
;; there.
;;
;; The rule of the reference is the same for every diagram, so it lives
;; here and not in the checks: a reference names a file of this repository
;; and the number of a line of it, and that line carries a definition --
;; an empty line names no code, a line that holds nothing but a comment
;; names no code either, and a line that holds code that is not a
;; definition names no definition.
;;
;; The file is loaded, not required: a check that loads it decides where
;; the tree is first, and the tree is what the path of this file is
;; relative to.

;;; Code:

(defun yeah-diagram--root ()
  "Return the root of the project."
  (expand-file-name default-directory))

(defun yeah-diagram--text (path)
  "Return the text of the file at PATH."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(defun yeah-diagram--lines (path)
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

(defun yeah-diagram--content-lines (text)
  "Return the lines of TEXT without the empty lines at its end.
The first line of the answer is the first line of the text and the last
line is the last line that carries something: the newline that ends the
file does not open a line of its own."
  (let ((lines (split-string text "\n")))
    (while (and lines (string-empty-p (string-trim (car (last lines)))))
      (setq lines (butlast lines)))
    lines))

(defun yeah-diagram--definition-p (text)
  "Return non-nil when TEXT carries a definition.
A definition is the opening of a `defun', a `defconst', a `cl-defun' or a
`cl-defstruct': the name of the thing the block of the picture names is a
name of the code, and a line that carries code and no definition names no
definition.  An empty line carries no code, and a line that holds nothing
but a comment carries no code either."
  (let ((trimmed (string-trim text)))
    (and (not (string-empty-p trimmed))
         (string-match "\\`[(]\\(cl-\\)?def[a-z-]+[ \t(]" trimmed))))

(defun yeah-diagram--comment-p (line)
  "Return non-nil when LINE is a comment of PlantUML.
A comment of PlantUML begins with an apostrophe, and a comment names
nothing: the name of a file in a comment of the picture is not a name of
the code."
  (and (string-match "\\`[[:space:]]*'" line) t))

(defun yeah-diagram--references-in-line (line)
  "Return the references of LINE.
A reference is a path of this repository and the number of a line of it.
The path carries a slash: a name of a file of this repository is a path
in the tree, and `file:line' without a path names nothing of this
repository.

The escape `\\n' of the title of a block is cut before the references are
read: the `n' of the escape is a letter, and a path that follows the
escape would be read as a path that begins with that letter."
  (let ((text (replace-regexp-in-string "\\\\n" "\n" line))
        references)
    (while (string-match
            "\\(^\\|[^A-Za-z0-9._/-]\\)\\([A-Za-z0-9._-]+\\(/[A-Za-z0-9._-]+\\)+\\):\\([0-9]+\\)"
            text)
      (push (list (match-string 2 text)
                  (string-to-number (match-string 4 text)))
            references)
      (setq text (substring text (match-end 0))))
    (nreverse references)))

(defun yeah-diagram--references (text)
  "Return the references of the diagram in TEXT.
The references of the picture are the references of its blocks: a
comment names nothing, and the name of a file in a comment of the
picture is not a name of the code."
  (let (references)
    (dolist (line (split-string text "\n"))
      (unless (yeah-diagram--comment-p line)
        (setq references (append references
                                 (yeah-diagram--references-in-line line)))))
    references))

(defun yeah-diagram--components (text)
  "Return the blocks of the diagram in TEXT.
A block is a list (ALIAS REFERENCES): the alias of the block and the
references that the block carries.  A block is a line of the form
`component \"TITLE\" as ALIAS'; the title is a text of the picture and
the alias is its name, and the references of the block are the
references of the line that carries it."
  (let (blocks)
    (dolist (line (split-string text "\n"))
      (unless (yeah-diagram--comment-p line)
        (when (string-match
               "\\`[[:space:]]*component[[:space:]]+\".*\"[[:space:]]+as[[:space:]]+\\([^[:space:]]+\\)[[:space:]]*\\'"
               line)
          (push (list (match-string 1 line)
                      (yeah-diagram--references-in-line line))
                blocks))))
    (nreverse blocks)))

(defun yeah-diagram--words (line)
  "Return the words of LINE.
A word is a run of letters and digits: the colon that stands in front of
a name of an answer is not a part of the word, and the word `project' is
not the word `projection'."
  (split-string (string-trim line) "[^A-Za-z0-9]+" t))

(defun yeah-diagram--names-all-p (line names)
  "Return non-nil when LINE names every one of NAMES.
A name is named by the line when the line has a word that is the name.
The names are compared as words and not as pieces of text: the word
`project' is not found in the word `projection'."
  (let ((words (yeah-diagram--words line)))
    (cl-every (lambda (name) (member name words)) names)))

(defun yeah-diagram--broken-references (root references)
  "Return the references of REFERENCES that point at nothing, with the reason.
ROOT is the root of the project.  Every reference must name a file of
this repository, a line of that file, and a line that carries a
definition.  The answer is a list of (REFERENCE REASON), and the reason
says which of the three the reference misses."
  (let (broken)
    (dolist (reference references)
      (let ((file (nth 0 reference))
            (line (nth 1 reference)))
        (cond
         ((string-prefix-p "/" file)
          (push (list reference
                      (format "%s:%d names a path outside of this repository"
                              file line))
                broken))
         ((not (file-exists-p (expand-file-name file root)))
          (push (list reference (format "%s:%d names a file that is not there"
                                        file line))
                broken))
         ((not (file-readable-p (expand-file-name file root)))
          (push (list reference (format "%s:%d names a file that cannot be read"
                                        file line))
                broken))
         (t
          (let* ((content (yeah-diagram--lines (expand-file-name file root)))
                 (count (car content))
                 (lines (cdr content)))
            (cond
             ((or (< line 1) (> line count))
              (push (list reference
                          (format "%s:%d names a line that the file does not have (it has %d line(s))"
                                  file line count))
                    broken))
             ((not (yeah-diagram--definition-p (nth (1- line) lines)))
              (push (list reference
                          (format "%s:%d names a line that carries no definition"
                                  file line))
                    broken))))))))
    (nreverse broken)))

;;; yeah-diagram-source.el ends here
