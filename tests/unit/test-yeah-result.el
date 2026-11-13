;;; test-yeah-result.el --- structured result and artifact tests -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'yeah-result)

(ert-deftest yeah-result-success-has-provider-safe-content ()
  (let ((result (yeah-result-ok "content" '(:count 1))))
    (should (yeah-result-success-p result))
    (should (equal "content" (yeah-result-model-text result)))))

(ert-deftest yeah-result-error-has-provider-safe-message ()
  (let ((result (yeah-result-error "bad input")))
    (should-not (yeah-result-success-p result))
    (should (equal "bad input" (yeah-result-model-text result)))))

(ert-deftest yeah-result-large-output-becomes-private-artifact ()
  (let ((yeah-result-artifact-directory (make-temp-file "yeah-artifacts" t))
        (text (make-string 100 ?x)))
    (unwind-protect
        (let* ((result (yeah-result-from-output text 10))
               (artifacts (plist-get result :artifacts))
               (file (car artifacts)))
          (should (plist-get result :truncated))
          (should (= 1 (length artifacts)))
          (should (file-exists-p file))
          (should (= #o600 (logand #o777 (file-modes file))))
          (should (equal text (with-temp-buffer
                                (insert-file-contents file)
                                (buffer-string))))
          (should (string-match-p "Output truncated"
                                  (yeah-result-model-text result))))
      (ignore-errors (delete-directory yeah-result-artifact-directory t t)))))

(ert-deftest yeah-result-legacy-values-remain-supported ()
  (should (equal "legacy" (yeah-result-model-text "legacy")))
  (should (equal "Error: old"
                 (yeah-result-model-text '(:yeah-error "Error: old")))))

(provide 'test-yeah-result)
;;; test-yeah-result.el ends here
