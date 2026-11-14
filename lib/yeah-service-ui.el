;;; yeah-service-ui.el --- drive a service Emacs from the editor -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; `M-x yeah-service' is the primary-path entry: a dedicated Emacs runs the
;; harness, and the editor drives it over the socket.  The editor renders
;; the same journal as the attached placement: ACP updates are projected
;; into the same pure view model, and the journal owns the presentation.

;;; Code:

(require 'cl-lib)
(require 'project)
(require 'yeah-perm)
(require 'yeah-service)
(require 'yeah-client)
(require 'yeah-compose)
(require 'yeah-journal)
(require 'yeah-ui)

(defgroup yeah-service-ui nil
  "Driving a service Emacs from the editor."
  :group 'yeah)

(defcustom yeah-service-init-file nil
  "File a clean service Emacs loads to configure the model backend.
The service is a separate Emacs; starting it with the person's full init
pays for every package the editor loads.  With this set, `M-x
yeah-service' starts the service clean and loads only this file, which
typically configures gptel (or sets `yeah-acp-default-transport').
When nil, the service inherits the person's full init file."
  :type '(choice (const nil) file)
  :group 'yeah-service-ui)

(defun yeah-service-ui--rules (profile)
  "Return the standing permissions of PROFILE as permission rule plists.
`plan' denies the tools that change the world, `build' grants nothing —
every effect is asked of the person over the wire, and this buffer is
what answers — and `allow' grants the tools that edit, so that the agent
may work without asking."
  (pcase profile
    ('plan (yeah-perm-profile "plan"))
    ('allow (mapcar (lambda (tool) (yeah-perm-rule-make tool "*" 'allow))
                    '("edit" "write" "bash")))
    (_ nil)))

(defvar-local yeah-service-ui--client nil
  "The client of this buffer's service session.")

(defvar-local yeah-service-ui--session-id nil
  "The ACP session id of this buffer.")

(defvar-local yeah-service-ui--busy nil
  "Non-nil while a prompt is being answered.")

(defvar-local yeah-service-ui--records nil
  "Canonical local projection of the ACP updates in this buffer.")

(defvar-local yeah-service-ui--event-id 0
  "Counter used for local records that do not carry an ACP id.")

(defvar yeah-service-ui-permission-prompter
  #'yeah-service-ui--prompt-permission
  "Function answering a permission request of the service.
Called with (TITLE RAW-INPUT) and returns \"allow-once\", \"reject-once\"
or \"cancelled\".  The default asks the person; a check binds its own.")

(defun yeah-service-ui--permission-diff (title raw-input)
  "Return a preview of the change RAW-INPUT describes, or nil.
An `edit' on a file this machine can read is shown as a diff of the
passage the edit replaces; anything else has no preview."
  (when (and (string-match-p "\\`edit " (or title ""))
             (listp raw-input)
             (stringp (nth 0 raw-input))
             (stringp (nth 1 raw-input))
             (stringp (nth 2 raw-input))
             (file-readable-p (nth 0 raw-input)))
    (let ((old (nth 1 raw-input))
          (new (nth 2 raw-input)))
      (format "--- %s\n+++ %s (edited)\n-%s\n+%s"
              (nth 0 raw-input) (nth 0 raw-input)
              (replace-regexp-in-string "\n" "\n-" old)
              (replace-regexp-in-string "\n" "\n+" new)))))

