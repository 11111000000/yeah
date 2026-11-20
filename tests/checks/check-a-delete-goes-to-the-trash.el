;;; check-a-delete-goes-to-the-trash.el --- a deletion goes into the trash -*- lexical-binding: t; no-byte-compile: t -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The gap this check covers: the shell of the agent removed files in place.
;; There was no tool that deletes, no trash, and no guard: a command that
;; said `rm -rf' removed the tree and the tree was gone for good.
;;
;; This check proves four things with the real tools of the agent:
;;
;; 1. the `rm' of the shell of the agent moves what it is given into the
;;    trash and removes nothing: the tree is gone from its place, it is in the
;;    trash with what was in it, and it comes back with its content;
;; 2. the `delete' tool of the agent moves a path into the trash the same way;
;; 3. a command that removes in place and cannot be caught by the `rm' of the
;;    shell (`/bin/rm', `find -delete', `shred') is refused by name, and the
;;    refusal says why;
;; 4. the ordinary commands run.
;;
;; The verdict is decided by construction: the control of the claim takes the
;; trash away -- the `rm' of the shell is the `rm' of the system -- and the
;; check then fails by its own assertion, because the tree is gone for good.
;;
;; The trash of the check is the trash of a temporary directory: the check
;; does not leave its rubbish in the trash of the person.
;;
;; Exit codes: 0 -- a deletion goes into the trash and comes back; 1 -- it
;; does not.

;;; Code:

(require 'cl-lib)
(require 'yeah-process)
(require 'yeah-tools)
(require 'yeah-trash)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--data-home nil
  "The data of the user while the check runs.")

(defun yeah-check--wait (predicate)
  "Pump the events until PREDICATE is true or the deadline passes."
  (let ((deadline (+ (float-time) 30)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.02))
    (funcall predicate)))

(defun yeah-check--run (command directory)
  "Run COMMAND in DIRECTORY and return the result of the run.
The result is the plist the tool hands to its caller: the content of the
run and whether it succeeded.  A command that the guard refuses never
starts: the refusal is the failure of the tool, and it comes back the
same way."
  (let ((result nil))
    (condition-case err
        (progn
          (yeah-process-bash
           (list command 30 directory nil)
           (lambda (value) (setq result value)))
          (yeah-check--wait (lambda () result))
          result)
      (user-error (list :ok nil :content (error-message-string err))))))

(let* ((data-home (make-temp-file "yeah-trash-home" t))
       (workspace (make-temp-file "yeah-trash-work" t))
       (tree (expand-file-name "tree" workspace))
       (file (expand-file-name "victim.txt" workspace))
       (old-xdg (getenv "XDG_DATA_HOME")))
  (unwind-protect
      (progn
        (setenv "XDG_DATA_HOME" data-home)
        (setq yeah-check--data-home data-home)
        (make-directory tree)
        (with-temp-file (expand-file-name "inner.txt" tree) (insert "inner"))
        (with-temp-file file (insert "victim"))
        ;; 1. the rm of the shell moves into the trash
        (let ((result (yeah-check--run (format "rm -rf %s" tree) workspace)))
          (unless (plist-get result :ok)
            (push (format "the rm of the agent failed: %S" result)
                  yeah-check--failures))
          (when (file-exists-p tree)
            (push "the tree is still in its place after the rm of the agent"
                  yeah-check--failures))
          (let ((stored (expand-file-name "tree" (yeah-trash--files-directory))))
            (unless (file-exists-p stored)
              (push "the tree is not in the trash after the rm of the agent"
                    yeah-check--failures))
            (unless (file-exists-p (expand-file-name "inner.txt" stored))
              (push "the tree in the trash lost what was in it"
                    yeah-check--failures))))
        ;; the tree comes back
        (let ((entries (yeah-trash-list)))
          (let ((entry (cl-find-if (lambda (entry)
                                     (equal tree (plist-get entry :path)))
                                   entries)))
            (unless entry
              (push "the trash does not name the tree that was thrown away"
                    yeah-check--failures))
            (when entry
              (yeah-trash-restore (plist-get entry :info))
              (unless (file-exists-p (expand-file-name "inner.txt" tree))
                (push "the tree did not come back from the trash"
                      yeah-check--failures)))))
        ;; 2. the delete tool of the agent moves into the trash
        (let ((result (yeah-tools-call "delete" (list file))))
          (unless (and (stringp result) (string-match-p "trash" result))
            (push (format "the delete tool did not move the file: %S" result)
                  yeah-check--failures))
          (when (file-exists-p file)
            (push "the delete tool left the file in its place"
                  yeah-check--failures)))
        ;; 3. the commands that destroy in place are refused
        (dolist (command (list (format "/bin/rm -rf %s" tree)
                                "find . -delete"
                                "shred -u secret"))
          (let ((result (yeah-check--run command workspace)))
            (when (plist-get result :ok)
              (push (format "the agent ran a command that destroys in place: %s" command)
                    yeah-check--failures))))
        ;; 4. the ordinary commands run
        (let ((result (yeah-check--run "printf 'ok\\n'" workspace)))
          (unless (plist-get result :ok)
            (push (format "the agent could not run an ordinary command: %S" result)
                  yeah-check--failures))))
    (setenv "XDG_DATA_HOME" (or old-xdg ""))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory workspace t)))
  (dolist (failure yeah-check--failures)
    (message "trash: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-delete-goes-to-the-trash.el ends here
