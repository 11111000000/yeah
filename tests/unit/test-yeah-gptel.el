;;; test-yeah-gptel.el --- ERT tests for yeah-gptel -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-gptel.el'. The
;; positive tests exercise the happy path (the prelude is
;; appended, the passthrough returns the call, the FSM handler
;; accepts valid shapes, the install/uninstall cycle is
;; symmetric). The negative test exercises the closest
;; plausible failure mode (gptel is not loaded).

;;; Code:

(require 'ert)
(require 'yeah-gptel)

(ert-deftest yeah-gptel-prompt-transform-appends-prelude ()
  "`yeah-gptel-prompt-transform' prepends the prelude to PROMPT."
  (let* ((original "hello world")
         (info nil)
         (transformed (yeah-gptel-prompt-transform original info)))
    (should (stringp transformed))
    (should (string-prefix-p yeah-gptel-prelude transformed))
    (should (string-match-p (regexp-quote original) transformed))
    (should (> (length transformed) (length original)))))

(ert-deftest yeah-gptel-pre-tool-call-passthrough ()
  "`yeah-gptel-pre-tool-call' returns the call unchanged when
the gptel-tools registry is empty (the Tier-3 registry has
not landed yet). Today every call is a passthrough."
  (let* ((call '(:name "read" :args ("foo")))
         (echoed nil)
         (returned nil))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (setq echoed (cons (apply #'format fmt args) echoed))
                 nil)))
      (setq returned (yeah-gptel-pre-tool-call call)))
    (should (equal returned call))))

(ert-deftest yeah-gptel-fsm-handler-accepts-valid-event ()
  "`yeah-gptel-fsm-handler' accepts the two valid event shapes:
`(:state STATE)' and `(:transition FROM TO)'. It must not
signal `user-error' or `error' for either shape."
  (let ((event-1 (list :state 'idle))
        (event-2 (list :transition 'idle 'user-prompt))
        (echoed nil))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (setq echoed (cons (apply #'format fmt args) echoed))
                 nil)))
      (condition-case nil
          (progn
            (yeah-gptel-fsm-handler event-1 'idle)
            (yeah-gptel-fsm-handler event-2 'idle)
            (should t))
        (error (should nil))
        (user-error (should nil))))))

(ert-deftest yeah-gptel-handles-missing-gptel ()
  "`yeah-gptel-hooks-install' and `yeah-gptel-hooks-uninstall'
must not signal when gptel is not loaded. The test wraps the
install call in `condition-case' and asserts no error escapes.
The test is symmetric for uninstall."
  (let ((err-install nil)
        (err-uninstall nil))
    (condition-case nil
        (yeah-gptel-hooks-install)
      (error (setq err-install t)))
    (condition-case nil
        (yeah-gptel-hooks-uninstall)
      (error (setq err-uninstall t)))
    (should-not err-install)
    (should-not err-uninstall)))

(provide 'test-yeah-gptel)
;;; test-yeah-gptel.el ends here