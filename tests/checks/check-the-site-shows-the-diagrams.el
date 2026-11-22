;;; check-the-site-shows-the-diagrams.el --- the page shows the diagrams -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The eight pictures of the architecture are drawn (wave D2) and they are on
;; the page (wave D3).  Nothing keeps them there: the page is checked in
;; without a build step, so a picture can be renamed, a file of the page can
;; be dropped, the text of a picture can be emptied, and the page still looks
;; whole.
;;
;; This check reads the page and the stylesheet of the site and proves:
;;
;;   1. the page shows the eight diagrams -- one figure for each of them,
;;      named by `data-diagram', and not a ninth one;
;;   2. every picture of a figure points at a file that is on disk;
;;   3. every picture of a figure carries a text that says what the picture
;;      is, and every figure carries a caption -- a reader who does not see
;;      the picture must still learn what it is;
;;   4. the ASCII figure of the architecture is gone from the page and from
;;      the stylesheet;
;;   5. the pictures are scaled into the column of the page
;;      (`max-width: 100%' and `height: auto'), so the page does not run
;;      sideways;
;;   6. the theme of the frame chooses the picture -- the dark picture is
;;      hidden by default and shown in the dark theme, and the light one is
;;      the other way round -- so the page is readable with JavaScript
;;      disabled: the light picture is the one that is there;
;;   7. the stylesheet prints the pictures.
;;
;; One rule, one place: the rules of the page live in the stylesheet, and the
;; rules of the stylesheet live in this check.  The check names what it found
;; and not only that it failed.
;;
;; Exit codes: 0 -- the page shows the eight diagrams and the stylesheet
;; carries them; 1 -- it does not.

;;; Code:

