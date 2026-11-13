;;; yeah-faces.el --- semantic presentation primitives -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Semantic faces and small string formatters shared by Yeah interfaces.
;; Icons are optional decoration: every formatter retains a readable text
;; label when a package, display, font or glyph is unavailable.  This module
;; does not change themes, global face attributes or keybindings.

;;; Code:

(require 'button)
(require 'subr-x)

(declare-function nerd-icons-codicon "nerd-icons" (icon-name &rest args))

(defgroup yeah-faces nil
  "Semantic faces and formatting for Yeah."
  :group 'yeah)

(defcustom yeah-icons 'auto
  "When Yeah may decorate text labels with icons.
With `auto', use `nerd-icons' only when it is available and the current
display can show the resulting glyph.  With `never', use text alone."
  :type '(choice (const :tag "Use displayable icons when available" auto)
                 (const :tag "Never use icons" never))
  :group 'yeah-faces)

(defface yeah-faces-user-heading
  '((t :inherit font-lock-keyword-face :weight bold))
  "Face for the heading of a person's message."
  :group 'yeah-faces)

(defface yeah-faces-assistant-heading
  '((t :inherit font-lock-function-name-face :weight bold))
  "Face for the heading of an assistant message."
  :group 'yeah-faces)

(defface yeah-faces-metadata
  '((t :inherit shadow))
  "Face for secondary session and event metadata."
  :group 'yeah-faces)

(defface yeah-faces-dimmed
  '((t :inherit shadow))
  "Face for deliberately de-emphasized text."
  :group 'yeah-faces)

(defface yeah-faces-tool-name
  '((t :inherit font-lock-function-name-face))
  "Face for tool names."
  :group 'yeah-faces)

(defface yeah-faces-pending
  '((t :inherit font-lock-type-face))
  "Face for work or input waiting for an answer."
  :group 'yeah-faces)

(defface yeah-faces-running
  '((t :inherit font-lock-keyword-face))
  "Face for active work."
  :group 'yeah-faces)

(defface yeah-faces-success
  '((t :inherit success))
  "Face for successful completion."
  :group 'yeah-faces)

(defface yeah-faces-warning
  '((t :inherit warning))
  "Face for warnings, refusals and interruptions."
  :group 'yeah-faces)

(defface yeah-faces-error
  '((t :inherit error))
  "Face for errors and failed work."
  :group 'yeah-faces)

(defface yeah-faces-code
  '((t :inherit (fixed-pitch font-lock-string-face)))
  "Face for inline code and code blocks."
  :group 'yeah-faces)

(defface yeah-faces-output
  '((t :inherit fixed-pitch))
  "Face for tool and process output."
  :group 'yeah-faces)

(defface yeah-faces-key-hint
  '((t :inherit help-key-binding))
  "Face for keyboard hints."
  :group 'yeah-faces)

(defface yeah-faces-button
  '((t :inherit button))
  "Face for local text buttons."
  :group 'yeah-faces)

(defconst yeah-faces--kind-specs
  '((user :face yeah-faces-user-heading :label "User" :icon "nf-cod-account")
    (assistant :face yeah-faces-assistant-heading :label "Assistant" :icon "nf-cod-hubot")
    (reasoning :face yeah-faces-dimmed :label "Reasoning" :icon "nf-cod-thinking")
    (metadata :face yeah-faces-metadata :label "Details" :icon "nf-cod-info")
    (dimmed :face yeah-faces-dimmed :label "Details")
    (tool :face yeah-faces-tool-name :label "Tool" :icon "nf-cod-tools")
    (pending :face yeah-faces-pending :label "Pending" :icon "nf-cod-watch")
    (running :face yeah-faces-running :label "Running" :icon "nf-cod-sync")
    (success :face yeah-faces-success :label "Success" :icon "nf-cod-check")
    (warning :face yeah-faces-warning :label "Warning" :icon "nf-cod-warning")
    (error :face yeah-faces-error :label "Error" :icon "nf-cod-error")
    (code :face yeah-faces-code :label "Code" :icon "nf-cod-code")
    (output :face yeah-faces-output :label "Output" :icon "nf-cod-output")
    (key-hint :face yeah-faces-key-hint :label "Key" :icon "nf-cod-record_keys")
    (button :face yeah-faces-button :label "Action"))
  "Presentation defaults indexed by normalized semantic kind.")

(defconst yeah-faces--status-kinds
  '((idle . metadata)
    (pending . pending)
    (queued . pending)
    (waiting . pending)
    (awaiting-user-permission . pending)
    (awaiting-user-input . pending)
    (blocked-on-rate . pending)
    (running . running)
    (deciding . running)
    (post-decide . running)
    (awaiting-tool . running)
    (accumulating . running)
    (compacting . running)
    (success . success)
    (done . success)
    (completed . success)
    (finished . success)
    (warning . warning)
    (cancelled . warning)
    (canceled . warning)
    (refused . warning)
    (denied . warning)
    (withdrawn . warning)
    (interrupted . warning)
    (error . error)
    (failed . error)
    (failure . error))
  "Map run and tool states to their semantic presentation kind.")

(defun yeah-faces--normalize-kind (kind)
  "Return KIND as a symbol, accepting keywords and strings."
  (let ((name (cond ((null kind) "unknown")
                    ((symbolp kind) (symbol-name kind))
                    ((stringp kind) kind)
                    (t (format "%s" kind)))))
    (intern (replace-regexp-in-string "\\`:" "" name))))

(defun yeah-faces--humanize (value &optional fallback)
  "Return VALUE as a readable label, or FALLBACK when VALUE is empty."
  (let ((name (string-trim
               (replace-regexp-in-string
                "[-_]+" " "
                (string-remove-prefix ":" (format "%s" (or value "")))))))
    (if (string-empty-p name)
        (or fallback "Item")
      (capitalize name))))

(defun yeah-faces--label-text (label fallback)
  "Return LABEL as text, using FALLBACK when LABEL is nil or blank."
  (let ((text (cond ((stringp label) label)
                    ((null label) "")
                    (t (format "%s" label)))))
    (if (string-match-p "\\`[[:space:]]*\\'" text)
        fallback
      text)))

(defun yeah-faces--kind-spec (kind)
  "Return the presentation plist for KIND."
  (let* ((normalized (yeah-faces--normalize-kind kind))
         (known (assq normalized yeah-faces--kind-specs)))
    (or (cdr known)
        (list :face 'default
              :label (yeah-faces--humanize normalized "Item")))))

(defun yeah-faces--icon-provider ()
  "Return the optional Nerd Icons provider when it is loadable."
  (and (or (featurep 'nerd-icons)
           (require 'nerd-icons nil t))
       (fboundp 'nerd-icons-codicon)
       #'nerd-icons-codicon))

(defun yeah-faces--icon (kind override face)
  "Return an icon for KIND with FACE, or nil when it is unavailable.
OVERRIDE is a literal icon string, `never', or nil for the default icon."
  (unless (or (eq yeah-icons 'never)
              (eq override 'never)
              (not (display-multi-font-p))
              (not (fboundp 'char-displayable-p)))
    (let ((glyph
           (cond
            ((stringp override) override)
            (override nil)
            (t
             (when-let ((name (plist-get (yeah-faces--kind-spec kind) :icon)))
               (when-let ((provider (yeah-faces--icon-provider)))
                 (condition-case nil
                     (funcall provider name :face face :height 1.0 :v-adjust 0.0)
                   (error nil))))))))
      (when (and (stringp glyph)
                 (not (string-empty-p glyph))
                 (condition-case nil
                     (char-displayable-p glyph)
                   (error nil)))
        (if (stringp override)
            (propertize glyph 'face face)
          glyph)))))

(defun yeah-faces-label (kind label &optional icon)
  "Return LABEL with the semantic face and optional icon for KIND.
KIND names a role or presentation state, such as `user', `assistant',
`tool', `metadata', `code', `output', `pending', `running', `success',
`warning' or `error'.  A nil or blank LABEL becomes a nonempty readable
default.  ICON is a literal icon string, `never' to suppress an icon for
this call, or nil to use KIND's optional Nerd Icon.  Text remains when the
icon package, display or glyph is unavailable."
  (let* ((spec (yeah-faces--kind-spec kind))
         (face (plist-get spec :face))
         (text (yeah-faces--label-text label (plist-get spec :label)))
         (plain (substring-no-properties text))
         (rendered (propertize text 'face face))
         (glyph (yeah-faces--icon kind icon face)))
    (propertize (if glyph
                    (concat glyph " " rendered)
                  rendered)
                'help-echo plain)))

(defun yeah-faces-status (state &optional label)
  "Return a readable status label for STATE.
STATE may be a run state or a tool outcome.  LABEL overrides the default
human-readable state name; a nil or blank LABEL still produces text.  The
semantic face and optional icon are additions, never the only indication
of state."
  (let* ((normalized (yeah-faces--normalize-kind state))
         (kind (or (cdr (assq normalized yeah-faces--status-kinds)) 'metadata))
         (text (yeah-faces--label-text
                label (yeah-faces--humanize normalized "Unknown")))
         (rendered (yeah-faces-label kind text)))
    (propertize rendered
                'help-echo (format "State: %s" (substring-no-properties text)))))

(defun yeah-faces-metadata (label &optional width)
  "Return single-line metadata LABEL with a dimmed face.
When WIDTH is a positive integer, limit the result to that many display
columns with an ellipsis.  The untruncated, unpropertized text is retained
in `help-echo'.  A nil or blank LABEL becomes \"Details\"."
  (when (and width (not (and (integerp width) (> width 0))))
    (user-error "yeah-faces: metadata width must be a positive integer"))
  (let* ((text (string-trim
                (replace-regexp-in-string
                 "[[:space:]]+" " "
                 (yeah-faces--label-text label "Details"))))
         (text (yeah-faces--label-text text "Details"))
         (plain (substring-no-properties text))
         (shown (if width
                    (truncate-string-to-width text width nil nil "…")
                  text)))
    (propertize shown 'face 'yeah-faces-metadata 'help-echo plain)))

(defun yeah-faces-button (label action &optional help-echo)
  "Return a local text button labelled LABEL that calls ACTION.
ACTION receives no arguments.  HELP-ECHO defaults to an activation hint.
A nil or blank LABEL becomes \"Action\".  The returned string carries its
own button keymap; no global keybinding or buffer is created or changed."
  (unless (functionp action)
    (user-error "yeah-faces: button action must be a function"))
  (let* ((text (yeah-faces--label-text label "Action"))
         (plain (substring-no-properties text))
         (hint (yeah-faces--label-text
                help-echo (format "Activate %s (RET or mouse-1)" plain)))
         (rendered (propertize text 'face 'yeah-faces-button)))
    (propertize
     (buttonize rendered (lambda (_button) (funcall action)) nil hint)
     'face 'yeah-faces-button)))

(provide 'yeah-faces)
;;; yeah-faces.el ends here
