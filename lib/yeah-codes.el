;;; yeah-codes.el --- Tier 4 #22 PTC sandbox (stub) -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The Programmatic Tool Calling (PTC) sandbox is the answer to
;; "save round-trips" in opencode / pi. The model issues several
;; tool calls in one turn as a single Elisp form; we execute the
;; form inside a sandboxed environment. The contract is fixed by
;; `decisions/sandbox-elisp-codes-mode@0': the sandbox is
;; `sandbox.el' (Emacs 29+) plus a static whitelist of allowed
;; bindings; values cross the boundary as JSON-clean `read'/
;; `prin1' pairs; the boundary is a `let'-binding, not a
;; function call.
;;
;; This file lands a **stub** for the public API. The whitelist
;; gate and the JSON-clean boundary are real; the underlying
;; `sandbox.el' integration is deferred until an Emacs 29+ CI
;; target exists. The stub evaluates each form in a `let' that
;; exposes the whitelisted names plus INPUTS as lexical
;; bindings. See `decisions/codes-impl@0' for the full
;; commitment and reversal path.

;;; Code:

(require 'cl-lib)

(defgroup yeah-codes nil
  "The Yeah Programmatic Tool Calling (PTC) sandbox."
  :group 'yeah)

(defvar yeah-codes--whitelist
  '( "read" "edit" "grep" "glob" "bash" "webfetch" "text" "image" "console" "exit")
  "List of currently-allowed PTC binding names, in canonical order.

These are the names the model may pass as `:name' to
`yeah-codes-eval'. The default list is the ten names fixed
by `decisions/sandbox-elisp-codes-mode@0'. Mutations go
through `yeah-codes-allow' / `yeah-codes-disallow' so the
order stays canonical. Rebind with `setq', not `let',
per `ELISP_BEST_PRACTICES.md §11.1'.")

(defun yeah-codes-whitelist ()
  "Return the list of PTC binding names currently allowed.

The order matches the canonical whitelist fixed by
`decisions/sandbox-elisp-codes-mode@0'. Mutate through
`yeah-codes-allow' / `yeah-codes-disallow'; do not push to
the returned list directly."
  (declare (pure t) (side-effect-free t))
  yeah-codes--whitelist)

(defun yeah-codes--whitelist-member (name)
  "Non-nil if NAME (a string) is in `yeah-codes--whitelist'."
  (member name yeah-codes--whitelist))

(defun yeah-codes--string-p-or-error (name)
  "Signal `user-error' unless NAME is a non-empty string.
Return NAME when valid."
  (unless (stringp name)
    (signal 'user-error
            (list (format "yeah-codes: NAME must be a string, got %S"
                          (type-of name)))))
  (when (= (length name) 0)
    (signal 'user-error
            (list "yeah-codes: NAME must be a non-empty string")))
  name)

