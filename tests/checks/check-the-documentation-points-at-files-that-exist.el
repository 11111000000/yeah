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
;; The things of the top level are the things that git knows about: the
;; files of the repository and the untracked files that are not ignored.
;; The directory of the repository is not a thing of the repository: `.'
;; is the repository itself and `..' is the way out of it.  A hidden name
;; is not a thing of it either: `.math/' is the state of the machine and
;; `.git/' is the machinery of git, and neither of them is a thing of the
;; repository that a reader can follow.
;;
;; The name that points out of the repository is left alone as well: a
;; name that starts with `..' points at a research clone that stands next
;; to it, and where that clone stands is not a fact of this repository.
;;
;; The output of a run is not a file of the repository either.  The record
;; of a bench run lies in `bench/results/', and the pictures of the pixel
;; checks lie in `tests/artifacts/': git ignores both, they are written by
;; the runs themselves, and a reader of a fresh copy of the repository has
;; no such thing.  An ignored name is left alone, the same way `.math/' is.
;;
;; This matters more than it looks.  The evidence of a claim is collected in
;; an isolated copy of the repository, and that copy holds the files of the
;; repository and nothing else.  A check that follows the output of an
;; earlier run answers "it is there" in the working tree and "it is not
;; there" in the copy -- the same check, two answers, and the negative
;; control that is supposed to prove the check bites bites for the wrong
;; reason.  A check that cannot answer the same way twice is not a check.
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

