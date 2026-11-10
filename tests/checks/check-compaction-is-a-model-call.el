;;; check-compaction-is-a-model-call.el --- canary for the context -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The summary of a run is written by the model: nothing else knows what
;; mattered in the conversation. The old outputs of the tools are pruned
;; separately, and a pruned record is still a record — the log is
;; append-only.
;;
;; The check asserts three things: the overflow of the context is seen,
;; the summary comes from the model and not from a placeholder, and the
;; records that were summarised are still on disk.
;;
;; Exit codes: 0 — the context behaves; 1 — it does not.

;;; Code:

(require 'yeah-context)
(require 'yeah-compact)
(require 'yeah-session)

(let* ((failures nil)
       (root (make-temp-file "yeah-context-check" t))
       (session (yeah-session-open "context" root))
       (asked nil)
       (answer "the model says what mattered"))

  ;; a run with a conversation in it
  (dotimes (i 6)
    (yeah-session-append session (list :type "user-message"
                                      :payload (format "question %d" i)))
    (yeah-session-append session (list :type "tool-end"
                                      :tool "read" :ok t
                                      :payload (format "the output of %d" i))))
  (yeah-session-append session (list :type "usage" :input 900 :output 120))

  ;; the context is seen
  (let ((usage (yeah-context-usage (yeah-session-records session))))
    (unless (> (plist-get usage :total) 0)
      (push "the context of the run was not counted" failures))
    (unless (equal (plist-get usage :reported) 1020)
      (push (format "the reported tokens were lost: %S" usage) failures)))
  (unless (yeah-context-overflow-p (yeah-session-records session) 500)
    (push "the overflow of the context was not seen" failures))

  ;; the summary is written by the model
  (let ((transport (lambda (prompt callback)
                     (setq asked prompt)
                     (funcall callback answer))))
    (unless (equal (yeah-context-summarize "a long conversation" transport) answer)
      (push "the summary was not the one the model wrote" failures))
    (unless asked
      (push "the model was not asked" failures)))

  ;; the compaction writes a projection and keeps the sources
  (let* ((result (yeah-compact-run session 40
                                   (lambda (records) answer)))
         (records (yeah-session-records session)))
    (unless result
      (push "the compaction returned nothing" failures))
    (unless (member "compaction" (mapcar (lambda (r) (plist-get r :type)) records))
      (push "the compaction left no record of itself" failures))
    ;; the sources are still there
    (let ((sources (cl-count-if (lambda (r) (equal (plist-get r :type) "tool-end"))
                                 records)))
      (unless (= 6 sources)
        (push (format "the sources did not survive the compaction: %d of 6" sources)
              failures))))

  ;; the old outputs are pruned, and a pruned record is still a record
  (let* ((records (yeah-session-records session))
         (pruned (yeah-context-prune records 40)))
    (unless (= (length records) (length pruned))
      (push "the pruning changed the number of records" failures))
    (unless (cl-some (lambda (r) (plist-get r :pruned)) pruned)
      (push "nothing was pruned" failures))
    (unless (cl-some (lambda (r) (equal (plist-get r :type) "tool-end")) pruned)
      (push "the pruned records are not records any more" failures)))

  (dolist (failure failures)
    (message "context: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-compaction-is-a-model-call.el ends here
