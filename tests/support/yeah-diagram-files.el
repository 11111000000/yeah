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
;;   block says: a block is a list (ALIAS REFERENCES TITLE), and the
;;   title is what the picture says about the block;
;; * `yeah-diagram--package-names' returns the names of the packages
;;   that the picture opens, and `yeah-diagram--packages' returns the
;;   packages with the text that stands in them;
;; * `yeah-diagram--note-lines' returns the lines of the note of the
;;   picture, `yeah-diagram--note-alias' returns the block the note
;;   hangs on, `yeah-diagram--notes' returns every note of the picture
;;   with the block it hangs on, and `yeah-diagram--exclusion' returns
;;   the module of `lib/' and the reason of one line of that note;
;; * `yeah-diagram--modules-of' walks `lib/' and returns the modules of
;;   the kernel, in every directory of it;
;; * `yeah-diagram--titles' returns the titles of the drawing: the
;;   quoted strings of the lines, split at the newlines that PlantUML
;;   writes as `\n'.  A title is what the picture says about a thing,
;;   and a word that is only in the body of a block is not the title
;;   of that block;
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

(defun yeah-diagram--comment-p (line &optional engine)
  "Return non-nil when LINE is a comment of the picture.
A comment of PlantUML begins with an apostrophe and a comment of D2
begins with a hash; a comment names nothing: the name of a file in a
comment of the picture is not a name of the code.

The engine is \"plantuml\" (the default) or \"d2\"."
  (if (equal engine "d2")
      (and (string-prefix-p "#" (string-trim line)) t)
    (and (string-match "\\`[[:space:]]*'" line) t)))

(defun yeah-diagram--engine-of (path)
  "Return the engine of the picture at PATH: \"plantuml\" or \"d2\".
The engine of a picture is the instrument that drew it: the source of a
picture of PlantUML is a \".puml\" file and the source of a picture of D2
is a \".d2\" file."
  (if (string-suffix-p ".d2" path) "d2" "plantuml"))

(defun yeah-diagram--d2-label-lines (label)
  "Return the lines of the label LABEL of a node of D2.
A label of D2 breaks its lines at the backslash-n that D2 reads as a line
break; a line that holds nothing is no line of the picture."
  (let (lines)
    (dolist (fragment (split-string label (regexp-quote "\\n") t))
      (unless (string-empty-p (string-trim fragment))
        (push (string-trim fragment) lines)))
    (nreverse lines)))

