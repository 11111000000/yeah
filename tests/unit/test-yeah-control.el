;;; test-yeah-control.el --- queued human control tests -*- lexical-binding: t; no-byte-compile: t -*-
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
                   (funcall callback "I'll read the file next."))
                 nil 60000 2))
          (should (yeah-turn-done turn))
          (should (= 3 calls))
          (should (= 2 (yeah-turn-nudges turn)))
          (should (= 2 (cl-count-if
                        (lambda (record)
                          (equal "nudge" (plist-get record :type)))
                        (yeah-session-records session)))))
      (ignore-errors (delete-directory root t t)))))

(ert-deftest yeah-turn-a-result-ends-the-run-when-no-supervision-is-asked ()
  "Without supervision, the first answer ends the run."
  (let* ((root (make-temp-file "yeah-result" t))
         (session (yeah-session-open "result" root))
         (calls 0))
    (unwind-protect
        (progn
          (let ((turn (yeah-turn-run
                        session "start"
                        (lambda (_prompt callback)
                          (setq calls (1+ calls))
                          (funcall callback "I fixed the bug; the test passes."))
                        nil 60000 0)))
            (should (yeah-turn-done turn))
            (should (= 1 calls))
            (should (= 0 (yeah-turn-nudges turn)))))
      (ignore-errors (delete-directory root t t)))))

(ert-deftest yeah-turn-a-result-that-no-tool-backs-is-nudged ()
  "With supervision, a result without a tool is premature: the run nudges it."
  (let* ((root (make-temp-file "yeah-early" t))
         (session (yeah-session-open "early" root))
         (calls 0))
    (unwind-protect
        (progn
          (let ((turn (yeah-turn-run
                        session "start"
                        (lambda (_prompt callback)
                          (setq calls (1+ calls))
                          (funcall callback "I fixed the bug; the test passes."))
                        nil 60000 2)))
            (should (yeah-turn-done turn))
            (should (= 3 calls))
            (should (= 2 (yeah-turn-nudges turn)))
            (should (= 2 (cl-count-if
                           (lambda (record)
                             (equal "nudge" (plist-get record :type)))
                           (yeah-session-records session))))))
      (ignore-errors (delete-directory root t t)))))

(ert-deftest yeah-turn-nudge-names-the-next-call ()
  "A narration nudge names the exact call: the unused path tool and the file
the model named, and a repeated nudge says the next answer must contain the
call, not another plan."
  (let* ((root (make-temp-file "yeah-nudge-call" t))
         (session (yeah-session-open "nudge-call" root))
         (nudges nil))
    (unwind-protect
        (progn
          (yeah-turn-run session "start"
                         (lambda (_prompt callback)
                           (funcall callback "I'll start by checking broken.el."))
                         nil 60000 2)
          (dolist (record (yeah-session-records session))
            (when (equal "nudge" (plist-get record :type))
              (push (plist-get record :payload) nudges)))
          (setq nudges (nreverse nudges))
          (should (= 2 (length nudges)))
          (should (string-match-p "Make this call now: `read' on broken.el"
                                  (nth 0 nudges)))
          (should (string-match-p "next answer must contain the tool call"
                                  (nth 1 nudges))))
      (ignore-errors (delete-directory root t t)))))

(ert-deftest yeah-turn-nudge-names-the-path-argument-without-a-file ()
  "When the plan names no file, the nudge names the path argument to use."
  (let* ((root (make-temp-file "yeah-nudge-arg" t))
         (session (yeah-session-open "nudge-arg" root))
         (nudges nil))
    (unwind-protect
        (progn
          (yeah-turn-run session "start"
                         (lambda (_prompt callback)
                           (funcall callback "Let me look at the project first."))
                         nil 60000 1)
          (dolist (record (yeah-session-records session))
            (when (equal "nudge" (plist-get record :type))
              (push (plist-get record :payload) nudges)))
          (should (= 1 (length nudges)))
          (should (string-match-p "Make this call now: `read', with the `path' argument"
                                  (car nudges))))
      (ignore-errors (delete-directory root t t)))))

