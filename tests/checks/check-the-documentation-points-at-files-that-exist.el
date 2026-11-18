;;; check-the-documentation-points-at-files-that-exist.el --- the documentation points at what is there -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The documentation of the project is written by hand and it points at
;; other documents by name: "`docs/PLAN.md' §17.2" says "that part of that
;; plan", and "`lib/yeah-acp.el'" says "that file of the kernel".  A name
;; that nobody wrote any more is a dead end for the reader: the link looks
;; right and leads nowhere.
;;
;; This check reads every document of the project and follows every name it
;; finds.  It looks for two things and names the one that is broken: the
;; file the name points at must be on disk, and the section it names must
;; be a heading of that file.
;;
;; What is a name of this repository: a word in backticks whose first part
;; is a thing of the top level of the repository -- `lib/', `docs/',
;; `tests/', `AGENTS.md' and the like.  Such a word is a path of this
;; repository and it must exist.  Everything else is left alone: a command
;; (`scripts/dev gate'), a pattern (`lib/yeah-*.el'), a name of another
;; project (a file of Paseo) and a file of Emacs are not paths of this
;; repository, and a check that follows them is a check that cries wolf.
;;
;; The directory of the repository is not a thing of the repository
;; either.  A name that starts with `..' points out of the repository --
;; to a research clone that stands next to it, for example -- and where
;; that clone stands is not a fact of this repository.  The name of such
;; a path is left alone as well.
;;
;; The hidden names are left alone for the same reason: `.math/' is the
;; state of this machine and `.git/' is the machinery of git, and neither
;; of them is a thing of the repository that a reader can follow.
;;
;; The line of a name is a part of the name -- `lib/yeah-acp.el:1141' is
;; the file `lib/yeah-acp.el' -- and the punctuation of the text around the
;; name is not: "`lib/yeah-acp.el'," names the same file.
;;
;; Exit codes: 0 -- every name of the documentation leads to a file and a
;; section that are there; 1 -- one of them leads nowhere.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--sections-cache (make-hash-table :test #'equal)
  "The sections of the documents this check has read.")

(defun yeah-check--root ()
  "Return the root of the project."
  (expand-file-name default-directory))

(defun yeah-check--documents ()
  "Return the documents of the project that this check reads."
  (let (documents)
    (dolist (file (file-expand-wildcards (expand-file-name "docs/*.md" (yeah-check--root))))
      (push file documents))
    (dolist (file '("AGENTS.md" "README.md" "ELISP_BEST_PRACTICES.md"))
      (let ((path (expand-file-name file (yeah-check--root))))
        (when (file-readable-p path)
          (push path documents))))
    (sort documents #'string<)))

(defun yeah-check--top-level ()
  "Return the names of the things of the top level of the repository.
The directory of the repository is not a thing of the repository: `.'
is the repository itself and `..' is the way out of it.  A hidden name
is not a thing of it either: `.math/' is the state of the machine and
`.git/' is the machinery of git.  Where they stand is not a fact of the
repository, so a name that names them is left alone."
  (let (names)
    (dolist (path (directory-files (yeah-check--root) t nil nil))
      (let ((name (file-name-nondirectory path)))
        (unless (string-prefix-p "." name)
          (push name names))))
    (sort names #'string<)))

(defun yeah-check--strip-slash (path)
  "Return PATH without the slash at its end."
  (if (and (> (length path) 0) (eq (aref path (1- (length path))) ?/))
      (substring path 0 -1)
    path))

(defun yeah-check--without-dots (text)
  "Return TEXT without the dots at its ends.
The number of a section is written `17.' at the end of a sentence: the dot
belongs to the sentence and not to the number.  The dots are taken off
without a regexp: a regexp of Emacs wipes the data of the match that is
being read, and the line of the finding is read from that data."
  (let ((start 0)
        (end (length text)))
    (while (and (< start end) (eq (aref text start) ?.))
      (setq start (1+ start)))
    (while (and (< start end) (eq (aref text (1- end)) ?.))
      (setq end (1- end)))
    (substring text start end)))

(defun yeah-check--path (token)
  "Return the path of the repository that TOKEN names, or nil.
A token names a path of this repository when its first part is a thing of
the top level of the repository.  A command, a pattern, a name of another
project and a file of Emacs name nothing here."
  (when (and (not (string-match-p "[ \t\n]" token))
             (not (string-match-p "[*?]" token))
             (not (string-match-p "\\`[~$#@]" token))
             (not (string-match-p "://" token)))
    (when (string-match "\\`\\([A-Za-z0-9._/-]+\\)" token)
      (let* ((path (yeah-check--strip-slash (match-string 1 token)))
             (first (car (split-string path "/" t))))
        (when (and (not (string-empty-p path))
                   (cl-position first (yeah-check--top-level) :test #'string=))
          path)))))

(defun yeah-check--sections (file)
  "Return the numbers of the sections of FILE.
A section of the documentation is a heading that starts with a number:
`## 17. What is left', `### 16.45 The wave', `### D1 -- The journal', or
`### §11.1 -- know whether a variable is special'."
  (or (gethash file yeah-check--sections-cache)
      (puthash file
               (with-temp-buffer
                 (insert-file-contents file)
                 (goto-char (point-min))
                 (let (numbers)
                   (while (re-search-forward
                           "^#\\{1,6\\}[ \t]*§?[ \t]*\\([0-9]+\\(\\.[0-9]+\\)*\\|\\([A-Z][0-9]+\\)\\)"
                           nil t)
                     (push (match-string 1) numbers))
                   (sort numbers #'string<)))
               yeah-check--sections-cache)))

(defun yeah-check--scan (file)
  "Return the findings of FILE and the number of the names it followed.
The findings are the names of the file that lead nowhere.  The number of the
names is a part of the answer on purpose: a check that follows no name at
all cannot tell a good name from a bad one, and it has to say so instead of
passing."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((findings nil)
          (names 0))
      ;; the names of the files of the repository
      (goto-char (point-min))
      (while (re-search-forward "`\\([^`\n]+\\)`" nil t)
        (let ((line (line-number-at-pos (match-beginning 0)))
              (token (match-string 1)))
          (let ((path (yeah-check--path token)))
            (when path
              (setq names (1+ names))
              (unless (file-exists-p (expand-file-name path (yeah-check--root)))
                (push (format "line %d: it names %s, and there is no such file"
                              line path)
                      findings))))))
      ;; the names of the sections of the documents
      (goto-char (point-min))
      (while (re-search-forward "`\\([^`\n]+\\)`[ \t]*§[ \t]*\\([0-9A-Za-z.]+\\)" nil t)
        (let ((line (line-number-at-pos (match-beginning 0)))
              (token (match-string 1))
              (number (yeah-check--without-dots (match-string 2))))
          (let ((path (yeah-check--path token)))
            (when path
              (setq names (1+ names))
              (let ((target (expand-file-name path (yeah-check--root))))
                (when (file-exists-p target)
                  (unless (cl-position number (yeah-check--sections target) :test #'string=)
                    (push (format "line %d: it names %s §%s, and there is no such section"
                                  line path number)
                          findings))))))))
      (cons (nreverse findings) names))))

(let ((documents (yeah-check--documents)))
  (when (null documents)
    (push "there is no document of the project to read" yeah-check--failures))
  (let ((names 0))
    (dolist (document documents)
      (let ((result (yeah-check--scan document)))
        (setq names (+ names (cdr result)))
        (dolist (finding (car result))
          (push (format "%s: %s" (file-name-nondirectory document) finding)
                yeah-check--failures))))
    (when (zerop names)
      (push "no name of the documentation was followed: this check cannot tell a good name from a bad one"
            yeah-check--failures)))
  (dolist (failure yeah-check--failures)
    (message "docs: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-documentation-points-at-files-that-exist.el ends here
