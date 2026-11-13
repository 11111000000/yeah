;;; check-session-exports-to-org.el --- canary for the Org export -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The journal is written for the machine.  The export writes the same
;; truth for the person, in the format the person already reads: one
;; heading per event, the fields of the event as properties, and the text
;; of the event in a block that Org cannot mistake for syntax.
;;
;; Exit codes: 0 — the export is right; 1 — it is not.

;;; Code:

(require 'yeah-events)
(require 'yeah-org)
(require 'yeah-session)

(let* ((failures nil)
       (root (make-temp-file "yeah-org-check" t))
       (session (yeah-session-open "export" root))
       ;; The property names are checked as they are written: Org property
       ;; names are upper case, and a case-insensitive match would accept
       ;; anything.
       (case-fold-search nil))
  (unwind-protect
      (progn
        (yeah-events-write session "user-message" :payload "do the thing")
        (yeah-events-write session "tool-end" :tool "probe" :ok t
                            :payload "probe saw /tmp/probe-target")
        (yeah-events-write session "assistant-message" :payload "done")
        (let ((text (yeah-org-session-text session)))
          (unless (string-match-p "\\`#\\+TITLE: Yeah session export" text)
            (push "the export has no title" failures))
          (unless (string-match-p "^\\* user-message$" text)
            (push "the export has no heading for the question" failures))
          (unless (string-match-p "^\\* assistant-message$" text)
            (push "the export has no heading for the answer" failures))
          (unless (string-match-p ":TOOL: probe" text)
            (push "the export lost the tool of the call" failures))
          (unless (string-match-p "#\\+BEGIN_example\ndo the thing\n" text)
            (push "the payload is not in a block" failures))
          (unless (string-match-p "#\\+BEGIN_example\nprobe saw /tmp/probe-target\n"
                                 text)
            (push "the result of the tool is not in a block" failures))
          (when (string-match-p "^\\* header$" text)
            (push "the header of the journal was exported" failures))
          ;; The file is what the person opens.
          (let ((file (expand-file-name "export.org" root)))
            (yeah-org-export-session session file)
            (unless (file-exists-p file)
              (push "the export was not written" failures))
            (with-temp-buffer
              (insert-file-contents file)
              (unless (string= (buffer-string) text)
                (push "the file and the text are not the same" failures))))))
    (ignore-errors (delete-directory root t)))
  (dolist (failure failures)
    (message "org export: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-session-exports-to-org.el ends here
