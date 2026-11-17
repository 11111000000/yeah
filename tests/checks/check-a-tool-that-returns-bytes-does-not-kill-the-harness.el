;;; check-a-tool-that-returns-bytes-does-not-kill-the-harness.el --- the harness lives -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; This check is the live defect of the harness, end to end and offline.
;; A `bash' tool of the agent runs a command that writes a byte that
;; cannot be a part of a UTF-8 character.  The bytes come back through the
;; sentinel of the process, and the journal writes them.
;;
;; Before the fix, the refusal of JSON arrived inside the sentinel, where
;; no handler of the turn stands, and the whole Emacs process died: the
;; run left no record of itself and the exit code was 255.
;;
;; The check runs a real Emacs process that does the real work: the tool
;; runs, the bytes come back, the journal is written, and the process
;; exits with the code 0.  The journal must hold the record of the tool,
;; with the broken byte standing as the replacement character.
;;
;; Exit codes: 0 — the harness lives and the journal holds the record;
;; 1 — the harness died or the record was lost.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-session)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defconst yeah-check--child-source
  ";;; -*- lexical-binding: t; no-byte-compile: t -*-
(require 'yeah-session)
(require 'yeah-process)
(let* ((root (or (getenv \"YEAH_CHILD_ROOT\") \"/tmp\"))
       (session (yeah-session-open \"child\" root)))
  (yeah-process-bash
   (list (or (getenv \"YEAH_CHILD_COMMAND\") \"true\") 30 root nil)
   (lambda (result)
     (yeah-session-append session (list :type \"tool-end\" :payload result))
     (princ \"CONTENT-MULTIBYTE=\")
     (princ (if (multibyte-string-p (plist-get result :content)) \"t\" \"nil\"))
     (terpri)
     (princ \"CHILD-OK\")
     (terpri))))
(let ((deadline (+ (float-time) 20)))
  (while (< (float-time) deadline)
    (accept-process-output nil 0.2)))
(kill-emacs 0)
"
  "The Elisp source of the child that runs the real path of the tool.")

(defun yeah-check--expect (ok message)
  "Record MESSAGE as a failure when OK is nil."
  (unless ok
    (push message yeah-check--failures)))

(defun yeah-check--emacs ()
  "Return the Emacs program to run the child."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-check--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (expand-file-name (file-name-directory (or (locate-library "yeah-session")
                                             "yeah-session.el"))))

(defun yeah-check--journal-path (root)
  "Return the path of the journal the child writes under ROOT."
  (expand-file-name "sessions/child.jsonl" root))

(let* ((root (make-temp-file "yeah-bytes-live" t))
       (script (expand-file-name "child.el" root))
       (chunks nil)
       (process nil)
       (command (concat "printf 'ok\\n'; printf '\\262'; printf ' tail\\n'")))
  (unwind-protect
      (progn
        (with-temp-file script
          (insert yeah-check--child-source))
        ;; The child needs the directory of the journal and the command that
        ;; writes the broken byte.  `make-process' takes the environment of
        ;; the process from the dynamic variable.
        (let ((process-environment
               (cons (format "YEAH_CHILD_ROOT=%s" root)
                     (cons (format "YEAH_CHILD_COMMAND=%s" command)
                           process-environment))))
          (setq process
                (make-process
                 :name "yeah-bytes-child"
                 :buffer nil
                 :command (list (yeah-check--emacs) "-Q" "--batch"
                                "-L" (yeah-check--lib-directory)
                                "-l" script)
                 :filter (lambda (_process chunk)
                           (push chunk chunks)))))
        (let ((deadline (+ (float-time) 60)))
          (while (and (process-live-p process)
                      (< (float-time) deadline))
            (accept-process-output nil 0.1)))
        (let ((output (apply #'concat (nreverse chunks)))
              (status (and process (process-exit-status process))))
          ;; 1. The harness lived.
          (yeah-check--expect
           (and status (= status 0))
           (format "the harness died: the exit code was %S" status))
          ;; 2. The tool answered, and its output is text.
          (yeah-check--expect
           (string-match-p "CONTENT-MULTIBYTE=t" output)
           "the output of the tool is not text that the journal can write")
          (yeah-check--expect
           (string-match-p "CHILD-OK" output)
           "the harness did not finish the work of the tool"))
        ;; 3. The journal holds the record of the tool.
        (let ((path (yeah-check--journal-path root)))
          (yeah-check--expect
           (file-exists-p path)
           "the journal holds no record of the run")
          (when (file-exists-p path)
            (with-temp-buffer
              (insert-file-contents path)
              (let* ((text (buffer-string))
                     (records (delq nil
                                    (mapcar (lambda (line)
                                              (condition-case nil
                                                  (json-parse-string line
                                                                    :object-type 'plist
                                                                    :array-type 'list)
                                                (error nil)))
                                            (split-string text "\n" t))))
                     (tool-end (cl-find-if
                                (lambda (record)
                                  (equal "tool-end" (plist-get record :type)))
                                records)))
                (yeah-check--expect
                 (and tool-end
                      (not (plist-get tool-end :unserializable)))
                 "the journal holds no record of the tool")
                (yeah-check--expect
                 (and (string-match-p (char-to-string 65533) text)
                      (string-match-p
                       (char-to-string 65533)
                       (plist-get (plist-get tool-end :payload) :content)))
                 "the broken byte did not become the replacement character"))))))
    (when (process-live-p process)
      (ignore-errors (kill-process process)))
    (ignore-errors (delete-directory root t t))
    (dolist (failure yeah-check--failures)
      (message "bytes-live: %s" failure))
    (if yeah-check--failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-a-tool-that-returns-bytes-does-not-kill-the-harness.el ends here
