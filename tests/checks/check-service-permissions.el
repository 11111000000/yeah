;;; check-service-permissions.el --- the standing permissions reach the service -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A headless service cannot ask the person for permission, so the tools it
;; may use without asking are the standing permissions the person grants
;; when the service starts; what the rules do not name is asked of the
;; client over the wire (session/request_permission).  This check starts
;; two services with the same fake model — one without permissions and one
;; with `read' granted — and compares the permission decision the service
;; wrote into its journal: without rules the decision is to defer to the
;; client, with the rule it is to allow without asking.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-service)
(require 'yeah-client)
(require 'yeah-perm)

(defconst yeah-check--transport
  "(defun yeah-check--transport (prompt callback)
     (funcall callback
              (list 'tool-call
                    (list (list :name \"read\")
                          (list \"/etc/hostname\")
                          (lambda (value) (funcall callback \"done\"))))))"
  "The fake transport of the service: it asks for one read.")

(defun yeah-check--decision (data-home)
  "Return the effect the service recorded for its permission request."
  (let ((effect nil))
    (dolist (file (directory-files-recursively data-home "\\.jsonl\\'"))
      (dolist (line (split-string (with-temp-buffer
                                    (insert-file-contents file)
                                    (buffer-string))
                                  "\n" t))
        (when (string-match-p "\"type\":\"permission-decision\"" line)
          (setq effect (plist-get (json-parse-string line :object-type 'plist)
                                  :effect)))))
    effect))

(defun yeah-check--drive (client data-home)
  "Drive one tool call through CLIENT and return the service's decision."
  (let ((session-id nil))
    (yeah-client-request
     client "session/new"
     (list :cwd data-home :mcpServers nil)
     (lambda (result _error)
       (setq session-id (plist-get result :sessionId))))
    (let ((deadline (+ (float-time) 15)))
      (while (and (null session-id) (< (float-time) deadline))
        (accept-process-output nil 0.05)))
    (when session-id
      (yeah-client-request
       client "session/prompt"
       (list :sessionId session-id
             :prompt (vector (list :type "text" :text "read it")))
       (lambda (_result _error) nil)))
    (let ((deadline (+ (float-time) 15)))
      (while (and (null (yeah-check--decision data-home))
                  (< (float-time) deadline))
        (accept-process-output nil 0.05)))
    (yeah-check--decision data-home)))

(defun yeah-check--run (rules)
  "Start a service with RULES, drive one tool call through it, and return
the permission decision the service recorded."
  (let ((data-home (make-temp-file "yeah-service-perm" t))
        (name (format "perm-%d" (random 1000000)))
        (decision nil))
    (unwind-protect
        (progn
          (yeah-service-start name yeah-check--transport data-home
                             "#'yeah-check--transport" t rules)
          (let ((client
                 (condition-case err
                     (yeah-client-connect
                      (yeah-service-socket-path name))
                   (error (message "service-perm: the service did not start: %S"
                                   err)
                          nil))))
            (when client
              (setq decision (yeah-check--drive client data-home))
              (yeah-client-close client))
            (unless client
              (when-let ((process (gethash name yeah-service--processes)))
                (when-let ((buffer (process-buffer process)))
                  (with-current-buffer buffer
                    (message "service-perm: the service said:\n%s"
                             (buffer-string))))))))
      (yeah-service-stop name)
      (ignore-errors (delete-directory data-home t)))
    decision))

(let* ((failures nil)
       (without (yeah-check--run nil))
       (with-read (yeah-check--run (list (yeah-perm-rule-make "read" "*" 'allow)))))
  (unless (equal without "defer")
    (push (format "a service without permissions did not ask the client: %S"
                  without)
          failures))
  (unless (equal with-read "allow")
    (push (format "the granted permission did not reach the service: %S"
                  with-read)
          failures))
  (dolist (failure failures)
    (message "service-perm: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-service-permissions.el ends here
