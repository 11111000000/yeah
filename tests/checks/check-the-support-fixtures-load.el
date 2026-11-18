;;; check-the-support-fixtures-load.el --- the fixtures of the support load -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Every check of the project is written against the fixtures of the support:
;; a check that needs a model, a client or a journal takes it from
;; `tests/support'.  A fixture that does not load is a check that cannot
;; even start, and the failure of such a check says nothing about the
;; subject it was written for.
;;
;; This check loads every fixture of the support and names the ones that
;; refuse to load.  A fixture is loaded in a child Emacs, one child per
;; fixture: a fixture of the support is allowed to start a process, and a
;; child that is stopped gives this check a name and a reason instead of a
;; timeout of the whole check.  The child is stopped in every case, so the
;; check leaves no process behind.
;;
;; Three fixtures start a server and wait for ever: they are the subject of
;; the waves 55 to 58, and they are checked there, where the server is
;; killed on purpose.  Loading them here would wait for ever instead of
;; proving anything, so they are named here, their presence is checked, and
;; the rest of the support is left to them.
;;
;; Exit codes: 0 -- every fixture of the support loads and ends; 1 -- one of
;; them does not.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defconst yeah-check--servers
  '("yeah-check-server-fixture.el"
    "yeah-hanging-check-fixture.el"
    "yeah-pilot-fixture.el")
  "The fixtures that start a server and wait for ever.
They are the subject of the waves 55 to 58: the check of each wave starts
the server, kills it and proves that it is gone.")

(defconst yeah-check--limit 10
  "The seconds a fixture of the support may take to load.")

(defun yeah-check--root ()
  "Return the root of the project."
  (expand-file-name default-directory))

(defun yeah-check--emacs ()
  "Return the Emacs program that loads a fixture of the support."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (executable-find "emacs")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-check--support-files ()
  "Return the paths of the fixtures of the support."
  (sort (file-expand-wildcards (expand-file-name "tests/support/*.el" (yeah-check--root)))
        #'string<))

(defun yeah-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (< (float-time) deadline) (not (funcall predicate)))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-check--kill-group (pid signal)
  "Send SIGNAL to the group of the process PID.
The group is the one of the process that was started: Emacs gives every
child of `make-process' a group of its own.  Return non-nil when the
signal was sent."
  (let ((kill-bin (or (executable-find "kill") "/bin/kill")))
    (condition-case err
        (zerop (call-process kill-bin nil nil nil
                             (concat "-" signal) "--" (format "-%d" pid)))
      (error (message "support: the signal %s to the group %d was not sent: %S"
                      signal pid err)
             nil))))

(defun yeah-check--text (buffer)
  "Return the text of the BUFFER."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (buffer-substring-no-properties (point-min) (point-max)))))

(defun yeah-check--reason (text)
  "Return the first line of TEXT that says what went wrong."
  (let (reason)
    (dolist (line (split-string text "\n" t))
      (when (and (null reason)
                 (or (string-match-p "Error during evaluation" line)
                     (string-match-p "^Error:" line)
                     (string-match-p "End of file during parsing" line)))
        (setq reason (string-trim line))))
    (or reason (string-trim (or (car (split-string text "\n" t)) "")))))

(defun yeah-check--load (file)
  "Load FILE in a child Emacs and return what the child did.
The result is a cons: the outcome (`ok', `failed' or `hung') and the
output of the child.  The child is stopped when it does not end by
itself."
  (let* ((output (get-buffer-create " *yeah support*"))
         (process
          (make-process
           :name "yeah-support-load"
           :command (list (yeah-check--emacs) "-Q" "--batch"
                          "-L" (expand-file-name "lib" (yeah-check--root))
                          "-L" (yeah-check--root)
                          "-l" file)
           :connection-type 'pipe
           :noquery t
           :filter (lambda (_process chunk)
                     (with-current-buffer output
                       (goto-char (point-max))
                       (insert chunk))))))
    (unwind-protect
        (progn
          (yeah-check--await (lambda () (not (process-live-p process))) yeah-check--limit)
          (if (process-live-p process)
              (cons 'hung (yeah-check--text output))
            (cons (if (= 0 (process-exit-status process)) 'ok 'failed)
                  (yeah-check--text output))))
      (when (process-live-p process)
        (yeah-check--kill-group (process-id process) "TERM")
        (yeah-check--await (lambda () (not (process-live-p process))) 5)
        (when (process-live-p process)
          (yeah-check--kill-group (process-id process) "KILL"))))))

(let* ((files (yeah-check--support-files))
       (names (mapcar #'file-name-nondirectory files))
       (emacs (yeah-check--emacs)))
  (when (null emacs)
    (push "there is no Emacs to load the fixtures of the support with"
          yeah-check--failures))
  ;; the fixtures of the server are named here and checked there: this
  ;; check proves that they are there, not that they end
  (dolist (server yeah-check--servers)
    (unless (member server names)
      (push (format "the fixture %s of the server is gone" server)
            yeah-check--failures)))
  (when (null files)
    (push "there is no fixture of the support to load" yeah-check--failures))
  (when emacs
    (dolist (file files)
      (let ((name (file-name-nondirectory file)))
        (unless (member name yeah-check--servers)
          (let ((result (yeah-check--load file)))
            (pcase (car result)
              ('ok nil)
              ('failed
               (push (format "the fixture %s does not load: %s"
                             name (yeah-check--reason (cdr result)))
                     yeah-check--failures))
              ('hung
               (push (format "the fixture %s does not end: it was still loading after %d seconds"
                             name yeah-check--limit)
                     yeah-check--failures))
              (_
               (push (format "the fixture %s gave an answer nobody knows: %S"
                             name (car result))
                     yeah-check--failures))))))))
  (dolist (failure yeah-check--failures)
    (message "support: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-support-fixtures-load.el ends here
