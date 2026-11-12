;;; check-coding-tools-end-to-end.el --- real coding tool scenario -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Exercise the registry and real built-in handlers on a temporary project:
;; discovery, guarded editing, non-evaluating validation, async process output
;; and Emacs introspection.  No model or network is involved.

;;; Code:

(require 'cl-lib)
(require 'yeah-tools)
(require 'yeah-result)

(defun yeah-check-coding--wait (predicate)
  "Pump the event loop until PREDICATE returns non-nil or five seconds pass."
  (let ((deadline (+ (float-time) 5)))
    (while (and (not (funcall predicate))
                (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(let* ((root (make-temp-file "yeah-coding-tools" t))
       (file (expand-file-name "demo.el" root))
       (failures nil)
       (buffer nil))
  (unwind-protect
      (progn
        (with-temp-file file
          (insert "(defun yeah-demo () \"old\" 1)\n"))
        (setq buffer (find-file-noselect file))

        ;; File tools return bounded structured results.
        (let ((read-result (yeah-tools-call "read" (list file))))
          (unless (yeah-result-success-p read-result)
            (push "read failed" failures)))
        (let ((glob-result (yeah-tools-call "glob" (list "\\.el\\'" root 10))))
          (unless (string-match-p "demo.el"
                                  (yeah-result-model-text glob-result))
            (push "glob did not find demo.el" failures)))
        (let ((grep-result (yeah-tools-call "grep" (list "yeah-demo" root 10))))
          (unless (string-match-p "demo.el:1:"
                                  (yeah-result-model-text grep-result))
            (push "grep did not find the function" failures)))

        ;; A fresh modification tick guards a real buffer edit.
        (let* ((tick (with-current-buffer buffer (buffer-chars-modified-tick)))
               (edit-result (yeah-tools-call
                             "edit" (list file "\"old\"" "\"new\"" tick))))
          (unless (yeah-result-success-p edit-result)
            (push (format "tick edit failed: %S" edit-result) failures)))
        (unless (with-current-buffer buffer
                  (string-match-p "\"new\"" (buffer-string)))
          (push "tick edit did not change the buffer" failures))
        (unless (yeah-result-success-p (yeah-tools-call "elisp-check" (list file)))
          (push "the edited Elisp is not readable" failures))

        ;; Async bash returns through the continuation, not a blocking wait.
        (let ((outcome nil))
          (yeah-tools-dispatch
           "bash" (list "printf stage-1" 5 root)
           (lambda (result) (setq outcome result)))
          (unless (yeah-check-coding--wait (lambda () outcome))
            (push "bash did not settle" failures))
          (unless (string-match-p "stage-1"
                                  (yeah-result-model-text outcome))
            (push (format "bash returned the wrong output: %S" outcome)
                  failures)))

        (unless (yeah-result-success-p
                 (yeah-tools-call "introspect" (list "car" "function")))
          (push "introspection failed" failures))

        (dolist (name '("read" "glob" "grep" "edit" "write" "bash"
                        "job-status" "job-read" "job-cancel"
                        "introspect" "buffer-read" "elisp-check" "diagnostics"))
          (unless (yeah-tools-get name)
            (push (format "built-in tool is missing: %s" name) failures)))

        (dolist (failure failures)
          (message "coding tools: %s" failure))
        (if failures
            (kill-emacs 1)
          (kill-emacs 0)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (set-buffer-modified-p nil))
      (kill-buffer buffer))
    (ignore-errors (delete-directory root t t))))

;;; check-coding-tools-end-to-end.el ends here
