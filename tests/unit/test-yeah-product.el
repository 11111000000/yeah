;;; test-yeah-product.el --- interactive product layer tests -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-product)

(defmacro yeah-product-test--with-project (&rest body)
  "Run BODY in an isolated project and data home."
  (declare (indent 0))
  `(let* ((project (make-temp-file "yeah-product-project" t))
          (yeah-data-home (make-temp-file "yeah-product-data" t))
          (yeah-product-refresh-interval 60)
          (buffer nil))
     (unwind-protect
         (progn ,@body)
       (when (buffer-live-p buffer)
         (kill-buffer buffer))
       (ignore-errors (delete-directory project t))
       (ignore-errors (delete-directory yeah-data-home t)))))

(ert-deftest yeah-product-session-root-is-project-scoped-and-private ()
  (yeah-product-test--with-project
    (let* ((first (yeah-product-session-root project))
           (second (yeah-product-session-root project)))
      (should (equal first second))
      (should (string-prefix-p (file-name-as-directory yeah-data-home) first))
      (should (= #o700 (logand #o777 (file-modes first)))))))

(ert-deftest yeah-product-renders-ask-answer-from-events ()
  (yeah-product-test--with-project
    (setq buffer
          (yeah-product-open project
                             (lambda (_prompt callback)
                               (funcall callback "done"))
                             #'yeah-approval-policy-decision))
    (with-current-buffer buffer
      (yeah-product-ask "hello"))
    (yeah-product-render buffer)
    (let ((text (with-current-buffer buffer (buffer-string))))
      (should (string-match-p "Session:" text))
      (should (string-match-p "State: idle" text))
      (should (string-match-p "\\* User\nhello" text))
      (should (string-match-p "\\* Assistant\ndone" text))
      (should (string-match-p "a ask · s steer" text)))))

(ert-deftest yeah-product-formats-stage-events ()
  (let ((text (yeah-product--format-event
               (list :type "steering" :payload "clarify"))))
    (should (string-match-p "Steering" text))
    (should (string-match-p "clarify" text)))
  (let ((text (yeah-product--format-event
               (list :type "nudge" :payload "verify"))))
    (should (string-match-p "Completion nudge" text)))
  (let ((text (yeah-product--format-event
               (list :type "cancel" :payload "stop"))))
    (should (string-match-p "Cancelled" text))))

(ert-deftest yeah-product-doctor-does-not-print-secrets ()
  (let ((buffer (yeah-doctor)))
    (unwind-protect
        (let ((text (with-current-buffer buffer (buffer-string))))
          (should (string-match-p "Emacs:" text))
          (should (string-match-p "Model transport:" text))
          (should (string-match-p "No API keys" text))
          (should-not (string-match-p "Bearer" text)))
      (kill-buffer buffer))))

(ert-deftest yeah-mode-keymap-exposes-control-commands ()
  (should (eq (lookup-key yeah-mode-map (kbd "a")) #'yeah-product-ask))
  (should (eq (lookup-key yeah-mode-map (kbd "s")) #'yeah-product-steer))
  (should (eq (lookup-key yeah-mode-map (kbd "c")) #'yeah-product-cancel))
  (should (eq (lookup-key yeah-mode-map (kbd "r")) #'yeah-product-recover-next))
  (should (eq (lookup-key yeah-mode-map (kbd "g")) #'yeah-product-refresh)))

(provide 'test-yeah-product)
;;; test-yeah-product.el ends here
