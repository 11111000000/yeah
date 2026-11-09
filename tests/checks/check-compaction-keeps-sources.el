;;; check-compaction-keeps-sources.el --- canary for compaction -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Compaction is a projection, not a deletion: the source records stay on
;; disk and the compaction record joins them. A compactor that truncated
;; the log would leave the in-memory projection shorter and the file
;; shorter, and the difference between the two is exactly what this check
;; looks at.
;;
;; Exit codes: 0 — the sources survived; 1 — they did not.

;;; Code:

(require 'yeah-session)
(require 'yeah-compact)

(defun yeah-check--records-of (path)
  "Return the parsed records of the JSONL file at PATH."
  (with-temp-buffer
    (insert-file-contents path)
    (mapcar (lambda (line) (json-parse-string line :object-type 'plist))
            (split-string (buffer-string) "\n" t))))

(let* ((root (make-temp-file "yeah-compact-check" t))
       (session (yeah-session-open "beta" root))
       (path (yeah-session--path-for "beta" root)))
  (dolist (n '(1 2 3 4 5 6))
    (yeah-session-append session (list :type "user" :payload (format "line-%d" n))))
  (let* ((before (yeah-check--records-of path))
         (result (yeah-compact-run session 40))
         (after (yeah-check--records-of path)))
    (unless result
      (message "the compactor returned nothing")
      (kill-emacs 1))
    (unless (= (1+ (length before)) (length after))
      (message "the log holds %d records after the compaction, expected %d"
               (length after) (1+ (length before)))
      (kill-emacs 1))
    (unless (equal before (butlast after))
      (message "the source records were not left alone by the compaction")
      (kill-emacs 1))
    (unless (string= (plist-get (car (last after)) :type) "compaction")
      (message "the compaction left no record of itself")
      (kill-emacs 1))))

(kill-emacs 0)

;;; check-compaction-keeps-sources.el ends here
