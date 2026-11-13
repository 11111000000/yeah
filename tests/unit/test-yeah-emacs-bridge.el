;;; test-yeah-emacs-bridge.el --- ERT tests for yeah-bridge -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Tests for `lib/yeah-bridge.el'.  The bridge talks to an attached
;; Emacs through `emacsclient'; here it talks to a stub program
;; instead, so that the tests need neither a running Emacs server
;; nor the network.  The stub answers `--eval' requests from the
;; arguments it receives, and fails on request.

;;; Code:

(require 'ert)
(require 'yeah-bridge)
(require 'yeah-tools)

(defconst yeah-bridge-test--stub-lines
  '( "#!/bin/sh"
    "expr=\"\""
    "for arg in \"$@\"; do expr=\"$arg\"; done"
    "case \"$expr\" in"
    "  t) printf 't\\n'; exit 0 ;;"
    "  *boom*) echo '*ERROR*: boom' >&2; exit 1 ;;"
    "  *missing-buffer*) echo '*ERROR*: No such buffer' >&2; exit 1 ;;"
    "  *buffer-text*) printf 'stub buffer text\\n'; exit 0 ;;"
    "  *) printf 'args=%s expr=%s\\n' \"$#\" \"$expr\"; exit 0 ;;"
    "esac")
  "Lines of the stub program the bridge tests run.")

(defmacro yeah-bridge-test--with-stub (&rest body)
  "Evaluate BODY with `yeah-bridge-program' bound to a stub program.
The stub is written into a temporary directory, made executable,
and removed again afterwards."
  (declare (indent 0) (debug t))
  `(let* ((directory (make-temp-file "yeah-bridge-test-" t))
          (stub (expand-file-name "stub" directory)))
     (with-temp-file stub
       (insert (mapconcat #'identity yeah-bridge-test--stub-lines "\n"))
       (insert "\n"))
     (set-file-modes stub #o755)
     (unwind-protect
         (let ((yeah-bridge-program stub))
           ,@body)
       (delete-directory directory t))))

(ert-deftest yeah-bridge-tool-specs-have-the-documented-shape ()
  "The tool specs carry the documented names, inputs and handlers."
  (let* ((specs (yeah-bridge-tool-specs))
         (eval-spec (car specs))
         (read-spec (cadr specs)))
    (should (= (length specs) 2))
    (should (equal (plist-get eval-spec :name) "bridge__eval"))
    (should (equal (plist-get read-spec :name) "bridge__buffer_read"))
    (should (stringp (plist-get eval-spec :description)))
    (should (> (length (plist-get eval-spec :description)) 0))
    (should (stringp (plist-get read-spec :description)))
    (should (> (length (plist-get read-spec :description)) 0))
    (should (equal (plist-get eval-spec :input)
                   '((:name "expression" :type string))))
    (should (equal (plist-get read-spec :input)
                   '((:name "name" :type string))))
    (should (functionp (plist-get eval-spec :handler)))
    (should (functionp (plist-get read-spec :handler)))))

(ert-deftest yeah-bridge-register-registers-both-tools-idempotently ()
  "Registration puts both tools into the registry and may be repeated."
  (yeah-tools-reset-for-test)
  (unwind-protect
      (let ((first (yeah-bridge-register))
            (second (yeah-bridge-register)))
        (should (equal (mapcar (lambda (spec) (plist-get spec :name)) first)
                       '("bridge__eval" "bridge__buffer_read")))
        (should (equal first second))
        (should (eq (yeah-tools-get "bridge__eval") (car first)))
        (should (eq (yeah-tools-get "bridge__buffer_read") (cadr first)))
        (should (member "bridge__eval" (yeah-tools-names)))
        (should (member "bridge__buffer_read" (yeah-tools-names))))
    (yeah-tools-reset-for-test)))

(ert-deftest yeah-bridge-dispatch-reaches-the-stub-program ()
  "A registered tool, dispatched through the registry, reaches the stub."
  (yeah-tools-reset-for-test)
  (unwind-protect
      (progn
        (yeah-bridge-register)
        (yeah-bridge-test--with-stub
          (should (equal (yeah-tools-dispatch "bridge__eval" (list "(+ 1 1)"))
                         "args=2 expr=(+ 1 1)"))
          (should (equal (yeah-tools-dispatch "bridge__buffer_read"
                                              (list "buffer-text"))
                         "stub buffer text"))))
    (yeah-tools-reset-for-test)))

(ert-deftest yeah-bridge-eval-signals-user-error-on-failure ()
  "A failing evaluation raises `user-error' and says what failed."
  (yeah-bridge-test--with-stub
    (let ((caught nil))
      (condition-case err
          (yeah-bridge-eval "boom")
        (user-error (setq caught err)))
      (should caught)
      (should (string-match-p "failed" (error-message-string caught))))))

(ert-deftest yeah-bridge-eval-signals-user-error-when-unavailable ()
  "A bridge without an executable program raises `user-error'."
  (let ((yeah-bridge-program "/nonexistent/emacsclient")
        (caught nil))
    (condition-case err
        (yeah-bridge-eval "(+ 1 1)")
      (user-error (setq caught err)))
    (should caught)
    (should (string-match-p "unavailable" (error-message-string caught)))))

(ert-deftest yeah-bridge-buffer-read-returns-the-stub-text ()
  "The buffer read returns the text the stub produced."
  (yeah-bridge-test--with-stub
    (should (equal (yeah-bridge-buffer-read "buffer-text")
                   "stub buffer text"))))

(ert-deftest yeah-bridge-buffer-read-signals-user-error-when-missing ()
  "A buffer that is not there raises `user-error'."
  (yeah-bridge-test--with-stub
    (let ((caught nil))
      (condition-case err
          (yeah-bridge-buffer-read "missing-buffer")
        (user-error (setq caught err)))
      (should caught))))

(ert-deftest yeah-bridge-available-p-is-nil-without-a-program ()
  "A missing program makes the bridge unavailable, without an error."
  (let ((yeah-bridge-program "/nonexistent/emacsclient"))
    (should-not (yeah-bridge-available-p))))

(ert-deftest yeah-bridge-available-p-is-non-nil-with-the-stub ()
  "The stub answers the probe, so the bridge is available."
  (yeah-bridge-test--with-stub
    (should (yeah-bridge-available-p))))

(provide 'test-yeah-emacs-bridge)
;;; test-yeah-emacs-bridge.el ends here
