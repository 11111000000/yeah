;;; test-yeah-live-answer.el --- ERT tests for what counts as an answer -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; The live stands ask a real model and must decide whether the provider
;; answered.  A model that reasons sends the empty string between its thinking
;; and its answer, and a stand that stops there reports a silent provider
;; where there was an answer.  The decision is tested here, offline: the
;; stand needs a key and the network, so it cannot be the test of its own
;; decision.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-live-answer
         (expand-file-name "tests/support/yeah-live-answer.el"))

(ert-deftest yeah-live-answer-empty-string-is-not-an-answer ()
  "The empty string of a reasoning model is the road to the answer."
  (should (eq 'empty (yeah-live-answer-shape "")))
  (should-not (yeah-live-answer-answered-p ""))
  (should-not (yeah-live-answer-text "")))

(ert-deftest yeah-live-answer-text-is-an-answer ()
  (should (eq 'text (yeah-live-answer-shape "OK")))
  (should (yeah-live-answer-answered-p "OK"))
  (should (equal "OK" (yeah-live-answer-text "OK"))))

(ert-deftest yeah-live-answer-tool-call-is-an-answer ()
  "A model that acts instead of talking answers with a tool call."
  (let ((response (list 'tool-call
                        (list (list :name "write")
                              (list "answer.txt")
                              (lambda (_value) nil)))))
    (should (eq 'tool-call (yeah-live-answer-shape response)))
    (should (yeah-live-answer-answered-p response))
    (should-not (yeah-live-answer-text response))))

(ert-deftest yeah-live-answer-error-is-not-an-answer ()
  (let ((response (cons 'error "the provider refused the request")))
    (should (eq 'error (yeah-live-answer-shape response)))
    (should-not (yeah-live-answer-answered-p response))
    (should (equal "the provider refused the request"
                   (yeah-live-answer-error response)))))

(ert-deftest yeah-live-answer-the-streaming-sentinel-is-not-an-answer ()
  "gptel sends `t' while the answer is still coming."
  (should (eq 'stream (yeah-live-answer-shape t)))
  (should-not (yeah-live-answer-answered-p t)))

(ert-deftest yeah-live-answer-reasoning-and-tool-result-are-not-answers ()
  (should (eq 'reasoning (yeah-live-answer-shape '(reasoning "thinking"))))
  (should-not (yeah-live-answer-answered-p '(reasoning "thinking")))
  (should (eq 'tool-result (yeah-live-answer-shape '(tool-result "written"))))
  (should-not (yeah-live-answer-answered-p '(tool-result "written"))))

(ert-deftest yeah-live-answer-an-unknown-shape-is-not-an-answer ()
  (should (eq 'unknown (yeah-live-answer-shape '(42 42))))
  (should-not (yeah-live-answer-answered-p '(42 42)))
  (should (eq 'none (yeah-live-answer-shape nil)))
  (should-not (yeah-live-answer-answered-p nil)))

(ert-deftest yeah-live-answer-the-error-of-a-good-answer-is-nil ()
  (should-not (yeah-live-answer-error "OK"))
  (should-not (yeah-live-answer-error "")))

;;; test-yeah-live-answer.el ends here
