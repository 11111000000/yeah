;;; yeah-product.el --- interactive Yeah journal -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; The product layer renders the session journal and queues user input through
;; `yeah-control'.  It is intentionally a client of the kernel: the view is
;; rebuilt from events, and all execution happens through the run controller.

;;; Code:

(require 'cl-lib)
(require 'yeah-control)
(require 'yeah-input)
(require 'yeah-result)
(require 'yeah-tools)
(require 'yeah-gptel)

(declare-function project-current "project" (&optional maybe-prompt))
(declare-function project-root "project" (project))
(declare-function diff-buffer-with-file "diff" (&optional buffer))
(declare-function gptel-backend-name "gptel" (backend))
(defvar gptel-backend)
(defvar gptel-model)
(defvar gptel-version)

(defgroup yeah-product nil
  "Interactive Yeah product layer."
  :group 'yeah)

(defcustom yeah-data-home
  (expand-file-name "yeah/"
                    (or (getenv "XDG_DATA_HOME")
                        (expand-file-name ".local/share/" (getenv "HOME"))))
  "Directory containing durable Yeah data."
  :type 'directory
  :group 'yeah-product)

(defcustom yeah-product-refresh-interval 0.5
  "Seconds between journal refreshes in interactive session buffers."
  :type 'number
  :group 'yeah-product)

(defconst yeah-product--safe-tools
  '("read" "glob" "grep" "introspect" "buffer-read" "elisp-check"
    "diagnostics" "job-status" "job-read")
  "Read-oriented tools that do not need an interactive approval prompt.")

(defvar-local yeah-product--control nil
  "Controller for the current Yeah session buffer.")

(defvar-local yeah-product--rendered-count nil
  "Number of journal records already rendered in this buffer.")

(defvar-local yeah-product--refresh-timer nil
  "Timer refreshing this Yeah session buffer.")

(defun yeah-product-project-root ()
  "Return the current project root, or `default-directory' outside projects."
  (let ((project (and (fboundp 'project-current)
                      (project-current nil))))
    (if project
        (file-truename (project-root project))
      (file-truename default-directory))))

(defun yeah-product-session-root (&optional project-root)
  "Return the durable session directory for PROJECT-ROOT."
  (let* ((root (file-truename (or project-root (yeah-product-project-root))))
         (hash (secure-hash 'sha256 (encode-coding-string root 'utf-8)))
         (directory (expand-file-name
                     (format "yeah/projects/%s/" hash) yeah-data-home)))
    (make-directory directory t)
    (set-file-modes directory #o700)
    directory))

(defun yeah-product--session-id (root)
  "Return a readable unique session id for project ROOT."
  (format "%s-%s"
          (file-name-nondirectory (directory-file-name root))
          (format-time-string "%Y%m%d-%H%M%S")))

