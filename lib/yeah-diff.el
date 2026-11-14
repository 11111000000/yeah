;;; yeah-diff.el --- preview Yeah tool changes without applying them -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.

;;; Commentary:
;;
;; Approval is useful only when the person can see what an effect will do.
;; This module builds a diff for Edit and Write arguments without changing
;; the file, the visited buffer, its modification tick, or undo history.

;;; Code:

(require 'cl-lib)
(require 'diff)

(defgroup yeah-diff nil
  "Read-only previews of Yeah changes."
  :group 'yeah)

(defun yeah-diff--read-file (path)
  "Return the contents of PATH, or nil when it cannot be read."
  (when (and path (file-readable-p path))
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8))
        (insert-file-contents path))
      (buffer-string))))

(defun yeah-diff--replace-once (old new text)
  "Return TEXT with OLD replaced by NEW exactly once.
Return nil when OLD is absent or occurs more than once."
  (let ((count (length (split-string text (regexp-quote old) t))))
    (and (= count 1)
         (replace-regexp-in-string (regexp-quote old) new text t t))))

(defun yeah-diff--unified (old-text new-text)
  "Return a unified diff between OLD-TEXT and NEW-TEXT."
  (let ((old-buffer (generate-new-buffer " *yeah-diff-old*"))
        (new-buffer (generate-new-buffer " *yeah-diff-new*"))
        (preview (generate-new-buffer " *yeah-diff-preview*")))
    (unwind-protect
        (progn
          (with-current-buffer old-buffer (insert old-text))
          (with-current-buffer new-buffer (insert new-text))
          (condition-case nil
              (progn
                (diff-no-select old-buffer new-buffer nil t preview)
                (with-current-buffer preview (buffer-string)))
            (error nil)))
      (when (buffer-live-p old-buffer) (kill-buffer old-buffer))
      (when (buffer-live-p new-buffer) (kill-buffer new-buffer))
      (when (buffer-live-p preview) (kill-buffer preview)))))

(defun yeah-diff-preview (action arguments)
  "Return a preview plist for ACTION with ARGUMENTS.
The result is `(:ok t :text TEXT :path PATH)' for a readable diff, or
`(:ok nil :error REASON)' when a safe preview cannot be produced."
  (let ((arguments (or arguments '())))
    (pcase action
      ("edit"
       (if (and (>= (length arguments) 3)
                (stringp (nth 0 arguments))
                (stringp (nth 1 arguments))
                (stringp (nth 2 arguments)))
           (let* ((path (expand-file-name (nth 0 arguments)))
                  (old-text (nth 1 arguments))
                  (new-text (nth 2 arguments))
                  (current (yeah-diff--read-file path)))
             (if (null current)
                 (list :ok nil :error (format "Cannot read %s" path))
               (let ((changed (yeah-diff--replace-once old-text new-text current)))
                 (if (null changed)
                     (list :ok nil
                           :error "The old text is absent or does not occur exactly once")
                   (let ((text (yeah-diff--unified current changed)))
                     (if text
                         (list :ok t :text text :path path)
                       (list :ok nil :error "The diff could not be computed")))))))
         (list :ok nil :error "Edit arguments are incomplete")))
      ("write"
       (if (and (>= (length arguments) 2)
                (stringp (nth 0 arguments))
                (stringp (nth 1 arguments)))
           (let* ((path (expand-file-name (nth 0 arguments)))
                  (new-text (nth 1 arguments))
                  (old-text (or (yeah-diff--read-file path) "")))
             (let ((text (yeah-diff--unified old-text new-text)))
               (if text
                   (list :ok t :text text :path path)
                 (list :ok nil :error "The diff could not be computed"))))
         (list :ok nil :error "Write arguments are incomplete")))
      (_
       (list :ok nil :error (format "No preview for %s" action))))))

(defun yeah-diff-show (action arguments)
  "Show a read-only diff preview for ACTION and ARGUMENTS.
Return the preview buffer, or nil when no preview is available."
  (let* ((preview (yeah-diff-preview action arguments))
         (text (plist-get preview :text))
         (buffer (get-buffer-create "*Yeah Diff Preview*")))
    (unless (plist-get preview :ok)
      (user-error "%s" (or (plist-get preview :error) "No diff preview")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text))
      (setq buffer-read-only t)
      (goto-char (point-min)))
    (pop-to-buffer buffer)
    buffer))

(provide 'yeah-diff)
;;; yeah-diff.el ends here