(ert-deftest yeah-turn-a-supervised-run-that-never-finishes-says-so ()
  "A supervised run whose nudge budget is spent without the model finishing
writes the `unfinished' event: ending as if it were done would be a false
success."
  (let* ((root (make-temp-file "yeah-unfinished" t))
         (session (yeah-session-open "unfinished" root))
         (turn nil))
    (unwind-protect
        (progn
          (setq turn (yeah-turn-run session "start"
                                     (lambda (_prompt callback)
                                       (funcall callback
                                                "I'll start by looking at the project."))
                                     nil 60000 1))
          (should (yeah-turn-done turn))
          (should (cl-some
                   (lambda (record)
                     (and (equal "unfinished" (plist-get record :type))
                          (plist-get record :reason)))
                   (yeah-session-records session))))
      (ignore-errors (delete-directory root t t)))))

(ert-deftest yeah-turn-an-empty-answer-is-nudged-into-the-action ()
  "An answer that says nothing is not a result: with supervision the run
nudges the model into the action instead of ending without the effect."
  (let* ((root (make-temp-file "yeah-silent" t))
         (session (yeah-session-open "silent" root))
         (calls 0)
         (nudges nil))
    (unwind-protect
        (progn
          (let ((turn (yeah-turn-run
                        session "start"
                        (lambda (_prompt callback)
                          (setq calls (1+ calls))
                          (funcall callback ""))
                        nil 60000 2)))
            (should (yeah-turn-done turn))
            (should (= 3 calls))
            (should (= 2 (yeah-turn-nudges turn))))
          (dolist (record (yeah-session-records session))
            (when (equal "nudge" (plist-get record :type))
              (push (plist-get record :payload) nudges)))
          (setq nudges (nreverse nudges))
          (should (= 2 (length nudges)))
          (should (string-match-p "last answer was empty" (nth 0 nudges)))
          ;; The budget is spent and the model still says nothing: the run
          ;; says it did not finish instead of looking done.
          (should (cl-some
                   (lambda (record)
                     (and (equal "unfinished" (plist-get record :type))
                          (plist-get record :reason)))
                   (yeah-session-records session))))
      (ignore-errors (delete-directory root t t)))))

(ert-deftest yeah-turn-an-empty-answer-without-supervision-fails-the-run ()
  "Without supervision there is no nudge to give, and an answer that says
nothing is no answer: the run fails instead of ending as a finished job."
  (let* ((root (make-temp-file "yeah-silent-plain" t))
         (session (yeah-session-open "silent-plain" root))
         (turn nil))
    (unwind-protect
        (progn
          (setq turn (yeah-turn-run session "start"
                                     (lambda (_prompt callback)
                                       (funcall callback ""))
                                     nil 60000 0))
          (should (yeah-turn-done turn))
          (should (eq 'failed (yeah-turn-state turn)))
          (should (yeah-turn-error turn))
          (should (cl-some
                   (lambda (record)
                     (equal "error" (plist-get record :type)))
                   (yeah-session-records session))))
      (ignore-errors (delete-directory root t t)))))

(defvar yeah-turn-test--late-callback nil
  "The answer callback of the model, captured while a tool runs.")

(ert-deftest yeah-turn-a-late-answer-does-not-break-the-run ()
  "An answer that arrives while the harness waits for a tool waits for it."
  (let* ((root (make-temp-file "yeah-late" t))
         (session (yeah-session-open "late" root)))
    (unwind-protect
        (progn
          (yeah-perm-rules-add (yeah-perm-rule-make "late-probe" "*" 'allow))
          (yeah-tools-register
           (list :name "late-probe"
                 :description "A probe that lets the model answer while it runs."
                 :input nil
                 :handler (lambda ()
                            (when yeah-turn-test--late-callback
                              (funcall yeah-turn-test--late-callback
                                       "the work is done")))))
          (let ((turn (yeah-turn-run
                        session "start"
                        (lambda (_prompt callback)
                          (setq yeah-turn-test--late-callback callback)
                          (funcall callback
                                   (list 'tool-call
                                         (list (list :name "late-probe")
                                               (list)
                                               (lambda (_value) nil)))))
                        nil 60000 0)))
            (let ((deadline (+ (float-time) 5)))
              (while (and (not (yeah-turn-done turn))
                          (< (float-time) deadline))
                (accept-process-output nil 0.05)))
            (should (yeah-turn-done turn))
            (should (eq 'completed (yeah-turn-state turn)))
            (should (cl-find-if
                     (lambda (record)
                       (equal "the work is done" (plist-get record :payload)))
                     (yeah-session-records session)))))
      (yeah-tools-unregister "late-probe")
      (setq yeah-turn-test--late-callback nil)
      (ignore-errors (delete-directory root t t)))))

(ert-deftest yeah-turn-finish-ends-the-run-with-the-summary ()
  "The model ends the run by calling the finish tool, not by talk."
  (let* ((root (make-temp-file "yeah-finish" t))
         (session (yeah-session-open "finish" root)))
    (unwind-protect
        (progn
          (yeah-tools-register
           (list :name "probe"
                 :description "A tool the run may use."
                 :input nil
                 :handler (lambda () "x")))
          (yeah-perm-rules-add (yeah-perm-rule-make "probe" "*" 'allow))
          (let ((turn (yeah-turn-run
                        session "start"
                        (lambda (_prompt callback)
                          (funcall callback
                                   (list 'tool-call
                                         (list (list :name "finish")
                                               (list "the work is done")
                                               (lambda (_value) nil)))))
                        nil 60000 2)))
            (let ((deadline (+ (float-time) 5)))
              (while (and (not (yeah-turn-done turn))
                          (< (float-time) deadline))
                (accept-process-output nil 0.05)))
            (should (yeah-turn-done turn))
            (should (eq 'completed (yeah-turn-state turn)))
            (should (cl-find-if
                     (lambda (record)
                       (equal "finish" (plist-get record :type)))
                     (yeah-session-records session)))))
      (yeah-tools-unregister "probe")
      (ignore-errors (delete-directory root t t)))))

(ert-deftest yeah-turn-a-cancelled-run-is-not-revived-by-a-late-answer ()
  "A cancelled run stays interrupted: an answer that waits for the tools
does not bring it back."
  (let* ((root (make-temp-file "yeah-late-cancel" t))
         (session (yeah-session-open "late-cancel" root)))
    (unwind-protect
        (progn
          (yeah-tools-register
           (list :name "slow-probe"
                 :description "A tool that never answers."
                 :input nil
                 :async t
                 :handler (lambda (_args done) (ignore done)))))
          (yeah-perm-rules-add (yeah-perm-rule-make "slow-probe" "*" 'allow))
          (let ((turn (yeah-turn-run
                        session "start"
                        (lambda (_prompt callback)
                          (setq yeah-turn-test--late-callback callback)
                          (funcall callback
                                   (list 'tool-call
                                         (list (list :name "slow-probe")
                                               (list)
                                               (lambda (_value) nil)))))
                        nil 60000 0)))
            (let ((deadline (+ (float-time) 5)))
              (while (and (not (eq 'awaiting-tool (yeah-turn-state turn)))
                          (< (float-time) deadline))
                (accept-process-output nil 0.05)))
            (when (eq (yeah-turn-state turn) 'awaiting-tool)
              ;; the model answers while the tool is running
              (funcall yeah-turn-test--late-callback "done")
              ;; and the run is cancelled before the tools settle
              (yeah-turn-cancel turn "stop"))
            (should (eq 'interrupted (yeah-turn-state turn)))
            (should-not (eq 'completed (yeah-turn-state turn)))))
      (yeah-tools-unregister "slow-probe")
      (setq yeah-turn-test--late-callback nil)
      (ignore-errors (delete-directory root t t))))

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

(ert-deftest yeah-turn-parallel-same-name-calls-have-stable-correlation ()
  (yeah-control-test--with-tools
    (let* ((root (make-temp-file "yeah-correlation" t))
           (session (yeah-session-open "correlation" root))
           (callbacks nil)
           (continued 0))
      (unwind-protect
          (progn
            (yeah-tools-register
             (list :name "probe" :description "parallel probe"
                   :input '((:name "path" :type string)) :async t
                   :handler (lambda (path done)
                              (push (cons (car path) done) callbacks))))
            (let* ((transport
                    (lambda (_prompt callback)
                      (let ((continuation
                             (lambda (_value)
                               (cl-incf continued)
                               (when (= continued 2)
                                 (funcall callback "finished")))))
                        (funcall callback
                                 (list 'tool-call
                                       (list (list :name "probe") '("a") continuation)
                                       (list (list :name "probe") '("b") continuation))))))
                   (turn (yeah-turn-run session "parallel" transport nil 60000 0)))
              (should (= 2 (length callbacks)))
              (funcall (cdr (assoc "b" callbacks)) "second")
              (should-not (cl-some (lambda (record)
                                     (equal "tool-end" (plist-get record :type)))
                                   (yeah-session-records session)))
              (funcall (cdr (assoc "a" callbacks)) "first")
              (should (yeah-turn-done turn))
              (let* ((records (yeah-session-records session))
                     (user (cl-find-if (lambda (record)
                                         (equal "user-message" (plist-get record :type)))
                                       records))
                     (requests (cl-remove-if-not
                                (lambda (record)
                                  (equal "tool-request" (plist-get record :type)))
                                records))
                     (permissions (cl-remove-if-not
                                   (lambda (record)
                                     (equal "permission-request"
                                            (plist-get record :type)))
                                   records))
                     (decisions (cl-remove-if-not
                                 (lambda (record)
                                   (equal "permission-decision"
                                          (plist-get record :type)))
                                 records))
                     (ends (cl-remove-if-not
                            (lambda (record)
                              (equal "tool-end" (plist-get record :type)))
                            records)))
                (dotimes (index 2)
                  (let ((request (nth index requests))
                        (permission (nth index permissions))
                        (decision (nth index decisions))
                        (end (nth index ends)))
                    (should (equal (format "%s-call-%d" (yeah-turn-id turn)
                                           (1+ index))
                                   (plist-get request :tool_call_id)))
                    (should (equal (plist-get user :id)
                                   (plist-get request :parent_event_id)))
                    (should (equal (plist-get request :tool_call_id)
                                   (plist-get permission :tool_call_id)))
                    (should (equal (plist-get request :tool_call_id)
                                   (plist-get decision :tool_call_id)))
                    (should (equal (plist-get request :tool_call_id)
                                   (plist-get end :tool_call_id)))
                    (should (equal (plist-get request :id)
                                   (plist-get permission :parent_event_id)))
                    (should (equal (plist-get permission :id)
                                   (plist-get decision :parent_event_id)))
                    (should (equal (plist-get request :id)
                                   (plist-get end :parent_event_id)))
                    (should (equal (plist-get request :run_id)
                                   (plist-get end :run_id)))
                    (should (equal (plist-get request :turn_id)
                                   (plist-get end :turn_id))))))))
        (ignore-errors (delete-directory root t t))))))

(ert-deftest yeah-turn-deferred-permission-resume-logs-final-decision-once ()
  (yeah-control-test--with-tools
    (let* ((root (make-temp-file "yeah-deferred" t))
           (session (yeah-session-open "deferred" root))
           (seen-request nil)
           (dispatched 0))
      (unwind-protect
          (progn
            (yeah-tools-register
             (list :name "probe" :description "probe" :input nil
                   :handler (lambda ()
                              (cl-incf dispatched)
                              "ok")))
            (let* ((answerer
                    (lambda (request)
                      (setq seen-request request)
                      (list :defer "permission-1")))
                   (turn
                    (yeah-turn-run
                     session "wait"
                     (lambda (_prompt callback)
                       (funcall callback
                                (yeah-control-test--answer
                                 "probe" nil
                                 (lambda (_value)
                                   (funcall callback "finished")))))
                     answerer 60000 0)))
              (should (= 0 dispatched))
              (should (eq 'awaiting-tool (yeah-turn-state turn)))
              (yeah-turn-resume-permission
               turn "permission-1" (list :effect :allow :reply :once))
              (yeah-turn-resume-permission
               turn "permission-1" (list :effect :deny :reply :reject))
              (should (= 1 dispatched))
              (should (yeah-turn-done turn))
              (let* ((records (yeah-session-records session))
                     (request (cl-find-if
                               (lambda (record)
                                 (equal "tool-request" (plist-get record :type)))
                               records))
                     (decisions (cl-remove-if-not
                                 (lambda (record)
                                   (equal "permission-decision"
                                          (plist-get record :type)))
                                 records))
                     (end (cl-find-if
                           (lambda (record)
                             (equal "tool-end" (plist-get record :type)))
                           records))
                     (tool-call-id (plist-get request :tool_call_id)))
                (should (equal tool-call-id
                               (plist-get seen-request :tool-call-id)))
                (should (= 2 (length decisions)))
                (should (equal "defer" (plist-get (nth 0 decisions) :effect)))
                (should (equal "allow" (plist-get (nth 1 decisions) :effect)))
                (should (equal tool-call-id
                               (plist-get (nth 0 decisions) :tool_call_id)))
                (should (equal tool-call-id
                               (plist-get (nth 1 decisions) :tool_call_id)))
                (should (equal tool-call-id (plist-get end :tool_call_id)))
                (should (equal (plist-get (nth 0 decisions) :id)
                               (plist-get (nth 1 decisions) :parent_event_id)))
                (should (equal (plist-get request :id)
                               (plist-get end :parent_event_id))))))
        (ignore-errors (delete-directory root t t))))))

(ert-deftest yeah-turn-cancel-before-deferred-response-prevents-dispatch ()
  (yeah-control-test--with-tools
    (let* ((root (make-temp-file "yeah-cancel-deferred" t))
           (session (yeah-session-open "cancel-deferred" root))
           (dispatched 0))
      (unwind-protect
          (progn
            (yeah-tools-register
             (list :name "probe" :description "probe" :input nil
                   :handler (lambda ()
                              (cl-incf dispatched)
                              "must not run")))
            (let ((turn
                   (yeah-turn-run
                    session "wait"
                    (lambda (_prompt callback)
                      (funcall callback
                               (yeah-control-test--answer "probe" nil nil)))
                    (lambda (_request) (list :defer "permission-cancel"))
                    60000 0)))
              (yeah-turn-cancel turn "stop before permission")
              (yeah-turn-resume-permission
               turn "permission-cancel" (list :effect :allow :reply :once))
              (should (= 0 dispatched))
              (should (eq 'interrupted (yeah-turn-state turn)))
              (should-not (cl-some
                           (lambda (record)
                             (equal "tool-end" (plist-get record :type)))
                           (yeah-session-records session)))
              (should (= 1 (cl-count-if
                            (lambda (record)
                              (equal "permission-decision"
                                     (plist-get record :type)))
                            (yeah-session-records session))))))
        (ignore-errors (delete-directory root t t))))))

(ert-deftest yeah-turn-tool-end-carries-truthful-result-details ()
  (yeah-control-test--with-tools
    (let* ((root (make-temp-file "yeah-result-details" t))
           (session (yeah-session-open "result-details" root)))
      (unwind-protect
          (progn
            (yeah-tools-register
             (list :name "probe" :description "probe" :input nil
                   :handler (lambda ()
                              (yeah-result-ok "short" '(:tick 7) t
                                              '("/tmp/full")))))
            (let ((turn
                   (yeah-turn-run
                    session "details"
                    (lambda (_prompt callback)
                      (funcall callback
                               (yeah-control-test--answer
                                "probe" nil
                                (lambda (_value)
                                  (funcall callback "finished")))))
                    nil 60000 0)))
              (should (yeah-turn-done turn))
              (let* ((end (cl-find-if
                           (lambda (record)
                             (equal "tool-end" (plist-get record :type)))
                           (yeah-session-records session)))
                     (details (plist-get end :details)))
                (should (eq t (plist-get details :truncated)))
                (should (equal ["/tmp/full"] (plist-get details :artifacts)))
                (should (= 7 (plist-get (plist-get details :metadata) :tick)))
                (should (equal (concat "short\n[tick: 7]\n[Output truncated.]"
                                       "\n[Full output: /tmp/full]")
                               (plist-get end :payload))))))
        (ignore-errors (delete-directory root t t))))))

(ert-deftest yeah-control-submit-completes-each-queued-input ()
  (let* ((root (make-temp-file "yeah-submit" t))
         (yeah-input-directory root)
         (session (yeah-session-open "submit" root))
         (model-callbacks nil)
         (completions nil)
         (control nil))
    (unwind-protect
        (progn
          (setq control
                (yeah-control-new
                 session
                 (lambda (prompt callback)
                   (push (cons prompt callback) model-callbacks))
                 nil 60000 0))
          (let ((first (yeah-control-submit
                        control "first" nil
                        (lambda (completion) (push completion completions))))
                (second nil)
                (third nil))
            (setq second
                  (yeah-control-submit
                   control "second" nil
                   (lambda (completion) (push completion completions))))
            (setq third
                  (yeah-control-submit
                   control "third" nil
                   (lambda (completion) (push completion completions))))
            (should (and (stringp first) (stringp second) (stringp third)))
            (should (= 2 (length (yeah-control-pending control))))
            (dolist (input (yeah-control-pending control))
              (should (yeah-input--serializable-p (plist-get input :frozen))))
            (yeah-control-withdraw control third)
            (let ((withdrawn (cl-find third completions
                                      :key (lambda (completion)
                                             (plist-get completion :input-id))
                                      :test #'equal)))
              (should (eq 'cancelled (plist-get withdrawn :state)))
              (should-not (plist-get withdrawn :turn)))
            (funcall (cdr (assoc "first" model-callbacks)) "first done")
            (should (assoc "second" model-callbacks))
            (funcall (cdr (assoc "second" model-callbacks)) "second done")
            (should (= 3 (length completions)))
            (dolist (id (list first second))
              (let ((completion (cl-find id completions
                                         :key (lambda (value)
                                                (plist-get value :input-id))
                                         :test #'equal)))
                (should (eq 'completed (plist-get completion :state)))
                (should (plist-get completion :turn))))
            (should (yeah-control-done-p control))))
      (ignore-errors (delete-directory root t t)))))

(defun yeah-control-test--queue-events (session)
  "Return the records of SESSION that belong to the pending queue."
  (seq-filter (lambda (record)
                (member (plist-get record :type)
                        '("input-queued" "input-taken" "input-recovered"
                          "input-withdrawn")))
              (yeah-session-records session)))

(ert-deftest yeah-control-the-pending-queue-is-written-into-the-journal ()
  "The queue of the person is visible in the journal: what entered it, what
started a run, and in which order."
  (let* ((root (make-temp-file "yeah-queue-journal" t))
         (yeah-input-directory root)
         (session (yeah-session-open "queue-journal" root))
         (callbacks nil)
         (control nil))
    (unwind-protect
        (progn
          (setq control
                (yeah-control-new
                 session
                 (lambda (prompt callback)
                   (push (cons prompt callback) callbacks))
                 nil 60000 0))
          (let* ((first (yeah-control-submit control "first"))
                 (second (yeah-control-submit control "second"))
                 (events (yeah-control-test--queue-events session)))
            ;; the journal holds the queue, in the order it changed
            (should (equal (mapcar (lambda (record) (plist-get record :type))
                                    events)
                           '("input-queued" "input-taken" "input-queued")))
            (should (equal (plist-get (nth 0 events) :input_id) first))
            (should (equal (plist-get (nth 0 events) :input_kind) "ask"))
            (should (equal (plist-get (nth 0 events) :prompt) "first"))
            (should (plist-get (plist-get (nth 0 events) :frozen) :budget))
            ;; the first input started the run
            (should (equal (plist-get (nth 1 events) :input_id) first))
            ;; the second one is still waiting
            (should (equal (plist-get (nth 2 events) :input_id) second))
            (should (= 1 (length (yeah-control-pending control))))
            ;; the run ends: the waiting input starts
            (funcall (cdr (assoc "first" callbacks)) "first done")
            (let ((taken (cl-find-if (lambda (record)
                                        (and (equal "input-taken"
                                                    (plist-get record :type))
                                             (equal second
                                                    (plist-get record :input_id))))
                                      (yeah-session-records session))))
              (should taken)
              (should (equal "ask" (plist-get taken :input_kind))))))
      (ignore-errors (delete-directory root t t)))))

(ert-deftest yeah-control-an-explicit-recovery-is-written-as-input-recovered ()
  "The automatic continuation of a run is `input-taken'.  An input that the
person starts explicitly, after a restart, is `input-recovered'."
  (let* ((root (make-temp-file "yeah-recover-journal" t))
         (yeah-input-directory root)
         (session (yeah-session-open "recover-journal" root))
         (silent (lambda (_prompt _callback) nil))
         (control (yeah-control-new session silent nil 60000 0)))
    (unwind-protect
        (progn
          (let* ((first (yeah-control-submit control "first"))
                 (second (yeah-control-submit control "second")))
            (should (= 1 (length (yeah-control-pending control))))
            ;; the person cancels the run: the queue continues by itself
            (yeah-control-cancel control "the person changed their mind")
            (should (cl-some (lambda (record)
                               (and (equal "input-taken" (plist-get record :type))
                                    (equal second (plist-get record :input_id))))
                             (yeah-session-records session)))
            (should-not (cl-some (lambda (record)
                                   (equal "input-recovered"
                                          (plist-get record :type)))
                                 (yeah-session-records session)))
            ;; the person asks once more and quits
            (let ((third (yeah-control-submit control "third")))
              (should (= 1 (length (yeah-control-pending control))))
              ;; the person comes back: the queue survived the restart
              (let* ((again (yeah-session-open "recover-journal" root))
                     (other (yeah-control-new again silent nil 60000 0)))
                (should (yeah-control-done-p other))
                (should (= 1 (length (yeah-control-pending other))))
                (yeah-control-recover-next other)
                (let ((records (yeah-session-records again)))
                  (should (cl-some (lambda (record)
                                     (and (equal "input-recovered"
                                                 (plist-get record :type))
                                          (equal third (plist-get record :input_id))))
                                   records))
                  ;; a recovery is not the continuation of a run
                  (should-not (cl-some (lambda (record)
                                         (and (equal "input-taken"
                                                     (plist-get record :type))
                                              (equal third
                                                     (plist-get record :input_id))))
                                       records))
                  ;; the first input was taken by the run it started
                  (should (cl-some (lambda (record)
                                     (and (equal "input-taken"
                                                 (plist-get record :type))
                                          (equal first (plist-get record :input_id))))
                                   records)))))))
      (ignore-errors (delete-directory root t t)))))

(ert-deftest yeah-control-a-withdrawal-is-written-with-the-id-of-the-input ()
  "A withdrawn input is written into the journal with its id: the pending
list of the editor is a projection of the journal, and a withdrawn input
must leave it."
  (let* ((root (make-temp-file "yeah-withdraw-journal" t))
         (yeah-input-directory root)
         (session (yeah-session-open "withdraw-journal" root))
         (silent (lambda (_prompt _callback) nil))
         (control (yeah-control-new session silent nil 60000 0)))
    (unwind-protect
        (progn
          (let* ((first (yeah-control-submit control "first"))
                 (second (yeah-control-submit control "second")))
            (should (= 1 (length (yeah-control-pending control))))
            (yeah-control-withdraw control second)
            ;; the input is gone from the queue
            (should (= 0 (length (yeah-control-pending control))))
            ;; and the journal says so, with the id of the input
            (let ((withdrawn (cl-find-if (lambda (record)
                                           (equal "input-withdrawn"
                                                  (plist-get record :type)))
                                         (yeah-session-records session))))
              (should withdrawn)
              (should (equal second (plist-get withdrawn :input_id)))
              (should (equal "ask" (plist-get withdrawn :kind)))
              (should (stringp (plist-get withdrawn :reason)))
              ;; the run that is under way is not the withdrawn input
              (should-not (equal first (plist-get withdrawn :input_id))))))
      (ignore-errors (delete-directory root t t)))))

(provide 'test-yeah-control)
;;; test-yeah-control.el ends here