(defun yeah-diagram--reference-defect (root file line)
  "Return the defect of the reference FILE:LINE in the tree at ROOT, or nil.
A reference of a `.el' file must point at a line that carries a
definition: a name of the picture is a name of the code, and a line
that carries no definition names no code.  A reference of any other
file must point at a line that is there.

A reference never begins with a slash: the pattern of a reference begins
with a letter, a digit, a dot or a dash, and a name that begins
elsewhere is not a name of a file of this repository."
  (cond
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

(defun yeah-diagram--block-places (blocks words)
  "Return the places of the blocks of BLOCKS that name every word of WORDS.
The place of a block is its number in the list of the blocks, counted
from zero, and the places come in the order of the blocks.  A block
that names every word of a step is the block of that step, and a
picture in which the step is not in the picture has no place for it."
  (let (places)
    (let ((place 0))
      (dolist (block blocks)
        (when (yeah-diagram--names-all-p block words)
          (push place places))
        (setq place (1+ place))))
    (nreverse places)))

(defun yeah-diagram--words-text (words)
  "Return the words WORDS as the text of a list.
The list is read the way a person reads it: `scheduler and runs' and
`model, proposes and call'.  The words are the words of the picture,
and the text names them for the reader of a refusal."
  (if (= 1 (length words))
      (car words)
    (concat (mapconcat #'identity (butlast words) ", ") " and " (car (last words)))))

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

(defconst yeah-diagram--d2-attributes
  '("class" "label" "style" "shape" "icon" "tooltip" "near" "width" "height"
    "constraint" "link" "url" "pattern" "multiple")
  "The attributes of a node of D2.
A line that names an attribute is not a node of the picture: the label of a
connection and the class of a connection are the words of the connection,
and a picture that names the label of a connection says nothing about a
node.")

(defun yeah-diagram--d2-block (line)
  "Return the block of the node of D2 in LINE, or nil.
A block is a list (KEY LABEL BODY): the name of the node, the text of its
label and non-nil when the node opens a body.  A node of D2 is a line of
the form key: label, and a band of the picture is a node that opens a body
after its label."
  (when (string-match
         "^[ \t]*\\([A-Za-z0-9_.-]+\\)[ \t]*:[ \t]*\"\\([^\"]*\\)\"\\(.*\\)$"
         line)
    (let ((key (match-string 1 line)))
      (unless (member key yeah-diagram--d2-attributes)
        (list key
              (match-string 2 line)
              (and (string-match "[ \t]*{[ \t]*$" (match-string 3 line)) t))))))

(defun yeah-diagram--d2-blocks (text)
  "Return the blocks of the picture of D2 in TEXT.
A block is a list (KEY LABEL REFERENCES BODY): the name of the node, the text of
its label, the names of the files that the label carries and non-nil when
the node opens a body: a node that opens a body is a band of the picture
and names no file of its own.  The comment
of the picture names nothing: a name in a comment is not a claim of the
picture."
  (let (blocks)
    (dolist (line (split-string text "\n" t))
      (unless (yeah-diagram--comment-p line "d2")
        (let ((block (yeah-diagram--d2-block line)))
          (when block
            (push (list (nth 0 block)
                        (nth 1 block)
                        (yeah-diagram--references-in-line (nth 1 block))
                        (nth 2 block))
                  blocks)))))
    (nreverse blocks)))

(defun yeah-diagram--d2-groups (text)
  "Return the names of the bands of the picture of D2 in TEXT.
A band is a node that opens a body: the picture holds the shapes of the
band inside it, and the name of the band is what the picture says about
them."
  (let (names)
    (dolist (line (split-string text "\n" t))
      (unless (yeah-diagram--comment-p line "d2")
        (let ((block (yeah-diagram--d2-block line)))
          (when (and block (nth 2 block))
            (push (nth 1 block) names)))))
    (nreverse names)))

(defun yeah-diagram--d2-drawing-lines (text)
  "Return the lines of the drawing of the picture of D2 in TEXT.
A line of the drawing is a line of a label of a node of the picture: the
comment of the picture is not a line of the drawing, and a word that is
only in the comment is not a claim of the picture."
  (let (lines)
    (dolist (block (yeah-diagram--d2-blocks text))
      (dolist (line (yeah-diagram--d2-label-lines (nth 1 block)))
        (push line lines)))
    (nreverse lines)))

(defun yeah-diagram--module-name-p (name)
  "Return non-nil when NAME is the name of a module of the kernel.
A name of a module is a path of the tree: a run of names of the files and
of the directories, and the names hold letters, digits, dots, dashes and
underscores.  A name with a space in it is a phrase, and a phrase is not a
module."
  (and (string-match "^[A-Za-z0-9._-]+\\(/[A-Za-z0-9._-]+\\)*$" name) t))

(defun yeah-diagram--declaration-package-p (line)
  "Return non-nil when LINE declares a package of the kernel.
A declaration of a package is the name of the package, a colon and the
modules of it, and the modules are the names of the modules of the kernel:
the prose of the comment of the picture speaks of packages too, and the prose
is not a declaration."
  (let ((colon (string-search ": " line)))
    (and colon
         (let ((rest (string-trim (substring line (+ colon 2)))))
           (and (not (string-empty-p rest))
                (cl-every (lambda (name)
                           (yeah-diagram--module-name-p (string-trim name)))
                         (split-string rest ", " t)))))))

(defun yeah-diagram--declaration-exclusion-p (line)
  "Return non-nil when LINE excludes a module of the kernel.
An exclusion is the name of a module and the reason why it is in no
package of the picture."
  (and (string-match "^[A-Za-z0-9._-]+\\(/[A-Za-z0-9._-]+\\)* -- " line) t))

(defun yeah-diagram--d2-declaration (text)
  "Return the lines of the declaration of the picture of D2 in TEXT.
A declaration is a comment of the picture that names the packages of the
kernel and the modules of each, or a module that is in no package.  The
declaration is where the picture says what it is made of; the picture itself
shows the shape."
  (let (lines)
    (dolist (line (split-string text "\n" t))
      (when (yeah-diagram--comment-p line "d2")
        (let ((trimmed (string-trim (string-trim (string-trim line) "#"))))
          (when (or (yeah-diagram--declaration-package-p trimmed)
                    (yeah-diagram--declaration-exclusion-p trimmed))
            (push trimmed lines)))))
    (nreverse lines)))

(defun yeah-diagram--requires-of (root)
  "Return the requires of the modules of the tree at ROOT.
The answer is a list of (MODULE REQUIREMENT): the module that asks and the
module that is asked for.  The requires of the tree are the edges of the
graph of the packages."
  (let (requires)
    (dolist (module (yeah-diagram--modules-of root))
      (with-temp-buffer
        (insert-file-contents (expand-file-name module root))
        (dolist (line (split-string (buffer-string) "\n" t))
          (when (string-match "require[ \t]+'?\\([A-Za-z0-9._-]+\\)" line)
            (push (list (file-name-base module) (match-string 1 line)) requires)))))
    (nreverse requires)))

(defun yeah-diagram--d2-note (text)
  "Return the lines of the note of the picture of D2 in TEXT, or nil.
A note is a node whose name is note: the picture holds it as a block of
its own, and the text of the note is its label."
  (let ((note nil))
    (dolist (line (split-string text "\n" t))
      (unless (yeah-diagram--comment-p line "d2")
        (let ((block (yeah-diagram--d2-block line)))
          (when (and block (string= (nth 0 block) "note"))
            (setq note (yeah-diagram--d2-label-lines (nth 1 block)))))))
    note))

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

(defun yeah-diagram--titles (text)
  "Return the titles of the drawing of the diagram in TEXT.
A title is a quoted string of a line of the picture, and a title of
several lines is split at the newlines that PlantUML writes as `\\n',
exactly as `yeah-diagram--drawing-lines' splits a title of the drawing.

The comment of the diagram is not a line of the drawing: a title that
is only in the comment is not a title of the picture."
  (let (titles)
    (dolist (line (split-string text "\n" t))
      (unless (yeah-diagram--comment-p line)
        (dolist (string (yeah-diagram--strings line))
          (dolist (fragment (split-string string (regexp-quote "\\n") t))
            (unless (string-empty-p (string-trim fragment))
              (push (string-trim fragment) titles))))))
    (nreverse titles)))

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

(defun yeah-diagram--references (text &optional engine)
  "Return the references of the drawing of the diagram in TEXT.
A reference is a path of this repository and the number of a line of
it.  The comment of the diagram names nothing: the name of a file in
the comment of the picture is not a name of the code."
  (let (references)
    (dolist (line (split-string text "\n" t))
      (unless (yeah-diagram--comment-p line engine)
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

(defun yeah-diagram--places (text &optional engine)
  "Return the names of the places of the drawing of the diagram in TEXT.
A place is named with a line or without one: the line of a place is the
line of its definition, and a picture that names a directory names it
without a line.  The comment of the diagram names nothing: the name of a
place in the comment of the picture is not a name of the code."
  (let (places)
    (dolist (line (split-string text "\n" t))
      (unless (yeah-diagram--comment-p line engine)
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
is a dead end for the reader of the picture.

A place never begins with a slash: the pattern of a place begins with a
letter, a digit, a dot or a dash, and a name that begins elsewhere is not
a name of a place."
  (cond
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
A block is a list (ALIAS REFERENCES TITLE): the alias of the block, the
references that the block carries and the title of the block.  A block is
a line of the form `component \"TITLE\" as ALIAS'; the title is a text of
the picture and the alias is its name, and the references of the block
are the references of the line that carries it."
  (let (blocks)
    (dolist (line (split-string text "\n" t))
      (unless (yeah-diagram--comment-p line)
        (when (string-match
               "\\`[[:space:]]*component[[:space:]]+\".*\"[[:space:]]+as[[:space:]]+\\([^[:space:]]+\\)[[:space:]]*\\'"
               line)
          (push (list (match-string 1 line)
                      (yeah-diagram--references-in-line line)
                      (car (yeah-diagram--strings line)))
                blocks))))
    (nreverse blocks)))

