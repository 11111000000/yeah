;;; check-the-emacs-layer-diagram-shows-the-bridge-and-the-scopes.el --- the Emacs layer shows the bridge and the scopes -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The picture of the Emacs layer is written by hand in the notation of D2,
;; and every leaf of it names the file of the kernel that implements the
;; leaf.  The bridge is the subject of the picture: it is the only path from
;; the harness to the live state of the editor's Emacs, and it is a
;; capability the person approves on purpose.
;;
;; This check reads `site/diagrams/emacs-layer.d2` and measures:
;;
;;   1. the picture is not empty;
;;   2. every reference of the form `file:line` points at a file of this
;;      repository, at a line of that file, and at a line that carries a
;;      definition; a picture that names no file at all cannot tell a good
;;      name from a bad one;
;;   3. the five modules that hold the layer together are named;
;;   4. every leaf names at least one file, and the bridge is a leaf of its
;;      own that names a file of `lib/yeah-bridge.el`;
;;   5. the answers of the person -- once, session, project, global and
;;      reject -- are the words of the picture;
;;   6. the six capabilities of the layer -- BUFFERS, INTROSPECT, EDIT,
;;      DIAGNOSE, COMPOSE and RECOVER -- are named by the picture.
;;
;; The rules of the reader of the pictures live in one place:
;; `tests/support/yeah-diagram-files.el`.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- the picture shows the bridge and the scopes; 1 -- it does
;; not; 2 -- the tree is not where we think, and the check cannot answer.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--blockers nil
  "The reasons why this check cannot answer.")

(defconst yeah-check--layer-modules
  '("lib/yeah-emacs.el"
    "lib/yeah-bridge.el"
    "lib/yeah-compose.el"
    "lib/yeah-doctor-ui.el"
    "lib/yeah-approval-ui.el")
  "The modules the picture of the Emacs layer has to name.")

(defconst yeah-check--layer-capabilities
  '("BUFFERS" "INTROSPECT" "EDIT" "DIAGNOSE" "COMPOSE" "RECOVER")
  "The six capabilities of the Emacs layer.
Every one of them is named by a title of the picture.  The case
matters: the picture says `EDIT` and the word `edit` is not the word
`EDIT`.")

(defun yeah-check--names-p (line word)
  "Return non-nil when LINE names WORD as a whole word.
The name of a file is not a word of the picture, and the case
matters: the word `ACP` is not the word `acp`."
  (and (yeah-diagram--names-all-p line (list word)) t))

(let* ((root (expand-file-name default-directory))
       (reader (expand-file-name "tests/support/yeah-diagram-files.el" root))
       (diagram (expand-file-name "site/diagrams/emacs-layer.d2" root)))
  (unless (file-directory-p (expand-file-name "lib" root))
    (push "the tree of the repository is not where we think: there is no lib/"
          yeah-check--blockers))
  (unless (file-directory-p (expand-file-name "site/diagrams" root))
    (push "the tree of the repository is not where we think: there is no site/diagrams/"
          yeah-check--blockers))
  (unless (file-readable-p reader)
    (push "the tree of the repository is not where we think: there is no tests/support/yeah-diagram-files.el"
          yeah-check--blockers))
  (unless (file-readable-p diagram)
    (push "the tree of the repository is not where we think: there is no site/diagrams/emacs-layer.d2"
          yeah-check--blockers))
  (when (null yeah-check--blockers)
    (load reader nil t)
    (let* ((text (yeah-diagram--text diagram))
           (engine (yeah-diagram--engine-of diagram))
           (lines (yeah-diagram--d2-drawing-lines text))
           (blocks (yeah-diagram--d2-blocks text))
           (references (yeah-diagram--references text engine))
           (named (delete-dups (mapcar #'car references))))
      ;; 1. the picture is there and it is not empty.
      (when (string-empty-p (string-trim text))
        (push "site/diagrams/emacs-layer.d2 is empty: there is no picture of the layer"
              yeah-check--failures))
      (when (null blocks)
        (push "site/diagrams/emacs-layer.d2 has no node: there is no picture of the layer"
              yeah-check--failures))
      ;; 2. every reference points at a file, at a line and at code.
      (dolist (broken (yeah-diagram--broken-references root references))
        (push (format "the picture of the Emacs layer names %s:%d, and %s"
                      (nth 0 (car broken)) (nth 1 (car broken)) (nth 1 broken))
              yeah-check--failures))
      (when (null references)
        (push "the picture of the Emacs layer names no file at all: this check cannot tell a good name from a bad one"
              yeah-check--failures))
      ;; 3. the five modules that hold the layer together are named.
      (dolist (module yeah-check--layer-modules)
        (unless (member module named)
          (push (format "the picture of the Emacs layer does not name %s: the capability it holds is not in the picture"
                        module)
                yeah-check--failures)))
      ;; 4. every leaf names a file, and the bridge is a leaf of its own.
      (dolist (block blocks)
        (unless (or (string= (nth 0 block) "note") (nth 3 block) (nth 2 block))
          (push (format "the leaf %s of the picture names no file" (nth 0 block))
                yeah-check--failures)))
      (let ((bridge (cl-find "bridge" blocks :key #'car :test #'string=)))
        (unless bridge
          (push "the picture of the Emacs layer has no leaf of the bridge: the bridge is the subject of the picture"
                yeah-check--failures))
        (unless (and bridge (member "lib/yeah-bridge.el" (mapcar #'car (nth 2 bridge))))
          (push "the leaf of the bridge names no file of lib/yeah-bridge.el: the bridge is the only path to the live state of the editor's Emacs"
                yeah-check--failures)))
      ;; 5. the answers of the person are the words of the kernel.
      (unless (yeah-diagram--answers-p lines)
        (push "the picture of the Emacs layer has no line that names the answers of the person: once, session, project, global and reject"
              yeah-check--failures))
      ;; 6. the six capabilities of the layer are named by the picture.
      (dolist (capability yeah-check--layer-capabilities)
        (unless (cl-some (lambda (line) (yeah-check--names-p line capability))
                         lines)
          (push (format "the picture of the Emacs layer has no title that names the capability %s: the capability of the layer is not in the picture"
                        capability)
                yeah-check--failures)))
      (dolist (failure yeah-check--failures)
        (message "emacs-layer-diagram: %s" failure))
      (if yeah-check--failures
          (kill-emacs 1)
        (kill-emacs 0))))
  (when yeah-check--blockers
    (dolist (blocker yeah-check--blockers)
      (message "emacs-layer-diagram: %s" blocker))
    (kill-emacs 2)))

;;; check-the-emacs-layer-diagram-shows-the-bridge-and-the-scopes.el ends here
