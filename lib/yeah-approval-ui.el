;;; yeah-approval-ui.el --- approve or refuse one Yeah tool call -*- lexical-binding: t -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.

;;; Commentary:
;;
;; A permission request is a decision about one concrete effect.  This
;; module shows the action, resource, arguments, and a read-only diff when
;; one can be computed.
;;
;; The answer is one of the answers of the kernel: `once', `session',
;; `project', `global' or `reject'.  The view names what every answer
;; allows, so that the person reads the scope of the answer and not only
;; the word "allow".  The kernel decides what the answers mean: the scope
;; of the answer is the scope of the carrier of the path that asks, and
;; the answer `global' is the file of the user.
;;
;; The legacy name `always' is still accepted: it is the answer `session',
;; the scope of the path that asks.

;;; Code:

(require 'cl-lib)
(require 'yeah-approval)
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

(defconst yeah-approval--keys
  '((:once . "o") (:session . "s") (:project . "p")
    (:global . "a") (:reject . "r"))
  "The key every answer of the view is offered under.

The table holds the keys of the surface and not the answers: the answers
are read from the dictionary of the kernel, and the view offers every
answer of that dictionary.  The answer `global' is offered under the key
of the forever of the person.")

(defun yeah-approval--key-of (answer)
  "Return the key the view offers ANSWER under, or nil when it has none."
  (let ((entry (assq answer yeah-approval--keys)))
    (and entry (cdr entry))))

(defun yeah-approval--offers ()
  "Return the offers of the view: every answer of the kernel and its words.
The answers are read from the one dictionary of the kernel, and this
module writes none of them again."
  (mapcar (lambda (answer)
            (list :answer answer
                  :key (yeah-approval--key-of answer)
                  :label (yeah-approval-label answer)))
          (yeah-approval-reply-kinds)))

(defun yeah-approval--offer-line (offer)
  "Return the line of the view that names OFFER."
  (format "%s %s"
          (or (plist-get offer :key) " ")
          (plist-get offer :label)))

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
           "\nWhat this allows\n"
           (mapconcat (lambda (offer)
                        (concat "  " (yeah-approval--offer-line offer) "\n"))
                      (yeah-approval--offers)
                      "")
           (if (plist-get preview :ok)
               (concat "\nPreview\n" (plist-get preview :text))
             (concat "\n"
                     (format "No read-only preview is available: %s\n"
                             (or (plist-get preview :error)
                                 "this tool has no diff preview")))))))
    (propertize text 'face 'default)))

(defun yeah-approval--decide (reply)
  "Decide the current approval with REPLY.
REPLY is one of the answers of the kernel; the legacy name `always' is
the answer `session' and is accepted as well."
  (unless (derived-mode-p 'yeah-approval-mode)
    (user-error "Not in a Yeah approval"))
  (when yeah-approval--decided
    (user-error "This request has already been answered"))
  (unless (yeah-approval-reply-p reply)
    (user-error "Unknown approval reply: %S" reply))
  (let ((callback yeah-approval--callback))
    (setf yeah-approval--decided t)
    (when (functionp callback)
      (funcall callback reply)))
  (kill-buffer (current-buffer)))

(defun yeah-approval-allow-once ()
  "Allow the current tool call once.
The answer is forgotten: nothing is written into the rules."
  (interactive)
  (yeah-approval--decide :once))

(defun yeah-approval-allow-session ()
  "Allow the current action for the session of the path that asks.
The rule is written into the carrier of that path: the rules of the run
of an attached run, the rules of the session of an ACP session, and the
file of the user in the plain path, which has no session of its own."
  (interactive)
  (yeah-approval--decide :session))

(defun yeah-approval-allow-project ()
  "Allow the current action for the project of the person.
The rule is written into the file of the project, and into no other
carrier."
  (interactive)
  (yeah-approval--decide :project))

(defun yeah-approval-allow-always ()
  "Allow the current action always.
The rule is written into the file of the user: the answer `global' is
the forever of the person.  The legacy name `always' is the answer
`session', the scope of the path that asks, and it is not this answer."
  (interactive)
  (yeah-approval--decide :global))

(defun yeah-approval-reject ()
  "Reject the current tool call.
The refusal is forgotten: nothing is written into the rules."
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
    (define-key map (kbd "s") #'yeah-approval-allow-session)
    (define-key map (kbd "p") #'yeah-approval-allow-project)
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
CALLBACK is called with the answer of the person; the answers are the
ones `yeah-approval-reply-kinds' returns, and this module writes none
of them again."
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
                  (propertize
                   (mapconcat #'yeah-approval--offer-line
                              (yeah-approval--offers)
                              " · ")
                   'face 'help-key-binding)))
      (force-mode-line-update))
    (pop-to-buffer buffer)
    buffer))

;;;###autoload
(defun yeah-approval-answer (request)
  "Ask the person about REQUEST in the approval view and return the decision.
The decision carries the answer of the person as `:reply': one of the
five answers of the kernel.  A request that nobody answers is refused:
a question with no answer may not become an effect."
  (let ((decision nil))
    (yeah-approval-open
     request
     (lambda (reply)
       (setq decision
             (if (eq (yeah-approval-reply-canonical reply) :reject)
                 (list :effect :deny :reply :reject
                       :reason "rejected by the person")
               (list :effect :allow :reply reply)))))
    (let ((deadline (+ (float-time) 600)))
      (while (and (null decision) (< (float-time) deadline))
        (accept-process-output nil 0.1)))
    (or decision
        (list :effect :deny :reply :reject
              :reason "the person did not answer the request"))))

(provide 'yeah-approval-ui)
;;; yeah-approval-ui.el ends here
