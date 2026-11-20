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
(require 'yeah-acp-vocabulary)
(require 'yeah-approval-ui)
(require 'yeah-perm)
(require 'yeah-service)
(require 'yeah-client)
(require 'yeah-compose)
(require 'yeah-journal)
(require 'yeah-org)
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

(defcustom yeah-service-ui-export-directory
  (expand-file-name
   "yeah/exports/"
   (or (getenv "XDG_DATA_HOME")
       (expand-file-name ".local/share/" (getenv "HOME"))))
  "Directory where service journal exports are written."
  :type 'directory
  :group 'yeah-service-ui)

(defun yeah-service-ui--rules (profile)
  "Return the standing permissions of PROFILE as permission rule plists.
`plan' denies the tools that change the world, `build' grants nothing —
every effect is asked of the person over the wire, and this buffer is
what answers — `allow' grants the tools that edit, so that the agent
may work without asking, and `auto' is the profile of the kernel that
grants everything: there is nobody to ask."
  (pcase profile
    ('plan (yeah-perm-profile "plan"))
    ('allow (mapcar (lambda (tool) (yeah-perm-rule-make tool "*" 'allow))
                    '("edit" "write" "bash")))
    ('auto (yeah-perm-profile "auto"))
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
  #'yeah-service-ui--approval-prompter
  "Function answering a permission request of the service.
Called with (TITLE RAW-INPUT) and returns \"allow-once\", \"allow-always\"
or \"reject-once\".  The default asks the person in the shared approval
view; a check binds its own.")

(defun yeah-service-ui--approval-prompter (title raw-input)
  "Ask the person about TITLE with RAW-INPUT in the shared approval view.
Returns the option id of the answer: \"allow-once\", \"allow-always\" or
\"reject-once\"."
  (let ((decision (yeah-approval-answer
                   (list :action (yeah-service-ui--permission-action title)
                         :resource (yeah-service-ui--permission-resource title)
                         :arguments raw-input))))
    (if (eq (plist-get decision :effect) :allow)
        (if (eq (plist-get decision :reply) :always)
            "allow-always"
          "allow-once")
      "reject-once")))

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
  (let ((blocks (cond
                 ((vectorp content) (append content nil))
                 ((and (listp content) (plist-get content :text))
                  (list content))
                 ((listp content) content)
                 (t nil))))
    (string-join
     (mapcar (lambda (block)
               (if (hash-table-p block)
                   (or (gethash "text" block) "")
                 (or (plist-get block :text) "")))
             blocks)
     "")))

(defun yeah-service-ui--plist-value (plist &rest keys)
  "Return the first value of KEYS present in PLIST.
A present nil value is returned as nil; it is not confused with an
absent key."
  (let ((value nil)
        (found nil))
    (while (and keys (not found))
      (let ((key (pop keys)))
        (when (plist-member plist key)
          (setq value (plist-get plist key)
                found t))))
    value))

(defun yeah-service-ui--queue-record-type (kind)
  "Return the local record type for the ACP queue event KIND."
  (pcase kind
    ("input_queued" "input-queued")
    ("input_taken" "input-taken")
    ("input_recovered" "input-recovered")
    ("input_withdrawn" "input-withdrawn")
    (_ nil)))

(defun yeah-service-ui--queue-kind-p (kind)
  "Return non-nil when KIND is an ACP queue event kind."
  (and (stringp kind)
       (member kind '("input_queued"
                      "input_taken"
                      "input_recovered"
                      "input_withdrawn"))))

(defun yeah-service-ui--queue-record (kind update params)
  "Return the local record for the ACP queue event KIND.
UPDATE carries the event payload and PARAMS the notification envelope."
  (let* ((input-id (or (yeah-service-ui--plist-value
                         update :inputId :input_id :input-id)
                       (yeah-service-ui--plist-value
                         params :inputId :input_id :input-id)))
         (input-kind (or (yeah-service-ui--plist-value
                            update :inputKind :input_kind :input-kind :kind)
                          (yeah-service-ui--plist-value
                            params :inputKind :input_kind :input-kind :kind)))
         (prompt (or (yeah-service-ui--plist-value
                       update :prompt :text)
                     (yeah-service-ui--content-text
                      (yeah-service-ui--plist-value update :content))
                     (yeah-service-ui--plist-value params :prompt)))
         (reason (or (yeah-service-ui--plist-value update :reason)
                     (yeah-service-ui--plist-value params :reason)))
         (type (yeah-service-ui--queue-record-type kind)))
    (when type
      (list :type type
            :id (yeah-service-ui--next-id "input")
            :input_id input-id
            :input_kind input-kind
            :kind input-kind
            :prompt prompt
            :reason reason))))

(defun yeah-service-ui--render-update (buffer message)
  "Project the ACP MESSAGE into BUFFER's canonical journal view."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let* ((params (plist-get message :params))
             (update (plist-get params :update))
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
          ((pred yeah-service-ui--queue-kind-p)
           (let ((record (yeah-service-ui--queue-record kind update params)))
             (when record
               (yeah-service-ui--append-record record))))
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
              (yeah-service-ui--outcome-record (plist-get result :stopReason))))
           (yeah-service-ui--update-journal)))
       (when (functionp callback) (funcall callback result error))))))

(defun yeah-service-ui--outcome-record (stop-reason)
  "Return the record of the outcome of a prompt that ended with STOP-REASON.
A run that ended without the effect is not a finish: the editor must see
the difference, or the person reads a refusal as a success."
  (pcase stop-reason
    ("end_turn"
     (list :type "finish" :id (yeah-service-ui--next-id "finish")
           :summary "end_turn"))
    ("cancelled"
     (list :type "cancel" :id (yeah-service-ui--next-id "cancel")
           :payload "the run was cancelled"))
    (_
     (list :type "unfinished" :id (yeah-service-ui--next-id "unfinished")
           :payload "the run ended without the effect"
           :reason (format "the service answered %s" (or stop-reason "nothing"))))))

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

(defun yeah-service-ui--request-control (method params &optional callback)
  "Send the control request METHOD with PARAMS for this service session.
CALLBACK, when given, receives the ACP result and error."
  (unless (and yeah-service-ui--client yeah-service-ui--session-id)
    (user-error "No service session in this buffer"))
  (let ((buffer (current-buffer)))
    (yeah-client-request
     yeah-service-ui--client method params
     (lambda (result error)
       (when (and error (buffer-live-p buffer))
         (with-current-buffer buffer
           (yeah-service-ui--append-record
            (list :type "error"
                  :id (yeah-service-ui--next-id "error")
                  :payload (format "%s" error)))
           (yeah-service-ui--update-journal)))
       (when (functionp callback)
         (funcall callback result error))))))

(defun yeah-service-ui--prompt-with-context (text context)
  "Return TEXT with the explicit composer CONTEXT appended."
  (let ((file (plist-get context :file))
        (buffer (plist-get context :buffer)))
    (concat text
            (when file (format "\n\nExplicit file context: %s" file))
            (when buffer
              (format "\n\nExplicit buffer context: %s" buffer)))))

(defun yeah-service-ui--send-steering (text context &optional callback)
  "Queue steering TEXT with CONTEXT for the running service prompt.
CALLBACK, when given, receives the ACP result and error."
  (unless (stringp text)
    (user-error "The service steering must be text"))
  (yeah-service-ui--request-control
   "session/steer"
   (list :sessionId yeah-service-ui--session-id
         :prompt (yeah-service-ui--prompt-with-context text context))
   callback))

(defun yeah-service-ui-steer (&optional prompt)
  "Queue steering clarification PROMPT for the running service prompt.
Interactively, open the full steering composer."
  (interactive)
  (if prompt
      (yeah-service-ui--send-steering prompt nil)
    (yeah-journal-steer-command)))

(defun yeah-service-ui-withdraw (id)
  "Withdraw pending input ID from this service session."
  (interactive
   (let* ((pending (plist-get (yeah-service-ui--view) :pending-inputs))
          (choices (mapcar
                    (lambda (input)
                      (cons (format "%s: %s"
                                    (plist-get input :id)
                                    (truncate-string-to-width
                                     (or (plist-get input :prompt) "") 60))
                            (plist-get input :id)))
                    pending)))
     (unless choices
       (user-error "Yeah service: no pending input"))
     (cdr (assoc (completing-read "Withdraw service input: " choices nil t)
                 choices))))
  (unless (stringp id)
    (user-error "Yeah service: the pending input id must be text"))
  (yeah-service-ui--request-control
   "session/withdraw"
   (list :sessionId yeah-service-ui--session-id
         :inputId id)))

(defun yeah-service-ui-recover ()
  "Explicitly start the oldest pending input in this service session."
  (interactive)
  (yeah-service-ui--request-control
   "session/recover"
   (list :sessionId yeah-service-ui--session-id)))

(defun yeah-service-ui--export ()
  "Export this service journal as an Org file and open it."
  (let* ((session (list :id (or yeah-service-ui--session-id "service")
                        :path "service"
                        :records yeah-service-ui--records))
         (file (yeah-org-export-file session
                                     yeah-service-ui-export-directory)))
    (find-file file)))

(defun yeah-service-ui-export ()
  "Export this service journal as an Org file and open it."
  (interactive)
  (yeah-service-ui--export))

(defvar yeah-service-ui-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a") #'yeah-journal-ask-command)
    (define-key map (kbd "s") #'yeah-service-ui-steer)
    (define-key map (kbd "c") #'yeah-service-ui--cancel)
    (define-key map (kbd "r") #'yeah-service-ui-recover)
    (define-key map (kbd "w") #'yeah-service-ui-withdraw)
    map)
  "Keymap of the Yeah service buffer.")

(define-derived-mode yeah-service-ui-mode yeah-journal-mode "Yeah-Service"
  "A buffer driving a Yeah service Emacs."
  (set-keymap-parent yeah-service-ui-mode-map yeah-journal-mode-map)
  (define-key yeah-service-ui-mode-map (kbd "a") #'yeah-journal-ask-command)
  (define-key yeah-service-ui-mode-map (kbd "s") #'yeah-service-ui-steer)
  (define-key yeah-service-ui-mode-map (kbd "c") #'yeah-service-ui--cancel)
  (define-key yeah-service-ui-mode-map (kbd "r") #'yeah-service-ui-recover)
  (define-key yeah-service-ui-mode-map (kbd "w") #'yeah-service-ui-withdraw))

(defun yeah-service-ui--driver (journal)
  "Return the service driver for JOURNAL."
  (list :ask (lambda (text _context callback)
                (with-current-buffer (yeah-journal-buffer journal)
                  (yeah-service-ui--send-prompt text callback)))
        :steer (lambda (text context callback)
                 (with-current-buffer (yeah-journal-buffer journal)
                   (yeah-service-ui--send-steering text context callback)))
        :cancel (lambda (callback)
                  (with-current-buffer (yeah-journal-buffer journal)
                    (yeah-service-ui--cancel))
                  (when (functionp callback) (funcall callback t)))
        :export (lambda (callback)
                  (with-current-buffer (yeah-journal-buffer journal)
                    (yeah-service-ui--export))
                  (when (functionp callback) (funcall callback t)))
        :capabilities '(:ask :steer :cancel :export)))

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
           ("Auto — unattended, nobody answers" . "auto"))
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
    ;; The editor is a client of Yeah: it announces the events that ACP
    ;; does not have, so that it sees the queue of the session.  A client
    ;; that announces nothing is served plain ACP.
    (yeah-client-request client "initialize"
                         (list :protocolVersion yeah-acp-protocol-version
                               :clientCapabilities
                               (yeah-acp-queue-events-capabilities))
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
