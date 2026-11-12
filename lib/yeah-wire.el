;;; yeah-wire.el --- shared stdio plumbing for the wire protocols -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; In batch mode Emacs reads standard input a line at a time with
;; `read-string'; `read-char' does not see it.  A server therefore reads one
;; request, then pumps the event loop until the work it started has settled,
;; so asynchronous answers leave immediately instead of waiting for the next
;; request.

;;; Code:

(require 'cl-lib)

(defgroup yeah-wire nil
  "Shared stdio plumbing for Yeah's wire protocols."
  :group 'yeah)

(defun yeah-wire-read-line ()
  "Read one line from standard input.
Return the line without its newline, or nil at end of file."
  (condition-case nil
      (let ((line (read-string "")))
        (if (or (null line) (string= line "")) nil line))
    (error nil)))

(defun yeah-wire-pump-until (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil or TIMEOUT seconds pass.
TIMEOUT defaults to 600 seconds.  Return non-nil when the predicate held."
  (let* ((deadline (+ (float-time) (or timeout 600)))
         (ok nil))
    (while (and (not ok) (< (float-time) deadline))
      (accept-process-output nil 0.05)
      (setq ok (and (functionp predicate) (funcall predicate))))
    ok))

(provide 'yeah-wire)
;;; yeah-wire.el ends here
