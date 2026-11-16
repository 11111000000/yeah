;;; test-yeah-delegate-names-children.el --- ERT tests for a wrong id -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; A model that asks for a child by an id that does not exist has to learn
;; what does exist.  The refusal of `delegate-result' names the children of
;; the run, so that the model can ask again with an id that is there.
;;
;; The test below runs a real turn of Yeah: the model delegates, and then
;; asks for a child that does not exist.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-delegate)
(require 'yeah-session)
(require 'yeah-turn)

(defconst yeah-delegate-names-test--preset
  "---\nname: reviewer\ndescription: Reviews a diff and says what is wrong.\nmodel: cheap-model\ntools: read, grep\n---\n\nYou are a reviewer.\n"
  "The preset the test delegates to.")

(defun yeah-delegate-names-test--directory ()
  "Return a directory with one preset in it."
  (let ((directory (make-temp-file "yeah-delegate-names" t)))
    (with-temp-buffer
      (insert yeah-delegate-names-test--preset)
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    directory))

(defun yeah-delegate-names-test--answer (state callback)
  "Return the next answer of the run.
STATE is the state of the run: :asked counts the answers it gave, and :id
holds the id that the delegate tool returned.  CALLBACK is the callback of
the transport."
  (let ((step (plist-get state :asked)))
    (setf (plist-get state :asked) (1+ step))
    (cond
     ((zerop step)
      (list 'tool-call
            (list (list :name "delegate")
                  (list "reviewer" "look at the diff")
                  (lambda (text)
                    (when (string-match "sub-[0-9]+" (or text ""))
                      (setf (plist-get state :id) (match-string 0 text)))
                    (funcall callback
                             (yeah-delegate-names-test--answer state callback))))))
     ((eql step 1)
      (list 'tool-call
            (list (list :name "delegate-result")
                  (list "sub-404")
                  (lambda (_value) (funcall callback "the run is done")))))
     (t "the run is done"))))

(defun yeah-delegate-names-test--transport (state)
  "Return the transport of the run.
STATE is the state of the run; see `yeah-delegate-names-test--answer'."
  (lambda (_prompt callback)
    (funcall callback (yeah-delegate-names-test--answer state callback))))

(defun yeah-delegate-names-test--child-transport ()
  "Return the transport of a child that answers at once."
  (lambda (_prompt callback)
    (funcall callback "the child is done")))

(defun yeah-delegate-names-test--tool-end (session tool)
  "Return the record of the end of the call of TOOL in SESSION, or nil."
  (cl-find-if (lambda (record)
                (and (equal (plist-get record :type) "tool-end")
                     (equal (plist-get record :tool) tool)))
              (yeah-session-records session)))

(ert-deftest yeah-delegate-result-names-the-children-of-the-run ()
  "A wrong id is refused by name: the refusal names the children that do
exist."
  (let* ((directory (yeah-delegate-names-test--directory))
         (root (make-temp-file "yeah-delegate-names-root" t))
         (session (yeah-session-open "run" root))
         (state (list :asked 0 :id nil))
         (yeah-agent-directories (list directory))
         (yeah-delegate--transport-factory
          (lambda (_model _system _tools)
            (yeah-delegate-names-test--child-transport))))
    (unwind-protect
        (progn
          (yeah-delegate-register)
          (yeah-turn-run session "delegate the review"
                         (yeah-delegate-names-test--transport state)
                         (lambda (_request) (list :effect :allow :reply :once)))
          ;; the wrong id was refused
          (let ((end (yeah-delegate-names-test--tool-end session "delegate-result")))
            (should end)
            (should (eq (plist-get end :ok) :false)))
          ;; and the refusal named the child that does exist
          (let ((end (yeah-delegate-names-test--tool-end session "delegate-result"))
                (payload (or (plist-get (yeah-delegate-names-test--tool-end
                                         session "delegate-result")
                                        :payload)
                             "")))
            (should (string-match-p "sub-1" payload))))
      (yeah-delegate-reset-for-test)
      (ignore-errors (delete-directory root t))
      (ignore-errors (delete-directory directory t)))))

(provide (quote test-yeah-delegate-names-children))
;;; test-yeah-delegate-names-children.el ends here
