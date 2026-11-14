;;; yeah-session-list.el --- browse Yeah sessions -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.

;;; Commentary:
;;
;; Sessions are durable text, not disposable chat history.  The list shows
;; what exists and lets the person open one; it deliberately offers no
;; delete or rewrite operation.

;;; Code:

(require 'cl-lib)
(require 'tabulated-list)
(require 'yeah-sessions)

(defgroup yeah-session-list nil
  "Browsing Yeah sessions."
  :group 'yeah)

(defvar-local yeah-session-list--root nil
  "The session data root shown in the current list.")

(defvar-local yeah-session-list--open nil
  "Function called with a selected session id.")

(defun yeah-session-list--time (mtime)
  "Return a readable representation of MTIME."
  (if (numberp mtime)
      (format-time-string "%Y-%m-%d %H:%M" (seconds-to-time mtime) t)
    ""))

(defun yeah-session-list--entry (session)
  "Return the tabulated-list entry for SESSION."
  (list (plist-get session :id)
        (vector (format "%s" (or (plist-get session :title)
                                  (plist-get session :id)))
                (yeah-session-list--time (plist-get session :mtime))
                (format "%s" (or (plist-get session :status) "unknown"))
                (format "%s" (or (plist-get session :model) "-"))
                (format "%s" (or (plist-get session :placement) "-")))))

(defun yeah-session-list-open-session ()
  "Open the selected session through the list's callback."
  (interactive)
  (unless (derived-mode-p 'yeah-session-list-mode)
    (user-error "Not in a Yeah session list"))
  (let ((id (tabulated-list-get-id)))
    (unless id
      (user-error "No session is selected"))
    (if (functionp yeah-session-list--open)
        (funcall yeah-session-list--open id)
      (user-error "No session opener is configured"))))

(defvar yeah-session-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'yeah-session-list-open-session)
    map)
  "Keymap for `yeah-session-list-mode'.")

(define-derived-mode yeah-session-list-mode tabulated-list-mode "Yeah-Sessions"
  "List the sessions of one Yeah project."
  (setq-local tabulated-list-format
              [("Session" 30 t)
               ("Updated" 18 nil)
               ("Status" 14 nil)
               ("Model" 20 nil)
               ("Placement" 12 nil)])
  (setq-local tabulated-list-padding 1))

;;;###autoload
(defun yeah-session-list-open (root &optional on-open)
  "Open the session list for ROOT.
ON-OPEN is called with the id of a selected session."
  (unless (stringp root)
    (signal 'user-error (list "yeah-session-list-open: ROOT must be a string")))
  (let ((buffer (get-buffer-create "*Yeah Sessions*")))
    (with-current-buffer buffer
      (yeah-session-list-mode)
      (setq yeah-session-list--root (file-truename (directory-file-name root))
            yeah-session-list--open on-open)
      (setq tabulated-list-entries
            (mapcar #'yeah-session-list--entry
                    (yeah-sessions-index root)))
      (tabulated-list-init-header)
      (tabulated-list-print t))
    (pop-to-buffer buffer)
    buffer))

(provide 'yeah-session-list)
;;; yeah-session-list.el ends here
