;;; test-yeah-version-guard.el --- ERT tests for the guard of the version token -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;; The edit refuses a version token that is not the version of the file now.
;; The refusal names the token and reports the current one: a token that was
;; copied wrong does not mean that the file changed, and a model that is told
;; about a change that did not happen goes looking for one.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-edit)
(require 'yeah-files)
(require 'yeah-tools)
(require 'yeah-version)

(defmacro yeah-version-guard-test--with-tools (&rest body)
  "Register the edit tools around BODY and restore the test registry."
  (declare (indent 0) (debug t))
  `(unwind-protect
       (progn
         (yeah-tools-reset-for-test)
         (yeah-tools-unregister "edit")
         (yeah-tools-unregister "write")
         (dolist (spec (yeah-edit-tools))
           (yeah-tools-register spec))
         ,@body)
     (yeah-tools-reset-for-test)))

(defun yeah-version-guard-test--cleanup (path)
  "Delete PATH and kill its visiting buffer without saving."
  (let ((buffer (find-buffer-visiting path)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (set-buffer-modified-p nil))
      (kill-buffer buffer)))
  (when (file-exists-p path)
    (delete-file path)))

(defun yeah-version-guard-test--file-contents (path)
  "Return PATH decoded as UTF-8."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents path))
    (buffer-string)))

(defun yeah-version-guard-test--wrong (version)
  "Return VERSION with its first character changed: a token copied wrong."
  (concat (if (string= (substring version 0 1) "0") "1" "0")
          (substring version 1)))

(ert-deftest yeah-version-a-wrong-token-is-refused-with-the-current-one ()
  "An edit that presents a token which is not the version of the file now is
refused; the refusal names the token, does not blame a change of the file, and
reports the current token, so that a retry with it lands."
  (yeah-version-guard-test--with-tools
    (let ((path (make-temp-file "yeah-version-guard-" nil ".txt")))
      (unwind-protect
          (progn
            (with-temp-file path (insert "alpha beta"))
            (let* ((version (plist-get (plist-get (yeah-files--read path)
                                                 :metadata)
                                       :version))
                   (refused (yeah-tools-call
                             "edit" (list path "beta" "omega" nil nil
                                          (yeah-version-guard-test--wrong version))))
                   (error (plist-get refused :error))
                   (current (plist-get (plist-get refused :metadata) :version)))
              (should-not (yeah-result-success-p refused))
              (should (string-match-p "stale version" error))
              (should (string-match-p "copied wrong" error))
              (should-not (string-match-p "the file changed since the read" error))
              (should (equal (yeah-version-file path) current))
              ;; The file was not touched by the refused edit.
              (should (equal "alpha beta"
                             (yeah-version-guard-test--file-contents path)))
              ;; A retry with the token the refusal reported lands.
              (let ((retry (yeah-tools-call
                            "edit" (list path "beta" "omega" nil nil current))))
                (should (yeah-result-success-p retry))
                (should (equal "alpha omega"
                               (yeah-version-guard-test--file-contents path))))))
        (yeah-version-guard-test--cleanup path)))))

(provide 'test-yeah-version-guard)
;;; test-yeah-version-guard.el ends here
