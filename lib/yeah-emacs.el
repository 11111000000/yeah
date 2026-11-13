;;; yeah-emacs.el --- introspection and live editor tools -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; Tools that expose Emacs itself: live buffers, documentation/source,
;; non-evaluating Elisp reader checks and Flymake diagnostics.  Variable
;; values are deliberately not printed by introspection because they may
;; contain credentials or other private state.

;;; Code:

(require 'cl-lib)
(require 'yeah-result)

(declare-function find-function-noselect "find-func"
                  (symbol &optional switch-to-buffer))
(declare-function flymake-diagnostics "flymake" (&optional beg end))
(declare-function flymake-diagnostic-type "flymake" (diag))
(declare-function flymake-diagnostic-text "flymake" (diag))
(declare-function flymake-diagnostic-beg "flymake" (diag))
(declare-function flymake-diagnostic-end "flymake" (diag))
(defvar flymake-mode)
(defvar read-eval)

(defun yeah-emacs--documentation (symbol)
  "Return bounded documentation and source metadata for SYMBOL."
  (let* ((kind (cond ((fboundp symbol) "function")
                     ((boundp symbol) "variable")
                     (t nil)))
         (file (and kind (symbol-file symbol))))
    (unless kind
      (signal 'user-error
              (list (format "yeah-introspect: unknown function or variable: %S"
                            symbol))))
    (list :kind kind
          :file file
          :text (format "%s\nType: %s\nSource: %s\n\n%s"
                        symbol kind (or file "unknown")
                        (or (and (equal kind "function") (documentation symbol))
                            (and (equal kind "variable")
                                 (documentation-property symbol
                                                         'variable-documentation))
                            "No documentation available.")))))

(defun yeah-emacs--function-source (symbol)
  "Return the source form of function SYMBOL without evaluating it."
  (unless (fboundp symbol)
    (signal 'user-error
            (list (format "yeah-introspect: not a function: %S" symbol))))
  (let ((location (find-function-noselect symbol)))
    (with-current-buffer (car location)
      (save-excursion
        (goto-char (cdr location))
        (let ((start (point)))
          (forward-sexp)
          (buffer-substring-no-properties start (point)))))))

(defun yeah-emacs-introspect (name &optional kind)
  "Return documentation, source or matching symbols for NAME.
KIND is `function', `variable', `source' or `apropos' (the default is
`function').  No variable values are returned."
  (let ((kind (or kind "function")))
    (condition-case err
        (pcase kind
          ("apropos"
           (let* ((symbols (sort (mapcar #'symbol-name
                                        (apropos-internal name))
                                 #'string<))
                  (limited (seq-take symbols 100)))
             (yeah-result-from-output
              (mapconcat #'identity limited "\n")
              nil
              (list :query name :count (length symbols)
                    :returned (length limited)))))
          ((or "function" "variable")
           (let ((info (yeah-emacs--documentation (intern name))))
             (yeah-result-from-output
              (plist-get info :text) nil
              (list :name name :kind (plist-get info :kind)
                    :file (plist-get info :file)))))
          ("source"
           (yeah-result-from-output
            (yeah-emacs--function-source (intern name)) nil
            (list :name name :kind "source")))
          (_ (yeah-result-error
              (format "unknown introspection kind: %s" kind))))
      (error (yeah-result-error (error-message-string err))))))

(defun yeah-emacs-elisp-check (path)
  "Read PATH without evaluation and report reader/parenthesis validity."
  (condition-case err
      (let ((absolute (expand-file-name path))
            (forms 0))
        (unless (file-regular-p absolute)
          (signal 'user-error (list (format "not a regular file: %s" path))))
        (when (> (file-attribute-size (file-attributes absolute))
                 (* 2 1024 1024))
          (signal 'user-error (list "yeah-elisp-check: file exceeds 2 MiB")))
        (with-temp-buffer
          (insert-file-contents absolute)
          (goto-char (point-min))
          (check-parens)
          (goto-char (point-min))
          (let ((read-eval nil)
                (done nil))
            (while (not done)
              (condition-case nil
                  (progn (read (current-buffer)) (setq forms (1+ forms)))
                (end-of-file (setq done t))))))
        (yeah-result-ok
         (format "OK: %d forms read; parentheses are balanced." forms)
         (list :path absolute :forms forms)))
    (error
     (yeah-result-error (error-message-string err)))))

(defun yeah-emacs-buffer-read (name &optional offset limit widen)
  "Read live buffer NAME by lines and return its modification tick.
OFFSET is 1-based and LIMIT defaults to 2000 lines.  WIDEN non-nil explicitly
permits reading beyond the current narrowing."
  (let ((offset (or offset 1))
        (limit (or limit 2000))
        (buffer (get-buffer name)))
    (cond
     ((not (buffer-live-p buffer))
      (yeah-result-error (format "no live buffer named %s" name)))
     ((or (< offset 1) (< limit 1))
      (yeah-result-error "offset and limit must be positive"))
     (t
      (with-current-buffer buffer
        (save-restriction
          (when widen (widen))
          (let* ((tick (buffer-chars-modified-tick))
                 (total (count-lines (point-min) (point-max)))
                 (start (save-excursion
                          (goto-char (point-min))
                          (forward-line (1- offset))
                          (point)))
                 (end (save-excursion
                        (goto-char start)
                        (forward-line limit)
                        (point))))
            (yeah-result-ok
             (buffer-substring-no-properties start end)
             (list :buffer name :offset offset :limit limit
                   :total-lines total :tick tick
                   :truncated (< end (point-max)))))))))))

(defun yeah-emacs-diagnostics (&optional path)
  "Return Flymake diagnostics for PATH or the current buffer.
PATH must already have a visiting buffer; this tool does not open files or
start a language server."
  (let ((buffer (if path (find-buffer-visiting (expand-file-name path))
                  (current-buffer))))
    (cond
     ((not (buffer-live-p buffer))
      (yeah-result-error "diagnostics require an existing visiting buffer"))
     ((not (and (boundp 'flymake-mode) flymake-mode
                (fboundp 'flymake-diagnostics)))
      (yeah-result-error
       (format "Flymake is not active in %s" (buffer-name buffer))))
     (t
      (with-current-buffer buffer
        (let* ((diagnostics (flymake-diagnostics))
               (lines
                (mapcar
                 (lambda (diag)
                   (let ((beg (flymake-diagnostic-beg diag))
                         (end (flymake-diagnostic-end diag)))
                     (format "%s:%d:%d: %s: %s"
                             (buffer-name)
                             (line-number-at-pos beg)
                             (max 0 (- end beg))
                             (flymake-diagnostic-type diag)
                             (flymake-diagnostic-text diag))))
                 diagnostics)))
          (yeah-result-from-output
           (if lines (mapconcat #'identity lines "\n")
             "No diagnostics.")
           nil
           (list :buffer (buffer-name) :count (length diagnostics)))))))))

(defun yeah-emacs-tools ()
  "Return the built-in Emacs capability tool specifications."
  (list
   (list :name "introspect"
         :description "Look up the Emacs documentation, source or matching symbols for a symbol; no variable values are returned."
         :input (list (list :name "symbol" :type 'string)
                      (list :name "kind" :type 'string :optional t))
         :handler #'yeah-emacs-introspect)
   (list :name "buffer-read"
         :description "Read the content of a live Emacs buffer by its buffer name, from a 1-based line offset, up to a line limit. Use it for a buffer that is open in this Emacs."
         :input (list (list :name "name" :type 'string)
                      (list :name "offset" :type 'integer :optional t)
                      (list :name "limit" :type 'integer :optional t)
                      (list :name "widen" :type 'boolean :optional t))
         :handler #'yeah-emacs-buffer-read)
   (list :name "elisp-check"
         :description "Check that an Elisp source parses: reader syntax and balanced parentheses, without evaluating any form."
         :input (list (list :name "path" :type 'string))
         :handler #'yeah-emacs-elisp-check)
   (list :name "diagnostics"
         :description "Return the Flymake/Eglot diagnostics of a buffer that visits a path, or of the current buffer; it returns the diagnostics, not the content of the buffer."
         :input (list (list :name "path" :type 'string :optional t))
         :handler #'yeah-emacs-diagnostics)))

(provide 'yeah-emacs)
;;; yeah-emacs.el ends here
