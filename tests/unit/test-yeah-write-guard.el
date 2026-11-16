;;; test-yeah-write-guard.el --- ERT tests for the guard of the write tool -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;; The write tool replaces a whole file, and a write that lands on a file
;; that changed after the read of that file overwrites text the model never
;; read.  The write therefore takes the same short version token as the
;; edit, and a token that is not the version of the file now is refused.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-edit)
(require 'yeah-files)
(require 'yeah-tools)
(require 'yeah-version)

(defmacro yeah-write-guard-test--with-tools (&rest body)
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

(defun yeah-write-guard-test--cleanup (path)
  "Delete PATH and kill its visiting buffer without saving."
  (let ((buffer (find-buffer-visiting path)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (set-buffer-modified-p nil))
      (kill-buffer buffer)))
  (when (file-exists-p path)
    (delete-file path)))

(defun yeah-write-guard-test--file-contents (path)
  "Return PATH decoded as UTF-8."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents path))
    (buffer-string)))

(ert-deftest yeah-write-a-stale-version-is-refused ()
  "A write that replaces a file presents the version of the read that it
follows, and is refused when the file changed since that read; the file keeps
the text it has now and the refusal reports the current version."
  (yeah-write-guard-test--with-tools
    (let ((path (make-temp-file "yeah-write-stale-" nil ".txt")))
      (unwind-protect
          (progn
            (with-temp-file path (insert "alpha beta"))
            (let* ((version (plist-get (plist-get (yeah-files--read path)
                                                 :metadata)
                                       :version)))
              (should (stringp version))
              ;; The file changes under the model after the read.
              (with-temp-file path (insert "gamma delta"))
              (let ((refused (yeah-tools-call
                              "write" (list path "omega" t version))))
                (let ((current (plist-get (plist-get refused :metadata) :version)))
                  (should-not (yeah-result-success-p refused))
                  (should (string-match-p "stale version"
                                          (plist-get refused :error)))
                  (should (equal (yeah-version-file path) current))
                  (should (equal "gamma delta"
                                 (yeah-write-guard-test--file-contents path)))))))
        (yeah-write-guard-test--cleanup path)))))

(ert-deftest yeah-write-a-current-version-replaces-the-file ()
  "A write that presents the version of the file it follows replaces the file
and the result says that the file was overwritten."
  (yeah-write-guard-test--with-tools
    (let ((path (make-temp-file "yeah-write-current-" nil ".txt")))
      (unwind-protect
          (progn
            (with-temp-file path (insert "alpha beta"))
            (let* ((version (plist-get (plist-get (yeah-files--read path)
                                                 :metadata)
                                       :version))
                   (result (yeah-tools-call
                            "write" (list path "gamma" t version))))
              (should (yeah-result-success-p result))
              (should (equal "gamma"
                             (yeah-write-guard-test--file-contents path)))
              (should (plist-get (plist-get result :metadata) :overwritten))))
        (yeah-write-guard-test--cleanup path)))))

(provide 'test-yeah-write-guard)
;;; test-yeah-write-guard.el ends here
