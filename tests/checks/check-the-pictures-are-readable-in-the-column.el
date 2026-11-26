;;; check-the-pictures-are-readable-in-the-column.el --- the pictures of the site are readable in the column -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The pictures of the site are true (the guards of every diagram read the
;; source against the code), and nothing guarded their SIZE.  A picture that
;; is wider than the column of the page is scaled down by the stylesheet
;; (`max-width: 100%'), and a picture that is scaled down enough is a picture
;; whose words are smaller than the words of the page: the reader of the site
;; cannot read what the guards prove the picture says.
;;
;; This check measures it.  The column of the page is computed out of the
;; stylesheet, the way a browser computes it: the frame width, the fringe,
;; the two gutters, the border of a figure and the padding of a picture; a
;; clamp is resolved at the width of the frame, which is the widest the frame
;; of the site ever is.  The size of the type of a picture is read out of the
;; SVG of the picture.  The effective size of a word is
;;
;;     the size of the type * the column / the width of the picture,
;;
;; and the smallest effective size of every picture must be at or above the
;; floor of this check.
;;
;; The floor is twelve pixels: the text of a caption of the page is 12.8 px
;; (0.8rem), and a picture whose smallest word is smaller than the smallest
;; word of the prose around it is a picture the person cannot read.  The
;; owner named the threshold among the decisions of the owner (12, 14 or 16);
;; this floor is the honest minimum the tree holds today, and the decision of
;; the owner can raise it (docs/PLAN.md §17.2).
;;
;; Exit codes: 0 -- every picture is readable in the column; 1 -- at least
;; one picture is not; 2 -- the tree is not where we think.

;;; Code:

(require 'cl-lib)

(defconst yeah-check--legibility-floor 12.0
  "The smallest effective size of the type of a picture, in pixels.
The size the picture is rendered at in the column of the page.  Twelve
pixels is the smallest size of the prose of the page (a caption is
0.8rem = 12.8 px); the owner may raise the floor (docs/PLAN.md §17.2).")

(defconst yeah-check--rem-in-px 16.0
  "The size of one rem, in pixels, the way a browser reads the site.")

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--blockers nil
  "The things that stopped this check before it could measure anything.")

(defun yeah-check--root ()
  "Return the root of the project."
  (expand-file-name default-directory))

(defun yeah-check--css-number (css name)
  "Return the number of pixels of the declaration NAME of the CSS.
The declaration is `NAME: 123px'.  The value is read the way a browser
reads it: a rem is `yeah-check--rem-in-px' pixels."
  (when (string-match (concat (regexp-quote name) "[[:space:]]*:[[:space:]]*\\([0-9.]+\\)px") css)
    (string-to-number (match-string 1 css))))

(defun yeah-check--css-clamp (css name frame-width)
  "Return the pixels of the clamp declaration NAME of the CSS.
The declaration is `NAME: clamp(Arem, Bvw, Crem)'; the preferred value
is resolved at FRAME-WIDTH, the way a browser resolves a vw unit."
  (when (string-match
         (concat (regexp-quote name)
                 "[[:space:]]*:[[:space:]]*clamp([[:space:]]*\\([0-9.]+\\)rem,[[:space:]]*\\([0-9.]+\\)vw,[[:space:]]*\\([0-9.]+\\)rem[[:space:]]*)")
         css)
    (let ((minimum (* (string-to-number (match-string 1 css)) yeah-check--rem-in-px))
          (preferred (* (string-to-number (match-string 2 css)) (/ frame-width 100.0)))
          (maximum (* (string-to-number (match-string 3 css)) yeah-check--rem-in-px)))
      (min maximum (max minimum preferred)))))

(defun yeah-check--css-block (css selector)
  "Return the declarations of the rule of CSS that SELECTOR opens.
The rule is `SELECTOR { ... }', and the body is what stands between
its braces.  The rule this check reads must be the rule it names: the
stylesheet carries other `padding' clamps for other elements, and a
number that belongs to another element says nothing about a picture."
  (when (string-match (concat "^" (regexp-quote selector)
                              "[[:space:]]*{\\([^}]*\\)}")
                      css)
    (match-string 1 css)))

