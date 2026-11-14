;;; yeah-product.el --- interactive Yeah journal -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.

;;; Commentary:
;;
;; The product layer owns the attached placement.  It turns a session and
;; its run controller into the shared read-only journal, provides the
;; attached driver, and keeps the historical public commands working.

;;; Code:

(require 'cl-lib)
(require 'yeah-approval)
(require 'yeah-control)
(require 'yeah-doctor-ui)
(require 'yeah-events)
(require 'yeah-input)
(require 'yeah-journal)
(require 'yeah-org)
(require 'yeah-result)
(require 'yeah-session-list)
(require 'yeah-tools)
(require 'yeah-ui)
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

(defvar-local yeah-product--refresh-timer nil
  "Timer refreshing this Yeah session buffer.")

(defvar-local yeah-product--profile nil
  "Permission profile of the current Yeah session.")

(defvar-local yeah-product--root nil
  "Project root of the current Yeah session.")

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

(defun yeah-product-latest-session-id (root)
  "Return the id of the most recent session of ROOT, or nil.
A session is resumed by its file, so a person can quit and come back."
  (let ((directory (expand-file-name "sessions" (yeah-product-session-root root))))
    (when (file-directory-p directory)
      (let ((files (directory-files directory t "\\.jsonl\\'")))
        (when files
          (file-name-base
           (car (sort files
                       (lambda (left right)
                         (let ((left-time
                                (file-attribute-modification-time
                                 (file-attributes left)))
                               (right-time
                                (file-attribute-modification-time
                                 (file-attributes right))))
                           (if (= left-time right-time)
                               (string< (car left) (car right))
                             (> left-time right-time))))))))))))

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

;;;###autoload
(defun yeah-product-human-answerer (request)
  "Answer REQUEST through a one-key approval of the person.
This is the answerer of the attached placement: the run lives in the
Emacs of the person, so the person may answer."
  (yeah-product--human-answerer request))

(defun yeah-product--view (control &optional profile root)
  "Return the journal view of CONTROL.
PROFILE and ROOT enrich the session metadata without changing the journal."
  (let* ((session (yeah-control-session control))
         (view (yeah-ui-view (yeah-session-records session)))
         (metadata (plist-put (copy-sequence (plist-get view :session))
                              :placement "attached")))
    (plist-put metadata :project (or root
                                   (plist-get session :project-root)))
    (plist-put metadata :profile (or profile "build"))
    (when (and (boundp 'gptel-model) gptel-model)
      (plist-put metadata :model gptel-model))
    (plist-put view :session metadata)
    view))

(defun yeah-product--prompt-with-context (text context)
  "Return TEXT with the explicit composer CONTEXT appended."
  (let ((file (plist-get context :file))
        (buffer (plist-get context :buffer)))
    (concat text
            (when file (format "\n\nExplicit file context: %s" file))
            (when buffer (format "\n\nExplicit buffer context: %s" buffer)))))

(defun yeah-product--driver (control)
  "Return the attached driver for CONTROL."
  (list
   :ask (lambda (text context callback)
          (yeah-control-ask
           control (yeah-product--prompt-with-context text context))
          (when (functionp callback) (funcall callback t)))
   :steer (lambda (text context callback)
            (yeah-control-steer
             control (yeah-product--prompt-with-context text context))
            (when (functionp callback) (funcall callback t)))
   :cancel (lambda (callback)
             (yeah-control-cancel control "cancelled by user")
             (when (functionp callback) (funcall callback t)))
   :export (lambda (callback)
             (yeah-product-export)
             (when (functionp callback) (funcall callback t)))
   :capabilities '(:ask :steer :cancel :export)))

(defun yeah-product-render (&optional buffer)
  "Render BUFFER's session journal from scratch."
  (let ((buffer (or buffer (current-buffer))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (let ((journal yeah-journal--current))
          (yeah-journal-full-render
           journal (yeah-product--view yeah-product--control
                                         yeah-product--profile
                                         yeah-product--root)))))))

(defun yeah-product--refresh ()
  "Refresh the current session buffer when its journal changed."
  (let ((control yeah-product--control)
        (journal yeah-journal--current))
    (when (and control journal)
      (yeah-journal-update
       journal (yeah-product--view control
                                   yeah-product--profile
                                   yeah-product--root)))))

(defun yeah-product-refresh ()
  "Refresh the current Yeah session buffer."
  (interactive)
  (yeah-product--refresh))

(defvar yeah-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map yeah-journal-mode-map)
    (define-key map (kbd "a") #'yeah-product-ask)
    (define-key map (kbd "s") #'yeah-product-steer)
    (define-key map (kbd "c") #'yeah-product-cancel)
    (define-key map (kbd "r") #'yeah-product-recover-next)
    (define-key map (kbd "w") #'yeah-product-withdraw)
    (define-key map (kbd "d") #'yeah-product-diff)
    (define-key map (kbd "g") #'yeah-product-refresh)
    map)
  "Keymap for `yeah-mode'.")

(define-derived-mode yeah-mode yeah-journal-mode "Yeah"
  "Interactive Yeah session journal."
  (set-keymap-parent yeah-mode-map yeah-journal-mode-map)
  (define-key yeah-mode-map (kbd "a") #'yeah-product-ask)
  (define-key yeah-mode-map (kbd "s") #'yeah-product-steer)
  (define-key yeah-mode-map (kbd "c") #'yeah-product-cancel)
  (define-key yeah-mode-map (kbd "r") #'yeah-product-recover-next)
  (define-key yeah-mode-map (kbd "w") #'yeah-product-withdraw)
  (define-key yeah-mode-map (kbd "d") #'yeah-product-diff)
  (add-hook 'kill-buffer-hook #'yeah-product--kill-buffer nil t))

(defun yeah-product--kill-buffer ()
  "Stop the refresh timer of a dying session buffer."
  (when-let ((timer yeah-product--refresh-timer))
    (cancel-timer timer)
    (setq yeah-product--refresh-timer nil)))

(defun yeah-product--choose-profile ()
  "Ask the person which permission profile the session runs under.
The answer is `plan' or `build'; `build' is the default, and it is the
behaviour of the harness without a profile: the person is asked for
every tool that changes the world."
  (completing-read
   "Yeah profile: "
   '(("Build — ask before changing the world" . "build")
     ("Plan — read only" . "plan"))
   nil t "build"))

(defun yeah-product--system-prompt (root)
  "Return the system prompt of a session in the project ROOT.
The model is told where it works, because a model that does not know
the directory acts in a directory it guesses."
  (concat yeah-gptel-prelude
          (format "
You are working in the directory %s.
" root)))

(defun yeah-product-open (&optional project-root transport answerer budget nudges frozen profile session-id)
  "Open or create an interactive Yeah session for PROJECT-ROOT.
TRANSPORT and ANSWERER are optional kernel inputs used by tests and callers;
interactive use defaults to gptel and one-key human approvals.
PROFILE is the permission profile of the session: `plan' refuses the tools
that change the world, `build' asks for them.  SESSION-ID, when given,
resumes an existing session of the project instead of starting a new one."
  (let* ((nudges (or nudges 2))
         (root (or project-root (yeah-product-project-root)))
         (session-root (yeah-product-session-root root))
         (session (yeah-session-open (or session-id
                                         (yeah-product--session-id root))
                                     session-root))
         (profile (or profile "build"))
         (control
          (yeah-control-new
           session
           (or transport
               (lambda (prompt callback)
                 (yeah-gptel-request
                  prompt callback
                  :system (yeah-product--system-prompt root))))
           (yeah-approval-profile-answerer
            profile
            (or answerer #'yeah-product--human-answerer))
           budget nudges frozen))
         (buffer-name (format "*Yeah: %s*"
                              (file-name-nondirectory
                               (directory-file-name root))))
         (journal (yeah-journal-open
                   (yeah-product--driver control)
                   (yeah-product--view control profile root)
                   buffer-name)))
    (plist-put session :project-root root)
    (with-current-buffer (yeah-journal-buffer journal)
      (yeah-mode)
      (setq yeah-journal--current journal
            yeah-product--control control
            yeah-product--profile profile
            yeah-product--root root
            yeah-product--refresh-timer
            (run-at-time yeah-product-refresh-interval
                         yeah-product-refresh-interval
                         (lambda ()
                           (when (buffer-live-p (yeah-journal-buffer journal))
                             (with-current-buffer (yeah-journal-buffer journal)
                               (yeah-product--refresh)))))))
    (pop-to-buffer (yeah-journal-buffer journal))
    (yeah-journal-buffer journal)))

(defun yeah-product--current-control ()
  "Return the controller of the current `yeah-mode' buffer."
  (unless (and (derived-mode-p 'yeah-mode) yeah-product--control)
    (user-error "yeah: current buffer is not a Yeah session"))
  yeah-product--control)

(defun yeah-product-ask (&optional prompt)
  "Queue PROMPT in the current session, starting it when idle.
Interactively, open the full prompt composer."
  (interactive)
  (let ((control (yeah-product--current-control)))
    (if prompt
        (progn
          (yeah-control-ask control prompt)
          (yeah-product-refresh))
      (yeah-journal-ask-command))))

(defun yeah-product-steer (&optional prompt)
  "Queue steering clarification PROMPT for the active run.
Interactively, open the full steering composer."
  (interactive)
  (let ((control (yeah-product--current-control)))
    (if prompt
        (progn
          (yeah-control-steer control prompt)
          (yeah-product-refresh))
      (yeah-journal-steer-command))))

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

(defun yeah-product-export-directory ()
  "Return the directory the Org exports are written to."
  (expand-file-name "exports/" yeah-data-home))

(defun yeah-product-export ()
  "Export the current Yeah session as an Org file and open it.
The journal is written for the machine; this is the same truth for the
person, in the format the person already reads."
  (interactive)
  (let* ((control (yeah-product--current-control))
         (session (yeah-control-session control))
         (file (yeah-org-export-file session
                                     (yeah-product-export-directory))))
    (find-file file)))

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
  (yeah-doctor-ui-open))

(provide 'yeah-product)
;;; yeah-product.el ends here