(defun yeah-check--git (args)
  "Run git with ARGS in the root of the project and return (EXIT . OUTPUT).
The process is started with `make-process': the check waits for git
without a shell and without spinning the event loop."
  (let ((buffer (generate-new-buffer " *yeah-check-git*"))
        (exit nil))
    (with-current-buffer buffer
      (let ((process
             (let ((default-directory (yeah-check--root)))
               (make-process
                :name "yeah-check-git"
                :buffer buffer
                :command (cons "git" args)
                :coding '(utf-8 . utf-8)
                :connection-type 'pipe
                :noquery t
                :sentinel
                (lambda (proc _event)
                  (when (memq (process-status proc) '(exit signal))
                    (setq exit (process-exit-status proc))))))))
        (while (and (null exit) (process-live-p process))
          (accept-process-output process 0.05))
        ;; The sentinel may run just before the final output filter callback.
        (accept-process-output nil 0.05)
        (let ((output (buffer-substring-no-properties (point-min) (point-max))))
          (kill-buffer buffer)
          (cons exit output))))))

(defun yeah-check--repository-files ()
  "Return the files of the repository, or nil when git cannot say.
The files are the ones git knows about: the tracked files and the
untracked files that are not ignored.  The copy of the repository that
the method makes for a negative control holds these files and nothing
else, so they are the files a reader of that copy can follow."
  (let ((result (yeah-check--git '("ls-files" "-z" "--cached" "--others"
                                  "--exclude-standard"))))
    (unless (eq (car result) 0)
      (push (format "git could not list the files of the repository: %s"
                    (string-trim (cdr result)))
            yeah-check--failures)
      nil)
    (split-string (cdr result) (string ?\C-@) t)))

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

(defun yeah-check--top-level (files)
  "Return the names of the things of the top level of the repository.
FILES are the files of the repository.  The directory of the repository
is not a thing of the repository: `.' is the repository itself and `..'
is the way out of it.  A hidden name is not a thing of it either:
`.math/' is the state of the machine and `.git/' is the machinery of
git.  Where they stand is not a fact of the repository, so a name that
names them is left alone."
  (let (names)
    (dolist (file files)
      (let ((name (car (split-string file "/" t))))
        (when (and (not (string-empty-p name))
                   (not (string-prefix-p "." name))
                   (not (cl-position name names :test #'string=)))
          (push name names))))
    (sort names #'string<)))

(defun yeah-check--ignored (paths)
  "Return the members of PATHS that git ignores.
An ignored path is the output of a run and not a thing of the
repository: it is not there in a fresh copy of the repository, and a
name that points at it is left alone.

Every name is asked about twice: as it is written and with a slash at
the end of it.  A rule of `.gitignore' that names a directory
(`tests/artifacts/') matches a name only when git knows the name to be
a directory, and git knows it only when the directory is there.  The
copy of the repository has no such directory, so the name with the
slash is the one that matches the rule there as well."
  (let* ((forms (cl-remove-duplicates
                 (append paths
                         (mapcar (lambda (path) (concat path "/")) paths))
                 :test #'string=))
         (result (yeah-check--git (append '("check-ignore") forms))))
    (cond ((eq (car result) 0)
           (mapcar #'yeah-check--strip-slash
                   (split-string (cdr result) "\n" t)))
          ((eq (car result) 1)
           nil)
          (t
           (push (format "git could not tell which names are ignored: %s"
                         (string-trim (cdr result)))
                 yeah-check--failures)
           nil))))

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

(defun yeah-check--path (token top-level)
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
                   (cl-position first top-level :test #'string=))
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

(defun yeah-check--names (file top-level)
  "Return the names of the repository that FILE mentions.
Every name is a triple: the line it stands on, the path of the
repository it names, and the number of the section it names, or nil."
  (with-temp-buffer
    (insert-file-contents file)
    (let (names)
      ;; the names of the files of the repository
      (goto-char (point-min))
      (while (re-search-forward "`\\([^`\n]+\\)`" nil t)
        (let ((line (line-number-at-pos (match-beginning 0)))
              (token (match-string 1)))
          (let ((path (yeah-check--path token top-level)))
            (when path
              (push (list line path nil) names)))))
      ;; the names of the sections of the documents
      (goto-char (point-min))
      (while (re-search-forward "`\\([^`\\n]+\\)`[ \t]*§[ \t]*\\([0-9A-Za-z.]+\\)" nil t)
        (let ((line (line-number-at-pos (match-beginning 0)))
              (token (match-string 1))
              (number (yeah-check--without-dots (match-string 2))))
          (let ((path (yeah-check--path token top-level)))
            (when path
              (push (list line path number) names)))))
      (nreverse names))))

(let ((documents (yeah-check--documents)))
  (when (null documents)
    (push "there is no document of the project to read" yeah-check--failures))
  (let* ((files (yeah-check--repository-files))
         (top-level (and files (yeah-check--top-level files)))
         (mentions nil)
         (names 0))
    (when top-level
      (dolist (document documents)
        (dolist (mention (yeah-check--names document top-level))
          (push (cons document mention) mentions))))
    ;; the names that git ignores are the output of a run and not a thing
    ;; of the repository: they are left alone
    (let* ((paths (delete-dups (mapcar #'cadr (mapcar #'cdr mentions))))
           (ignored (and paths (yeah-check--ignored paths))))
      (dolist (mention mentions)
        (let* ((document (car mention))
               (line (nth 1 mention))
               (path (nth 2 mention))
               (number (nth 3 mention)))
          (unless (and ignored (cl-position path ignored :test #'string=))
            (setq names (1+ names))
            (let ((target (expand-file-name path (yeah-check--root))))
              (unless (file-exists-p target)
                (push (format "%s: line %d: it names %s, and there is no such file"
                              (file-name-nondirectory document) line path)
                      yeah-check--failures))
              (when (and number (file-exists-p target))
                (unless (cl-position number (yeah-check--sections target) :test #'string=)
                  (push (format "%s: line %d: it names %s §%s, and there is no such section"
                                (file-name-nondirectory document) line path number)
                        yeah-check--failures))))))))
    (when (zerop names)
      (push "no name of the documentation was followed: this check cannot tell a good name from a bad one"
            yeah-check--failures))
    (dolist (failure yeah-check--failures)
      (message "docs: %s" failure))
    (if yeah-check--failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-the-documentation-points-at-files-that-exist.el ends here
