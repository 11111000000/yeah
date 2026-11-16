;;; yeah-untrusted.el --- opening a file of an untrusted project -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The content of a project is untrusted input.  When Emacs opens a file it
;; looks for the local variables of that file and for the directory-local
;; variables of its directory, and it runs them: an `eval:' entry of the
;; local variables is Elisp that Emacs evaluates, and a `mode:' entry names a
;; function that Emacs calls.  A project can put that code into every file it
;; owns, and a directory-local file (`.dir-locals.el') puts it into every file
;; of a directory.
;;
;; The harness opens files of the project on behalf of the model, and it must
;; not run the code of the project in the Emacs of the person.  This module
;; opens a file with that machinery neutralized: the local variables of the
;; file and the directory-local variables of its directory are not executed.
;;
;; What is left is Emacs' own behaviour: the major mode of the buffer comes
;; from the name of the file (`auto-mode-alist'), which is Emacs' choice and
;; not the choice of the file.  The mode line of the file (`-*- mode: -*-') is
;; part of its content, so it is ignored here: a file may ask for a mode whose
;; function the project defines, and calling it would run the code of the
;; project.  The price is that a file whose mode differs from the mode of its
;; name comes up in the mode of its name.

;;; Code:

(defun yeah-untrusted-open-file (path)
  "Open PATH in a buffer and return it.
The local variables of the file and the directory-local variables of its
directory are not executed: the project is untrusted input, and the harness
does not run the code of the project in the Emacs of the person."
  (let ((enable-local-variables nil)
        (enable-local-eval nil)
        (enable-dir-local-variables nil))
    (find-file-noselect path)))

(provide 'yeah-untrusted)

;;; yeah-untrusted.el ends here