(defun yeah-product--human-answerer (request)
  "Answer REQUEST through an explicit one-key approval."
  (let* ((action (plist-get request :action))
         (resource (plist-get request :resource)))
    (if (member action yeah-product--safe-tools)
        (list :effect :allow :reply :once)
      (let* ((prompt (format "Allow %s on %s? [o]nce/[a]lways/[r]eject "
                             action resource))
             (answer (read-char-choice prompt '(?o ?a ?r))))
        (pcase answer
          (?o (list :effect :allow :reply :once))
          (?a (list :effect :allow :reply :always))
          (_ (list :effect :deny :reply :reject
                   :reason "rejected by user")))))))

(defun yeah-product--format-event (record)
  "Return one display block for journal RECORD."
  (pcase (plist-get record :type)
    ("header" nil)
    ("user-message"
     (concat "* User\n" (or (plist-get record :payload) "") "\n"))
    ("assistant-message"
     (concat "* Assistant\n" (or (plist-get record :payload) "") "\n"))
    ("tool-request"
     (format "* Tool request: %s\n%s\n"
             (plist-get record :tool)
             (plist-get record :args)))
    ("permission-decision"
     (format "* Permission: %s on %s → %s\n"
             (plist-get record :action)
             (plist-get record :resource)
             (plist-get record :effect)))
    ("tool-end"
     (format "* Tool result: %s (%s)\n%s\n"
             (plist-get record :tool)
             (if (plist-get record :ok) "ok" "error")
             (plist-get record :payload)))
    ("usage"
     (format "* Usage: input %s, output %s\n"
             (plist-get record :input)
             (plist-get record :output)))
    ("compaction"
     (format "* Compaction: cut %s\n%s\n"
             (plist-get record :cut_point)
             (plist-get record :summary)))
    ("pruning"
     (format "* Pruning: keep %s characters\n"
             (plist-get record :keep-chars)))
    ("steering"
     (concat "* Steering\n" (or (plist-get record :payload) "") "\n"))
    ("nudge"
     (concat "* Completion nudge\n" (or (plist-get record :payload) "") "\n"))
    ("cancel"
     (concat "* Cancelled\n" (or (plist-get record :payload) "") "\n"))
    ("error"
     (concat "* Error\n" (or (plist-get record :payload) "") "\n"))
    (_ (format "* Event %s\n%S\n"
               (plist-get record :type) record))))

(defun yeah-product-render (&optional buffer)
  "Render BUFFER's session journal from scratch."
  (let ((buffer (or buffer (current-buffer))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (let ((inhibit-read-only t)
              (control yeah-product--control))
          (erase-buffer)
          (insert "# Yeah\n\n")
          (insert (format "Session: %s\n"
                          (plist-get (yeah-control-session control) :id)))
          (insert (format "Project: %s\n"
                          (plist-get (yeah-control-session control)
                                     :project-root)))
          (insert (format "State: %s\n\n"
                          (if-let ((turn (yeah-control-active-turn control)))
                              (yeah-turn-state turn)
                            'idle)))
          (insert "Keys: a ask · s steer · c cancel · r recover · w withdraw · d diff · g refresh · q bury\n\n")
          (dolist (record (yeah-session-records (yeah-control-session control)))
            (when-let ((block (yeah-product--format-event record)))
              (insert block "\n")))
          (setq yeah-product--rendered-count
                (length (yeah-session-records (yeah-control-session control))))
          (goto-char (point-max))
          (setq buffer-read-only t)
          buffer)))))

(defun yeah-product--refresh ()
  "Refresh the current session buffer when its journal changed."
  (let ((control yeah-product--control))
    (when (and control
               (/= (or yeah-product--rendered-count -1)
                   (length (yeah-session-records (yeah-control-session control)))))
      (yeah-product-render))))

(defun yeah-product-refresh ()
  "Refresh the current Yeah session buffer."
  (interactive)
  (yeah-product--refresh))

(defvar yeah-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a") #'yeah-product-ask)
    (define-key map (kbd "s") #'yeah-product-steer)
    (define-key map (kbd "c") #'yeah-product-cancel)
    (define-key map (kbd "r") #'yeah-product-recover-next)
    (define-key map (kbd "w") #'yeah-product-withdraw)
    (define-key map (kbd "d") #'yeah-product-diff)
    (define-key map (kbd "g") #'yeah-product-refresh)
    (define-key map (kbd "q") #'bury-buffer)
    map)
  "Keymap for `yeah-mode'.")

(define-derived-mode yeah-mode special-mode "Yeah"
  "Interactive Yeah session journal."
  (setq-local outline-regexp "^\\* ")
  (when (fboundp 'outline-minor-mode)
    (outline-minor-mode 1))
  (add-hook 'kill-buffer-hook #'yeah-product--kill-buffer nil t))

(defun yeah-product--kill-buffer ()
  "Stop the refresh timer of a dying session buffer."
  (when-let ((timer yeah-product--refresh-timer))
    (cancel-timer timer)
    (setq yeah-product--refresh-timer nil)))

(defun yeah-product-open (&optional project-root transport answerer budget nudges frozen)
  "Open or create an interactive Yeah session for PROJECT-ROOT.
TRANSPORT and ANSWERER are optional kernel inputs used by tests and callers;
interactive use defaults to gptel and one-key human approvals."
  (let* ((root (or project-root (yeah-product-project-root)))
         (session-root (yeah-product-session-root root))
         (session (yeah-session-open (yeah-product--session-id root) session-root))
         (buffer (generate-new-buffer
                  (format "*Yeah: %s*"
                          (file-name-nondirectory (directory-file-name root))))))
    (plist-put session :project-root root)
    (with-current-buffer buffer
      (yeah-mode)
      (setq yeah-product--control
            (yeah-control-new session transport
                              (or answerer #'yeah-product--human-answerer)
                              budget nudges frozen))
      (setq yeah-product--refresh-timer
            (run-at-time yeah-product-refresh-interval
                         yeah-product-refresh-interval
                         (lambda ()
                           (when (buffer-live-p buffer)
                             (with-current-buffer buffer
                               (yeah-product--refresh))))))
      (yeah-product-render buffer))
    (pop-to-buffer buffer)
    buffer))

(defun yeah-product--current-control ()
  "Return the controller of the current `yeah-mode' buffer."
  (unless (and (derived-mode-p 'yeah-mode) yeah-product--control)
    (user-error "yeah: current buffer is not a Yeah session"))
  yeah-product--control)

(defun yeah-product-ask (prompt)
  "Queue PROMPT in the current session, starting it when idle."
  (interactive "sYeah ask: ")
  (yeah-control-ask (yeah-product--current-control) prompt)
  (yeah-product-refresh))

(defun yeah-product-steer (prompt)
  "Queue steering clarification PROMPT for the active run."
  (interactive "sYeah steering: ")
  (yeah-control-steer (yeah-product--current-control) prompt)
  (yeah-product-refresh))

(defun yeah-product-cancel ()
  "Cancel the current active run."
  (interactive)
  (yeah-control-cancel (yeah-product--current-control) "cancelled by user")
  (yeah-product-refresh))

(defun yeah-product-recover-next ()
  "Explicitly start the oldest pending input."
  (interactive)
  (yeah-control-recover-next (yeah-product--current-control))
  (yeah-product-refresh))

(defun yeah-product-withdraw (id)
  "Withdraw pending input ID from the current session."
  (interactive
   (let* ((control (yeah-product--current-control))
          (pending (yeah-control-pending control))
          (choices (mapcar (lambda (input)
                             (cons (format "%s: %s"
                                           (plist-get input :id)
                                           (truncate-string-to-width
                                            (plist-get input :prompt) 60))
                                   (plist-get input :id)))
                           pending)))
     (unless choices
       (user-error "yeah: no pending input"))
     (list (cdr (assoc (completing-read "Withdraw input: " choices nil t)
                       choices)))))
  (yeah-control-withdraw (yeah-product--current-control) id)
  (yeah-product-refresh))

(defun yeah-product-diff (path)
  "Show the difference between visiting PATH's buffer and its saved file."
  (interactive "fDiff buffer with file: ")
  (let ((buffer (find-buffer-visiting (expand-file-name path))))
    (unless (buffer-live-p buffer)
      (user-error "yeah: no visiting buffer for %s" path))
    (diff-buffer-with-file buffer)))

(defun yeah-doctor ()
  "Display local Yeah runtime diagnostics without exposing credentials."
  (interactive)
  (let ((buffer (get-buffer-create "*Yeah Doctor*"))
        (gptel-status
         (condition-case err
             (if (yeah-gptel-check-contract)
                 (format "supported gptel %s" gptel-version))
           (user-error (error-message-string err)))))
    (with-current-buffer buffer
      (special-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "# Yeah Doctor\n\n")
        (insert (format "Emacs: %s\n" emacs-version))
        (insert (format "Model transport: %s\n" gptel-status))
        (insert (format "Backend configured: %s\n"
                        (and (boundp 'gptel-backend) gptel-backend t)))
        (insert (format "Model configured: %s\n"
                        (and (boundp 'gptel-model) gptel-model t)))
        (insert (format "Registered tools: %d\n" (length (yeah-tools-names))))
        (insert (format "Data home: %s\n" yeah-data-home))
        (insert (format "Pending inputs: %s\n" yeah-input-directory))
        (insert (format "Output artifacts: %s\n" yeah-result-artifact-directory))
        (insert "\nNo API keys or secrets are printed.\n"))
      (goto-char (point-min)))
    (pop-to-buffer buffer)
    buffer))

(provide 'yeah-product)
;;; yeah-product.el ends here
