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

;;; Code:

(require 'cl-lib)

(defgroup yeah-version nil
  "Version tokens of files on disk."
  :group 'yeah)

(defun yeah-version--digest (text)
  "Return the digest of TEXT as a hexadecimal string."
  (secure-hash 'sha256 (encode-coding-string text 'utf-8-unix)))

(defun yeah-version-text (text)
  "Return the version token of the text TEXT.
The same text always gives the same token, and any change of the text gives
another one."
  (yeah-version--digest text))

(defun yeah-version-file (path)
  "Return the version token of the file PATH, or nil when it cannot be read.
The file is read as UTF-8, the same way the read tool reads it, so the token
of a file and the token of a read of that file are the same token."
  (when (and path (file-readable-p path))
    (condition-case nil
        (with-temp-buffer
          (let ((coding-system-for-read 'utf-8-unix))
            (insert-file-contents (expand-file-name path)))
          (yeah-version--digest (buffer-string)))
      (error nil))))

(provide 'yeah-version)
;;; yeah-version.el ends here
