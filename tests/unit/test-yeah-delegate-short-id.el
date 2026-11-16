;;; test-yeah-delegate-short-id.el --- ERT tests for the id of a child -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; The model has to copy the id of a child back into `delegate-result'.  A
;; long token is copied with an error: the pilot of wave 35 copied 58 of the
;; 64 characters of a digest, and the edit of that file was refused.  The id
;; of a child is therefore short, and the harness finds the child by it.
;;
;; The test below runs a real turn of Yeah: the model delegates, the tool
;; answers with an id, and the model asks for the child by that id.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-delegate)
(require 'yeah-session)
(require 'yeah-turn)

(defconst yeah-delegate-short-test--preset
  "---\nname: reviewer\ndescription: Reviews a diff and says what is wrong.\nmodel: cheap-model\ntools: read, grep\n---\n\nYou are a reviewer.\n"
  "The preset the test delegates to.")

(defun yeah-delegate-short-test--directory ()
  "Return a directory with one preset in it."
  (let ((directory (make-temp-file "yeah-delegate-short" t)))
    (with-temp-buffer
      (insert yeah-delegate-short-test--preset)
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    directory))

(defun yeah-delegate-short-test--answer (state callback)
  "Return the next answer of the run.
STATE is the state of the run: :asked counts the answers it gave, and :id
holds the id that the model copied out of the answer of the delegate tool.
CALLBACK is the callback of the transport: the continuation of a tool call
calls it again, and the model of the run goes on where it left off."
  (let ((step (plist-get state :asked)))
    (setf (plist-get state :asked) (1+ step))
    (cond
     ((zerop step)
      (list 'tool-call
            (list (list :name "delegate")
                  (list "reviewer" "look at the diff")
                  (lambda (text)
                    ;; the model sees the text of the tool and copies the id
                    ;; of the child out of it
                    (when (string-match "sub-[0-9]+" (or text ""))
                      (setf (plist-get state :id) (match-string 0 text)))
                    (funcall callback
                             (yeah-delegate-short-test--answer state callback))))))
     ((eql step 1)
      (list 'tool-call
            (list (list :name "delegate-result")
                  (list (plist-get state :id))
                  (lambda (_value) (funcall callback "the run is done")))))
     (t "the run is done"))))

(defun yeah-delegate-short-test--transport (state)
  "Return the transport of the run.
STATE is the state of the run; see `yeah-delegate-short-test--answer'."
  (lambda (_prompt callback)
    (funcall callback (yeah-delegate-short-test--answer state callback))))

(defun yeah-delegate-short-test--child-transport ()
  "Return the transport of a child that answers at once."
  (lambda (_prompt callback)
    (funcall callback "the child is done")))

(defun yeah-delegate-short-test--tool-end (session tool)
  "Return the record of the end of the call of TOOL in SESSION, or nil."
  (cl-find-if (lambda (record)
                (and (equal (plist-get record :type) "tool-end")
                     (equal (plist-get record :tool) tool)))
              (yeah-session-records session)))

(defun yeah-delegate-short-test--id (session)
  "Return the id that the delegate tool answered with in SESSION.
The id is the metadata of the answer of the tool, and the text of that
answer names it as well: the model copies it out of the text."
  (let ((end (yeah-delegate-short-test--tool-end session "delegate")))
    (plist-get (plist-get (plist-get end :details) :metadata) :id)))

(ert-deftest yeah-child-is-found-by-a-short-id ()
  "The id of a child is short enough to copy, and the harness finds the child
by it."
  (let* ((directory (yeah-delegate-short-test--directory))
         (root (make-temp-file "yeah-delegate-short-root" t))
         (session (yeah-session-open "run" root))
         (state (list :asked 0 :id nil))
         (yeah-agent-directories (list directory))
         (yeah-delegate--transport-factory
          (lambda (_model _system _tools)
            (yeah-delegate-short-test--child-transport))))
    (unwind-protect
        (progn
          (yeah-delegate-register)
          (yeah-turn-run session "delegate the review"
                         (yeah-delegate-short-test--transport state)
                         (lambda (_request) (list :effect :allow :reply :once)))
          ;; the id of the child is short: a model can copy it without losing
          ;; a character of it
          (let ((id (yeah-delegate-short-test--id session)))
            (should (stringp id))
            (should (> (length id) 0))
            (should (<= (length id) 12))
            ;; and the text the model read names that id
            (should (string-match-p (regexp-quote id)
                                    (or (plist-get (yeah-delegate-short-test--tool-end
                                                    session "delegate")
                                                   :payload)
                                        "")))
            ;; the model copied the id out of the text
            (should (equal (plist-get state :id) id)))
          ;; the model asked for the child by that id, and the harness found it
          (let ((end (yeah-delegate-short-test--tool-end session "delegate-result")))
            (should end)
            (should (eq (plist-get end :ok) t))
            (should (string-match-p (regexp-quote (plist-get state :id))
                                    (or (plist-get end :payload) "")))))
      (yeah-delegate-reset-for-test)
      (ignore-errors (delete-directory root t))
      (ignore-errors (delete-directory directory t)))))

(provide (quote test-yeah-delegate-short-id))
;;; test-yeah-delegate-short-id.el ends here
