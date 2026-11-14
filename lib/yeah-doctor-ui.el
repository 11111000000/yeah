;;; yeah-doctor-ui.el --- actionable Yeah diagnostics -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.

;;; Commentary:
;;
;; Doctor explains whether Yeah can run and what the person can do next.
;; It never prints a backend object, an API key, or auth-source data.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'yeah-faces)
(require 'yeah-gptel)
(require 'yeah-input)
(require 'yeah-result)
(require 'yeah-service)

(defgroup yeah-doctor-ui nil
  "The Yeah diagnostic interface."
  :group 'yeah)

(defun yeah-doctor-ui--data-home ()
  "Return Yeah's durable data directory without printing its contents."
  (if (boundp 'yeah-data-home)
      yeah-data-home
    (expand-file-name "yeah/" user-emacs-directory)))

(defun yeah-doctor-ui--version-ok-p ()
  "Return non-nil when the running Emacs is supported."
  (version< emacs-version "30.2"))

(defun yeah-doctor-ui--directory-status (directory)
  "Return the status of DIRECTORY as a plist."
  (cond ((not (stringp directory))
         (list :status :unavailable :detail "Directory is not configured"))
        ((not (file-directory-p directory))
         (list :status :unavailable :detail "Directory does not exist"))
        ((not (file-writable-p directory))
         (list :status :action :detail "Directory is not writable"))
        (t (list :status :ok :detail "Directory is writable"))))

(defun yeah-doctor-ui--report ()
  "Return the diagnostic checks as a list of plists.
Each check has `:name', `:status', `:detail' and optional `:action'."
  (let ((checks nil))
    (cl-labels ((add (name status detail &optional action)
               (push (list :name name :status status :detail detail
                           :action action)
                     checks)))
      (add "Emacs"
           (if (yeah-doctor-ui--version-ok-p) :ok :action)
           (format "Emacs %s" emacs-version)
           (and (not (yeah-doctor-ui--version-ok-p))
                "Yeah requires Emacs 30.2 or newer"))
      (let ((gptel
             (condition-case err
                 (if (yeah-gptel-check-contract) :ok :action)
               (user-error (error-message-string err)))))
        (add "gptel"
             (if (eq gptel :ok) :ok :action)
             (if (eq gptel :ok)
                 (format "supported gptel %s" gptel-version)
               (format "%s" gptel))
             (and (not (eq gptel :ok))
                  "Configure a supported gptel version, then run M-x yeah-doctor")))
      (add "Model backend"
           (if (and (boundp 'gptel-backend) gptel-backend) :ok :action)
           (if (and (boundp 'gptel-backend) gptel-backend)
               "A backend is configured"
             "No backend is configured")
           "Configure gptel-backend in your init file")
      (add "Model"
           (if (and (boundp 'gptel-model) gptel-model) :ok :action)
           (if (and (boundp 'gptel-model) gptel-model)
               "A model is configured"
             "No model is configured")
           "Configure gptel-model in your init file")
      (dolist (item
               (list (list "Session data" (yeah-doctor-ui--data-home))
                     (list "Pending input" yeah-input-directory)
                     (list "Output artifacts" yeah-result-artifact-directory)))
        (let ((report (yeah-doctor-ui--directory-status (plist-get item 1))))
          (add (plist-get item 0)
               (plist-get report :status)
               (plist-get report :detail)
               (and (not (eq (plist-get report :status) :ok))
                    "Choose a writable data directory"))))
      (add "Service Emacs"
           (if (and (file-executable-p yeah-service-emacs)
                    (fboundp 'make-network-process))
               :ok :action)
           (if (file-executable-p yeah-service-emacs)
               (format "%s is executable" yeah-service-emacs)
             "No executable service Emacs was found")
           "Set yeah-service-emacs or install Emacs 30.2")
      (add "Icons"
           :ok
           (if (or (featurep 'nerd-icons) (locate-library "nerd-icons"))
               "Optional nerd-icons are available"
             "Text labels will be used; nerd-icons is optional"))
      (nreverse checks))))

(defun yeah-doctor-ui--status-label (status)
  "Return a readable label and face for STATUS."
  (pcase status
    (:ok (cons "OK" 'yeah-faces-success))
    (:action (cons "ACTION NEEDED" 'yeah-faces-warning))
    (:unavailable (cons "UNAVAILABLE" 'yeah-faces-metadata))
    (:warning (cons "WARNING" 'yeah-faces-warning))
    (:error (cons "ERROR" 'yeah-faces-error))
    (_ (cons "UNKNOWN" 'yeah-faces-metadata))))

(defun yeah-doctor-ui--render (checks)
  "Return the rendered diagnostic report CHECKS."
  (concat
   (propertize "Yeah Doctor\n\n" 'face 'yeah-faces-user-heading)
   (mapconcat
    (lambda (check)
      (let* ((status (plist-get check :status))
             (label (yeah-doctor-ui--status-label status))
             (action (plist-get check :action)))
        (concat
         (propertize (format "%-14s" (car label)) 'face (cdr label))
         (format " %s\n" (plist-get check :name))
         (format "  %s\n" (plist-get check :detail))
         (when action
           (format "  Next: %s\n" action))
         "\n")))
    checks
    "")))

(defvar yeah-doctor-ui-mode-map
  (make-sparse-keymap)
  "Keymap for `yeah-doctor-ui-mode'.")

(define-derived-mode yeah-doctor-ui-mode special-mode "Yeah-Doctor"
  "Show Yeah's local diagnostics."
  (setq-local buffer-read-only t)
  (visual-line-mode 1))

;;;###autoload
(defun yeah-doctor-ui-open ()
  "Open Yeah's local diagnostic report."
  (let* ((checks (yeah-doctor-ui--report))
         (buffer (get-buffer-create "*Yeah Doctor*")))
    (with-current-buffer buffer
      (yeah-doctor-ui-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (yeah-doctor-ui--render checks)))
      (goto-char (point-min)))
    (pop-to-buffer buffer)
    buffer))

(provide 'yeah-doctor-ui)
;;; yeah-doctor-ui.el ends here
