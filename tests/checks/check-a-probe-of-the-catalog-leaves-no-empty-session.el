;;; check-a-probe-of-the-catalog-leaves-no-empty-session.el --- a probe of the catalog leaves no session -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The defect: the orchestrator reads the catalog of the models and the modes
;; through a real session -- `discover()' in the route of the orchestrator
;; calls `session/new' and never closes the session it opened -- and every
;; such probe left a session file in the journal of the project.  The file
;; held nothing but its header, and the journal of a project filled with
;; them: hundreds of files that say nothing, in the place where a person
;; looks for the truth about a run.
;;
;; This check starts a real ACP service on a socket, opens a session the way
;; the orchestrator opens it (a probe: no prompt, no run) and proves three
;; things:
;;
;; 1. the probe leaves no file in the journal of the project -- the journal
;;    holds no session file at all;
;; 2. the session that did work leaves a journal whose first line is its
;;    header, and whose lines follow it in order;
;; 3. the session of this process loads without a file -- the kernel refuses
;;    only a session it knows nothing about.
;;
;; The model of the service is a fake (the model is a FAKE).
;;
;; The verdict is decided by construction: the control of the claim makes the
;; kernel write the file of a session when the session opens, and the check
;; then fails by its own assertion -- the probe left a file behind.
;;
;; Exit codes: 0 -- the probe of the catalog left nothing behind; 1 -- it did.

;;; Code:

(require 'cl-lib)
(require 'yeah-product)
(require 'yeah-session)

(load (expand-file-name "tests/support/yeah-acp-client.el") nil t)
(load (expand-file-name "tests/support/yeah-journal-files.el") nil t)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--model-source ()
  "Return the source of the fake model of the service."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "tests/support/yeah-session-model.el"))
    (buffer-string)))

(defun yeah-check--journal-path (data-home cwd session-id)
  "Return the path of the journal of SESSION-ID of the project at CWD.
DATA-HOME is the data home of the service; the journal of the project lives
under it."
  (let ((yeah-data-home data-home))
    (yeah-session--path-for session-id (yeah-product-session-root cwd))))

(defun yeah-check--lines-of (path)
  "Return the non-empty lines of the journal at PATH."
  (when (file-exists-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (split-string (buffer-string) "\n" t))))

(let* ((data-home (make-temp-file "yeah-probe" t))
       (workspace (make-temp-file "yeah-probe-work" t))
       (name (format "yeah-probe-%d" (random 1000000)))
       (client nil)
       (questions nil)
       (updates nil)
       (session-id nil))
  (unwind-protect
      (progn
        (yeah-service-start name (yeah-check--model-source) data-home
                            "#'yeah-session-model-transport" t nil)
        (let ((connection (yeah-acp-client-connect (yeah-service-socket-path name))))
          (setq client (nth 0 connection)
                questions (nth 1 connection)
                updates (nth 2 connection)))
        (let ((answer (yeah-acp-client-request client "initialize"
                                               (list :protocolVersion 1))))
          (unless (plist-get answer :result)
            (push "the handshake was not answered" yeah-check--failures)))
        ;; the probe of the catalog: a session that is opened and never used
        (let* ((answer (yeah-acp-client-request
                        client "session/new"
                        (list :cwd workspace :mcpServers (vector))))
               (result (plist-get answer :result)))
          (setq session-id (plist-get result :sessionId))
          (unless session-id
            (push (format "the probe of the catalog was not answered: %S" answer)
                  yeah-check--failures)))
        ;; 1. the probe left no file in the journal
        (let ((files (yeah-journal-files--files data-home)))
          (unless (null files)
            (push (format "the probe of the catalog left %d session file(s) in the journal: %S"
                          (length files) files)
                  yeah-check--failures)))
        ;; 3. the session of this process loads without a file, and a session
        ;;    the process knows nothing about is refused
        (when session-id
          (let* ((answer (yeah-acp-client-request
                          client "session/load"
                          (list :sessionId session-id
                                :cwd workspace
                                :mcpServers (vector))))
                 (result (plist-get answer :result)))
            (unless result
              (push (format "the session of this process was not loaded: %S" answer)
                    yeah-check--failures))
            (when result
              (unless (equal session-id (plist-get result :sessionId))
                (push (format "the load named another session: %S" result)
                      yeah-check--failures))
              (unless (equal 0 (plist-get result :replayed))
                (push (format "the load of a session without a file replayed %S record(s)"
                              (plist-get result :replayed))
                      yeah-check--failures)))
            ;; the load of a session without a file leaves no file behind
            (let ((files (yeah-journal-files--files data-home)))
              (unless (null files)
                (push (format "the load of a session without a file left %d session file(s) in the journal: %S"
                              (length files) files)
                      yeah-check--failures)))))
        (let ((answer (yeah-acp-client-request
                       client "session/load"
                       (list :sessionId "session-that-never-was"
                             :cwd workspace
                             :mcpServers (vector)))))
          (unless (plist-get answer :error)
            (push (format "a session the process knows nothing about was loaded: %S"
                          answer)
                  yeah-check--failures)))
        ;; 2. the session that did work leaves a journal that begins with its header
        (when session-id
          (yeah-acp-client-request
           client "session/prompt"
           (list :sessionId session-id
                 :prompt (vector (list :type "text" :text "say OK"))))
          (let* ((path (yeah-check--journal-path data-home workspace session-id))
                 (deadline (+ (float-time) 20)))
            (while (and (not (file-exists-p path))
                        (< (float-time) deadline))
              (accept-process-output nil 0.05))
            (let ((lines (yeah-check--lines-of path)))
              (unless lines
                (push (format "the run of the session left no journal: %s" path)
                      yeah-check--failures))
              (when lines
                (let ((header (condition-case nil
                                  (json-parse-string (nth 0 lines) :object-type 'plist)
                                (error nil))))
                  (unless (and header
                               (equal "header" (plist-get header :type))
                               (= 0 (plist-get header :id)))
                    (push (format "the journal of the session does not begin with its header: %S"
                                  (nth 0 lines))
                          yeah-check--failures)))
                (unless (> (length lines) 1)
                  (push (format "the journal of the session holds nothing but its header: %S"
                                lines)
                        yeah-check--failures)))))))
    (when client (ignore-errors (yeah-client-close client)))
    (ignore-errors (yeah-service-stop name))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory workspace t)))
  (dolist (failure yeah-check--failures)
    (message "probe-catalog: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-probe-of-the-catalog-leaves-no-empty-session.el ends here
