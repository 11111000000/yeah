;;; check-the-journal-holds-the-usage-of-a-request-once.el --- the journal holds the usage of a request once -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The defect: a model that thinks was paid twice in the journal.  The
;; transport of gptel hands the info of a request to every shape of it: the
;; reasoning of the model and the answer that follows it carry the same
;; tokens, and the kernel wrote the usage of the request for each of them.
;; The journal of the live run of 19 November 2026 held two records of the
;; usage of one request with the same numbers, and the cost of the run that
;; the orchestrator would show was twice the cost of the run.
;;
;; This check starts a real ACP service on a socket, drives a prompt whose
;; model thinks before it answers, and proves three things:
;;
;; 1. the journal of the session holds one record of the usage of the request
;;    and not two;
;; 2. the record holds the tokens the provider reported;
;; 3. the answer to the prompt carries those tokens once: the orchestrator
;;    counts what the kernel reports, and a doubled number is a wrong bill.
;;
;; The model here is a FAKE (the model is a FAKE): it thinks, and then it
;; ends the run with the `finish' tool, and both shapes carry the same info.
;;
;; Exit codes: 0 -- the journal holds the usage of the request once; 1 -- it
;; does not.

;;; Code:

(require 'cl-lib)
(require 'yeah-product)
(require 'yeah-session)

(load (expand-file-name "tests/support/yeah-acp-client.el") nil t)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--model-source ()
  "Return the source of the fake model of the check."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "tests/support/yeah-session-usage-model.el"))
    (buffer-string)))

(defun yeah-check--journal-path (data-home cwd session-id)
  "Return the path of the journal of SESSION-ID of the project at CWD."
  (let ((yeah-data-home data-home))
    (yeah-session--path-for session-id (yeah-product-session-root cwd))))

(defun yeah-check--records (path)
  "Return the records of the journal at PATH."
  (when (file-exists-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (let ((records nil))
        (dolist (line (split-string (buffer-string) "\n" t))
          (let ((record (condition-case nil
                            (json-parse-string line :object-type 'plist)
                          (error nil))))
            (when record
              (push record records))))
        (nreverse records)))))

(let* ((data-home (make-temp-file "yeah-usage-once" t))
       (workspace (make-temp-file "yeah-usage-once-work" t))
       (name (format "yeah-usage-once-%d" (random 1000000)))
       (client nil)
       (session-id nil)
       (answer nil))
  (unwind-protect
      (progn
        (yeah-service-start name (yeah-check--model-source) data-home
                            "#'yeah-session-usage-model-transport" t nil)
        (let ((connection (yeah-acp-client-connect (yeah-service-socket-path name))))
          (setq client (nth 0 connection)))
        (yeah-acp-client-request client "initialize" (list :protocolVersion 1))
        (let* ((answer (yeah-acp-client-request
                        client "session/new"
                        (list :cwd workspace :mcpServers (vector))))
               (result (plist-get answer :result)))
          (setq session-id (plist-get result :sessionId))
          (unless session-id
            (push (format "the session was not opened: %S" answer) yeah-check--failures)))
        (when session-id
          (setq answer
                (yeah-acp-client-request
                 client "session/prompt"
                 (list :sessionId session-id
                       :prompt (vector (list :type "text"
                                              :text "do the thing, thinking, spend 1200"))))
                ))
          ;; 1 and 2: the journal holds the usage of the request once.
          (let* ((path (yeah-check--journal-path data-home workspace session-id))
                 (deadline (+ (float-time) 20)))
            (while (and (not (file-exists-p path))
                        (< (float-time) deadline))
              (accept-process-output nil 0.05))
            (let* ((records (yeah-check--records path))
                   (usages (delq nil
                                 (mapcar (lambda (record)
                                           (when (equal "usage" (plist-get record :type))
                                             record))
                                         records))))
              (unless usages
                (push (format "the journal of the session holds no record of the usage: %s" path)
                      yeah-check--failures))
              (unless (= 1 (length usages))
                (push (format "the journal holds %d record(s) of the usage of one request: the tokens of the request were written twice"
                              (length usages))
                      yeah-check--failures))
              (when (and (= 1 (length usages))
                         (not (equal 1200 (plist-get (car usages) :input))))
                (push (format "the record of the usage holds the wrong input tokens: %S is not 1200"
                              (plist-get (car usages) :input))
                      yeah-check--failures))))
          ;; 3: the answer carries the tokens of the request once.
          (let ((usage (plist-get (plist-get answer :result) :usage)))
            (unless usage
              (push "the answer to the prompt carried no usage" yeah-check--failures))
            (when usage
              (unless (equal 1200 (plist-get usage :inputTokens))
                (push (format "the answer carried the wrong input tokens: %S is not 1200"
                              (plist-get usage :inputTokens))
                      yeah-check--failures))
              (unless (equal 34 (plist-get usage :outputTokens))
                (push (format "the answer carried the wrong output tokens: %S is not 34"
                              (plist-get usage :outputTokens))
                      yeah-check--failures))))))
    (when client (ignore-errors (yeah-client-close client)))
    (ignore-errors (yeah-service-stop name))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory workspace t)))
  (dolist (failure yeah-check--failures)
    (message "usage-once: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-journal-holds-the-usage-of-a-request-once.el ends here
