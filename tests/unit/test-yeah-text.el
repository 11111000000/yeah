;;; test-yeah-text.el --- the text of the harness is always valid UTF-8 -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'json)
(require 'yeah-text)

(ert-deftest yeah-text-keeps-plain-text ()
  (should (equal "plain" (yeah-text-valid "plain")))
  (should (multibyte-string-p (yeah-text-valid "plain"))))

(ert-deftest yeah-text-replaces-a-byte-that-is-not-utf-8 ()
  (let ((text (yeah-text-valid (unibyte-string 104 105 178 33))))
    (should (multibyte-string-p text))
    (should (equal "hi�!" text))))

(ert-deftest yeah-text-reads-a-character-of-two-bytes ()
  (let ((text (yeah-text-valid (unibyte-string 208 178))))
    (should (equal "в" text)))
  (let ((text (yeah-text-valid (unibyte-string 226 130 172))))
    (should (equal "€" text))))

(ert-deftest yeah-text-replaces-a-raw-byte-inside-a-multibyte-string ()
  (let* ((broken (decode-coding-string (unibyte-string 104 105 178 33) 'utf-8))
         (text (yeah-text-valid broken)))
    (should (multibyte-string-p text))
    (should (equal "hi�!" text))))

(ert-deftest yeah-text-gives-json-text-it-can-write ()
  (dolist (broken (list (unibyte-string 104 178 33)
                         (decode-coding-string (unibyte-string 104 178 33) 'utf-8)))
    (let ((text (yeah-text-valid broken)))
      (should (stringp (json-serialize text)))
      (should (string-match-p "�" text)))))

(ert-deftest yeah-text-walks-a-value ()
  (let* ((value (list :a (unibyte-string 178)
                      :b (vector (unibyte-string 178))))
         (safe (yeah-text-value-valid value)))
    (should (equal "�" (plist-get safe :a)))
    (should (equal ["�"] (plist-get safe :b)))))

(ert-deftest yeah-text-leaves-what-is-not-text-alone ()
  (should (eq 42 (yeah-text-valid 42)))
  (should (eq 'sym (yeah-text-value-valid 'sym)))
  (should (eq nil (yeah-text-valid nil))))

;;; test-yeah-text.el ends here
