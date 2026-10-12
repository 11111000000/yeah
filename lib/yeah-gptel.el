;;; yeah-gptel.el --- gptel transport bridge -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; The single integration point between Yeah and the gptel
;; transport (see `decisions/gptel-as-transport.yaml'). This
;; module is the *only* place in Yeah that registers gptel hooks
;; and the *only* place that calls `gptel-request-...'. Every
;; other module that needs to talk to the model goes through
;; the hook surface installed here.
;;
;; The three hooks (one per `gptel-...' variable) are:
;;
;;   * `gptel-prompt-transform-functions' — augmented with
;;     `yeah-gptel-prompt-transform', which prepends the Yeah
;;     system-prompt prelude (tools, FSM states, manifesto).
;;
;;   * `gptel-pre-tool-call-functions' — augmented with
;;     `yeah-gptel-pre-tool-call', which currently passes the
;;     call through unchanged. Real wiring lands in Tier 3
;;     alongside `lib/yeah-tools.el' and `lib/yeah-perm.el'.
;;
;;   * `gptel-fsm-handlers' — augmented with
;;     `yeah-gptel-fsm-handler', which records the state
;;     transition in the current session. In revision 0 the
;;     recording is a `message' echo; the future hook into
;;     `lib/yeah-session.el' is documented inline.
;;
;; When `gptel' is not loaded, the install/uninstall functions
;; are no-ops that catch `void-function' and `void-variable'
;; so that Yeah can boot in environments without gptel (CI,
;; tests). See `decisions/gptel-hook-surface.yaml'.

;;; Code:

(require 'cl-lib)

(defgroup yeah-gptel nil
  "Yeah / gptel transport bridge."
  :group 'yeah)

(defcustom yeah-gptel-prelude
  (concat
   "# Yeah — system prompt\n"
   "\n"
   "You are an agent of the Yeah runtime. The agent loop is a\n"
   "deterministic finite state machine with 12 states (see\n"
   "`lib/yeah-state.el'). Your tool calls must conform to the\n"
   "schemas exposed via `lib/yeah-tools.el' (Tier 3).\n"
   "\n"
   "Manifesto: stay within Emacs, route all LLM traffic through\n"
   "the gptel hook surface, and never bypass the permission\n"
   "system.\n")
  "The Yeah system-prompt prelude prepended by `yeah-gptel-prompt-transform'.
Configure with `setq' or `customize-set-variable'; not via `let'-binding."
  :type 'string
  :group 'yeah-gptel)

(defvar yeah-gptel--installed nil
  "Non-nil when the three gptel hooks are currently registered.
Internal flag for idempotent install/uninstall.")

(defun yeah-gptel--safe-add-hook (hook function)
  "Add FUNCTION to HOOK when HOOK is a bound variable.
Returns t on success, nil when HOOK is unbound. Catches
`void-variable' for the case where gptel is not loaded."
  (condition-case nil
      (progn
        (add-hook hook function)
        t)
    (void-variable nil)
    (void-function nil)))

(defun yeah-gptel--safe-remove-hook (hook function)
  "Remove FUNCTION from HOOK when HOOK is a bound variable.
Returns t on success, nil when HOOK is unbound. Catches
`void-variable' for the case where gptel is not loaded."
  (condition-case nil
      (progn
        (remove-hook hook function)
        t)
    (void-variable nil)
    (void-function nil)))

(defun yeah-gptel-prompt-transform (prompt _info)
  "Prepend the Yeah prelude to PROMPT before each gptel turn.
_INFO is the gptel request info plist; unused in revision 0.
The prelude advertises the tools, FSM states, and manifesto."
  (declare (pure t) (side-effect-free t))
  (concat yeah-gptel-prelude prompt))

(defun yeah-gptel-pre-tool-call (call)
  "Wrap a gptel tool CALL before dispatch.
In revision 0 the wrapper is a passthrough: the call is returned
unchanged after a debug `message'. Real wiring (permission
checks, tool-registry lookup, per-tool pre-conditions) lands
in Tier 3 alongside `lib/yeah-tools.el' and `lib/yeah-perm.el'."
  (message "yeah-gptel: pre-tool-call %S" call)
  call)

(defun yeah-gptel-fsm-handler (_event state)
  "Record the gptel FSM STATE transition.
In revision 0 the recording is a `message' echo. The future
hook is `yeah-session-record' (defined in `lib/yeah-session.el',
Tier 3); when that module lands, replace the `message` below
with `(yeah-session-record (list :event _event :state state))'.
The argument shapes accepted today are `(:state STATE)' and
`(:transition FROM TO)'."
  (message "yeah-gptel: fsm-handler state=%S" state))

(defun yeah-gptel-hooks-install ()
  "Register the three gptel hook functions on `gptel-...' variables.
Idempotent: a second call is a no-op. Catches `void-variable'
and `void-function' so that Yeah can boot in environments
without gptel loaded."
  (if yeah-gptel--installed
      nil
    (let ((installed
           (and (yeah-gptel--safe-add-hook
                 'gptel-prompt-transform-functions
                 #'yeah-gptel-prompt-transform)
                (yeah-gptel--safe-add-hook
                 'gptel-pre-tool-call-functions
                 #'yeah-gptel-pre-tool-call)
                (yeah-gptel--safe-add-hook
                 'gptel-fsm-handlers
                 #'yeah-gptel-fsm-handler))))
      (when installed
        (setq yeah-gptel--installed t))
      installed)))

(defun yeah-gptel-hooks-uninstall ()
  "Remove the three gptel hook functions registered by
`yeah-gptel-hooks-install'. Idempotent: a second call is a
no-op. Catches `void-variable' and `void-function' so the
function is safe to call without gptel loaded."
  (if (not yeah-gptel--installed)
      nil
    (prog1 nil
      (yeah-gptel--safe-remove-hook
       'gptel-prompt-transform-functions
       #'yeah-gptel-prompt-transform)
      (yeah-gptel--safe-remove-hook
       'gptel-pre-tool-call-functions
       #'yeah-gptel-pre-tool-call)
      (yeah-gptel--safe-remove-hook
       'gptel-fsm-handlers
       #'yeah-gptel-fsm-handler)
      (setq yeah-gptel--installed nil))))

(provide 'yeah-gptel)
;;; yeah-gptel.el ends here