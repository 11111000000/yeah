;;; test-yeah-delegate-depth-journal.el --- ERT tests for the depth in the journal -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; A child knows where it stands in the tree of the delegations, and it knows
;; it from its own journal.  The journal outlives the Emacs that wrote it: a
;; restart of the harness must not make a child of depth one look like a root,
;; and a child that reads its depth as zero would be allowed to delegate
;; deeper than its agent allows.
;;
;; The test below delegates a child, drops the memory of the Emacs the way a
;; restart does, reads the journal of the child again, and asks that child to
;; delegate a grandchild to an agent that allows the depth one.  The delegation
;; is refused, because the child stands at the depth one and the grandchild
;; would stand at the depth two.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-delegate)
(require 'yeah-session)
(require 'yeah-turn)

(defconst yeah-delegate-depth-test--preset
  "---\nname: reviewer\ndescription: Reviews a diff and says what is wrong.\nmodel: cheap-model\ntools: read, grep\n---\n\nYou are a reviewer.\n"
  "The preset the test delegates to.")

(defconst yeah-delegate-depth-test--shallow
  "---\nname: shallow\ndescription: Works only at the first level.\nmodel: cheap-model\ntools: read\ndepth: 1\n---\n\nYou are shallow.\n"
  "The preset that allows the depth one.")

(defun yeah-delegate-depth-test--finish (summary)
  "Return a gptel-shaped call of the `finish' tool with SUMMARY.
A supervised run ends through this call and not through talk (wave 53)."
  (list 'tool-call
        (list (list :name "finish")
              (list summary)
              (lambda (_value) nil))))

(defun yeah-delegate-depth-test--directory ()
  "Return a directory with the two presets of the test in it."
  (let ((directory (make-temp-file "yeah-delegate-depth" t)))
    (with-temp-buffer
      (insert yeah-delegate-depth-test--preset)
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    (with-temp-buffer
      (insert yeah-delegate-depth-test--shallow)
      (write-region (point-min) (point-max)
                    (expand-file-name "shallow.md" directory)))
    directory))

(defun yeah-delegate-depth-test--delegate-transport (state)
  "Return the transport of the first turn: it delegates a child and stops."
  (lambda (_prompt callback)
    (funcall callback
             (list 'tool-call
                   (list (list :name "delegate")
                         (list "reviewer" "look at the diff")
                         (lambda (_value)
                           (funcall callback (yeah-delegate-depth-test--finish "the run is done"))))))))

(defun yeah-delegate-depth-test--grandchild-transport ()
  "Return the transport of the second turn: it asks for a grandchild."
  (lambda (_prompt callback)
    (funcall callback
             (list 'tool-call
                   (list (list :name "delegate")
                         (list "shallow" "look at the diff")
                         (lambda (_value) (funcall callback (yeah-delegate-depth-test--finish "the run is done"))))))))

(defun yeah-delegate-depth-test--child-transport ()
  "Return the transport of a child that answers at once."
  (lambda (_prompt callback)
    (funcall callback "the child is done")))

(defun yeah-delegate-depth-test--records (session type)
  "Return the records of TYPE in the journal of SESSION."
  (cl-remove-if-not (lambda (record)
                      (equal (plist-get record :type) type))
                    (yeah-session-records session)))

(defun yeah-delegate-depth-test--tool-end (session tool)
  "Return the record of the end of the call of TOOL in SESSION, or nil."
  (cl-find-if (lambda (record)
                (and (equal (plist-get record :type) "tool-end")
                     (equal (plist-get record :tool) tool)))
              (yeah-session-records session)))

(defun yeah-delegate-depth-test--wait-for (predicate &optional timeout)
  "Wait until PREDICATE holds, up to TIMEOUT seconds.
Return the value of PREDICATE."
  (let ((deadline (+ (float-time) (or timeout 10))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(ert-deftest yeah-a-session-knows-its-depth-from-the-journal ()
  "The depth of a child is in its own journal, and a restart of the harness
does not make a child of depth one look like a root."
  (let* ((directory (yeah-delegate-depth-test--directory))
         (root (make-temp-file "yeah-delegate-depth-root" t))
         (session (yeah-session-open "run" root))
         (state (list :id nil))
         (child-id nil)
         (child-session nil)
         (yeah-agent-directories (list directory))
         (yeah-delegate--transport-factory
          (lambda (_model _system _tools)
            (yeah-delegate-depth-test--child-transport))))
    (unwind-protect
        (progn
          (yeah-delegate-register)
          ;; the first turn delegates a child
          (yeah-turn-run session "delegate the review"
                         (yeah-delegate-depth-test--delegate-transport state)
                         (lambda (_request) (list :effect :allow :reply :once)))
          (should (yeah-delegate-depth-test--wait-for
                   (lambda () (>= (length (yeah-delegate-depth-test--records
                                           session "child-end"))
                                  1))))
          ;; the child stands at the depth one, and its own journal says so
          (let ((spawns (yeah-delegate-depth-test--records session "spawn")))
            (should (= 1 (length spawns)))
            (should (= 1 (plist-get (car spawns) :depth)))
            (should (equal "sub-1" (plist-get (car spawns) :short-id)))
            (setq child-id (plist-get (car spawns) :child)))
          (setq child-session (yeah-session-open child-id root))
          (let ((starts (yeah-delegate-depth-test--records child-session "child-start")))
            (should (= 1 (length starts)))
            (should (= 1 (plist-get (car starts) :depth)))
            (should (equal "run" (plist-get (car starts) :parent)))
            (should (equal "sub-1" (plist-get (car starts) :short-id))))
          ;; the harness restarts: the memory of the Emacs is gone
          (yeah-delegate-reset-for-test)
          (setq child-session (yeah-session-open child-id root))
          ;; and the child asks for a grandchild: the agent allows the depth
          ;; one, and the grandchild would stand at the depth two
          (yeah-turn-run child-session "delegate a grandchild"
                         (yeah-delegate-depth-test--grandchild-transport)
                         (lambda (_request) (list :effect :allow :reply :once)))
          (let ((end (yeah-delegate-depth-test--tool-end child-session "delegate")))
            (should end)
            (should (eq (plist-get end :ok) :false))
            (should (string-match-p "depth"
                                    (or (plist-get end :payload) "")))))
        (yeah-delegate-reset-for-test)
        (ignore-errors (delete-directory root t))
        (ignore-errors (delete-directory directory t)))))

(provide (quote test-yeah-delegate-depth-journal))
;;; test-yeah-delegate-depth-journal.el ends here
