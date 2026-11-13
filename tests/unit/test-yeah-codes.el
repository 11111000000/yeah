;;; test-yeah-codes.el --- ERT tests for yeah-codes -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; PTC is experimental and disabled by default.  Evaluation tests explicitly
;; enable it in a dynamic scope; the security regression tests never assume
;; that the restricted evaluator is a general sandbox.

;;; Code:

(require 'ert)
(require 'yeah-codes)

(defmacro yeah-codes-test--enabled (&rest body)
  "Run BODY with experimental PTC explicitly enabled."
  (declare (indent 0))
  `(let ((yeah-codes-enable-ptc t))
     ,@body))

(ert-deftest yeah-codes-is-disabled-by-default ()
  (should-not yeah-codes-enable-ptc)
  (let ((yeah-codes-enable-ptc nil))
    (should-error (yeah-codes-eval '((:name "read" :code "42")))
                  :type 'user-error)))

(ert-deftest yeah-codes-whitelist-has-the-10-default-names ()
  (should (equal (yeah-codes-whitelist)
                 '("read" "edit" "grep" "glob" "bash"
                   "webfetch" "text" "image" "console" "exit"))))

(ert-deftest yeah-codes-allow-and-disallow ()
  (let ((yeah-codes--whitelist '("read")))
    (yeah-codes-allow "draft")
    (should (equal '("read" "draft") (yeah-codes-whitelist)))
    (yeah-codes-allow "draft")
    (should (equal '("read" "draft") (yeah-codes-whitelist)))
    (yeah-codes-disallow "draft")
    (should (equal '("read") (yeah-codes-whitelist)))))

(ert-deftest yeah-codes-eval-returns-ok-when-whitelisted ()
  (yeah-codes-test--enabled
    (let ((yeah-codes--whitelist '("read")))
      (let ((records (yeah-codes-eval '((:name "read" :code "(+ 1 2)")))))
        (should (= 1 (length records)))
        (should (eq t (plist-get (car records) :ok)))
        (should (equal "read" (plist-get (car records) :name)))
        (should (= 3 (plist-get (car records) :result)))))))

(ert-deftest yeah-codes-eval-rejects-unwhitelisted-name ()
  (yeah-codes-test--enabled
    (let ((yeah-codes--whitelist '("read")))
      (should-error (yeah-codes-eval '((:name "evil" :code "42")))
                    :type 'user-error))))

(ert-deftest yeah-codes-eval-passes-inputs ()
  (yeah-codes-test--enabled
    (let ((yeah-codes--whitelist '("read")))
      (let ((records (yeah-codes-eval '((:name "read" :code "(+ a b)"))
                                      '(("a" . 1) ("b" . 40)))))
        (should (= 41 (plist-get (car records) :result)))))))

(ert-deftest yeah-codes-eval-result-is-json-clean ()
  (yeah-codes-test--enabled
    (let ((yeah-codes--whitelist '("read")))
      (let* ((records (yeah-codes-eval
                       '((:name "read" :code "(list \"alpha\" \"beta\")"))))
             (value (plist-get (car records) :result)))
        (should (equal value (read (prin1-to-string value))))))))

(ert-deftest yeah-codes-eval-malformed-form-errors ()
  (yeah-codes-test--enabled
    (let ((yeah-codes--whitelist '("read")))
      (should-error (yeah-codes-eval '((:name "read" :code "(unclosed")))
                    :type 'user-error))))

(ert-deftest yeah-codes-rejects-higher-order-function-bypass ()
  (yeah-codes-test--enabled
    (let ((yeah-codes--whitelist '("read"))
          (target (make-temp-file "yeah-ptc-regression")))
      (unwind-protect
          (progn
            (should-error
             (yeah-codes-eval
              (list (list :name "read"
                          :code (format "(mapcar 'delete-file '(%S))" target))))
             :type 'user-error)
            (should (file-exists-p target)))
        (when (file-exists-p target)
          (delete-file target))))))

(ert-deftest yeah-codes-rejects-sort-predicate-bypass ()
  (yeah-codes-test--enabled
    (let ((yeah-codes--whitelist '("read"))
          (target (make-temp-file "yeah-ptc-sort-regression")))
      (unwind-protect
          (progn
            (should-error
             (yeah-codes-eval
              (list (list :name "read"
                          :code (format "(sort '(%S 1) 'delete-file)" target))))
             :type 'user-error)
            (should (file-exists-p target)))
        (when (file-exists-p target)
          (delete-file target))))))

(ert-deftest yeah-codes-sandbox-available-p-is-featurep ()
  (should (eq (yeah-codes-sandbox-available-p) (featurep 'sandbox))))

(provide 'test-yeah-codes)
;;; test-yeah-codes.el ends here
