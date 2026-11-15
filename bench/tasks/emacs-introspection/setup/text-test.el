;;; text-test.el --- the test of text.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'text)

(ert-deftest text-trim-removes-both-ends ()
  (should (equal "hi" (text-trim "  hi \n")))
  (should (equal "a b" (text-trim "\t a b \t"))))

(provide 'text-test)
;;; text-test.el ends here