(defun yeah-check--css-border (block)
  "Return the width in pixels of the border declaration of BLOCK.
The declaration is `border: 1px solid ...'."
  (when (string-match "border:[[:space:]]*\\([0-9.]+\\)px" block)
    (string-to-number (match-string 1 block))))

(defun yeah-check--column (css)
  "Return the width of the column a picture may fill, out of the CSS.
The column is the width of the frame, less the fringe, less the two
gutters, less the border of the figure, less the padding of the
picture on both of its sides.  The frame, the fringe and the gutter
are read out of the variables of the root; the border and the padding
are read out of the rules that name them -- `.diagram' and
`.diagram__img' -- and not out of the first declaration the file
happens to carry."
  (let* ((frame (yeah-check--css-number css "--frame-w"))
         (fringe (yeah-check--css-number css "--fringe-w"))
         (gutter (and frame (yeah-check--css-clamp
                             css "--gutter" frame)))
         (figure (yeah-check--css-block css ".diagram"))
         (border (and figure (yeah-check--css-border figure)))
         (picture (yeah-check--css-block css ".diagram__img"))
         (padding (and picture frame
                       (yeah-check--css-clamp picture "padding" frame))))
    (unless (and frame fringe gutter border padding)
      (push "the stylesheet of the site does not name the sizes this check reads: --frame-w and --fringe-w of the root, the clamp of --gutter, the border of the rule .diagram, or the padding clamp of the rule .diagram__img"
            yeah-check--failures))
    (when (and frame fringe gutter border padding)
      (- frame fringe (* 2 gutter) (* 2 border) (* 2 padding)))))

(defun yeah-check--picture-sizes (svg)
  "Return (WIDTH . SIZES) of the picture at SVG.
WIDTH is the width of the viewBox of the picture, and SIZES are the
sizes of the type the picture carries, every one of them."
  (let ((text (with-temp-buffer
                (insert-file-contents svg)
                (buffer-string))))
    (when (string-match "viewBox=\"0 0 \\([0-9.]+\\)[^\"]*\"" text)
      (let ((width (string-to-number (match-string 1 text)))
            (sizes nil))
        (while (string-match "font-size[:=][[:space:]]*\"?\\([0-9.]+\\)" text)
          (push (string-to-number (match-string 1 text)) sizes)
          (setq text (substring text (match-end 0))))
        (cons width (nreverse sizes))))))

(defun yeah-check--pictures ()
  "Return the files of the pictures of the site, in order."
  (let ((root (yeah-check--root)))
    (sort (directory-files (expand-file-name "site/assets/diagrams" root) t "^[^.].*\\.svg\\'")
          #'string<)))

(let* ((root (yeah-check--root))
       (css-file (expand-file-name "site/styles.css" root)))
  (unless (file-directory-p (expand-file-name "lib" root))
    (push "the tree of the repository is not where we think: there is no lib/"
          yeah-check--failures))
  (unless (file-readable-p css-file)
    (push "the stylesheet site/styles.css is not there: this check cannot read the column of the page"
          yeah-check--failures))
  (when (null yeah-check--failures)
    (let* ((css (with-temp-buffer
                  (insert-file-contents css-file)
                  (buffer-string)))
           (column (yeah-check--column css))
           (pictures (yeah-check--pictures)))
      (when (null pictures)
        (push "the site carries no picture at all: this check cannot tell a readable picture from an unreadable one"
              yeah-check--failures))
      (when column
        (dolist (picture pictures)
          (let* ((sizes (yeah-check--picture-sizes picture))
                 (width (car sizes))
                 (scale (min 1.0 (/ column width)))
                 (effective (mapcar (lambda (size) (* size scale)) (cdr sizes)))
                 (smallest (and effective (apply #'min effective))))
            (unless (cdr sizes)
              (push (format "%s carries no size of the type at all: this check cannot tell what the reader reads"
                            (file-name-nondirectory picture))
                    yeah-check--failures))
            (when (and smallest (< smallest yeah-check--legibility-floor))
              (push (format "%s is read at %.1f px in the column of the page (%d px wide, scaled %.2f): the smallest word of the picture is smaller than the floor of %.1f px"
                            (file-name-nondirectory picture)
                            smallest (floor width) scale yeah-check--legibility-floor)
                    yeah-check--failures)))))
        (let ((smallest (cl-loop
                         for picture in pictures
                         for sizes = (yeah-check--picture-sizes picture)
                         when (and column (cdr sizes))
                         minimize (apply #'min
                                         (mapcar (lambda (size)
                                                   (* size
                                                      (min 1.0 (/ column (car sizes)))))
                                                 (cdr sizes))))))
          (when (and (null yeah-check--failures) smallest)
            (message "pictures: the smallest word of every picture of the site is %.1f px in the column of the page, and the floor is %.1f px"
                     smallest yeah-check--legibility-floor)))))
  (when yeah-check--failures
    (dolist (failure yeah-check--failures)
      (message "pictures: %s" failure))
    (kill-emacs 1))
  (when yeah-check--blockers
    (dolist (blocker yeah-check--blockers)
      (message "pictures: %s" blocker))
    (kill-emacs 2))
  (kill-emacs 0)))

;;; check-the-pictures-are-readable-in-the-column.el ends here
