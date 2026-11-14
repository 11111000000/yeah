;;; test-yeah-result.el --- structured result and artifact tests -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'json)
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

(ert-deftest yeah-result-details-are-structured-and-json-safe ()
  (let* ((result (yeah-result-ok "short" '(:tick 7 :status ready :ids ("a" "b"))
                                 t '("/tmp/full")))
         (details (yeah-result-details result)))
    (should (eq t (plist-get details :truncated)))
    (should (equal ["/tmp/full"] (plist-get details :artifacts)))
    (should (= 7 (plist-get (plist-get details :metadata) :tick)))
    (should (equal "ready" (plist-get (plist-get details :metadata) :status)))
    (should (equal ["a" "b"]
                   (plist-get (plist-get details :metadata) :ids)))
    (should (stringp (json-serialize details)))
    (should (equal (concat "short\n[tick: 7]\n[Output truncated.]"
                           "\n[Full output: /tmp/full]")
                   (yeah-result-model-text result)))))

(ert-deftest yeah-result-details-omit-legacy-and-empty-metadata ()
  (should-not (yeah-result-details "legacy"))
  (should-not (yeah-result-details (yeah-result-ok "plain"))))

(provide 'test-yeah-result)
;;; test-yeah-result.el ends here
