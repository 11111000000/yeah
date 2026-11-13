;;; check-ptc-sandbox-restricts.el --- PTC quarantine and exploit regressions -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; PTC is an experimental restricted evaluator, not a security boundary.
;; Verify that it is disabled by default and that the two demonstrated
;; higher-order-function bypasses are rejected when it is explicitly enabled.

;;; Code:

(require 'yeah-codes)
(require 'yeah-tools)
(require 'yeah-perm)

(let ((failures nil)
      (target (make-temp-file "yeah-ptc-canary")))
  (unwind-protect
      (progn
        ;; The public entry point is off by default.
        (let ((yeah-codes-enable-ptc nil))
          (condition-case nil
              (progn
                (yeah-codes-eval '((:name "read" :code "42")))
                (push "disabled PTC accepted a form" failures))
            (user-error nil)))

        (let ((yeah-codes-enable-ptc t))
          ;; A normal registry tool still works when explicitly enabled.
          (yeah-perm-rules-reset-for-test)
          (yeah-perm-rules-add (yeah-perm-rule-make "read" "*" 'allow))
          (condition-case err
              (let ((records (yeah-codes-eval
                              (list (list :name "read"
                                          :code (format "(read %S)" target))))))
                (unless (and (= 1 (length records))
                             (eq t (plist-get (car records) :ok)))
                  (push "an enabled registry tool did not run" failures)))
            (user-error
             (push (format "an enabled registry tool was rejected: %S" err)
                   failures)))

          ;; Direct and higher-order bypasses are refused before execution.
          (dolist (code (list (format "(delete-file %S)" target)
                              (format "(mapcar 'delete-file '(%S))" target)
                              (format "(sort '(%S 1) 'delete-file)" target)))
            (condition-case nil
                (progn
                  (yeah-codes-eval (list (list :name "read" :code code)))
                  (push (format "forbidden form was accepted: %s" code)
                        failures))
              (user-error nil))
            (unless (file-exists-p target)
              (push (format "forbidden form deleted the target: %s" code)
                    failures)))))

    (when (file-exists-p target)
      (delete-file target)))
  (dolist (failure failures)
    (message "ptc: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-ptc-sandbox-restricts.el ends here
