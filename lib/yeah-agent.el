;;; yeah-agent.el --- declarative agent presets -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; An agent preset is a file: a name, a description, a model, the tools it
;; may use, and the prompt it is given.  Nothing about it is code, so a
;; person can write one and a child of Yeah can find it.
;;
;; The format is the one the other harnesses use: Markdown with a header
;; between two `---' lines, and Org with `#+NAME:' and friends.
;;
;;   ---
;;   name: reviewer
;;   description: Reviews a diff and says what is wrong with it.
;;   model: my-cheap-model
;;   tools: read, grep, diagnostics
;;   depth: 1
;;   ---
;;
;;   You are a reviewer. Look at the diff and say what is wrong with it.
;;
;; Discovery reads the header only.  The body of a preset is read when the
;; preset is used: a directory with fifty agents in it costs fifty header
;; reads, not fifty documents.

;;; Code:

(require 'cl-lib)
(require 'yeah-product)

(defgroup yeah-agent nil
  "Yeah declarative agent presets."
  :group 'yeah)

(defcustom yeah-agent-directories '("~/.config/yeah/agents" ".yeah/agents")
  "Directories the agent presets are looked for in.
A relative directory is resolved against the project root; `~' is
resolved against the home directory."
  :type '(repeat string)
  :group 'yeah-agent)

(defconst yeah-agent--front-matter-keys
  '("name" "description" "model" "tools" "depth" "budget")
  "The keys the header of a preset may carry.")

(defun yeah-agent--candidates (name)
  "Return the file names the preset NAME may have."
  (if (file-name-extension name)
      (list name)
    (list (concat name ".md")
          (concat name ".org")
          name)))

(defun yeah-agent--file (name &optional directories)
  "Return the file of the preset NAME, or nil.
The name may carry an extension: `reviewer' and `reviewer.md' name the
same file when only one of them exists.  The file is looked for in
DIRECTORIES, or in the directories of the user."
  (let ((found nil))
    (dolist (directory (or directories yeah-agent-directories))
      (unless found
        (dolist (candidate (yeah-agent--candidates name))
          (let ((path (expand-file-name candidate directory)))
            (when (and (file-readable-p path) (file-regular-p path))
              (setq found path))))))
    found))

(defun yeah-agent--header-end (text)
  "Return the number of characters of TEXT that hold its header.
Zero when the text has no header.

`string-match' is used and not `string-match-p', because only the
former updates the match data, and the end of the header is read from
it."
  (cond
   ((string-prefix-p "---" text)
    ;; A Markdown preset: the header is between the first `---' and the
    ;; next one.
    (let ((start 3))
      (when (string-match "\n---[ \t]*\n" text start)
        (match-end 0))))
   ((string-prefix-p "#+NAME:" text)
    ;; An Org preset has no delimiter: the header is the leading block
    ;; of #+KEY: lines.
    (let ((end 0)
          (pos 0))
      (while (string-match "\n#\\+[A-Za-z]+:[ \t]*" text pos)
        (setq end (match-end 0)
              pos (match-end 0)))
      (if (> end 0)
          ;; The header ends with the last of those lines, value included.
          (or (string-match "\n" text end) end)
        0)))
   (t 0)))

(defun yeah-agent--parse-line (line)
  "Return the (KEY . VALUE) pair of the header line LINE, or nil.
Both the Markdown form `key: value' and the Org form `#+KEY: value' are
understood."
  (when (string-match "\\`\\(#\\+?\\)?\\([A-Za-z_][A-Za-z0-9_-]*\\)[ \t]*:[ \t]*\\(.*\\)\\'" line)
    (cons (downcase (match-string 2 line))
          (string-trim (match-string 3 line)))))

(defun yeah-agent--parse-header (text)
  "Return the plist of the header of TEXT."
  (let ((end (yeah-agent--header-end text))
        (pairs nil))
    (when end
      (dolist (line (split-string (substring text 0 end) "\n" t))
        (let ((pair (yeah-agent--parse-line line)))
          (when (and pair (member (car pair) yeah-agent--front-matter-keys))
            (push (cons (intern (format ":%s" (car pair))) (cdr pair))
                  pairs)))))
    (apply #'append
           (mapcar (lambda (pair) (list (car pair) (cdr pair)))
                   (nreverse pairs)))))

(defun yeah-agent--tool-list (value)
  "Return the list of tool names in the header VALUE."
  (if (null value)
      nil
    (seq-remove (lambda (name) (string-empty-p name))
                (mapcar #'string-trim (split-string value "," t)))))

(defun yeah-agent--header (file)
  "Return the plist of the header of the preset FILE.
The body of the file is not read: only the header is."
  (with-temp-buffer
    (insert-file-contents file)
    (let* ((text (buffer-string))
           (end (yeah-agent--header-end text))
           (header (yeah-agent--parse-header text)))
      ;; `plist-put' mutates the plist it is given, so the empty one is
      ;; built afresh: a literal would be a constant shared by every call.
      ;; The assignments are one at a time: a `setq' with several pairs
      ;; does not promise that the next pair sees the previous one.
      (setq header (plist-put (or header (list :name nil)) :file file))
      (setq header (plist-put header :name (or (plist-get header :name)
                                                (file-name-base file))))
      (setq header (plist-put header :tools (yeah-agent--tool-list
                                                (plist-get header :tools))))
      (setq header (plist-put header :header-end end))
      header)))

(defun yeah-agent-discover (&optional directories)
  "Return the presets in DIRECTORIES, or in the directories of the user.
Only the header of a preset is read: the body is read when the preset
is used."
  (let ((presets nil)
        (seen nil))
    (dolist (directory (or directories yeah-agent-directories))
      (let ((path (expand-file-name directory)))
        (when (file-directory-p path)
          (dolist (file (directory-files path t "\\.\\(md\\|org\\)\\'"))
            (unless (member file seen)
              (push file seen)
              (push (yeah-agent--header file) presets))))))
    (sort presets (lambda (left right)
                    (string< (plist-get left :name) (plist-get right :name))))))

(defun yeah-agent-load (name &optional directories)
  "Return the preset NAME with its prompt, or nil.
The body of the preset is read here and nowhere else.  The preset is
looked for in DIRECTORIES, or in the directories of the user."
  (let ((file (yeah-agent--file name directories)))
    (when file
      (let ((header (yeah-agent--header file)))
        (with-temp-buffer
          (insert-file-contents file)
          (let ((text (buffer-string))
                (end (or (plist-get header :header-end) 0)))
            (setq header (plist-put header :prompt
                                    (string-trim (substring text end))))
            header))))))

(defun yeah-agent-find (name &optional directories)
  "Return the preset NAME with its header, or nil.
The body of the preset is not read.  The preset is looked for in
DIRECTORIES, or in the directories of the user."
  (let ((file (yeah-agent--file name directories)))
    (when file
      (yeah-agent--header file))))

(defun yeah-agent-names ()
  "Return the names of the presets the user can see."
  (mapcar (lambda (preset) (plist-get preset :name))
          (yeah-agent-discover)))

(provide 'yeah-agent)
;;; yeah-agent.el ends here
