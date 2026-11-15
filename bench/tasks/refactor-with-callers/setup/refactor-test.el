;;; refactor-test.el --- the test of the rename -*- lexical-binding: t; -*-

(require 'ert)
(require 'records)
(require 'main)

(ert-deftest the-function-has-the-new-name ()
  (should (fboundp 'record-format))
  (should-not (fboundp 'legacy-format)))

(ert-deftest the-callers-use-the-new-name ()
  (should (equal "apple: 3" (record-format '(:name "apple" :count 3))))
  (should (equal '("apple: 3" "pear: 5")
                 (render-records '((:name "apple" :count 3)
                                   (:name "pear" :count 5))))))

(provide 'refactor-test)
;;; refactor-test.el ends here
