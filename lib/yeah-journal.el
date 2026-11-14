;;; yeah-journal.el --- the shared Yeah session journal -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The person-facing journal is shared by every placement.  This module
;; renders the pure view from `yeah-ui' and delegates actions to a driver;
;; it does not know whether the run lives in this Emacs or in a service.
;;
;; The transcript is read-only.  Updates replace only the block whose
;; content changed, preserve the place a person is reading, and follow new
;; output only when the window was already at the end.

;;; Code:

(require 'cl-lib)
(require 'outline)
(require 'transient)
(require 'yeah-faces)
(require 'yeah-markdown)

(defgroup yeah-journal nil
  "The shared Yeah session journal."
  :group 'yeah)

(defconst yeah-journal--update-delay 0.05
  "Seconds used to coalesce consecutive journal updates.")

(cl-defstruct (yeah-journal (:constructor yeah-journal--make))
  "One rendered journal.

BUFFER is the transcript buffer.  DRIVER is the plist of action callbacks.
VIEW is the last pure view rendered.  BLOCKS maps a block id to its text and
markers.  PENDING is the newest view waiting to be applied.  TIMER coalesces
updates."
  (buffer nil)
  (driver nil)
  (view nil)
  (blocks nil)
  (pending nil)
  (timer nil))

(defvar-local yeah-journal--current nil
  "The `yeah-journal' shown in the current buffer.")

(defun yeah-journal--block-id (block index)
  "Return the stable id of BLOCK, falling back to INDEX."
  (or (plist-get block :id)
      (plist-get block :event-id)
      (format "block-%d" index)))

(defun yeah-journal--plain (text)
  "Return TEXT without text properties."
  (if (stringp text) (substring-no-properties text) (format "%s" text)))

