;;; yeah-journal-files.el --- the journals of a data home, not the lock files -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A data home holds the journals of its sessions and, while a process holds
;; a journal open, the lock file of Emacs next to it.  The lock file is not
;; a journal: it carries no record, it exists only while the file is held,
;; and it disappears without a warning.
;;
;; A check that reads every `.jsonl' file of a data home must therefore skip
;; the lock files and must survive a file that vanishes between the scan and
;; the read.  Without that, the check does not fail on its own assertion:
;; Emacs aborts with `file-missing', the method reads the crashed verifier
;; as an error and not as a proven control, and the verdict of the claim
;; becomes `inconclusive'.

;;; Code:

(require 'seq)

(defun yeah-journal-files--lock-p (file)
  "Return non-nil when FILE is a lock file of Emacs."
  (string-prefix-p ".#" (file-name-nondirectory file)))

(defun yeah-journal-files--files (data-home)
  "Return the journal files under DATA-HOME, without the lock files."
  (when (file-directory-p data-home)
    (seq-remove #'yeah-journal-files--lock-p
                (directory-files-recursively data-home "\\.jsonl\\'"))))

(defun yeah-journal-files--read (file)
  "Return the text of the journal FILE, or the empty string.
A file that vanished between the scan and the read is not a journal."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file)
        (buffer-string))
    (file-missing "")))

(defun yeah-journal-files--text (data-home)
  "Return the text of every journal under DATA-HOME."
  (mapconcat #'yeah-journal-files--read
             (yeah-journal-files--files data-home)
             "\n"))

(provide 'yeah-journal-files)
