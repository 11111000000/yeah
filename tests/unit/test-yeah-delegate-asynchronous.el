;;; test-yeah-delegate-asynchronous.el --- ERT tests for the delegation -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; A delegation must not hold the turn of its parent.  The parent asks for the
;; delegation, the child starts, and the turn of the parent goes on while the
;; child works.  The child answers on its own, later.
;;
;; The test below runs a real turn of Yeah with a child that answers after a
;; delay: when the turn of the parent is over, both children still work.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-delegate)
(require 'yeah-session)
(require 'yeah-turn)

(defconst yeah-delegate-async-test--preset
  "---\nname: reviewer\ndescription: Reviews a diff and says what is wrong.\nmodel: cheap-model\ntools: read, grep\n---\n\nYou are a reviewer.\n"
  "The preset the test delegates to.")

(defun yeah-delegate-async-test--directory ()
  "Return a directory with one preset in it."
  (let ((directory (make-temp-file "yeah-delegate-async" t)))
    (with-temp-buffer
      (insert yeah-delegate-async-test--preset)
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    directory))

(defun yeah-delegate-async-test--finish (summary)
  "Return a gptel-shaped call of the `finish' tool with SUMMARY.
A supervised run ends through this call and not through talk (wave 53)."
  (list 'tool-call
        (list (list :name "finish")
              (list summary)
              (lambda (_value) nil))))

(defun yeah-delegate-async-test--parent-answer (asked callback)
  "Return the next answer of the parent run.
ASKED counts the answers the parent gave already: the parent delegates twice,
with two different tasks, and answers with text after that.  CALLBACK is the
callback of the transport: the continuation of a tool call calls it again,
and the model of the parent goes on where it left off."
  (let ((step (length asked)))
    (push step asked)
    (if (< step 2)
        (list 'tool-call
              (list (list :name "delegate")
                    (list "reviewer" (format "the task %d" step))
                    (lambda (_value)
                      (funcall callback
                               (yeah-delegate-async-test--parent-answer
                                asked callback)))))
      (yeah-delegate-async-test--finish "the parent is done"))))

(defun yeah-delegate-async-test--parent-transport (asked)
  "Return the transport of the parent run.
ASKED counts the answers the parent gave; see
`yeah-delegate-async-test--parent-answer'."
  (lambda (_prompt callback)
    (funcall callback
             (yeah-delegate-async-test--parent-answer asked callback))))

(defun yeah-delegate-async-test--child-ids (session)
  "Return the ids of the children that the run of SESSION delegated."
  (let ((ids nil))
    (dolist (record (yeah-session-records session))
      (when (equal (plist-get record :type) "spawn")
        (push (plist-get record :child) ids)))
    (nreverse ids)))

(defun yeah-delegate-async-test--status (id)
  "Return the status of the child ID, as the delegate-result tool reports it."
  (plist-get (plist-get (yeah-delegate--result id) :metadata) :status))

(defun yeah-delegate-async-test--wait-for (predicate &optional timeout)
  "Wait until PREDICATE holds, up to TIMEOUT seconds.
Return the value of PREDICATE."
  (let ((deadline (+ (float-time) (or timeout 10))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(ert-deftest yeah-delegate-does-not-hold-the-turn-of-its-parent ()
  "A delegation answers while the child works: the turn of the parent is over
and the children still work."
  (let* ((directory (yeah-delegate-async-test--directory))
         (session (yeah-session-open "parent" directory))
         (asked nil)
         (yeah-agent-directories (list directory))
         (yeah-delegate--transport-factory
          (lambda (_model _system _tools)
            (lambda (_prompt callback)
              (run-at-time 1.5 nil
                           (lambda () (funcall callback "the child is done")))))))
    (unwind-protect
        (progn
          (yeah-delegate-register)
          (let ((turn (yeah-turn-run session "delegate the review"
                                       (yeah-delegate-async-test--parent-transport asked)
                                       (lambda (_request) (list :effect :allow :reply :once)))))
            ;; the turn of the parent is over
            (should (yeah-turn-done turn)))
          ;; the turn of the parent is over, and both children still work
          (let ((ids (yeah-delegate-async-test--child-ids session)))
            (should (= 2 (length ids)))
            (dolist (id ids)
              (should (equal (yeah-delegate-async-test--status id) "running"))))
          ;; and the children answer on their own
          (dolist (id (yeah-delegate-async-test--child-ids session))
            (should (yeah-delegate-async-test--wait-for
                     (lambda () (equal (yeah-delegate-async-test--status id)
                                       "completed"))))))
      (yeah-delegate-reset-for-test)
      (ignore-errors (delete-directory directory t)))))

(provide (quote test-yeah-delegate-asynchronous))
;;; test-yeah-delegate-asynchronous.el ends here
