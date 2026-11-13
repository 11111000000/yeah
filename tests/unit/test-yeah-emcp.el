;;; test-yeah-emcp.el --- ERT tests for yeah-emcp -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-emcp.el'.
;;
;; The positive tests exercise the registry and the dispatch
;; happy path; the negative tests exercise the closest plausible
;; failure modes (unknown id, malformed spec, duplicate id).

;;; Code:

(require 'ert)
(require 'yeah-emcp)

(ert-deftest yeah-emcp-tool-ids-lists-first-wave ()
  "`yeah-emcp-tool-ids' returns the nine first-wave ids in order."
  (let ((expected '("emacs__buffer_list"
                    "emacs__buffer_read"
                    "emacs__buffer_write"
                    "emacs__magit_status"
                    "emacs__describe_function"
                    "emacs__describe_variable"
                    "emacs__dired_list"
                    "emacs__project_find_file"
                    "emacs__eval"))
        (got (yeah-emcp-tool-ids)))
    (should (= (length got) 9))
    (should (equal got expected))))

(ert-deftest yeah-emcp-published-ids-are-read-only-by-default ()
  "The published surface carries the read-only tools and nothing else."
  (let ((published (yeah-emcp-published-ids)))
    (should (member "emacs__buffer_list" published))
    (should (member "emacs__buffer_read" published))
    (should-not (member "emacs__buffer_write" published))
    (should-not (member "emacs__eval" published))
    (should (= (length published) 7))))

(ert-deftest yeah-emcp-published-ids-follow-the-operator ()
  "An operator may widen the published surface with an explicit id."
  (let ((yeah-emcp-publish-extra-tools '("emacs__buffer_write")))
    (should (member "emacs__buffer_write" (yeah-emcp-published-ids)))
    (should (member "emacs__buffer_list" (yeah-emcp-published-ids)))))

(ert-deftest yeah-emcp-tool-spec-known ()
  "`emacs__eval' has the expected `:description'."
  (let* ((spec (yeah-emcp-tool-spec "emacs__eval"))
         (desc (plist-get spec :description))
         (in   (plist-get spec :input)))
    (should (listp spec))
    (should (stringp desc))
    (should (> (length desc) 0))
    (should (equal in '("expr")))
    (should (equal (plist-get spec :output) "string"))
    (should (functionp (plist-get spec :handler)))))

(ert-deftest yeah-emcp-tool-spec-unknown ()
  "`yeah-emcp-tool-spec' returns nil for an unknown id."
  (should-not (yeah-emcp-tool-spec "emacs__not_real"))
  (should-not (yeah-emcp-tool-spec ""))
  (should-not (yeah-emcp-tool-spec "eval")))

(ert-deftest yeah-emcp-handle-call-returns-the-evaluated-value ()
  "Calling `emacs__eval' evaluates the expression for real."
  (let ((result (yeah-emcp-handle-call "emacs__eval" '(:expr "(+ 1 1)"))))
    (should (stringp result))
    (should (equal result "2"))))

(ert-deftest yeah-emcp-handle-call-reads-a-live-buffer ()
  "Calling `emacs__buffer_read' returns the text of a live buffer."
  (let ((buffer (generate-new-buffer " yeah-emcp-test")))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (insert "hello"))
          (should (equal (yeah-emcp-handle-call
                          "emacs__buffer_read" (list :name (buffer-name buffer)))
                         "hello")))
      (kill-buffer buffer))))

(ert-deftest yeah-emcp-handle-call-unknown-id-errors ()
  "Calling an unknown tool id raises `user-error'."
  (let ((err nil))
    (condition-case nil
        (yeah-emcp-handle-call "emacs__not_real" nil)
      (user-error (setq err t)))
    (should err)))

(ert-deftest yeah-emcp-handle-call-rejects-duplicate-registration ()
  "Re-registering an existing id raises `user-error'."
  (let* ((id "emacs__eval")
         (spec (yeah-emcp-tool-spec id))
         (err nil))
    (condition-case nil
        (yeah-emcp-register-tool spec)
      (user-error (setq err t)))
    (should err)))

(ert-deftest yeah-emcp-handle-call-rejects-malformed-spec ()
  "Registering a malformed spec raises `user-error'."
  (let ((spec-no-handler (list :id "emacs__test" :description "x"))
        (spec-bad-handler (list :id "emacs__test" :description "x" :input '() :handler 42))
        (caught-1 nil)
        (caught-2 nil))
    (condition-case nil
        (yeah-emcp-register-tool spec-no-handler)
      (user-error (setq caught-1 t)))
    (should caught-1)
    (condition-case nil
        (yeah-emcp-register-tool spec-bad-handler)
      (user-error (setq caught-2 t)))
    (should caught-2)))

(ert-deftest yeah-emcp-register-tool-round-trip ()
  "Register a new tool, look it up, call it, get the expected result."
  (let* ((calls 0)
         (id "emacs__test_round_trip")
         (handler (lambda (input)
                    (setq calls (1+ calls))
                    (format "ok %S" input)))
         (spec (list :id id
                     :description "Round-trip test handler."
                     :input '("input")
                     :handler handler))
         (registered (yeah-emcp-register-tool spec))
         (looked-up  (yeah-emcp-tool-spec id))
         (result     (yeah-emcp-handle-call id '(:input "hello"))))
    (should (eq registered spec))
    (should (eq looked-up spec))
    (should (stringp result))
    (should (string-prefix-p "ok " result))
    (should (= calls 1))
    (yeah-emcp--reset-for-test)))

(provide 'test-yeah-emcp)
;;; test-yeah-emcp.el ends here