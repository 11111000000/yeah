;;; test-yeah-delegate-preset.el --- ERT tests for the delegation -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; A delegation hands a task to a child agent, named by a preset.  The child
;; runs with the model of the preset, with the tools of the preset and with
;; the instructions of the preset, and every other tool is refused to it.
;;
;; The test below runs a real turn of Yeah: the model of the parent asks for
;; the `delegate' tool, the permission is granted, the child starts and the
;; refusal of a tool outside the preset is written into the journal of the
;; child.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-delegate)
(require 'yeah-session)
(require 'yeah-turn)

(defconst yeah-delegate-preset-test--preset
  "---\nname: reviewer\ndescription: Reviews a diff and says what is wrong.\nmodel: cheap-model\ntools: read, grep\n---\n\nYou are a reviewer. Say what is wrong with the diff.\n"
  "The preset the test delegates to.")

(defun yeah-delegate-preset-test--directory ()
  "Return a directory with one preset in it."
  (let ((directory (make-temp-file "yeah-delegate-preset" t)))
    (with-temp-buffer
      (insert yeah-delegate-preset-test--preset)
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    directory))

(defun yeah-delegate-preset-test--parent-transport (asked)
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

(defun yeah-delegate-preset-test--child-transport (asked)
  "Return the transport of the child.
ASKED is the list of the calls that were made already.  The child asks for a
tool that its preset did not grant, and the refusal of that tool is what the
test reads."
  (lambda (_prompt callback)
    (if asked
        (funcall callback "the child is done")
      (progn
        (push t asked)
        (funcall callback
                 (list 'tool-call
                       (list (list :name "bash")
                             (list "echo hello")
                             (lambda (_value)
                               (funcall callback "the child is done")))))))))

(defun yeah-delegate-preset-test--child-id (session)
  "Return the id of the child that the run of SESSION delegated."
  (let ((id nil))
    (dolist (record (yeah-session-records session))
      (when (equal (plist-get record :type) "spawn")
        (setq id (plist-get record :child))))
    id))

(defun yeah-delegate-preset-test--tool-end (session tool)
  "Return the record of the end of the call of TOOL in SESSION, or nil."
  (cl-find-if (lambda (record)
                (and (equal (plist-get record :type) "tool-end")
                     (equal (plist-get record :tool) tool)))
              (yeah-session-records session)))

(ert-deftest yeah-delegate-child-runs-with-the-model-and-the-tools-of-the-preset ()
  "The child of a delegation runs on the model of the preset, with the tools of
the preset and with the instructions of the preset."
  (let* ((directory (yeah-delegate-preset-test--directory))
         (session (yeah-session-open "parent" directory))
         (calls nil)
         (child-asked nil)
         (parent-asked nil)
         (yeah-agent-directories (list directory))
         (yeah-delegate--transport-factory
          (lambda (model system tools)
            (push (list :model model :system system :tools tools) calls)
            (yeah-delegate-preset-test--child-transport child-asked))))
    (unwind-protect
        (progn
          (yeah-delegate-register)
          (yeah-turn-run session "delegate the review"
                         (yeah-delegate-preset-test--parent-transport parent-asked)
                         (lambda (_request) (list :effect :allow :reply :once)))
          ;; the child was given the model, the tools and the instructions
          ;; of the preset
          (should (= 1 (length calls)))
          (let ((call (car calls)))
            (should (equal (plist-get call :model) "cheap-model"))
            (should (equal (plist-get call :tools) '("read" "grep")))
            (should (string-match-p "You are a reviewer"
                                    (plist-get call :system))))
          ;; the child was refused the tool that its preset did not grant
          (let* ((id (yeah-delegate-preset-test--child-id session))
                 (record (gethash id yeah-delegate--children))
                 (child (plist-get record :child-session))
                 (end (yeah-delegate-preset-test--tool-end child "bash")))
            (should id)
            (should end)
            (should (equal (plist-get end :ok) :false)))
          ;; and the child ended on its own
          (let* ((id (yeah-delegate-preset-test--child-id session))
                 (status (plist-get (plist-get (yeah-delegate--result id) :metadata)
                                    :status)))
            (should (equal status "completed")))
          ;; and the parent was told what became of the child
          (let ((end (cl-find-if (lambda (record)
                                   (equal (plist-get record :type) "child-end"))
                                 (yeah-session-records session))))
            (should end)
            (should (eq (plist-get end :ok) t))))
      (yeah-delegate-reset-for-test)
      (ignore-errors (delete-directory directory t)))))

(provide (quote test-yeah-delegate-preset))
;;; test-yeah-delegate-preset.el ends here
