;;; stack-test.el --- the test of stack.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'stack)

(ert-deftest the-stack-holds-the-items ()
  (let ((stack (stack-push (stack-push nil 1) 2)))
    (should (equal '(2 1) stack))
    (should (equal 2 (stack-peek stack)))
    (should (equal '(1) (stack-pop stack)))))

(provide 'stack-test)
;;; stack-test.el ends here
