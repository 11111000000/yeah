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
;; The reader answers these things:
;;
;; * `yeah-diagram--text' reads the file;
;; * `yeah-diagram--lines-of' counts the lines of a file and keeps the
;;   empty ones, because the number of a line is the place of it;
;; * `yeah-diagram--drawing-lines' returns the lines of the *drawing*:
;;   a quoted title is split at the newlines that PlantUML writes as
;;   `\n', and the comment of the diagram is not a line of the drawing
;;   -- a word that is only in the comment is not a claim of the
;;   picture;
;; * `yeah-diagram--references' returns every name of the form
;;   `file:line' of the drawing, and `yeah-diagram--reference-defect'
;;   says what is wrong with such a name;
;; * `yeah-diagram--places' returns every name of a place of the tree that
;;   the drawing carries -- a directory of the tests or a file of `lib/',
;;   with a line or without one -- and `yeah-diagram--place-defect' says
;;   what is wrong with such a name;
;; * `yeah-diagram--without-places' returns a line without the names of
;;   the places, because the name of a place is not a word of the picture;
;; * `yeah-diagram--components' returns the blocks of the picture that
;;   carry a name of their own, so that a check can ask what a named
;;   block says;
;; * `yeah-diagram--says-p' says whether the drawing says a word, and
;;   `yeah-diagram--names-all-p' says whether one line of the drawing
;;   names every one of a list of names.
;;
;; The tree of the repository is never written: this reader only reads.

;;; Code:

(require 'cl-lib)

(defconst yeah-diagram--reference-pattern
  "[A-Za-z0-9._][A-Za-z0-9._/-]*\\.[A-Za-z0-9]+:[0-9]+"
  "The pattern of a name of the form `file:line' in a diagram.")

(defconst yeah-diagram--path-pattern
  "[A-Za-z0-9._-][A-Za-z0-9._/-]*\\.[A-Za-z0-9]+\\(:[0-9]+\\)?"
  "The pattern of a name of a file in a diagram, with a line or without.
The number of the line is a shy group: in the regexp of Emacs a parenthesis
without a backslash in front of it is a literal character and not a group,
and a group of a literal parenthesis matches no name of a file at all.")

(defun yeah-diagram--root ()
  "Return the root of the project."
  (expand-file-name default-directory))

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
A definition is the opening of a `defun', a `defvar', a `defconst',
a `cl-defun' or a `cl-defstruct': the name of a thing the picture names
is a name of the code, and a line that carries code and no definition
names no definition.  An empty line carries no code, and a line that
holds nothing but a comment carries no code either."
  (let ((trimmed (string-trim text)))
    (and (not (string-empty-p trimmed))
         (string-match yeah-diagram--definition-pattern trimmed))))

(defun yeah-diagram--comment-p (line)
  "Return non-nil when LINE is a comment of PlantUML.
A comment of PlantUML begins with an apostrophe, and a comment names
nothing: the name of a file in a comment of the picture is not a name
of the code."
  (and (string-match "\\`[[:space:]]*'" line) t))

(defun yeah-diagram--strings (line)
  "Return the quoted strings of LINE."
  (let (strings)
    (while (string-match "\"\\([^\"]*\\)\"" line)
      (push (match-string 1 line) strings)
      (setq line (substring line (match-end 0))))
    (nreverse strings)))

(defun yeah-diagram--drawing-lines (text)
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
      (unless (yeah-diagram--comment-p line)
        (let ((strings (yeah-diagram--strings line)))
          (if strings
              (dolist (string strings)
                (dolist (fragment (split-string string (regexp-quote "\\n") t))
                  (unless (string-empty-p (string-trim fragment))
                    (push (string-trim fragment) lines))))
            (push (string-trim line) lines)))))
    (nreverse lines)))

(defun yeah-diagram--blocks (text)
  "Return the blocks of the drawing of the diagram in TEXT.
A block is a step of the picture: a line of the drawing that begins with a
colon.  The answer is the text of the block, and the words of the text are
the words of the step: a step of the turn that the picture does not name is
a step the reader of the picture does not see."
  (let (blocks)
    (dolist (line (yeah-diagram--drawing-lines text))
      (when (string-match "\\`:[[:space:]]*\\(.*\\)[[:space:]]*\\'" line)
        (let ((body (match-string 1 line)))
          (when (string-suffix-p ";" body)
            (setq body (substring body 0 -1)))
          (push body blocks))))
    (nreverse blocks)))

