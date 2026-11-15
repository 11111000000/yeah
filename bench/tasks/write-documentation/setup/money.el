;;; money.el -*- the amounts of the project -*- lexical-binding: t; -*-

(defun money-add (a b)
  "Return the sum of the amounts A and B."
  (+ a b))

(defun money-zero-p (amount)
  "Return non-nil when AMOUNT is zero."
  (= amount 0))

(provide 'money)
;;; money.el ends here
