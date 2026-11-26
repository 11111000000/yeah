;;; check-every-diagram-names-what-it-does-not-show.el --- every picture names its boundary -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Every picture of the site names what it does NOT show.  A picture
;; that hides its own boundary tells the reader more than the code
;; holds: the reader takes the picture for the whole, and the part the
;; picture left out becomes the part the reader does not know exists.
;;
;; The boundaries of the eight pictures:
;;
;;   the picture of the turn does not show the machinery of the run --
;;   the supervision that nudges a model that announces and does not
;;   act, the retries of a dropped request and the compaction of the
;;   context; the machine of the states of a run is the neighbouring
;;   picture;
;;   the picture of the fixed point does not show the cancellation of a
;;   child that ran out of its time;
;;   the machine of the states does not show that a run which never
;;   meets a busy provider never takes blocked-on-rate -- the machine is
;;   the declared table, and the cells are measured as places of a tick,
;;   not as runs;
;;   the picture of the packages does not show the edges between the
;;   packages: the degrees name how many, not which;
;;   the picture of the Emacs layer does not show the paths the bridge
;;   does not take: the harness never reaches the buffers of the editor
;;   without the approval of the person;
;;   the picture of the layers does not name the modules that are out of
;;   its scope, and says why;
;;   the picture of the placements names the honest limit of the wire;
;;   the picture of the levels of the check names what is still open at
;;   the top of the ladder.
;;
;; This check reads the source of every picture, takes the comments out
;; (a word that is only in the comment is not a claim of the picture),
;; folds the escapes of the labels into spaces, and looks for the
;; boundary of the picture in the prose that is left.
;;
;; The boundary of the machine of the states is written by the generator
;; of the diagram (`lib/yeah-state-diagram.el', `scripts/dev
;; state-diagram') and not by hand: the source of that picture is a
;; function of the code, and a boundary that the code does not carry is
;; a boundary the generator must carry.
;;
;; The seam of the control of the claim is the boundary of the picture
;; of the turn: a picture that stops naming its boundary must make this
;; check fail by its own assertion.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- every picture names what it does not show; 1 -- a
;; boundary is missing; 2 -- the tree is not where we think.

;;; Code:

(require 'cl-lib)

(defvar yeah-boundary--failures nil
  "The failures this check found.")

(defconst yeah-boundary--pictures
  '(("site/diagrams/one-turn.puml" "plantuml"
     . "does not show the machinery of the run")
    ("site/diagrams/fixed-point.puml" "plantuml"
     . "does not show the cancellation")
    ("site/diagrams/state-machine.puml" "plantuml"
     . "never takes blocked-on-rate")
    ("site/diagrams/code-packages.d2" "d2"
     . "does not show the edges between the packages")
    ("site/diagrams/emacs-layer.d2" "d2"
     . "The paths the bridge does not take are not in this picture")
    ("site/diagrams/core-layers.d2" "d2"
     . "this picture does not name")
    ("site/diagrams/placements.d2" "d2"
     . "The honest limit of the wire")
    ("site/diagrams/check-levels.puml" "plantuml"
     . "Still open at the top of the ladder"))
  "Every picture of the site and the boundary it names.")

(defun yeah-boundary--prose (path engine)
  "Return the prose of the picture PATH of ENGINE.
The prose is the source without the comment lines, with the escapes of
the labels folded into spaces and the whitespace collapsed -- the text
the reader of the picture reads, as one line."
  (let ((text (yeah-diagram--text path))
        (lines nil))
    (dolist (line (split-string text "\n" t))
      (unless (yeah-diagram--comment-p line engine)
        (push line lines)))
    (let ((joined (mapconcat #'identity (nreverse lines) " ")))
      (setq joined (replace-regexp-in-string "\\\\n" " " joined))
      (replace-regexp-in-string "[[:space:]]+" " " joined))))

(let* ((root (expand-file-name default-directory))
       (reader (expand-file-name "tests/support/yeah-diagram-files.el" root)))
  (unless (file-readable-p reader)
    (message "boundary: the reader of the pictures is not there: %s" reader)
    (kill-emacs 2))
  (load reader)
  (unless (file-directory-p (expand-file-name "site/diagrams" root))
    (message "boundary: the tree of the repository is not where we think")
    (kill-emacs 2))
  (dolist (entry yeah-boundary--pictures)
    (let* ((path (car entry))
           (engine (cadr entry))
           (phrase (cddr entry)))
      (if (not (file-readable-p (expand-file-name path root)))
          (progn
            (message "boundary: the picture %s is not there" path)
            (setq yeah-boundary--failures t))
        (unless (string-match
                 (regexp-quote phrase)
                 (yeah-boundary--prose path engine))
          (message "boundary: the picture %s names no boundary the check can find: the prose holds no %S"
                   path phrase)
          (setq yeah-boundary--failures t)))))
  (if yeah-boundary--failures
      (kill-emacs 1)
    (message "boundary: every picture of the site names what it does not show")
    (kill-emacs 0)))

;;; check-every-diagram-names-what-it-does-not-show.el ends here
