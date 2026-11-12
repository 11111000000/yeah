;;; check-turn-handles-tool-failures.el --- U1-U4 turn failure canaries -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; U1 malformed arguments, U2 handler exceptions, U3 duplicate async
;; callbacks and U4 nil results must not wedge the turn or send nil/non-string
;; data to the model.  No network or gptel installation is used.

;;; Code:

(require 'cl-lib)
(require 'yeah-events)
(require 'yeah-turn)
(require 'yeah-tools)
(require 'yeah-perm)
(require 'yeah-session)

(defun yeah-check-failures--run (spec args)
  "Run one tool SPEC with ARGS through a fake model.
Return the completed turn, its records and model continuation observations."
  (let* ((root (make-temp-file "yeah-turn-failure" t))
         (session (yeah-session-open "failure" root))
         (name (plist-get spec :name))
         (continuations 0)
         continued-value
         outcome)
    (yeah-tools-reset-for-test)
    (yeah-perm-rules-reset-for-test)
    (yeah-tools-register spec)
    (yeah-perm-rules-add (yeah-perm-rule-make name "*" 'allow))
    (let ((turn
           (yeah-turn-run
            session "exercise failure handling"
            (lambda (_prompt callback)
              (funcall callback
                       (list 'tool-call
                             (list (list :name name)
                                   args
                                   (lambda (value)
                                     (setq continuations (1+ continuations)
                                           continued-value value)
                                     (funcall callback "finished")))))))))
      (setq outcome
            (list :turn turn
                  :records (yeah-session-records session)
                  :continuations continuations
                  :value continued-value)))
    (ignore-errors (delete-directory root t t))
    outcome))

(defun yeah-check-failures--tool-end (outcome)
  "Return the tool-end record of OUTCOME."
  (cl-find-if (lambda (record)
                (equal "tool-end" (plist-get record :type)))
              (plist-get outcome :records)))

(let ((failures nil))
  ;; U1: malformed argument containers become a tool failure.
  (let* ((outcome
          (yeah-check-failures--run
           (list :name "probe" :description "probe"
                 :input '((:name "path" :type string))
                 :handler (lambda (_path) "should not run"))
           "not-a-list"))
         (end (yeah-check-failures--tool-end outcome)))
    (unless (eq 'completed (yeah-turn-state (plist-get outcome :turn)))
      (push "U1 left the turn incomplete" failures))
    (when (yeah-events-boolean-p (plist-get end :ok))
      (push "U1 was logged as a success" failures))
    (unless (stringp (plist-get outcome :value))
      (push "U1 did not give the model a string" failures)))

  ;; U2: an exception is a result, not an escaped error that wedges the FSM.
  (let* ((outcome
          (yeah-check-failures--run
           (list :name "explode" :description "explode" :input nil
                 :handler (lambda () (error "boom")))
           nil))
         (end (yeah-check-failures--tool-end outcome)))
    (unless (eq 'completed (yeah-turn-state (plist-get outcome :turn)))
      (push "U2 left the turn incomplete" failures))
    (when (yeah-events-boolean-p (plist-get end :ok))
      (push "U2 was logged as a success" failures))
    (unless (equal "Error: boom" (plist-get outcome :value))
      (push (format "U2 returned the wrong error: %S" outcome) failures)))

  ;; U3: first result wins; a duplicate callback settles neither log nor FSM twice.
  (let* ((outcome
          (yeah-check-failures--run
           (list :name "flaky" :description "flaky" :input nil :async t
                 :handler (lambda (_args done)
                            (funcall done "first")
                            (funcall done "second")))
           nil))
         (ends (cl-count-if (lambda (record)
                              (equal "tool-end" (plist-get record :type)))
                            (plist-get outcome :records))))
    (unless (= 1 ends)
      (push (format "U3 produced %d tool-end records" ends) failures))
    (unless (= 1 (plist-get outcome :continuations))
      (push "U3 continued the model more than once" failures))
    (unless (equal "first" (plist-get outcome :value))
      (push "U3 did not preserve the first result" failures)))

  ;; U4: nil becomes an explicit string failure, never provider-invalid data.
  (let* ((outcome
          (yeah-check-failures--run
           (list :name "nothing" :description "nothing" :input nil
                 :handler (lambda () nil))
           nil))
         (end (yeah-check-failures--tool-end outcome)))
    (when (yeah-events-boolean-p (plist-get end :ok))
      (push "U4 was logged as a success" failures))
    (unless (equal "Error: tool produced no result"
                   (plist-get outcome :value))
      (push "U4 did not normalize the nil result" failures)))

  (dolist (failure failures)
    (message "turn failure: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-turn-handles-tool-failures.el ends here
