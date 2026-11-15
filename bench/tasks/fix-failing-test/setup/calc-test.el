;;; calc-test.el --- the test of calc.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'calc)

(ert-deftest calc-average-keeps-the-fraction ()
  (should (= 2.5 (calc-average '(1 2 3 4))))
  (should (= 3.0 (calc-average '(2 3 4)))))

(provide 'calc-test)
;;; calc-test.el ends here
