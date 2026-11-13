;;; yeah-service-ui.el --- drive a service Emacs from the editor -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; `M-x yeah-service' is the primary-path entry: a dedicated Emacs runs the
;; harness, and the editor drives it over the socket.  The service inherits
;; the user's configuration (the gptel backend), so the model is the one
;; the person uses.  The buffer shows the conversation as it streams.

;;; Code:

(require 'cl-lib)
(require 'project)
(require 'yeah-perm)
(require 'yeah-service)
(require 'yeah-client)

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
               (raw-input (plist-get tool-call :rawInput)))
          (when (buffer-live-p buffer)
            (with-current-buffer buffer
              (let ((inhibit-read-only t))
                (goto-char (point-max))
                (insert (format "\n[permission] %s\n" title))
                (when-let ((diff (yeah-service-ui--permission-diff
                                  title raw-input)))
                  (insert diff "\n")))))
          (funcall respond
                   (list :outcome
                         (list :optionId
                               (funcall yeah-service-ui-permission-prompter
                                        title raw-input))))))))
    (_
     (funcall respond nil))))

(defun yeah-service-ui--render-update (buffer message)
  "Render the session/update MESSAGE into BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (let* ((update (plist-get (plist-get message :params) :update))
               (kind (plist-get update :sessionUpdate)))
          (pcase kind
            ("agent_message_chunk"
             (insert (or (plist-get (plist-get update :content) :text) "")))
            ("user_message_chunk"
             (insert (format "\n\n> %s\n\n"
                             (or (plist-get (plist-get update :content) :text)
                                 ""))))
            ("tool_call"
             (insert (format "\n[tool %s]\n" (or (plist-get update :title) "?"))))
            ("tool_call_update"
             (insert (format "[tool: %s]\n"
                             (or (plist-get update :status) "?"))))
            (_ nil)))))))

(defun yeah-service-ui--ask (prompt)
  "Send PROMPT to this buffer's service session."
  (interactive "sYeah service: ")
  (unless (and yeah-service-ui--client yeah-service-ui--session-id)
    (user-error "No service session in this buffer"))
  (when yeah-service-ui--busy
    (user-error "The service is answering; cancel it first (C-c C-k)"))
  (let ((buffer (current-buffer)))
    (setq yeah-service-ui--busy t)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert (format "\n\n> %s\n\n" prompt)))
    (yeah-client-request
     yeah-service-ui--client "session/prompt"
     (list :sessionId yeah-service-ui--session-id
           :prompt (vector (list :type "text" :text prompt)))
     (lambda (result error)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (setq yeah-service-ui--busy nil)
           (let ((inhibit-read-only t))
             (goto-char (point-max))
             (insert (if error
                         (format "\n\n— error: %s\n" error)
                       (format "\n\n— %s\n"
                               (or (plist-get result :stopReason) "done")))))))))))

(defun yeah-service-ui--cancel ()
  "Cancel the prompt this buffer's service is answering."
  (interactive)
  (unless (and yeah-service-ui--client yeah-service-ui--session-id)
    (user-error "No service session in this buffer"))
  (yeah-client-notify yeah-service-ui--client "session/cancel"
                      (list :sessionId yeah-service-ui--session-id))
  (setq yeah-service-ui--busy nil))

(defvar yeah-service-ui-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'yeah-service-ui--ask)
    (define-key map (kbd "C-c C-k") #'yeah-service-ui--cancel)
    map)
  "Keymap of the Yeah service buffer.")

(define-derived-mode yeah-service-ui-mode fundamental-mode "Yeah-Service"
  "A buffer driving a Yeah service Emacs.")

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
         (buffer (get-buffer-create (format "*Yeah service: %s*" name))))
    (unless (and existing (process-live-p existing))
      (yeah-service-start
       name
       (when yeah-service-init-file
         (format "(load %S)" (expand-file-name yeah-service-init-file)))
       nil nil
       (null yeah-service-init-file)
       (yeah-service-ui--rules
        (pcase (read-char-choice
                "Yeah service permissions: [p]lan/[b]uild/[a]llow edits "
                '(?p ?b ?a))
          (?p 'plan)
          (?a 'allow)
          (_ 'build)))))
    (let ((client
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
                  (let ((inhibit-read-only t))
                    (goto-char (point-max))
                    (insert "\n\n— the service is gone; M-x yeah-service starts it again\n"))))))))
      (with-current-buffer buffer
        (yeah-service-ui-mode)
        (setq yeah-service-ui--client client)
        (let ((inhibit-read-only t))
          (goto-char (point-max))
          (insert (format "Yeah service %s — RET asks, C-c C-k cancels\n\n"
                          name)))
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
                   (let ((inhibit-read-only t))
                     (goto-char (point-max))
                     (insert (format "the service refused the session: %s\n"
                                     error)))
                 (setq yeah-service-ui--session-id
                       (plist-get result :sessionId))))))))
      (pop-to-buffer buffer))))

(provide 'yeah-service-ui)
;;; yeah-service-ui.el ends here
