;;; check-a-session-changes-its-permission-profile-over-the-wire.el --- the mode of a session changes over the wire -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The defect: the method `session/set_mode' did not exist, and a client that
;; asked was answered with `-32601'.  The permission profile of a session
;; could not be changed over the wire, so a person could not tell the agent
;; to look without touching, and the client of Paseo had no modes to show.
;;
;; This check starts a real ACP service on a socket, opens two sessions, and
;; proves four things on the wire:
;;
;; 1. `session/new' publishes the modes the session may be in and the one it
;;    is in;
;; 2. `session/set_mode' is answered, and not with an error;
;; 3. in the `build' mode the client is asked about a tool that changes the
;;    world, and the tool runs after the answer;
;; 4. in the `plan' mode the client is not asked at all, the tool is refused,
;;    and the file it would have written is not written.
;;
;; The verdict is decided by construction: the mode of a session decides
;; before anybody is asked, and the control of the claim takes that decision
;; out -- the mode decides nothing -- and the check then fails by its own
;; assertion.
;;
;; No network is involved: the model of the service is a fake that calls the
;; `write' tool and then the `finish' tool
;; (tests/support/yeah-mode-model.el).
;;
;; Exit codes: 0 -- the mode of the session changed over the wire and
;; decided; 1 -- it did not.

;;; Code:

(require 'cl-lib)

(load (expand-file-name "tests/support/yeah-acp-mode.el") nil t)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--mode-ids (available)
  "Return the ids of the modes AVAILABLE."
  (mapcar (lambda (mode) (plist-get mode :id)) available))

(defun yeah-check--current-mode-update (updates)
  "Return the update that announced the mode of the session, or nil.
The update is inside the notification: the notification of ACP carries the
session and the update, and the update names the mode."
  (let ((params
         (cl-find-if
          (lambda (message)
            (let ((update (plist-get (plist-get message :params) :update)))
              (equal "current_mode_update" (plist-get update :sessionUpdate))))
          updates)))
    (and params (plist-get (plist-get params :params) :update))))

(let* ((data-home (make-temp-file "yeah-mode" t))
       (build-workspace (make-temp-file "yeah-mode-build" t))
       (plan-workspace (make-temp-file "yeah-mode-plan" t))
       (name (format "yeah-mode-%d" (random 1000000)))
       (client nil)
       (questions nil)
       (updates nil))
  (unwind-protect
      (progn
        (yeah-acp-mode--start name data-home)
        (let ((connection (yeah-acp-client-connect (yeah-service-socket-path name))))
          (setq client (nth 0 connection)
                questions (nth 1 connection)
                updates (nth 2 connection)))
        (let ((answer (yeah-acp-client-request client "initialize"
                                               (list :protocolVersion 1))))
          (unless (plist-get answer :result)
            (push "the handshake was not answered" yeah-check--failures)))
        ;; 1. the modes of a new session
        (let* ((answer (yeah-acp-client-request
                        client "session/new"
                        (list :cwd build-workspace :mcpServers nil)))
               (result (plist-get answer :result))
               (modes (plist-get result :modes))
               (available (plist-get modes :availableModes)))
          (unless (equal "build" (plist-get modes :currentModeId))
            (push (format "the session did not publish the mode it is in: it published %S"
                          (plist-get modes :currentModeId))
                  yeah-check--failures))
          (unless (and (listp available)
                       (equal (sort (yeah-check--mode-ids available) #'string<)
                              '("build" "plan")))
            (push (format "the session did not publish the modes it may be in: %S"
                          available)
                  yeah-check--failures))
          ;; 2. the build mode asks the client and lets the tool run
          (let ((session-id (plist-get result :sessionId)))
            (let ((answer (yeah-acp-client-request
                           client "session/prompt"
                           (list :sessionId session-id
                                 :prompt (vector (list :type "text"
                                                       :text "write it"))))))
              (unless (plist-get answer :result)
                (push "the run of the session in the build mode did not finish"
                      yeah-check--failures)))
            (unless (= 1 (length (funcall questions)))
              (push (format "the client was asked %d times about the write in the build mode"
                            (length (funcall questions)))
                    yeah-check--failures))
            (unless (file-exists-p (expand-file-name "written.txt" build-workspace))
              (push "the session in the build mode did not write the file"
                    yeah-check--failures))))
        ;; 3. the plan mode decides without a question
        (let* ((answer (yeah-acp-client-request
                        client "session/new"
                        (list :cwd plan-workspace :mcpServers nil)))
               (session-id (plist-get (plist-get answer :result) :sessionId))
               (questions-before (length (funcall questions))))
          (let ((reply (yeah-acp-client-request
                        client "session/set_mode"
                        (list :sessionId session-id :modeId "plan"))))
            (when (plist-get reply :error)
              (push (format "the wire refused the mode of the session: %S"
                            (plist-get reply :error))
                    yeah-check--failures)))
          (let ((update (yeah-check--current-mode-update (funcall updates))))
            (unless (and update (equal "plan" (plist-get update :currentModeId)))
              (push (format "the client was not told about the new mode of the session: %S"
                            update)
                    yeah-check--failures)))
          (let ((answer (yeah-acp-client-request
                         client "session/prompt"
                         (list :sessionId session-id
                               :prompt (vector (list :type "text"
                                                     :text "write it"))))))
            (unless (plist-get answer :result)
              (push "the run of the session in the plan mode did not finish"
                    yeah-check--failures)))
          (unless (= questions-before (length (funcall questions)))
            (push "the client was asked about a permission in the plan mode"
                  yeah-check--failures))
          (unless (cl-find-if (lambda (update) (equal "write" (plist-get update :title)))
                               (yeah-acp-client-tool-calls (funcall updates)))
            (push "the session in the plan mode did not call the write tool"
                  yeah-check--failures))
          (when (file-exists-p (expand-file-name "written.txt" plan-workspace))
            (push "the session in the plan mode wrote the file although its mode forbids it"
                  yeah-check--failures)))
    (when client (ignore-errors (yeah-client-close client)))
    (ignore-errors (yeah-service-stop name))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory build-workspace t))
    (ignore-errors (delete-directory plan-workspace t)))
  (dolist (failure yeah-check--failures)
    (message "session-mode: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0))))

;;; check-a-session-changes-its-permission-profile-over-the-wire.el ends here
