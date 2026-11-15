;;; main.el -*- the caller of the records -*- lexical-binding: t; -*-

(require 'records)

(defun render-records (records)
  "Return one line of text per record in RECORDS."
  (mapcar #'legacy-format records))

(provide 'main)
;;; main.el ends here