(defun yeah-service-ui--prompt-permission (title raw-input)
  "Ask the person whether the service may run TITLE with RAW-INPUT.
Returns \"allow-once\", \"reject-once\" or \"cancelled\"."
  (when-let ((diff (yeah-service-ui--permission-diff title raw-input)))
    (with-temp-buffer-window "*Yeah permission*" nil nil
      (princ diff)))
  (pcase (read-char-choice
          (format "Yeah service asks: %s — [a]llow once / [r]eject " title)
          '(?a ?r))
    (?a "allow-once")
    (?r "reject-once")))

(defun yeah-service-ui--next-id (prefix)
  "Return a fresh local id beginning with PREFIX."
  (setq yeah-service-ui--event-id (1+ yeah-service-ui--event-id))
  (format "%s-%d" prefix yeah-service-ui--event-id))

(defun yeah-service-ui--append-record (record)
  "Append RECORD to the local canonical projection."
  (setq yeah-service-ui--records
        (append yeah-service-ui--records (list record)))
  record)

(defun yeah-service-ui--permission-action (title)
  "Return the action named by TITLE."
  (let ((title (or title "")))
    (if (string-match "\\`\\([^ ]+\\) on " title)
        (match-string 1 title)
      "tool")))

(defun yeah-service-ui--permission-resource (title)
  "Return the resource named by TITLE."
  (let ((title (or title "")))
    (if (string-match "\\`[^ ]+ on \\(.+\\)" title)
        (match-string 1 title)
      "")))

(defun yeah-service-ui--view ()
  "Return the journal view of the local ACP projection."
  (let* ((view (yeah-ui-view yeah-service-ui--records))
         (session (plist-put (copy-sequence (plist-get view :session))
                             :placement "service"))
         (state (if yeah-service-ui--busy "running" "idle")))
    (plist-put session :title "Yeah service")
    (plist-put view :session session)
    (plist-put view :status (list :state state :active-tool-count 0 :error nil))
    view))

(defun yeah-service-ui--update-journal ()
  "Update the shared journal from the local ACP projection."
  (let ((journal yeah-journal--current))
    (when journal
      (yeah-journal-update journal (yeah-service-ui--view)))
    journal))

(defun yeah-service-ui--content-text (content)
  "Return the text of CONTENT, a list of ACP content blocks."
  (if (vectorp content)
      (string-join
       (mapcar (lambda (block)
                 (if (hash-table-p block)
                     (or (gethash "text" block) "")
                   (or (plist-get block :text) "")))
               (append content nil))
       "")
    (if (and (listp content) (plist-get content :text))
        (plist-get content :text)
      "")))

(defun yeah-service-ui--render-update (buffer message)
  "Project the ACP MESSAGE into BUFFER's canonical journal view."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let* ((update (plist-get (plist-get message :params) :update))
             (kind (plist-get update :sessionUpdate))
             (content (plist-get update :content)))
        (pcase kind
          ("user_message_chunk"
           (yeah-service-ui--append-record
            (list :type "user-message"
                  :id (yeah-service-ui--next-id "user")
                  :payload (yeah-service-ui--content-text content))))
          ("agent_message_chunk"
           (let* ((text (yeah-service-ui--content-text content))
                  (last (car (last yeah-service-ui--records))))
             (if (and last (equal (plist-get last :type) "assistant-message"))
                 (plist-put last :payload
                            (concat (or (plist-get last :payload) "") text))
               (yeah-service-ui--append-record
                (list :type "assistant-message"
                      :id (yeah-service-ui--next-id "assistant")
                      :payload text)))))
          ("tool_call"
           (yeah-service-ui--append-record
            (list :type "tool-request"
                  :id (or (plist-get update :toolCallId)
                           (yeah-service-ui--next-id "tool"))
                  :tool (or (plist-get update :title) "tool")
                  :args (or (plist-get update :rawInput) "")
                  :tool_call_id (or (plist-get update :toolCallId)
                                   (yeah-service-ui--next-id "tool")))))
          ("tool_call_update"
           (yeah-service-ui--append-record
            (list :type "tool-end"
                  :id (or (plist-get update :toolCallId)
                           (yeah-service-ui--next-id "tool"))
                  :tool (or (plist-get update :title) "tool")
                  :ok (not (equal (plist-get update :status) "failed"))
                  :payload (yeah-service-ui--content-text content)
                  :tool_call_id (or (plist-get update :toolCallId)
                                   (yeah-service-ui--next-id "tool")))))
          (_ nil))
        (yeah-service-ui--update-journal)))))

