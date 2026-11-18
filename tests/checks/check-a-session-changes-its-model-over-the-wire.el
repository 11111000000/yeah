;;; check-a-session-changes-its-model-over-the-wire.el --- the model of a session changes over the wire -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The defect: the model of a session could not be changed over the wire.
;; Neither `session/set_model' nor `session/set_config_option' existed, so a
;; client that asked was answered with `-32601', and the client of Paseo had
;; no model to show and no model to change: the model of the service was
;; chosen when the process started, and nothing else could be chosen.
;;
;; This check starts a real ACP service on a socket, opens a session, and
;; proves five things on the wire:
;;
;; 1. `session/new' publishes the configuration options of the session, and
;;    the option of the model names every model the session may run on and
;;    the one it runs on now;
;; 2. `session/set_config_option' is answered, and not with an error, and
;;    the answer names the model the session runs on now;
;; 3. the client is told about the new model of the session;
;; 4. the run of the session goes to the model the client chose: the model
;;    of the service writes down the model it runs on, and the file it
;;    writes lands in the directory of the session;
;; 5. a session that is opened again keeps the model it was left in, and a
;;    model that no session may run on is refused.
;;
;; The verdict is decided by construction: the model of the session is bound
;; around the call of the transport, and the control of the claim takes that
;; binding out -- the model of the session is nowhere -- and the check then
;; fails by its own assertion.
;;
;; No network is involved: the model of the service is a fake that writes
;; down the model it runs on (tests/support/yeah-session-model.el).
;;
;; Exit codes: 0 -- the model of the session changed over the wire and the
;; run went to that model; 1 -- it did not.

;;; Code:

(require 'cl-lib)

(load (expand-file-name "tests/support/yeah-acp-model.el") nil t)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--model-option (options)
  "Return the option of the model among the configuration OPTIONS."
  (cl-find-if (lambda (option) (equal "model" (plist-get option :category)))
              options))

(defun yeah-check--option-values (option)
  "Return the values the model OPTION offers."
  (mapcar (lambda (value) (plist-get value :value))
          (plist-get option :options)))

(defun yeah-check--written-model (workspace)
  "Return the model the run of the session wrote down in WORKSPACE."
  (let ((file (expand-file-name "model-used.txt" workspace)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (string-trim (buffer-string))))))

(let* ((data-home (make-temp-file "yeah-model" t))
       (workspace (make-temp-file "yeah-model-work" t))
       (name (format "yeah-model-%d" (random 1000000)))
       (client nil)
       (questions nil)
       (updates nil))
  (unwind-protect
      (progn
        (yeah-acp-model--start name data-home)
        (let ((connection (yeah-acp-client-connect (yeah-service-socket-path name))))
          (setq client (nth 0 connection)
                questions (nth 1 connection)
                updates (nth 2 connection)))
        (let ((answer (yeah-acp-client-request client "initialize"
                                               (list :protocolVersion 1))))
          (unless (plist-get answer :result)
            (push "the handshake was not answered" yeah-check--failures)))
        ;; 1. the configuration options of a new session
        (let* ((answer (yeah-acp-client-request
                        client "session/new"
                        (list :cwd workspace :mcpServers nil)))
               (result (plist-get answer :result))
               (options (plist-get result :configOptions))
               (option (yeah-check--model-option options)))
          (unless (stringp (plist-get result :sessionId))
            (push "the session was not answered with a session id" yeah-check--failures))
          (unless option
            (push (format "the session did not publish the option of the model: %S"
                          options)
                  yeah-check--failures))
          (when option
            (unless (equal "model-a" (plist-get option :currentValue))
              (push (format "the session did not publish the model it runs on: %S"
                            (plist-get option :currentValue))
                    yeah-check--failures))
            (unless (equal '("model-a" "model-b")
                            (yeah-check--option-values option))
              (push (format "the session did not publish the models it may run on: %S"
                            (yeah-check--option-values option))
                    yeah-check--failures)))
          ;; 2. the model of the session changes
          (let* ((session-id (plist-get result :sessionId))
                 (reply (yeah-acp-client-request
                         client "session/set_config_option"
                         (list :sessionId session-id
                               :configId "model"
                               :value "model-b")))
                 (options (plist-get (plist-get reply :result) :configOptions))
                 (option (yeah-check--model-option options)))
            (when (plist-get reply :error)
              (push (format "the wire refused the model of the session: %S"
                            (plist-get reply :error))
                    yeah-check--failures))
            (unless (and option (equal "model-b" (plist-get option :currentValue)))
              (push (format "the wire did not answer with the new model of the session: %S"
                            options)
                    yeah-check--failures))
            ;; 3. the client is told about the new model
            (let ((update (yeah-acp-client-update-of (funcall updates)
                                                      "config_option_update")))
              (unless update
                (push "the client was not told about the new model of the session"
                      yeah-check--failures)))
            ;; 4. the run of the session goes to the model the client chose
            (let ((answer (yeah-acp-client-request
                           client "session/prompt"
                           (list :sessionId session-id
                                 :prompt (vector (list :type "text"
                                                       :text "write the model down"))))))
              (unless (plist-get answer :result)
                (push "the run of the session did not finish" yeah-check--failures)))
            (let ((model (yeah-check--written-model workspace)))
              (unless (equal "model-b" model)
                (push (format "the run of the session did not go to the model of the session: it went to %S"
                              model)
                      yeah-check--failures)))
            ;; 5. a session that is opened again keeps its model
            (let* ((answer (yeah-acp-client-request
                            client "session/load"
                            (list :cwd workspace :sessionId session-id)))
                   (options (plist-get (plist-get answer :result) :configOptions))
                   (option (yeah-check--model-option options)))
              (unless (and option (equal "model-b" (plist-get option :currentValue)))
                (push (format "the session that was opened again did not keep its model: %S"
                              options)
                      yeah-check--failures)))
            ;; a model that no session may run on is refused
            (let ((reply (yeah-acp-client-request
                          client "session/set_config_option"
                          (list :sessionId session-id
                                :configId "model"
                                :value "model-c"))))
              (unless (plist-get reply :error)
                (push "the wire accepted a model that no session may run on"
                      yeah-check--failures))))))
    (when client (ignore-errors (yeah-client-close client)))
    (ignore-errors (yeah-service-stop name))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory workspace t)))
  (dolist (failure yeah-check--failures)
    (message "session-model: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0))))

;;; check-a-session-changes-its-model-over-the-wire.el ends here
