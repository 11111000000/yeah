;;; check-a-tool-call-carries-its-kind.el --- the call of a tool carries its kind -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The defect: the `tool_call' of the wire named the tool and carried what
;; it was called with and what it returned, but no kind.  A client that
;; renders the call of a tool by its kind -- a read, an edit, a shell -- saw
;; the name of the tool and nothing else, and the plugin of Paseo had to
;; guess the kind from the name of the tool.
;;
;; This check starts a real ACP server over stdio, creates a session whose
;; `cwd' is a temporary directory with a file in it, lets the model of the
;; server read that file, and proves on the wire that the call of the tool
;; carries its kind: the update that announced the call names the kind of
;; the read.
;;
;; The verdict is decided by construction: the kind of a call is a field of
;; the wire, and the control of the claim takes that field out -- the wire
;; stops carrying the kind -- and the check then fails by its own assertion.
;;
;; No network is involved: the model of the server is a fake that calls the
;; `read' tool and then the `finish' tool
;; (tests/support/yeah-tool-call-model.el), and a safe read is allowed
;; without a question.
;;
;; Exit codes: 0 -- the call of the tool carried its kind; 1 -- it did not.

;;; Code:

(load (expand-file-name "tests/support/yeah-acp-tool-call.el") nil t)

(defvar yeah-check--failures nil
  "The failures this check found.")

(let* ((workspace (make-temp-file "yeah-tool-kind" t))
       (update nil))
  (with-temp-file (expand-file-name "marker.txt" workspace)
    (insert "the marker of the session"))
  (unwind-protect
      (setq update (condition-case err
                      (yeah-acp-tool-call--drive workspace)
                    (error
                     (format "the session of the check did not run: %s"
                             (error-message-string err)))))
    (unless (equal "read" (and update (plist-get update :kind)))
      (push (format "the call of the tool did not carry its kind on the wire: it carried %S"
                    (and update (plist-get update :kind)))
            yeah-check--failures))
    (dolist (failure yeah-check--failures)
      (message "tool-kind: %s" failure))
    (ignore-errors (delete-directory workspace t))
    (if yeah-check--failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-a-tool-call-carries-its-kind.el ends here
