;;; yeah-text.el --- the text of the harness is always valid UTF-8 -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A tool of the agent can return bytes that are not text.  `tail -c' cuts a
;; character of a UTF-8 file in half, and the process hands the raw byte to
;; the harness.  A unibyte string with such a byte cannot be written into the
;; journal: `json-serialize' refuses it, and the refusal arrives inside the
;; sentinel of the process, where the turn does not stand — the whole Emacs
;; process dies, and the run leaves no record of itself.
;;
;; This module is the one place that decides what the text of the harness is.
;; `yeah-text-valid' returns text that is always valid UTF-8: a byte sequence
;; that is not valid UTF-8 becomes the replacement character, and everything
;; else is kept as it is.  `yeah-text-value-valid' walks a value and makes
;; every string in it valid.
;;
;; Two shapes of broken text arrive from the outside.  A unibyte string holds
;; bytes, and the bytes that are not valid UTF-8 become the replacement
;; character.  A multibyte string holds characters, and the decoder of a
;; process leaves the bytes it could not decode as raw bytes inside it: a
;; character whose code is at or above #x3FFF00.  Such a string is multibyte
;; and is not text either, and JSON refuses it.

;;; Code:

(require 'cl-lib)

(defgroup yeah-text nil
  "Valid UTF-8 text for the harness."
  :group 'yeah)

(defconst yeah-text--replacement (string 65533)
  "The character that stands for a byte that is not valid UTF-8.")

(defconst yeah-text--raw-byte-min #x3FFF00
  "The smallest code point of a raw byte inside a multibyte string.
A decoder that refuses a byte leaves it in the string as a raw byte, and
the code point of such a character is in the range from this one up to
#x3FFFFF.")

(defun yeah-text--sequence-length (byte)
  "Return the length of the UTF-8 sequence that starts with BYTE, or nil."
  (cond ((<= byte #x7f) 1)
        ((<= byte #xbf) nil)
        ((<= byte #xdf) 2)
        ((<= byte #xef) 3)
        ((<= byte #xf4) 4)
        (t nil)))

(defun yeah-text--continuation-p (byte)
  "Return non-nil when BYTE continues a UTF-8 sequence."
  (and (>= byte #x80) (<= byte #xbf)))

(defun yeah-text--decode (bytes)
  "Return the text of the UTF-8 sequence BYTES.
A sequence that the decoder refuses is not text either, and it becomes the
replacement character.  The result is a multibyte string: the text of the
harness holds characters and not bytes."
  (condition-case nil
      (string-to-multibyte
       (decode-coding-string (apply #'unibyte-string (append bytes nil)) 'utf-8))
    (error yeah-text--replacement)))

(defun yeah-text--replace (bytes)
  "Return the text of BYTES with every invalid sequence replaced.
A sequence that starts with a byte that cannot start one, or that is cut in
half, becomes the replacement character, and the bytes after it are read as
they are."
  (let* ((vector (vconcat bytes))
         (result nil)
         (index 0)
         (length (length vector)))
    (while (< index length)
      (let* ((byte (aref vector index))
             (size (yeah-text--sequence-length byte)))
        (if (and size
                 (<= (+ index size) length)
                 (cl-every (lambda (offset)
                             (yeah-text--continuation-p
                              (aref vector (+ index offset))))
                           (number-sequence 1 (1- size))))
            (progn
              (push (yeah-text--decode
                     (cl-subseq vector index (+ index size)))
                    result)
              (setq index (+ index size)))
          (push yeah-text--replacement result)
          (setq index (1+ index)))))
    (apply #'concat (nreverse result))))

(defun yeah-text--raw-byte-p (char)
  "Return non-nil when CHAR is a raw byte that a decoder refused."
  (and (integerp char) (>= char yeah-text--raw-byte-min)))

(defun yeah-text--clean-raw (string)
  "Return STRING with every raw byte replaced by the replacement character.
A string that holds no raw byte is returned as it is."
  (let ((chars (append string nil)))
    (if (cl-some #'yeah-text--raw-byte-p chars)
        (apply #'concat
               (mapcar (lambda (char)
                         (if (yeah-text--raw-byte-p char)
                             yeah-text--replacement
                           (char-to-string char)))
                       chars))
      string)))

(defun yeah-text-valid (string)
  "Return STRING as text that is always valid UTF-8.
The result is a multibyte string: it holds characters and not bytes.  A
multibyte string is returned as it is when it holds no raw byte.  A unibyte
string is read as UTF-8, and every byte sequence that is not valid UTF-8
becomes the replacement character.  A multibyte string that holds raw bytes
is read as well, and every raw byte becomes the replacement character."
  (cond ((not (stringp string)) string)
        ((multibyte-string-p string) (yeah-text--clean-raw string))
        (t (yeah-text--clean-raw
            (yeah-text--replace (string-to-list string))))))

(defun yeah-text-value-valid (value)
  "Return VALUE with every string in it valid UTF-8.
A plist keeps its keys and its order, a vector keeps its shape, and a value
that is not text is returned as it is."
  (cond ((stringp value) (yeah-text-valid value))
        ((vectorp value) (vconcat (mapcar #'yeah-text-value-valid value)))
        ((consp value)
         (let ((tail (cdr value)))
           (cons (yeah-text-value-valid (car value))
                 (if (listp tail)
                     (mapcar #'yeah-text-value-valid tail)
                   (yeah-text-value-valid tail)))))
        (t value)))

(provide 'yeah-text)
;;; yeah-text.el ends here
