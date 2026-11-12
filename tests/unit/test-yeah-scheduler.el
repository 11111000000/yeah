;;; test-yeah-scheduler.el --- scheduler failure and settlement tests -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'yeah-scheduler)

(ert-deftest yeah-scheduler-handler-error-settles-batch ()
  (let ((continuations 0)
        results)
    (yeah-scheduler-run
     (list (list :name "broken" :args nil :mode 'shared
                 :handler (lambda (_args) (error "boom"))))
     (lambda (settled)
       (setq continuations (1+ continuations)
             results settled)))
    (should (= 1 continuations))
    (should (equal "Error: boom" (plist-get (aref results 0) :yeah-error)))))

(ert-deftest yeah-scheduler-async-setup-error-settles-batch ()
  (let (results)
    (yeah-scheduler-run
     (list (list :name "broken" :args nil :mode 'shared :async t
                 :handler (lambda (_args _done) (error "async boom"))))
     (lambda (settled) (setq results settled)))
    (should (equal "Error: async boom"
                   (plist-get (aref results 0) :yeah-error)))))

(ert-deftest yeah-scheduler-first-async-result-wins ()
  (let ((continuations 0)
        results)
    (yeah-scheduler-run
     (list (list :name "flaky" :args nil :mode 'shared :async t
                 :handler (lambda (_args done)
                            (funcall done "first")
                            (funcall done "second"))))
     (lambda (settled)
       (setq continuations (1+ continuations)
             results settled)))
    (should (= 1 continuations))
    (should (equal "first" (aref results 0)))))

(ert-deftest yeah-scheduler-nil-result-is-explicit-failure ()
  (let (results)
    (yeah-scheduler-run
     (list (list :name "nothing" :args nil :mode 'shared
                 :handler (lambda (_args) nil)))
     (lambda (settled) (setq results settled)))
    (should (equal "Error: tool produced no result"
                   (plist-get (aref results 0) :yeah-error)))))

(ert-deftest yeah-scheduler-non-string-result-is-normalized ()
  (let (results)
    (yeah-scheduler-run
     (list (list :name "number" :args nil :mode 'shared
                 :handler (lambda (_args) 42)))
     (lambda (settled) (setq results settled)))
    (should (equal "42" (aref results 0)))))

(ert-deftest yeah-scheduler-preserves-structured-result-metadata ()
  (let (results)
    (yeah-scheduler-run
     (list (list :name "structured" :args nil :mode 'shared
                 :handler (lambda (_args)
                            (list :ok t :content "excerpt" :error nil
                                  :truncated t :artifacts '("/tmp/out")
                                  :metadata '(:count 1)))))
     (lambda (settled) (setq results settled)))
    (should (eq t (plist-get (aref results 0) :truncated)))
    (should (equal '("/tmp/out") (plist-get (aref results 0) :artifacts)))
    (should (equal "excerpt" (plist-get (aref results 0) :content)))))

(provide 'test-yeah-scheduler)
;;; test-yeah-scheduler.el ends here
