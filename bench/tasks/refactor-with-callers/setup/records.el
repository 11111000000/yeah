;;; records.el -*- the records of the project -*- lexical-binding: t; -*-

(defun legacy-format (record)
  "Return RECORD formatted as one line of text."
  (format "%s: %d" (plist-get record :name) (plist-get record :count)))

(provide 'records)
;;; records.el ends here
