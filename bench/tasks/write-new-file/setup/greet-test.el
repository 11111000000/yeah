;;; greet-test.el --- the test of greet.el -*- lexical-binding: t; -*-

(require 'ert)
(require 'greet)

(ert-deftest greet-names-the-person ()
  (should (equal "Hello, Ada!" (greet "Ada")))
  (should (equal "Hello, world!" (greet nil)))
  (should (equal "Hello, world!" (greet ""))))

(provide 'greet-test)
;;; greet-test.el ends here
