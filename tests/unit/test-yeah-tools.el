;;; test-yeah-tools.el --- ERT tests for yeah-tools -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-tools.el'.
;;
;; The positive tests exercise the registry and the dispatch
;; happy path (register, get, names, call, unregister). The
;; negative tests cover the closest plausible failure modes
;; (unknown name, wrong arg count).

;;; Code:

(require 'ert)
(require 'yeah-tools)

(ert-deftest yeah-tools-register-adds-name ()
  "`yeah-tools-register' makes the name visible to `yeah-tools-get'
and to `yeah-tools-names'."
  (yeah-tools-reset-for-test)
  (let* ((spec (list :name "tmp-register"
                     :description "A throwaway tool for the register test."
                     :input (list (list :name "x" :type 'string))
                     :handler (lambda (x) x))))
    (yeah-tools-register spec)
    (should (eq (yeah-tools-get "tmp-register") spec))
    (should (member "tmp-register" (yeah-tools-names))))
  (yeah-tools-reset-for-test))

(ert-deftest yeah-tools-get-returns-spec ()
  "`yeah-tools-get' returns the spec for a registered tool."
  (yeah-tools-reset-for-test)
  (let* ((handler (lambda (p) p))
         (spec    (list :name "tmp-get"
                        :description "A throwaway tool for the get test."
                        :input (list (list :name "p" :type 'string))
                        :handler handler))
         (registered (yeah-tools-register spec))
         (looked-up  (yeah-tools-get "tmp-get")))
    (should (eq registered spec))
    (should (eq looked-up spec))
    (should (string= "tmp-get" (plist-get looked-up :name)))
    (should (string= "A throwaway tool for the get test."
                     (plist-get looked-up :description)))
    (should (functionp (plist-get looked-up :handler))))
  (yeah-tools-reset-for-test))

(ert-deftest yeah-tools-names-lists-registered ()
  "`yeah-tools-names' lists registered names in registration order
(beyond the built-in `read', which is registered at load time)."
  (yeah-tools-reset-for-test)
  (let ((names '("a-test" "b-test" "c-test")))
    (dolist (n names)
      (yeah-tools-register
       (list :name n
             :description "x"
             :input (list (list :name "p" :type 'string))
             :handler (lambda (_) nil))))
    (let ((got (yeah-tools-names)))
      (should (equal (last got 3) names))))
  (yeah-tools-reset-for-test))

(ert-deftest yeah-tools-call-dispatches-to-handler ()
  "`yeah-tools-call' looks up the tool and calls its handler."
  (yeah-tools-reset-for-test)
  (let* ((calls 0)
         (handler (lambda (x) (setq calls (1+ calls)) (concat "got " x)))
         (spec (list :name "echo"
                     :description "Echo its argument."
                     :input (list (list :name "x" :type 'string))
                     :handler handler)))
    (yeah-tools-register spec)
    (let ((result (yeah-tools-call "echo" (list "hello"))))
      (should (stringp result))
      (should (string= result "got hello"))
      (should (= calls 1))))
  (yeah-tools-reset-for-test))

(ert-deftest yeah-tools-unregister-removes ()
  "`yeah-tools-unregister' makes the tool invisible to `yeah-tools-get'."
  (yeah-tools-reset-for-test)
  (let ((spec (list :name "tmp-unregister"
                    :description "x"
                    :input (list (list :name "p" :type 'string))
                    :handler (lambda (_) nil))))
    (yeah-tools-register spec)
    (should (yeah-tools-get "tmp-unregister"))
    (yeah-tools-unregister "tmp-unregister")
    (should-not (yeah-tools-get "tmp-unregister"))
    (should-not (member "tmp-unregister" (yeah-tools-names))))
  (yeah-tools-reset-for-test))

(ert-deftest yeah-tools-call-unknown-name-errors ()
  "`yeah-tools-call' raises `user-error' for an unknown name."
  (yeah-tools-reset-for-test)
  (let ((err nil))
    (condition-case nil
        (yeah-tools-call "not-a-real-tool" nil)
      (user-error (setq err t)))
    (should err))
  (yeah-tools-reset-for-test))

(ert-deftest yeah-tools-call-wrong-arg-count-errors ()
  "`yeah-tools-call' raises `user-error' when the arg count is wrong."
  (yeah-tools-reset-for-test)
  (let* ((spec (list :name "needs-two"
                     :description "needs two string args"
                     :input (list (list :name "a" :type 'string)
                                  (list :name "b" :type 'string))
                     :handler (lambda (_a _b) "never")))
         (err-short nil)
         (err-long  nil))
    (yeah-tools-register spec)
    (condition-case nil
        (yeah-tools-call "needs-two" (list "only-one"))
      (user-error (setq err-short t)))
    (condition-case nil
        (yeah-tools-call "needs-two" (list "a" "b" "c"))
      (user-error (setq err-long t)))
    (should err-short)
    (should err-long))
  (yeah-tools-reset-for-test))

(ert-deftest yeah-tools-register-rejects-duplicate ()
  "`yeah-tools-register' raises `user-error' on a duplicate name."
  (yeah-tools-reset-for-test)
  (let* ((spec (list :name "dup"
                     :description "x"
                     :input (list (list :name "p" :type 'string))
                     :handler (lambda (_) nil)))
         (err nil))
    (yeah-tools-register spec)
    (condition-case nil
        (yeah-tools-register spec)
      (user-error (setq err t)))
    (should err))
  (yeah-tools-reset-for-test))

(ert-deftest yeah-tools-built-in-read-handles-path ()
  "The built-in `read' tool reads the file at its first argument."
  (let* ((tmpfile (make-temp-file "yeah-tools-read-" nil ".txt"))
         (content "hello yeah-tools")
         (result nil))
    (with-temp-file tmpfile (insert content))
    (unwind-protect
        (setq result (yeah-tools-call "read" (list tmpfile)))
      (delete-file tmpfile))
    (should (stringp result))
    (should (string= result content))))

(provide 'test-yeah-tools)
;;; test-yeah-tools.el ends here