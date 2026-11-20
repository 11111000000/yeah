;;; yeah-trash.el --- the trash of the agent -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A deletion in the world of the agent is a move: the path goes into
;; the trash of the XDG specification, and it can be brought back from
;; there.  The trash lives in `$XDG_DATA_HOME/Trash' (or
;; `~/.local/share/Trash'): `files' holds the moved paths under their
;; own names, `info' holds a `.trashinfo' file for each of them, and
;; that file says where the path came from and when it was thrown away.
;;
;; The trash of the agent is the trash of the person: the agent moves
;; things into the same place the desktop of the person moves them, so
;; that what another program threw away can be restored by the same
;; code that restores what the agent threw away.
;;
;; The agent never removes a file.  The `delete' tool of the agent moves
;; it here, and the `rm' that the shell of the agent finds is a script
;; that moves it here too (`lib/yeah-shell-guard.el').  What the trash
;; cannot do is to bring back what was never moved into it: the
;; commands that destroy in place (`shred', `dd', `find -delete') are
;; refused by name, and the refusal names the reason.
;;
;; The names of the trash are the names of the XDG specification and
;; nothing else: another program that speaks that specification writes
;; into the same place and is read by the same restore.

;;; Code:

(require 'cl-lib)

(defconst yeah-trash--info-prefix "[Trash Info]\n"
  "The first line of a `.trashinfo' file of the XDG specification.")

(defun yeah-trash--data-home ()
  "Return the directory of the data of the user, where the trash lives."
  (or (getenv "XDG_DATA_HOME")
      (expand-file-name ".local/share/" (getenv "HOME"))))

(defun yeah-trash-directory ()
  "Return the root of the trash of the user."
  (expand-file-name "Trash/" (yeah-trash--data-home)))

(defun yeah-trash--files-directory ()
  "Return the directory of the moved paths of the trash."
  (expand-file-name "files/" (yeah-trash-directory)))

(defun yeah-trash--info-directory ()
  "Return the directory of the `.trashinfo' files of the trash."
  (expand-file-name "info/" (yeah-trash-directory)))

(defun yeah-trash--ensure-directories ()
  "Create the directories of the trash when they are not there yet."
  (dolist (directory (list (yeah-trash--files-directory)
                            (yeah-trash--info-directory)))
    (unless (file-directory-p directory)
      (make-directory directory t))))

(defun yeah-trash--unique-name (name)
  "Return a name in the trash that NAME does not have yet.
The name of a path that is thrown away twice in a row must not collide
with the name of the one that is already there."
  (let ((candidate name)
        (index 1))
    (while (file-exists-p (expand-file-name candidate (yeah-trash--files-directory)))
      (setq candidate (format "%s.%d" name index))
      (setq index (1+ index)))
    candidate))

(defun yeah-trash--escape (path)
  "Return PATH escaped the way the XDG specification escapes a path.
The path of the original is written as an absolute path, and the
characters that would break the format are percent-encoded."
  (replace-regexp-in-string "[ \t\n\r%#]"
                            (lambda (char)
                              (format "%%%02X" (aref char 0)))
                            path t t))

(defun yeah-trash--unescape (text)
  "Return TEXT unescaped the way the XDG specification escapes a path."
  (replace-regexp-in-string "%\\([0-9A-Fa-f][0-9A-Fa-f]\\)"
                            (lambda (match)
                              (string (string-to-number (substring match 1 3) 16)))
                            text t t))

(defun yeah-trash--write-info (info-path original)
  "Write the `.trashinfo' file INFO-PATH about the path ORIGINAL.
The file names the path the entry came from and the moment it was
thrown away, as the specification says."
  (with-temp-file info-path
    (set-buffer-file-coding-system 'utf-8-unix)
    (insert yeah-trash--info-prefix)
    (insert (format "Path=%s\n" (yeah-trash--escape original)))
    (insert (format "DeletionDate=%s\n"
                    (format-time-string "%Y-%m-%dT%H:%M:%S"))))
  (set-file-modes info-path #o600))

(defun yeah-trash--read-info (info-path)
  "Return the plist of the `.trashinfo' file INFO-PATH.
The plist holds the path the entry came from under `:path' and the
moment it was thrown away under `:date'.  Returns nil when the file
says nothing usable."
  (when (file-exists-p info-path)
    (with-temp-buffer
      (insert-file-contents info-path)
      (let ((path nil)
            (date nil))
        (dolist (line (split-string (buffer-string) "\n" t))
          (cond
           ((string-prefix-p "Path=" line)
            (setq path (yeah-trash--unescape (substring line 5))))
           ((string-prefix-p "DeletionDate=" line)
            (setq date (substring line 13)))))
        (when path
          (list :path path :date date))))))

(defun yeah-trash-move (path)
  "Move PATH into the trash of the user and return the `.trashinfo' file.
PATH must be a file or a directory that exists.  The path keeps its
name in the trash, and a second path of the same name gets a number
behind it.  Signals `user-error' when the path cannot be moved."
  (unless (and (stringp path) (file-exists-p path))
    (signal 'user-error (list (format "yeah-trash-move: no such path: %s" path))))
  (let* ((absolute (file-truename path))
         (name (yeah-trash--unique-name (file-name-nondirectory absolute)))
         (target (expand-file-name name (yeah-trash--files-directory)))
         (info (expand-file-name (concat name ".trashinfo")
                                 (yeah-trash--info-directory))))
    (yeah-trash--ensure-directories)
    (condition-case err
        (progn
          (rename-file absolute target)
          (yeah-trash--write-info info absolute)
          info)
      (error
       (signal 'user-error
               (list (format "yeah-trash-move: cannot move %s into the trash: %s"
                             path (error-message-string err))))))))

(defun yeah-trash-restore (info-path)
  "Restore the entry of the trash that INFO-PATH describes.
Returns the path the entry came back to.  Signals `user-error' when the
entry cannot be restored."
  (let ((info (yeah-trash--read-info info-path)))
    (unless info
      (signal 'user-error
              (list (format "yeah-trash-restore: not an entry of the trash: %s"
                            info-path))))
    (let* ((original (plist-get info :path))
           (name (file-name-sans-extension (file-name-nondirectory info-path)))
           (stored (expand-file-name name (yeah-trash--files-directory))))
      (unless (file-exists-p stored)
        (signal 'user-error
                (list (format "yeah-trash-restore: the entry is not in the trash: %s"
                              stored))))
      (let ((directory (file-name-directory original)))
        (unless (file-directory-p directory)
          (make-directory directory t)))
      (rename-file stored original)
      (delete-file info-path)
      original)))

(defun yeah-trash-list ()
  "Return the entries of the trash of the user.
Every entry is a plist with the path of its `.trashinfo' file under
`:info', the path it came from under `:path' and the moment it was
thrown away under `:date'."
  (let ((entries nil))
    (when (file-directory-p (yeah-trash--info-directory))
      (dolist (info (directory-files (yeah-trash--info-directory) t "\\.trashinfo\\'"))
        (let ((entry (yeah-trash--read-info info)))
          (when entry
            (push (append entry (list :info info)) entries)))))
    (nreverse entries)))

;;;###autoload
(defun yeah-trash-restore-entry ()
  "Restore one entry of the trash, chosen by the person.
The entries are listed with the path they came from and the moment they
were thrown away; the person chooses one and it comes back."
  (interactive)
  (let* ((entries (yeah-trash-list))
         (choice (and entries
                      (completing-read "Restore from the trash: "
                                       (mapcar (lambda (entry)
                                                 (format "%s (from %s)"
                                                         (file-name-nondirectory
                                                          (plist-get entry :info))
                                                         (plist-get entry :path)))
                                               entries)
                                       nil t))))
    (unless choice
      (user-error "the trash is empty"))
    (let ((entry (cl-find choice entries
                          (lambda (entry)
                            (string= choice
                                     (format "%s (from %s)"
                                             (file-name-nondirectory
                                              (plist-get entry :info))
                                             (plist-get entry :path))))
                          :test #'equal)))
      (message "restored %s" (yeah-trash-restore (plist-get entry :info))))))

(defun yeah-trash--delete (path)
  "Move PATH into the trash and return what happened.
The tool never removes anything: it moves the path, and it names the
entry of the trash so that the path can be brought back."
  (unless (and (stringp path) (file-exists-p path))
    (signal 'user-error (list (format "delete: no such path: %S" path))))
  (let ((info (yeah-trash-move path)))
    (format "moved %s into the trash; the entry is %s" path info)))

(defun yeah-trash-tools ()
  "Return the tools of the trash of the agent."
  (list (list :name "delete"
              :kind "delete"
              :description "Move a file or a directory into the trash.  Nothing is removed: the path can be brought back from the trash, and the result names the entry of the trash."
              :input (list (list :name "path" :type 'string))
              :handler #'yeah-trash--delete)))

(provide 'yeah-trash)
;;; yeah-trash.el ends here
