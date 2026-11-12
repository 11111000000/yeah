;;; live-interactive-path.el --- the interactive path with a live model -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The alpha release gate of Stage 4 says what a person must be able to
;; do.  This check drives the interactive product path against a live
;; provider: open a session in the journal mode, ask a real coding task,
;; watch the work, cancel a run, quit, restart and recover the pending
;; input.  The person is scripted (approvals are answered for them), but
;; the model and the tools are real.
;;
;; The configuration comes from the environment, so that no key is ever
;; written into this repository:
;;
;;   YEAH_TEST_KEY    the API key; without it the check skips
;;   YEAH_TEST_HOST   the API host, for example api.minimax.io
;;   YEAH_TEST_MODEL  the model, for example MiniMax-M2.7
;;
;; Exit codes: 0 — the path works; 1 — it does not.

;;; Code:

(require 'gptel)
(require 'gptel-openai)
(require 'yeah-control)
(require 'yeah-product)
(require 'yeah-session)

(defun yeah-live--task-directory ()
  "Return a directory with a small broken project in it."
  (let ((directory (make-temp-file "yeah-live-ui" t)))
    (with-temp-buffer
      (insert ";;; broken.el --- a function with a wrong answer -*- lexical-binding: t; -*-\n\n"
              "(defun broken-add (a b)\n"
              "  \"Return the sum of A and B.\"\n"
              "  a)\n\n"
              "(provide 'broken)\n")
      (write-region (point-min) (point-max)
                    (expand-file-name "broken.el" directory) nil 'silent))
    (with-temp-buffer
      (insert ";;; broken-test.el --- the test -*- lexical-binding: t; -*-\n\n"
              "(require 'ert)\n(require 'broken)\n\n"
              "(ert-deftest broken-add-adds ()\n"
              "  (should (= 5 (broken-add 2 3))))\n\n"
              "(provide 'broken-test)\n")
      (write-region (point-min) (point-max)
                    (expand-file-name "broken-test.el" directory) nil 'silent))
    directory))

(defun yeah-live--wait-for (predicate &optional timeout)
  "Wait for PREDICATE to return non-nil and return its value."
  (let ((deadline (+ (float-time) (or timeout 300))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.2))
    (funcall predicate)))

(defun yeah-live--path ()
  "Drive the interactive path and return a failure message, or nil."
  (let* ((key (getenv "YEAH_TEST_KEY"))
         (host (or (getenv "YEAH_TEST_HOST") "api.minimax.io"))
         (model (or (getenv "YEAH_TEST_MODEL") "MiniMax-M2.7"))
         (directory (yeah-live--task-directory))
         (failure nil))
    (unless key
      (message "live ui: skipped — no YEAH_TEST_KEY in the environment")
      (kill-emacs 0))
    (setq gptel-backend
          (gptel-make-openai "yeah-live-ui"
            :host host
            :endpoint "/v1/chat/completions"
            :key key
            :models (list (intern model))))
    (setq gptel-model (intern model))
    (dolist (tool '("read" "glob" "grep" "edit" "write" "bash"
                    "elisp-check" "introspect"))
      (yeah-perm-rules-add (yeah-perm-rule-make tool "*" 'allow)))
    (let* ((buffer (yeah-product-open directory nil
                                      (lambda (_request)
                                        (list :effect :allow :reply :once))
                                      nil nil nil "build"))
           (control (with-current-buffer buffer yeah-product--control)))
      (unless (and buffer control)
        (setq failure "the journal buffer was not created"))
      (unless failure
        (with-current-buffer buffer
          (yeah-product-ask "Fix the bug in broken.el in this project: broken-add must return the sum of A and B, not A. Use the edit tool on broken.el to replace the body's a with (+ a b), then run the test in the project with emacs -Q --batch -L . -l broken-test.el -f ert-run-tests-batch-and-exit. Do not change the test.")
          (unless (yeah-live--wait-for (lambda ()
                                         (yeah-control-done-p
                                          (with-current-buffer buffer
                                            yeah-product--control))))
            (setq failure "the run did not finish")))
        (unless failure
          (with-current-buffer buffer
            (yeah-product-render)
            (let ((text (buffer-string)))
              (unless (string-match-p "broken-add" text)
                (setq failure "the journal does not show the task"))
              (unless (string-match-p "\\(+ a b\\)" text)
                (setq failure "the journal does not show the edit"))))
          (dolist (event (yeah-session-records
                          (yeah-control-session
                           (with-current-buffer buffer yeah-product--control))))
            (message "live ui: %s" event))
          (unless failure
            (let ((file (expand-file-name "broken.el" directory)))
              (with-temp-buffer
                (insert-file-contents file)
                (unless (search-forward "(+ a b)" nil t)
                  (setq failure "the file was not fixed")))))

        ;; --- cancel a run, then quit and restart ---
        (with-current-buffer buffer
          (yeah-product-ask "Wait forever, never answer.")
          (yeah-product-cancel)
          (unless (yeah-control-done-p
                   (with-current-buffer buffer yeah-product--control))
            (setq failure "the cancel did not stop the run"))
          (unless (member "cancel"
                          (mapcar (lambda (event) (plist-get event :type))
                                  (yeah-session-records
                                   (yeah-control-session
                                    (with-current-buffer buffer
                                      yeah-product--control)))))
            (setq failure "the cancel is not in the journal"))
          ;; --- quit and restart: the pending input survives ---
        (with-current-buffer buffer
          (yeah-product-ask "Wait forever, never answer.")
          (yeah-control-ask (with-current-buffer buffer yeah-product--control)
                            "a task for later")
          (let* ((session (yeah-control-session
                           (with-current-buffer buffer yeah-product--control)))
                 (session-id (plist-get session :id))
                 (again (yeah-product-open
                         directory nil
                         (lambda (_request)
                           (list :effect :allow :reply :once))
                         nil nil nil "build" session-id))
                 (control (with-current-buffer again yeah-product--control)))
            (unless (= 1 (length (yeah-control-pending control)))
              (setq failure "the pending input did not survive the restart"))
            (when (not (yeah-control-done-p control))
              (setq failure "the restart ran a pending input by itself"))
            (yeah-control-recover-next control)
            (when (yeah-control-done-p control)
              (setq failure "the recovery did not start the pending input"))
            (yeah-control-cancel control)
            (when (not (yeah-control-done-p control))
              (setq failure "the cancel did not stop the recovered run"))))
    (ignore-errors (delete-directory directory t))
    failure))))))

(message "live ui: starting")
(let ((failure (yeah-live--path)))
  (when failure
    (message "live ui: %s" failure)
    (kill-emacs 1))
  (message "live ui: the interactive path works")
  (kill-emacs 0))

;;; live-interactive-path.el ends here