(defun yeah-service-ui--handle-request (buffer method params respond)
  "Answer the service's request METHOD with PARAMS through RESPOND.
A permission request is rendered into BUFFER and asked of the person;
the asking happens outside the process filter so the event loop keeps
running while the person decides."
  (pcase method
    ("session/request_permission"
     (run-at-time
      0 nil
      (lambda ()
        (let* ((tool-call (plist-get params :toolCall))
               (title (or (plist-get tool-call :title) "a tool call"))
               (raw-input (plist-get tool-call :rawInput))
               (tool-call-id (plist-get tool-call :toolCallId)))
          (when (buffer-live-p buffer)
            (with-current-buffer buffer
              (yeah-service-ui--append-record
               (list :type "permission-request"
                     :id (yeah-service-ui--next-id "permission")
                     :action (yeah-service-ui--permission-action title)
                     :resource (yeah-service-ui--permission-resource title)
                     :arguments raw-input
                     :tool_call_id tool-call-id))
              (let ((journal (yeah-service-ui--update-journal)))
                (when journal
                  (yeah-journal--flush-pending journal)))))
          (let ((answer (funcall yeah-service-ui-permission-prompter
                                       title raw-input)))
            (when (buffer-live-p buffer)
              (with-current-buffer buffer
                (yeah-service-ui--append-record
                 (list :type "permission-decision"
                       :id (yeah-service-ui--next-id "permission")
                       :action (yeah-service-ui--permission-action title)
                       :resource (yeah-service-ui--permission-resource title)
                       :tool_call_id tool-call-id
                       :effect (if (equal answer "allow-once") "allow" "deny")))
                (yeah-service-ui--update-journal)))
            (funcall respond
                     (if (equal answer "cancelled")
                         (list :outcome "cancelled")
                       (list :outcome (list :optionId answer)))))))))
    (_
     (funcall respond nil))))

(defun yeah-service-ui--send-prompt (prompt callback)
  "Send PROMPT through this buffer's service session."
  (unless (and yeah-service-ui--client yeah-service-ui--session-id)
    (user-error "No service session in this buffer"))
  (when yeah-service-ui--busy
    (user-error "The service is answering; cancel it first (C-c C-k)"))
  (let ((buffer (current-buffer)))
    (setq yeah-service-ui--busy t)
    (yeah-service-ui--update-journal)
    (yeah-client-request
     yeah-service-ui--client "session/prompt"
     (list :sessionId yeah-service-ui--session-id
           :prompt (vector (list :type "text" :text prompt)))
     (lambda (result error)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (setq yeah-service-ui--busy nil)
           (if error
               (yeah-service-ui--append-record
                (list :type "error" :id (yeah-service-ui--next-id "error")
                      :payload (format "%s" error)))
             (yeah-service-ui--append-record
              (list :type "finish" :id (yeah-service-ui--next-id "finish")
                    :summary (or (plist-get result :stopReason) "done"))))
           (yeah-service-ui--update-journal)))
       (when (functionp callback) (funcall callback result error))))))

(defun yeah-service-ui--ask (prompt)
  "Send PROMPT to this buffer's service session."
  (unless (stringp prompt)
    (user-error "The service prompt must be text"))
  (yeah-service-ui--send-prompt prompt nil))

(defun yeah-service-ui--cancel ()
  "Cancel the prompt this buffer's service is answering."
  (interactive)
  (unless (and yeah-service-ui--client yeah-service-ui--session-id)
    (user-error "No service session in this buffer"))
  (yeah-client-notify yeah-service-ui--client "session/cancel"
                      (list :sessionId yeah-service-ui--session-id))
  (setq yeah-service-ui--busy nil)
  (yeah-service-ui--update-journal))

(defvar yeah-service-ui-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a") #'yeah-journal-ask-command)
    (define-key map (kbd "c") #'yeah-service-ui--cancel)
    map)
  "Keymap of the Yeah service buffer.")

