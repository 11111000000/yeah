;;; test-yeah-tools.el --- ERT tests for yeah-tools -*- lexical-binding: t; no-byte-compile: t -*-
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
    (should (listp result))
    (should (eq t (plist-get result :ok)))
    (should (string= (plist-get result :content) content))))

(ert-deftest yeah-tools-kind-is-declared-by-the-tool ()
  "The kind of a tool is a fact of the tool: it is the kind the tool declares,
and a tool that declares none has the kind `other'."
  (yeah-tools-reset-for-test)
  (let ((spec (list :name "tmp-kind"
                    :description "A throwaway tool for the kind test."
                    :kind "execute"
                    :input (list (list :name "p" :type 'string))
                    :handler (lambda (_) nil))))
    (yeah-tools-register spec)
    (should (equal "execute" (yeah-tools-kind "tmp-kind"))))
  (yeah-tools-reset-for-test)
  (should (equal "other" (yeah-tools-kind "read-without-a-kind"))))

(ert-deftest yeah-tools-kind-of-an-unknown-tool-is-other ()
  "A name the registry does not know has no kind to declare, and the kind of
such a call is `other'."
  (should (equal "other" (yeah-tools-kind "tmp-no-such-tool"))))

(ert-deftest yeah-tools-built-in-tools-declare-their-kind ()
  "The built-in tools declare the kind the wire of ACP knows: a read is a
read, a search is a search, an edit is an edit and a shell is an execute."
  (yeah-tools-reset-for-test)
  (should (equal "read" (yeah-tools-kind "read")))
  (should (equal "search" (yeah-tools-kind "grep")))
  (should (equal "search" (yeah-tools-kind "glob")))
  (should (equal "edit" (yeah-tools-kind "edit")))
  (should (equal "edit" (yeah-tools-kind "write")))
  (should (equal "execute" (yeah-tools-kind "bash"))))

(ert-deftest yeah-tools-named-args-carry-the-names-of-the-tool ()
  "The arguments of a call travel under the names the tool declared: a client
that looks for `path' finds it."
  (yeah-tools-reset-for-test)
  (should (equal '(:path "answer.txt")
                 (yeah-tools-named-args "read" (list "answer.txt")))))

(ert-deftest yeah-tools-named-args-leave-out-an-argument-that-was-not-given ()
  "An optional argument the model did not give is not on the wire: a call that
named no `offset' has no `offset'.  A required argument is always there."
  (yeah-tools-reset-for-test)
  (should (equal '(:path "answer.txt")
                 (yeah-tools-named-args "read" (list "answer.txt" nil nil))))
  (should (equal '(:path "answer.txt" :offset 3)
                 (yeah-tools-named-args "read" (list "answer.txt" 3 nil)))))

(ert-deftest yeah-tools-named-args-of-an-unknown-tool-are-empty ()
  "A name the registry does not know declares no names, so the arguments of
its call travel without names."
  (should (equal nil (yeah-tools-named-args "tmp-no-such-tool" (list "x")))))

(ert-deftest yeah-tools-named-args-of-a-call-without-arguments-are-empty ()
  "A call whose arguments are not a list has no names to read: such a call is
refused by the dispatch, and the names of its arguments are not read."
  (should (equal nil (yeah-tools-named-args "read" "not-a-list")))
  (should (equal nil (yeah-tools-named-args "read" 42))))

(provide 'test-yeah-tools)
;;; test-yeah-tools.el ends here