;;; test-yeah-delegate-deadline.el --- ERT tests for the time of a child -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; A child of a delegation works on its own, and nobody waits for it.  A
;; child that never ends would stay `running' for ever, and the parent would
;; never learn that the child is still there.  The child has a time of its
;; own: the preset names it, and when the time is up the child is cancelled
;; and the parent is told why.
;;
;; The test below runs a real turn of Yeah with a child that never answers.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-delegate)
(require 'yeah-session)
(require 'yeah-turn)

(defconst yeah-delegate-deadline-test--preset
  "---\nname: reviewer\ndescription: Reviews a diff and says what is wrong.\nmodel: cheap-model\ntools: read, grep\ntimeout: 1\n---\n\nYou are a reviewer.\n"
  "The preset the test delegates to: it names a time of one second.")

(defun yeah-delegate-deadline-test--directory ()
  "Return a directory with one preset in it."
  (let ((directory (make-temp-file "yeah-delegate-deadline" t)))
    (with-temp-buffer
      (insert yeah-delegate-deadline-test--preset)
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    directory))

(defun yeah-delegate-deadline-test--answer (asked callback)
  "Return the next answer of the run that delegates once.
ASKED counts the answers the run gave already.  CALLBACK is the callback of
the transport."
  (let ((step (length asked)))
    (push step asked)
    (if (zerop step)
        (list 'tool-call
              (list (list :name "delegate")
                    (list "reviewer" "look at the diff")
                    (lambda (_value)
                      (funcall callback "the run is done"))))
      "the run is done")))

(defun yeah-delegate-deadline-test--transport (asked)
  "Return the transport of the run that delegates once.
ASKED counts the answers the run gave already."
  (lambda (_prompt callback)
    (funcall callback (yeah-delegate-deadline-test--answer asked callback))))

(defun yeah-delegate-deadline-test--silent-transport ()
  "Return the transport of a child that never answers."
  (lambda (_prompt _callback) nil))

(defun yeah-delegate-deadline-test--child (session)
  "Return the id of the session of the child of the run of SESSION."
  (let ((id nil))
    (dolist (record (yeah-session-records session))
      (when (equal (plist-get record :type) "spawn")
        (setq id (plist-get record :child))))
    id))

(defun yeah-delegate-deadline-test--wait-for (predicate &optional timeout)
  "Wait until PREDICATE holds, up to TIMEOUT seconds.
Return the value of PREDICATE."
  (let ((deadline (+ (float-time) (or timeout 10))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(ert-deftest yeah-child-ends-when-its-time-is-up ()
  "A child that runs past its time is cancelled, and the parent is told that
the child ran out of time."
  (let* ((directory (yeah-delegate-deadline-test--directory))
         (root (make-temp-file "yeah-delegate-deadline-root" t))
         (session (yeah-session-open "run" root))
         (asked nil)
         (yeah-agent-directories (list directory))
         (yeah-delegate--transport-factory
          (lambda (_model _system _tools)
            (yeah-delegate-deadline-test--silent-transport))))
    (unwind-protect
        (progn
          (yeah-delegate-register)
          (yeah-turn-run session "delegate the review"
                         (yeah-delegate-deadline-test--transport asked)
                         (lambda (_request) (list :effect :allow :reply :once)))
          ;; the child of the run
          (let ((id (yeah-delegate-deadline-test--child session)))
            (should id)
            (let ((record (gethash id yeah-delegate--children)))
              (should record)
              ;; the child did not work for ever: it ended
              (should (yeah-delegate-deadline-test--wait-for
                       (lambda ()
                         (not (eq 'running (plist-get record :status))))
                       8))
              (should (eq 'failed (plist-get record :status)))
              ;; and the parent is told why the child ended
              (should (string-match-p "deadline"
                                      (or (plist-get record :result) ""))))))
      (yeah-delegate-reset-for-test)
      (ignore-errors (delete-directory root t))
      (ignore-errors (delete-directory directory t)))))

(provide (quote test-yeah-delegate-deadline))
;;; test-yeah-delegate-deadline.el ends here