(define-derived-mode yeah-service-ui-mode yeah-journal-mode "Yeah-Service"
  "A buffer driving a Yeah service Emacs."
  (set-keymap-parent yeah-service-ui-mode-map yeah-journal-mode-map)
  (define-key yeah-service-ui-mode-map (kbd "a") #'yeah-journal-ask-command)
  (define-key yeah-service-ui-mode-map (kbd "c") #'yeah-service-ui--cancel))

(defun yeah-service-ui--driver (journal)
  "Return the service driver for JOURNAL."
  (list :ask (lambda (text _context callback)
                (with-current-buffer (yeah-journal-buffer journal)
                  (yeah-service-ui--send-prompt text callback)))
        :cancel (lambda (callback)
                  (with-current-buffer (yeah-journal-buffer journal)
                    (yeah-service-ui--cancel))
                  (when (functionp callback) (funcall callback t)))
        :capabilities '(:ask :cancel)))

;;;###autoload
(defun yeah-service (&optional name)
  "Start or connect to a Yeah service Emacs and drive it from a buffer.
With `yeah-service-init-file' set the service starts clean and loads only
that file (the gptel configuration); otherwise it inherits the person's
init, so the model is the one the person uses.  NAME names the service;
the default is \"default\".
The person chooses the standing permissions of the service: `plan' lets
the agent look but not touch, `build' asks the person for every effect
(this buffer answers over the wire) and `allow' lets the agent edit."
  (interactive)
  (let* ((name (or name "default"))
         (existing (gethash name yeah-service--processes))
         (buffer nil)
         (client nil)
         (journal nil))
    (unless (and existing (process-live-p existing))
      (yeah-service-start
       name
       (when yeah-service-init-file
         (format "(load %S)" (expand-file-name yeah-service-init-file)))
       nil nil
       (null yeah-service-init-file)
       (yeah-service-ui--rules
        (completing-read
         "Yeah service permissions: "
         '(("Build — ask before changing the world" . "build")
           ("Plan — read only" . "plan")
           ("Allow edits — unattended" . "allow"))
         nil t "build"))))
    (setq client
          (yeah-client-connect
           (yeah-service-socket-path name)
           :on-notification
           (lambda (message)
             (when (equal (plist-get message :method) "session/update")
               (yeah-service-ui--render-update buffer message)))
           :on-request
           (lambda (method params respond)
             (yeah-service-ui--handle-request buffer method params respond))
           :on-close
           (lambda (_client)
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (setq yeah-service-ui--busy nil)
                 (yeah-service-ui--append-record
                  (list :type "error" :id (yeah-service-ui--next-id "error")
                        :payload "The service disconnected."))
                 (yeah-service-ui--update-journal))))))
    (setq journal
          (yeah-journal-open
           nil
           nil
           (format "*Yeah service: %s*" name)))
    (setf (yeah-journal-driver journal) (yeah-service-ui--driver journal))
    (setq buffer (yeah-journal-buffer journal))
    (with-current-buffer buffer
      (yeah-service-ui-mode)
      (setq yeah-journal--current journal
            yeah-service-ui--client client
            yeah-service-ui--session-id nil
            yeah-service-ui--busy nil
            yeah-service-ui--records nil
            yeah-service-ui--event-id 0)
      (yeah-service-ui--update-journal))
    (yeah-client-request client "initialize"
                         (list :protocolVersion 1)
                         (lambda (_result _error) nil))
    (yeah-client-request
     client "session/new"
     (list :cwd (or (and (fboundp 'project-current)
                         (when-let ((project (project-current)))
                           (project-root project)))
                      default-directory)
           :mcpServers nil)
     (lambda (result error)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (if error
               (progn
                 (yeah-service-ui--append-record
                  (list :type "error" :id (yeah-service-ui--next-id "error")
                        :payload (format "%s" error)))
                 (yeah-service-ui--update-journal))
             (setq yeah-service-ui--session-id
                   (plist-get result :sessionId))
             (yeah-service-ui--update-journal))))))
    (pop-to-buffer buffer)
    buffer))

(provide 'yeah-service-ui)
;;; yeah-service-ui.el ends here