(defconst yeah-diagram--package-pattern
  "\\`[[:space:]]*package[[:space:]]+\"\\([^\"]*\\)\"[[:space:]]+as[[:space:]]+\\([^[:space:]]+\\)[[:space:]]*{\\'"
  "The pattern of a package of a picture.
A package is a line of the form `package \"NAME\" as alias {': the title of
the package is its name and the alias is the name the picture uses for it.
The group of the alias is not read by the rules of the reader: the name of
a package is what the picture says about it.")

(defun yeah-diagram--package-names (text)
  "Return the names of the packages that the picture in TEXT opens.
A package that is never closed is a package of the picture all the same:
the count is the count of the lines that open a package."
  (let (names)
    (dolist (line (split-string text "\n" t))
      (when (string-match yeah-diagram--package-pattern line)
        (push (match-string 1 line) names)))
    (nreverse names)))

(defun yeah-diagram--packages (text)
  "Return the packages of the picture in TEXT.
A package is a list (NAME BODY): the name of the package and the text of
the lines that stand in it.  The braces are counted, so the lines that
stand outside of a package -- the note at the end -- are the lines of no
package, and a package that is never closed has no body of its own."
  (let (stack packages)
    (dolist (line (split-string text "\n" t))
      (cond
       ((string-match yeah-diagram--package-pattern line)
        (push (list (match-string 1 line) "") stack))
       ((and stack (string-match "\\`[[:space:]]*}" line))
        (push (pop stack) packages))
       (stack
        (setcdr (car stack) (list (concat (nth 1 (car stack)) "\n" line))))))
    (nreverse packages)))

