;;; yeah-approval-ui.el --- approve or refuse one Yeah tool call -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.

;;; Commentary:
;;
;; A permission request is a decision about one concrete effect.  This
;; module shows the action, resource, arguments, and a read-only diff when
;; one can be computed.  The answer is once, always for the exact resource,
;; or reject.  The kernel decides what those answers mean.

;;; Code:

(require 'cl-lib)
(require 'yeah-diff)
(require 'yeah-faces)

(defgroup yeah-approval-ui nil
  "Interactive approval of Yeah tool calls."
  :group 'yeah)

(defvar-local yeah-approval--request nil
  "The request shown in the current approval buffer.")

(defvar-local yeah-approval--callback nil
  "Function called with the selected reply.")

(defvar-local yeah-approval--decided nil
  "Non-nil after the current approval has been decided.")

(defun yeah-approval--preview (request)
  "Return the diff preview plist for REQUEST, or nil."
  (let ((action (plist-get request :action))
        (arguments (plist-get request :arguments)))
    (when (member action '("edit" "write"))
      (yeah-diff-preview action arguments))))

(defun yeah-approval--render (request)
  "Return the rendered contents of REQUEST."
  (let* ((action (or (plist-get request :action) "tool"))
         (resource (or (plist-get request :resource) ""))
         (arguments (plist-get request :arguments))
         (preview (yeah-approval--preview request))
         (text
          (concat
           (propertize "Yeah needs permission\n\n" 'face 'yeah-faces-user-heading)
           (format "Action: %s\n" action)
           (format "Resource: %s\n" resource)
           (when arguments (format "Arguments: %S\n" arguments))
           (if (plist-get preview :ok)
               (concat "\nPreview\n" (plist-get preview :text))
             (concat "\n"
                     (format "No read-only preview is available: %s\n"
                             (or (plist-get preview :error)
                                 "this tool has no diff preview")))))))
    (propertize text 'face 'default)))

(defun yeah-approval--decide (reply)
  "Decide the current approval with REPLY."
  (unless (derived-mode-p 'yeah-approval-mode)
    (user-error "Not in a Yeah approval"))
  (when yeah-approval--decided
    (user-error "This request has already been answered"))
  (unless (memq reply '(:once :always :reject))
    (user-error "Unknown approval reply: %S" reply))
  (let ((callback yeah-approval--callback))
    (setf yeah-approval--decided t)
    (when (functionp callback)
      (funcall callback reply)))
  (kill-buffer (current-buffer)))

(defun yeah-approval-allow-once ()
  "Allow the current tool call once."
  (interactive)
  (yeah-approval--decide :once))

(defun yeah-approval-allow-always ()
  "Allow the current action for the exact resource in this session."
  (interactive)
  (yeah-approval--decide :always))

(defun yeah-approval-reject ()
  "Reject the current tool call."
  (interactive)
  (yeah-approval--decide :reject))

(defun yeah-approval-show-diff ()
  "Show the read-only diff for the current request."
  (interactive)
  (let* ((request yeah-approval--request)
         (action (plist-get request :action))
         (arguments (plist-get request :arguments)))
    (unless (member action '("edit" "write"))
      (user-error "This request has no diff preview"))
    (yeah-diff-show action arguments)))

(defvar yeah-approval-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "o") #'yeah-approval-allow-once)
    (define-key map (kbd "a") #'yeah-approval-allow-always)
    (define-key map (kbd "r") #'yeah-approval-reject)
    (define-key map (kbd "d") #'yeah-approval-show-diff)
    map)
  "Keymap for `yeah-approval-mode'.")

(define-derived-mode yeah-approval-mode special-mode "Yeah-Approval"
  "Approve or refuse one Yeah tool call."
  (setq-local buffer-read-only t)
  (visual-line-mode 1))

;;;###autoload
(defun yeah-approval-open (request callback)
  "Open an approval for REQUEST.
CALLBACK is called with :once, :always or :reject."
  (unless (listp request)
    (signal 'user-error (list "yeah-approval-open: REQUEST must be a plist")))
  (unless (functionp callback)
    (signal 'user-error (list "yeah-approval-open: CALLBACK must be a function")))
  (let ((buffer (get-buffer-create "*Yeah Approval*")))
    (with-current-buffer buffer
      (yeah-approval-mode)
      (setq yeah-approval--request request
            yeah-approval--callback callback
            yeah-approval--decided nil)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (yeah-approval--render request))
        (goto-char (point-min)))
      (setq header-line-format
            (list (propertize "Yeah approval" 'face 'mode-line-emphasis)
                  "  "
                  (propertize "o once · a always for this resource · r reject"
                              'face 'help-key-binding)))
      (force-mode-line-update))
    (pop-to-buffer buffer)
    buffer))

(provide 'yeah-approval-ui)
;;; yeah-approval-ui.el ends here
