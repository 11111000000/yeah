;;; test-yeah-emacs.el --- tests for Emacs-native tools -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'yeah-emacs)

(ert-deftest yeah-emacs-introspect-reads-documentation-without-values ()
  (let* ((result (yeah-emacs-introspect "car" "function"))
         (text (yeah-result-model-text result)))
    (should (yeah-result-success-p result))
    (should (string-match-p "car" text))
    (should (string-match-p "Type: function" text))))

(ert-deftest yeah-emacs-introspect-rejects-unknown-symbol ()
  (let ((result (yeah-emacs-introspect "yeah-no-such-symbol-xyz" "function")))
    (should-not (yeah-result-success-p result))))

(ert-deftest yeah-emacs-elisp-check-accepts-readable-file ()
  (let ((file (make-temp-file "yeah-check" nil ".el" "(defun x () 1)\n")))
    (unwind-protect
        (let ((result (yeah-emacs-elisp-check file)))
          (should (yeah-result-success-p result))
          (should (string-match-p "1 forms"
                                  (yeah-result-model-text result))))
      (delete-file file))))

(ert-deftest yeah-emacs-elisp-check-rejects-unbalanced-file ()
  (let ((file (make-temp-file "yeah-check" nil ".el" "(defun x () 1\n")))
    (unwind-protect
        (should-not (yeah-result-success-p
                     (yeah-emacs-elisp-check file)))
      (delete-file file))))

(ert-deftest yeah-emacs-buffer-read-honors-lines-and-tick ()
  (with-temp-buffer
    (rename-buffer "yeah-buffer-test" t)
    (insert "one\ntwo\nthree\n")
    (let ((result (yeah-emacs-buffer-read (buffer-name) 2 1)))
      (should (yeah-result-success-p result))
      (should (equal "two\n" (plist-get result :content)))
      (should (integerp (plist-get (plist-get result :metadata) :tick))))))

(ert-deftest yeah-emacs-buffer-read-rejects-missing-buffer ()
  (should-not (yeah-result-success-p
               (yeah-emacs-buffer-read "yeah-no-buffer-xyz"))))

(ert-deftest yeah-emacs-diagnostics-reports-inactive-flymake ()
  (with-temp-buffer
    (let ((result (yeah-emacs-diagnostics)))
      (should-not (yeah-result-success-p result))
      (should (string-match-p "Flymake is not active"
                              (yeah-result-model-text result))))))

(ert-deftest yeah-emacs-tools-have-expected-names ()
  (should (equal '("introspect" "buffer-read" "elisp-check" "diagnostics")
                 (mapcar (lambda (spec) (plist-get spec :name))
                         (yeah-emacs-tools)))))

(provide 'test-yeah-emacs)
;;; test-yeah-emacs.el ends here