(defun yeah-codes-allow (name)
  "Add NAME to the PTC whitelist. Return the new whitelist.

Duplicates are silently absorbed; the whitelist is not
reordered. NAME must be a non-empty string; any other shape
raises `user-error'."
  (yeah-codes--string-p-or-error name)
  (unless (yeah-codes--whitelist-member name)
    (setq yeah-codes--whitelist
          (append yeah-codes--whitelist (list name))))
  yeah-codes--whitelist)

(defun yeah-codes-disallow (name)
  "Remove NAME from the PTC whitelist. Return the new whitelist.

No-op if NAME is absent. NAME must be a string; any other
shape raises `user-error'."
  (yeah-codes--string-p-or-error name)
  (setq yeah-codes--whitelist
        (cl-remove name yeah-codes--whitelist :test 'string=))
  yeah-codes--whitelist)

(defun yeah-codes--plist-name (form)
  "Return the `:name' string of FORM, or `user-error' if missing/wrong."
  (let ((name (plist-get form :name)))
    (unless (stringp name)
      (signal 'user-error
              (list (format "yeah-codes-eval: each form needs :name string, got %S"
                            form))))
    name))

(defun yeah-codes--read-form (code)
  "Parse CODE (a string) as a single body form. Raise `user-error'.

The body is wrapped in parens before `read' so that the
parser sees a list. Read errors of any flavour
(`scan-error', `end-of-file', `invalid-read-syntax',
`wrong-type-argument') are mapped to a single
`user-error' signal so nothing leaks past the boundary."
  (condition-case err
      (car (read (concat "(" code ")")))
    ((scan-error end-of-file invalid-read-syntax wrong-type-argument)
     (signal 'user-error
             (list (format "yeah-codes-eval: malformed form: %S (%S)"
                           code err))))))

(defun yeah-codes--json-roundtrip (value)
  "Return `read'/`prin1' round-trip of VALUE.

The result is `equal' to VALUE for every JSON-clean value:
atoms, lists, strings, numbers, the standard t/nil. This is
the `sandbox-elisp-codes-mode@0' boundary: nothing leaves
the sandbox that hasn't been prin1/read round-tripped."
  (read (prin1-to-string value)))

(defun yeah-codes--input-binding (cell)
  "Return the (SYMBOL VALUE) binding cell for one INPUTS cell.

INPUTS cell has shape `(KEY . ANY)'. KEY is a string or
symbol; the result uses a symbol. VALUE is `prin1'/`read'
round-tripped so the boundary is JSON-clean. The result is
a two-element **list** `(NAME VALUE)', not a dotted pair; a
`let' binding list requires proper lists, not dotted pairs."
  (let* ((key (car cell))
         (sym (if (symbolp key) key
                (intern key)))
         (val (cdr cell)))
    (list sym (yeah-codes--json-roundtrip val))))

(defun yeah-codes--eval-one (form inputs)
  "Evaluate one FORM. Return `(:name ... :result ... :ok t)'.

FORM is a plist (:name NAME :code CODE). INPUTS is the full
alist. NAME is whitelisted at the caller (`yeah-codes-eval').
CODE is parsed, wrapped in a `let' that binds INPUTS, then
`eval'd. The result is prin1/read round-tripped."
  (let* ((name (yeah-codes--plist-name form))
         (code (plist-get form :code))
         (bindings (mapcar #'yeah-codes--input-binding inputs))
         (body (yeah-codes--read-form code)))
    (let ((result
           (eval `(let ,bindings ,body)
                 lexical-binding)))
      (list :name name
            :result (yeah-codes--json-roundtrip result)
            :ok t))))

(defun yeah-codes-eval (form-alist &optional inputs)
  "Evaluate every form in FORM-ALIST inside the PTC sandbox.

FORM-ALIST is a list of plists, each of shape
`(:name NAME :code CODE)', where NAME is a string naming the
PTC binding being invoked and CODE is a string holding the
Elisp body. INPUTS is an alist of `((KEY . VALUE) ...)' that
pre-binds KEY as a lexical variable before the form runs.

Return a list of plists, one per input form, each of shape
`(:name NAME :result VALUE :ok t)'. The list order matches
FORM-ALIST. Every VALUE is `read'/`prin1' round-tripped
(JSON-clean).

Hard-error cases (each raises `user-error'):

  * a FORM-ALIST entry whose `:name' is not in the whitelist;
  * a FORM-ALIST entry whose `:code' fails `read';
  * a non-string NAME in FORM-ALIST or INPUTS.

Soft-error cases (the offending form gets `:ok nil' under the
gate above; in this stub they raise `user-error' too) are not
differentiated; the boundary is uniform."
  (unless (listp form-alist)
    (signal 'user-error
            (list (format "yeah-codes-eval: FORM-ALIST must be a list, got %S"
                          (type-of form-alist)))))
  (let ((err nil)
        (i 0))
    (while (and (null err) (< i (length form-alist)))
      (let* ((form (nth i form-alist))
             (name (and (consp form) (plist-get form :name))))
        (when (and (stringp name)
                   (not (yeah-codes--whitelist-member name)))
          (setq err (format "form #%d: %S is not in the whitelist"
                            (1+ i) name))))
      (setq i (1+ i)))
    (when err
      (signal 'user-error (list (concat "yeah-codes-eval: " err)))))
  (mapcar (lambda (form) (yeah-codes--eval-one form (or inputs '())))
          form-alist))

(defun yeah-codes-sandbox-available-p ()
  "Non-nil if the `sandbox' feature is loaded or loadable.

In this stub, the check is `(featurep \\='sandbox)'. The real
`sandbox.el' integration lands in `codes-impl@1', at which
point this function attempts `(require \\='sandbox nil t)'
before falling back to `featurep'."
  (declare (pure t) (side-effect-free t))
  (featurep 'sandbox))

(provide 'yeah-codes)
;;; yeah-codes.el ends here
