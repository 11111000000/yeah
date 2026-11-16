;;; test-yeah-delegate-restart.el --- ERT tests for the child after a restart -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; The tree of the delegations belongs in the journal of the run and not only
;; in the memory of the running Emacs.  A restart of the harness forgets the
;; children that the Emacs delegated, and the journal still holds them: the
;; child of a run is found after the restart, and what became of it is told.
;;
;; The test below delegates a child, waits for the child to end, drops the
;; memory of the Emacs the way a restart does, reads the session from its
;; journal again, and asks for the child by the short id that the model was
;; given.  The child is found, and the answer says what became of it.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-delegate)
(require 'yeah-session)
(require 'yeah-turn)

(defconst yeah-delegate-restart-test--preset
  "---\nname: reviewer\ndescription: Reviews a diff and says what is wrong.\nmodel: cheap-model\ntools: read, grep\n---\n\nYou are a reviewer.\n"
  "The preset the test delegates to.")

(defun yeah-delegate-restart-test--directory ()
  "Return a directory with one preset in it."
  (let ((directory (make-temp-file "yeah-delegate-restart" t)))
    (with-temp-buffer
      (insert yeah-delegate-restart-test--preset)
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    directory))

(defun yeah-delegate-restart-test--delegate-transport (state)
  "Return the transport of the first turn: it delegates a child and stops.
STATE holds the id that the delegate tool answered with."
  (lambda (_prompt callback)
    (funcall callback
             (list 'tool-call
                   (list (list :name "delegate")
                         (list "reviewer" "look at the diff")
                         (lambda (text)
                           (when (string-match "sub-[0-9]+" (or text ""))
                             (setf (plist-get state :id) (match-string 0 text)))
                           (funcall callback "the run is done")))))))

(defun yeah-delegate-restart-test--result-transport (state)
  "Return the transport of the second turn: it asks for the child.
STATE holds the id that the delegate tool answered with."
  (lambda (_prompt callback)
    (funcall callback
             (list 'tool-call
                   (list (list :name "delegate-result")
                         (list (or (plist-get state :id) "sub-1"))
                         (lambda (_value) (funcall callback "the run is done")))))))

(defun yeah-delegate-restart-test--child-transport ()
  "Return the transport of a child that answers at once."
  (lambda (_prompt callback)
    (funcall callback "the child is done")))

(defun yeah-delegate-restart-test--records (session type)
  "Return the records of TYPE in the journal of SESSION."
  (cl-remove-if-not (lambda (record)
                      (equal (plist-get record :type) type))
                    (yeah-session-records session)))

(defun yeah-delegate-restart-test--tool-end (session tool)
  "Return the record of the end of the call of TOOL in SESSION, or nil."
  (cl-find-if (lambda (record)
                (and (equal (plist-get record :type) "tool-end")
                     (equal (plist-get record :tool) tool)))
              (yeah-session-records session)))

(defun yeah-delegate-restart-test--wait-for (predicate &optional timeout)
  "Wait until PREDICATE holds, up to TIMEOUT seconds.
Return the value of PREDICATE."
  (let ((deadline (+ (float-time) (or timeout 10))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(ert-deftest yeah-a-child-is-found-after-the-harness-restarts ()
  "The child of a run is found after a restart of the harness: the journal of
the run holds the child, and the answer says what became of it."
  (let* ((directory (yeah-delegate-restart-test--directory))
         (root (make-temp-file "yeah-delegate-restart-root" t))
         (session (yeah-session-open "run" root))
         (state (list :id nil))
         (yeah-agent-directories (list directory))
         (yeah-delegate--transport-factory
          (lambda (_model _system _tools)
            (yeah-delegate-restart-test--child-transport))))
    (unwind-protect
        (progn
          (yeah-delegate-register)
          ;; the first turn delegates a child
          (yeah-turn-run session "delegate the review"
                         (yeah-delegate-restart-test--delegate-transport state)
                         (lambda (_request) (list :effect :allow :reply :once)))
          (should (equal "sub-1" (plist-get state :id)))
          ;; and the child ends, so that the journal holds what became of it
          (should (yeah-delegate-restart-test--wait-for
                   (lambda () (>= (length (yeah-delegate-restart-test--records
                                           session "child-end"))
                                  1))))
          ;; the harness restarts: the memory of the Emacs is gone, and the
          ;; session is read from its journal again
          (yeah-delegate-reset-for-test)
          (setq session (yeah-session-open "run" root))
          ;; the second turn asks for the child by the id the model was given
          (yeah-turn-run session "ask for the child"
                         (yeah-delegate-restart-test--result-transport state)
                         (lambda (_request) (list :effect :allow :reply :once)))
          ;; the child is found, and the answer tells what became of it
          (let ((end (yeah-delegate-restart-test--tool-end session "delegate-result")))
            (should end)
            (should (eq (plist-get end :ok) t))
            (should (string-match-p "the child sub-1 is done"
                                    (or (plist-get end :payload) "")))))
        (yeah-delegate-reset-for-test)
        (ignore-errors (delete-directory root t))
        (ignore-errors (delete-directory directory t)))))

(provide (quote test-yeah-delegate-restart))
;;; test-yeah-delegate-restart.el ends here
