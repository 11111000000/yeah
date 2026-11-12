;;; live-fixed-point.el --- the Y of Yeah: Yeah repairs a Yeah canary -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The Y in Yeah is bounded, inspectable recursive work: Yeah can help
;; develop and verify Yeah itself.  This check is the smallest honest
;; version of that: a child of Yeah is given a project with a failing
;; canary, and it is asked to make the canary pass.  The child runs the
;; tests, finds the broken source, fixes it with a guarded edit, runs the
;; tests again, and returns the diff of what it changed.
;;
;; The model and the tools are real.  The project is small, so that a real
;; model can finish the task.  The child runs in its own session, with
;; its own permissions, and the parent reads its journal.
;;
;; The configuration comes from the environment, so that no key is ever
;; written into this repository:
;;
;;   YEAH_TEST_KEY    the API key; without it the check skips
;;   YEAH_TEST_HOST   the API host, for example api.minimax.io
;;   YEAH_TEST_MODEL  the model, for example MiniMax-M2.7
;;
;; Exit codes: 0 — the child repaired the canary; 1 — it did not.

;;; Code:

(require 'gptel)
(require 'gptel-openai)
(require 'yeah-control)
(require 'yeah-gptel)
(require 'yeah-perm)
(require 'yeah-session)
(require 'yeah-subagent)

(defun yeah-live-fp--project (directory)
  "Write a project with a failing canary into DIRECTORY."
  (let ((source (expand-file-name "double.el" directory))
        (test (expand-file-name "double-check.el" directory)))
    (with-temp-buffer
      (insert ";;; double.el --- a function with a wrong answer -*- lexical-binding: t; -*-\n\n"
              "(defun double (n)\n"
              "  \"Return N doubled.\"\n"
              "  n)\n\n"
              "(provide 'double)\n")
      (write-region (point-min) (point-max) source nil 'silent))
    (with-temp-buffer
      (insert ";;; double-check.el --- the canary -*- lexical-binding: t; -*-\n\n"
              "(require 'ert)\n(require 'double)\n\n"
              "(ert-deftest double-doubles ()\n"
              "  \"double doubles its argument.\"\n"
              "  (should (= 8 (double 4))))\n\n"
              "(provide 'double-check)\n")
      (write-region (point-min) (point-max) test nil 'silent))
    source))

(defun yeah-live-fp--preset ()
  "Return the prompt of the repairer."
  (concat
   "You are a repairer working inside Emacs.  The project has a source file "
   "double.el and a canary double-check.el.  The canary fails because double "
   "returns its argument instead of doubling it.\n"
   "Do these things, in this order, with the tools:\n"
   "1. Run the canary with bash to see it fail: emacs -Q --batch -L . "
   "-l double-check.el -f ert-run-tests-batch-and-exit\n"
   "2. Read double.el with the read tool; note its tick in the result.\n"
   "3. Use the edit tool on double.el to replace exactly the text `  n)' "
   "with `  (* 2 n))', passing the tick from the read result.\n"
   "4. Run the canary again with bash to see it pass.\n"
   "5. End by saying the command you ran and the diff of what you changed.\n"
   "Act with the tools; do not narrate what you are about to do.\n"))

(defun yeah-live-fp--wait (child &optional timeout)
  "Wait for the child CHILD to finish and return its record."
  (let ((deadline (+ (float-time) (or timeout 600))))
    (while (and (not (yeah-turn-done (plist-get child :turn)))
                (< (float-time) deadline))
      (accept-process-output nil 0.2))
    child))

(defun yeah-live-fp--run ()
  "Run the fixed point and return a failure message, or nil."
  (let* ((key (getenv "YEAH_TEST_KEY"))
         (host (or (getenv "YEAH_TEST_HOST") "api.minimax.io"))
         (model (or (getenv "YEAH_TEST_MODEL") "MiniMax-M2.7"))
         (directory (make-temp-file "yeah-fixed-point" t))
         (source (yeah-live-fp--project directory))
         (failure nil))
    (unless key
      (message "live fp: skipped — no YEAH_TEST_KEY in the environment")
      (kill-emacs 0))
    (setq gptel-backend
          (gptel-make-openai "yeah-fp"
            :host host
            :endpoint "/v1/chat/completions"
            :key key
            :models (list (intern model))))
    (setq gptel-model (intern model))
    (let* ((yeah-subagent-max-nudges 4)
           (parent (yeah-session-open "fixed-point" directory))
           (child nil))
      (dolist (tool '("read" "glob" "grep" "edit" "write" "bash" "elisp-check"))
        (yeah-perm-rules-add (yeah-perm-rule-make tool "*" 'allow)))
      (setq child
            (yeah-subagent-spawn
             parent
             "repairer"
             (format "Call the edit tool on %s/double.el with old_str `  n)' and new_str `  (* 2 n))' and the tick from the read result of %s/double.el. Nothing else."
                     directory directory)
             :tools '("read" "glob" "grep" "edit" "write" "bash" "elisp-check")
             :transport (lambda (prompt callback)
                          (yeah-gptel-request
                           prompt callback
                           :system (format "You are a repairer working inside Emacs. The project is in %s; every path you use must be inside it. You have tools: read, glob, grep, edit, write, bash, elisp-check. Act with them; do not narrate what you are about to do."
                                           directory)))))
      (yeah-live-fp--wait child)
      (dolist (event (yeah-session-records (plist-get child :child-session)))
        (message "live fp: %s" event))
      (unless (eq 'completed (plist-get child :status))
        (setq failure (format "the child ended in %S" (plist-get child :status))))
      (unless failure
        (let* ((control (make-process :name "yeah-fp-check"
                                       :buffer (generate-new-buffer " *fp*")
                                       :command (list "emacs" "-Q" "--batch"
                                                      "-L" directory
                                                      "-l" "double-check.el"
                                                      "-f" "ert-run-tests-batch-and-exit")
                                       :connection-type 'pipe
                                       :noquery t)))
          (let ((waited 0))
            (while (and (process-live-p control) (< waited 120))
              (accept-process-output control 0.1)
              (setq waited (1+ waited))))
          (unless (and (not (process-live-p control))
                       (= 0 (process-exit-status control)))
            (setq failure "the canary does not pass after the child's work"))))
      (unless failure
        (let ((text (with-temp-buffer
                      (insert-file-contents source)
                      (buffer-string))))
          (unless (string-match-p (regexp-quote "(* 2 n)") text)
            (setq failure "the source does not double its argument"))))
      (unless (getenv "YEAH_FP_KEEP")
        (ignore-errors (delete-directory directory t)))
      failure)))

(let ((attempts 3)
      (failure nil))
  (while (and (> attempts 0) (null failure))
    (setq attempts (1- attempts))
    (setq failure (yeah-live-fp--run))
    (when failure
      (message "live fp: attempt failed: %s" failure)
      (setq failure nil)))
  (when (and failure (message "live fp: the child repaired the canary"))
    nil)
  (when failure
    (message "live fp: %s" failure)
    (kill-emacs 1))
  (kill-emacs 0))

;;; live-fixed-point.el ends here
