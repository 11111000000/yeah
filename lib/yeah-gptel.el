;;; yeah-gptel.el --- private gptel transport adapter -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; This module is the only integration point between Yeah and gptel.  A
;; request carries its own backend, model, tools and system prompt; Yeah does
;; not install global hooks or change the user's global gptel configuration.
;;
;; gptel intentionally reads several request settings dynamically.  The
;; `let' bindings in `yeah-gptel-request' follow its public contract: they
;; give one request a frozen configuration without changing global values.

;;; Code:

(require 'cl-lib)
(require 'yeah-tools)
(require 'gptel nil t)

(declare-function gptel-request "gptel"
  (&optional prompt &key callback buffer position context dry-run
                    stream in-place system schema transforms fsm))
(declare-function gptel-make-tool "gptel" (&rest slots))
(defvar gptel-backend nil)
(defvar gptel-model nil)
(defvar gptel-tools nil)
(defvar gptel-include-reasoning nil)
(defvar gptel-use-context nil)
(defvar gptel-use-tools nil)
(defvar gptel-version nil)

(defgroup yeah-gptel nil
  "Yeah / private gptel transport adapter."
  :group 'yeah)

(defconst yeah-gptel--supported-versions '("0.9.9.5" "0.9.9.6")
  "gptel versions whose request contract has been checked by Yeah.")

(defcustom yeah-gptel-prelude
  (concat
   "# Yeah — system prompt\n\n"
   "You are an agent running inside Emacs through the Yeah harness. "
   "Use the advertised tools when they help complete the task. "
   "Tool execution is controlled by Yeah's permission system.\n")
  "Default system prompt for Yeah model requests."
  :type 'string
  :group 'yeah-gptel)

(defcustom yeah-gptel-include-reasoning t
  "How the model's reasoning is kept in the conversation.
A model that reasons narrates its plan, and dropping that plan from the
history makes the model start the task over on every turn.  Keep the
reasoning in the conversation by default; set this to nil to hide it.
The value is bound per request, never mutated globally."
  :type '(choice (const :tag "Keep the reasoning" t)
                 (const :tag "Hide it" nil))
  :group 'yeah-gptel)

(defun yeah-gptel--require-gptel (what)
  "Signal `user-error' unless gptel is available, naming WHAT wanted it."
  (unless (fboundp 'gptel-request)
    (signal 'user-error
            (list (format "yeah-gptel: %s needs gptel, which is not loaded" what))))
  t)

(defun yeah-gptel-check-contract ()
  "Validate the gptel contract used by Yeah.
Return t when the loaded gptel is supported.  Signal `user-error' for an
unknown version or missing request/tool bindings instead of silently
continuing with an incompatible transport."
  (yeah-gptel--require-gptel "yeah-gptel-check-contract")
  (unless (and (boundp 'gptel-version)
               (stringp gptel-version))
    (signal 'user-error
            (list "yeah-gptel: loaded gptel does not expose `gptel-version'")))
  (unless (member gptel-version yeah-gptel--supported-versions)
    (signal 'user-error
            (list (format "yeah-gptel: unsupported gptel version %S; supported: %s"
                          gptel-version
                          (string-join yeah-gptel--supported-versions ", ")))))
  (dolist (variable '(gptel-backend gptel-model gptel-tools
                      gptel-use-tools gptel-use-context))
    (unless (boundp variable)
      (signal 'user-error
              (list (format "yeah-gptel: gptel %s does not bind %S"
                            gptel-version variable)))))
  (unless (fboundp 'gptel-make-tool)
    (signal 'user-error
            (list (format "yeah-gptel: gptel %s does not define `gptel-make-tool'"
                          gptel-version))))
  t)

(defun yeah-gptel--argument-type (type)
  "Return the JSON Schema type name for registry TYPE."
  (pcase type
    ('string  "string")
    ('integer "integer")
    ('boolean "boolean")
    ('symbol  "string")
    (_        "string")))

(defun yeah-gptel-tool-for (name)
  "Return a gptel tool description for registry tool NAME.
The confirmation function always returns true, so gptel returns tool calls
to Yeah's callback instead of executing them outside Yeah's permission and
logging path."
  (yeah-gptel--require-gptel "yeah-gptel-tool-for")
  (unless (fboundp 'gptel-make-tool)
    (signal 'user-error (list "yeah-gptel-tool-for: gptel-make-tool is unavailable")))
  (let ((spec (yeah-tools-get name)))
    (unless spec
      (signal 'user-error
              (list (format "yeah-gptel-tool-for: no such tool: %S" name))))
    (gptel-make-tool
     :name name
     :function (lambda (&rest args)
                 (yeah-tools-call name (yeah-tools-normalize-args name args)))
     :description (plist-get spec :description)
     :args (mapcar (lambda (param)
                     (list :name (plist-get param :name)
                           :description (format "the %s argument"
                                                 (plist-get param :name))
                           :type (yeah-gptel--argument-type
                                  (plist-get param :type))))
                   (plist-get spec :input))
     :confirm (lambda (&rest _args) t))))

(defun yeah-gptel--request-tools (tools)
  "Resolve the request TOOLS option.
`registry' builds tools from Yeah's registry, nil disables tools, and a list
is used as an explicit list of gptel tool objects."
  (pcase tools
    ('registry (mapcar #'yeah-gptel-tool-for (yeah-tools-names)))
    ('nil nil)
    ((pred listp) tools)
    (_ (signal 'user-error
               (list (format "yeah-gptel-request: invalid tools option: %S" tools))))))

(defun yeah-gptel--usage (info)
  "Return normalized token usage from request INFO, or nil when unavailable."
  (when-let ((tokens (plist-get info :tokens)))
    (list :input (and (numberp (plist-get tokens :input))
                      (plist-get tokens :input))
          :output (and (numberp (plist-get tokens :output))
                       (plist-get tokens :output))
          :cache (and (numberp (plist-get tokens :cache))
                      (plist-get tokens :cache))
          :cached (and (numberp (plist-get tokens :cached))
                       (plist-get tokens :cached)))))

(defun yeah-gptel--failure-reason (info)
  "Return a printable provider failure reason from request INFO."
  (let ((reason (or (plist-get info :error)
                    (plist-get info :status)
                    "no response")))
    (if (stringp reason) reason (format "%S" reason))))

(defun yeah-gptel--normalize-response (response info)
  "Normalize gptel RESPONSE and INFO for Yeah's run loop.
Text, reasoning, tool calls/results and the streaming sentinel t retain
gptel's public shapes.  Failures and unknown shapes become `(error . REASON)'."
  (cond
   ((or (stringp response) (eq response t)) response)
   ((and (consp response)
         (memq (car response) '(reasoning tool-call tool-result)))
    response)
   ((eq response 'abort) (cons 'error "the model request was aborted"))
   ((null response) (cons 'error (yeah-gptel--failure-reason info)))
   (t (cons 'error (format "unsupported gptel response shape: %S" response)))))

(defun yeah-gptel--callback (callback response info)
  "Deliver normalized RESPONSE and INFO to CALLBACK."
  (let ((normalized-info (and (listp info) (copy-sequence info))))
    (when-let ((usage (yeah-gptel--usage info)))
      (setq normalized-info (plist-put normalized-info :yeah-usage usage)))
    (funcall callback
             (yeah-gptel--normalize-response response info)
             normalized-info)))

;;;###autoload
(cl-defun yeah-gptel-request
    (prompt callback &key backend model (tools 'registry)
                    (system yeah-gptel-prelude) stream context dry-run)
  "Ask the model PROMPT and call CALLBACK with its response and request info.

This is the only place in Yeah that calls `gptel-request'.  BACKEND and MODEL
default to the user's current gptel choices.  TOOLS is `registry' for Yeah's
registered tools, nil for no tools, or an explicit list of gptel tools.
SYSTEM defaults to `yeah-gptel-prelude' and may be nil.  STREAM, CONTEXT and
DRY-RUN have the meanings documented by `gptel-request'.

Responses retain gptel's text/reasoning/tool shapes; failures become
`(error . REASON)'.  When usage is available, CALLBACK's info contains
`:yeah-usage' with normalized input/output/cache/cached counts.

The configuration is captured for this request only.  Global gptel settings
are not modified and ambient gptel editor context is disabled.  The return
value is gptel's request state machine, which can be inspected or aborted."
  (unless (functionp callback)
    (signal 'user-error
            (list (format "yeah-gptel-request: callback is not a function: %S"
                          callback))))
  (yeah-gptel-check-contract)
  (let* ((request-tools (yeah-gptel--request-tools tools))
         (gptel-backend (or backend gptel-backend))
         (gptel-model (or model gptel-model))
         (gptel-tools request-tools)
         (gptel-use-tools (and request-tools t))
         (gptel-use-context nil)
         (gptel-include-reasoning yeah-gptel-include-reasoning))
    (gptel-request prompt
                   :callback (lambda (response info)
                               (yeah-gptel--callback callback response info))
                   :system system
                   :stream stream
                   :context context
                   :dry-run dry-run)))

(defun yeah-gptel-bind-tools (&optional buffer)
  "Advertise Yeah's registry as buffer-local gptel tools in BUFFER.
This helper is for interactive gptel buffers only.  `yeah-gptel-request'
passes its own tools directly and does not depend on this buffer state."
  (yeah-gptel--require-gptel "yeah-gptel-bind-tools")
  (with-current-buffer (or buffer (current-buffer))
    (setq-local gptel-tools
                (mapcar #'yeah-gptel-tool-for (yeah-tools-names)))))

(provide 'yeah-gptel)
;;; yeah-gptel.el ends here
