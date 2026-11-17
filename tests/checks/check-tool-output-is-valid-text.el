;;; check-tool-output-is-valid-text.el --- the output of a tool is text -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A tool of the agent can hand back bytes that are not text.  `tail -c'
;; cuts a character of a UTF-8 file in half, and `printf '\262'` writes a
;; byte that cannot start a UTF-8 sequence.  The bytes arrive in two
;; shapes: as a unibyte string of bytes, and as a multibyte string that
;; holds a raw byte where the decoder refused one.
;;
;; Both shapes are refused by JSON, and the refusal of JSON happens where
;; the journal is written.  The text of the harness must be text: a
;; multibyte string that JSON accepts, with the broken byte standing as
;; the replacement character and the rest of the text kept as it is.
;;
;; Exit codes: 0 — the output of the tool is text and the journal writes
;; it; 1 — it is not.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-text)
(require 'yeah-result)
(require 'yeah-session)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--unibyte-broken ()
  "Return bytes that are not valid UTF-8: a byte that cannot start a sequence."
  (unibyte-string 111 107 32 178 32 116 97 105 108))

(defun yeah-check--multibyte-broken ()
  "Return a multibyte string that holds a raw byte where the decoder refused one."
  (decode-coding-string (yeah-check--unibyte-broken) 'utf-8))

(defun yeah-check--text-p (value)
  "Return non-nil when VALUE is text that the journal can write.
Text is a multibyte string, and JSON accepts it."
  (and (stringp value)
       (multibyte-string-p value)
       (stringp (condition-case nil (json-serialize value) (error nil)))))

(defun yeah-check--expect (ok message)
  "Record MESSAGE as a failure when OK is nil."
  (unless ok
    (push message yeah-check--failures)))

(let* ((root (make-temp-file "yeah-valid-text" t))
       (session (yeah-session-open "valid-text" root)))
  (unwind-protect
      (progn
        ;; 1. The output of a tool is text, in both shapes of broken bytes.
        (dolist (broken (list (yeah-check--unibyte-broken)
                               (yeah-check--multibyte-broken)))
          (let* ((result (yeah-result-from-output broken))
                 (content (plist-get result :content))
                 (text (yeah-result-model-text result)))
            (yeah-check--expect
             (yeah-check--text-p content)
             "the output of the tool is not text that the journal can write")
            (yeah-check--expect
             (yeah-check--text-p text)
             "the text of the model is not text that the journal can write")
            ;; The broken byte stands as the replacement character, and the
            ;; text around it is kept as it is.
            (yeah-check--expect
             (and (string-match-p (char-to-string 65533) content)
                  (string-match-p "ok " content)
                  (string-match-p "tail" content))
             "the broken byte did not become the replacement character")))
        ;; 2. The journal writes a record that holds such text.
        (let* ((broken (yeah-check--multibyte-broken))
               (id (yeah-session-append
                    session (list :type "tool-end"
                                  :payload (list :content broken))))
               (path (plist-get session :path))
               (lines (and (file-exists-p path)
                            (with-temp-buffer
                              (insert-file-contents path)
                              (split-string (buffer-string) "\n" t)))))
          (yeah-check--expect (integerp id)
                              "the journal refused to write the record")
          (yeah-check--expect
           (cl-some (lambda (line)
                      (condition-case nil
                          (let ((record (json-parse-string line
                                                         :object-type 'plist
                                                         :array-type 'list)))
                            (equal "tool-end" (plist-get record :type)))
                        (error nil)))
                    lines)
           "the journal holds no readable record of the tool"))
        ;; 3. The text of the model is text as well.
        (let ((text (yeah-result-model-text
                     (list :yeah-error (yeah-check--unibyte-broken)))))
          (yeah-check--expect
           (yeah-check--text-p text)
           "the error of a tool is not text that the journal can write")))
    (ignore-errors (delete-directory root t t))
    (dolist (failure yeah-check--failures)
      (message "valid-text: %s" failure))
    (if yeah-check--failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-tool-output-is-valid-text.el ends here