(defun yeah-journal--line (text &optional face)
  "Return one rendered LINE with optional FACE."
  (if face
      (propertize text 'face face)
    text))

(defun yeah-journal--heading (level text face)
  "Return an outline heading at LEVEL with TEXT and FACE."
  (propertize (format "%s %s" (make-string level ?*) text) 'face face))

(defun yeah-journal--tool-state (state)
  "Return a readable state for tool STATE."
  (yeah-faces-status (or state "unknown")))

(defun yeah-journal--render-tool (tool indent)
  "Return the rendered text of TOOL at INDENT spaces."
  (let* ((name (or (plist-get tool :tool) (plist-get tool :name) "tool"))
         (state (or (plist-get tool :state) "unknown"))
         (args (plist-get tool :args))
         (result (plist-get tool :result))
         (prefix (make-string indent ?\s))
         (heading (propertize
                   (format "%s%s  %s"
                           prefix
                           (yeah-journal--plain
                            (yeah-faces-label 'tool name 'never))
                           (yeah-journal--plain
                            (yeah-faces-status state)))
                   'face 'yeah-faces-tool-name))
         (details
          (concat
           (if args
               (format "\n%sArguments: %s" prefix (format "%S" args))
             "")
           (if (and result (not (equal result "")))
               (format "\n%s%s" prefix result)
             ""))))
    (concat heading
            (propertize details 'face 'yeah-faces-output))))

(defun yeah-journal--render-approval (approval)
  "Return the rendered text of APPROVAL."
  (let* ((action (or (plist-get approval :action) "tool"))
         (resource (or (plist-get approval :resource) ""))
         (state (or (plist-get approval :state) "pending"))
         (args (plist-get approval :arguments))
         (text (format "%s  %s\nResource: %s%s"
                       (yeah-journal--plain
                        (yeah-faces-label 'approval action 'never))
                       (yeah-journal--plain
                        (yeah-faces-status state))
                       resource
                       (if args (format "\nArguments: %S" args) ""))))
    (propertize text 'face 'yeah-faces-pending)))

(defun yeah-journal--render-activity (activity)
  "Return the rendered text of ACTIVITY and its children."
  (let ((children (plist-get activity :children))
        (text ""))
    (dolist (child children)
      (setq text
            (concat text
                    (if (equal (plist-get child :kind) :approval)
                        (yeah-journal--render-approval child)
                      (yeah-journal--render-tool child 2))
                    "\n")))
    (concat
     (propertize "* Activity" 'face 'yeah-faces-metadata)
     (if (equal text "") "" (concat "\n" text)))))

(defun yeah-journal--render-block (block _index)
  "Return the rendered text of BLOCK at INDEX."
  (let ((kind (plist-get block :kind)))
    (pcase kind
      (:user
       (concat
        (propertize "* User" 'face 'yeah-faces-user-heading)
        (format "\n%s" (or (plist-get block :text) ""))))
      (:assistant
       (concat
        (propertize "* Yeah" 'face 'yeah-faces-assistant-heading)
        (format "\n%s" (or (plist-get block :text) ""))))
      (:reasoning
       (concat
        (propertize "* Reasoning" 'face 'yeah-faces-dimmed)
        (format "\n%s" (or (plist-get block :text) ""))))
      (:activity (yeah-journal--render-activity block))
      (:tool (yeah-journal--render-tool block 0))
      (:approval (yeah-journal--render-approval block))
      (:finish
       (concat
        (propertize "* Finished" 'face 'yeah-faces-success)
        (format "\n%s" (or (plist-get block :summary) (plist-get block :text) ""))))
      (:error
       (concat
        (propertize "* Error" 'face 'yeah-faces-error)
        (format "\n%s" (or (plist-get block :text) (plist-get block :payload) ""))))
      (:cancel
       (concat
        (propertize "* Cancelled" 'face 'yeah-faces-warning)
        (format "\n%s" (or (plist-get block :text) (plist-get block :payload) ""))))
      (:compaction
       (concat
        (propertize "* Compaction" 'face 'yeah-faces-metadata)
        (format "\n%s" (or (plist-get block :summary) (plist-get block :text) ""))))
      (:pruning
       (concat
        (propertize "* Pruning" 'face 'yeah-faces-metadata)
        (format "\n%s" (or (plist-get block :text) ""))))
      (:steering
       (concat
        (propertize "* Steering" 'face 'yeah-faces-metadata)
        (format "\n%s" (or (plist-get block :text) (plist-get block :payload) ""))))
      (:nudge
       (concat
        (propertize "* Completion nudge" 'face 'yeah-faces-warning)
        (format "\n%s" (or (plist-get block :text) (plist-get block :payload) ""))))
      (:spawn
       (concat
        (propertize "* Child started" 'face 'yeah-faces-metadata)
        (format "\n%s" (or (plist-get block :text) (plist-get block :child) ""))))
      (:child-end
       (concat
        (propertize "* Child finished" 'face 'yeah-faces-metadata)
        (format "\n%s" (or (plist-get block :text) (plist-get block :summary) ""))))
      (:input-withdrawn
       (concat
        (propertize "* Input withdrawn" 'face 'yeah-faces-warning)
        (format "\n%s" (or (plist-get block :text) (plist-get block :reason) ""))))
      (_
       (let ((type (or (plist-get block :event-type) "event")))
         (concat
          (propertize (format "* %s" (capitalize (format "%s" type)))
                      'face 'yeah-faces-metadata)
          (format "\n%s"
                  (or (plist-get block :text)
                      (and (plist-get block :record)
                           (format "%S" (plist-get block :record)))
                      ""))))))))

(defun yeah-journal--view-blocks (view)
  "Return the top-level blocks of VIEW."
  (plist-get view :blocks))

(defun yeah-journal--header (view)
  "Return a header-line format for VIEW."
  (let* ((session (plist-get view :session))
         (status (plist-get view :status))
         (usage (plist-get view :usage))
         (title (or (plist-get session :title) "Yeah"))
         (project (or (plist-get session :project) ""))
         (profile (or (plist-get session :profile) ""))
         (model (or (plist-get session :model) ""))
         (state (or (plist-get status :state) "idle"))
         (reported (plist-get usage :reported-p))
         (input (plist-get usage :input))
         (output (plist-get usage :output))
         (usage-text
          (if reported
              (format "%s in / %s out" (or input "?") (or output "?"))
            "usage unknown")))
    (list
     (propertize "Yeah" 'face 'mode-line-emphasis)
     "  "
     (propertize (format "%s" title) 'face 'bold)
     (when (not (string-empty-p project))
       (concat "  " (propertize (format "%s" project) 'face 'dired-header)))
     (when (not (string-empty-p profile))
       (concat "  " (propertize (format "%s" profile) 'face 'font-lock-type-face)))
     (when (not (string-empty-p model))
       (concat "  " (propertize (format "%s" model) 'face 'font-lock-string-face)))
     (concat "  " (propertize (format "%s" state) 'face 'mode-line))
     (concat "  " (propertize usage-text 'face 'help-key-binding)))))

(defun yeah-journal--save-window-state (buffer)
  "Return a saved point/window state for BUFFER."
  (list :point (with-current-buffer buffer (point))
        :windows
        (mapcar (lambda (window)
                  (cons window (window-start window)))
                (get-buffer-window-list buffer nil t))))

(defun yeah-journal--restore-window-state (buffer state following)
  "Restore BUFFER's point/window state from STATE.
FOLLOWING means output was at the end and should remain there."
  (when state
    (with-current-buffer buffer
      (unless following
        (goto-char (min (point-max) (plist-get state :point))))
      (dolist (entry (plist-get state :windows))
        (let ((window (car entry)))
          (when (window-live-p window)
            (set-window-start window (min (point-max) (cdr entry)) t)))))))

(defun yeah-journal--replace-block (journal id text)
  "Replace the block ID in JOURNAL with TEXT."
  (let* ((buffer (yeah-journal-buffer journal))
         (entry (gethash id (yeah-journal-blocks journal)))
         (state (yeah-journal--save-window-state buffer)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (if entry
            (let* ((start-marker (car (cdr entry)))
                   (end-marker (car (cdr (cdr entry))))
                   (start (marker-position start-marker))
                   (end (marker-position end-marker)))
              (delete-region start end)
              (goto-char start)
              (insert text)
              (set-marker start-marker start)
              (set-marker end-marker (point)))
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (let ((start (point)))
            (insert text)
            (let ((start-marker (copy-marker start))
                  (end-marker (copy-marker (point))))
              (puthash id (list text start-marker end-marker)
                       (yeah-journal-blocks journal)))))))
    (yeah-journal--restore-window-state buffer state nil)))

(defun yeah-journal--append-block (journal id text)
  "Append TEXT as block ID in JOURNAL."
  (let* ((buffer (yeah-journal-buffer journal))
         (state (yeah-journal--save-window-state buffer))
         (following
          (with-current-buffer buffer
            (>= (point) (1- (point-max))))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (let ((start (point)))
          (insert text)
          (let ((start-marker (copy-marker start))
                (end-marker (copy-marker (point))))
            (puthash id (list text start-marker end-marker)
                     (yeah-journal-blocks journal))))))
    (yeah-journal--restore-window-state buffer state following)))

(defun yeah-journal--apply-view (journal view)
  "Apply VIEW to JOURNAL immediately."
  (let ((blocks (yeah-journal--view-blocks view)))
    (cl-labels ((apply-block (block index)
                  (let* ((id (yeah-journal--block-id block index))
                         (text (yeah-journal--render-block block index))
                         (entry (gethash id (yeah-journal-blocks journal))))
                    (if (and entry (not (equal (car entry) text)))
                        (yeah-journal--replace-block journal id text)
                      (unless entry
                        (yeah-journal--append-block journal id text))))))
      (cl-loop for block in blocks
               for index from 0
               do (apply-block block index)))
    (setf (yeah-journal-view journal) view)
    (with-current-buffer (yeah-journal-buffer journal)
      (setq header-line-format (yeah-journal--header view))
      (force-mode-line-update))
    journal))

(defun yeah-journal--flush-pending (journal)
  "Apply JOURNAL's pending view, if any."
  (when (yeah-journal-timer journal)
    (cancel-timer (yeah-journal-timer journal))
    (setf (yeah-journal-timer journal) nil))
  (when (yeah-journal-pending journal)
    (let ((view (yeah-journal-pending journal)))
      (setf (yeah-journal-pending journal) nil)
      (yeah-journal--apply-view journal view)))
  journal)

(defun yeah-journal-update (journal view)
  "Schedule VIEW as the newest projection of JOURNAL."
  (setf (yeah-journal-pending journal) view)
  (unless (yeah-journal-timer journal)
    (setf (yeah-journal-timer journal)
          (run-at-time yeah-journal--update-delay nil
                       (lambda ()
                         (when (buffer-live-p (yeah-journal-buffer journal))
                           (yeah-journal--flush-pending journal))))))
  journal)

(defun yeah-journal-full-render (journal &optional view)
  "Render VIEW, or the current view, from scratch in JOURNAL."
  (let* ((buffer (yeah-journal-buffer journal))
         (view (or view (yeah-journal-view journal)))
         (state (yeah-journal--save-window-state buffer)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setf (yeah-journal-blocks journal) (make-hash-table :test 'equal))
        (insert "# Yeah session\n\n")
        (setf (yeah-journal-view journal) view)
        (setq header-line-format (yeah-journal--header view))
        (force-mode-line-update)))
    (yeah-journal--apply-view journal view)
    (yeah-journal--restore-window-state buffer state nil)
    journal))

(defun yeah-journal--driver (journal)
  "Return JOURNAL's driver."
  (yeah-journal-driver journal))

(defun yeah-journal-capability-p (journal capability)
  "Return non-nil when JOURNAL supports CAPABILITY."
  (memq capability (plist-get (yeah-journal--driver journal) :capabilities)))

(defun yeah-journal--call-driver (journal capability &rest arguments)
  "Call JOURNAL's CAPABILITY callback with ARGUMENTS.
Signal `user-error' when the capability is unavailable."
  (unless (yeah-journal-capability-p journal capability)
    (signal 'user-error
            (list (format "yeah: %s is not available in this session" capability))))
  (let ((callback (plist-get (yeah-journal--driver journal) capability)))
    (unless (functionp callback)
      (signal 'user-error
              (list (format "yeah: %s has no callback" capability))))
    (apply callback arguments)))

(defun yeah-journal-ask (journal &optional prompt)
  "Ask JOURNAL, optionally using PROMPT, through its driver."
  (let ((text (or prompt (read-string "Yeah ask: "))))
    (when (string-empty-p (string-trim text))
      (signal 'user-error "yeah: the prompt is empty"))
    (yeah-journal--call-driver journal :ask text nil nil)))

(defun yeah-journal-steer (journal &optional prompt)
  "Steer JOURNAL, optionally using PROMPT, through its driver."
  (let ((text (or prompt (read-string "Yeah steering: "))))
    (when (string-empty-p (string-trim text))
      (signal 'user-error "yeah: the steering is empty"))
    (yeah-journal--call-driver journal :steer text nil nil)))

(defun yeah-journal-cancel (journal)
  "Cancel the active work of JOURNAL."
  (yeah-journal--call-driver journal :cancel nil))

(defun yeah-journal-ask-command ()
  "Ask the current journal through its driver."
  (interactive)
  (yeah-journal-ask (yeah-journal--current)))

(defun yeah-journal-steer-command ()
  "Steer the current journal through its driver."
  (interactive)
  (yeah-journal-steer (yeah-journal--current)))

(defun yeah-journal-cancel-command ()
  "Cancel the current journal through its driver."
  (interactive)
  (yeah-journal-cancel (yeah-journal--current)))

(defun yeah-journal--current ()
  "Return the journal in the current buffer, or signal an error."
  (unless (derived-mode-p 'yeah-journal-mode)
    (signal 'user-error "yeah: current buffer is not a Yeah journal"))
  (unless yeah-journal--current
    (signal 'user-error "yeah: current buffer has no Yeah journal"))
  yeah-journal--current)

(defun yeah-journal-current ()
  "Return the journal in the current buffer."
  (yeah-journal--current))

(defun yeah-journal-current-session ()
  "Return the session metadata of the current journal."
  (plist-get (yeah-journal-view (yeah-journal--current)) :session))

(defun yeah-journal-close (journal)
  "Close JOURNAL, cancelling its pending update."
  (when (yeah-journal-timer journal)
    (cancel-timer (yeah-journal-timer journal))
    (setf (yeah-journal-timer journal) nil))
  (setf (yeah-journal-pending journal) nil)
  (when-let ((callback (plist-get (yeah-journal--driver journal) :close)))
    (funcall callback))
  (when (buffer-live-p (yeah-journal-buffer journal))
    (with-current-buffer (yeah-journal-buffer journal)
      (setq yeah-journal--current nil)))
  journal)

(defun yeah-journal-open (driver &optional view buffer-name)
  "Open a journal for DRIVER, rendering VIEW.
BUFFER-NAME names the transcript buffer.  Return the journal."
  (let* ((name (or buffer-name "*Yeah*"))
         (buffer (generate-new-buffer name))
         (journal (yeah-journal--make :buffer buffer :driver driver)))
    (with-current-buffer buffer
      (yeah-journal-mode)
      (setq yeah-journal--current journal)
      (setq buffer-read-only nil))
    (when view
      (setf (yeah-journal-view journal) view)
      (yeah-journal-full-render journal view))
    (with-current-buffer buffer
      (setq buffer-read-only t))
    journal))

(defun yeah-journal--next-block (journal direction)
  "Move to the next block in DIRECTION."
  (let* ((buffer (yeah-journal-buffer journal))
         (entries (sort (copy-sequence (hash-table-values (yeah-journal-blocks journal)))
                        (lambda (left right)
                          (< (marker-position (car (cdr left)))
                             (marker-position (car (cdr right)))))))
         (positions (mapcar (lambda (entry) (marker-position (car (cdr entry)))) entries))
         (current (with-current-buffer buffer (point)))
         (target (cond
                  ((> direction 0)
                   (or (seq-find (lambda (position) (> position current)) positions)
                       (car positions)))
                  (t
                   (or (seq-find (lambda (position) (< position current))
                                 (reverse positions))
                       (car (reverse positions)))))))
    (when target
      (with-current-buffer buffer
        (goto-char (min (point-max) target))))))

(defun yeah-journal-goto-next ()
  "Go to the next journal block."
  (interactive)
  (yeah-journal--next-block (yeah-journal--current) 1))

(defun yeah-journal-goto-previous ()
  "Go to the previous journal block."
  (interactive)
  (yeah-journal--next-block (yeah-journal--current) -1))

(defun yeah-journal-toggle-fold ()
  "Toggle the outline section at point."
  (interactive)
  (outline-toggle-children))

(defun yeah-journal-refresh ()
  "Render the current journal again from its view."
  (interactive)
  (yeah-journal-full-render (yeah-journal--current)))

(defun yeah-journal-bury ()
  "Bury the current journal buffer."
  (interactive)
  (bury-buffer))

(defun yeah-journal-export ()
  "Export the current journal through its driver."
  (interactive)
  (yeah-journal--call-driver (yeah-journal--current) :export nil))

(defun yeah-journal-diff ()
  "Show a diff through the current journal's driver."
  (interactive)
  (yeah-journal--call-driver (yeah-journal--current) :diff nil))

(defun yeah-journal--open-current-block ()
  "Open the journal block at point through its driver."
  (interactive)
  (yeah-journal--call-driver (yeah-journal--current) :open nil))

(transient-define-prefix yeah-journal-menu ()
  "Transient menu for a Yeah journal."
  [["Session"]
   ("Ask" yeah-journal-ask-command :transient t)
   ("Steer" yeah-journal-steer-command :transient t)
   ("Cancel" yeah-journal-cancel-command :transient t)]
  [["View"]
   ("Next" yeah-journal-goto-next :transient t)
   ("Previous" yeah-journal-goto-previous :transient t)
   ("Refresh" yeah-journal-refresh :transient t)
   ("Export" yeah-journal-export :transient t)]
  [["Other"]
   ("Diff" yeah-journal-diff :transient t)
   ("Bury" yeah-journal-bury :transient t)])

(defvar yeah-journal-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a") #'yeah-journal-ask-command)
    (define-key map (kbd "s") #'yeah-journal-steer-command)
    (define-key map (kbd "c") #'yeah-journal-cancel-command)
    (define-key map (kbd "d") #'yeah-journal-diff)
    (define-key map (kbd "e") #'yeah-journal-export)
    (define-key map (kbd "g") #'yeah-journal-refresh)
    (define-key map (kbd "q") #'yeah-journal-bury)
    (define-key map (kbd "n") #'yeah-journal-goto-next)
    (define-key map (kbd "p") #'yeah-journal-goto-previous)
    (define-key map (kbd "TAB") #'yeah-journal-toggle-fold)
    (define-key map (kbd "RET") #'yeah-journal--open-current-block)
    (define-key map (kbd "?") #'yeah-journal-menu)
    map)
  "Keymap for `yeah-journal-mode'.")

(easy-menu-define yeah-journal-menu-bar yeah-journal-mode-map
  "Menu for the Yeah journal."
  '("Yeah"
    ["Ask" yeah-journal-ask-command]
    ["Steer" yeah-journal-steer-command]
    ["Cancel" yeah-journal-cancel-command]
    "-"
    ["Next block" yeah-journal-goto-next]
    ["Previous block" yeah-journal-goto-previous]
    ["Refresh" yeah-journal-refresh]
    ["Export" yeah-journal-export]
    "-"
    ["Diff" yeah-journal-diff]
    ["Bury" yeah-journal-bury]))

(define-derived-mode yeah-journal-mode special-mode "Yeah"
  "A read-only journal of one Yeah session."
  (setq-local outline-regexp "^\\*+ ")
  (outline-minor-mode 1)
  (visual-line-mode 1)
  (add-hook 'kill-buffer-hook
            (lambda ()
              (when yeah-journal--current
                (yeah-journal-close yeah-journal--current)))
            nil t))

(provide 'yeah-journal)
;;; yeah-journal.el ends here
