;;; strings-test.el --- the test of strings.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'strings)

(ert-deftest trim-spaces-trims-both-ends ()
  (should (equal "hi" (trim-spaces "  hi  ")))
  (should (equal "hi there" (trim-spaces " hi there ")))
  (should (equal "" (trim-spaces "   "))))

(provide 'strings-test)
;;; strings-test.el ends here
