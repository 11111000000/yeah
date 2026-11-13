;;; check-git-tools.el --- canary for the git tools -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; The git tools on a real repository in a temporary directory: the status
;; shows the changed file, the diff shows the change, and a commit needs a
;; rule that allows it — without the rule the commit is refused and the
;; history does not move.
;;
;; The fixture is built with the real git, in a subprocess the check starts
;; itself: the tools under test do not build the fixture they are tested on.
;; No model and no network are involved.

;;; Code:

(require 'cl-lib)
(require 'yeah-git)
(require 'yeah-perm)
(require 'yeah-result)
(require 'yeah-tools)

(defun yeah-check-git--git (directory args)
  "Run git with ARGS in DIRECTORY and return (EXIT . OUTPUT)."
  (let ((buffer (generate-new-buffer " *yeah-check-git*"))
        (exit nil))
    (with-current-buffer buffer
      (let ((process
             (let ((default-directory directory))
               (make-process
                :name "yeah-check-git"
                :buffer buffer
                :command (cons "git" args)
                :coding '(utf-8 . utf-8)
                :connection-type 'pipe
                :noquery t
                :sentinel
                (lambda (proc _event)
                  (when (memq (process-status proc) '(exit signal))
                    (setq exit (process-exit-status proc))))))))
        (while (and (null exit) (process-live-p process))
          (accept-process-output process 0.05))
        (let ((output (buffer-substring-no-properties (point-min) (point-max))))
          (kill-buffer buffer)
          (cons exit output))))))

(defun yeah-check-git--call (name args)
  "Call the tool NAME with ARGS and return its result.
The tools are asynchronous: the result arrives through the continuation,
so the event loop is pumped until it does."
  (let ((cell (list nil)))
    (yeah-tools-dispatch name args (lambda (result) (setf (car cell) result)))
    (let ((deadline (+ (float-time) 30)))
      (while (and (null (car cell)) (< (float-time) deadline))
        (accept-process-output nil 0.05)))
    (or (car cell) (yeah-result-error "the tool never answered"))))

(defun yeah-check-git--commits (directory)
  "Return the number of commits in the repository at DIRECTORY."
  (let ((log (yeah-check-git--git directory '("log" "--oneline"))))
    (length (split-string (cdr log) "\n" t))))

(let* ((root (make-temp-file "yeah-git-tools" t))
       (failures nil))
  (unwind-protect
      (progn
        ;; --- the fixture: a repository with one committed file -----------
        (yeah-check-git--git root '("init" "-q"))
        (yeah-check-git--git root '("config" "user.email" "check@example.invalid"))
        (yeah-check-git--git root '("config" "user.name" "Yeah Check"))
        (with-temp-file (expand-file-name "demo.txt" root)
          (insert "one\n"))
        (yeah-check-git--git root '("add" "--" "demo.txt"))
        (yeah-check-git--git root '("commit" "--no-gpg-sign" "-m" "initial"))
        ;; the file changes after that commit
        (with-temp-file (expand-file-name "demo.txt" root)
          (insert "two\n"))

        ;; --- the tools are registered ------------------------------------
        (dolist (name '("git_status" "git_diff" "git_commit"))
          (unless (yeah-tools-get name)
            (push (format "the built-in tool is missing: %s" name) failures)))

        ;; --- the status shows the changed file ----------------------------
        (let* ((result (yeah-check-git--call "git_status" (list root)))
               (text (yeah-result-model-text result)))
          (unless (yeah-result-success-p result)
            (push (format "the status failed: %S" result) failures))
          (unless (string-match-p "M demo\\.txt" text)
            (push (format "the status did not show demo.txt as changed: %s" text)
                  failures)))

        ;; --- the diff shows the change ------------------------------------
        (let* ((result (yeah-check-git--call "git_diff" (list root "demo.txt")))
               (text (yeah-result-model-text result)))
          (unless (yeah-result-success-p result)
            (push (format "the diff failed: %S" result) failures))
          (unless (string-match-p "-one" text)
            (push (format "the diff did not show the old line: %s" text) failures))
          (unless (string-match-p "+two" text)
            (push (format "the diff did not show the new line: %s" text) failures)))

        ;; --- a commit needs a rule that allows it --------------------------
        (yeah-perm-rules-reset-for-test)
        (let* ((result (yeah-check-git--call "git_commit"
                                              (list root "the change" "demo.txt")))
               (text (yeah-result-model-text result)))
          (when (yeah-result-success-p result)
            (push "a commit happened although no rule allowed it" failures))
          (unless (string-match-p "rules" text)
            (push (format "the refusal did not name the rules: %s" text) failures))
          (unless (= 1 (yeah-check-git--commits root))
            (push "the history moved although no rule allowed the commit" failures)))

        ;; --- with the rule, the commit happens -----------------------------
        (yeah-perm-rules-add (yeah-perm-rule-make "git_commit" "*" 'allow))
        (let* ((result (yeah-check-git--call "git_commit"
                                              (list root "the change" "demo.txt")))
               (text (yeah-result-model-text result)))
          (unless (yeah-result-success-p result)
            (push (format "the commit was refused although the rules allow it: %s"
                          text)
                  failures))
          (unless (= 2 (yeah-check-git--commits root))
            (push "the commit did not reach the history" failures))
          (let ((log (yeah-check-git--git root '("log" "--oneline"))))
            (unless (string-match-p "the change" (cdr log))
              (push (format "the commit did not carry the message: %s" (cdr log))
                    failures)))
          (let ((status (yeah-check-git--git root '("status" "--porcelain"))))
            (unless (string= "" (string-trim (cdr status)))
              (push (format "the tree is not clean after the commit: %s"
                            (cdr status))
                    failures))))

        (dolist (failure failures)
          (message "git tools: %s" failure))
        (if failures
            (kill-emacs 1)
          (kill-emacs 0)))
    (ignore-errors (delete-directory root t t))))

;;; check-git-tools.el ends here
