;;; yeah-markdown.el --- optional Markdown fontification -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A small adapter for `markdown-mode'.  The target buffer keeps its major
;; mode, text, narrowing and read-only state.  Fontification happens in a
;; temporary buffer and only face properties are copied back.  Without the
;; optional package, the plain-text region is left untouched.

;;; Code:

(require 'font-lock)

(declare-function markdown-mode "markdown-mode")
(defvar markdown-mode-hook nil)
(defvar markdown-hide-markup nil)
(defvar markdown-fontify-code-blocks-natively nil)
(defvar text-mode-hook nil)

(defun yeah-markdown-available-p ()
  "Return non-nil when the optional `markdown-mode' adapter is available."
  (and (or (featurep 'markdown-mode)
           (require 'markdown-mode nil t))
       (fboundp 'markdown-mode)
       t))

(defun yeah-markdown--fontification-runs ()
  "Return face runs in the current temporary fontification buffer.
Each run is (START END PROPERTY VALUE), using the temporary buffer's
positions.  Invisibility, display, keymaps and other properties are not
included."
  (let (runs)
    (dolist (property '(face font-lock-face))
      (let ((position (point-min))
            (end (point-max)))
        (while (< position end)
          (let ((next (or (next-single-property-change position property nil end)
                          end))
                (value (get-text-property position property)))
            (when value
              (push (list position next property value) runs))
            (setq position next)))))
    (nreverse runs)))

(defun yeah-markdown-fontify-region (start end)
  "Fontify the accessible region from START to END with `markdown-mode'.
Return non-nil when the optional adapter ran.  Return nil and retain plain
text when the package is absent, the region is empty, or fontification
fails.  Only `face' and `font-lock-face' properties are copied to the
current buffer; its major mode and non-face text properties are preserved."
  (let ((beginning (min start end))
        (limit (max start end)))
    (when (or (< beginning (point-min))
              (> limit (point-max)))
      (user-error "yeah-markdown: region is outside the accessible buffer"))
    (when (< beginning limit)
      (condition-case nil
          (when (yeah-markdown-available-p)
            (let ((text (buffer-substring-no-properties beginning limit))
                  (target (current-buffer))
                  runs)
              (with-temp-buffer
                (insert text)
                (let ((markdown-mode-hook nil)
                      (text-mode-hook nil)
                      (markdown-hide-markup nil)
                      (markdown-fontify-code-blocks-natively nil))
                  (markdown-mode))
                (font-lock-ensure (point-min) (point-max))
                (setq runs (yeah-markdown--fontification-runs)))
              (let ((inhibit-read-only t))
                (with-silent-modifications
                  (dolist (run runs)
                    (add-text-properties
                     (+ beginning (1- (nth 0 run)))
                     (+ beginning (1- (nth 1 run)))
                     (list (nth 2 run) (nth 3 run))
                     target))))
              t))
        (error nil)))))

(provide 'yeah-markdown)
;;; yeah-markdown.el ends here
