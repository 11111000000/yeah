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

(defun yeah-check--transport (tool)
  "Return the source of a fake transport that asks for TOOL.
A read changes nothing, a write changes the world: the service asks the
client about the second and answers the first by itself."
  (format "(defun yeah-check--transport (prompt callback)
     (funcall callback
              (list 'tool-call
                    (list (list :name \"%s\")
                          (list \"/etc/hostname\")
                          (lambda (value) (funcall callback \"done\"))))))"
          tool))

(defun yeah-check--decisions (data-home)
  "Return the permission effects the service recorded, in journal order."
  (let (effects)
    (dolist (file (directory-files-recursively data-home "\\.jsonl\\'"))
      (dolist (line (split-string (with-temp-buffer
                                    (insert-file-contents file)
                                    (buffer-string))
                                  "\n" t))
        (when (string-match-p "\"type\":\"permission-decision\"" line)
          (push (plist-get (json-parse-string line :object-type 'plist)
                           :effect)
                effects))))
    (nreverse effects)))

(defun yeah-check--drive (client data-home)
  "Drive one tool call through CLIENT and return the service's decision."
  (let ((session-id nil))
    (yeah-client-request
     client "session/new"
     (list :cwd data-home :mcpServers nil)
     (lambda (result _error)
       (setq session-id (plist-get result :sessionId))))
    (let ((deadline (+ (float-time) 8)))
      (while (and (null session-id) (< (float-time) deadline))
        (accept-process-output nil 0.05)))
    (when session-id
      (yeah-client-request
       client "session/prompt"
       (list :sessionId session-id
             :prompt (vector (list :type "text" :text "read it")))
       (lambda (_result _error) nil)))
    (let ((deadline (+ (float-time) 8)))
      (while (and (null (yeah-check--decisions data-home))
                  (< (float-time) deadline))
        (accept-process-output nil 0.05)))
    (yeah-check--decisions data-home)))

(defun yeah-check--run (rules tool)
  "Start a service with RULES, drive one call of TOOL through it, and
return the permission decisions the service recorded."
  (let ((data-home (make-temp-file "yeah-service-perm" t))
        (name (format "perm-%d" (random 1000000)))
        (decision nil))
    (unwind-protect
        (progn
          (yeah-service-start name (yeah-check--transport tool) data-home
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
       ;; a tool that changes the world: the client is asked
       (without (yeah-check--run nil "write"))
       ;; the same tool with the permission granted
       (with-write (yeah-check--run (list (yeah-perm-rule-make "write" "*" 'allow))
                                   "write"))
       ;; a tool that only looks: nobody is asked, and the journal says why
       (safe-read (yeah-check--run nil "read")))
  (unless (and (member "defer" without)
               (not (member "allow" without)))
    (push (format "a service without permissions did not ask the client about the write: %S"
                  without)
          failures))
  (unless (and (member "allow" with-write)
               (not (member "defer" with-write)))
    (push (format "the granted permission did not reach the service: %S"
                  with-write)
          failures))
  (unless (and (member "allow" safe-read)
               (not (member "defer" safe-read)))
    (push (format "a safe read was asked about: %S" safe-read)
          failures))
  (dolist (failure failures)
    (message "service-perm: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-service-permissions.el ends here
