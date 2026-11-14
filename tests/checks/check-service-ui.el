;;; check-service-ui.el --- the editor drives a service through the UI -*- lexical-binding: t; no-byte-compile: t -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The person-facing surface is shared by the attached and service
;; placements.  This check opens a real attached journal with a fake model
;; and a real service Emacs with a fake model, sends the same prompt
;; through both, and reads the transcripts back.  No network and no key are
;; needed.

;;; Code:

(require 'cl-lib)
(require 'yeah-product)
(require 'yeah-service)
(require 'yeah-client)
(require 'yeah-journal)
(require 'yeah-service-ui)

(defun yeah-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE holds, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 15))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-check--count-matches (pattern haystack)
  "Return how many times PATTERN matches in HAYSTACK."
  (let ((start 0)
        (count 0))
    (while (string-match pattern haystack start)
      (setq count (1+ count)
            start (match-end 0)))
    count))

(let* ((failures nil)
       (name (format "check-%d" (random 1000000)))
       (data-home (make-temp-file "yeah-service-ui" t))
       (attached-home (make-temp-file "yeah-attached-ui" t))
       (attached-root (make-temp-file "yeah-attached-root" t))
       (client nil)
       (journal nil)
       (buffer nil)
       (attached-buffer nil))
  (unwind-protect
      (progn
        ;; --- the attached placement ---------------------------------------
        (let ((yeah-data-home attached-home))
          (setq attached-buffer
                (yeah-product-open
                 attached-root
                 (lambda (_prompt callback)
                   (funcall callback "the answer"))
                 (lambda (_request)
                   (list :effect :allow :reply :once)))))
        (with-current-buffer attached-buffer
          (yeah-product-ask "hi"))
        (yeah-check--await
         (lambda ()
           (with-current-buffer attached-buffer
             (string-match-p "\\* Yeah\nthe answer" (buffer-string))))
         5)
        (with-current-buffer attached-buffer
          (let ((text (buffer-string)))
            (unless (derived-mode-p 'yeah-journal-mode)
              (push "the attached surface is not the shared journal" failures))
            (unless buffer-read-only
              (push "the attached journal is not read-only" failures))
            (unless (string-match-p "\\* User\nhi" text)
              (push "the attached journal does not show the question" failures))
            (unless (string-match-p "\\* Yeah\nthe answer" text)
              (push "the attached journal does not show the answer" failures))
            (unless (= 1 (yeah-check--count-matches "\\* User\nhi" text))
              (push "the attached question is not rendered exactly once" failures))
            (unless (equal "attached"
                           (plist-get (yeah-journal-current-session)
                                      :placement))
              (push "the attached journal does not identify its placement"
                    failures))))

        ;; --- the service placement ------------------------------------------
        (yeah-service-start
         name
         (concat "(defun yeah-check--transport (prompt callback) "
                 "(funcall callback \"the answer\"))")
         data-home
         "#'yeah-check--transport"
         t)
        (setq client
              (yeah-client-connect
               (yeah-service-socket-path name)))
        (let ((session-id nil))
          (yeah-client-request
           client "session/new"
           (list :cwd data-home :mcpServers nil)
           (lambda (result _error)
             (setq session-id (plist-get result :sessionId))))
          (yeah-check--await (lambda () session-id))
          (unless (stringp session-id)
            (push "the service did not create a session" failures))
          (when session-id
            (setq journal (yeah-journal-open nil nil "*yeah-service-ui-test*"))
            (setf (yeah-journal-driver journal)
                  (yeah-service-ui--driver journal))
            (setq buffer (yeah-journal-buffer journal))
            (with-current-buffer buffer
              (yeah-service-ui-mode)
              (setq yeah-journal--current journal
                    yeah-service-ui--client client
                    yeah-service-ui--session-id session-id
                    yeah-service-ui--busy nil
                    yeah-service-ui--records nil
                    yeah-service-ui--event-id 0))
            (setf (yeah-client-on-notification client)
                  (lambda (message)
                    (when (equal (plist-get message :method) "session/update")
                      (yeah-service-ui--render-update buffer message))))
            (with-current-buffer buffer
              (yeah-service-ui--ask "hi"))
            (yeah-check--await
             (lambda ()
               (with-current-buffer buffer
                 (string-match-p "end_turn" (buffer-string))))
             15)
            (with-current-buffer buffer
              (let ((text (buffer-string)))
                (unless (derived-mode-p 'yeah-journal-mode)
                  (push "the service surface is not the shared journal" failures))
                (unless buffer-read-only
                  (push "the service journal is not read-only" failures))
                (unless (string-match-p "\\* User\nhi" text)
                  (push "the question is not in the journal" failures))
                (unless (string-match-p "\\* Yeah\nthe answer" text)
                  (push "the answer is not in the journal" failures))
                (unless (string-match-p "\\* Finished\nend_turn" text)
                  (push (format "the stop reason is not in the journal: %S" text)
                        failures))
                (unless (= 1 (yeah-check--count-matches
                              "\\* User\nhi" text))
                  (push (format "the question is not rendered exactly once: %S" text)
                        failures))
                (unless (equal "service"
                               (plist-get (yeah-journal-current-session)
                                          :placement))
                  (push "the service journal does not identify its placement"
                        failures))))))
    (when client
      (yeah-client-close client))
    (yeah-service-stop name)
    (when (buffer-live-p buffer) (kill-buffer buffer))
    (when (buffer-live-p attached-buffer) (kill-buffer attached-buffer))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory attached-root t))
    (ignore-errors (delete-directory attached-home t))
    (dolist (failure failures)
      (message "service-ui: %s" failure))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0)))))

;;; check-service-ui.el ends here
