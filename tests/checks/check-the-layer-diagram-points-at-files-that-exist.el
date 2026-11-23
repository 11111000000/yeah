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
;; The picture of the layers of the core is written by hand in the notation
;; of D2, and every leaf of it names the file of the kernel that implements
;; the leaf.  A name that nobody wrote any more is a dead end for the
;; reader: the leaf says what it is made of, and the file it names is not
;; there.
;;
;; This check reads `site/diagrams/core-layers.d2` and follows every name
;; it finds.  It measures four things:
;;
;;   1. every reference of the form `file:line` points at a file of this
;;      repository, at a line of that file, and at a line that carries a
;;      definition -- an empty line names no code, a line that holds
;;      nothing but a comment names no code either, and a line that holds
;;      code that is not a definition names no definition;
;;   2. every leaf of the picture names at least one file, and a picture
;;      that names no file at all cannot tell a good name from a bad one.
;;      A band is a group of leaves and names no file of its own;
;;   3. the four bands of the picture are all there: what asks, what
;;      decides, what is remembered and what is seen.  A picture without a
;;      band is a picture of a part;
;;   4. the note names the modules of `lib/` that the picture does not name,
;;      and it says why; the note names no module that is not there, and
;;      names no module that the picture names as well.
;;
;; The picture is a picture of the bands of the core and not a map of the
;; modules of `lib/`: a module that the picture does not name is a module
;; that is out of the scope of the picture, and the rule of the reference,
;; the rule of the definition, the rule of the leaf, the rule of the band
;; and the walk of the modules of `lib/` live in one place:
;; `tests/support/yeah-diagram-files.el`.  A copy of the rule in this
;; check is a rule that drifts away from the rule of the other pictures
;; of the site, and one picture that is read two ways gives two verdicts
;; for one picture.
;;
;; The format of the source is a rule of the reader of the pictures and
;; not of D2: a node of the picture is a line of the form `key: "label"`,
;; a band is a node that opens a body, and the note of the picture is the
;; node whose name is `note`.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- the diagram points at what is there; 1 -- it points at
;; something that is not there, or a band of it is missing; 2 -- the tree
;; is not where we think, and the check cannot answer.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--blockers nil
  "The reasons why this check cannot answer.")

(defconst yeah-check--bands
  '("what asks" "what decides" "what is remembered" "what is seen")
  "The bands of the picture of the layers of the core.
The picture of the bands is the picture of the core that the site shows:
what asks, what decides, what is remembered and what is seen.")

(let* ((root (expand-file-name default-directory))
       (reader (expand-file-name "tests/support/yeah-diagram-files.el" root))
       (diagram (expand-file-name "site/diagrams/core-layers.d2" root)))
  (unless (file-directory-p (expand-file-name "lib" root))
    (push "the tree of the repository is not where we think: there is no lib/"
          yeah-check--blockers))
  (unless (file-readable-p diagram)
    (push "the tree of the repository is not where we think: there is no site/diagrams/core-layers.d2"
          yeah-check--blockers))
  (unless (file-readable-p reader)
    (push "the tree of the repository is not where we think: there is no tests/support/yeah-diagram-files.el"
          yeah-check--blockers))
  (when (null yeah-check--blockers)
    (load reader nil t)
    (let* ((text (yeah-diagram--text diagram))
           (engine (yeah-diagram--engine-of diagram))
           (blocks (yeah-diagram--d2-blocks text))
           (groups (yeah-diagram--d2-groups text))
           (note (yeah-diagram--d2-note text))
           (exclusions (delq nil (mapcar #'yeah-diagram--exclusion note)))
           (references (yeah-diagram--references text engine))
           (named (delete-dups (mapcar #'car references))))
      ;; 1. every reference points at a file, at a line, and at code.
      (dolist (broken (yeah-diagram--broken-references root references))
        (push (nth 1 broken) yeah-check--failures))
      ;; A picture that names nothing cannot tell a good name from a bad one.
      (when (null references)
        (push "the diagram names no file at all: this check cannot tell a good name from a bad one"
              yeah-check--failures))
      ;; 2. every leaf names a file, and a band names no file.
      (dolist (block blocks)
        (unless (or (string= (nth 0 block) "note")
                    (nth 3 block)
                    (nth 2 block))
          (push (format "the leaf %s of the picture names no file" (nth 0 block))
                yeah-check--failures)))
      ;; 3. the bands of the picture are all there.
      (dolist (band yeah-check--bands)
        (unless (cl-find band groups :test #'string=)
          (push (format "the picture has no band %s" band) yeah-check--failures)))
      ;; 4. the note names the modules that are there, and only once.
      (when (null exclusions)
        (push "the picture has no note of the modules it does not name" yeah-check--failures))
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
            (push (format "the module %s is named by the picture and listed in the note as a module the picture does not name"
                          module)
                  yeah-check--failures))))
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
