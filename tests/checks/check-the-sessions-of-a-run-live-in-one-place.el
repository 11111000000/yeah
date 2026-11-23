;;; check-the-sessions-of-a-run-live-in-one-place.el --- the sessions live under the data home once -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The wart: the data home of Yeah IS the directory of Yeah -- it holds
;; `projects/', `Trash/' and `exports/' -- but the sessions of a project were
;; placed in `yeah/projects/<hash>/' relative to it.  The path of a session is
;; what a report names, and the doubled segment misleads the reader: the
;; sessions lay in `~/.local/share/yeah/yeah/projects/...'.
;;
;; The check measures three things:
;;
;; 1. the session root of a project lies under the data home, and the path
;;    from the data home to it holds the hash in the segment right after
;;    `projects' -- one segment, not two;
;; 2. no segment of the path of the session root is named `yeah' twice: the
;;    data home is the directory of Yeah, and the session root is under it;
;; 3. a real run writes its journal under that root -- the path of the
;;    journal of the session is the path the kernel says it is.
;;
;; The model of the service is a fake (the model is a FAKE).
;;
;; The verdict is decided by construction: the control of the claim restores
;; the doubled segment, and the check then fails by its own assertion -- the
;; session root of the project is not under `projects/' any more.
;;
;; Exit codes: 0 -- the sessions live in one place; 1 -- they do not.

;;; Code:

(require 'cl-lib)
(require 'yeah-product)
(require 'yeah-session)

(load (expand-file-name "tests/support/yeah-acp-client.el") nil t)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defun yeah-check--model-source ()
  "Return the source of the fake model of the service."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "tests/support/yeah-session-model.el"))
    (buffer-string)))

(defun yeah-check--relative (file directory)
  "Return FILE relative to DIRECTORY, or nil when it is not under it."
  (let ((file (expand-file-name file))
        (directory (expand-file-name directory)))
    (when (string-prefix-p (concat (file-name-as-directory directory)) file)
      (substring file (length (file-name-as-directory directory))))))

(let* ((data-home (make-temp-file "yeah-place" t))
       (workspace (make-temp-file "yeah-place-work" t))
       (name (format "yeah-place-%d" (random 1000000)))
       (client nil)
       (session-id nil))
  (unwind-protect
      (progn
        ;; 1 and 2: the shape of the path of the session root
        (let* ((root (let ((yeah-data-home data-home))
                         (yeah-product-session-root workspace)))
               (relative (yeah-check--relative root data-home)))
          (unless relative
            (push (format "the session root is not under the data home: %s (the data home is %s)"
                          root data-home)
                  yeah-check--failures))
          (when relative
            (let ((segments (split-string (directory-file-name relative) "/")))
              (unless (and (= 2 (length segments))
                           (equal "projects" (nth 0 segments))
                           (string-match-p "\\`[0-9a-f]\\{64\\}\\'" (nth 1 segments)))
                (push (format "the session root is not `projects/<hash>/' of the data home: %s"
                              relative)
                      yeah-check--failures))
              (when (member "yeah" segments)
                (push (format "the path of the session root carries a doubled segment: %s"
                              relative)
                      yeah-check--failures)))))
        ;; 3: a real run writes its journal under that root
        (yeah-service-start name (yeah-check--model-source) data-home
                            "#'yeah-session-model-transport" t nil)
        (let ((connection (yeah-acp-client-connect (yeah-service-socket-path name))))
          (setq client (nth 0 connection)))
        (let* ((answer (yeah-acp-client-request client "initialize"
                                               (list :protocolVersion 1)))
               (opened (yeah-acp-client-request
                        client "session/new"
                        (list :cwd workspace :mcpServers (vector))))
               (result (plist-get opened :result)))
          (unless (plist-get answer :result)
            (push "the handshake was not answered" yeah-check--failures))
          (setq session-id (plist-get result :sessionId))
          (unless session-id
            (push (format "the session was not opened: %S" opened) yeah-check--failures)))
        (when session-id
          (yeah-acp-client-request
           client "session/prompt"
           (list :sessionId session-id
                 :prompt (vector (list :type "text" :text "say OK"))))
          (let* ((path (let ((yeah-data-home data-home))
                          (yeah-session--path-for session-id
                                                  (yeah-product-session-root workspace))))
                 (deadline (+ (float-time) 20)))
            (while (and (not (file-exists-p path))
                        (< (float-time) deadline))
              (accept-process-output nil 0.05))
            (unless (file-exists-p path)
              (push (format "the run of the session left no journal: %s" path)
                    yeah-check--failures))
            (when (file-exists-p path)
              (let ((relative (yeah-check--relative path data-home)))
                (unless (and relative
                             (string-prefix-p "projects/" relative))
                  (push (format "the journal of the session is not under `projects/' of the data home: %s"
                                path)
                        yeah-check--failures)))))))
    (when client (ignore-errors (yeah-client-close client)))
    (ignore-errors (yeah-service-stop name))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory workspace t)))
  (dolist (failure yeah-check--failures)
    (message "sessions-place: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-sessions-of-a-run-live-in-one-place.el ends here
