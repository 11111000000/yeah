;;; check-every-diagram-points-at-files-that-exist.el --- every diagram of the site points at what is there -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The pictures of the site are written by hand, and every picture names
;; the files of the kernel that hold what the picture says, as
;; `file:line'.  A name that nobody wrote any more is a dead end for the
;; reader: the picture says what the code is made of, and the file it
;; names is not there.
;;
;; One check of one picture reads one picture.  This check reads the whole
;; catalogue of the pictures of the site, so that a picture that is added
;; later is covered by the rule and not by a new list of names.
;;
;; This check walks `site/diagrams/' -- every directory of it -- and
;; measures four things for every picture it finds there:
;;
;;   1. the picture is a picture of PlantUML and its name is the name of
;;      its file: the first line of the drawing is `@startuml NAME', where
;;      NAME is the name of the file without `.puml', and the last line is
;;      `@enduml'.  The names of the pictures are a rule and not a list
;;      (`docs/SITE-DIAGRAMS-PLAN.md' §7.1);
;;   2. the picture says something: it holds at least one line of the
;;      drawing that says what it holds.  A comment says nothing, an empty
;;      line says nothing, a `skinparam' is the skin of a theme and not a
;;      part of the picture, and a line that holds nothing but the
;;      `@startuml' or the `@enduml' says that the picture begins and
;;      ends;
;;   3. every reference of the form `file:line' points at a file of this
;;      repository, at a line of that file and -- for a file of Elisp --
;;      at a line that carries a definition: an empty line names no
;;      code, a line that holds nothing but a comment names no code
;;      either, and a line that holds code that is not a definition names
;;      no definition;
;;   4. the picture names at least one place of the repository, so that
;;      there is a name to follow, and every place it names is there in
;;      the tree.  A place is named with a line or without one: a picture
;;      that shows where the levels of the verification live names the
;;      directories of the tests and not the lines of their files.  The
;;      machine of the states is the one exception of this rule: it is
;;      written out of the code by `lib/yeah-state-diagram.el', and its
;;      truth is there and not in a reference of the picture.  The
;;      exception is the picture at `site/diagrams/state-machine.puml'
;;      and not every picture that carries that name, and it is named in
;;      the code of this check, and the check asks for the generator of
;;      the picture to be there, so that the exception cannot outlive its
;;      reason.
;;
;; The pictures of the skins of the themes (`palette-*') are not pictures
;; of the site: the pipeline does not draw them, and they name no file.
;;
;; The rule of the reference is the rule of every picture of the site and
;; it lives in one place: `tests/support/yeah-diagram-files.el'.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- every picture of the site points at what is there;
;; 1 -- a picture points at something that is not there, or says nothing
;; at all; 2 -- the tree is not where we think, and the check cannot
;; answer.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--blockers nil
  "The reasons why this check cannot answer.")

(defconst yeah-check--generated-diagrams
  '(("site/diagrams/state-machine.puml" "lib/yeah-state-diagram.el"))
  "The pictures that the code writes out, and the generator of each.
The machine of the states of the kernel is not drawn by hand: the code
of `lib/yeah-state-diagram.el' reads the tables of the kernel and writes
the picture out of them.  A picture that the code writes names no file of
the repository, and this is the one exception of the rule of the fourth
measurement.

The exception is the path of the picture and not the name of its file:
the machine of the states is at `site/diagrams/state-machine.puml', and a
picture that carries that name in a subdirectory of the tree of the
pictures is a picture of a person and not the machine of the states.")

(defun yeah-check--substantive-p (line)
  "Return non-nil when LINE of a drawing says something.
A comment is not a line of the drawing and the reader drops those.  An
empty line says nothing, a `skinparam' is the skin of a theme and not a
part of the picture, and a line that holds nothing but the `@startuml' or
the `@enduml' says that the picture begins and ends."
  (let ((trimmed (string-trim line)))
    (and (not (string-empty-p trimmed))
         (not (string-match "\\`skinparam\\([ \t]\\|$\\)" trimmed))
         (not (string-match "\\`@" trimmed)))))

(defun yeah-check--generated-p (path)
  "Return non-nil when the picture at PATH is written out of the code.
PATH is the path of the picture relative to the root of the tree."
  (cl-some (lambda (entry) (string= path (nth 0 entry)))
           yeah-check--generated-diagrams))

