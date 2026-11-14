;;; yeah-compose.el --- compose a prompt for Yeah -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.

;;; Commentary:
;;
;; A prompt sent to an agent is often a paragraph, a list of constraints,
;; and a few files.  A one-line minibuffer is the wrong shape for that.
;; This module provides a small Emacs-native composer: a real text buffer,
;; explicit file and buffer context, bounded in-memory history, and the
;; familiar C-c C-c / C-c C-k send and cancel keys.

;;; Code:

(require 'cl-lib)
(require 'ring)
(require 'text-mode)

(defgroup yeah-compose nil
  "Prompt composition for Yeah."
  :group 'yeah)

(defconst yeah-compose-history-limit 100
  "Maximum number of prompts remembered during this Emacs session.")

(defvar yeah-compose--history (make-ring yeah-compose-history-limit)
  "In-memory history of sent prompts.")

(defvar yeah-compose--history-index nil
  "Index into `yeah-compose--history' for the active composer.")

(defun yeah-compose-history-add (text)
  "Add nonempty TEXT to the in-memory prompt history."
  (when (and (stringp text) (not (string-empty-p (string-trim text))))
    (ring-insert yeah-compose--history text))
  text)

(defun yeah-compose-history-list ()
  "Return remembered prompts, newest first."
  (ring-elements yeah-compose--history))

(defun yeah-compose--history-nth (index)
  "Return history item INDEX, or nil when INDEX is outside the history."
  (let ((items (yeah-compose-history-list)))
    (and (>= index 0) (< index (length items)) (nth index items))))

(defvar-local yeah-compose--target nil
  "Function called with prompt text and context when the prompt is sent.")

(defvar-local yeah-compose--kind :ask
  "Meaning of this prompt: `:ask' or `:steering'.")

(defvar-local yeah-compose--context nil
  "Explicit file and buffer context attached to this prompt.")

(defvar-local yeah-compose--sent nil
  "Non-nil after this composer has sent its prompt.")

(defun yeah-compose--header ()
  "Return the header line for the current composer."
  (let ((kind (if (eq yeah-compose--kind :steering) "Steering" "New prompt"))
        (file (plist-get yeah-compose--context :file))
        (buffer (plist-get yeah-compose--context :buffer)))
    (list
     (propertize (format "Yeah %s" kind) 'face 'mode-line-emphasis)
     (when file
       (concat "  " (propertize (format "file: %s" file)
                                 'face 'font-lock-string-face)))
     (when buffer
       (concat "  " (propertize (format "buffer: %s" buffer)
                                 'face 'font-lock-variable-name-face)))
     (concat "  " (propertize "C-c C-c send · C-c C-k cancel"
                               'face 'help-key-binding)))))

(defun yeah-compose--refresh-header ()
  "Refresh the current composer's header."
  (when (derived-mode-p 'yeah-compose-mode)
    (setq header-line-format (yeah-compose--header))
    (force-mode-line-update)))

(defun yeah-compose-add-file ()
  "Add an existing project file to the current prompt context."
  (interactive)
  (unless (derived-mode-p 'yeah-compose-mode)
    (user-error "Not in a Yeah composer"))
  (let* ((default (or (buffer-local-value 'default-directory nil)
                       default-directory))
         (path (expand-file-name (read-file-name "Add file: " default))))
    (unless (file-exists-p path)
      (user-error "File does not exist: %s" path))
    (unless (file-readable-p path)
      (user-error "File is not readable: %s" path))
    (setq yeah-compose--context
          (plist-put (copy-sequence yeah-compose--context)
                     :file (file-truename path)))
    (yeah-compose--refresh-header)))

(defun yeah-compose-add-buffer ()
  "Add a live Emacs buffer to the current prompt context."
  (interactive)
  (unless (derived-mode-p 'yeah-compose-mode)
    (user-error "Not in a Yeah composer"))
  (let ((name (completing-read
                "Add buffer: " (mapcar #'buffer-name (buffer-list)) nil t)))
    (unless (get-buffer name)
      (user-error "Buffer does not exist: %s" name))
    (setq yeah-compose--context
          (plist-put (copy-sequence yeah-compose--context) :buffer name))
    (yeah-compose--refresh-header)))

(defun yeah-compose-clear-context ()
  "Remove all explicit context from the current prompt."
  (interactive)
  (unless (derived-mode-p 'yeah-compose-mode)
    (user-error "Not in a Yeah composer"))
  (setq yeah-compose--context nil)
  (yeah-compose--refresh-header))

(defun yeah-compose-history-previous ()
  "Insert the previous prompt from history."
  (interactive)
  (unless (derived-mode-p 'yeah-compose-mode)
    (user-error "Not in a Yeah composer"))
  (let* ((items (yeah-compose-history-list))
         (index (or yeah-compose--history-index -1)))
    (when (> (length items) 0)
      (let ((next (min (1- (length items)) (1+ index))))
        (setq yeah-compose--history-index next)
        (erase-buffer)
        (insert (or (yeah-compose--history-nth next) ""))))))

(defun yeah-compose-history-next ()
  "Insert the next prompt from history."
  (interactive)
  (unless (derived-mode-p 'yeah-compose-mode)
    (user-error "Not in a Yeah composer"))
  (let* ((items (yeah-compose-history-list))
         (index (or yeah-compose--history-index 0)))
    (when (> (length items) 0)
      (let ((next (min (length items) (1+ index))))
        (setq yeah-compose--history-index next)
        (erase-buffer)
        (insert (if (< next (length items))
                     (or (yeah-compose--history-nth next) "")
                   ""))))))

(defun yeah-compose-prompt ()
  "Return the current prompt text."
  (unless (derived-mode-p 'yeah-compose-mode)
    (user-error "Not in a Yeah composer"))
  (buffer-string))

(defun yeah-compose-context ()
  "Return the current explicit prompt context."
  (unless (derived-mode-p 'yeah-compose-mode)
    (user-error "Not in a Yeah composer"))
  yeah-compose--context)

(defun yeah-compose-send ()
  "Send the current prompt through its target."
  (interactive)
  (unless (derived-mode-p 'yeah-compose-mode)
    (user-error "Not in a Yeah composer"))
  (when yeah-compose--sent
    (user-error "This prompt has already been sent"))
  (let ((text (string-trim (yeah-compose-prompt))))
    (when (string-empty-p text)
      (user-error "The prompt is empty"))
    (unless (functionp yeah-compose--target)
      (user-error "This composer has no target"))
    (let ((target yeah-compose--target)
          (context (yeah-compose-context)))
      (setf yeah-compose--sent t)
      (yeah-compose-history-add text)
      (funcall target text context))
    (kill-buffer (current-buffer))))

(defun yeah-compose-cancel ()
  "Cancel the current prompt, preserving an unsent draft after confirmation."
  (interactive)
  (unless (derived-mode-p 'yeah-compose-mode)
    (user-error "Not in a Yeah composer"))
  (if (and (not yeah-compose--sent)
           (not (string-empty-p (string-trim (yeah-compose-prompt))))
           (not (y-or-n-p "Discard the unsent prompt? ")))
      nil
    (kill-buffer (current-buffer))))

(defvar yeah-compose-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'yeah-compose-send)
    (define-key map (kbd "C-c C-k") #'yeah-compose-cancel)
    (define-key map (kbd "C-c C-f") #'yeah-compose-add-file)
    (define-key map (kbd "C-c C-b") #'yeah-compose-add-buffer)
    (define-key map (kbd "C-c C-l") #'yeah-compose-clear-context)
    (define-key map (kbd "M-p") #'yeah-compose-history-previous)
    (define-key map (kbd "M-n") #'yeah-compose-history-next)
    map)
  "Keymap for `yeah-compose-mode'.")

(define-derived-mode yeah-compose-mode text-mode "Yeah-Compose"
  "Compose a prompt for a Yeah session."
  (setq-local comment-start nil)
  (setq-local comment-end nil)
  (visual-line-mode 1)
  (set (make-local-variable 'buffer-read-only) nil)
  (add-hook 'kill-buffer-hook
            (lambda ()
              (setq yeah-compose--sent t))
            nil t))

;;;###autoload
(defun yeah-compose-open (target &optional kind initial)
  "Open a composer that sends its prompt to TARGET.
TARGET is called with TEXT and the explicit context plist.  KIND is
`:ask' or `:steering'.  INITIAL is optional initial text."
  (unless (functionp target)
    (signal 'user-error (list "yeah-compose-open: TARGET must be a function")))
  (setq kind (or kind :ask))
  (unless (memq kind '(:ask :steering))
    (signal 'user-error (list "yeah-compose-open: KIND must be :ask or :steering")))
  (let ((buffer (generate-new-buffer "*Yeah Compose*")))
    (with-current-buffer buffer
      (yeah-compose-mode)
      (setq yeah-compose--target target
            yeah-compose--kind kind
            yeah-compose--context nil
            yeah-compose--sent nil)
      (when initial (insert initial))
      (yeah-compose--refresh-header))
    (pop-to-buffer buffer)
    buffer))

(provide 'yeah-compose)
;;; yeah-compose.el ends here
