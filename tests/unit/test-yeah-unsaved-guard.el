;;; test-yeah-unsaved-guard.el --- ERT tests for the guard of unsaved changes -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;; A read of a file shows the disk, and the tick it hands out belongs to the
;; buffer that visits the file.  When Emacs holds unsaved changes of that
;; file, an edit lands on the buffer and overwrites the changes of the
;; person with text the model never read.  D5 promises that the agent does
;; not edit such a file, and the promise does not depend on a version: a
;; model that presents no version has seen the same disk.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-edit)
(require 'yeah-files)
(require 'yeah-tools)

(defmacro yeah-unsaved-guard-test--with-tools (&rest body)
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

(defun yeah-unsaved-guard-test--cleanup (path)
  "Delete PATH and kill its visiting buffer without saving."
  (let ((buffer (find-buffer-visiting path)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (set-buffer-modified-p nil))
      (kill-buffer buffer)))
  (when (file-exists-p path)
    (delete-file path)))

(defun yeah-unsaved-guard-test--file-contents (path)
  "Return PATH decoded as UTF-8."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents path))
    (buffer-string)))

(ert-deftest yeah-unsaved-an-edit-without-a-version-is-refused ()
  "An edit of a file that Emacs holds unsaved changes of is refused even when
the model presents no version; the changes of the person stay in the buffer
and the file on disk keeps its text."
  (yeah-unsaved-guard-test--with-tools
    (let ((path (make-temp-file "yeah-unsaved-" nil ".txt")))
      (unwind-protect
          (progn
            (with-temp-file path (insert "alpha beta"))
            (let* ((version (plist-get (plist-get (yeah-files--read path)
                                                 :metadata)
                                       :version))
                   (buffer (find-file-noselect path)))
              (should (stringp version))
              ;; The person changes the file in Emacs and does not save it.
              (with-current-buffer buffer
                (goto-char (point-max))
                (insert " gamma"))
              (let ((refused (yeah-tools-call
                              "edit" (list path "beta" "omega" nil nil nil))))
                (should-not (yeah-result-success-p refused))
                (should (string-match-p "unsaved changes"
                                        (plist-get refused :error)))
                (should (equal "alpha beta gamma"
                               (with-current-buffer buffer (buffer-string))))
                (should (equal "alpha beta"
                               (yeah-unsaved-guard-test--file-contents path))))))
        (yeah-unsaved-guard-test--cleanup path)))))

(provide 'test-yeah-unsaved-guard)
;;; test-yeah-unsaved-guard.el ends here