(defun yeah-diagram--references-in-line (line)
  "Return the references of LINE.
The newlines that PlantUML writes inside a title as `\\n' are read as
the line breaks they are: the path of a reference that follows such a
newline begins at the beginning of a line, and not in the middle of the
word `\\n'."
  (let ((text (replace-regexp-in-string "\\\\n" "\n" line))
        references)
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

(defun yeah-diagram--references (text)
  "Return the references of the drawing of the diagram in TEXT.
A reference is a path of this repository and the number of a line of
it.  The comment of the diagram names nothing: the name of a file in
the comment of the picture is not a name of the code."
  (let (references)
    (dolist (line (split-string text "\n" t))
      (unless (yeah-diagram--comment-p line)
        (setq references (append references
                                 (yeah-diagram--references-in-line line)))))
    (nreverse references)))

(defconst yeah-diagram--place-pattern
  "[A-Za-z0-9._-]+\\(?:[/.][A-Za-z0-9._-]+\\)+"
  "The pattern of a name of a place in a diagram.
A place is a run of words with a slash or a dot in it: the directories of the
tests and the files of `lib/' are places, and the name of a level is a word
of its own.")

(defun yeah-diagram--trim-dots (name)
  "Return NAME without the dots at its end.
The dot that ends a sentence is not a part of the name of the place, and a
name of a file that ends with a dot is not a file."
  (replace-regexp-in-string "\\.+\\'" "" name))

(defun yeah-diagram--places-in-line (line)
  "Return the names of the places of LINE.
The newlines that PlantUML writes inside a title as `\\n' are read as the
line breaks they are: the path of a place that follows such a newline begins
at the beginning of a line, and not in the middle of the word `\\n'."
  (let ((text (replace-regexp-in-string "\\\\n" "\n" line))
        places)
    (while (string-match yeah-diagram--place-pattern text)
      (push (yeah-diagram--trim-dots (match-string 0 text)) places)
      (setq text (substring text (match-end 0))))
    (nreverse places)))

(defun yeah-diagram--places (text)
  "Return the names of the places of the drawing of the diagram in TEXT.
A place is named with a line or without one: the line of a place is the
line of its definition, and a picture that names a directory names it
without a line.  The comment of the diagram names nothing: the name of a
place in the comment of the picture is not a name of the code."
  (let (places)
    (dolist (line (split-string text "\n" t))
      (unless (yeah-diagram--comment-p line)
        (setq places (append places (yeah-diagram--places-in-line line)))))
    (delete-dups places)))

(defun yeah-diagram--root-entries (root)
  "Return the names of the entries at the root of the tree at ROOT.
The hidden entries are not entries of the project: the dot before the name
of a file is a habit of a person and not a place of the repository."
  (let (entries)
    (dolist (entry (directory-files root nil "\\`[^.]" t))
      (push (file-name-nondirectory entry) entries))
    (nreverse entries)))

(defun yeah-diagram--place-p (root place)
  "Return non-nil when PLACE is a place of the tree at ROOT.
A place of the repository begins where the repository begins: the first
segment of the name of a place is an entry at the root of the tree.  The
name of a place that begins elsewhere is not a name of a place -- the
picture of the scheduler says `shared/exclusive' about the scheduler, and
that is a word of the picture and not a path."
  (let ((segments (split-string place "/")))
    (and segments
         (member (car segments) (yeah-diagram--root-entries root)))))

(defun yeah-diagram--place-defect (root place)
  "Return the defect of the place PLACE in the tree at ROOT, or nil.
A place of the repository must be there: a name that nobody wrote any more
is a dead end for the reader of the picture."
  (cond
   ((string-prefix-p "/" place)
    (format "the diagram names the place %s, and a name of the diagram must be a path of this repository"
            place))
   ((not (yeah-diagram--place-p root place))
    nil)
   ((not (file-exists-p (expand-file-name place root)))
    (format "the diagram names the place %s, and there is no such place in the tree"
            place))
   (t nil)))

(defun yeah-diagram--without-places (line)
  "Return LINE without the names of the places.
The name of a place is not a word of the picture: the word `unit' of
`tests/unit' says where the level lives and not what the level is."
  (replace-regexp-in-string yeah-diagram--place-pattern " " line))

(defun yeah-diagram--components (text)
  "Return the blocks of the diagram in TEXT.
A block is a list (ALIAS REFERENCES): the alias of the block and the
references that the block carries.  A block is a line of the form
`component \"TITLE\" as ALIAS'; the title is a text of the picture and
the alias is its name, and the references of the block are the
references of the line that carries it."
  (let (blocks)
    (dolist (line (split-string text "\n" t))
      (unless (yeah-diagram--comment-p line)
        (when (string-match
               "\\`[[:space:]]*component[[:space:]]+\".*\"[[:space:]]+as[[:space:]]+\\([^[:space:]]+\\)[[:space:]]*\\'"
               line)
          (push (list (match-string 1 line)
                      (yeah-diagram--references-in-line line))
                blocks))))
    (nreverse blocks)))

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

(defun yeah-diagram--broken-references (root references)
  "Return the references of REFERENCES that point at nothing, with the reason.
ROOT is the root of the project.  The answer is a list of (REFERENCE
REASON), and the reason says what the reference misses."
  (let (broken)
    (dolist (reference references)
      (let ((defect (yeah-diagram--reference-defect root
                                               (nth 0 reference)
                                               (nth 1 reference))))
        (when defect
          (push (list reference defect) broken))))
    (nreverse broken)))

(defun yeah-diagram--words (line)
  "Return the words of LINE.
A word is a run of letters and digits: the colon that stands in front of
a name of an answer is not a part of the word, and the word `project' is
not the word `projection'.
The name of a file is not a word of the picture: the word `service' of
`lib/yeah-service.el:127' says where the code is and not what the picture
says."
  (split-string (string-trim (replace-regexp-in-string yeah-diagram--path-pattern " " line))
                "[^A-Za-z0-9]+" t))

(defun yeah-diagram--names-all-p (line names)
  "Return non-nil when LINE names every one of NAMES.
A name is named by the line when the line has a word that is the name.
The names are compared as words and not as pieces of text: the word
`project' is not found in the word `projection'.  The case matters: the
word `ACP' is not the word `acp'."
  (let ((words (yeah-diagram--words line)))
    (let ((case-fold-search nil))
      (cl-every (lambda (name) (member name words)) names))))

(defconst yeah-diagram--answers
  '("once" "session" "project" "global" "reject")
  "The answers the person may give to a request for permission.
Every picture that shows the person answering names the same five answers,
and the list of them lives here and not in a check of a picture.")

(defun yeah-diagram--answers-p (lines)
  "Return non-nil when one of LINES names every answer of the person."
  (cl-some (lambda (line) (yeah-diagram--names-all-p line yeah-diagram--answers))
           lines))

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
