;;; check-the-server-does-not-spin-when-the-provider-is-silent.el --- a silent server costs nothing -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A server that waits for an answer of a provider that will not come must
;; wait, and waiting is not working.  The defect of 2026-11-16 was a server
;; that burned half a core in a tight loop of userspace while its provider
;; was silent: the process was measured with 1 921 354 involuntary context
;; switches and six voluntary ones, and it never slept.
;;
;; The bound of the claim is one per cent of a core over ten seconds, and
;; the check measures the subject the way the defect itself was measured:
;; the ticks of the stat file of the process, not the percentage of the
;; CPU that `top' prints.
;;
;; The control of the claim brings the busy loop back -- the pump of the
;; wire stops waiting -- and the measured ticks must then exceed the bound.
;; The check fails by its own assertion and not by a crash.
;;
;; The ticks are read by the reader of the kernel
;; (lib/yeah-proc.el), and the reader decides: a server that is
;; gone has no ticks, and that is not the number zero.  A check that read
;; the ticks of a server that is gone as zero would prove nothing, so the
;; check names the server that is not running and fails by that name.

;;; Code:

(require 'json)
(require 'seq)

;; The reader of the ticks of a process is the one of the kernel: the
;; process of the server may die while the check reads it, and a reader
;; that dies on the filesystem does not decide on its own assertion.
(require 'yeah-proc)

(defvar yeah-check--emacs
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS"))
           (getenv "EMACS"))
      (executable-find "emacs")
      (expand-file-name "~/.nix-profile/bin/emacs"))
  "The Emacs program that runs the server of the check.")

(defvar yeah-check--root
  (or (locate-dominating-file (or load-file-name buffer-file-name default-directory)
                              "spec.json")
      (expand-file-name "../.."
                        (or (file-name-directory (or load-file-name default-directory))
                            default-directory)))
  "The root of the repository: the directory that holds `spec.json'.")

(defvar yeah-check--server nil
  "The process of the server the check measures.")

(defvar yeah-check--written ""
  "What the server wrote on its standard output so far.")

(defvar yeah-check--window 10
  "Seconds the check measures the server over.")

(defvar yeah-check--bound-percent 1
  "Per cent of a core the server may cost over the window of the check.")

(defun yeah-check--clock-ticks ()
  "Return the number of the clock ticks of the kernel in one second.
The kernel counts the time of a process in those ticks, and the bound of
the claim is a share of a core."
  (let ((answer (and (executable-find "getconf")
                     (with-temp-buffer
                       (condition-case nil
                           (progn (call-process "getconf" nil t nil "CLK_TCK")
                                  (string-trim (buffer-string)))
                         (error nil))))))
    (if (and answer (string-match-p "^[0-9]+$" answer))
        (string-to-number answer)
      100)))

(defun yeah-check--start-server (data-home)
  "Start the ACP server in its own Emacs process and return that process.
The provider of the server is a transport that never answers: the request
of the model goes out and nothing comes back."
  (setq yeah-check--written "")
  (setq yeah-check--server
        (make-process
         :name "yeah-acp-silent-server"
         :command (list yeah-check--emacs "-Q" "--batch"
                        "-L" (expand-file-name "lib" yeah-check--root)
                        "--eval"
                        (format "(progn (setq yeah-data-home %S) (require 'yeah-acp) (defun yeah-check--silent-transport (prompt callback) nil) (setq yeah-acp-default-transport #'yeah-check--silent-transport) (yeah-acp-serve))"
                                data-home))
         :connection-type 'pipe
         :noquery t
         :coding '(utf-8 . utf-8)
         :filter (lambda (_process chunk)
                   (setq yeah-check--written (concat yeah-check--written chunk))))))

(defun yeah-check--send (object)
  "Send OBJECT as one JSON line to the server."
  (process-send-string yeah-check--server (concat (json-serialize object) "\n")))

(defun yeah-check--messages ()
  "Return the complete messages the server wrote so far."
  (let (messages)
    (when (string-suffix-p "\n" yeah-check--written)
      (dolist (line (split-string yeah-check--written "\n" t))
        (unless (string-empty-p line)
          (push (json-parse-string line :object-type 'plist :array-type 'list)
                messages))))
    (nreverse messages)))

(defun yeah-check--await (id &optional timeout)
  "Return the response of the server to the request with ID, or nil."
  (let ((deadline (+ (float-time) (or timeout 5)))
        (answer nil))
    (while (and (null answer) (< (float-time) deadline))
      (accept-process-output yeah-check--server 0.05)
      (dolist (message (yeah-check--messages))
        (when (and (equal (plist-get message :id) id)
                   (not (plist-get message :method)))
          (setq answer message))))
    answer))

(let* ((home (make-temp-file "yeah-acp-spin" t))
       (data-home (expand-file-name "data" home))
       (failures nil))
  (make-directory data-home t)
  (unwind-protect
      (progn
        (yeah-check--start-server data-home)
        (yeah-check--send
         (list :jsonrpc "2.0" :id 1 :method "initialize"
               :params (list :protocolVersion 1)))
        (unless (yeah-check--await 1)
          (push "the server did not answer the handshake" failures))
        (yeah-check--send
         (list :jsonrpc "2.0" :id 2 :method "session/new"
               :params (list :cwd home :mcpServers nil)))
        (let* ((answer (yeah-check--await 2))
               (session-id (plist-get (plist-get answer :result) :sessionId)))
          (unless (stringp session-id)
            (push "the server did not create a session" failures))
          (when session-id
            ;; the request goes out and no answer comes: the server waits
            (yeah-check--send
             (list :jsonrpc "2.0" :id 3 :method "session/prompt"
                   :params (list :sessionId session-id
                                 :prompt (vector (list :type "text" :text "hi")))))
            ;; the turn starts and the provider keeps silent
            (sleep-for 2)
            (let* ((clock (yeah-check--clock-ticks))
                   (pid (process-id yeah-check--server))
                   (before (yeah-proc--ticks pid))
                   (wall (+ (float-time) yeah-check--window)))
              (if (null before)
                  ;; the server is gone: it has no ticks, and the ticks of a
                  ;; server that is not there are not zero -- they are
                  ;; nothing to measure, and the claim is not shown
                  (push "the server of the check is not running: it has no ticks to measure"
                        failures)
                (progn
                  (while (< (float-time) wall)
                    (accept-process-output yeah-check--server 0.05)
                    (sleep-for 0.05))
                  (let* ((after (yeah-proc--ticks pid))
                         (bound (/ (* yeah-check--window yeah-check--bound-percent) 100.0)))
                    (cond
                     ((null after)
                      (push "the server of the check is not running: it is gone before the window of the check ended"
                            failures))
                     ((> (/ (- after before) clock) bound)
                      (push (format "the silent server spun: it cost %.3f seconds of CPU in %d seconds, the bound is %.3f"
                                    (/ (- after before) clock) yeah-check--window bound)
                            failures))))))))))
    (when (and yeah-check--server (process-live-p yeah-check--server))
      (ignore-errors (kill-process yeah-check--server)))
    (ignore-errors (delete-directory home t)))
  (dolist (failure failures)
    (message "server-spin: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-server-does-not-spin-when-the-provider-is-silent.el ends here
