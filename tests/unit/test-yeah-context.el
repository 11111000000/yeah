;;; test-yeah-context.el --- context budget and compaction tests -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-context)
(require 'yeah-compact)

(defun yeah-context-test--pump (predicate)
  "Pump the event loop until PREDICATE is true or two seconds pass."
  (let ((deadline (+ (float-time) 2)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.02))
    (funcall predicate)))

(ert-deftest yeah-context-estimate-is-cjk-aware ()
  (should (= 1 (yeah-context-estimate-tokens "abcd")))
  (should (= 2 (yeah-context-estimate-tokens "終端検査"))))

(ert-deftest yeah-context-calibration-clamps-to-safe-range ()
  (let ((yeah-context-token-calibration 1.0))
    (should (= 3.0 (yeah-context-calibrate
                    10 '(:yeah-usage (:input 100)))))
    (should (= 0.5 (yeah-context-calibrate
                    100 '(:yeah-usage (:input 10)))))
    (should (= 0.5 (yeah-context-calibrate
                    100 '(:yeah-usage (:input 0)))))))

(ert-deftest yeah-context-prune-preserves-source-records ()
  (let* ((source (list (list :type "tool-end" :payload "old")
                       (list :type "user-message" :payload "new")))
         (projected (yeah-context-prune source 1)))
    (should (plist-get (car projected) :pruned))
    (should-not (plist-get (car source) :pruned))))

(ert-deftest yeah-context-prune-session-appends-event ()
  (let* ((root (make-temp-file "yeah-prune" t))
         (session (yeah-session-open "prune" root)))
    (unwind-protect
        (progn
          (yeah-events-write session "tool-end" :tool "read" :ok t :payload "x")
          (yeah-context-prune-session session 1)
          (should (equal "pruning"
                         (plist-get (car (last (yeah-session-records session)))
                                    :type)))
          (should (plist-get (nth 1 (yeah-context-project session)) :pruned))
          (should-not (plist-get (nth 1 (yeah-session-records session)) :pruned)))
      (delete-directory root t))))

(ert-deftest yeah-context-summarize-async-does-not-block ()
  (let ((answered nil)
        (returned nil))
    (yeah-context-summarize-async
     "conversation"
     (lambda (_prompt callback)
       (run-at-time 0.02 nil (lambda () (funcall callback "summary" nil))))
     (lambda (summary _info) (setq answered summary)))
    (setq returned t)
    (should returned)
    (should-not answered)
    (should (yeah-context-test--pump (lambda () answered)))
    (should (equal "summary" answered))))

(ert-deftest yeah-context-summarize-async-rejects-blank-summary ()
  (let ((called nil))
    (yeah-context-summarize-async
     "conversation"
     (lambda (_prompt callback) (funcall callback "  " nil))
     (lambda (summary _info) (setq called summary)))
    (should-not called)))

(ert-deftest yeah-compact-async-commits-only-complete-summary ()
  (let* ((root (make-temp-file "yeah-compact-async" t))
         (session (yeah-session-open "compact" root))
         (result nil))
    (unwind-protect
        (progn
          (dotimes (index 3)
            (yeah-events-write session "user-message" :payload (number-to-string index)))
          (yeah-compact-run-async
           session 20
           (lambda (_prompt callback)
             (run-at-time 0.01 nil (lambda () (funcall callback "complete summary" nil))))
           (lambda (value _info) (setq result value)))
          (should (yeah-context-test--pump (lambda () result)))
          (should-not (plist-get result :error))
          (should (equal "complete summary" (plist-get result :summary)))
          (should (cl-some (lambda (record)
                             (equal "compaction" (plist-get record :type)))
                           (yeah-session-records session)))
          (let ((before (length (yeah-session-records session))))
            (yeah-compact-run-async
             session 20
             (lambda (_prompt callback) (funcall callback "" nil))
             (lambda (_value _info) (setq before before)))
            (should (= before (length (yeah-session-records session))))))
      (delete-directory root t))))

(provide 'test-yeah-context)
;;; test-yeah-context.el ends here
