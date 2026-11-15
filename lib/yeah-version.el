;;; yeah-version.el --- a version token for a file on disk -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.

;;; Commentary:
;;
;; The modification tick of a buffer says what the model saw, and it exists
;; only when a buffer visits the file.  A file that nobody opened has no
;; tick: a read of it hands the model nothing to guard an edit with, and the
;; edit lands on whatever the file holds at that moment -- possibly text the
;; model never read.
;;
;; This module gives every file a version token: a digest of the text the
;; file holds right now.  A read hands the token out, an edit checks it, and
;; the guard of an edit no longer depends on a buffer being open.
;;
;; The token is short.  A model has to copy it back, and a model that copies
;; 64 characters of hex loses some of them: the pilot of 2026-11-15 saw a
;; token of 64 characters come back with six characters missing, and the edit
;; refused a file that had not changed.  Twelve characters of a sha256 leave
;; 48 bits -- enough to tell two states of a file apart -- and are short
;; enough to be copied back unchanged.

;;; Code:

(require 'cl-lib)

(defgroup yeah-version nil
  "Version tokens of files on disk."
  :group 'yeah)

(defconst yeah-version-length 12
  "The number of characters of the version token of a file.
The token is copied by a model, and a model that copies 64 characters of hex
loses some of them.")

(defun yeah-version--digest (text)
  "Return the digest of TEXT as a hexadecimal string."
  (secure-hash 'sha256 (encode-coding-string text 'utf-8-unix)))

(defun yeah-version--token (text)
  "Return the version token of TEXT: the first characters of its digest."
  (substring (yeah-version--digest text) 0 yeah-version-length))

(defun yeah-version-text (text)
  "Return the version token of the text TEXT.
The same text always gives the same token, and any change of the text gives
another one."
  (yeah-version--token text))

(defun yeah-version-file (path)
  "Return the version token of the file PATH, or nil when it cannot be read.
The file is read as UTF-8, the same way the read tool reads it, so the token
of a file and the token of a read of that file are the same token."
  (when (and path (file-readable-p path))
    (condition-case nil
        (with-temp-buffer
          (let ((coding-system-for-read 'utf-8-unix))
            (insert-file-contents (expand-file-name path)))
          (yeah-version--token (buffer-string)))
      (error nil))))

(provide 'yeah-version)
;;; yeah-version.el ends here
