;;; check-approval-answers-later.el --- a permission answered later -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The question of a permission is written into the log BEFORE it is
;; asked, and the answer may come later: an answerer marked by
;; `yeah-approval-async' answers whenever it can, and the tool waits for
;; the answer.
;;
;; The check runs a real turn with an answerer that answers later and
;; reads the log:
;;
;;   * the `permission-request' event is in the log when the question is
;;     asked, so that the answer finds its request there;
;;   * the tool does not run before the answer arrives, and runs after it;
;;   * a second answer changes nothing: the question settles once, the
;;     tool runs once, and the log holds one decision;
;;   * an answer that arrives after the run ended changes nothing.
;;
;; The adapter itself is checked too: it settles a question exactly once,
;; and a question that is not answered in time is refused with a reason.
;;
;; Exit codes: 0 — the answers behave; 1 — they do not.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-approval)
(require 'yeah-perm)
(require 'yeah-session)
(require 'yeah-tools)
(require 'yeah-turn)

(defun yeah-check--types (session)
  "Return the type of every record of SESSION, in the order they were written."
  (mapcar (lambda (record) (plist-get record :type))
          (yeah-session-records session)))

(defun yeah-check--decisions (session)
  "Return the effect of every permission decision of SESSION."
  (mapcar (lambda (record) (plist-get record :effect))
          (seq-filter (lambda (record)
                        (equal "permission-decision" (plist-get record :type)))
                      (yeah-session-records session))))

(defun yeah-check--transport ()
  "Return a transport that asks for the tool `probe' and continues with it."
  (lambda (_prompt callback)
    (funcall callback
             (list 'tool-call
                   (list (list :name "probe") nil
                         (lambda (value) (funcall callback value)))))))

(defun yeah-check--with-probe (body)
  "Run BODY with a fresh registry and a tool named `probe'.
BODY is called with a function that says how many times the tool ran."
  (let ((count 0))
    (yeah-tools-reset-for-test)
    (unwind-protect
        (progn
          (yeah-tools-register
           (list :name "probe" :description "probe" :input nil
                 :handler (lambda () (cl-incf count) "ok")))
          (funcall body (lambda () count)))
      (yeah-tools-reset-for-test))))

(ert-deftest yeah-check--the-request-is-in-the-log-before-the-question ()
  "The permission request is written down before anybody is asked."
  (yeah-check--with-probe
    (lambda (ran)
      (let* ((root (make-temp-file "yeah-answers-later" t))
             (session (yeah-session-open "answers-later" root))
             (seen nil))
        (unwind-protect
            (progn
              (let ((turn
                     (yeah-turn-run
                      session "do it"
                      (yeah-check--transport)
                      (lambda (_request)
                        ;; The question is asked now: the request is
                        ;; already in the log and nothing is decided yet.
                        (setq seen (yeah-check--types session))
                        (list :effect :allow :reply :once)))))
                (should (member "permission-request" seen))
                (should-not (member "permission-decision" seen))
                (should (equal '("header" "user-message" "tool-request"
                                 "permission-request")
                               seen))
                (should (yeah-turn-done turn))
                (should (equal '("allow") (yeah-check--decisions session)))
                (should (= 1 (funcall ran)))))
          (ignore-errors (delete-directory root t t)))))))

(ert-deftest yeah-check--an-answer-that-comes-later-runs-the-tool ()
  "The tool waits for the answer, and runs when the answer arrives."
  (yeah-check--with-probe
    (lambda (ran)
      (let* ((root (make-temp-file "yeah-answers-later" t))
             (session (yeah-session-open "answers-later" root))
             (answer nil))
        (unwind-protect
            (progn
              (let ((turn
                     (yeah-turn-run
                      session "do it"
                      (yeah-check--transport)
                      (yeah-approval-async
                       (lambda (_request done) (setq answer done))))))
                (should answer)
                (should (= 0 (funcall ran)))
                ;; the answer comes later
                (funcall answer (list :effect :allow :reply :once))
                (should (= 1 (funcall ran)))
                (should (yeah-turn-done turn))
                (should (equal '("defer" "allow")
                               (yeah-check--decisions session)))
                ;; the request was in the log before the question was asked,
                ;; and the question waited: the deferral and the answer are
                ;; two decisions, the second one under the first.
                (should (equal '("header" "user-message" "tool-request"
                                 "permission-request" "permission-decision"
                                 "permission-decision" "tool-end"
                                 "assistant-message")
                               (yeah-check--types session)))))
          (ignore-errors (delete-directory root t t)))))))

(ert-deftest yeah-check--a-second-answer-is-ignored ()
  "A question settles once: a second answer changes nothing."
  (yeah-check--with-probe
    (lambda (ran)
      (let* ((root (make-temp-file "yeah-answers-later" t))
             (session (yeah-session-open "answers-later" root))
             (answer nil))
        (unwind-protect
            (progn
              (yeah-turn-run
               session "do it"
               (yeah-check--transport)
               (yeah-approval-async
                (lambda (_request done) (setq answer done))))
              (funcall answer (list :effect :allow :reply :once))
              (funcall answer (list :effect :deny :reply :reject))
              (should (= 1 (funcall ran)))
              (should (equal '("defer" "allow")
                             (yeah-check--decisions session))))
          (ignore-errors (delete-directory root t t)))))))

(ert-deftest yeah-check--an-answer-after-the-run-ended-is-ignored ()
  "A run that has ended does not run a tool for an answer that arrives late."
  (yeah-check--with-probe
    (lambda (ran)
      (let* ((root (make-temp-file "yeah-answers-later" t))
             (session (yeah-session-open "answers-later" root))
             (answer nil))
        (unwind-protect
            (progn
              (let ((turn
                     (yeah-turn-run
                      session "do it"
                      (yeah-check--transport)
                      (yeah-approval-async
                       (lambda (_request done) (setq answer done))))))
                (yeah-turn-cancel turn "the run is over")
                (funcall answer (list :effect :allow :reply :once))
                (should (= 0 (funcall ran)))
                (should (yeah-turn-done turn))))
          (ignore-errors (delete-directory root t t)))))))

(ert-deftest yeah-check--the-adapter-settles-a-question-exactly-once ()
  "The adapter calls back once, whatever the answerer does."
  (let* ((answers 0)
         (done nil))
    (yeah-approval-resolve
     (yeah-approval-async (lambda (_request answer) (setq done answer)))
     (yeah-approval-request "edit" "/tmp/x")
     (lambda (_answer) (cl-incf answers)))
    (should done)
    (funcall done (list :effect :allow :reply :once))
    (funcall done (list :effect :deny :reply :reject))
    (should (= 1 answers))))

(ert-deftest yeah-check--a-question-that-is-not-answered-in-time-is-refused ()
  "A question that waits too long is refused, and the refusal says why."
  (let ((decision nil))
    (yeah-approval-resolve
     (yeah-approval-async (lambda (_request _answer) nil) 0.01)
     (yeah-approval-request "edit" "/tmp/x")
     (lambda (answer) (setq decision answer)))
    (should-not decision)
    (sit-for 0.1)
    (should (eq :deny (plist-get decision :effect)))
    (should (string-match-p "in time" (or (plist-get decision :reason) "")))))

(ert-run-tests-batch-and-exit)

;;; check-approval-answers-later.el ends here
