;;; test-yeah-control.el --- queued human control tests -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-control)
(require 'yeah-input)
(require 'yeah-tools)
(require 'yeah-perm)
(require 'yeah-process)

(defmacro yeah-control-test--with-tools (&rest body)
  "Run BODY with fresh permissions and an isolated process registry."
  (declare (indent 0))
  `(unwind-protect
       (progn
         (yeah-tools-reset-for-test)
         (yeah-perm-rules-reset-for-test)
         (yeah-perm-rules-add (yeah-perm-rule-make "probe" "*" 'allow))
         (yeah-perm-rules-add (yeah-perm-rule-make "bash" "*" 'allow))
         (let ((yeah-process--jobs (make-hash-table :test 'equal))
               (yeah-process--next-id 0))
           ,@body))
     (yeah-tools-reset-for-test)
     (yeah-perm-rules-reset-for-test)))

(defun yeah-control-test--answer (name args continuation)
  "Return a gptel-shaped tool-call for NAME, ARGS and CONTINUATION."
  (list 'tool-call (list (list :name name) args continuation)))

(defun yeah-control-test--wait (predicate)
  "Pump the event loop until PREDICATE is true or two seconds pass."
  (let ((deadline (+ (float-time) 2)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.01))
    (funcall predicate)))

(ert-deftest yeah-control-steering-arrives-after-tool-batch ()
  (yeah-control-test--with-tools
    (let* ((directory (make-temp-file "yeah-steering" t))
           (yeah-input-directory directory)
           (session (yeah-session-open "steering" directory))
           (tool-done nil)
           (seen-result nil))
      (unwind-protect
          (progn
            (yeah-tools-register
             (list :name "probe" :description "probe" :input nil :async t
                   :handler (lambda (_args done) (setq tool-done done))))
            (let* ((transport
                    (lambda (prompt callback)
                      (if (equal "first" prompt)
                          (funcall callback
                                   (yeah-control-test--answer
                                    "probe" nil
                                    (lambda (value)
                                      (setq seen-result value)
                                      (funcall callback "finished"))))
                        (funcall callback "finished"))))
                   (control (yeah-control-new session transport nil 60000 0)))
              (yeah-control-ask control "first")
              (should (eq 'awaiting-tool
                          (yeah-turn-state (yeah-control-active-turn control))))
              (yeah-control-steer control "clarify")
              (should (= 1 (length (yeah-control-pending control))))
              (should-not seen-result)
              (funcall tool-done "tool-result")
              (should (string-match-p "User clarification: clarify" seen-result))
              (should (yeah-control-done-p control))
              (should (cl-some (lambda (record)
                                 (equal "steering" (plist-get record :type)))
                               (yeah-session-records session)))))
        (ignore-errors (delete-directory directory t t))))))

(ert-deftest yeah-control-cancel-allows-next-queued-ask ()
  (yeah-control-test--with-tools
    (let* ((directory (make-temp-file "yeah-queue" t))
           (yeah-input-directory directory)
           (session (yeah-session-open "queue" directory))
           (callbacks nil))
      (unwind-protect
          (progn
            (yeah-tools-register
             (list :name "probe" :description "probe" :input nil :async t
                   :handler (lambda (_args done)
                              (push done callbacks))))
            (let* ((transport
                    (lambda (prompt callback)
                      (if (equal "first" prompt)
                          (funcall callback
                                   (yeah-control-test--answer
                                    "probe" nil
                                    (lambda (value)
                                      (funcall callback value))))
                        (funcall callback "second done"))))
                   (control (yeah-control-new session transport nil 60000 0)))
              (yeah-control-ask control "first")
              (yeah-control-ask control "second")
              (should (= 1 (length (yeah-control-pending control))))
              (yeah-control-cancel control "test cancel")
              (should (yeah-control-done-p control))
              (should (= 0 (length (yeah-control-pending control))))
              (should (cl-some (lambda (record)
                                 (and (equal "assistant-message" (plist-get record :type))
                                      (equal "second done" (plist-get record :payload))))
                               (yeah-session-records session)))))
        (ignore-errors (delete-directory directory t t))))))

(ert-deftest yeah-control-restart-recovery-is-explicit ()
  (yeah-control-test--with-tools
    (let* ((directory (make-temp-file "yeah-recovery" t))
           (yeah-input-directory directory)
           (session (yeah-session-open "recovery" directory))
           (calls 0))
      (unwind-protect
          (progn
            (yeah-input-enqueue
             session
             (list :kind 'ask :prompt "recovered"
                   :frozen '(:budget 123 :max-nudges 0 :model "frozen")))
            (let ((control
                   (yeah-control-new
                    session
                    (lambda (_prompt callback)
                      (setq calls (1+ calls))
                      (funcall callback "done"))
                    nil 60000 0)))
              (should (= 0 calls))
              (should (= 1 (length (yeah-control-pending control))))
              (yeah-control-recover-next control)
              (should (= 1 calls))
              (should (yeah-control-done-p control))
              (should (= 0 (length (yeah-control-pending control))))))
        (ignore-errors (delete-directory directory t t))))))

(ert-deftest yeah-turn-cancel-stops-managed-process-and-late-callbacks ()
  (yeah-control-test--with-tools
    (let* ((directory (make-temp-file "yeah-cancel-process" t))
           (yeah-input-directory directory)
           (session (yeah-session-open "cancel-process" directory))
           (late-answer nil))
      (unwind-protect
          (progn
            (let* ((transport
                    (lambda (_prompt callback)
                      (funcall callback
                               (yeah-control-test--answer
                                "bash" (list "sleep 5" 5)
                                (lambda (_value)
                                  (setq late-answer t)
                                  (funcall callback "late"))))))
                   (control (yeah-control-new session transport nil 60000 0)))
              (yeah-control-ask control "start")
              (should (= 1 (hash-table-count yeah-process--jobs)))
              (yeah-control-cancel control "stop")
              (should (yeah-control-done-p control))
              (maphash (lambda (_id job)
                         (should (equal "cancelled"
                                        (yeah-process--job-status job))))
                       yeah-process--jobs)
              (should-not late-answer)))
        (ignore-errors (delete-directory directory t t))))))

(ert-deftest yeah-turn-nudges-are-bounded-and-visible ()
  (let* ((root (make-temp-file "yeah-nudge" t))
         (session (yeah-session-open "nudge" root))
         (calls 0)
         (turn nil))
    (unwind-protect
        (progn
          (setq turn
                (yeah-turn-run
                 session "start"
                 (lambda (_prompt callback)
                   (setq calls (1+ calls))
                   (funcall callback "done"))
                 nil 60000 2))
          (should (yeah-turn-done turn))
          (should (= 3 calls))
          (should (= 2 (yeah-turn-nudges turn)))
          (should (= 2 (cl-count-if
                        (lambda (record)
                          (equal "nudge" (plist-get record :type)))
                        (yeah-session-records session)))))
      (ignore-errors (delete-directory root t t)))))

(ert-deftest yeah-turn-deadline-cancels-run ()
  (let* ((root (make-temp-file "yeah-deadline" t))
         (session (yeah-session-open "deadline" root))
         (turn nil))
    (unwind-protect
        (progn
          (setq turn
                (yeah-turn-run session "never answers"
                               (lambda (_prompt _callback) nil)
                               nil 60000 0 nil nil nil 0.03))
          (should (yeah-control-test--wait (lambda () (yeah-turn-done turn))))
          (should (eq 'interrupted (yeah-turn-state turn)))
          (should (cl-some (lambda (record)
                             (and (equal "cancel" (plist-get record :type))
                                  (equal "deadline exceeded"
                                         (plist-get record :payload))))
                           (yeah-session-records session))))
      (ignore-errors (delete-directory root t t)))))

(provide 'test-yeah-control)
;;; test-yeah-control.el ends here
