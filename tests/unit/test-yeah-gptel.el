;;; test-yeah-gptel.el --- ERT tests for yeah-gptel -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; The fake gptel in these tests implements the public request contract.  No
;; network or installed gptel is required.

;;; Code:

(require 'ert)
(require 'yeah-gptel)

(defmacro yeah-gptel-test--with-contract (&rest body)
  "Run BODY with a supported fake gptel version and dynamic settings."
  (declare (indent 0))
  `(let ((gptel-version "0.9.9.6")
         (gptel-backend 'global-backend)
         (gptel-model 'global-model)
         (gptel-tools '(global-tool))
         (gptel-use-tools t)
         (gptel-use-context 'system))
     (cl-letf (((symbol-function 'gptel-make-tool)
                (lambda (&rest slots) slots)))
       ,@body)))

(ert-deftest yeah-gptel-check-contract-accepts-supported-version ()
  (yeah-gptel-test--with-contract
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (&rest _args) nil))
              ((symbol-function 'gptel-make-tool)
               (lambda (&rest slots) slots)))
      (should (eq t (yeah-gptel-check-contract))))))

(ert-deftest yeah-gptel-check-contract-rejects-unsupported-version ()
  (yeah-gptel-test--with-contract
    (setq gptel-version "0.0.0")
    (should-error (yeah-gptel-check-contract) :type 'user-error)))

(ert-deftest yeah-gptel-check-contract-rejects-missing-gptel ()
  (cl-letf (((symbol-function 'gptel-request) nil))
    (should-error (yeah-gptel-check-contract) :type 'user-error)))

(ert-deftest yeah-gptel-request-freezes-private-configuration ()
  (yeah-gptel-test--with-contract
    (let (captured returned)
      (cl-letf (((symbol-function 'gptel-request)
                 (lambda (prompt &rest keys)
                   (setq captured
                         (list :prompt prompt :keys keys
                               :backend gptel-backend :model gptel-model
                               :tools gptel-tools :use-tools gptel-use-tools
                               :use-context gptel-use-context))
                   (setq returned (list 'request-fsm)))))
        (yeah-gptel-request "question" #'ignore
                            :backend 'private-backend :model 'private-model
                            :tools nil :system "private system"
                            :stream t :context 'private-context :dry-run t))
      (should (equal "question" (plist-get captured :prompt)))
      (should (eq 'private-backend (plist-get captured :backend)))
      (should (eq 'private-model (plist-get captured :model)))
      (should-not (plist-get captured :tools))
      (should-not (plist-get captured :use-tools))
      (should-not (plist-get captured :use-context))
      (let ((keys (plist-get captured :keys)))
        (should (equal "private system" (plist-get keys :system)))
        (should (eq t (plist-get keys :stream)))
        (should (eq 'private-context (plist-get keys :context)))
        (should (eq t (plist-get keys :dry-run))))
      (should (equal '(request-fsm) returned))
      (should (eq 'global-backend gptel-backend))
      (should (eq 'global-model gptel-model))
      (should (equal '(global-tool) gptel-tools))
      (should (eq 'system gptel-use-context)))))

(ert-deftest yeah-gptel-request-builds-registry-tools-by-default ()
  (yeah-gptel-test--with-contract
    (let (captured)
      (cl-letf (((symbol-function 'gptel-make-tool)
                 (lambda (&rest slots) slots))
                ((symbol-function 'gptel-request)
                 (lambda (_prompt &rest _keys)
                   (setq captured (list :tools gptel-tools
                                        :use-tools gptel-use-tools))
                   nil)))
        (yeah-gptel-request "question" #'ignore))
      (should (>= (length (plist-get captured :tools)) 1))
      (should (equal "read" (plist-get (car (plist-get captured :tools)) :name)))
      (should (eq t (plist-get captured :use-tools))))))

(ert-deftest yeah-gptel-request-does-not-install-global-hooks ()
  (yeah-gptel-test--with-contract
    (let (hook-called)
      (cl-letf (((symbol-function 'add-hook)
                 (lambda (&rest _args) (setq hook-called t)))
                ((symbol-function 'remove-hook)
                 (lambda (&rest _args) (setq hook-called t)))
                ((symbol-function 'gptel-request)
                 (lambda (&rest _args) nil)))
        (yeah-gptel-request "question" #'ignore :tools nil))
      (should-not hook-called))))

(ert-deftest yeah-gptel-request-rejects-invalid-callback ()
  (should-error (yeah-gptel-request "question" nil) :type 'user-error))

(ert-deftest yeah-gptel-tool-for-rejects-unknown-tool ()
  (cl-letf (((symbol-function 'gptel-make-tool)
             (lambda (&rest slots) slots)))
    (should-error (yeah-gptel-tool-for "does-not-exist") :type 'user-error)))

(ert-deftest yeah-gptel-callback-normalizes-errors-and-usage ()
  (let (answer received-info)
    (yeah-gptel--callback
     (lambda (response info)
       (setq answer response received-info info))
     nil
     (list :status "HTTP 429" :tokens '(:input 120 :output 7 :cache 3)))
    (should (equal '(error . "HTTP 429") answer))
    (should (equal '(:input 120 :output 7 :cache 3 :cached nil)
                   (plist-get received-info :yeah-usage)))))

(ert-deftest yeah-gptel-callback-preserves-public-response-shapes ()
  (dolist (response '("text" t (reasoning . "thinking") (tool-call)))
    (let (answer)
      (yeah-gptel--callback (lambda (value _info) (setq answer value))
                            response nil)
      (should (equal response answer)))))

(provide 'test-yeah-gptel)
;;; test-yeah-gptel.el ends here
