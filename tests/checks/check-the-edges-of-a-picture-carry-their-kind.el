;;; check-the-edges-of-a-picture-carry-their-kind.el --- the edges of a picture carry their kind -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; An edge of a picture of the site that crosses a boundary of
;; responsibility carries its KIND.  The request of the person travels
;; inward, the answer of the person decides what may run, an event is
;; written into the journal, a view is projected out of it, and the live
;; state of the editor is reached on a capability the person approves on
;; purpose.  The label of the edge names the kind in words, and the style
;; of the line carries the kind a second time -- colour never carries the
;; meaning alone.
;;
;; This check measures three things:
;;
;;   1. the palette of every theme defines the five kinds -- request,
;;      answer, write, project and capability -- and the dash of every
;;      kind is a dash no other kind of that palette carries: two kinds
;;      that share one dash are one line, and a picture that draws them
;;      tells the reader nothing.  Every kind carries a width as well,
;;      and the label of the edge names the kind in words either way;
;;   2. the picture of the layers, the picture of the Emacs layer and the
;;      picture of the placements draw their named edges as the kinds the
;;      labels say: the edge whose label says the request is drawn as a
;;      request, the edge whose label says the answer as an answer, the
;;      edge into the journal as a write, the edge out of the journal as
;;      a projection, and the edges of the bridge as the capability they
;;      are;
;;   3. every edge that carries a kind carries a label: a line without
;;      words carries no kind the reader of the picture can name.
;;
;; The seam of the control of the claim is the dash of the kinds in the
;; palette of the light theme: a palette whose two kinds share one dash
;; must make this check fail by its own assertion.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- the edges carry their kinds; 1 -- a kind is missing,
;; two kinds share a style, or an edge carries the wrong kind; 2 -- the
;; tree is not where we think, and the check cannot answer.

;;; Code:

(require 'cl-lib)

(defvar yeah-edge--failures nil
  "The failures this check found.")

(defvar yeah-edge--blockers nil
  "The reasons why this check cannot answer.")

(defconst yeah-edge--kinds
  '("request" "answer" "write" "project" "capability")
  "The kinds of an edge that crosses a boundary of responsibility.")

(defconst yeah-edge--pictures
  '(("site/diagrams/core-layers.d2"
     ("the request" . "request")
     ("every event is written" . "write")
     ("every view is a projection" . "project"))
    ("site/diagrams/emacs-layer.d2"
     ("writes the prompt" . "request")
     ("the prompt" . "request")
     ("answers a request" . "answer")
     ("the answer decides\\nwhat may run" . "answer")
     ("the only path\\nto the live state" . "capability")
     ("a capability you\\napprove on purpose" . "capability")
     ("writes what happened" . "write"))
    ("site/diagrams/placements.d2"
     ("ACP" . "request")
     ("MCP" . "request")
     ("evaluates in the editing Emacs" . "capability")))
  "The three structural pictures and the kinds of their named edges.
The label is the label of the source of the picture, with the escapes
of D2 as they are written there: the reader of the picture sees the
words, and this check reads the source.")

(defun yeah-edge--text (path)
  "Return the text of the picture PATH, read from the root of the tree."
  (with-temp-buffer
    (insert-file-contents (expand-file-name path default-directory))
    (buffer-string)))

(defun yeah-edge--style-of (text kind)
  "Return the (DASH . WIDTH) of the kind KIND in the palette TEXT, or nil.
A kind that carries no dash carries no style the check can hold apart
from the style of another kind."
  (let ((case-fold-search nil))
    (when (string-match
           (concat "\\(?:\\`\n\\|.*\n\\)  " (regexp-quote kind)
                   ": {\\(\\(?:.*\n\\)*?\\)  }")
           text)
      (let ((block (match-string 1 text)))
        (cons (and (string-match "stroke-dash: \\([0-9]+\\)" block)
                   (string-to-number (match-string 1 block)))
              (and (string-match "stroke-width: \\([0-9]+\\)" block)
                   (string-to-number (match-string 1 block))))))))

