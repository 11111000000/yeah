;;; test-yeah-answer.el --- ERT tests for what counts as an answer -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; The kernel has to decide whether the provider answered: the run loop waits
;; for the answer of the model, the compaction of the context waits for the
;; summary of the model, and the stands of the tests ask a real model and wait
;; for its answer.  The decision is one decision, and it is tested here,
;; offline: the stands need a key and the network, so they cannot be the test
;; of their own decision.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-answer)

(ert-deftest yeah-answer-the-empty-string-is-not-an-answer ()
  "The empty string of a reasoning model is the road to the answer."
  (should (eq 'empty (yeah-answer-shape "")))
  (should-not (yeah-answer-answered-p ""))
  (should-not (yeah-answer-text "")))

(ert-deftest yeah-answer-text-is-an-answer ()
  (should (eq 'text (yeah-answer-shape "OK")))
  (should (yeah-answer-answered-p "OK"))
  (should (equal "OK" (yeah-answer-text "OK"))))

(ert-deftest yeah-answer-a-tool-call-is-an-answer ()
  "A model that acts instead of talking answers with a tool call."
  (let ((response (list 'tool-call
                        (list (list :name "write")
                              (list "answer.txt")
                              (lambda (_value) nil)))))
    (should (eq 'tool-call (yeah-answer-shape response)))
    (should (yeah-answer-answered-p response))
    (should-not (yeah-answer-text response))))

(ert-deftest yeah-answer-an-error-is-not-an-answer ()
  (let ((response (cons 'error "the provider refused the request")))
    (should (eq 'error (yeah-answer-shape response)))
    (should-not (yeah-answer-answered-p response))
    (should (equal "the provider refused the request"
                   (yeah-answer-error response)))))

(ert-deftest yeah-answer-the-streaming-sentinel-is-not-an-answer ()
  "gptel sends `t' while the answer is still coming."
  (should (eq 'stream (yeah-answer-shape t)))
  (should-not (yeah-answer-answered-p t)))

(ert-deftest yeah-answer-the-reasoning-is-not-an-answer ()
  "The thinking of a model is the road to the answer."
  (should (eq 'reasoning (yeah-answer-shape '(reasoning "thinking"))))
  (should-not (yeah-answer-answered-p '(reasoning "thinking"))))

(ert-deftest yeah-answer-the-result-of-a-tool-is-not-an-answer ()
  (should (eq 'tool-result (yeah-answer-shape '(tool-result "written"))))
  (should-not (yeah-answer-answered-p '(tool-result "written"))))

(ert-deftest yeah-answer-an-unknown-shape-is-not-an-answer ()
  (should (eq 'unknown (yeah-answer-shape '(42 42))))
  (should-not (yeah-answer-answered-p '(42 42)))
  (should (eq 'none (yeah-answer-shape nil)))
  (should-not (yeah-answer-answered-p nil)))

(ert-deftest yeah-answer-the-error-of-a-good-answer-is-nil ()
  (should-not (yeah-answer-error "OK"))
  (should-not (yeah-answer-error "")))

(ert-deftest yeah-answer-the-reasoning-does-not-end-the-request ()
  "The thinking of a model does not end the request of the provider."
  (should-not (yeah-answer-end-p '(reasoning "thinking")))
  (should-not (yeah-answer-end-p '(reasoning . t)))
  (should-not (yeah-answer-end-p '(tool-result "written"))))

(ert-deftest yeah-answer-the-answer-ends-the-request ()
  "Everything but the road to the answer ends the request."
  (should (yeah-answer-end-p "OK"))
  (should (yeah-answer-end-p ""))
  (should (yeah-answer-end-p t))
  (should (yeah-answer-end-p nil))
  (should (yeah-answer-end-p (cons 'error "the provider refused")))
  (should (yeah-answer-end-p '(tool-call (list (list :name "write"))))))

(ert-deftest yeah-answer-the-stand-of-the-tests-follows-the-kernel ()
  "The name that the stands of the tests use is the decision of the kernel."
  (require 'yeah-live-answer
           (expand-file-name "tests/support/yeah-live-answer.el"))
  (dolist (response '("" "OK" t nil
                      '(reasoning "thinking")
                      '(reasoning . t)
                      '(tool-result "written")
                      '(tool-call (list (list :name "write")))
                      (cons 'error "the provider refused")))
    (should (eq (yeah-answer-shape response) (yeah-live-answer-shape response)))
    (should (eq (yeah-answer-answered-p response)
                (yeah-live-answer-answered-p response)))
    (should (equal (yeah-answer-text response)
                   (yeah-live-answer-text response)))
    (should (equal (yeah-answer-error response)
                   (yeah-live-answer-error response)))))

;;; test-yeah-answer.el ends here
