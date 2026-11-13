;;; check-sessions-have-a-tree.el --- canary for the sessions -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A project has many runs. A person needs to see which ones there are,
;; what each of them cost, and to be able to continue a run from a point
;; that is not the end — without the rest of the line disappearing.
;;
;; Exit codes: 0 — the sessions behave; 1 — they do not.

;;; Code:

(require 'yeah-sessions)
(require 'yeah-session)

(defun yeah-check--records (root name)
  "Return the records of the log of the session NAME under ROOT."
  (with-temp-buffer
    (insert-file-contents (expand-file-name (format "sessions/%s.jsonl" name) root))
    (mapcar (lambda (line) (json-parse-string line :object-type 'plist))
            (split-string (buffer-string) "\n" t))))

(let* ((failures nil)
       (root (make-temp-file "yeah-sessions-check" t))
       (first (yeah-session-open "alpha" root))
       (second (yeah-session-open "beta" root)))

  ;; two runs under one root
  (yeah-session-append first (list :type "user-message" :payload "one"))
  (yeah-session-append first (list :type "usage" :input 100 :output 20))
  (yeah-session-append first (list :type "user-message" :payload "two"))
  (yeah-session-append second (list :type "user-message" :payload "other"))

  ;; the index knows what there is
  (let ((index (yeah-sessions-index root)))
    (unless (= 2 (length index))
      (push (format "the index holds %d sessions, expected 2" (length index))
            failures))
    (unless (equal (mapcar (lambda (s) (plist-get s :id)) index) '("alpha" "beta"))
      (push "the index does not name the sessions in order" failures))
    (let ((alpha (cl-find-if (lambda (s) (equal (plist-get s :id) "alpha")) index)))
      (unless alpha
        (push "the index does not hold the first session" failures))
      (when alpha
        (let ((cost (plist-get alpha :cost)))
          (unless (> (plist-get cost :total) 0)
            (push "the index does not say what the session cost" failures))))))

  ;; the cost of a run is counted
  (let ((cost (yeah-sessions-cost (yeah-check--records root "alpha"))))
    (unless (= 100 (plist-get cost :reported-input))
      (push (format "the reported tokens were lost: %S" cost) failures))
    (unless (= 20 (plist-get cost :reported-output))
      (push (format "the output tokens were lost: %S" cost) failures))
    (unless (> (plist-get cost :estimated) 0)
      (push "the rest of the run was not estimated at all" failures)))

  ;; the tree: a branch keeps what was abandoned
  (let* ((records (yeah-check--records root "alpha"))
         (branch (yeah-sessions-branch records 1)))
    (unless (= 2 (length (plist-get branch :path)))
      (push (format "the branch holds %d records, expected 2"
                    (length (plist-get branch :path)))
            failures))
    (unless (= 2 (length (plist-get branch :abandoned)))
      (push (format "the abandoned path holds %d records, expected 2"
                    (length (plist-get branch :abandoned)))
            failures))
    (unless (= 4 (length records))
      (push "the branch changed the records that are on disk" failures)))

  (dolist (failure failures)
    (message "sessions: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-sessions-have-a-tree.el ends here
