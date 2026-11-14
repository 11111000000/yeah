;;; check-bridge-keeps-the-answer.el --- the bridge does not lose the answer -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The bridge collects what the attached Emacs printed with a process
;; filter.  A process can exit before its last chunk reaches the filter:
;; the answer was then lost and the bridge reported success with an empty
;; output — the person saw an empty buffer that the server had never
;; emptied.  This check reads the same live buffer many times through the
;; bridge and requires that no answer is ever empty.

;;; Code:

(require 'cl-lib)
(require 'yeah-bridge)

(defvar yeah-check--emacs
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS"))
           (getenv "EMACS"))
      (executable-find "emacs")
      (expand-file-name "~/.nix-profile/bin/emacs"))
  "The Emacs program that runs the server.")

(defvar yeah-check--emacsclient
  (let* ((dir (file-name-directory yeah-check--emacs))
         (candidate (expand-file-name "emacsclient" dir)))
    (or (and (file-executable-p candidate) candidate)
        (executable-find "emacsclient")
        candidate))
  "The emacsclient program that reaches the server.")

(defvar yeah-check--reads 120
  "How many times the check reads the buffer through the bridge.
Losing an answer is a race between the exit of the child process and the
delivery of its last chunk, so it shows up under load: the check keeps a
thread spinning to make the parent late, and reads often enough that the
loss is certain without the fix.")

(defvar yeah-check--load-thread nil
  "The thread that keeps the parent late, so the race can happen.")

(let ((failures nil)
      (name (format "yeah-bridge-keep-%d" (random 1000000)))
      (empty 0))
  (unwind-protect
      (progn
        (make-process
         :name "yeah-bridge-keep-server"
         :command (list yeah-check--emacs
                        (concat "--daemon=" name)
                        "--eval"
                        "(with-current-buffer (get-buffer-create \"*yeah-live*\") (insert \"live text\"))")
         :connection-type 'pipe
         :noquery t)
        ;; wait for the server
        (let ((deadline (+ (float-time) 15)))
          (while (and (< (float-time) deadline)
                      (not (zerop (with-temp-buffer
                                    (call-process yeah-check--emacsclient nil t nil
                                                  "-s" name "--eval" "t")))))
            (accept-process-output nil 0.1)))
        ;; a spinning thread makes the parent slow, which is when the
        ;; answer of the child is lost
        (setq yeah-check--load-thread
              (make-thread
               (lambda ()
                 (let ((counter 0))
                   (while (< counter 100000000)
                     (setq counter (1+ counter)))))))
        (dotimes (_ yeah-check--reads)
          (let ((text (condition-case err
                         (let ((yeah-bridge-program yeah-check--emacsclient)
                               (yeah-bridge-server name))
                           (yeah-bridge-buffer-read "*yeah-live*"))
                       (error (format "ERROR: %S" err)))))
            (when (or (null text) (equal text ""))
              (setq empty (1+ empty)))))
        (when (> empty 0)
          (push (format "the bridge lost the answer %d times out of %d"
                        empty yeah-check--reads)
                failures)))
    (when yeah-check--load-thread
      (ignore-errors (thread-signal yeah-check--load-thread 'quit)))
    (ignore-errors
      (with-temp-buffer
        (call-process yeah-check--emacsclient nil t nil "-s" name "--eval" "(kill-emacs)"))))
    (dolist (failure failures)
      (message "bridge-keep: %s" failure))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-bridge-keeps-the-answer.el ends here