(defun yeah-check--measure (root path)
  "Measure the picture at PATH against the tree at ROOT.
The failures are pushed onto `yeah-check--failures', and the number of
the references and of the places the picture names is returned."
  (let* ((name (file-relative-name path root))
         (base (file-name-base path))
         (engine (yeah-diagram--engine-of path))
         (text (yeah-diagram--text path))
         (lines (if (equal engine "d2")
                    (yeah-diagram--d2-drawing-lines text)
                  (yeah-diagram--drawing-lines text)))
         (references (yeah-diagram--references text engine))
         (places (cl-remove-if-not (lambda (place) (yeah-diagram--place-p root place))
                                   (yeah-diagram--places text)))
         (first (string-trim (or (car lines) "")))
         (last (string-trim (or (car (last lines)) ""))))
    ;; 1. the picture is a picture of its engine, and the picture of
    ;;    PlantUML is named after its file.
    (if (equal engine "d2")
        (unless (yeah-diagram--d2-blocks text)
          (push (format "the picture %s holds no node: it is no picture of the site"
                        name)
                yeah-check--failures))
      (progn
        (unless (string= first (format "@startuml %s" base))
          (push (format "the picture %s starts with %S, and the first line of a picture of the site is `@startuml %s'"
                        name first base)
                yeah-check--failures))
        (unless (string= last "@enduml")
          (push (format "the picture %s ends with %S, and the last line of a picture of the site is `@enduml'"
                        name last)
                yeah-check--failures))))
    ;; 2. the picture says something.
    (unless (cl-some #'yeah-check--substantive-p lines)
      (push (format "the picture %s says nothing: it holds no line that says what it holds"
                    name)
            yeah-check--failures))
    ;; 3. every reference points at a file, at a line, and at a definition.
    (dolist (broken (yeah-diagram--broken-references root references))
      (push (format "the picture %s: %s" name (nth 1 broken))
            yeah-check--failures))
    ;; 4. the picture names a place of the repository, and every place it
    ;;    names is there.
    (dolist (place places)
      (let ((defect (yeah-diagram--place-defect root place)))
        (when defect
          (push (format "the picture %s: %s" name defect)
                yeah-check--failures))))
    (unless (or places
                (yeah-check--generated-p name))
      (push (format "the picture %s names no place of the repository, and a picture of the site must name at least one place of the tree"
                    name)
            yeah-check--failures))
    (cons (length references) (length places))))

(let* ((root (expand-file-name default-directory))
       (reader (expand-file-name "tests/support/yeah-diagram-files.el" root))
       (pictures (expand-file-name "site/diagrams" root))
       (paths (sort (directory-files-recursively pictures "\\.puml\\'\\|\\.d2\\'") #'string<))
       (measured (delq nil
                        (mapcar (lambda (path)
                                  (unless (string-prefix-p "palette-"
                                                        (file-name-nondirectory path))
                                    path))
                                paths))))
  (unless (file-directory-p (expand-file-name "lib" root))
    (push "the tree of the repository is not where we think: there is no lib/"
          yeah-check--blockers))
  (unless (file-directory-p pictures)
    (push "the tree of the repository is not where we think: there is no site/diagrams/"
          yeah-check--blockers))
  (unless (file-readable-p reader)
    (push "the tree of the repository is not where we think: there is no tests/support/yeah-diagram-files.el"
          yeah-check--blockers))
  (when (null yeah-check--blockers)
    (load reader nil t)
    (when (null measured)
      (push "site/diagrams/ holds no picture of the site: this check has nothing to measure"
            yeah-check--blockers))
    (when (null yeah-check--blockers)
      ;; The exception of the rule does not outlive its reason: the code
      ;; that writes a picture out is there.
      (dolist (entry yeah-check--generated-diagrams)
        (let ((generator (nth 1 entry)))
          (unless (file-exists-p (expand-file-name generator root))
            (push (format "the picture %s is exempt from the rule of naming a file, and the generator %s is not there"
                          (nth 0 entry) generator)
                  yeah-check--failures))))
      (let* ((counts (mapcar (lambda (path) (yeah-check--measure root path)) measured))
             (references (cl-reduce #'+ (mapcar #'car counts) :initial-value 0))
             (places (cl-reduce #'+ (mapcar #'cdr counts) :initial-value 0)))
        (dolist (failure yeah-check--failures)
          (message "every-diagram: %s" failure))
        (if yeah-check--failures
            (kill-emacs 1)
          (message "every-diagram: %d picture(s) of site/diagrams/ measured, %d reference(s) and %d place(s) followed"
                   (length measured) references places)
          (kill-emacs 0)))))
  (when yeah-check--blockers
    (dolist (blocker yeah-check--blockers)
      (message "every-diagram: %s" blocker))
    (kill-emacs 2)))

;;; check-every-diagram-points-at-files-that-exist.el ends here
