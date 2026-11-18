;;; check-a-tool-call-carries-named-arguments.el --- the call of a tool carries its arguments by their names -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The defect: the arguments of a call travelled on the wire as a positional
;; list.  A client that looks for the named fields of a tool -- `path',
;; `old_str', `command' -- found nothing, and the client of Paseo could not
;; draw the edit of a file, because it reads the fields by their names.
;;
;; This check starts a real ACP server over stdio, creates a session whose
;; `cwd' is a temporary directory with a file in it, lets the model of the
;; server read that file, and proves on the wire that the call of the tool
;; carries its arguments under the names the tool declared: the update that
;; announced the call carries an object with the name of the argument and
;; its value, and not a list of values.
;;
;; The verdict is decided by construction: the control of the claim sends the
;; values in the order they came instead of the names they have, and the
;; check then fails by its own assertion: the call carries no named field.
;;
;; No network is involved: the model of the server is a fake that calls the
;; `read' tool and then the `finish' tool
;; (tests/support/yeah-tool-call-model.el), and a safe read is allowed
;; without a question.
;;
;; Exit codes: 0 -- the call of the tool carried its arguments by their
;; names; 1 -- it did not.

;;; Code:

(load (expand-file-name "tests/support/yeah-acp-tool-call.el") nil t)

(defvar yeah-check--failures nil
  "The failures this check found.")

(let* ((workspace (make-temp-file "yeah-tool-arguments" t))
       (update nil)
       (input nil))
  (with-temp-file (expand-file-name "marker.txt" workspace)
    (insert "the marker of the session"))
  (unwind-protect
      (setq update (condition-case err
                      (yeah-acp-tool-call--drive workspace)
                    (error
                     (format "the session of the check did not run: %s"
                             (error-message-string err)))))
    (setq input (and update (plist-get update :rawInput)))
    (unless (and (listp input)
                 (equal "marker.txt" (plist-get input :path)))
      (push (format "the call of the tool did not carry its arguments by their names on the wire: it carried %S"
                    input)
            yeah-check--failures))
    (dolist (failure yeah-check--failures)
      (message "tool-arguments: %s" failure))
    (ignore-errors (delete-directory workspace t))
    (if yeah-check--failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-a-tool-call-carries-named-arguments.el ends here
