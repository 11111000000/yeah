;;; yeah-shell.el --- the *yeah-shell* REPL buffer -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; The Yeah shell is a `shell-mode'-like REPL buffer that sends
;; user input to the agent loop. It is intentionally a thin
;; wrapper: a buffer with a prompt, history through `savehist',
;; and a `yeah-shell-send-input' command. The actual gptel
;; call lives behind that command and lands in a later revision.

;;; Code:

(require 'cl-lib)
(require 'ring)

(defgroup yeah-shell nil
  "Yeah — the *yeah-shell* REPL."
  :group 'tools)

(defvar yeah-shell--buffer-name "*yeah-shell*"
  "Name of the Yeah REPL buffer.")

(defvar yeah-shell--prompt "yeah> "
  "Prompt string for the Yeah REPL.")

(defvar yeah-shell--history (make-ring 200)
  "History ring for Yeah REPL input. Bounded size; oldest
entries are dropped as new ones are added.")

(defun yeah-shell-history ()
  "Return the current Yeah shell history as a list (oldest first)."
  (declare (pure t) (side-effect-free t))
  (ring-elements yeah-shell--history))

(defun yeah-shell-history-length ()
  "Return the current number of entries in the history."
  (declare (pure t) (side-effect-free t))
  (ring-length yeah-shell--history))

(defun yeah-shell-history-add (input)
  "Add INPUT to the Yeah shell history."
  (when (and (stringp input)
             (not (string= input "")))
    (ring-insert yeah-shell--history input))
  (ring-length yeah-shell--history))

(defun yeah-shell-history-clear ()
  "Drop all history entries."
  (setq yeah-shell--history (make-ring 200)))

(defun yeah-shell--format-prompt ()
  "Return the prompt text."
  (declare (pure t) (side-effect-free t))
  yeah-shell--prompt)

(defun yeah-shell--ensure-buffer ()
  "Return the Yeah REPL buffer, creating it if necessary."
  (or (get-buffer yeah-shell--buffer-name)
      (with-current-buffer (get-buffer-create yeah-shell--buffer-name)
        (special-mode)
        (setq-local mode-line-format
                    (list "Yeah shell "
                          '(t (:eval (format "%d" (length (yeah-shell-history)))))))
        (current-buffer))))

(defun yeah-shell-open ()
  "Open (or focus) the Yeah REPL buffer."
  (interactive)
  (let ((buf (yeah-shell--ensure-buffer)))
    (pop-to-buffer buf)
    (goto-char (point-max))
    (insert (yeah-shell--format-prompt))
    buf))

(defun yeah-shell-send-input (input)
  "Send INPUT to the agent loop. Stub: echo back and append to history."
  (interactive "sYeah> ")
  (let ((buf (yeah-shell--ensure-buffer)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (goto-char (point-max))
          (insert input "\n")
          (insert (format "[yeah-stub] received: %s\n" input))
          (insert (yeah-shell--format-prompt)))))
    (yeah-shell-history-add input)))

(provide 'yeah-shell)
;;; yeah-shell.el ends here
