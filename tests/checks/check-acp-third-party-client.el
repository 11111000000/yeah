;;; check-acp-third-party-client.el --- a third-party ACP client drives Yeah -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The wire checks so far used Yeah's own processes as the client.  This
;; check drives the ACP server with xenodium/acp.el — a client that is not
;; Yeah — loaded from the research clone.  The clone is a reference, not a
;; runtime dependency; when it is absent the check skips itself.
;;
;; The model is a FAKE that answers with text, so the check needs no
;; network and no key.
;;
;; Exit codes: 0 — the third-party client completed the handshake, the
;; session and the prompt, and saw the streamed updates; 1 — it did not.

;;; Code:

(require 'cl-lib)
(require 'json)

(defun yeah-check--acp-client-dir ()
  "Return the directory of the independent acp.el client.
The environment variable wins, then the checkout sibling, then the usual
research checkout in the user's home."
  (let* ((library-dir
          (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))
         (candidates
          (delq nil
                (list (getenv "YEAH_ACP_RESEARCH_DIR")
                      (expand-file-name "../../emacs-agents-research/acp.el"
                                        library-dir)
                      (expand-file-name "~/Projects/emacs-agents-research/acp.el")))))
    (or (cl-find-if (lambda (dir)
                      (file-readable-p (expand-file-name "acp.el" dir)))
                    candidates)
        (car candidates))))

(defvar yeah-check--acp-dir (yeah-check--acp-client-dir)
  "The directory of the acp.el research clone.")

(unless (and (file-directory-p yeah-check--acp-dir)
             (file-readable-p (expand-file-name "acp.el" yeah-check--acp-dir)))
  ;; The independent client lives outside this repository.  Its absence is
  ;; a blocked check, not a passed one: exit 2 says "unknown", and a
  ;; check that cannot fail proves nothing.
  (message "third-party: blocked — the acp.el research clone is absent (%s)"
           yeah-check--acp-dir)
  (kill-emacs 2))

(add-to-list 'load-path yeah-check--acp-dir)
(require 'acp)

(defvar yeah-check--emacs
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (expand-file-name "~/.nix-profile/bin/emacs"))
  "The Emacs program that runs the Yeah server.")

(defvar yeah-check--lib
  (expand-file-name (file-name-directory (or (locate-library "yeah-acp")
                                             "yeah-acp.el")))
  "The directory holding Yeah's Elisp modules.")

(defvar yeah-check--data-home (make-temp-file "yeah-acp-3p" t)
  "The data home of the server process.")

(defun yeah-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil, at most TIMEOUT."
  (let ((deadline (+ (float-time) (or timeout 20)))
        (done nil))
    (while (and (not done) (< (float-time) deadline))
      (accept-process-output nil 0.05)
      (setq done (funcall predicate)))
    done))

(let ((failures nil)
      (notifications nil)
      (prompt-answer nil))
  (unwind-protect
      (progn
        (let ((client (acp-make-client
                       :command yeah-check--emacs
                       :command-params
                       (list "-Q" "--batch"
                             "-L" yeah-check--lib
                             "-l" "yeah-acp"
                             "--eval"
                             (format
                              (concat "(progn (setq yeah-data-home %S) "
                                      "(defun yeah-check--transport (prompt callback) "
                                      "(funcall callback \"done\")) "
                                      "(yeah-acp-serve #'yeah-check--transport))")
                              yeah-check--data-home)))))
          (acp-subscribe-to-notifications
           :client client
           :on-notification (lambda (notification)
                              (push notification notifications)))
          ;; initialize
          (let ((init-result (condition-case err
                                 (acp-send-request
                                  :client client
                                  :request (acp-make-initialize-request
                                            :protocol-version 1)
                                  :sync t)
                               (error (push (format "initialize failed: %S" err)
                                            failures)
                                      nil))))
            (unless (equal 1 (map-elt init-result 'protocolVersion))
              (push (format "initialize answered %S" init-result) failures)))
          ;; a session
          (let* ((session-result (condition-case err
                                     (acp-send-request
                                      :client client
                                      :request (acp-make-session-new-request
                                                :cwd yeah-check--data-home)
                                      :sync t)
                                   (error (push (format "session/new failed: %S" err)
                                                failures)
                                          nil)))
                 (session-id (map-elt session-result 'sessionId)))
            (unless (stringp session-id)
              (push "session/new did not return a session id" failures))
            (when session-id
              ;; a prompt
              (acp-send-request
               :client client
               :request (acp-make-session-prompt-request
                         :session-id session-id
                         :prompt (list (list (cons 'type "text")
                                             (cons 'text "hello"))))
               :on-success (lambda (result)
                             (setq prompt-answer result))
               :on-failure (lambda (err) (push (format "prompt failed: %S" err)
                                               failures)))
              (unless (yeah-check--await (lambda () prompt-answer) 20)
                (push "the prompt was not answered" failures))
              (unless (equal "end_turn" (map-elt (or prompt-answer '())
                                                 'stopReason))
                (push (format "the prompt answered with %S"
                              (map-elt (or prompt-answer '()) 'stopReason))
                      failures))
              ;; the streamed updates arrived
              (unless (cl-some (lambda (notification)
                                 (equal "session/update"
                                        (map-elt notification 'method)))
                               notifications)
                (push "no session/update notification arrived" failures)))
            (acp-shutdown :client client))))

    (dolist (failure failures)
      (message "third-party: %s" failure))
    (ignore-errors (delete-directory yeah-check--data-home t))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-acp-third-party-client.el ends here
