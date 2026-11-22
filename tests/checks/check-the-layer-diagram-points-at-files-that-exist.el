;;; check-the-layer-diagram-points-at-files-that-exist.el --- the layer diagram points at what is there -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The diagram of the layers of the core is written by hand, and every
;; block of it names the files of the kernel that implement the block.  A
;; name that nobody wrote any more is a dead end for the reader: the block
;; says what it is made of, and the file it names is not there.
;;
;; This check reads `site/diagrams/core-layers.puml' and follows every
;; name it finds.  It measures four things:
;;
;;   1. every reference of the form `file:line' points at a file of this
;;      repository, at a line of that file, and at a line that carries a
;;      definition -- an empty line names no code, a line that holds
;;      nothing but a comment names no code either, and a line that holds
;;      code that is not a definition names no definition;
;;   2. every module of `lib/' is named by the diagram or listed in the
;;      note of the modules the picture does not name, with the reason why
;;      it is not there.  A module that is nowhere is a module the picture
;;      dropped silently, and the reader of the picture cannot tell it
;;      from a module that was never there;
;;   3. the note names no module that is not there, names no module
;;      without a reason, and names no module that the diagram names as
;;      well -- a module that is both named and excluded is a module whose
;;      place in the picture is not decided;
;;   4. every block of the picture names at least one file, and the
;;      packages of the picture are all there: the drivers, the core, the
;;      journal and the projections.  A block without a file is a block of
;;      nothing, and a picture without a layer is a picture of a part.
;;
;; The rule of the reference, the rule of the definition and the rule of
;; the block live in one place: `tests/support/yeah-diagram-files.el'.  A
;; copy of the rule in this check is a rule that drifts away from the
;; rule of the other pictures of the site, and one picture that is read
;; two ways gives two verdicts for one picture.
;;
;; The format of the source is a rule of this check and not of PlantUML:
;; a package is `package "NAME" as alias {', the note of the modules the
;; picture does not name is a `note' whose lines are of the form
;; `lib/MODULE.el -- the reason'.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- the diagram points at what is there; 1 -- it points at
;; something that is not there, or it dropped a module of `lib/'; 2 -- the
;; tree is not where we think, and the check cannot answer.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--blockers nil
  "The reasons why this check cannot answer.")

(defun yeah-check--packages (text)
  "Return the names of the packages of the diagram in TEXT.
The reader of the pictures of the site has no rule of the package: the
package is a line of the form `package \"NAME\" as alias {'."
  (let (packages)
    (dolist (line (split-string text "\n" t))
      (when (string-match
             "\\`[[:space:]]*package[[:space:]]+\"\\([^\"]*\\)\"[[:space:]]+as[[:space:]]+\\([^[:space:]]+\\)[[:space:]]+{\\'"
             line)
        (push (match-string 1 line) packages)))
    (nreverse packages)))

(defun yeah-check--note (text)
  "Return the lines of the note of the modules the picture does not name."
  (let (lines in-note)
    (dolist (line (split-string text "\n" t))
      (cond ((string-match "\\`[[:space:]]*note\\b" line)
             (setq in-note t))
            ((and in-note (string-match "\\`[[:space:]]*end note\\'" line))
             (setq in-note nil))
            (in-note (push line lines))))
    (nreverse lines)))

(defun yeah-check--exclusion (line)
  "Return the exclusion of LINE, or nil.
An exclusion is a module of `lib/' and the reason why the picture does not
name it.  The reason of an exclusion may be nothing: the check then says
that the note names a module and says nothing about it."
  (when (string-match "\\`[[:space:]]*\\(lib/[A-Za-z0-9._-]+\\.el\\)\\b" line)
    (let ((module (match-string 1 line)))
      (if (string-match "--[[:space:]]*\\(.*\\)\\'" line)
          (list module (string-trim (match-string 1 line)))
        (list module nil)))))

(let* ((root (expand-file-name default-directory))
       (reader (expand-file-name "tests/support/yeah-diagram-files.el" root))
       (diagram (expand-file-name "site/diagrams/core-layers.puml" root)))
  (unless (file-directory-p (expand-file-name "lib" root))
    (push "the tree of the repository is not where we think: there is no lib/" yeah-check--blockers))
  (unless (file-readable-p diagram)
    (push "the tree of the repository is not where we think: there is no site/diagrams/core-layers.puml"
          yeah-check--blockers))
  (unless (file-readable-p reader)
    (push "the tree of the repository is not where we think: there is no tests/support/yeah-diagram-files.el"
          yeah-check--blockers))
  (when (null yeah-check--blockers)
    (load reader nil t)
    (let* ((text (yeah-diagram--text diagram))
           (packages (yeah-check--packages text))
           (components (yeah-diagram--components text))
           (exclusions (delq nil (mapcar #'yeah-check--exclusion (yeah-check--note text))))
           (references (yeah-diagram--references text))
           (named (delete-dups (mapcar #'car references))))
      ;; 1. every reference points at a file, at a line, and at code.
      (dolist (broken (yeah-diagram--broken-references root references))
        (push (nth 1 broken) yeah-check--failures))
      ;; A diagram that names nothing cannot tell a good name from a bad one.
      (when (null references)
        (push "the diagram names no file at all: this check cannot tell a good name from a bad one"
              yeah-check--failures))
      ;; 2. every module of lib/ is named by the picture or excluded with a reason.
      (dolist (module (file-expand-wildcards (expand-file-name "lib/*.el" root)))
        (let ((name (file-relative-name module root)))
          (unless (or (cl-find name named :test #'string=)
                      (cl-find name (mapcar #'car exclusions) :test #'string=))
            (push (format "the module %s is neither named by the diagram nor listed in the note of the modules the picture does not name"
                          name)
                  yeah-check--failures))))
      ;; 3. the note names modules that are there, and only once.
      (dolist (exclusion exclusions)
        (let ((module (nth 0 exclusion))
              (reason (nth 1 exclusion)))
          (unless (file-exists-p (expand-file-name module root))
            (push (format "the note names %s, and there is no such module" module)
                  yeah-check--failures))
          (when (null reason)
            (push (format "the note names %s, and it does not say why the picture does not name it" module)
                  yeah-check--failures))
          (when (cl-find module named :test #'string=)
            (push (format "the module %s is named by the diagram and listed in the note as a module the picture does not name"
                          module)
                  yeah-check--failures))))
      ;; 4. every block names a file, and every layer of the picture is there.
      (dolist (component components)
        (unless (nth 1 component)
          (push (format "the block %s of the picture names no file" (car component))
                yeah-check--failures)))
      (dolist (package '("drivers" "core" "journal" "projections"))
        (unless (cl-find package packages :test #'string=)
          (push (format "the picture has no package %s" package) yeah-check--failures)))
      (dolist (failure yeah-check--failures)
        (message "layer-diagram: %s" failure))
      (if yeah-check--failures
          (kill-emacs 1)
        (kill-emacs 0))))
  (when yeah-check--blockers
    (dolist (blocker yeah-check--blockers)
      (message "layer-diagram: %s" blocker))
    (kill-emacs 2)))

;;; check-the-layer-diagram-points-at-files-that-exist.el ends here
