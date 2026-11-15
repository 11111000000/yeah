;;; text.el -*- text helpers -*- lexical-binding: t; -*-

(defun text-trim (s)
  "Return S without its leading whitespace."
  (replace-regexp-in-string "\\`[ \t\n]+" "" s))

(provide 'text)
;;; text.el ends here
