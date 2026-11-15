;;; stack-depth-test.el --- the test of stack-depth.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'stack-depth)

(ert-deftest stack-depth-counts-the-items ()
  (should (= 0 (stack-depth nil)))
  (should (= 2 (stack-depth '(1 2))))
  (should (= 3 (stack-depth '(1 2 3)))))

(provide 'stack-depth-test)
;;; stack-depth-test.el ends here
