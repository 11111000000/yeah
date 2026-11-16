;;; test-yeah-delegate-plan-profile.el --- ERT tests for the delegation -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; A delegation is a change of the world: a child of a plan would do the work
;; that the plan was supposed to forbid.  The Plan profile therefore denies
;; the `delegate' tool, and the denial is in the journal of the run: no child
;; is started.
;;
;; The test below runs a real turn of Yeah with the rules of the Plan
;; profile, and reads the journal of the run: the decision is a denial, and
;; the tree of the run has no child.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-delegate)
(require 'yeah-perm)
(require 'yeah-run)
(require 'yeah-session)

(defconst yeah-delegate-plan-test--preset
  "---\nname: reviewer\ndescription: Reviews a diff and says what is wrong.\nmodel: cheap-model\ntools: read, grep\n---\n\nYou are a reviewer.\n"
  "The preset the test would delegate to.")

(defun yeah-delegate-plan-test--directory ()
  "Return a directory with one preset in it."
  (let ((directory (make-temp-file "yeah-delegate-plan" t)))
    (with-temp-buffer
      (insert yeah-delegate-plan-test--preset)
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    directory))

(defun yeah-delegate-plan-test--parent-transport (asked)
  "Return the transport of the parent run.
ASKED is the list of the calls that were made already: the transport asks for
the delegation once, and answers with text after that."
  (lambda (_prompt callback)
    (if asked
        (funcall callback "the parent is done")
      (progn
        (push t asked)
        (funcall callback
                 (list 'tool-call
                       (list (list :name "delegate")
                             (list "reviewer" "look at the diff")
                             (lambda (_value)
                               (funcall callback "the parent is done")))))))))

(defun yeah-delegate-plan-test--records (session type)
  "Return the records of SESSION whose type is TYPE."
  (seq-filter (lambda (record) (equal (plist-get record :type) type))
              (yeah-session-records session)))

(defun yeah-delegate-plan-test--decision (session action)
  "Return the permission decision of ACTION in SESSION, or nil."
  (cl-find-if (lambda (record)
                (equal (plist-get record :action) action))
              (yeah-delegate-plan-test--records session "permission-decision")))

(ert-deftest yeah-delegate-plan-profile-denies-the-delegation ()
  "The Plan profile denies the delegation: the run says no, and no child is
started."
  (let* ((directory (yeah-delegate-plan-test--directory))
         (session (yeah-session-open "parent" directory))
         (asked nil)
         (yeah-agent-directories (list directory))
         (yeah-delegate--transport-factory
          (lambda (_model _system _tools)
            ;; The child never starts, so its transport is never asked.
            (lambda (_prompt _callback) nil))))
    (unwind-protect
        (progn
          (yeah-delegate-register)
          (let ((context
                 (yeah-run-context-create
                  :placement 'batch
                  :session session
                  :transport (yeah-delegate-plan-test--parent-transport asked)
                  :rules (yeah-perm-profile "plan"))))
            (yeah-run-context-start context "delegate the review"))
          ;; the decision of the run is a denial, and the denial is the one
          ;; of the profile and not the silence of an absent person
          (let ((decision (yeah-delegate-plan-test--decision session "delegate")))
            (should decision)
            (should (equal (plist-get decision :effect) "deny"))
            (should (string-match-p "the rules deny delegate"
                                    (or (plist-get decision :reason) ""))))
          ;; and the run started no child
          (should-not (yeah-delegate-plan-test--records session "spawn"))
          ;; the tool of the run failed, and the model was told so
          (let ((end (cl-find-if (lambda (record)
                                   (equal (plist-get record :tool) "delegate"))
                                 (yeah-delegate-plan-test--records session "tool-end"))))
            (should end)
            (should (equal (plist-get end :ok) :false))))
      (yeah-delegate-reset-for-test)
      (ignore-errors (delete-directory directory t)))))

(provide (quote test-yeah-delegate-plan-profile))
;;; test-yeah-delegate-plan-profile.el ends here