(require 'cl-lib)

(defun yeah-check--root ()
  "Return the root of the project."
  (expand-file-name default-directory))

(defun yeah-check--read (file)
  "Return the text of FILE, or the empty string when it cannot be read."
  (if (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (buffer-string))
    ""))

(defun yeah-check--page ()
  "Return the text of the page of the site."
  (yeah-check--read (expand-file-name "site/index.html" (yeah-check--root))))

(defun yeah-check--stylesheet ()
  "Return the text of the stylesheet of the site."
  (yeah-check--read (expand-file-name "site/styles.css" (yeah-check--root))))

(defun yeah-check--all-matches (regexp string)
  "Return the texts of STRING that REGEXP matches, in the order they come.
The search is a plain loop over the matches of the regular expression:
Emacs 30 has no `string-match-all', and a check that needs a library that
is not there is a check that cannot run."
  (let ((start 0)
        (found nil))
    (while (string-match regexp string start)
      (push (match-string 0 string) found)
      (setq start (match-end 0)))
    (nreverse found)))

(defun yeah-check--class-list (tag)
  "Return the classes of the opening tag TAG as a list of words."
  (let ((match (string-match "class=\"\\([^\"]*\\)\"" tag)))
    (if match
        (split-string (match-string 1 tag) "[ \t]+" t)
      nil)))

(defun yeah-check--has-class-p (tag class)
  "Return non-nil when the opening tag TAG carries the class CLASS."
  (and (member class (yeah-check--class-list tag)) t))

(defun yeah-check--attribute (tag name)
  "Return the value of the attribute NAME of the opening tag TAG, or nil."
  (let ((match (string-match (concat name "=\"\\([^\"]*\\)\"") tag)))
    (and match (match-string 1 tag))))

(defun yeah-check--figure-blocks (page)
  "Return the texts of the `figure' blocks of PAGE, in the order they come.
A figure is not nested in a figure, so the end of a block is the first
`</figure>' that follows its opening tag."
  (let ((start 0)
        (blocks nil))
    (while (string-match "<figure\\b[^>]*>" page start)
      (let ((opening (match-string 0 page))
            (after (match-end 0)))
        (if (string-match "</figure>" page after)
            (progn
              (push (concat opening (substring page after (match-end 0))) blocks)
              (setq start (match-end 0)))
          ;; A figure that is never closed is a figure that is not there:
          ;; the check says so below.
          (setq start after))))
    (nreverse blocks)))

(defun yeah-check--figure-tag (block)
  "Return the opening tag of the figure BLOCK."
  (car (split-string block "\n" t)))

(defun yeah-check--diagrams (page)
  "Return the blocks of PAGE that are figures of diagrams.
A figure of a diagram carries the class `diagram'."
  (let ((diagrams nil))
    (dolist (block (yeah-check--figure-blocks page))
      (when (yeah-check--has-class-p (yeah-check--figure-tag block) "diagram")
        (push block diagrams)))
    (nreverse diagrams)))

(defun yeah-check--diagram-number (block)
  "Return the number of the diagram of the figure BLOCK, or nil."
  (let ((value (yeah-check--attribute (yeah-check--figure-tag block) "data-diagram")))
    (when (and value (string-match "^d\\([0-9]+\\)$" value))
      (string-to-number (match-string 1 value)))))

(defun yeah-check--figcaption (block)
  "Return the text of the caption of the figure BLOCK, or nil."
  (let ((match (string-match "<figcaption\\(?: [^>]*\\)?>\\(.*?\\)</figcaption>" block)))
    (and match (string-trim (match-string 1 block)))))

(defun yeah-check--images (block)
  "Return the opening tags of the images of the figure BLOCK."
  (yeah-check--all-matches "<img\\b[^>]*>" block))

(defun yeah-check--local-file (target)
  "Return the file of the site that TARGET names, or nil when it is not local."
  (when (and target
             (not (or (string-prefix-p "http" target)
                      (string-prefix-p "//" target)
                      (string-prefix-p "data:" target)
                      (string-prefix-p "mailto:" target))))
    (expand-file-name
     (if (string-match-p "[?#]" target)
         (substring target 0 (string-match "[?#]" target))
       target)
     (expand-file-name "site" (yeah-check--root)))))

(defun yeah-check--css-close (text open)
  "Return the position of the brace that closes the brace at OPEN in TEXT."
  (let ((depth 1)
        (pos (1+ open))
        (len (length text)))
    (while (and (< pos len) (> depth 0))
      (let ((char (aref text pos)))
        (cond ((eq char ?\{) (setq depth (1+ depth)))
              ((eq char ?\}) (setq depth (1- depth)))))
      (setq pos (1+ pos)))
    (min (1- pos) len)))

(defun yeah-check--css-rules (text)
  "Return the rules of the stylesheet TEXT as a list of (SELECTOR . BODY).
The rules of a nested block -- the `@media' of the print -- are rules of
their own, and their selector carries the block they live in."
  (let ((rules nil)
        (pos 0)
        (len (length text))
        (done nil))
    (while (and (< pos len) (not done))
      (let ((open (string-match "{" text pos)))
        (if (null open)
            (setq done t)
          (let* ((selector (string-trim (substring text pos open)))
                 (close (yeah-check--css-close text open)))
            (let ((body (substring text (1+ open) close)))
              (if (string-prefix-p "@" selector)
                  (dolist (rule (yeah-check--css-rules body))
                    (push (cons (concat selector " " (car rule)) (cdr rule)) rules))
                (push (cons selector body) rules)))
            (setq pos (1+ close))))))
    (nreverse rules)))

(defun yeah-check--rules-with (rules regexp)
  "Return the rules of RULES whose selector matches REGEXP."
  (let ((found nil))
    (dolist (rule rules)
      (when (string-match-p regexp (car rule))
        (push rule found)))
    (nreverse found)))

(defun yeah-check--bodies-with (rules regexp)
  "Return the bodies of the rules of RULES whose selector matches REGEXP."
  (mapcar #'cdr (yeah-check--rules-with rules regexp)))

(defun yeah-check--mentions-p (bodies needle)
  "Return non-nil when one of the BODIES mentions the NEEDLE."
  (and (cl-some (lambda (body) (and (string-match-p (regexp-quote needle) body) t)) bodies) t))

(defun yeah-check--check-page (page)
  "Return the failures of the page PAGE."
  (let ((failures nil))
    (when (string-empty-p page)
      (push "the page of the site is not to be read" failures))
    (unless (string-empty-p page)
      (let* ((blocks (yeah-check--figure-blocks page))
             (diagrams (yeah-check--diagrams page))
             (numbers (mapcar #'yeah-check--diagram-number diagrams)))
        ;; The eight of them, and no ninth.
        (unless (= (length diagrams) 8)
          (push (format "the page shows %d figures of diagrams, not eight" (length diagrams))
                failures))
        (dolist (number '(1 2 3 4 5 6 7 8))
          (let ((times (cl-count number numbers)))
            (cond ((zerop times)
                   (push (format "the page shows no figure of the diagram d%d" number)
                         failures))
                  ((> times 1)
                   (push (format "the page shows %d figures of the diagram d%d" times number)
                         failures)))))
        ;; Every figure of a diagram: a caption, and pictures that are there.
        (dolist (block diagrams)
          (let ((number (or (yeah-check--diagram-number block) 0)))
            (unless (yeah-check--figcaption block)
              (push (format "the figure of the diagram d%d has no caption" number) failures))
            (let ((images (yeah-check--images block)))
              (when (null images)
                (push (format "the figure of the diagram d%d has no picture" number) failures))
              (dolist (image images)
                (let ((alt (yeah-check--attribute image "alt"))
                      (src (yeah-check--attribute image "src")))
                  (when (or (null alt) (string-empty-p (string-trim alt)))
                    (push (format "the picture of the diagram d%d has no text that says what it is"
                                  number)
                          failures))
                  (let ((file (yeah-check--local-file src)))
                    (unless file
                      (push (format "the picture of the diagram d%d points at %s, which is not a file of the site"
                                    number (or src "nothing"))
                            failures))
                    (unless (or (null file) (file-exists-p file))
                      (push (format "the picture of the diagram d%d points at %s and there is no such file"
                                    number (or src "nothing"))
                            failures))))))))
        ;; The ASCII figure is gone from the page.
        (dolist (block blocks)
          (when (yeah-check--has-class-p (yeah-check--figure-tag block) "ascii-figure")
            (push "the page still has the figure of ASCII" failures)))
        (when (string-match-p "ascii-figure" page)
          (push "the page still names the figure of ASCII" failures))))
    failures))

(defun yeah-check--check-css (css)
  "Return the failures of the stylesheet CSS."
  (let ((failures nil))
    (when (string-empty-p css)
      (push "the stylesheet of the site is not to be read" failures))
    (unless (string-empty-p css)
      (let ((rules (yeah-check--css-rules css)))
        (when (string-match-p "ascii-figure" css)
          (push "the stylesheet still has the rules of the figure of ASCII" failures))
        (when (null (yeah-check--rules-with rules "\\.diagram"))
          (push "the stylesheet has no rule for the diagrams" failures))
        ;; The picture is scaled into the column.
        (let ((bodies (yeah-check--bodies-with rules "\\.diagram")))
          (unless (yeah-check--mentions-p bodies "max-width: 100%")
            (push "the stylesheet does not scale the picture of a diagram into the column"
                  failures))
          (unless (yeah-check--mentions-p bodies "height: auto")
            (push "the stylesheet does not keep the proportion of the picture of a diagram"
                  failures)))
        ;; The theme chooses the picture.
        (unless (yeah-check--mentions-p (yeah-check--bodies-with rules "\\.diagram__img--dark") "display: none")
          (push "the stylesheet does not hide the dark picture by default" failures))
        (unless (cl-some (lambda (rule)
                            (and (string-match-p "\\.diagram__img--dark" (car rule))
                                 (not (string-match-p "display: *none" (cdr rule)))
                                 t))
                          (yeah-check--rules-with rules "data-theme=\"dark\""))
          (push "the stylesheet does not show the dark picture in the dark theme" failures))
        (unless (cl-some (lambda (rule)
                            (and (string-match-p "\\.diagram__img--light" (car rule))
                                 (string-match-p "display: *none" (cdr rule))
                                 t))
                          (yeah-check--rules-with rules "data-theme=\"dark\""))
          (push "the stylesheet does not hide the light picture in the dark theme" failures))
        ;; The print.
        (unless (cl-some (lambda (rule) (and (string-match-p "\\.diagram" (car rule)) t))
                          (yeah-check--rules-with rules "@media print"))
          (push "the stylesheet does not print the pictures of the diagrams" failures))))
    failures))

(let ((failures (append (yeah-check--check-page (yeah-check--page))
                         (yeah-check--check-css (yeah-check--stylesheet)))))
  (dolist (failure failures)
    (message "site-diagrams: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-site-shows-the-diagrams.el ends here
