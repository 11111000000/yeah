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

(defun yeah-wire-print-line (text)
  "Write TEXT and a newline to standard output.
TEXT is one message of a wire protocol, serialized as JSON.  The
serializer returns a unibyte string whose bytes are UTF-8, and printing
such a string as it is makes Emacs read every byte as a character of
Latin-1 and write it back as UTF-8: the client reads the text twice
over, and a Russian answer arrives as mojibake.  The bytes are decoded
as UTF-8 before they are printed, so the client reads what the model
wrote.

A text that is not UTF-8 is printed as it is: a wire that carries
broken bytes is better than a wire that carries nothing."
  (princ (if (and (stringp text) (not (multibyte-string-p text)))
              (condition-case nil
                  (decode-coding-string text 'utf-8)
                (error text))
            text))
  (terpri))

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
