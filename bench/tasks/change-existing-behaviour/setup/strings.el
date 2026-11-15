;;; strings.el -*- string helpers -*- lexical-binding: t; -*-

(defun trim-spaces (s)
  "Return S without leading and trailing spaces."
  (let ((start (if (string-match "\\`[ ]*" s) (match-end 0) 0)))
    (substring s start)))

(provide 'strings)
;;; strings.el ends here