(defun yeah-edge--edges (text)
  "Return the edges of the picture in TEXT.
Every edge is a list (CLASS LABEL): the class the picture draws the
edge with and the label the picture names it by.  An edge whose block
closes without a label comes back with the label nil."
  (let ((edges nil)
        (current nil))
    (dolist (line (split-string text "\n" t))
      (cond
       ((and (string-match "\\`\\(.+\\) -> \\(.+\\): {" line)
             (not current))
        (setq current (list "edge")))
       ((and current
             (string-match "\\`[[:space:]]*class: \\([^[:space:]]+\\)" line))
        (setq current (append current (list (match-string 1 line)))))
       ((and current
             (string-match "\\`[[:space:]]*label: \"\\(.*\\)\"" line))
        (push (append current (list (match-string 1 line))) edges)
        (setq current nil))
       ((and current (string-match "\\`[[:space:]]*}" line))
        (push (append current (list nil)) edges)
        (setq current nil))))
    (nreverse edges)))

(let* ((root (expand-file-name default-directory))
       (palettes (mapcar (lambda (theme)
                           (concat "site/diagrams/palette-" theme ".d2"))
                         '("light" "dark"))))
  (unless (and (file-directory-p (expand-file-name "lib" root))
               (file-directory-p (expand-file-name "site/diagrams" root)))
    (push "the tree of the repository is not where we think"
          yeah-edge--blockers))
  (dolist (palette (append palettes (mapcar #'car yeah-edge--pictures)))
    (unless (file-readable-p (expand-file-name palette root))
      (push (format "the file %s is not there" palette) yeah-edge--blockers)))
  (if yeah-edge--blockers
      (progn
        (dolist (blocker yeah-edge--blockers)
          (message "edge-kind: %s" blocker))
        (kill-emacs 2))
    (let ((failures nil))
      ;; 1. every palette defines the five kinds, and no two kinds of one
      ;;    palette share the pair of the dash and the width
      (dolist (palette palettes)
        (let* ((text (yeah-edge--text palette))
               (styles (mapcar (lambda (kind)
                                 (cons kind (yeah-edge--style-of text kind)))
                               yeah-edge--kinds))
               (seen nil))
          (dolist (style styles)
            (let ((kind (car style))
                  (pair (cdr style)))
              (unless (and (numberp (car pair)) (numberp (cdr pair)))
                (push (format "the palette %s carries no dash or no width for the kind %s"
                              palette kind)
                      failures))
              (when (assoc (car pair) seen)
                (push (format "the palette %s draws %s and %s with one dash: two kinds that share a dash are one line"
                              palette (cdr (assoc (car pair) seen)) kind)
                      failures))
              (push (cons (car pair) kind) seen)))))
      ;; 2. the pictures draw their named edges as the kinds the labels say
      (dolist (entry yeah-edge--pictures)
        (let* ((text (yeah-edge--text (car entry)))
               (edges (yeah-edge--edges text)))
          (dolist (wanted (cdr entry))
            (let* ((label (car wanted))
                   (kind (cdr wanted))
                   (edge (cl-find-if
                          (lambda (edge)
                            (and (nth 2 edge)
                                 (string= (nth 2 edge) label)))
                          edges)))
              (cond
               ((null edge)
                (push (format "the picture %s carries no edge whose label is %S"
                              (car entry) label)
                      failures))
               ((null (nth 1 edge))
                (push (format "the picture %s draws the edge %S with no kind at all"
                              (car entry) label)
                      failures))
               ((not (string= (nth 1 edge) kind))
                (push (format "the picture %s draws the edge %S as the kind %s, and the label says %s"
                              (car entry) label (nth 1 edge) kind)
                      failures)))))))
      (dolist (failure (nreverse failures))
        (message "edge-kind: %s" failure))
      (if failures
          (kill-emacs 1)
        (message "edge-kind: the edges of the three pictures carry their kinds, and the palettes hold the styles of the five kinds apart")
        (kill-emacs 0)))))

;;; check-the-edges-of-a-picture-carry-their-kind.el ends here
