;;; check-turn-compacts-asynchronously.el --- overflow drives async compaction -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; A tiny context budget forces compaction.  The summary arrives on a later
;; timer turn, so the turn must be in `compacting' before the wait and reach
;; `completed' only after the summary is committed and tool results continue.

;;; Code:

(require 'cl-lib)
(require 'yeah-turn)
(require 'yeah-tools)
(require 'yeah-perm)

(let* ((root (make-temp-file "yeah-turn-compact" t))
       (session (yeah-session-open "compact" root))
       (turn nil)
       (deadline (+ (float-time) 3)))
  (unwind-protect
      (progn
        (yeah-tools-reset-for-test)
        (yeah-perm-rules-reset-for-test)
        (yeah-tools-register
         (list :name "probe" :description "probe" :input nil
               :handler (lambda () "tool output")))
        (yeah-perm-rules-add (yeah-perm-rule-make "probe" "*" 'allow))
        (let ((transport
               (lambda (prompt callback)
                 (if (string-prefix-p "Summarize this conversation" prompt)
                     ;; The summary is deliberately asynchronous.
                     (run-at-time 0.03 nil
                                  (lambda ()
                                    (funcall callback "the retained summary" nil)))
                   (funcall callback
                            (list 'tool-call
                                  (list (list :name "probe") nil
                                        (lambda (_value)
                                          (funcall callback "finished")))))))))
          (setq turn (yeah-turn-run session "start" transport nil 1))
          (unless (eq 'compacting (yeah-turn-state turn))
            (message "turn did not enter compacting without blocking: %S"
                     (yeah-turn-state turn))
            (kill-emacs 1))
          (while (and (not (yeah-turn-done turn))
                      (< (float-time) deadline))
            (accept-process-output nil 0.02))
          (unless (and (yeah-turn-done turn)
                       (eq 'completed (yeah-turn-state turn)))
            (message "turn did not complete after compaction: %S"
                     (yeah-turn-state turn))
            (kill-emacs 1))
          (let* ((records (yeah-session-records session))
                 (compaction (cl-find-if
                              (lambda (record)
                                (equal "compaction" (plist-get record :type)))
                              records))
                 (assistant (cl-find-if
                             (lambda (record)
                               (equal "assistant-message" (plist-get record :type)))
                             records)))
            (unless (and compaction assistant
                         (< (plist-get compaction :id)
                            (plist-get assistant :id)))
              (message "compaction did not precede the continued answer: %S" records)
              (kill-emacs 1))
            (unless (equal "the retained summary" (plist-get compaction :summary))
              (message "the committed summary is wrong: %S" compaction)
              (kill-emacs 1))
            (unless (cl-some (lambda (record)
                               (equal "tool-end" (plist-get record :type)))
                             records)
              (message "compaction removed the source tool event")
              (kill-emacs 1)))))
    (ignore-errors (delete-directory root t t)))
  (kill-emacs 0))

;;; check-turn-compacts-asynchronously.el ends here
