;;; check-the-code-packages-diagram-names-every-module-of-the-kernel.el --- the packages picture holds every module of the kernel -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The nine packages of the kernel are one knot and not nine layers: every
;; package reaches every other one, and the graph of the requires has no
;; level to speak of.  The picture of the knot shows the shape -- the
;; kernel in the middle and the nine packages around it -- and the
;; declaration of the picture names the modules of each package.
;;
;; This check reads `site/diagrams/code-packages.d2` and measures:
;;
;;   1. every module of `lib/` belongs to exactly one package of the
;;      declaration, or is excluded with the reason why it is in none.  A
;;      module that is nowhere is a module the picture dropped silently;
;;   2. the exclusions name modules that are there, and they say why;
;;   3. the picture names every package of the declaration;
;;   4. the numbers of the picture are the numbers the code holds: the
;;      number of the modules of the package, the number of the packages it
;;      needs and the number of the packages that need it.  A number that
;;      the code does not hold is a number the reader of the picture cannot
;;      trust.
;;
;; The declaration of the picture is the comment of its source: the picture
;; says what it is made of, and the comment says which module is of which
;; package.
;;
;; The rules of the reader of the pictures live in one place:
;; `tests/support/yeah-diagram-files.el`.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- the picture holds every module of the kernel and its
;; numbers are the numbers of the code; 1 -- it does not; 2 -- the tree is
;; not where we think, and the check cannot answer.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--blockers nil
  "The reasons why this check cannot answer.")

(defun yeah-check--package-of (owner module)
  "Return the name of the package that owns MODULE, or nil.
OWNER is the list of the packages and the modules of each.  The modules of
the declaration are the paths of the tree and the modules of the requires
are the names of the files, and the name of the file is the last part of
its path."
  (let (found)
    (dolist (entry owner)
      (when (cl-some (lambda (path) (string= (file-name-base path) module))
                     (cdr entry))
        (setq found (car entry))))
    found))

(defun yeah-check--degrees (root owner)
  "Return the degrees of the packages OWNER.
The answer is a list of (PACKAGE NEEDED WANTED): the name of the package,
the number of the other packages it needs and the number of the other
packages that need it.  A package that needs itself is not counted: the
requires inside a package are the code of the package and not an edge of
the graph of the packages."
  (let (edges)
    (dolist (edge (yeah-diagram--requires-of root))
      (let ((from (yeah-check--package-of owner (nth 0 edge)))
            (to (yeah-check--package-of owner (nth 1 edge))))
        (when (and from to (not (string= from to)))
          (push (cons from to) edges))))
    (setq edges (delete-dups edges))
    (mapcar
     (lambda (entry)
       (let ((package (car entry)))
         (list package
               (length (cl-remove-if-not (lambda (edge) (string= (car edge) package)) edges))
               (length (cl-remove-if-not (lambda (edge) (string= (cdr edge) package)) edges)))))
     owner)))

(defun yeah-check--card-name (label)
  "Return the name of the package that the card LABEL names.
The name is the lines of the label that are not the numbers: the lines of
the name may be broken at the backslash-n that D2 reads as a line break."
  (let (lines)
    (dolist (line (yeah-diagram--d2-label-lines label))
      (unless (or (string-suffix-p " modules" line)
                  (string-match "needs " line))
        (push line lines)))
    (string-join (nreverse lines) " ")))

(defun yeah-check--card-numbers (label)
  "Return the numbers of the card LABEL, or nil.
The numbers are the modules the package holds, the packages it needs and
the packages that need it: the card says 12 modules, and it says it needs
3 packages and is needed by 7."
  (let* ((lines (yeah-diagram--d2-label-lines label))
         (count (cl-find-if (lambda (line) (string-suffix-p " modules" line)) lines))
         (degrees (cl-find-if (lambda (line) (string-match "needs " line)) lines)))
    (when (and count degrees)
      (let* ((modules (string-to-number
                       (string-trim (substring count 0 -8))))
             (needs (string-search "needs " degrees))
             (wanted (string-search "needed by " degrees))
             (middle (string-trim (substring degrees (+ needs 6) wanted)))
             (first (string-trim (car (split-string middle ","))))
             (second (string-trim (substring degrees (+ wanted 10)))))
        (list modules (string-to-number first) (string-to-number second))))))

