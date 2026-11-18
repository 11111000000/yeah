;;; check-the-site-shows-the-current-version.el --- the site shows the project as it is -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The site of the project is the page that a reader of Yeah sees first.  It
;; is checked into the repository without a build step, which means that
;; nothing keeps it in step with the project: a version can be written by
;; hand and forgotten, and a file of the site can be renamed while the page
;; still points at the old name.
;;
;; This check reads the version of the project from `VERSION' and reads the
;; page, and it proves two things: the page shows one version, and it is
;; the version the project has now, and every local file the page points at
;; is on disk.
;;
;; One version, and not "the version is somewhere on the page": a page that
;; was half updated carries two versions, and the reader of the page cannot
;; tell which one the project is at.
;;
;; The links to other sites are left alone: this check is about this
;; repository, and a link to the manual of Emacs is not a file of the
;; project.  The query of a link is not a part of the name of a file: a
;; page may ask for `assets/og.png?v=2' and the file it asks for is
;; `assets/og.png'.
;;
;; Exit codes: 0 -- the page shows the current version and points at files
;; that exist; 1 -- it does not.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

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

(defun yeah-check--version ()
  "Return the version of the project."
  (string-trim (yeah-check--read (expand-file-name "VERSION" (yeah-check--root)))))

(defun yeah-check--page ()
  "Return the text of the page of the site."
  (yeah-check--read (expand-file-name "site/index.html" (yeah-check--root))))

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

(defun yeah-check--without-v (text)
  "Return TEXT without the `v' it starts with.
The version of the project is written `0.3.0', and the page may write it
`v0.3.0'.  The `v' is a part of the way it is written and not a part of
the version itself."
  (if (string-prefix-p "v" text)
      (substring text 1)
    text))

(defun yeah-check--versions (page)
  "Return the versions the PAGE shows."
  ;; the boundaries of a word are `\\<' and `\\>', and the question mark of
  ;; the regexp of Emacs is the one that stands for "zero or one": `\\?' is
  ;; a question mark and not an operator
  (yeah-check--all-matches "\\<v?[0-9]+\\.[0-9]+\\.[0-9]+\\>" page))

(defun yeah-check--links (page)
  "Return the targets the PAGE points at."
  (let ((targets nil))
    (dolist (attribute '("href=\"" "src=\""))
      (let ((regexp (concat attribute "\\([^\"]*\\)\""))
            (start 0))
        (while (string-match regexp page start)
          (push (match-string 1 page) targets)
          (setq start (match-end 1)))))
    (delete-dups targets)
    (sort targets #'string<)))

(defun yeah-check--local-p (target)
  "Return non-nil when TARGET names a file of this repository."
  (not (or (string-prefix-p "http" target)
           (string-prefix-p "//" target)
           (string-prefix-p "mailto:" target)
           (string-prefix-p "data:" target)
           (string-prefix-p "#" target))))

(defun yeah-check--file (target)
  "Return the file TARGET names, without the query and the anchor of it."
  (let ((name (if (string-match-p "[?#]" target)
                  (substring target 0 (string-match "[?#]" target))
                target)))
    (expand-file-name name (expand-file-name "site" (yeah-check--root)))))

(let ((version (yeah-check--version))
      (page (yeah-check--page)))
  (when (string-empty-p version)
    (push "the version of the project is not to be read" yeah-check--failures))
  (when (string-empty-p page)
    (push "the page of the site is not to be read" yeah-check--failures))
  (unless (string-empty-p version)
    (let ((shown (yeah-check--versions page)))
      (when (null shown)
        (push (format "the page shows no version, the project is at %s" version)
              yeah-check--failures))
      (dolist (one shown)
        (unless (string= (yeah-check--without-v one) version)
          (push (format "the page shows the version %s, the project is at %s"
                        one version)
                yeah-check--failures)))))
  (dolist (target (yeah-check--links page))
    (when (yeah-check--local-p target)
      (unless (file-exists-p (yeah-check--file target))
        (push (format "the page points at %s and there is no such file" target)
              yeah-check--failures))))
  (dolist (failure yeah-check--failures)
    (message "site: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-site-shows-the-current-version.el ends here
