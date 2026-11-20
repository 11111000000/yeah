;;; check-a-session-may-work-without-a-person.el --- a session may work without a person -*- lexical-binding: t; no-byte-compile: t -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The gap this check covers: the permission system knew only two profiles,
;; `plan' and `build', and neither of them answered the case of a session
;; that runs with nobody at the keyboard.  `plan' forbids the tools that
;; change the world, and `build' asks the person about each of them -- and
;; the person is not there: the orchestrator runs the agent unattended, and
;; every question is a question nobody answers.
;;
;; This check starts a real ACP service on a socket, opens a session, puts
;; the session into the `auto' mode and proves three things on the wire:
;;
;; 1. `session/new' publishes the `auto' mode among the modes the session
;;    may be in;
;; 2. `session/set_mode' accepts it, and the client is told about it;
;; 3. the model asks for the `bash' tool, the client is NOT asked about it,
;;    and the command runs: the marker the command writes is on the disk.
;;
;; The verdict is decided by construction: the control of the claim takes
;; the decision of the mode away -- the mode decides nothing -- and the
;; check then fails by its own assertion, because the client is asked.
;;
;; No network is involved: the model of the service is a fake that runs one
;; command and ends the run (tests/support/yeah-bash-model.el).
;;
;; Exit codes: 0 -- the session worked without a person; 1 -- it did not.

;;; Code:

(require 'cl-lib)

(load (expand-file-name "tests/support/yeah-acp-mode.el") nil t)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--mode-ids (available)
  "Return the ids of the modes AVAILABLE."
  (mapcar (lambda (mode) (plist-get mode :id)) available))

(defun yeah-check--current-mode-update (updates)
  "Return the update that announced the mode of the session, or nil."
  (let ((params
         (cl-find-if
          (lambda (message)
            (let ((update (plist-get (plist-get message :params) :update)))
              (equal "current_mode_update" (plist-get update :sessionUpdate))))
          updates)))
    (and params (plist-get (plist-get params :params) :update))))

(let* ((data-home (make-temp-file "yeah-auto" t))
       (workspace (make-temp-file "yeah-auto-work" t))
       (name (format "yeah-auto-%d" (random 1000000)))
       (client nil)
       (questions nil)
       (updates nil))
  (unwind-protect
      (progn
        (yeah-acp-mode--start-bash name data-home)
        (let ((connection (yeah-acp-client-connect (yeah-service-socket-path name))))
          (setq client (nth 0 connection)
                questions (nth 1 connection)
                updates (nth 2 connection)))
        (let ((answer (yeah-acp-client-request client "initialize"
                                               (list :protocolVersion 1))))
          (unless (plist-get answer :result)
            (push "the handshake was not answered" yeah-check--failures)))
        (let* ((answer (yeah-acp-client-request
                        client "session/new"
                        (list :cwd workspace :mcpServers nil)))
               (result (plist-get answer :result))
               (modes (plist-get result :modes))
               (available (plist-get modes :availableModes)))
          (unless (and (listp available)
                       (member "auto" (yeah-check--mode-ids available)))
            (push (format "the session did not publish the auto mode: %S" available)
                  yeah-check--failures))
          (let ((session-id (plist-get result :sessionId)))
            (let ((reply (yeah-acp-client-request
                          client "session/set_mode"
                          (list :sessionId session-id :modeId "auto"))))
              (when (plist-get reply :error)
                (push (format "the wire refused the auto mode: %S"
                              (plist-get reply :error))
                      yeah-check--failures)))
            (let ((update (yeah-check--current-mode-update (funcall updates))))
              (unless (and update (equal "auto" (plist-get update :currentModeId)))
                (push (format "the client was not told about the auto mode: %S" update)
                      yeah-check--failures)))
            (let ((questions-before (length (funcall questions)))
                  (answer (yeah-acp-client-request
                           client "session/prompt"
                           (list :sessionId session-id
                                 :prompt (vector (list :type "text"
                                                       :text "run it"))))))
              (unless (plist-get answer :result)
                (push "the run of the session in the auto mode did not finish"
                      yeah-check--failures))
              (unless (= questions-before (length (funcall questions)))
                (push "the client was asked about a permission in the auto mode"
                      yeah-check--failures))
              (unless (file-exists-p (expand-file-name "marker.txt" workspace))
                (push "the session in the auto mode did not run the command"
                      yeah-check--failures)))))
    (when client (ignore-errors (yeah-client-close client)))
    (ignore-errors (yeah-service-stop name))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory workspace t)))
  (dolist (failure yeah-check--failures)
    (message "session-auto: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0))))

;;; check-a-session-may-work-without-a-person.el ends here
