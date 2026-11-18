;;; test-yeah-delegate-journal.el --- ERT tests for the journal of a delegation -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; A delegation belongs to the run that asked for it.  The child of a
;; delegation is written into the journal of that run and into no other:
;; the journal is the source of truth of a run, and a reader of it must see
;; the children of that run and of no other.
;;
;; The test below runs two turns of Yeah in two sessions of their own.  The
;; first run asks for a child that does not exist -- a call that fails --
;; and then asks for a child of its own.  The second run asks for a child of
;; its own, and that child belongs to the second journal.  The first journal
;; holds the child of the first run and nothing else.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-delegate)
(require 'yeah-session)
(require 'yeah-turn)

(defconst yeah-delegate-journal-test--preset
  "---\nname: reviewer\ndescription: Reviews a diff and says what is wrong.\nmodel: cheap-model\ntools: read, grep\n---\n\nYou are a reviewer.\n"
  "The preset the test delegates to.")

(defun yeah-delegate-journal-test--finish (summary)
  "Return a gptel-shaped call of the `finish' tool with SUMMARY.
A supervised run ends through this call and not through talk (wave 53)."
  (list 'tool-call
        (list (list :name "finish")
              (list summary)
              (lambda (_value) nil))))

(defun yeah-delegate-journal-test--directory ()
  "Return a directory with one preset in it."
  (let ((directory (make-temp-file "yeah-delegate-journal" t)))
    (with-temp-buffer
      (insert yeah-delegate-journal-test--preset)
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    directory))

(defun yeah-delegate-journal-test--answer (asked calls callback)
  "Return the next answer of a run.
ASKED counts the answers the run gave already.  CALLS is the list of the
calls the run makes, in order: a pair of the name of the tool and its
arguments.  CALLBACK is the callback of the transport: the continuation of a
tool call calls it again, and the model of the run goes on where it left off."
  (let ((step (length asked)))
    (push step asked)
    (let ((call (nth step calls)))
      (if call
          (list 'tool-call
                (list (list :name (car call))
                      (cadr call)
                      (lambda (_value)
                        (funcall callback
                                 (yeah-delegate-journal-test--answer
                                  asked calls callback)))))
        (yeah-delegate-journal-test--finish "the run is done")))))

(defun yeah-delegate-journal-test--transport (asked calls)
  "Return the transport of a run that makes the calls CALLS.
ASKED counts the answers the run gave already."
  (lambda (_prompt callback)
    (funcall callback (yeah-delegate-journal-test--answer
                       asked calls callback))))

(defun yeah-delegate-journal-test--child-transport ()
  "Return the transport of a child that answers at once."
  (lambda (_prompt callback)
    (funcall callback "the child is done")))

(defun yeah-delegate-journal-test--records (session type)
  "Return the records of TYPE in the journal of SESSION."
  (cl-remove-if-not (lambda (record)
                      (equal (plist-get record :type) type))
                    (yeah-session-records session)))

(defun yeah-delegate-journal-test--wait-for (predicate &optional timeout)
  "Wait until PREDICATE holds, up to TIMEOUT seconds.
Return the value of PREDICATE."
  (let ((deadline (+ (float-time) (or timeout 10))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(ert-deftest yeah-delegation-is-written-into-the-journal-of-its-own-run ()
  "The child of a delegation is written into the journal of the run that
asked for it, and into no other journal."
  (let* ((directory (yeah-delegate-journal-test--directory))
         (root (make-temp-file "yeah-delegate-journal-root" t))
         (session-a (yeah-session-open "run-a" root))
         (session-b (yeah-session-open "run-b" root))
         (asked-a nil)
         (asked-b nil)
         (yeah-agent-directories (list directory))
         (yeah-delegate--transport-factory
          (lambda (_model _system _tools)
            (yeah-delegate-journal-test--child-transport))))
    (unwind-protect
        (progn
          (yeah-delegate-register)
          ;; the first run asks for a child that does not exist, and then for
          ;; a child of its own
          (yeah-turn-run session-a "ask for a child"
                         (yeah-delegate-journal-test--transport
                          asked-a '(("delegate-result" ("sub-404"))
                                    ("delegate" ("reviewer" "look at the diff"))))
                         (lambda (_request) (list :effect :allow :reply :once)))
          ;; the second run asks for a child of its own
          (yeah-turn-run session-b "ask for a child"
                         (yeah-delegate-journal-test--transport
                          asked-b '(("delegate" ("reviewer" "look at the diff"))))
                         (lambda (_request) (list :effect :allow :reply :once)))
          ;; the child of the second run is in the journal of the second run
          (let ((spawns (yeah-delegate-journal-test--records session-b "spawn")))
            (should (= 1 (length spawns)))
            (should (string-prefix-p "run-b."
                                     (plist-get (car spawns) :child))))
          ;; and the journal of the first run holds the child of the first run
          ;; and nothing else
          (let ((spawns (yeah-delegate-journal-test--records session-a "spawn")))
            (should (= 1 (length spawns)))
            (should (string-prefix-p "run-a."
                                     (plist-get (car spawns) :child))))
          ;; the parent is told what became of the child, in its own journal
          (should (yeah-delegate-journal-test--wait-for
                   (lambda () (>= (length (yeah-delegate-journal-test--records
                                           session-b "child-end"))
                                  1))))
          (should (= 1 (length (yeah-delegate-journal-test--records
                                session-a "child-end")))))
      (yeah-delegate-reset-for-test)
      (ignore-errors (delete-directory root t))
      (ignore-errors (delete-directory directory t)))))

(provide (quote test-yeah-delegate-journal))
;;; test-yeah-delegate-journal.el ends here