(defun yeah-diagram--note-lines (text)
  "Return the lines of the note of the picture in TEXT.
The note opens with a line that begins with `note' and closes with a line
that is `end note'.  The lines before the note and the lines after it are
not the lines of the note."
  (let (lines in-note)
    (dolist (line (split-string text "\n" t))
      (cond
       ((string-match "\\`[[:space:]]*note\\b" line)
        (setq in-note t))
       ((and in-note (string-match "\\`[[:space:]]*end note\\'" line))
        (setq in-note nil))
       (in-note (push line lines))))
    (nreverse lines)))

(defun yeah-diagram--note-alias (text)
  "Return the alias the note of the picture in TEXT hangs on, or nil.
The note opens with a line of the form `note bottom of ALIAS', and the
alias is the name of the block the note belongs to.  A note that hangs on
nothing names nothing, and the answer is nil.

The answer is the alias of the first note of the picture: a picture with
one note has one alias, and a picture with several notes has an alias
only for the first of them."
  (let (alias)
    (dolist (line (split-string text "\n" t))
      (unless alias
        (when (string-match
               "\\`[[:space:]]*note\\b.*\\bof[[:space:]]+\\([^[:space:]]+\\)"
               line)
          (setq alias (match-string 1 line)))))
    alias))

(defun yeah-diagram--notes (text)
  "Return the notes of the picture in TEXT.
Every note is a list (ALIAS LINES): the block the note hangs on -- nil
when it hangs on nothing -- and the lines of the note.  The notes come
in the order of the picture, and a picture with one note has one entry
here and a picture with several notes has one entry for each of them.

The lines of a note are the lines between the line that opens it and
the line that closes it: the line that opens the note is not a line of
it, and the line that closes it is not a line of it either.

One note and the alias of one note are two different things, and a
check that measures a note measures the note it means: the words of one
note and the block of another note are the words of one thing and the
name of another one."
  (let (notes in-note alias lines)
    (dolist (line (split-string text "\n" t))
      (cond
       ((string-match "\\`[[:space:]]*note\\b" line)
        (when in-note
          (push (list alias (nreverse lines)) notes))
        (setq in-note t
              lines nil
              alias (if (string-match
                         "\\`[[:space:]]*note\\b.*\\bof[[:space:]]+\\([^[:space:]]+\\)"
                         line)
                        (match-string 1 line)
                      nil)))
       ((and in-note (string-match "\\`[[:space:]]*end note\\'" line))
        (push (list alias (nreverse lines)) notes)
        (setq in-note nil lines nil alias nil))
       (in-note (push line lines))))
    (when in-note
      (push (list alias (nreverse lines)) notes))
    (nreverse notes)))

(defun yeah-diagram--exclusion (line)
  "Return the exclusion of LINE, or nil.
An exclusion is a list (MODULE REASON): a module of `lib/' and the reason
why the picture does not name it.  The reason of an exclusion may be
nothing: the check then says that the note names a module and says nothing
about it."
  (when (string-match "\\`[[:space:]]*\\(lib/[A-Za-z0-9._-]+\\.el\\)\\b" line)
    (let ((module (match-string 1 line)))
      (if (string-match "--[[:space:]]*\\(.*\\)\\'" line)
          (list module (string-trim (match-string 1 line)))
        (list module nil)))))

(defun yeah-diagram--modules-of (root)
  "Return the modules of `lib/' of the tree at ROOT.
Every directory of `lib/' is walked: a module in a subdirectory of `lib/'
is a module of the kernel as well.  The answer holds the paths of the
modules relative to the root of the tree, and the paths come in the order
of their names."
  (sort (mapcar (lambda (module) (file-relative-name module root))
                (directory-files-recursively (expand-file-name "lib" root)
                                             "\\.el\\'"))
        #'string<))

(provide 'yeah-diagram-files)
;;; yeah-diagram-files.el ends here