(let* ((root (expand-file-name default-directory))
       (reader (expand-file-name "tests/support/yeah-diagram-files.el" root))
       (diagram (expand-file-name "site/diagrams/code-packages.d2" root)))
  (unless (file-directory-p (expand-file-name "lib" root))
    (push "the tree of the repository is not where we think: there is no lib/"
          yeah-check--blockers))
  (unless (file-readable-p reader)
    (push "the tree of the repository is not where we think: there is no tests/support/yeah-diagram-files.el"
          yeah-check--blockers))
  (unless (file-readable-p diagram)
    (push "the tree of the repository is not where we think: there is no site/diagrams/code-packages.d2"
          yeah-check--blockers))
  (when (null yeah-check--blockers)
    (load reader nil t)
    (let* ((text (yeah-diagram--text diagram))
           (blocks (yeah-diagram--d2-blocks text))
           (declaration (yeah-diagram--d2-declaration text))
           (cards (cl-remove-if (lambda (block) (string= (nth 0 block) "knot")) blocks))
           (owner nil)
           (packages nil)
           (exclusions nil))
      ;; The declaration of the picture: the packages and the modules of
      ;; each, and the modules that are in no package.
      (dolist (line declaration)
        (if (yeah-diagram--declaration-package-p line)
            (let* ((colon (string-search ": " line))
                   (name (string-trim (substring line 0 colon)))
                   (modules (mapcar #'string-trim
                                    (split-string (string-trim (substring line (+ colon 2))) ", " t))))
              (push (cons name modules) owner)
              (push name packages))
          (let ((sep (string-search " -- " line)))
            (push (cons (string-trim (substring line 0 sep))
                        (string-trim (substring line (+ sep 4))))
                  exclusions))))
      (when (null packages)
        (push "the picture declares no package of the kernel" yeah-check--failures))
      ;; 1. every module of lib/ belongs to exactly one package.
      (dolist (module (yeah-diagram--modules-of root))
        (let* ((owners (cl-remove-if-not (lambda (entry) (member module (cdr entry))) owner)))
          (cond
           ((null owners)
            (unless (cl-find module (mapcar #'car exclusions) :test #'string=)
              (push (format "the module %s is in no package of the picture and is not excluded with a reason"
                            module)
                    yeah-check--failures)))
           ((> 1 (length owners))
            (push (format "the module %s is in %d packages of the picture"
                          module (length owners))
                  yeah-check--failures)))))
      ;; 2. the exclusions name modules that are there, and they say why.
      (dolist (exclusion exclusions)
        (let ((module (car exclusion))
              (reason (cdr exclusion)))
          (unless (file-exists-p (expand-file-name module root))
            (push (format "the declaration excludes %s, and there is no such module" module)
                  yeah-check--failures))
          (when (null reason)
            (push (format "the declaration excludes %s, and it does not say why" module)
                  yeah-check--failures))))
      ;; 3. the picture names every package of the declaration.
      (dolist (package packages)
        (unless (cl-some (lambda (card) (string= (yeah-check--card-name (nth 1 card)) package))
                         cards)
          (push (format "the picture has no card of the package %s" package)
                yeah-check--failures)))
      ;; 4. the numbers of the picture are the numbers the code holds.
      (dolist (entry (yeah-check--degrees root owner))
        (let* ((package (nth 0 entry))
              (needed (nth 1 entry))
              (wanted (nth 2 entry))
              (modules (length (cdr (assq package owner))))
              (card (cl-find-if (lambda (card) (string= (yeah-check--card-name (nth 1 card)) package))
                                cards)))
          (when card
            (let ((numbers (yeah-check--card-numbers (nth 1 card))))
              (unless numbers
                (push (format "the card of the package %s names no numbers" package)
                      yeah-check--failures))
              (when numbers
                (unless (= (nth 0 numbers) modules)
                  (push (format "the card of the package %s says %d modules, and the declaration holds %d"
                                package (nth 0 numbers) modules)
                        yeah-check--failures))
                (unless (= (nth 1 numbers) needed)
                  (push (format "the card of the package %s says it needs %d packages, and the code has %d"
                                package (nth 1 numbers) needed)
                        yeah-check--failures))
                (unless (= (nth 2 numbers) wanted)
                  (push (format "the card of the package %s says it is needed by %d packages, and the code has %d"
                                package (nth 2 numbers) wanted)
                        yeah-check--failures)))))))
      (dolist (failure yeah-check--failures)
        (message "code-packages-diagram: %s" failure))
      (if yeah-check--failures
          (kill-emacs 1)
        (kill-emacs 0))))
  (when yeah-check--blockers
    (dolist (blocker yeah-check--blockers)
      (message "code-packages-diagram: %s" blocker))
    (kill-emacs 2)))

;;; check-the-code-packages-diagram-names-every-module-of-the-kernel.el ends here
