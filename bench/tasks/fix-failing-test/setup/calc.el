;;; calc.el --- arithmetic for the benchmark -*- lexical-binding: t; -*-

(defun calc-average (numbers)
  "Return the average of NUMBERS."
  (/ (apply '+ numbers) (length numbers)))

(provide 'calc)
;;; calc.el ends here
