;;; test-yeah-untrusted.el --- ERT tests for opening an untrusted file -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;; Emacs runs the local variables of a file and the directory-local variables of
;; its directory when it opens it.  That code belongs to the project, and the
;; project is untrusted input: the harness opens the files of the project on
;; behalf of the model, and it must not run the code of the project in the
;; Emacs of the person.  The test puts a file with such variables into a
;; temporary directory and edits it with the configuration of an Emacs that
;; obeys them, which is the configuration that would run the code.
;;
;; The file asks for a mode and for an eval.  The mode is the sharp edge: Emacs
;; calls the function that the mode names, and the name may be a function of
;; the project.  The eval runs when the mode runs its hooks, which is what a
;; major mode does.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-edit)
(require 'yeah-files)
(require 'yeah-tools)

(defvar yeah-untrusted-test--mode-ran nil
  "Non-nil when the mode named by the local variables of the file was called.")

(defvar yeah-untrusted-test--eval-ran nil
  "Non-nil when the eval entry of the local variables of the file ran.")

(defun yeah-untrusted-test--evil-mode ()
  "The mode that the local variables of the file ask for.
It records that it was called and runs its hooks, the way a major mode does,
so that the local variables of the file are applied under it."
  (setq yeah-untrusted-test--mode-ran t)
  (run-mode-hooks 'yeah-untrusted-test--evil-mode-hook))

(defun yeah-untrusted-test--file (directory)
  "Write a file with local variables into DIRECTORY and return its path.
The file asks for a mode that records that it was called and for an eval
entry that records that it ran."
  (let ((path (expand-file-name "guarded.txt" directory)))
    (with-temp-file path
      (insert "alpha beta\n")
      ;; The name of the section is split, so that this file does not
      ;; hold a block of local variables of its own.
      (insert (concat ";; Local Var" "iables:\n"))
      (insert ";; mode: yeah-untrusted-test--evil\n")
      (insert ";; eval: (setq yeah-untrusted-test--eval-ran t)\n")
      (insert ";; End:\n"))
    path))

(defun yeah-untrusted-test--cleanup (path)
  "Delete PATH and kill its visiting buffer without saving."
  (let ((buffer (find-buffer-visiting path)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (set-buffer-modified-p nil))
      (kill-buffer buffer)))
  (when (file-exists-p path)
    (delete-file path)))

(ert-deftest yeah-untrusted-an-edit-does-not-run-the-local-variables ()
  "An edit of a file whose local variables would run Elisp does not run it,
even when the Emacs of the person obeys those variables."
  (yeah-tools-reset-for-test)
  (unwind-protect
      (progn
        (yeah-tools-unregister "edit")
        (yeah-tools-unregister "write")
        (dolist (spec (yeah-edit-tools))
          (yeah-tools-register spec))
        (let* ((directory (file-name-as-directory (make-temp-file "yeah-untrusted-" t)))
               (path (yeah-untrusted-test--file directory)))
          (unwind-protect
              (progn
                (setq yeah-untrusted-test--mode-ran nil)
                (setq yeah-untrusted-test--eval-ran nil)
                ;; The configuration of an Emacs that obeys the local
                ;; variables of the files it opens.
                (let ((enable-local-variables t)
                      (enable-local-eval t)
                      (enable-dir-local-variables t))
                  (let ((result (yeah-tools-call
                                 "edit" (list path "beta" "omega"))))
                    (should (yeah-result-success-p result))
                    (should-not yeah-untrusted-test--mode-ran)
                    (should-not yeah-untrusted-test--eval-ran))))
            (yeah-untrusted-test--cleanup path)
            (delete-directory directory t))))
    (yeah-tools-reset-for-test)))

(provide 'test-yeah-untrusted)
;;; test-yeah-untrusted.el ends here
