;;; live-coding-task.el --- a real coding task through Yeah -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The alpha gate of Stage 4 says what a person must be able to do.  This
;; check does the part that only a real model can do: it gives the harness
;; a small broken project and a plain request, and asks the harness to fix
;; it with its own tools — read, edit, run — and then checks that the
;; project works.
;;
;; The model is real and the tools are real.  Nothing here is faked: the
;; file is changed by the harness, and the test is run by the harness.
;;
;; The configuration comes from the environment, so that no key is ever
;; written into this repository:
;;
;;   YEAH_TEST_KEY    the API key; without it the check skips
;;   YEAH_TEST_HOST   the API host, for example api.minimax.io
;;   YEAH_TEST_MODEL  the model, for example MiniMax-M3
;;
;; Exit codes: 0 — the task was done; 1 — it was not.

;;; Code:

(require 'gptel)
(require 'gptel-openai)
(require 'yeah-control)
(require 'yeah-gptel)
(require 'yeah-perm)
(require 'yeah-session)
(require 'yeah-turn)

(defconst yeah-live--source
  ";;; broken.el --- a function with a wrong answer -*- lexical-binding: t; -*-

(defun broken-add (a b)
  \"Return the sum of A and B.\"
  (message \"broken-add is broken\")
  a)

(provide 'broken)
"
  "The broken file of the project.")

(defconst yeah-live--test
  ";;; broken-test.el --- the test of the project -*- lexical-binding: t; -*-

(require 'ert)
(require 'broken)

(ert-deftest broken-add-adds ()
  \"broken-add adds two numbers.\"
  (should (= 5 (broken-add 2 3))))

(provide 'broken-test)
;;; broken-test.el ends here
"
  "The test of the project.")

(defconst yeah-live--tools '("read" "glob" "grep" "edit" "write" "bash"
                             "elisp-check" "introspect")
  "The tools the task is allowed to use.")

(defun yeah-live--setup (directory)
  "Write the broken project into DIRECTORY and return the path of its file."
  (let ((file (expand-file-name "broken.el" directory)))
    (with-temp-buffer
      (insert yeah-live--source)
      (write-region (point-min) (point-max) file nil 'silent))
    (with-temp-buffer
      (insert yeah-live--test)
      (write-region (point-min) (point-max)
                    (expand-file-name "broken-test.el" directory) nil 'silent))
    file))

(defun yeah-live--run-test (directory)
  "Run the test of the project in DIRECTORY and return whether it passes."
  (let* ((command (format "emacs -Q --batch -L %s -l broken-test.el -f ert-run-tests-batch-and-exit"
                           (shell-quote-argument directory)))
         (buffer (generate-new-buffer " *yeah-live-test*")))
    (with-current-buffer buffer
      (let ((process (make-process :name "yeah-live-test"
                                    :buffer buffer
                                    :command (list "sh" "-c" command)
                                    :connection-type 'pipe
                                    :noquery t)))
        (let ((waited 0))
          (while (and (process-live-p process) (< waited 300))
            (accept-process-output process 0.1)
            (setq waited (1+ waited))))
        (and (not (process-live-p process))
             (= 0 (process-exit-status process)))))))

(defun yeah-live--wait (turn &optional timeout)
  "Wait for TURN to reach a terminal state and return that state."
  (let ((deadline (+ (float-time) (or timeout 600))))
    (while (and (not (yeah-turn-done turn)) (< (float-time) deadline))
      (accept-process-output nil 0.2))
    (yeah-turn-state turn)))

(defun yeah-live--describe (messages)
  "Return one line per message of the conversation MESSAGES."
  (mapcar
   (lambda (message)
     (format "%s: %s"
             (or (plist-get message :role) "?")
             (substring (or (plist-get message :content) "")
                        0
                        (min 90 (length (or (plist-get message :content) ""))))))
   messages))

(defun yeah-live--transport (directory report)
  "Return a transport that asks the model about the project in DIRECTORY.
REPORT is called with the messages of every request the model received."
  (lambda (prompt callback)
    (yeah-gptel-request
     prompt
     (lambda (response &optional info)
       (let ((data (plist-get info :data)))
         (funcall report (yeah-live--describe (plist-get data :messages))))
       (funcall callback response info))
     :system (format "You are an agent inside Emacs, working in the directory %s. You have tools: %s. Act with the tools; do not describe what you are about to do. When the work is done, say what you did."
                     directory
                     (string-join yeah-live--tools ", ")))))

(defun yeah-live--task ()
  "Run the task in a temporary project and return a failure message, or nil."
  (let* ((key (getenv "YEAH_TEST_KEY"))
         (host (or (getenv "YEAH_TEST_HOST") "api.minimax.io"))
         (model (or (getenv "YEAH_TEST_MODEL") "MiniMax-M3"))
         (directory (make-temp-file "yeah-live-task" t))
         (file (yeah-live--setup directory))
         (session (yeah-session-open "live" directory))
         (control nil)
         (turn nil)
         (state nil)
         (failure nil))
    (unless key
      (message "live task: skipped — no YEAH_TEST_KEY in the environment")
      (kill-emacs 0))
    (setq gptel-backend
          (gptel-make-openai "yeah-live"
            :host host
            :endpoint "/v1/chat/completions"
            :key key
            :models (list (intern model))))
    (setq gptel-model (intern model))
    (dolist (tool yeah-live--tools)
      (yeah-perm-rules-add (yeah-perm-rule-make tool "*" 'allow)))
    (setq control
          (yeah-control-new
           session
           (yeah-live--transport directory
                          (lambda (messages)
                            (dolist (line messages)
                              (message "live task:   %s" line))))
           nil nil 3))
    (yeah-control-ask control
                      (format "Fix the bug in %s/broken.el: the function broken-add must return the sum of A and B, not A. Use the edit tool on that file to replace `a' with `(+ a b)' in its body, then run emacs -Q --batch -L %s -l broken-test.el -f ert-run-tests-batch-and-exit to check that the test passes. Do not change the test."
                              directory directory))
    (setq turn (yeah-control-active-turn control))
    (unless turn
      (message "live task: the run did not start")
      (kill-emacs 1))
    (setq state (yeah-live--wait turn))
    (message "live task: state=%S" state)
    (dolist (event (yeah-session-records session))
      (message "live task: %s" event))
    (message "live task: the file now says:\n%s"
             (with-temp-buffer
               (insert-file-contents file)
               (buffer-string)))
    (unless (equal state 'completed)
      (setq failure (format "the run ended in %S" state)))
    (unless (yeah-live--run-test directory)
      (setq failure "the test of the project does not pass"))
    (ignore-errors (delete-directory directory t))
    failure))

(let ((failure (yeah-live--task)))
  (when failure
    (message "live task: %s" failure)
    (kill-emacs 1))
  (kill-emacs 0))

;;; live-coding-task.el ends here
